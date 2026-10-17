-- 拾光班级纪念馆 Supabase 数据库初始化
-- 在 Supabase Dashboard -> SQL Editor 中完整运行一次。
-- 此脚本会创建 profiles、public_profiles 视图和私有照片桶。
-- 只在网页中使用 Project URL + anon/public key，绝不使用 service_role key。

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '新同学' check (char_length(display_name) <= 60),
  age int check (age is null or (age between 1 and 120)),
  personality text not null default '' check (char_length(personality) <= 120),
  bio text not null default '' check (char_length(bio) <= 1000),
  avatar_path text,
  profile_visibility text not null default 'private' check (profile_visibility in ('private','public')),
  show_age boolean not null default false,
  show_personality boolean not null default true,
  show_bio boolean not null default true,
  show_avatar boolean not null default true,
  theme text not null default 'violet' check (theme in ('violet','ocean','sunset')),
  is_admin boolean not null default false,
  is_banned boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$ select exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true and p.is_banned = false); $$;

-- 用户可读取自己的完整资料；管理员可读取全部资料。普通用户只能通过 public_profiles 视图看公开字段。
drop policy if exists "profiles_select_self_or_admin" on public.profiles;
create policy "profiles_select_self_or_admin" on public.profiles
for select to authenticated using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self" on public.profiles
for insert to authenticated with check (id = auth.uid() and is_admin = false and is_banned = false);

drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles
for update to authenticated
using (id = auth.uid() and is_banned = false)
with check (id = auth.uid() and is_admin = false and is_banned = false);

-- 安全视图：对外只显示公开主页，隐藏字段在数据库查询结果中即为 NULL。
-- 视图由表所有者执行，因此必须保持字段清单精简并用 CASE 明确过滤每项隐私字段。
create or replace view public.public_profiles
with (security_barrier = true)
as
select
  p.id,
  p.display_name,
  case when p.show_age then p.age else null end as age,
  case when p.show_personality then p.personality else null end as personality,
  case when p.show_bio then p.bio else null end as bio,
  case when p.show_avatar then p.avatar_path else null end as avatar_path,
  p.theme,
  p.created_at
from public.profiles p
where p.profile_visibility = 'public'
  and p.is_banned = false;

grant select on public.public_profiles to authenticated;

-- 仅管理员可以通过 RPC 修改封禁状态；普通用户不能直接修改 is_admin / is_banned。
create or replace function public.admin_set_banned(target_user_id uuid, ban_value boolean)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception '管理员权限不足';
  end if;
  if target_user_id = auth.uid() then
    raise exception '不能限制自己的账号';
  end if;
  update public.profiles set is_banned = ban_value where id = target_user_id;
end;
$$;
revoke all on function public.admin_set_banned(uuid, boolean) from public;
grant execute on function public.admin_set_banned(uuid, boolean) to authenticated;

-- 私有照片桶。文件路径必须为 用户UUID/文件名。
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('class-photos', 'class-photos', false, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "photo_upload_own_folder" on storage.objects;
create policy "photo_upload_own_folder" on storage.objects
for insert to authenticated
with check (bucket_id = 'class-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "photo_update_own_folder" on storage.objects;
create policy "photo_update_own_folder" on storage.objects
for update to authenticated
using (bucket_id = 'class-photos' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'class-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "photo_delete_own_folder" on storage.objects;
create policy "photo_delete_own_folder" on storage.objects
for delete to authenticated
using (bucket_id = 'class-photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

drop policy if exists "photo_read_allowed_profiles" on storage.objects;
create policy "photo_read_allowed_profiles" on storage.objects
for select to authenticated
using (
  bucket_id = 'class-photos' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
    or exists (
      select 1 from public.public_profiles pp
      where pp.id::text = (storage.foldername(name))[1]
        and pp.avatar_path = name
    )
  )
);

-- 注册后自动建立个人资料行。
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, display_name, profile_visibility)
  values (new.id, '新同学', 'private')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- 为普通用户明确限制可更新的字段。管理员状态仅由 SQL 编辑器/可信管理流程赋予。
revoke update on public.profiles from authenticated;
grant update (display_name, age, personality, bio, avatar_path, profile_visibility,
              show_age, show_personality, show_bio, show_avatar, theme)
on public.profiles to authenticated;
