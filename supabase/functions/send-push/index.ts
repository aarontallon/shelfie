// Envía una notificación push (Web Push, RFC 8291) cuando se crea una fila
// en public.notifications (seguidor nuevo, solicitud, me gusta, comentario,
// reacción...) o en public.messages (mensaje directo nuevo).
//
// Se dispara desde DOS Database Webhooks de Supabase (Database → Webhooks),
// uno por cada tabla, ambos apuntando a esta misma función: uno en INSERT de
// public.notifications, otro en INSERT de public.messages. La propia base
// de datos avisa a la función, no hace falta tocar nada del cliente aquí.
//
// Requiere las secrets VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY y VAPID_SUBJECT
// (Edge Functions → Secrets) — genera el par de claves con
// `npx web-push generate-vapid-keys` o la librería `web-push`, una sola vez,
// y VAPID_SUBJECT es un `mailto:tu@email.com` cualquiera (Google/Apple lo
// piden para poder contactarte si abusas del servicio push, no se muestra
// al usuario final).
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const APP_URL = 'https://aarontallon.github.io/shelfie/';

const NOTIF_MESSAGES: Record<string, (name: string) => { title: string; body: string }> = {
  follow: (name) => ({ title: 'Nuevo seguidor', body: `${name} ha empezado a seguirte` }),
  follow_request: (name) => ({ title: 'Solicitud de seguimiento', body: `${name} quiere seguirte` }),
  follow_accepted: (name) => ({ title: 'Solicitud aceptada', body: `${name} ha aceptado tu solicitud de seguimiento` }),
  like: (name) => ({ title: 'Nuevo me gusta', body: `A ${name} le ha gustado tu publicación` }),
  comment: (name) => ({ title: 'Nuevo comentario', body: `${name} ha comentado tu publicación` }),
  comment_like: (name) => ({ title: 'Nuevo me gusta', body: `A ${name} le ha gustado tu comentario` }),
  reaction: (name) => ({ title: 'Nueva reacción', body: `${name} ha reaccionado a tu publicación` }),
};

function ok(body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });

  try {
    const payload = await req.json();
    if (payload?.type !== 'INSERT') return ok({ skipped: 'not an insert' });

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    // SUPABASE_SERVICE_ROLE_KEY es la clave "legacy" que Supabase inyecta sola —
    // en proyectos ya migrados al sistema nuevo de API keys puede venir vacía,
    // así que se admite SB_SECRET_KEY (secret propia, con la clave "secret" /
    // "service_role" copiada a mano de Project Settings → API Keys) como
    // alternativa explícita.
    const serviceRoleKey = Deno.env.get('SB_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY');
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY');
    const vapidSubject = Deno.env.get('VAPID_SUBJECT');
    if (!serviceRoleKey) {
      console.error('No service-role key available — set the SB_SECRET_KEY secret.');
      return ok({ error: 'missing service role key' });
    }
    if (!vapidPublicKey || !vapidPrivateKey || !vapidSubject) {
      console.error('VAPID secrets not configured — skipping push send.');
      return ok({ error: 'VAPID secrets not configured' });
    }
    webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);

    const admin = createClient(supabaseUrl, serviceRoleKey);

    let recipientId: string;
    let title: string, body: string, url: string, tag: string | undefined;

    if (payload.table === 'notifications') {
      const notif = payload.record;
      const build = NOTIF_MESSAGES[notif?.type];
      if (!notif || !build) return ok({ skipped: `no push template for type "${notif?.type}"` });

      const { data: actor } = await admin.from('profiles').select('name,username').eq('id', notif.actor_id).maybeSingle();
      const actorName = actor?.name || actor?.username || 'Alguien';
      recipientId = notif.user_id;
      ({ title, body } = build(actorName));
      url = new URL('./index.html?push=notifications', APP_URL).href;
      tag = `notif-${notif.type}`;
    } else if (payload.table === 'messages') {
      const msg = payload.record;
      if (!msg) return ok({ skipped: 'no message record' });

      const { data: conv } = await admin.from('conversations').select('user1_id,user2_id').eq('id', msg.conversation_id).maybeSingle();
      if (!conv) return ok({ skipped: 'conversation not found' });
      recipientId = conv.user1_id === msg.sender_id ? conv.user2_id : conv.user1_id;
      if (recipientId === msg.sender_id) return ok({ skipped: 'sender is recipient' });

      const { data: sender } = await admin.from('profiles').select('name,username').eq('id', msg.sender_id).maybeSingle();
      const senderName = sender?.name || sender?.username || 'Alguien';
      title = senderName;
      body = String(msg.text || '').slice(0, 200);
      url = new URL(`./index.html?push=chat&user=${msg.sender_id}`, APP_URL).href;
      tag = `chat-${msg.conversation_id}`;
    } else {
      return ok({ skipped: `unhandled table "${payload.table}"` });
    }

    const { data: subs } = await admin.from('push_subscriptions').select('id,endpoint,p256dh,auth').eq('user_id', recipientId);
    if (!subs || !subs.length) return ok({ skipped: 'recipient has no push subscriptions' });

    const payloadStr = JSON.stringify({ title, body, url, tag });
    const results = await Promise.allSettled(
      subs.map((s) =>
        webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payloadStr)
          .catch(async (err: { statusCode?: number }) => {
            if (err?.statusCode === 404 || err?.statusCode === 410) {
              await admin.from('push_subscriptions').delete().eq('id', s.id);
            }
            throw err;
          })
      )
    );

    return ok({ ok: true, sent: results.filter((r) => r.status === 'fulfilled').length, failed: results.filter((r) => r.status === 'rejected').length });
  } catch (e) {
    console.error('send-push failed:', e);
    return ok({ error: 'internal error', detail: e instanceof Error ? e.message : String(e) });
  }
});
