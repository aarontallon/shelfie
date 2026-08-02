// Elimina la cuenta del usuario autenticado, sin excepciones.
//
// Por qué esto no se puede hacer desde el cliente: borrar un usuario de
// auth.users requiere la API admin de Supabase, que solo acepta la service
// role key — una clave que nunca debe viajar al navegador (se saltaría
// Row Level Security por completo). Esta función vive en el servidor
// precisamente para ser la única que la usa.
//
// El borrado de auth.users se propaga en cascada a profiles y de ahí a
// todo lo demás (user_books, posts, comments, likes, friends,
// notifications, event_signups...) gracias a los "on delete cascade" del
// esquema — así que no hace falta borrar tabla por tabla aquí. Storage no
// sigue claves foráneas, así que el avatar sí se borra a mano.
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Falta la cabecera de autorización.' }), {
        status: 401,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // Cliente con la sesión del usuario que llama, solo para confirmar quién es
    // — nunca para el borrado en sí.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await callerClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'No se pudo verificar la sesión.' }), {
        status: 401,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Borra el avatar del usuario en Storage (best-effort — un fallo aquí no debe
    // impedir el borrado real de la cuenta).
    try {
      const { data: files } = await adminClient.storage.from('avatars').list(user.id);
      if (files?.length) {
        await adminClient.storage.from('avatars').remove(files.map((f) => `${user.id}/${f.name}`));
      }
    } catch (storageErr) {
      console.error('no se pudieron borrar los ficheros del avatar (se continúa igualmente):', storageErr);
    }

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);
    if (deleteError) {
      return new Response(JSON.stringify({ error: deleteError.message }), {
        status: 500,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('delete-account failed:', e);
    return new Response(JSON.stringify({ error: 'Error interno al eliminar la cuenta.' }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }
});
