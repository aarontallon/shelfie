// Pushes programados (no disparados por un INSERT, sino por pg_cron en un
// horario fijo): aviso de racha en peligro y resumen semanal de eventos.
//
// Se llama con un body {"job":"streak_reminder"} o {"job":"weekly_digest"} —
// pg_cron hace ambas llamadas por su cuenta con net.http_post, ver las dos
// tareas programadas al final de supabase_schema.sql. Comparte las mismas
// secrets VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY/VAPID_SUBJECT y SB_SECRET_KEY
// (o SUPABASE_SERVICE_ROLE_KEY) que la función send-push.
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const APP_URL = 'https://aarontallon.github.io/shelfie/';

function ok(body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } });
}

// "Hoy"/"ayer" en horario de España — reading_days se guarda con la fecha
// local del propio dispositivo de cada lector (ver todayKey() en el
// cliente), así que esto es una aproximación razonable para la base de
// usuarios actual, no una solución multi-zona horaria exacta.
function madridDateKey(offsetDays: number): string {
  const now = new Date();
  now.setUTCDate(now.getUTCDate() + offsetDays);
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Madrid', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

async function sendToUser(
  admin: ReturnType<typeof createClient>,
  userId: string,
  title: string,
  body: string,
  url: string,
  tag: string
): Promise<{ sent: number; failed: number }> {
  const { data: subs } = await admin.from('push_subscriptions').select('id,endpoint,p256dh,auth').eq('user_id', userId);
  if (!subs || !subs.length) return { sent: 0, failed: 0 };
  const payloadStr = JSON.stringify({ title, body, url, tag });
  const results = await Promise.allSettled(
    subs.map((s) =>
      webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payloadStr).catch(async (err: { statusCode?: number }) => {
        if (err?.statusCode === 404 || err?.statusCode === 410) await admin.from('push_subscriptions').delete().eq('id', s.id);
        throw err;
      })
    )
  );
  return { sent: results.filter((r) => r.status === 'fulfilled').length, failed: results.filter((r) => r.status === 'rejected').length };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });

  try {
    const payload = await req.json().catch(() => ({}));
    const job = payload?.job;

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SB_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY');
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY');
    const vapidSubject = Deno.env.get('VAPID_SUBJECT');
    if (!serviceRoleKey) return ok({ error: 'missing service role key' });
    if (!vapidPublicKey || !vapidPrivateKey || !vapidSubject) return ok({ error: 'VAPID secrets not configured' });
    webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);
    const admin = createClient(supabaseUrl, serviceRoleKey);

    if (job === 'streak_reminder') {
      const today = madridDateKey(0);
      const yesterday = madridDateKey(-1);
      // .contains() no serializa bien un array plano de JS contra una columna
      // jsonb (produce sintaxis inválida en el filtro) — más simple y fiable
      // traer todos los perfiles y comprobar el array de racha a mano aquí,
      // sin depender de ningún operador especial de jsonb en la consulta.
      const { data: candidates, error } = await admin.from('profiles').select('id,reading_days');
      if (error) return ok({ error: error.message });
      const targets = (candidates || []).filter((p) => {
        const days: string[] = Array.isArray(p.reading_days) ? p.reading_days : [];
        return days.includes(yesterday) && !days.includes(today);
      });
      let sent = 0, failed = 0;
      for (const p of targets) {
        const r = await sendToUser(admin, p.id, '🔥 No pierdas tu racha', 'Aún no has marcado tu lectura de hoy — quedan pocas horas.', new URL('./index.html', APP_URL).href, 'streak-reminder');
        sent += r.sent; failed += r.failed;
      }
      return ok({ ok: true, job, candidates: targets.length, sent, failed });
    }

    if (job === 'weekly_digest') {
      const now = new Date();
      const in7days = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
      const { data: events, error: evErr } = await admin.from('events').select('id,city,starts_at').gte('starts_at', now.toISOString()).lte('starts_at', in7days.toISOString());
      if (evErr) return ok({ error: evErr.message });
      if (!events || !events.length) return ok({ ok: true, job, skipped: 'no upcoming events in the next 7 days' });

      const { data: profilesWithCity, error: profErr } = await admin.from('profiles').select('id,city').not('city', 'is', null).neq('city', '');
      if (profErr) return ok({ error: profErr.message });

      let sent = 0, failed = 0, notified = 0;
      for (const p of profilesWithCity || []) {
        const cityLower = (p.city || '').trim().toLowerCase();
        if (!cityLower) continue;
        const matches = events.filter((e) => (e.city || '').trim().toLowerCase() === cityLower);
        if (!matches.length) continue;
        const { data: mySignups } = await admin.from('event_signups').select('event_id').eq('user_id', p.id).in('event_id', matches.map((e) => e.id));
        const signedUpIds = new Set((mySignups || []).map((s) => s.event_id));
        const newOnes = matches.filter((e) => !signedUpIds.has(e.id));
        if (!newOnes.length) continue;
        notified++;
        const r = await sendToUser(
          admin,
          p.id,
          '📅 Eventos esta semana',
          `${newOnes.length} evento${newOnes.length === 1 ? '' : 's'} de lectura en ${p.city} esta semana — échales un ojo.`,
          new URL('./index.html?push=events', APP_URL).href,
          'weekly-digest'
        );
        sent += r.sent; failed += r.failed;
      }
      return ok({ ok: true, job, upcomingEvents: events.length, notifiedUsers: notified, sent, failed });
    }

    return ok({ skipped: `unknown job "${job}"` });
  } catch (e) {
    console.error('send-scheduled-push failed:', e);
    return ok({ error: 'internal error', detail: e instanceof Error ? e.message : String(e) });
  }
});
