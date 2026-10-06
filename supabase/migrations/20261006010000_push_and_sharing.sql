-- トントンのプッシュ通知と、相手ごとに「見せる情報」を選ぶ設定。

-- ---------------------------------------------------------------- 通知の設定

alter table public.profiles add column receive_taps boolean not null default true;

-- 端末のプッシュ通知トークン。直接は読み書きさせず、関数経由で扱う。
create table public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;

-- 同じ端末で別のアカウントにログインし直しても、通知は今のアカウントにだけ届く。
create function public.register_device_token(p_token text, p_environment text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  insert into public.device_tokens (token, user_id, environment)
  values (p_token, auth.uid(), p_environment)
  on conflict (token) do update
    set user_id = excluded.user_id,
        environment = excluded.environment,
        updated_at = now();
end;
$$;

create function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;

-- ---------------------------------------------------------------- 見せる情報

-- 相手(viewer)ごとに、自分(owner)のどの情報を見せるか。行が無ければ、すべて見せる。
create table public.share_settings (
  owner_id uuid not null references auth.users (id) on delete cascade,
  viewer_id uuid not null references auth.users (id) on delete cascade,
  share_charging boolean not null default true,
  share_working boolean not null default true,
  share_sleep boolean not null default true,
  primary key (owner_id, viewer_id)
);
create index share_settings_viewer_idx on public.share_settings (viewer_id);

alter table public.share_settings enable row level security;
revoke all on public.share_settings from anon, authenticated;

create function public.get_share_settings()
returns table (viewer_id uuid, share_charging boolean, share_working boolean, share_sleep boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select s.viewer_id, s.share_charging, s.share_working, s.share_sleep
  from public.share_settings s
  where s.owner_id = auth.uid();
$$;

create function public.set_share_settings(
  p_viewer uuid,
  p_charging boolean,
  p_working boolean,
  p_sleep boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.pairs
    where user_a = least(me, p_viewer) and user_b = greatest(me, p_viewer)
  ) then
    raise exception 'not_paired' using errcode = 'P0001';
  end if;
  insert into public.share_settings (owner_id, viewer_id, share_charging, share_working, share_sleep)
  values (me, p_viewer, p_charging, p_working, p_sleep)
  on conflict (owner_id, viewer_id) do update
    set share_charging = excluded.share_charging,
        share_working = excluded.share_working,
        share_sleep = excluded.share_sleep;
end;
$$;

-- つながりを解除したら、見せる設定も消す (つなぎ直したときは、初期値に戻る)。
create or replace function public.remove_pair(p_partner uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  delete from public.pairs
  where user_a = least(me, p_partner) and user_b = greatest(me, p_partner);
  delete from public.share_settings
  where (owner_id = me and viewer_id = p_partner) or (owner_id = p_partner and viewer_id = me);
end;
$$;

-- 相手が「見せない」にした項目は、ここで隠す (アプリ側の表示ではなく、サーバーで守る)。
-- 充電・バッテリーを隠すと「充電中」にならず、就寝時間帯を隠すと「寝てる」にならない。
create or replace function public.get_partner_states()
returns table (
  partner_id uuid,
  display_name text,
  color text,
  character_style text,
  creature text,
  is_charging boolean,
  battery_level smallint,
  is_working boolean,
  sleep_start time,
  sleep_end time,
  utc_offset_minutes smallint,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.display_name, p.color, p.character_style, p.creature,
         case when coalesce(ss.share_charging, true) then s.is_charging else false end,
         case when coalesce(ss.share_charging, true) then s.battery_level else null end,
         case when coalesce(ss.share_working, true) then s.is_working else false end,
         case when coalesce(ss.share_sleep, true) then s.sleep_start else '00:00'::time end,
         case when coalesce(ss.share_sleep, true) then s.sleep_end else '00:00'::time end,
         s.utc_offset_minutes, s.updated_at
  from public.pairs pr
  join public.profiles p
    on p.id = case when pr.user_a = auth.uid() then pr.user_b else pr.user_a end
  join public.user_states s on s.user_id = p.id
  left join public.share_settings ss on ss.owner_id = p.id and ss.viewer_id = auth.uid()
  where auth.uid() in (pr.user_a, pr.user_b)
  order by pr.created_at;
$$;

-- ---------------------------------------------------------------- トントンの通知

-- taps への INSERT をきっかけに、Edge Function (send-tap-push) を呼ぶ。
-- 呼び出しの合言葉は Vault の push_webhook_secret。無ければ何もしない (トントン自体は成功させる)。
create extension if not exists pg_net with schema extensions;

create function public.notify_tap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  secret text;
begin
  select decrypted_secret into secret
  from vault.decrypted_secrets where name = 'push_webhook_secret';
  if secret is null then
    return new;
  end if;
  perform net.http_post(
    url := 'https://kjbyetjgiqmkybwwtcmt.supabase.co/functions/v1/send-tap-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    body := jsonb_build_object('sender_id', new.sender_id, 'receiver_id', new.receiver_id)
  );
  return new;
exception when others then
  return new;
end;
$$;

create trigger on_tap_created
  after insert on public.taps
  for each row execute function public.notify_tap();

-- ---------------------------------------------------------------- 権限

revoke execute on function
  public.register_device_token(text, text), public.unregister_device_token(text),
  public.get_share_settings(), public.set_share_settings(uuid, boolean, boolean, boolean),
  public.notify_tap()
  from public, anon, authenticated;
grant execute on function
  public.register_device_token(text, text), public.unregister_device_token(text),
  public.get_share_settings(), public.set_share_settings(uuid, boolean, boolean, boolean)
  to authenticated;
