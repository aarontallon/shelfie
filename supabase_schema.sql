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
  created_at timestamptz default now()
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

-- Friendships
create policy "friendships_select" on public.friendships for select using (auth.uid() = user_id or auth.uid() = friend_id);
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
