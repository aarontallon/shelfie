// Envía un email cuando se crea una notificación (seguidor nuevo, solicitud
// de seguimiento, solicitud aceptada) — si la persona destinataria tiene
// activadas las notificaciones por email.
//
// Se dispara desde un Database Webhook de Supabase (Database → Webhooks),
// configurado para llamar a esta función en cada INSERT de public.notifications.
// No hace falta tocar nada del cliente para esto: la propia base de datos
// avisa a la función.
//
// Usa Resend (resend.com) para el envío — API sencilla, tiene plan gratis.
// Requiere la secret RESEND_API_KEY (Edge Functions → Secrets) y un dominio
// de envío verificado en Resend (o usar su dominio de pruebas mientras se
// verifica el propio).
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// "notificaciones@resend.dev" no es una dirección válida del dominio de
// pruebas de Resend (solo aceptan enviar desde onboarding@resend.dev sin
// verificar dominio propio) — con la anterior, el 100% de los envíos fallaba
// en silencio (resendRes.ok siempre false). Cambia esto por tu dominio
// verificado en Resend en cuanto lo tengas.
const FROM_EMAIL = 'Shelfie <onboarding@resend.dev>';
const APP_URL = 'https://aarontallon.github.io/shelfie/';

// actorName sale del nombre/username del perfil de otra persona — texto
// controlado por el usuario que se inserta tal cual en el HTML del email.
// Sin escapar, alguien podía poner "<img src=x onerror=...>" o un enlace de
// phishing como su nombre y que le llegara renderizado al destinatario.
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const MESSAGES: Record<string, (actorName: string) => { subject: string; html: string }> = {
  follow: (name) => ({
    subject: `${name} ha empezado a seguirte en Shelfie`,
    html: `<p><strong>${escapeHtml(name)}</strong> ha empezado a seguirte en Shelfie.</p><p><a href="${APP_URL}">Ver en Shelfie →</a></p>`,
  }),
  follow_request: (name) => ({
    subject: `${name} quiere seguirte en Shelfie`,
    html: `<p><strong>${escapeHtml(name)}</strong> quiere seguirte en Shelfie. Puedes aceptar o rechazar la solicitud desde tus notificaciones.</p><p><a href="${APP_URL}">Ver en Shelfie →</a></p>`,
  }),
  follow_accepted: (name) => ({
    subject: `${name} ha aceptado tu solicitud de seguimiento`,
    html: `<p><strong>${escapeHtml(name)}</strong> ha aceptado tu solicitud de seguimiento en Shelfie. Ya puedes ver su shelfie.</p><p><a href="${APP_URL}">Ver en Shelfie →</a></p>`,
  }),
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });

  try {
    const payload = await req.json();
    const notif = payload?.record;
    if (!notif || payload?.table !== 'notifications' || payload?.type !== 'INSERT') {
      return new Response(JSON.stringify({ skipped: 'not a notification insert' }), {
        status: 200,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const buildMessage = MESSAGES[notif.type];
    if (!buildMessage) {
      return new Response(JSON.stringify({ skipped: `no email template for type "${notif.type}"` }), {
        status: 200,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    // SUPABASE_SERVICE_ROLE_KEY puede venir vacía en proyectos migrados al
    // nuevo sistema de claves de Supabase — igual que en send-push y
    // send-scheduled-push, se prueba primero la clave nombrada nueva.
    const serviceRoleKey = Deno.env.get('SB_SECRET_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const resendApiKey = Deno.env.get('RESEND_API_KEY');
    if (!serviceRoleKey) {
      console.error('No service role key configured (SB_SECRET_KEY / SUPABASE_SERVICE_ROLE_KEY) — skipping email send.');
      return new Response(JSON.stringify({ error: 'missing service role key' }), {
        status: 200,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }
    if (!resendApiKey) {
      console.error('RESEND_API_KEY secret is not set — skipping email send.');
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY not configured' }), {
        status: 200,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: recipientProfile } = await adminClient
      .from('profiles')
      .select('email_notifications')
      .eq('id', notif.user_id)
      .maybeSingle();
    if (recipientProfile?.email_notifications === false) {
      return new Response(JSON.stringify({ skipped: 'recipient has email notifications off' }), {
        status: 200,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const { data: actorProfile } = await adminClient
      .from('profiles')
      .select('name,username')
      .eq('id', notif.actor_id)
      .maybeSingle();
    const actorName = actorProfile?.name || actorProfile?.username || 'Alguien';

    const { data: recipientUser, error: userErr } = await adminClient.auth.admin.getUserById(notif.user_id);
    if (userErr || !recipientUser?.user?.email) {
      return new Response(JSON.stringify({ skipped: 'no recipient email found' }), {
        status: 200,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const { subject, html } = buildMessage(actorName);

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: FROM_EMAIL, to: recipientUser.user.email, subject, html }),
    });
    if (!resendRes.ok) {
      const errText = await resendRes.text();
      console.error('Resend send failed:', resendRes.status, errText);
      return new Response(JSON.stringify({ error: 'email send failed', detail: errText }), {
        status: 200, // no reintentar el webhook indefinidamente por un fallo del proveedor
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('send-notification-email failed:', e);
    return new Response(JSON.stringify({ error: 'internal error' }), {
      status: 200,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }
});
