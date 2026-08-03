-- ════════════════════════════════════════════════
-- SHELFIE — Schema Supabase
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ════════════════════════════════════════════════

-- ── Perfiles de usuario ──
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text not null default '',
  username text unique,
  bio text default 'Lector apasionado 📚',
  city text default '',
  photo text,
  public boolean default true,
  reading_days jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);

-- ── Libros en el shelfie del usuario ──
create table if not exists public.user_books (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  local_id text,                    -- id local del libro (b1234...)
  title text not null,
  author text not null,
  cover text,
  color text,
  status text check (status in ('leidos','leyendo','quiero','dnf')) not null,
  stars int check (stars between 0 and 5) default 0,
  review text default '',
  pages int,
  cur_page int default 0,
  year text default '',
  genres text[] default '{}',
  read_history jsonb default '[]',
  finished_at text,
  is_favorite boolean default false,
  rank_pos int,
  publisher text,
  isbn text,
  edition_year int,
  ol_key text,
  author_ol_key text,
  synopsis text,
  added_at timestamptz default now()
);

-- ── Publicaciones del feed ──
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  type text not null,
  text text default '',
  book_title text,
  book_author text,
  book_cover text,
  book_color text,
  rating int,
  spoiler boolean default false,
  edited_at timestamptz,
  created_at timestamptz default now(),
  extra jsonb default '{}'::jsonb  -- title/isReview/retoName/shelfBooks/quote/note/page/chapter/thread/character/subject
);

-- ── Comentarios ──
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  text text not null,
  created_at timestamptz default now()
);

-- ── Likes ──
create table if not exists public.likes (
  post_id uuid references public.posts(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  primary key (post_id, user_id)
);

-- ── Amigos ──
create table if not exists public.friendships (
  user_id uuid references public.profiles(id) on delete cascade,
  friend_id uuid references public.profiles(id) on delete cascade,
  status text default 'accepted',
  created_at timestamptz default now(),
  primary key (user_id, friend_id)
);

-- ── Notificaciones (p.ej. "X te ha empezado a seguir") ──
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,   -- quién la recibe
  actor_id uuid references public.profiles(id) on delete cascade not null,  -- quién la genera
  type text not null default 'follow',
  read boolean default false,
  created_at timestamptz default now()
);

-- ════ RLS (Row Level Security) ════
alter table public.profiles enable row level security;
alter table public.user_books enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.likes enable row level security;
alter table public.friendships enable row level security;
alter table public.notifications enable row level security;

-- Profiles
create policy "profiles_select" on public.profiles for select using (true);
create policy "profiles_insert" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update" on public.profiles for update using (auth.uid() = id);

-- User books
create policy "user_books_select" on public.user_books for select using (true);
create policy "user_books_insert" on public.user_books for insert with check (auth.uid() = user_id);
create policy "user_books_update" on public.user_books for update using (auth.uid() = user_id);
create policy "user_books_delete" on public.user_books for delete using (auth.uid() = user_id);

-- Posts
create policy "posts_select" on public.posts for select using (true);
create policy "posts_insert" on public.posts for insert with check (auth.uid() = user_id);
create policy "posts_update" on public.posts for update using (auth.uid() = user_id);
create policy "posts_delete" on public.posts for delete using (auth.uid() = user_id);

-- Comments
create policy "comments_select" on public.comments for select using (true);
create policy "comments_insert" on public.comments for insert with check (auth.uid() = user_id);
create policy "comments_delete" on public.comments for delete using (auth.uid() = user_id);

-- Likes
create policy "likes_select" on public.likes for select using (true);
create policy "likes_insert" on public.likes for insert with check (auth.uid() = user_id);
create policy "likes_delete" on public.likes for delete using (auth.uid() = user_id);

-- Friendships (public read: follower/following counts are shown on public profiles, like Instagram)
create policy "friendships_select" on public.friendships for select using (true);
create policy "friendships_insert" on public.friendships for insert with check (auth.uid() = user_id);
create policy "friendships_delete" on public.friendships for delete using (auth.uid() = user_id or auth.uid() = friend_id);

-- Notifications
create policy "notifications_select" on public.notifications for select using (auth.uid() = user_id);
create policy "notifications_insert" on public.notifications for insert with check (auth.uid() = actor_id);
create policy "notifications_update" on public.notifications for update using (auth.uid() = user_id);
create policy "notifications_delete" on public.notifications for delete using (auth.uid() = user_id);

-- Habilita Realtime en notifications para que la campanita se actualice al instante.
-- Si ya la tienes activada (o esto falla porque ya es miembro de la publicación), ignora el error.
alter publication supabase_realtime add table public.notifications;

-- ════ Trigger: crear perfil automáticamente al registrarse ════
create or replace function public.handle_new_user()
returns trigger as $$
declare
  base_username text;
begin
  base_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    '[^a-z0-9]', '', 'g'
  ));
  insert into public.profiles (id, name, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    base_username || '_reads'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: fotos de perfil reales + ver perfiles de otros usuarios
-- Si ya habías ejecutado el schema anterior, solo hace falta correr esto.
-- Es seguro volver a ejecutarlo (usa "if exists" / "on conflict").
-- ════════════════════════════════════════════════

-- Antes solo podías leer tus propias filas de "friendships". Para poder mostrar
-- cuánta gente sigue/es seguida por OTRO usuario en su perfil público (estilo
-- Instagram), esto tiene que ser de lectura pública — igual que ya lo son los
-- libros y las publicaciones de cualquier usuario.
drop policy if exists "friendships_select" on public.friendships;
create policy "friendships_select" on public.friendships for select using (true);

-- Bucket público para fotos de perfil. Antes se guardaban como base64 directamente
-- en la columna `photo`, lo que fallaba en silencio con fotos de tamaño normal
-- (superan el límite de payload de la API). Ahora se sube el archivo real aquí y
-- solo se guarda su URL pública en `profiles.photo`.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatar_public_read" on storage.objects;
create policy "avatar_public_read" on storage.objects for select using (bucket_id = 'avatars');

-- Any logged-in user may write into the avatars bucket (simpler than matching the
-- uploaded path's folder against auth.uid(), which is easy to get subtly wrong and
-- fails closed with "new row violates row-level security policy" if it doesn't
-- match exactly). This is safe: uploading a file here doesn't change anyone's
-- displayed photo — only that user's own profiles.photo row does, and THAT update
-- is still locked down by profiles_update (auth.uid() = id).
drop policy if exists "avatar_owner_write" on storage.objects;
create policy "avatar_owner_write" on storage.objects for insert with check (bucket_id = 'avatars' and auth.role() = 'authenticated');

drop policy if exists "avatar_owner_update" on storage.objects;
create policy "avatar_owner_update" on storage.objects for update using (bucket_id = 'avatars' and auth.role() = 'authenticated');

drop policy if exists "avatar_owner_delete" on storage.objects;
create policy "avatar_owner_delete" on storage.objects for delete using (bucket_id = 'avatars' and auth.role() = 'authenticated');

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: publicaciones completas de amigos en el feed
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Antes solo se guardaban text/book/rating/spoiler de cada publicación —
-- citas, marginalia, historias con personajes, shelfie-posts con varios
-- libros, etc. perdían esos datos al recargar la página. Este campo guarda
-- el resto de la publicación tal cual, sin necesitar una columna por campo.
alter table public.posts add column if not exists extra jsonb default '{}'::jsonb;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: guardar Retos y Clubs (antes no se guardaban en ningún sitio)
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Retos y Clubs son, tal y como están construidos hoy, espacios PERSONALES:
-- cuando creas o te unes a uno, los "miembros"/"participantes" que ves (aparte
-- de ti) son contenido de ejemplo, no cuentas reales — invitar a alguien con
-- @usuario solo muestra un aviso de "invitación enviada" y no conecta con
-- ningún otro usuario real. Por eso cada fila pertenece a un solo usuario y
-- guarda toda la estructura (miembros, debates, foro, anuncios, retos del
-- club...) tal cual, en una columna jsonb — el mismo patrón que ya usan
-- posts.extra y user_books.read_history, en vez de inventar un esquema
-- relacional para una función que no es realmente multiusuario todavía.
create table if not exists public.retos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz default now()
);

create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz default now()
);

alter table public.retos enable row level security;
alter table public.clubs enable row level security;

drop policy if exists "retos_select" on public.retos;
create policy "retos_select" on public.retos for select using (auth.uid()=user_id);
drop policy if exists "retos_insert" on public.retos;
create policy "retos_insert" on public.retos for insert with check (auth.uid()=user_id);
drop policy if exists "retos_update" on public.retos;
create policy "retos_update" on public.retos for update using (auth.uid()=user_id);
drop policy if exists "retos_delete" on public.retos;
create policy "retos_delete" on public.retos for delete using (auth.uid()=user_id);

drop policy if exists "clubs_select" on public.clubs;
create policy "clubs_select" on public.clubs for select using (auth.uid()=user_id);
drop policy if exists "clubs_insert" on public.clubs;
create policy "clubs_insert" on public.clubs for insert with check (auth.uid()=user_id);
drop policy if exists "clubs_update" on public.clubs;
create policy "clubs_update" on public.clubs for update using (auth.uid()=user_id);
drop policy if exists "clubs_delete" on public.clubs;
create policy "clubs_delete" on public.clubs for delete using (auth.uid()=user_id);

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: likes en comentarios + reacciones con emoji en publicaciones
-- + tiempo real para comentarios/likes/reacciones (antes solo se veían al recargar)
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

create table if not exists public.comment_likes (
  comment_id uuid references public.comments(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  primary key (comment_id, user_id)
);

-- One reaction per person per post (LinkedIn-style — picking a different emoji
-- REPLACES your previous one, it doesn't add a second reaction), so the primary
-- key is (post_id, user_id), not (post_id, user_id, emoji). post_id is `text`,
-- not `uuid`, on purpose — posts.id itself is `text` in this project (an
-- earlier iteration of this schema, before ids were standardized on uuid;
-- likes.post_id/comments.post_id are `text` for the same reason), so a `uuid`
-- foreign key here fails at creation time with "incompatible types".
drop table if exists public.post_reactions;
create table public.post_reactions (
  post_id text references public.posts(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

alter table public.comment_likes enable row level security;
alter table public.post_reactions enable row level security;

drop policy if exists "comment_likes_select" on public.comment_likes;
create policy "comment_likes_select" on public.comment_likes for select using (true);
drop policy if exists "comment_likes_insert" on public.comment_likes;
create policy "comment_likes_insert" on public.comment_likes for insert with check (auth.uid()=user_id);
drop policy if exists "comment_likes_delete" on public.comment_likes;
create policy "comment_likes_delete" on public.comment_likes for delete using (auth.uid()=user_id);

drop policy if exists "post_reactions_select" on public.post_reactions;
create policy "post_reactions_select" on public.post_reactions for select using (true);
drop policy if exists "post_reactions_insert" on public.post_reactions;
create policy "post_reactions_insert" on public.post_reactions for insert with check (auth.uid()=user_id);
drop policy if exists "post_reactions_update" on public.post_reactions;
create policy "post_reactions_update" on public.post_reactions for update using (auth.uid()=user_id);
drop policy if exists "post_reactions_delete" on public.post_reactions;
create policy "post_reactions_delete" on public.post_reactions for delete using (auth.uid()=user_id);

-- Realtime: para que likes/comentarios/reacciones de otras personas aparezcan
-- al instante sin recargar la página. Envuelto en bloques que ignoran el aviso
-- de "ya es miembro de la publicación" para poder volver a ejecutar esto sin
-- fallar si alguna de estas ya se había añadido en un intento anterior.
do $$ begin
  alter publication supabase_realtime add table public.posts;
exception when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.comments;
exception when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.likes;
exception when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.comment_likes;
exception when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.post_reactions;
exception when others then null; end $$;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: clubs buscables/descubribles + nickname único
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- clubs_select era "solo el dueño" — imposible de buscar o de mostrar en
-- Descubrir a nadie más. Cada club sigue siendo una fila por usuario (ver el
-- comentario más arriba sobre por qué), pero ahora cualquiera puede LEER
-- cualquier club — igual que ya pasa con posts/user_books — para poder
-- buscarlo por nombre/nickname y ver cuántas copias reales existen (= cuánta
-- gente se ha unido). Insert/update/delete se quedan como estaban: solo el
-- dueño de esa fila.
drop policy if exists "clubs_select" on public.clubs;
create policy "clubs_select" on public.clubs for select using (true);

-- Nickname único a nivel de base de datos, no solo comprobado en la app — dos
-- personas creando el mismo nickname a la vez no deberían poder colarse las
-- dos. El nickname vive dentro del jsonb `data`, así que es un índice único
-- sobre esa expresión en vez de una columna propia.
create unique index if not exists clubs_nickname_unique on public.clubs (lower(data->>'nickname')) where data->>'nickname' is not null;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: guarda en qué hueco de la estantería está cada libro
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- La vista "shelf" reparte los libros de cada estado (leídos, quiero leer...) en
-- 3 huecos reales por balda, y se puede arrastrar cualquier libro a cualquier
-- hueco con sitio. Antes esa colocación solo vivía en memoria y se perdía al
-- recargar la página — ahora se guarda por libro, igual que rank_pos para el
-- Top 10 de favoritos.
alter table public.user_books add column if not exists shelf_level integer;
alter table public.user_books add column if not exists shelf_col integer;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: distingue una colocación arrastrada a mano de una colocación
-- automática (la que hace el propio render para rellenar huecos por ancho real).
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Antes shelf_level/shelf_col se guardaban igual estuviera el libro arrastrado
-- a mano o solo colocado automáticamente al renderizar — eso "congelaba" la
-- colocación automática de la primera vez (con el ancho que hubiera entonces)
-- para siempre, dejando huecos a medio llenar y añadiendo baldas nuevas de más.
-- Ahora solo un arrastre real marca shelf_pinned=true; sin eso, cada libro se
-- recoloca fresco en cada render según el ancho real disponible.
alter table public.user_books add column if not exists shelf_pinned boolean default false;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: orden público del shelfie, elegido por su dueño
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- El dueño del perfil elige cómo se ordena su shelfie para quien lo visite
-- (recientes/título/autor/valoración/su propio orden manual) — un valor por
-- perfil, no por visitante.
alter table public.profiles add column if not exists shelf_public_sort text;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: tema visual de la estantería (fondo + baldas) — provisional
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Función experimental pedida como "provisional" — si no cuaja, esta columna
-- se puede dejar sin usar sin más (no rompe nada quitarla del cliente).
alter table public.profiles add column if not exists shelf_theme text;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: vista pública del shelfie (estantería/cuadrícula/lista)
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Misma idea que shelf_public_sort: el dueño del perfil elige qué vista se
-- muestra en "Mi shelfie" y "Tu shelfie", y es la que ve cualquier visitante.
-- Un solo valor persistido, cambiable desde cualquiera de los dos toggles.
alter table public.profiles add column if not exists shelf_public_view text;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: Eventos (locales/negocios que organizan eventos de lectura)
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Espacio totalmente aparte del de los lectores: un local/librería/biblioteca
-- se registra como "organizador" (no como lector), publica sus eventos y ve
-- quién se ha apuntado. Los lectores, desde su Shelfie normal, ven en
-- "Eventos" los que caen en su ciudad y pueden apuntarse.
--
-- Organizadores y lectores comparten auth.users (mismo sistema de login de
-- Supabase, con contraseñas de verdad) pero jamás la misma fila de datos:
-- el trigger de más abajo mira `raw_user_meta_data->>'account_type'` en el
-- momento del alta y decide si crear una fila en `organizers` o en
-- `profiles` — nunca ambas para la misma cuenta.

create table if not exists public.organizers (
  id uuid primary key references auth.users(id) on delete cascade,
  venue_name text not null default '',
  city text not null default '',
  description text not null default '',
  contact_email text not null default '',
  created_at timestamptz not null default now()
);
alter table public.organizers enable row level security;
drop policy if exists "organizers_select_own" on public.organizers;
create policy "organizers_select_own" on public.organizers for select using (auth.uid() = id);
drop policy if exists "organizers_update_own" on public.organizers;
create policy "organizers_update_own" on public.organizers for update using (auth.uid() = id);

-- Eventos: legibles por cualquiera (lectores logueados o no, para que la
-- landing pueda enseñarlos si algún día hace falta) — solo el organizador
-- dueño puede crear/editar/borrar los suyos. venue_name/city van duplicados
-- aquí (copiados del organizador al crear el evento) para que un lector
-- pueda ver esos datos sin necesitar acceso de lectura a `organizers`, que
-- se queda privada.
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references public.organizers(id) on delete cascade,
  venue_name text not null default '',
  title text not null,
  description text not null default '',
  event_type text not null default 'otro',
  city text not null default '',
  address text not null default '',
  starts_at timestamptz not null,
  capacity int,
  created_at timestamptz not null default now()
);
alter table public.events enable row level security;
drop policy if exists "events_select_all" on public.events;
create policy "events_select_all" on public.events for select using (true);
drop policy if exists "events_insert_own" on public.events;
create policy "events_insert_own" on public.events for insert with check (auth.uid() = organizer_id);
drop policy if exists "events_update_own" on public.events;
create policy "events_update_own" on public.events for update using (auth.uid() = organizer_id);
drop policy if exists "events_delete_own" on public.events;
create policy "events_delete_own" on public.events for delete using (auth.uid() = organizer_id);

-- Inscripciones: cada lector ve/crea/borra la suya; el organizador del
-- evento ve todas las de sus propios eventos (para poder contactar a quien
-- se ha apuntado). name/username van duplicados aquí (capturados del lector
-- en el momento de apuntarse) para que el organizador tenga una lista de
-- asistentes legible sin depender de una policy de lectura sobre profiles.
create table if not exists public.event_signups (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null default '',
  username text not null default '',
  created_at timestamptz not null default now(),
  unique(event_id, user_id)
);
alter table public.event_signups enable row level security;
drop policy if exists "event_signups_select_own" on public.event_signups;
create policy "event_signups_select_own" on public.event_signups for select using (auth.uid() = user_id);
drop policy if exists "event_signups_select_organizer" on public.event_signups;
create policy "event_signups_select_organizer" on public.event_signups for select using (
  exists (select 1 from public.events e where e.id = event_signups.event_id and e.organizer_id = auth.uid())
);
drop policy if exists "event_signups_insert_own" on public.event_signups;
create policy "event_signups_insert_own" on public.event_signups for insert with check (auth.uid() = user_id);
drop policy if exists "event_signups_delete_own" on public.event_signups;
create policy "event_signups_delete_own" on public.event_signups for delete using (auth.uid() = user_id);

-- Reemplaza el trigger de alta para que sepa distinguir organizador de
-- lector según el account_type que viaje en el signUp() — CREATE OR REPLACE
-- es seguro de volver a ejecutar y sustituye la versión anterior (solo
-- lectores) definida más arriba en este mismo archivo.
create or replace function public.handle_new_user()
returns trigger as $$
declare
  base_username text;
begin
  if (new.raw_user_meta_data->>'account_type') = 'organizer' then
    insert into public.organizers (id, venue_name, city, contact_email)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'venue_name', split_part(new.email, '@', 1)),
      coalesce(new.raw_user_meta_data->>'city', ''),
      new.email
    )
    on conflict (id) do nothing;
    return new;
  end if;

  base_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    '[^a-z0-9]', '', 'g'
  ));
  insert into public.profiles (id, name, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    base_username || '_reads'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: mapa de eventos + lista de inscritos visible para lectores
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Coordenadas del evento (geocodificadas en el navegador del organizador al
-- crear/editar el evento, vía Nominatim/OpenStreetMap — gratis, sin API key)
-- para poder pintar cada evento en el mapa de "Eventos".
alter table public.events add column if not exists lat double precision;
alter table public.events add column if not exists lng double precision;

-- Antes solo el propio lector inscrito (o el organizador del evento) podían
-- ver una inscripción. Ahora cualquier lector logueado puede ver cuántos y
-- quiénes se han apuntado a un evento (igual que ya ve reseñas o quién tiene
-- un libro) — sigue sin exponer nada más que name/username, ya públicos en
-- cualquier perfil.
drop policy if exists "event_signups_select_authenticated" on public.event_signups;
create policy "event_signups_select_authenticated" on public.event_signups for select using (auth.uid() is not null);

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: libro vinculado al evento (opcional, para la story)
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Un organizador no tiene una shelfie propia de la que tirar, así que el
-- libro se busca en Open Library y se guarda "plano" (título/autor/portada)
-- en el propio evento, igual que ya se hace con otros datos de books en la
-- app — sin tabla de libros ni claves foráneas de por medio.
alter table public.events add column if not exists book_title text;
alter table public.events add column if not exists book_author text;
alter table public.events add column if not exists book_cover text;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: clave de Open Library del libro vinculado al evento
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Con solo título/autor/portada, la ficha del evento no podía enlazar al
-- libro dentro de shelfie (no hay forma fiable de reencontrar la obra
-- exacta en Open Library a partir de un título). Guardamos también su
-- work key (p.ej. "/works/OL12345W") para poder abrir su ficha real.
alter table public.events add column if not exists book_ol_key text;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: recuerda si un libro leído pasó antes por "Quiero leer"
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Para el logro "Exploración" del perfil: contar cuántos libros leídos
-- vinieron de tu lista de "Quiero leer" en vez de solo el tamaño de la
-- lista — así el logro premia terminar lo que planeas leer, no acumular
-- una lista interminable que nunca abres.
alter table public.user_books add column if not exists came_from_quiero boolean default false;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: recuerda si un libro leído había sido abandonado antes
-- + cuántas veces se ha compartido la Story del shelfie
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Mismo mecanismo que came_from_quiero, pero para el logro "Segunda
-- oportunidad": retomar y terminar un libro que estaba en Abandonados.
alter table public.user_books add column if not exists came_from_dnf boolean default false;

-- Contador para el logro "Embajador" — cuántas veces se ha descargado o
-- compartido la imagen de Story del propio shelfie.
alter table public.profiles add column if not exists story_shares integer default 0;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: tutorial guiado de bienvenida
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Default TRUE para que las cuentas ya existentes (que ejecuten esta
-- migración) no se encuentren el tutorial de golpe — el propio trigger de
-- alta, más abajo, lo pone explícitamente en FALSE solo para cuentas nuevas.
alter table public.profiles add column if not exists onboarding_seen boolean default true;

create or replace function public.handle_new_user()
returns trigger as $$
declare
  base_username text;
begin
  base_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    '[^a-z0-9]', '', 'g'
  ));
  insert into public.profiles (id, name, username, onboarding_seen)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    base_username || '_reads',
    false
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: reportar y bloquear usuarios
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles(id) on delete cascade not null,
  target_type text not null check (target_type in ('user','post')),
  target_id text not null, -- id de profiles (uuid) o de posts (id de texto)
  target_user_id uuid references public.profiles(id) on delete cascade, -- a quién se reporta, para poder revisar rápido sin resolver target_id
  reason text not null,
  details text,
  status text not null default 'pending' check (status in ('pending','reviewed','dismissed')),
  created_at timestamptz default now()
);
alter table public.reports enable row level security;
-- Solo puedes crear reportes en tu nombre, y solo puedes leer los tuyos —
-- no hay panel de moderación en la app todavía, así que estas filas se
-- revisan a mano desde el SQL Editor de Supabase.
drop policy if exists "reports_insert" on public.reports;
create policy "reports_insert" on public.reports for insert with check (auth.uid() = reporter_id);
drop policy if exists "reports_select" on public.reports;
create policy "reports_select" on public.reports for select using (auth.uid() = reporter_id);

create table if not exists public.blocks (
  blocker_id uuid references public.profiles(id) on delete cascade not null,
  blocked_id uuid references public.profiles(id) on delete cascade not null,
  created_at timestamptz default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
alter table public.blocks enable row level security;
-- Puedes gestionar (crear/borrar) solo tus propios bloqueos. La lectura
-- también permite ver las filas donde TÚ eres el bloqueado — no para
-- enseñarte una lista de "quién me ha bloqueado" en la UI (no se hace),
-- sino porque el cliente necesita poder comprobar esa dirección para
-- ocultar su propio contenido a quien le ha bloqueado.
drop policy if exists "blocks_select" on public.blocks;
create policy "blocks_select" on public.blocks for select using (auth.uid() = blocker_id or auth.uid() = blocked_id);
drop policy if exists "blocks_insert" on public.blocks;
create policy "blocks_insert" on public.blocks for insert with check (auth.uid() = blocker_id);
drop policy if exists "blocks_delete" on public.blocks;
create policy "blocks_delete" on public.blocks for delete using (auth.uid() = blocker_id);

-- Bloquear a alguien deshace el "seguir" en ambos sentidos automáticamente.
create or replace function public.handle_new_block()
returns trigger as $$
begin
  delete from public.friendships
  where (user_id = new.blocker_id and friend_id = new.blocked_id)
     or (user_id = new.blocked_id and friend_id = new.blocker_id);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_block_created on public.blocks;
create trigger on_block_created
  after insert on public.blocks
  for each row execute function public.handle_new_block();

-- Y mientras el bloqueo exista, no se puede volver a seguir en ningún sentido
-- (defensa de verdad en la base de datos, no solo en el cliente).
create or replace function public.prevent_follow_if_blocked()
returns trigger as $$
begin
  if exists (
    select 1 from public.blocks
    where (blocker_id = new.user_id and blocked_id = new.friend_id)
       or (blocker_id = new.friend_id and blocked_id = new.user_id)
  ) then
    raise exception 'No se puede seguir: hay un bloqueo entre estos dos usuarios.';
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists before_friendship_insert on public.friendships;
create trigger before_friendship_insert
  before insert on public.friendships
  for each row execute function public.prevent_follow_if_blocked();

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: perfiles privados y solicitudes de seguimiento
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

alter table public.profiles add column if not exists is_private boolean default false;

create table if not exists public.follow_requests (
  requester_id uuid references public.profiles(id) on delete cascade not null,
  target_id uuid references public.profiles(id) on delete cascade not null,
  created_at timestamptz default now(),
  primary key (requester_id, target_id),
  check (requester_id <> target_id)
);
alter table public.follow_requests enable row level security;
drop policy if exists "follow_requests_select" on public.follow_requests;
create policy "follow_requests_select" on public.follow_requests for select using (auth.uid() = requester_id or auth.uid() = target_id);
drop policy if exists "follow_requests_insert" on public.follow_requests;
create policy "follow_requests_insert" on public.follow_requests for insert with check (auth.uid() = requester_id);
-- El propio solicitante puede cancelarla, y quien la recibe puede rechazarla —
-- "borrar la fila" es como se representa tanto cancelar como rechazar.
drop policy if exists "follow_requests_delete" on public.follow_requests;
create policy "follow_requests_delete" on public.follow_requests for delete using (auth.uid() = requester_id or auth.uid() = target_id);

-- Igual que con los bloqueos: no se puede pedir seguir si ya hay un bloqueo
-- de por medio, ni si ya existe la solicitud o ya se sigue a esa persona.
create or replace function public.prevent_bad_follow_request()
returns trigger as $$
begin
  if exists (
    select 1 from public.blocks
    where (blocker_id = new.requester_id and blocked_id = new.target_id)
       or (blocker_id = new.target_id and blocked_id = new.requester_id)
  ) then
    raise exception 'No se puede solicitar seguir: hay un bloqueo entre estos dos usuarios.';
  end if;
  if exists (select 1 from public.friendships where user_id = new.requester_id and friend_id = new.target_id) then
    raise exception 'Ya sigues a este usuario.';
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists before_follow_request_insert on public.follow_requests;
create trigger before_follow_request_insert
  before insert on public.follow_requests
  for each row execute function public.prevent_bad_follow_request();

-- Aceptar una solicitud de seguimiento crea una fila en friendships donde
-- el SOLICITANTE es quien sigue — pero la política de friendships_insert
-- solo deja crear filas donde tú (auth.uid()) eres ese "user_id" (quien
-- sigue), no en nombre de otra persona. Por eso esto va aparte, como
-- función security definer: solo actúa si de verdad existe una solicitud
-- pendiente dirigida a quien la llama.
create or replace function public.accept_follow_request(p_requester_id uuid)
returns void as $$
begin
  if not exists (
    select 1 from public.follow_requests
    where requester_id = p_requester_id and target_id = auth.uid()
  ) then
    raise exception 'No existe esa solicitud de seguimiento.';
  end if;
  insert into public.friendships (user_id, friend_id) values (p_requester_id, auth.uid())
  on conflict do nothing;
  delete from public.follow_requests where requester_id = p_requester_id and target_id = auth.uid();
end;
$$ language plpgsql security definer;

-- Aplica de verdad la privacidad a nivel de base de datos, no solo
-- escondiendo cosas en la interfaz — quien no te sigue (y no eres tú
-- mismo) ya no puede leer tus libros ni tus publicaciones si tu cuenta es
-- privada. (Los comentarios, "me gusta", likes de comentario y reacciones
-- de esas publicaciones quedan blindados igual más abajo, en la
-- actualización "privacidad real también en comentarios, likes...".)
drop policy if exists "user_books_select" on public.user_books;
create policy "user_books_select" on public.user_books for select using (
  auth.uid() = user_id
  or not exists (select 1 from public.profiles p where p.id = user_books.user_id and p.is_private = true)
  or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = user_books.user_id)
);

drop policy if exists "posts_select" on public.posts;
create policy "posts_select" on public.posts for select using (
  auth.uid() = user_id
  or not exists (select 1 from public.profiles p where p.id = posts.user_id and p.is_private = true)
  or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = posts.user_id)
);

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: preferencia de notificaciones por email
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

alter table public.profiles add column if not exists email_notifications boolean default true;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: privacidad real también en comentarios, likes, likes de
-- comentario y reacciones — hasta ahora solo user_books/posts respetaban
-- is_private a nivel de base de datos; estas cuatro tablas seguían siendo
-- de lectura pública, así que alguien con el id exacto de un comentario o
-- like de una cuenta privada podía leerlo sin ser amigo. Cada política
-- resuelve hasta el post al que pertenece esa fila y aplica la misma regla
-- que ya usan user_books_select/posts_select: dueño, cuenta pública, o
-- amigo del dueño. Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

drop policy if exists "comments_select" on public.comments;
create policy "comments_select" on public.comments for select using (
  exists (
    select 1 from public.posts po
    where po.id = comments.post_id
    and (
      auth.uid() = po.user_id
      or not exists (select 1 from public.profiles p where p.id = po.user_id and p.is_private = true)
      or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = po.user_id)
    )
  )
);

drop policy if exists "likes_select" on public.likes;
create policy "likes_select" on public.likes for select using (
  exists (
    select 1 from public.posts po
    where po.id = likes.post_id
    and (
      auth.uid() = po.user_id
      or not exists (select 1 from public.profiles p where p.id = po.user_id and p.is_private = true)
      or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = po.user_id)
    )
  )
);

drop policy if exists "comment_likes_select" on public.comment_likes;
create policy "comment_likes_select" on public.comment_likes for select using (
  exists (
    select 1 from public.comments c
    join public.posts po on po.id = c.post_id
    where c.id = comment_likes.comment_id
    and (
      auth.uid() = po.user_id
      or not exists (select 1 from public.profiles p where p.id = po.user_id and p.is_private = true)
      or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = po.user_id)
    )
  )
);

drop policy if exists "post_reactions_select" on public.post_reactions;
create policy "post_reactions_select" on public.post_reactions for select using (
  exists (
    select 1 from public.posts po
    where po.id = post_reactions.post_id
    and (
      auth.uid() = po.user_id
      or not exists (select 1 from public.profiles p where p.id = po.user_id and p.is_private = true)
      or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = po.user_id)
    )
  )
);
