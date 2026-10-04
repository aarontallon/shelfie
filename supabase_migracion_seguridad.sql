-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN (revisión de seguridad) — segura de volver a ejecutar.
--
-- 1) create_notification era "security definer" y, por defecto, Postgres da
--    EXECUTE a PUBLIC: cualquier usuario podía llamarla por RPC
--    (supa.rpc('create_notification', {...})) con el actor que quisiera y
--    suplantar notificaciones (y por tanto pushes) a cualquiera, anulando el
--    cierre de notifications_insert de arriba. Los triggers y
--    accept_follow_request la llaman como dueño, así que no necesitan EXECUTE.
-- 2) Las funciones security definer sin search_path fijo son vulnerables a
--    secuestro de funciones/tablas por un esquema en el search_path del
--    llamante. Se fija a public.
-- 3) push_subscriptions_update tenía "using (true)": un UPDATE sin filtro
--    permitía a cualquier usuario reasignarse TODAS las suscripciones push
--    (el endpoint no hacía falta conocerlo). Ahora la reclamación de un
--    endpoint (dispositivo compartido) pasa por una función que exige
--    conocer el endpoint, y la policy directa solo toca filas propias.
-- ════════════════════════════════════════════════

revoke execute on function public.create_notification(uuid, uuid, text) from public, anon, authenticated;

alter function public.handle_new_user() set search_path = public;
alter function public.handle_new_block() set search_path = public;
alter function public.prevent_follow_if_blocked() set search_path = public;
alter function public.prevent_bad_follow_request() set search_path = public;
alter function public.accept_follow_request(uuid) set search_path = public;
alter function public.handle_new_message() set search_path = public;
alter function public.enforce_event_capacity() set search_path = public;
alter function public.protect_message_immutable_fields() set search_path = public;
alter function public.protect_conversation_immutable_fields() set search_path = public;
alter function public.create_notification(uuid, uuid, text) set search_path = public;
alter function public.notify_on_follow() set search_path = public;
alter function public.notify_on_follow_request() set search_path = public;
alter function public.notify_on_like() set search_path = public;
alter function public.notify_on_comment() set search_path = public;
alter function public.notify_on_comment_like() set search_path = public;
alter function public.notify_on_post_reaction() set search_path = public;
alter function public.notify_on_event_signup() set search_path = public;

drop policy if exists "push_subscriptions_update" on public.push_subscriptions;
create policy "push_subscriptions_update" on public.push_subscriptions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.claim_push_subscription(
  p_endpoint text, p_p256dh text, p_auth text, p_user_agent text
) returns void as $$
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, p_user_agent)
  on conflict (endpoint) do update
    set user_id = auth.uid(), p256dh = excluded.p256dh,
        auth = excluded.auth, user_agent = excluded.user_agent;
end;
$$ language plpgsql security definer set search_path = public;
revoke execute on function public.claim_push_subscription(text, text, text, text) from public, anon;
grant execute on function public.claim_push_subscription(text, text, text, text) to authenticated;

-- El username acaba en atributos onclick de otras personas; el cliente ya lo
-- sanea, pero nada impedía saltarse el cliente por la API. "not valid" no
-- revalida filas antiguas (solo las nuevas/actualizadas).
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username is null or username ~ '^[a-z0-9_]+$') not valid;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN 2 (avisos del Security Advisor de Supabase) — segura de volver a ejecutar.
--
-- 4) Las funciones SECURITY DEFINER de trigger (notify_on_*, handle_new_*,
--    prevent_*, enforce_event_capacity...) quedaban ejecutables por RPC para
--    anon/authenticated ("Public Can Execute SECURITY DEFINER Function").
--    Solo las dispara Postgres: el permiso EXECUTE se comprueba al CREAR el
--    trigger, no al dispararlo, así que revocarlo no rompe nada.
-- 5) accept_follow_request sí se llama desde el cliente, pero solo con sesión:
--    se quita a anon/public y se deja a authenticated.
-- 6) El bucket público "avatars" tenía un SELECT amplio en storage.objects que
--    permitía LISTAR todos los ficheros del bucket. Las URLs públicas de las
--    imágenes no necesitan esa policy. Se limita al propio usuario (necesario
--    para que upload con upsert, update y delete funcionen sobre sus ficheros).
-- ════════════════════════════════════════════════

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

revoke execute on function public.accept_follow_request(uuid) from public, anon;
grant execute on function public.accept_follow_request(uuid) to authenticated;

drop policy if exists "avatar_public_read" on storage.objects;
drop policy if exists "avatar_owner_read" on storage.objects;
create policy "avatar_owner_read" on storage.objects for select using (
  bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
);
