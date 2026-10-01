-- Kehai 初期スキーマ。
-- 方針: テーブルは直接書き換えさせず、相手の情報は get_partner_states() 経由でだけ読む。

-- ---------------------------------------------------------------- テーブル

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 20),
  color text not null default '#F2917B' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  character_style text not null default 'maru' check (character_style in ('maru', 'dot')),
  creature text not null default 'cat' check (creature in ('cat', 'frog', 'robot', 'chick')),
  created_at timestamptz not null default now()
);

-- 「寝てる」は保存しない。見る側が、就寝時間帯・充電・更新時刻から推測する。
create table public.user_states (
  user_id uuid primary key references auth.users (id) on delete cascade,
  is_charging boolean not null default false,
  battery_level smallint check (battery_level between 0 and 100),
  is_working boolean not null default false,
  sleep_start time not null default '23:00',
  sleep_end time not null default '07:00',
  -- 就寝時間帯は本人の現地時間なので、見る側が換算できるよう UTC との差(分)を持つ。
  utc_offset_minutes smallint not null default 540 check (utc_offset_minutes between -840 and 840),
  updated_at timestamptz not null default now()
);

-- user_a < user_b に正規化して、同じ組を2行持たないようにする。
create table public.pairs (
  user_a uuid not null references auth.users (id) on delete cascade,
  user_b uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index pairs_user_b_idx on public.pairs (user_b);

create table public.invites (
  code text primary key,
  inviter_id uuid not null references auth.users (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '3 days',
  used_at timestamptz,
  used_by uuid references auth.users (id) on delete set null
);
create index invites_inviter_idx on public.invites (inviter_id);

create table public.taps (
  id bigint generated always as identity primary key,
  sender_id uuid not null references auth.users (id) on delete cascade,
  receiver_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index taps_sender_receiver_idx on public.taps (sender_id, receiver_id, created_at desc);
create index taps_receiver_idx on public.taps (receiver_id, created_at desc);

-- ---------------------------------------------------------------- 権限と RLS

alter table public.profiles enable row level security;
alter table public.user_states enable row level security;
alter table public.pairs enable row level security;
alter table public.invites enable row level security;
alter table public.taps enable row level security;

revoke all on public.profiles, public.user_states, public.pairs, public.invites, public.taps
  from anon, authenticated;

-- 自分の行だけ、読み書きできる。
grant select, update on public.profiles to authenticated;
create policy profiles_own_select on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_own_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

grant select, insert, update on public.user_states to authenticated;
create policy user_states_own_select on public.user_states
  for select to authenticated using (user_id = (select auth.uid()));
create policy user_states_own_insert on public.user_states
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy user_states_own_update on public.user_states
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ペアは自分が含まれるものだけ読める。作成・削除は関数経由。
grant select on public.pairs to authenticated;
create policy pairs_own_select on public.pairs
  for select to authenticated
  using (user_a = (select auth.uid()) or user_b = (select auth.uid()));

-- 招待は関数経由でだけ扱う(ポリシー無し = 直接は何も見えない)。

-- トントンは自分が送った・受け取ったものだけ読める。送信は send_tap() 経由。
grant select on public.taps to authenticated;
create policy taps_own_select on public.taps
  for select to authenticated
  using (sender_id = (select auth.uid()) or receiver_id = (select auth.uid()));

-- ---------------------------------------------------------------- トリガー

-- サインアップ時に、プロフィールと状態の行を作る。
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  insert into public.user_states (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- updated_at は、クライアントの値を信用せず、サーバーの時刻で上書きする。
create function public.touch_user_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger user_states_touch
  before insert or update on public.user_states
  for each row execute function public.touch_user_state();

-- ---------------------------------------------------------------- 関数

-- 招待コード(例: KEHAI-4F7Q2X)を作る。3日で期限切れ。1人につき有効なコードは1つ。
create function public.create_invite()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  suffix text;
  new_code text;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  delete from public.invites where inviter_id = me and used_at is null;

  loop
    suffix := '';
    for i in 1..6 loop
      suffix := suffix || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    new_code := 'KEHAI-' || suffix;
    begin
      insert into public.invites (code, inviter_id) values (new_code, me);
      return new_code;
    exception when unique_violation then
      null; -- 衝突したら作り直す
    end;
  end loop;
end;
$$;

-- 招待コードでつながる。相手の user_id を返す。1回で失効。1人あたり最大4人まで。
create function public.redeem_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  inv public.invites;
  a uuid;
  b uuid;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into inv from public.invites
    where code = upper(trim(p_code)) for update;

  if not found or inv.used_at is not null or inv.expires_at <= now() then
    raise exception 'invalid_or_expired_code' using errcode = 'P0001';
  end if;
  if inv.inviter_id = me then
    raise exception 'cannot_pair_with_self' using errcode = 'P0001';
  end if;

  a := least(me, inv.inviter_id);
  b := greatest(me, inv.inviter_id);

  if exists (select 1 from public.pairs where user_a = a and user_b = b) then
    raise exception 'already_paired' using errcode = 'P0001';
  end if;
  if (select count(*) from public.pairs where user_a = me or user_b = me) >= 4
     or (select count(*) from public.pairs where user_a = inv.inviter_id or user_b = inv.inviter_id) >= 4 then
    raise exception 'too_many_partners' using errcode = 'P0001';
  end if;

  insert into public.pairs (user_a, user_b) values (a, b);
  update public.invites set used_at = now(), used_by = me where code = inv.code;
  return inv.inviter_id;
end;
$$;

-- つながりを解除する。
create function public.remove_pair(p_partner uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.pairs
  where user_a = least(auth.uid(), p_partner) and user_b = greatest(auth.uid(), p_partner);
$$;

-- つながっている相手の、表示に必要な最小限の情報だけを返す。
create function public.get_partner_states()
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
         s.is_charging, s.battery_level, s.is_working,
         s.sleep_start, s.sleep_end, s.utc_offset_minutes, s.updated_at
  from public.pairs pr
  join public.profiles p
    on p.id = case when pr.user_a = auth.uid() then pr.user_b else pr.user_a end
  join public.user_states s on s.user_id = p.id
  where auth.uid() in (pr.user_a, pr.user_b)
  order by pr.created_at;
$$;

-- トントンを送る。つながっている相手にだけ、同じ相手へは3秒に1回まで。
create function public.send_tap(p_receiver uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  new_id bigint;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (
    select 1 from public.pairs
    where user_a = least(me, p_receiver) and user_b = greatest(me, p_receiver)
  ) then
    raise exception 'not_paired' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.taps
    where sender_id = me and receiver_id = p_receiver
      and created_at > now() - interval '3 seconds'
  ) then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  insert into public.taps (sender_id, receiver_id) values (me, p_receiver)
  returning id into new_id;
  return new_id;
end;
$$;

-- 関数は、ログイン済みのユーザーだけが呼べる。
revoke execute on function
  public.create_invite(), public.redeem_invite(text), public.remove_pair(uuid),
  public.get_partner_states(), public.send_tap(uuid),
  public.handle_new_user(), public.touch_user_state()
  from public, anon, authenticated;
grant execute on function
  public.create_invite(), public.redeem_invite(text), public.remove_pair(uuid),
  public.get_partner_states(), public.send_tap(uuid)
  to authenticated;
