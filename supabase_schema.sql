-- ============================================================
-- Kurd Sport — Owner Panel Backend (Supabase)
-- Run this ONCE in: Supabase Dashboard → SQL Editor
-- ============================================================

-- 1) Channels table (the live source of truth)
create table if not exists public.channels (
  id          bigint generated always as identity primary key,
  name        text not null,
  logo_url    text not null default '',
  category    text not null default 'Sports',
  stream_url  text not null,
  is_active   boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

-- Everyone can READ channels, nobody can write directly
alter table public.channels enable row level security;
drop policy if exists "public read channels" on public.channels;
create policy "public read channels"
  on public.channels for select
  using (true);
-- intentionally NO insert/update/delete policies for anon users

-- 2) Owner password
--    First set it in plain text below, run, then re-run with the hashed value
--    or just run once with your real password inside crypt().
create table if not exists public.owner_config (
  id int primary key default 1 check (id = 1),
  password_hash text not null
);
insert into public.owner_config (id, password_hash)
values (1, crypt('dk$qf8t8M6$NJGe', gen_salt('bf')))
on conflict (id) do nothing;

-- 3) Password check (used by the login form)
create or replace function public.owner_check_password(p_password text)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare h text;
begin
  select password_hash into h from public.owner_config where id = 1;
  return h is not null and h = crypt(p_password, h);
end $$;

-- 4) Secure write functions — only callable with the correct password
create or replace function public.owner_upsert_channel(
  p_password text,
  p_id bigint,
  p_name text,
  p_stream_url text,
  p_logo_url text default '',
  p_category text default 'Sports',
  p_is_active boolean default true,
  p_sort_order int default 0
)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare result jsonb;
begin
  if not public.owner_check_password(p_password) then
    raise exception 'Invalid owner password';
  end if;
  if p_id is null then
    insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
    values (p_name, p_stream_url, p_logo_url, p_category, p_is_active, p_sort_order)
    returning to_jsonb(public.channels.*) into result;
  else
    update public.channels
       set name = p_name, stream_url = p_stream_url, logo_url = p_logo_url,
           category = p_category, is_active = p_is_active, sort_order = p_sort_order
     where id = p_id
    returning to_jsonb(public.channels.*) into result;
  end if;
  return result;
end $$;

create or replace function public.owner_delete_channel(p_password text, p_id bigint)
returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.owner_check_password(p_password) then
    raise exception 'Invalid owner password';
  end if;
  delete from public.channels where id = p_id;
  return true;
end $$;

-- 5) Realtime: push changes to all visitors instantly
alter publication supabase_realtime add table public.channels;

-- 6) Allow anon to call the functions (the password check protects them)
grant execute on function public.owner_check_password(text)    to anon;
grant execute on function public.owner_upsert_channel(text,bigint,text,text,text,text,boolean,int) to anon;
grant execute on function public.owner_delete_channel(text,bigint) to anon;

-- ============================================================
-- 7) Site-wide broadcast commands (e.g. "force reload all visitors")
--    Owner inserts a command; every open browser receives it live.
-- ============================================================
create table if not exists public.site_commands (
  id          bigint generated always as identity primary key,
  command     text not null,               -- e.g. 'reload'
  payload     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

alter table public.site_commands enable row level security;
-- no policies: anon cannot read/write directly

create or replace function public.owner_broadcast_command(p_password text, p_command text)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare new_id bigint;
begin
  if not public.owner_check_password(p_password) then
    raise exception 'Invalid owner password';
  end if;
  insert into public.site_commands (command) values (p_command) returning id into new_id;
  return new_id;
end $$;

alter publication supabase_realtime add table public.site_commands;
grant execute on function public.owner_broadcast_command(text, text) to anon;

-- ============================================================
-- 8) Pre-seeded channels (imported from your current website)
--    Safe to re-run: skips any channel that already exists by name.
-- ============================================================
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Biner TV', 'https://lbgo.bozztv.com/ssh101/live/biner-zaxo/playlist.m3u8', 'https://kurdsport.online/binertv.png', 'Kurdish Sports', true, 0
where not exists (select 1 from public.channels where name = 'Biner TV');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'AVA Sport', 'http://avrstream.com:1935/live/AvaSport/tracks-v1a1/mono.m3u8', 'https://kurdsport.online/ava-sport.png', 'Kurdish Sports', true, 1
where not exists (select 1 from public.channels where name = 'AVA Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'NRT Sport', 'http://m3u.drm-26.com/live/Mkdtv1_061261/4STJysUc/280437.m3u8', 'https://kurdsport.online/nrt1-sport.png', 'Kurdish Sports', true, 2
where not exists (select 1 from public.channels where name = 'NRT Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Dasinya Sport', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/689911.m3u8', 'https://kurdsport.online/dasinyasport.png', 'Kurdish Sports', true, 3
where not exists (select 1 from public.channels where name = 'Dasinya Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'LD Sport', 'http://m3u.drm-26.com/live/Mkdtv1_061261/4STJysUc/280502.m3u8', 'https://kurdsport.online/ldsport.png', 'Kurdish Sports', true, 4
where not exists (select 1 from public.channels where name = 'LD Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Duhok Sport', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/689913.m3u8', 'https://kurdsport.online/duhoksport.png', 'Kurdish Sports', true, 5
where not exists (select 1 from public.channels where name = 'Duhok Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Zaxo Sport', 'http://m3u.drm-26.com/live/Mkdtv1_061261/4STJysUc/280431.m3u8', 'https://kurdsport.online/zaxosport.png', 'Kurdish Sports', true, 6
where not exists (select 1 from public.channels where name = 'Zaxo Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Astera Sport', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/689910.m3u8', 'https://kurdsport.online/asterasport1.png', 'Kurdish Sports', true, 7
where not exists (select 1 from public.channels where name = 'Astera Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Aso Sport', 'http://m3u.drm-26.com/live/Mkdtv1_061261/4STJysUc/456256.m3u8', 'https://kurdsport.online/asosport.png', 'Kurdish Sports', true, 8
where not exists (select 1 from public.channels where name = 'Aso Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Gewher Sport', 'https://cdn.karwan.tv/gewher-sport/index.m3u8', 'https://kurdsport.online/gewhersport.png', 'Kurdish Sports', true, 9
where not exists (select 1 from public.channels where name = 'Gewher Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 1', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/110.m3u8', 'https://kurdsport.online/beinsport1.png', 'BeIN Sports', true, 10
where not exists (select 1 from public.channels where name = 'Bein Sport 1');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 2', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/111.m3u8', 'https://kurdsport.online/beinsport2.png', 'BeIN Sports', true, 11
where not exists (select 1 from public.channels where name = 'Bein Sport 2');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 3', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/112.m3u8', 'https://kurdsport.online/beinsport3.png', 'BeIN Sports', true, 12
where not exists (select 1 from public.channels where name = 'Bein Sport 3');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 4', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/113.m3u8', 'https://kurdsport.online/beinsport4.png', 'BeIN Sports', true, 13
where not exists (select 1 from public.channels where name = 'Bein Sport 4');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 5', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/114.m3u8', 'https://kurdsport.online/beinsport5.png', 'BeIN Sports', true, 14
where not exists (select 1 from public.channels where name = 'Bein Sport 5');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 6', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/115.m3u8', 'https://kurdsport.online/beinsport6.png', 'BeIN Sports', true, 15
where not exists (select 1 from public.channels where name = 'Bein Sport 6');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 7', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/116.m3u8', 'https://kurdsport.online/beinsport7.png', 'BeIN Sports', true, 16
where not exists (select 1 from public.channels where name = 'Bein Sport 7');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 8', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/117.m3u8', 'https://kurdsport.online/beinsport8.png', 'BeIN Sports', true, 17
where not exists (select 1 from public.channels where name = 'Bein Sport 8');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Bein Sport 9', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/118.m3u8', 'https://kurdsport.online/beinsport9.png', 'BeIN Sports', true, 18
where not exists (select 1 from public.channels where name = 'Bein Sport 9');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 1', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641618.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 19
where not exists (select 1 from public.channels where name = 'Alwan Sport 1');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 2', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641619.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 20
where not exists (select 1 from public.channels where name = 'Alwan Sport 2');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 3', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641620.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 21
where not exists (select 1 from public.channels where name = 'Alwan Sport 3');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 4', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641621.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 22
where not exists (select 1 from public.channels where name = 'Alwan Sport 4');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 5', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641622.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 23
where not exists (select 1 from public.channels where name = 'Alwan Sport 5');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 6', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641623.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 24
where not exists (select 1 from public.channels where name = 'Alwan Sport 6');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 7', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641611.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 25
where not exists (select 1 from public.channels where name = 'Alwan Sport 7');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 8', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641612.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 26
where not exists (select 1 from public.channels where name = 'Alwan Sport 8');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 9', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641613.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 27
where not exists (select 1 from public.channels where name = 'Alwan Sport 9');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport 10', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641614.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 28
where not exists (select 1 from public.channels where name = 'Alwan Sport 10');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport F1', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641616.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 29
where not exists (select 1 from public.channels where name = 'Alwan Sport F1');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport UFC', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641615.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 30
where not exists (select 1 from public.channels where name = 'Alwan Sport UFC');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Alwan Sport WWE', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/1641617.m3u8', 'https://kurdsport.online/Alwan-sport.png', 'Alwan Sports', true, 31
where not exists (select 1 from public.channels where name = 'Alwan Sport WWE');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'AD Sport 1', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/200.m3u8', 'https://kurdsport.online/abudhabi1.png', 'Starzplay Sports', true, 32
where not exists (select 1 from public.channels where name = 'AD Sport 1');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'AD Sport 2', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/201.m3u8', 'https://kurdsport.online/abudhabi2.png', 'Starzplay Sports', true, 33
where not exists (select 1 from public.channels where name = 'AD Sport 2');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Starzplay Sport 1', 'http://m3u.drm-26.com/live/Mkdtv1_061261/4STJysUc/1173275.m3u8', 'https://kurdsport.online/starzsport.png', 'Starzplay Sports', true, 34
where not exists (select 1 from public.channels where name = 'Starzplay Sport 1');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Starzplay Sport 2', 'http://xtreamutv.org:80/live/pvVrD1gEuh/Wty1TYowId/205.m3u8', 'https://kurdsport.online/starzsport.png', 'Starzplay Sports', true, 35
where not exists (select 1 from public.channels where name = 'Starzplay Sport 2');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Starzplay Sport 3', 'http://m3u.drm-26.com/live/Mkdtv1_061261/4STJysUc/252720.m3u8', 'https://kurdsport.online/starzsport.png', 'Starzplay Sports', true, 36
where not exists (select 1 from public.channels where name = 'Starzplay Sport 3');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'ToFi Sport 1', 'https://cdn.gamhed.online/hls/bein1.m3u8', 'https://kurdsport.online/tofisports.png', 'Tofi Sports', true, 37
where not exists (select 1 from public.channels where name = 'ToFi Sport 1');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'ToFi Sport 2', 'https://cdn.gamhed.online/hls/bein2.m3u8', 'https://kurdsport.online/tofisports.png', 'Tofi Sports', true, 38
where not exists (select 1 from public.channels where name = 'ToFi Sport 2');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Al Iraqya Sport', 'http://m3u.drm-26.com:80/live/Mkdtv1_061261/4STJysUc/14284.m3u8', 'https://kurdsport.online/aliraq.png', 'Global Sports', true, 39
where not exists (select 1 from public.channels where name = 'Al Iraqya Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'GEM Sport', 'https://northtelecom.b-cdn.net/GEMSPORTHD/1_1001_Video.m3u8', 'https://kurdsport.online/gemsport.png', 'Global Sports', true, 40
where not exists (select 1 from public.channels where name = 'GEM Sport');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'Arda Spor', 'https://ladyboy.yedektv.cfd//hls/bein1.m3u8', 'https://kurdsport.online/ardaspor.png', 'Global Sports', true, 41
where not exists (select 1 from public.channels where name = 'Arda Spor');
insert into public.channels (name, stream_url, logo_url, category, is_active, sort_order)
select 'TNT Sport', 'http://195.178.110.110/tntsports/index.m3u8', 'https://kurdsport.online/tntsport.png', 'Global Sports', true, 42
where not exists (select 1 from public.channels where name = 'TNT Sport');
