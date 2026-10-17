-- 拾光 · 青春档案 v2 数据库初始化
-- 在 Supabase Dashboard -> SQL Editor 中完整运行一次。
-- 幂等设计：如果之前跑过 v1 的 schema.sql，直接再跑一遍本文件即可升级。
-- 网页中只使用 Project URL + anon/public key，绝不使用 service_role key。
-- 注意：Supabase -> Authentication -> Providers -> Email 里请关闭 "Confirm email"，
-- 本站使用用户名+密码注册（内部映射为合成邮箱），开邮箱验证会导致无法登录。

create extension if not exists pgcrypto;

-- ============ 用户档案 ============
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null default '' check (char_length(username) <= 24),
  display_name text not null default '新同学' check (char_length(display_name) <= 60),
  age int check (age is null or (age between 1 and 120)),
  personality text not null default '' check (char_length(personality) <= 120),
  signature text not null default '' check (char_length(signature) <= 200),
  bio text not null default '' check (char_length(bio) <= 2000),
  avatar_url text,
  hobbies text not null default '' check (char_length(hobbies) <= 500),
  contact text not null default '',
  social text not null default '',
  photo_layout text not null default 'center' check (photo_layout in ('left','right','center','cover')),
  theme text not null default 'aurora' check (theme in ('aurora','sunset','forest','mono','starry','ocean','custom')),
  theme_color text not null default '#a78bfa',
  role text not null default 'member' check (role in ('member','admin','super_admin')),
  is_admin boolean not null default false,
  is_banned boolean not null default false,
  profile_visibility text not null default 'public' check (profile_visibility in ('private','public')),
  show_name boolean not null default true,
  show_age boolean not null default true,
  show_personality boolean not null default true,
  show_signature boolean not null default true,
  show_bio boolean not null default true,
  show_avatar boolean not null default true,
  show_hobbies boolean not null default true,
  created_at timestamptz not null default now()
);

-- v1 升级补列
alter table public.profiles add column if not exists username text not null default '';
alter table public.profiles add column if not exists signature text not null default '';
alter table public.profiles add column if not exists hobbies text not null default '';
alter table public.profiles add column if not exists contact text not null default '';
alter table public.profiles add column if not exists social text not null default '';
alter table public.profiles add column if not exists photo_layout text not null default 'center';
alter table public.profiles add column if not exists theme text not null default 'aurora';
alter table public.profiles add column if not exists theme_color text not null default '#a78bfa';
alter table public.profiles add column if not exists role text not null default 'member';
alter table public.profiles add column if not exists show_name boolean not null default true;
alter table public.profiles add column if not exists show_signature boolean not null default true;
alter table public.profiles add column if not exists show_hobbies boolean not null default true;
do $$ begin
  alter table public.profiles add constraint profiles_username_unique unique (username);
exception when duplicate_object then null; end $$;
-- v1 的 is_admin 迁移到 role
update public.profiles set role = 'admin' where is_admin = true and role = 'member';

alter table public.profiles enable row level security;
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_select_public" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_admin_all" on public.profiles;
create policy "profiles_select_own" on public.profiles for select using (auth.uid() = id);
create policy "profiles_select_public" on public.profiles for select using (profile_visibility = 'public' and is_banned = false);
-- 普通用户新建/修改自己的档案时，不允许自封管理员或给自己解封（防提权）
create policy "profiles_insert_own" on public.profiles for insert with check (
  auth.uid() = id and role = 'member'
  and coalesce(is_admin, false) = false and coalesce(is_banned, false) = false);
create policy "profiles_update_own" on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id
    and role = (select p.role from public.profiles p where p.id = auth.uid())
    and coalesce(is_admin, false) = (select coalesce(p.is_admin, false) from public.profiles p where p.id = auth.uid())
    and coalesce(is_banned, false) = (select coalesce(p.is_banned, false) from public.profiles p where p.id = auth.uid()));
-- 管理员可以看全部、禁用用户；只有超管能改 role
create policy "profiles_admin_select" on public.profiles for select using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')));
create policy "profiles_admin_ban" on public.profiles for update using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')))
  with check (role = (select role from public.profiles where id = public.profiles.id));
create policy "profiles_superadmin_role" on public.profiles for update using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'super_admin'));
create policy "profiles_admin_delete" on public.profiles for delete using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin'))
  and (select role from public.profiles where id = public.profiles.id) = 'member');

-- 公开资料安全视图：字段级隐私在这里真正生效（联系方式/社交账号永不进视图）
create or replace view public.public_profiles as
select
  id,
  username,
  case when show_name then display_name end as display_name,
  case when show_age then age end as age,
  case when show_personality then personality end as personality,
  case when show_signature then signature end as signature,
  case when show_bio then bio end as bio,
  case when show_avatar then avatar_url end as avatar_url,
  case when show_hobbies then hobbies end as hobbies,
  photo_layout, theme, theme_color, role, created_at
from public.profiles
where profile_visibility = 'public' and is_banned = false;

-- 首个注册用户自动成为超管（仅当全站还没有超管时）
create or replace function public.claim_super_admin()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.profiles where role = 'super_admin') then
    update public.profiles set role = 'super_admin' where id = auth.uid();
  end if;
end $$;

-- ============ 青春时间线 ============
create table if not exists public.timeline_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_date date not null,
  title text not null check (char_length(title) <= 120),
  text text not null default '' check (char_length(text) <= 2000),
  image_url text,
  video_url text,
  created_at timestamptz not null default now()
);
alter table public.timeline_events enable row level security;
drop policy if exists "timeline_read" on public.timeline_events;
drop policy if exists "timeline_write_own" on public.timeline_events;
drop policy if exists "timeline_admin_delete" on public.timeline_events;
create policy "timeline_read" on public.timeline_events for select using (
  user_id = auth.uid() or exists (
    select 1 from public.profiles p where p.id = timeline_events.user_id
    and p.profile_visibility = 'public' and p.is_banned = false));
create policy "timeline_write_own" on public.timeline_events for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "timeline_admin_delete" on public.timeline_events for delete using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')));

-- ============ 班级相册 ============
create table if not exists public.albums (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) <= 80),
  category text not null default '班级日常' check (char_length(category) <= 40),
  cover_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.album_photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.albums(id) on delete cascade,
  image_url text not null,
  caption text not null default '' check (char_length(caption) <= 200),
  created_at timestamptz not null default now()
);
alter table public.albums enable row level security;
alter table public.album_photos enable row level security;
drop policy if exists "albums_read" on public.albums;
drop policy if exists "albums_write_own" on public.albums;
drop policy if exists "albums_admin" on public.albums;
drop policy if exists "aphotos_read" on public.album_photos;
drop policy if exists "aphotos_write" on public.album_photos;
create policy "albums_read" on public.albums for select using (true);
create policy "albums_write_own" on public.albums for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "albums_admin" on public.albums for all using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')));
create policy "aphotos_read" on public.album_photos for select using (true);
create policy "aphotos_write" on public.album_photos for all using (
  exists (select 1 from public.albums a where a.id = album_photos.album_id and (a.user_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')))));

-- ============ 班级动态 ============
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) <= 2000),
  image_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) <= 500),
  created_at timestamptz not null default now()
);
create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.likes enable row level security;
drop policy if exists "posts_read" on public.posts;
drop policy if exists "posts_write_own" on public.posts;
drop policy if exists "posts_admin_delete" on public.posts;
drop policy if exists "comments_all_auth" on public.comments;
drop policy if exists "comments_admin_delete" on public.comments;
drop policy if exists "likes_all_auth" on public.likes;
create policy "posts_read" on public.posts for select using (auth.uid() is not null);
create policy "posts_write_own" on public.posts for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "posts_admin_delete" on public.posts for delete using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')));
-- 评论：只能看全部、写自己的、改自己的、删自己的（管理员删任意见下面）
create policy "comments_select_auth" on public.comments for select using (auth.uid() is not null);
create policy "comments_insert_own" on public.comments for insert with check (user_id = auth.uid());
create policy "comments_update_own" on public.comments for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "comments_delete_own" on public.comments for delete using (user_id = auth.uid());
create policy "comments_admin_delete" on public.comments for delete using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')));
create policy "likes_select_auth" on public.likes for select using (auth.uid() is not null);
create policy "likes_insert_own" on public.likes for insert with check (user_id = auth.uid());
create policy "likes_delete_own" on public.likes for delete using (user_id = auth.uid());

-- ============ 公告与站点设置 ============
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) <= 120),
  content text not null check (char_length(content) <= 2000),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.site_settings (
  id int primary key default 1 check (id = 1),
  class_name text not null default '我们的班级',
  class_intro text not null default '青春档案 · 拾光纪念馆',
  bg_style text not null default 'aurora',
  invite_code text not null default ''
);
insert into public.site_settings (id) values (1) on conflict (id) do nothing;
alter table public.announcements enable row level security;
alter table public.site_settings enable row level security;
drop policy if exists "ann_read" on public.announcements;
drop policy if exists "ann_admin" on public.announcements;
drop policy if exists "site_read" on public.site_settings;
drop policy if exists "site_admin" on public.site_settings;
create policy "ann_read" on public.announcements for select using (auth.uid() is not null);
create policy "ann_admin" on public.announcements for all using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')));
create policy "site_read" on public.site_settings for select using (true);
create policy "site_admin" on public.site_settings for update using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','super_admin')));

-- ============ 照片存储桶（可选，v2 照片以 URL 为主） ============
insert into storage.buckets (id, name, public) values ('avatars','avatars', false)
on conflict (id) do nothing;
drop policy if exists "avatars_own_write" on storage.objects;
drop policy if exists "avatars_owner_read" on storage.objects;
create policy "avatars_own_write" on storage.objects for insert with check (
  bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_owner_read" on storage.objects for select using (
  bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
