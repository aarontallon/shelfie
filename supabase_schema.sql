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
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select using (true);
drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles for insert with check (auth.uid() = id);
drop policy if exists "profiles_update" on public.profiles;
create policy "profiles_update" on public.profiles for update using (auth.uid() = id);

-- User books
drop policy if exists "user_books_select" on public.user_books;
create policy "user_books_select" on public.user_books for select using (true);
drop policy if exists "user_books_insert" on public.user_books;
create policy "user_books_insert" on public.user_books for insert with check (auth.uid() = user_id);
drop policy if exists "user_books_update" on public.user_books;
create policy "user_books_update" on public.user_books for update using (auth.uid() = user_id);
drop policy if exists "user_books_delete" on public.user_books;
create policy "user_books_delete" on public.user_books for delete using (auth.uid() = user_id);

-- Posts
drop policy if exists "posts_select" on public.posts;
create policy "posts_select" on public.posts for select using (true);
drop policy if exists "posts_insert" on public.posts;
create policy "posts_insert" on public.posts for insert with check (auth.uid() = user_id);
drop policy if exists "posts_update" on public.posts;
create policy "posts_update" on public.posts for update using (auth.uid() = user_id);
drop policy if exists "posts_delete" on public.posts;
create policy "posts_delete" on public.posts for delete using (auth.uid() = user_id);

-- Comments
drop policy if exists "comments_select" on public.comments;
create policy "comments_select" on public.comments for select using (true);
drop policy if exists "comments_insert" on public.comments;
create policy "comments_insert" on public.comments for insert with check (auth.uid() = user_id);
drop policy if exists "comments_delete" on public.comments;
create policy "comments_delete" on public.comments for delete using (auth.uid() = user_id);

-- Likes
drop policy if exists "likes_select" on public.likes;
create policy "likes_select" on public.likes for select using (true);
drop policy if exists "likes_insert" on public.likes;
create policy "likes_insert" on public.likes for insert with check (auth.uid() = user_id);
drop policy if exists "likes_delete" on public.likes;
create policy "likes_delete" on public.likes for delete using (auth.uid() = user_id);

-- Friendships (public read: follower/following counts are shown on public profiles, like Instagram)
drop policy if exists "friendships_select" on public.friendships;
create policy "friendships_select" on public.friendships for select using (true);
drop policy if exists "friendships_insert" on public.friendships;
create policy "friendships_insert" on public.friendships for insert with check (auth.uid() = user_id);
drop policy if exists "friendships_delete" on public.friendships;
create policy "friendships_delete" on public.friendships for delete using (auth.uid() = user_id or auth.uid() = friend_id);

-- Notifications
drop policy if exists "notifications_select" on public.notifications;
create policy "notifications_select" on public.notifications for select using (auth.uid() = user_id);
drop policy if exists "notifications_insert" on public.notifications;
create policy "notifications_insert" on public.notifications for insert with check (auth.uid() = actor_id);
drop policy if exists "notifications_update" on public.notifications;
create policy "notifications_update" on public.notifications for update using (auth.uid() = user_id);
drop policy if exists "notifications_delete" on public.notifications;
create policy "notifications_delete" on public.notifications for delete using (auth.uid() = user_id);

-- Habilita Realtime en notifications para que la campanita se actualice al instante.
-- Envuelto en un bloque que ignora el aviso de "ya es miembro de la publicación"
-- para poder volver a ejecutar este archivo entero sin que falle aquí.
do $$ begin alter publication supabase_realtime add table public.notifications; exception when others then null; end $$;

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

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: reparar duplicados de post_reactions + confirmar Realtime
-- Si al cambiar de reacción en un post se quedan las dos (la vieja y la
-- nueva) en vez de reemplazarse, es porque la tabla post_reactions de esta
-- base de datos no tiene realmente la clave primaria (post_id, user_id) —
-- el upsert(...).onConflict('post_id,user_id') del cliente no tiene nada
-- contra lo que hacer match, así que cada cambio de emoji inserta una fila
-- nueva en vez de sustituir la anterior. Segura de volver a ejecutar: no
-- borra la tabla entera (a diferencia del create table post_reactions de
-- más arriba), solo limpia duplicados existentes y añade la clave si falta.
-- ════════════════════════════════════════════════

delete from public.post_reactions a
using public.post_reactions b
where a.post_id = b.post_id
  and a.user_id = b.user_id
  and a.ctid < b.ctid;

do $$ begin
  alter table public.post_reactions add constraint post_reactions_pkey primary key (post_id, user_id);
exception when others then null; end $$;

-- Si los posts de gente que sigues no te aparecen al instante en el feed,
-- es porque la tabla posts (o alguna de estas) no está realmente añadida a
-- la publicación de Realtime en este proyecto. Repetir esto no hace daño.
do $$ begin alter publication supabase_realtime add table public.posts; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table public.comments; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table public.likes; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table public.comment_likes; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table public.post_reactions; exception when others then null; end $$;

-- ════════════════════════════════════════════════
-- MENSAJES DIRECTOS (estilo Instagram)
-- Una conversación por pareja de usuarios. Empieza en 'pending' (solicitud
-- de mensaje) salvo que quien responde no sea quien la inició — responder
-- a una solicitud la acepta automáticamente, igual que en Instagram.
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user1_id uuid references public.profiles(id) on delete cascade not null,
  user2_id uuid references public.profiles(id) on delete cascade not null,
  initiator_id uuid references public.profiles(id) on delete cascade not null,
  status text not null default 'pending' check (status in ('pending','accepted')),
  last_message text default '',
  last_message_at timestamptz default now(),
  created_at timestamptz default now(),
  check (user1_id <> user2_id)
);

create unique index if not exists conversations_pair_idx on public.conversations (least(user1_id,user2_id), greatest(user1_id,user2_id));

alter table public.conversations enable row level security;
drop policy if exists "conversations_select" on public.conversations;
create policy "conversations_select" on public.conversations for select using (auth.uid() = user1_id or auth.uid() = user2_id);
drop policy if exists "conversations_insert" on public.conversations;
create policy "conversations_insert" on public.conversations for insert with check (
  auth.uid() = initiator_id
  and (auth.uid() = user1_id or auth.uid() = user2_id)
  and not exists (
    select 1 from public.blocks b
    where (b.blocker_id = user1_id and b.blocked_id = user2_id)
       or (b.blocker_id = user2_id and b.blocked_id = user1_id)
  )
);
drop policy if exists "conversations_update" on public.conversations;
create policy "conversations_update" on public.conversations for update using (auth.uid() = user1_id or auth.uid() = user2_id);
drop policy if exists "conversations_delete" on public.conversations;
create policy "conversations_delete" on public.conversations for delete using (auth.uid() = user1_id or auth.uid() = user2_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.conversations(id) on delete cascade not null,
  sender_id uuid references public.profiles(id) on delete cascade not null,
  text text not null,
  created_at timestamptz default now(),
  read_at timestamptz
);
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

alter table public.messages enable row level security;
drop policy if exists "messages_select" on public.messages;
create policy "messages_select" on public.messages for select using (
  exists (select 1 from public.conversations c where c.id = messages.conversation_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid()))
);
drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert" on public.messages for insert with check (
  auth.uid() = sender_id
  and exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = c.user1_id and b.blocked_id = c.user2_id)
         or (b.blocker_id = c.user2_id and b.blocked_id = c.user1_id)
    )
  )
);
-- Solo se usa para marcar read_at de los mensajes ajenos como leídos, nunca para tocar el texto.
drop policy if exists "messages_update" on public.messages;
create policy "messages_update" on public.messages for update using (
  exists (select 1 from public.conversations c where c.id = messages.conversation_id and (c.user1_id = auth.uid() or c.user2_id = auth.uid()))
);
drop policy if exists "messages_delete" on public.messages;
create policy "messages_delete" on public.messages for delete using (auth.uid() = sender_id);

create or replace function public.handle_new_message()
returns trigger as $$
begin
  update public.conversations
  set last_message = new.text,
      last_message_at = new.created_at,
      status = case when initiator_id <> new.sender_id then 'accepted' else status end
  where id = new.conversation_id;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_message_created on public.messages;
create trigger on_message_created
  after insert on public.messages
  for each row execute function public.handle_new_message();

do $$ begin alter publication supabase_realtime add table public.conversations; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table public.messages; exception when others then null; end $$;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: reacciones a mensajes directos (un emoji por persona,
-- igual que las reacciones a posts). Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

create table if not exists public.message_reactions (
  message_id uuid references public.messages(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  emoji text not null,
  created_at timestamptz default now(),
  primary key (message_id, user_id)
);

alter table public.message_reactions enable row level security;
drop policy if exists "message_reactions_select" on public.message_reactions;
create policy "message_reactions_select" on public.message_reactions for select using (
  exists (
    select 1 from public.messages m
    join public.conversations c on c.id = m.conversation_id
    where m.id = message_reactions.message_id
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
);
drop policy if exists "message_reactions_insert" on public.message_reactions;
create policy "message_reactions_insert" on public.message_reactions for insert with check (
  auth.uid() = user_id
  and exists (
    select 1 from public.messages m
    join public.conversations c on c.id = m.conversation_id
    where m.id = message_reactions.message_id
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
  )
);
drop policy if exists "message_reactions_update" on public.message_reactions;
create policy "message_reactions_update" on public.message_reactions for update using (auth.uid() = user_id);
drop policy if exists "message_reactions_delete" on public.message_reactions;
create policy "message_reactions_delete" on public.message_reactions for delete using (auth.uid() = user_id);

do $$ begin alter publication supabase_realtime add table public.message_reactions; exception when others then null; end $$;

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: notificaciones push (Web Push) — guarda una fila por
-- cada dispositivo/navegador que activa las notificaciones, con las claves
-- que hacen falta para poder enviarle un push cifrado (RFC 8291) más
-- adelante desde la Edge Function send-push. Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;
drop policy if exists "push_subscriptions_select" on public.push_subscriptions;
create policy "push_subscriptions_select" on public.push_subscriptions for select using (auth.uid() = user_id);
drop policy if exists "push_subscriptions_insert" on public.push_subscriptions;
create policy "push_subscriptions_insert" on public.push_subscriptions for insert with check (auth.uid() = user_id);
drop policy if exists "push_subscriptions_delete" on public.push_subscriptions;
create policy "push_subscriptions_delete" on public.push_subscriptions for delete using (auth.uid() = user_id);
-- Sin policy de update: para cambiar de claves, el cliente borra la fila
-- vieja (por endpoint) e inserta una nueva — es como cambia el navegador
-- una suscripción push, nunca hay que editar una ya existente en el sitio.

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: notificaciones push programadas (racha en peligro, resumen
-- semanal de eventos) — usa pg_cron para llamar a la Edge Function
-- send-scheduled-push en un horario fijo, en vez de reaccionar a un INSERT
-- como el resto de pushes. Requiere activar la extensión pg_cron una vez
-- (Database → Extensions → actívala si el create extension de abajo no
-- tiene permiso para hacerlo solo). Segura de volver a ejecutar — cada vez
-- que se corre, borra y vuelve a crear los dos jobs con el mismo nombre.
-- ════════════════════════════════════════════════

create extension if not exists pg_cron;

do $$ begin perform cron.unschedule('shelfie-streak-reminder'); exception when others then null; end $$;
select cron.schedule(
  'shelfie-streak-reminder',
  '0 19 * * *', -- ~20h en Madrid en horario de invierno (CET); en verano (CEST) cae sobre las 21h
  $cron$select net.http_post(
    url := 'https://zkoarvxhjunwmyiaynyc.supabase.co/functions/v1/send-scheduled-push',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"job":"streak_reminder"}'::jsonb
  );$cron$
);

do $$ begin perform cron.unschedule('shelfie-weekly-digest'); exception when others then null; end $$;
select cron.schedule(
  'shelfie-weekly-digest',
  '0 8 * * 1', -- lunes por la mañana
  $cron$select net.http_post(
    url := 'https://zkoarvxhjunwmyiaynyc.supabase.co/functions/v1/send-scheduled-push',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := '{"job":"weekly_digest"}'::jsonb
  );$cron$
);

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: auditoría de seguridad — organizadores sin perfil,
-- carrera de aforo en eventos, edición de mensajes ajenos, bloqueos no
-- aplicados en comentarios/likes/reacciones/notificaciones, y permisos de
-- avatar demasiado abiertos. Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- handle_new_user() se había quedado redefinida 3 veces en este archivo;
-- como CREATE OR REPLACE siempre deja ganar a la última que se ejecuta, la
-- versión que quedaba viva (la del tutorial de bienvenida) había perdido
-- sin querer la rama que distingue organizador de lector, Y encima nunca
-- creaba fila en profiles para los organizadores — con lo que la
-- notificación de "alguien se ha apuntado a tu evento" fallaba siempre por
-- violar la referencia notifications.user_id -> profiles(id). Esta versión
-- final crea profiles SIEMPRE (lector u organizador) y, si el alta es de
-- tipo organizador, además crea su fila en organizers.
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

  if (new.raw_user_meta_data->>'account_type') = 'organizer' then
    insert into public.organizers (id, venue_name, city, contact_email)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'venue_name', split_part(new.email, '@', 1)),
      coalesce(new.raw_user_meta_data->>'city', ''),
      new.email
    )
    on conflict (id) do nothing;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- Backfill: cualquier organizador ya existente que se diera de alta
-- mientras el trigger estaba roto y por tanto se quedó sin fila en
-- profiles. El sufijo con parte del id evita choques de username único.
insert into public.profiles (id, name, username, onboarding_seen)
select
  o.id,
  coalesce(nullif(o.venue_name,''), 'Organizador'),
  lower(regexp_replace(coalesce(nullif(o.venue_name,''),'organizador'), '[^a-z0-9]', '', 'g')) || '_' || substr(o.id::text,1,8),
  true
from public.organizers o
where not exists (select 1 from public.profiles p where p.id = o.id)
on conflict (id) do nothing;

-- Carrera de aforo: antes solo se comprobaba en el cliente (una lectura de
-- la caché local antes de insertar), así que dos inscripciones casi
-- simultáneas para el último hueco podían pasar las dos, y un cliente
-- modificado podía saltárselo directamente. "select ... for update" bloquea
-- la fila del evento mientras dura la transacción, así que dos inserts a
-- la vez quedan serializados y el segundo ve el conteo ya actualizado.
create or replace function public.enforce_event_capacity()
returns trigger as $$
declare
  cap int;
  current_count int;
begin
  select capacity into cap from public.events where id = new.event_id for update;
  if cap is not null then
    select count(*) into current_count from public.event_signups where event_id = new.event_id;
    if current_count >= cap then
      raise exception 'Este evento ya está completo.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists before_event_signup_insert on public.event_signups;
create trigger before_event_signup_insert
  before insert on public.event_signups
  for each row execute function public.enforce_event_capacity();

-- messages_update solo se pensó para marcar read_at como leído, pero la
-- policy en sí no lo impedía — cualquiera de los dos participantes podía
-- reescribir el texto (o hasta el remitente) de un mensaje ajeno. Un
-- trigger sí puede comparar OLD contra NEW columna a columna, cosa que RLS
-- no puede hacer por sí sola.
create or replace function public.protect_message_immutable_fields()
returns trigger as $$
begin
  if new.text is distinct from old.text
     or new.sender_id is distinct from old.sender_id
     or new.conversation_id is distinct from old.conversation_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Solo se puede actualizar read_at en un mensaje.';
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists before_message_update on public.messages;
create trigger before_message_update
  before update on public.messages
  for each row execute function public.protect_message_immutable_fields();

-- Mismo problema en conversations_update: un participante podía reasignar
-- al OTRO participante a un uuid arbitrario, exponiendo el historial de
-- mensajes a un tercero no invitado. Los únicos cambios legítimos son
-- status (al aceptar una solicitud) y last_message/last_message_at (los
-- pone el propio trigger handle_new_message()).
create or replace function public.protect_conversation_immutable_fields()
returns trigger as $$
begin
  if new.user1_id is distinct from old.user1_id
     or new.user2_id is distinct from old.user2_id
     or new.initiator_id is distinct from old.initiator_id
     or new.created_at is distinct from old.created_at then
    raise exception 'No se pueden cambiar los participantes de una conversación.';
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists before_conversation_update on public.conversations;
create trigger before_conversation_update
  before update on public.conversations
  for each row execute function public.protect_conversation_immutable_fields();

-- Bloquear a alguien ya deshacía el "seguir" en ambos sentidos, pero dejaba
-- vivas las solicitudes de seguimiento pendientes entre esas dos cuentas.
create or replace function public.handle_new_block()
returns trigger as $$
begin
  delete from public.friendships
  where (user_id = new.blocker_id and friend_id = new.blocked_id)
     or (user_id = new.blocked_id and friend_id = new.blocker_id);
  delete from public.follow_requests
  where (requester_id = new.blocker_id and target_id = new.blocked_id)
     or (requester_id = new.blocked_id and target_id = new.blocker_id);
  return new;
end;
$$ language plpgsql security definer;

-- El bloqueo se aplicaba ya al enviar mensajes directos, pero no al dar
-- like/comentar/reaccionar en publicaciones ni al reaccionar a un mensaje
-- — alguien a quien has bloqueado podía seguir interactuando con tu
-- contenido público llamando directamente a la API, saltándose el bloqueo.
drop policy if exists "comments_insert" on public.comments;
create policy "comments_insert" on public.comments for insert with check (
  auth.uid() = user_id
  and not exists (
    select 1 from public.posts p
    join public.blocks b on (b.blocker_id = p.user_id and b.blocked_id = auth.uid())
                          or (b.blocker_id = auth.uid() and b.blocked_id = p.user_id)
    where p.id = comments.post_id
  )
);

drop policy if exists "likes_insert" on public.likes;
create policy "likes_insert" on public.likes for insert with check (
  auth.uid() = user_id
  and not exists (
    select 1 from public.posts p
    join public.blocks b on (b.blocker_id = p.user_id and b.blocked_id = auth.uid())
                          or (b.blocker_id = auth.uid() and b.blocked_id = p.user_id)
    where p.id = likes.post_id
  )
);

drop policy if exists "comment_likes_insert" on public.comment_likes;
create policy "comment_likes_insert" on public.comment_likes for insert with check (
  auth.uid() = user_id
  and not exists (
    select 1 from public.comments c
    join public.posts p on p.id = c.post_id
    join public.blocks b on (b.blocker_id = p.user_id and b.blocked_id = auth.uid())
                          or (b.blocker_id = auth.uid() and b.blocked_id = p.user_id)
    where c.id = comment_likes.comment_id
  )
);

drop policy if exists "post_reactions_insert" on public.post_reactions;
create policy "post_reactions_insert" on public.post_reactions for insert with check (
  auth.uid() = user_id
  and not exists (
    select 1 from public.posts p
    join public.blocks b on (b.blocker_id = p.user_id and b.blocked_id = auth.uid())
                          or (b.blocker_id = auth.uid() and b.blocked_id = p.user_id)
    where p.id = post_reactions.post_id
  )
);

drop policy if exists "message_reactions_insert" on public.message_reactions;
create policy "message_reactions_insert" on public.message_reactions for insert with check (
  auth.uid() = user_id
  and exists (
    select 1 from public.messages m
    join public.conversations c on c.id = m.conversation_id
    where m.id = message_reactions.message_id
    and (c.user1_id = auth.uid() or c.user2_id = auth.uid())
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = c.user1_id and b.blocked_id = c.user2_id)
         or (b.blocker_id = c.user2_id and b.blocked_id = c.user1_id)
    )
  )
);

-- notifications_insert solo comprobaba "quien la manda soy yo", sin mirar
-- si hay un bloqueo entre emisor y receptor — cualquier cuenta logueada
-- podía forzar una notificación (y por tanto un push) a alguien que la
-- había bloqueado. Nota: esto cierra el caso de abuso más directo, pero no
-- valida que el evento en sí sea real (p.ej. que ese "like" haya pasado de
-- verdad) — hacerlo exigiría generar las notificaciones desde triggers en
-- las propias tablas de origen en vez de confiar en el insert del cliente,
-- un cambio más grande que queda fuera de este parche.
drop policy if exists "notifications_insert" on public.notifications;
create policy "notifications_insert" on public.notifications for insert with check (
  auth.uid() = actor_id
  and not exists (
    select 1 from public.blocks b
    where (b.blocker_id = notifications.user_id and b.blocked_id = auth.uid())
       or (b.blocker_id = auth.uid() and b.blocked_id = notifications.user_id)
  )
);

-- Los avatares se suben siempre a la ruta "{auth.uid()}/avatar_...ext"
-- (ver uploadProfilePhoto() en el cliente) — antes cualquier usuario
-- logueado podía sobrescribir o borrar el archivo de CUALQUIER otro
-- (vandalismo/DoS: podían dejar sin foto a todo el mundo), porque la
-- policy solo miraba que estuvieras autenticado, no de quién era la
-- carpeta. storage.foldername(name) da el primer segmento de la ruta.
drop policy if exists "avatar_owner_write" on storage.objects;
create policy "avatar_owner_write" on storage.objects for insert with check (
  bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "avatar_owner_update" on storage.objects;
create policy "avatar_owner_update" on storage.objects for update using (
  bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "avatar_owner_delete" on storage.objects;
create policy "avatar_owner_delete" on storage.objects for delete using (
  bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
);

-- push_subscriptions no tenía policy de update — el cliente borraba la fila
-- vieja e insertaba una nueva, lo que además de no ser atómico (dos
-- pestañas activando el push a la vez podían chocar) se rompía del todo en
-- un dispositivo compartido: si la cuenta A ya tenía el push activado y no
-- lo desactivó al cerrar sesión, la cuenta B no podía ni borrar la fila de
-- A (no es su dueña) ni insertar la suya (el mismo "endpoint" físico del
-- dispositivo choca con el unique constraint). Ahora el cliente hace un
-- upsert por endpoint; el endpoint es un secreto largo e infalsificable
-- (hace falta acceso real al propio dispositivo para conocerlo), así que
-- permitir el update en general y solo exigir que el resultado quede a tu
-- nombre es seguro y resuelve el caso de dispositivo compartido sin más.
drop policy if exists "push_subscriptions_update" on public.push_subscriptions;
create policy "push_subscriptions_update" on public.push_subscriptions for update
  using (true)
  with check (auth.uid() = user_id);

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: las notificaciones las genera la base de datos, no el
-- cliente. Hasta ahora cada acción (dar like, comentar, seguir...) hacía
-- DOS cosas desde el navegador: la acción en sí y, aparte, un insert en
-- notifications. Eso significaba que cualquiera con la consola abierta
-- podía insertar la notificación SIN hacer la acción — y desde que hay
-- push, eso es un aviso real al móvil de quien tú quisieras, las veces que
-- quisieras. Ahora cada notificación nace de un trigger sobre la tabla de
-- la acción real, y al cliente se le retira el permiso de insertar.
-- Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- Punto único por el que pasan todas: descarta auto-notificarse, respeta
-- bloqueos en ambos sentidos, y evita el spam de repetir la misma
-- notificación (dar y quitar like en bucle, cambiar de emoji varias veces)
-- reutilizando la que ya haya sin leer de la última hora. Los comentarios
-- se quedan fuera de esa deduplicación: cada comentario es contenido
-- distinto y merece su propio aviso.
create or replace function public.create_notification(p_user_id uuid, p_actor_id uuid, p_type text)
returns void as $$
begin
  if p_user_id is null or p_actor_id is null or p_user_id = p_actor_id then
    return;
  end if;
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = p_user_id and b.blocked_id = p_actor_id)
       or (b.blocker_id = p_actor_id and b.blocked_id = p_user_id)
  ) then
    return;
  end if;
  -- Solo notifica a cuentas que existen como perfil (un organizador sin
  -- perfil rompería la clave foránea y abortaría la acción original).
  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    return;
  end if;
  if p_type <> 'comment' and exists (
    select 1 from public.notifications n
    where n.user_id = p_user_id and n.actor_id = p_actor_id and n.type = p_type
      and n.read = false and n.created_at > now() - interval '1 hour'
  ) then
    return;
  end if;
  insert into public.notifications (user_id, actor_id, type)
  values (p_user_id, p_actor_id, p_type);
end;
$$ language plpgsql security definer;

create or replace function public.notify_on_follow()
returns trigger as $$
begin
  -- accept_follow_request() crea la amistad en nombre del solicitante; ahí
  -- el aviso correcto es "te han aceptado", no "te sigue", así que marca
  -- esta bandera de transacción para que este trigger se aparte.
  if coalesce(current_setting('shelfie.skip_follow_notification', true), '') = '1' then
    return new;
  end if;
  perform public.create_notification(new.friend_id, new.user_id, 'follow');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_friendship_notify on public.friendships;
create trigger on_friendship_notify
  after insert on public.friendships
  for each row execute function public.notify_on_follow();

create or replace function public.notify_on_follow_request()
returns trigger as $$
begin
  perform public.create_notification(new.target_id, new.requester_id, 'follow_request');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_follow_request_notify on public.follow_requests;
create trigger on_follow_request_notify
  after insert on public.follow_requests
  for each row execute function public.notify_on_follow_request();

create or replace function public.notify_on_like()
returns trigger as $$
declare
  author uuid;
begin
  select user_id into author from public.posts where id = new.post_id;
  perform public.create_notification(author, new.user_id, 'like');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_like_notify on public.likes;
create trigger on_like_notify
  after insert on public.likes
  for each row execute function public.notify_on_like();

create or replace function public.notify_on_comment()
returns trigger as $$
declare
  author uuid;
begin
  select user_id into author from public.posts where id = new.post_id;
  perform public.create_notification(author, new.user_id, 'comment');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_comment_notify on public.comments;
create trigger on_comment_notify
  after insert on public.comments
  for each row execute function public.notify_on_comment();

create or replace function public.notify_on_comment_like()
returns trigger as $$
declare
  author uuid;
begin
  select user_id into author from public.comments where id = new.comment_id;
  perform public.create_notification(author, new.user_id, 'comment_like');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_comment_like_notify on public.comment_likes;
create trigger on_comment_like_notify
  after insert on public.comment_likes
  for each row execute function public.notify_on_comment_like();

create or replace function public.notify_on_post_reaction()
returns trigger as $$
declare
  author uuid;
begin
  select user_id into author from public.posts where id = new.post_id;
  perform public.create_notification(author, new.user_id, 'reaction');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_post_reaction_notify on public.post_reactions;
create trigger on_post_reaction_notify
  after insert or update on public.post_reactions
  for each row execute function public.notify_on_post_reaction();

create or replace function public.notify_on_event_signup()
returns trigger as $$
declare
  organizer uuid;
begin
  select organizer_id into organizer from public.events where id = new.event_id;
  perform public.create_notification(organizer, new.user_id, 'event_signup');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_event_signup_notify on public.event_signups;
create trigger on_event_signup_notify
  after insert on public.event_signups
  for each row execute function public.notify_on_event_signup();

-- Aceptar una solicitud: crea la amistad (en nombre del solicitante, por eso
-- sigue siendo security definer), silencia el trigger de "te sigue" y manda
-- el aviso correcto de "te han aceptado".
create or replace function public.accept_follow_request(p_requester_id uuid)
returns void as $$
begin
  if not exists (
    select 1 from public.follow_requests
    where requester_id = p_requester_id and target_id = auth.uid()
  ) then
    raise exception 'No existe esa solicitud de seguimiento.';
  end if;
  perform set_config('shelfie.skip_follow_notification', '1', true);
  insert into public.friendships (user_id, friend_id) values (p_requester_id, auth.uid())
  on conflict do nothing;
  delete from public.follow_requests where requester_id = p_requester_id and target_id = auth.uid();
  perform public.create_notification(p_requester_id, auth.uid(), 'follow_accepted');
end;
$$ language plpgsql security definer;

-- Y ya nadie puede insertar una notificación a mano: solo salen de los
-- triggers de arriba, que corren como dueño de la tabla y por tanto no
-- pasan por esta policy.
drop policy if exists "notifications_insert" on public.notifications;
create policy "notifications_insert" on public.notifications for insert with check (false);

-- ════════════════════════════════════════════════
-- ACTUALIZACIÓN: orden manual de la estantería, objetivos del año y arreglos
-- de pérdida de datos detectados en la auditoría. Segura de volver a ejecutar.
-- ════════════════════════════════════════════════

-- El orden en el que colocas tus libros a mano no se guardaba en ninguna
-- parte: se perdía al recargar, y como la consulta tampoco pedía ningún
-- orden concreto, cada carga podía devolverlos en un orden distinto.
alter table public.user_books add column if not exists sort_order integer;
create index if not exists user_books_user_sort_idx on public.user_books (user_id, sort_order);

-- Los libros marcados para el "Shelfie <año>" (YEAR_GOAL_IDS) vivían solo en
-- memoria: la pestaña se vaciaba en cada recarga y el contador se colaba
-- entre cuentas al cambiar de sesión en la misma pestaña.
alter table public.profiles add column if not exists year_goal_ids jsonb default '[]'::jsonb;
alter table public.profiles add column if not exists year_goal_year integer;
-- Y el archivo de shelfies de años anteriores, que se generaba en memoria y
-- nunca se leía ni se guardaba en ningún sitio.
alter table public.profiles add column if not exists shelfie_archive jsonb default '[]'::jsonb;

-- Marca las cuentas de organizador para poder excluirlas de las listas de
-- lectores. Desde que handle_new_user() les crea también fila en profiles
-- (hace falta para la clave foránea de notifications), aparecían como
-- lectores fantasma en búsquedas, sugerencias y chats — con un usuario
-- inventado tipo "nombre_reads" y sin poder entrar nunca a la app de lector.
alter table public.profiles add column if not exists is_organizer boolean default false;
update public.profiles p set is_organizer = true
where exists (select 1 from public.organizers o where o.id = p.id) and p.is_organizer is distinct from true;

create or replace function public.handle_new_user()
returns trigger as $$
declare
  base_username text;
  is_org boolean := (new.raw_user_meta_data->>'account_type') = 'organizer';
begin
  base_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    '[^a-z0-9]', '', 'g'
  ));
  insert into public.profiles (id, name, username, onboarding_seen, is_organizer)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    base_username || '_reads',
    false,
    is_org
  )
  on conflict (id) do nothing;

  if is_org then
    insert into public.organizers (id, venue_name, city, contact_email)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'venue_name', split_part(new.email, '@', 1)),
      coalesce(new.raw_user_meta_data->>'city', ''),
      new.email
    )
    on conflict (id) do nothing;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- Borrar tu cuenta arrastraba consigo las conversaciones enteras y por tanto
-- los mensajes que la OTRA persona te había escrito y los suyos propios, sin
-- dejar rastro en su bandeja. Ahora la referencia se pone a null y queda un
-- hueco ("Cuenta eliminada") en vez de desaparecer la conversación entera.
do $$ begin
  alter table public.conversations drop constraint if exists conversations_user1_id_fkey;
  alter table public.conversations add constraint conversations_user1_id_fkey
    foreign key (user1_id) references public.profiles(id) on delete set null;
exception when others then null; end $$;
do $$ begin
  alter table public.conversations drop constraint if exists conversations_user2_id_fkey;
  alter table public.conversations add constraint conversations_user2_id_fkey
    foreign key (user2_id) references public.profiles(id) on delete set null;
exception when others then null; end $$;
do $$ begin
  alter table public.conversations alter column user1_id drop not null;
  alter table public.conversations alter column user2_id drop not null;
exception when others then null; end $$;
do $$ begin
  alter table public.messages drop constraint if exists messages_sender_id_fkey;
  alter table public.messages add constraint messages_sender_id_fkey
    foreign key (sender_id) references public.profiles(id) on delete set null;
  alter table public.messages alter column sender_id drop not null;
exception when others then null; end $$;

-- Y un reporte no debería poder borrarlo la propia persona reportada solo con
-- eliminar su cuenta — el historial de moderación tiene que sobrevivirle.
do $$ begin
  alter table public.reports drop constraint if exists reports_target_user_id_fkey;
  alter table public.reports add constraint reports_target_user_id_fkey
    foreign key (target_user_id) references public.profiles(id) on delete set null;
exception when others then null; end $$;

-- ACTUALIZACIÓN: la racha ("¡Hoy he leído!") exigía cero esfuerzo real — se
-- podía marcar el día sin haber tocado ningún libro. Ahora hace falta haber
-- avanzado al menos 5 páginas ESE DÍA (sumando todas las actualizaciones de
-- progreso), tanto si se marca a mano como si se autodetecta al actualizar
-- páginas. Solo hace falta guardar el acumulado del día actual, no un
-- historial — se resetea solo en cuanto cambia la fecha (ver
-- registerPagesProgress() en el cliente).
alter table public.profiles add column if not exists pages_today_date text;
alter table public.profiles add column if not exists pages_today_count integer not null default 0;
