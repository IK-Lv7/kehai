-- あいさつの種類 (トントン・おはよう・おつかれ・おやすみ) と、トントンの履歴・既読。
-- 古いアプリが呼ぶ send_tap(uuid) はそのまま残す (種類は tonton になる)。

alter table public.taps
  add column kind text not null default 'tonton'
    check (kind in ('tonton', 'ohayo', 'otsukare', 'oyasumi')),
  add column seen_at timestamptz;

-- 種類つきで送る。つながっている相手にだけ、同じ相手へは3秒に1回まで (send_tap と同じ)。
create function public.send_tap_with_kind(p_receiver uuid, p_kind text)
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

  insert into public.taps (sender_id, receiver_id, kind) values (me, p_receiver, p_kind)
  returning id into new_id;
  return new_id;
end;
$$;

-- 直近7日の、今つながっている相手とのやりとり (新しい順、最大50件)。
create function public.get_recent_taps()
returns table (
  id bigint,
  partner_id uuid,
  is_mine boolean,
  kind text,
  created_at timestamptz,
  seen_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id,
         case when t.sender_id = auth.uid() then t.receiver_id else t.sender_id end,
         t.sender_id = auth.uid(),
         t.kind, t.created_at, t.seen_at
  from public.taps t
  join public.pairs p
    on p.user_a = least(t.sender_id, t.receiver_id)
   and p.user_b = greatest(t.sender_id, t.receiver_id)
  where auth.uid() in (t.sender_id, t.receiver_id)
    and t.created_at > now() - interval '7 days'
  order by t.created_at desc
  limit 50;
$$;

-- 自分に届いたものを、見たことにする (送った側に「見た」と出る)。
create function public.mark_taps_seen()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.taps set seen_at = now()
  where receiver_id = auth.uid() and seen_at is null;
$$;

-- 通知の文面を種類で変えられるよう、種類も Edge Function に渡す。
create or replace function public.notify_tap()
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
    body := jsonb_build_object('sender_id', new.sender_id, 'receiver_id', new.receiver_id, 'kind', new.kind)
  );
  return new;
exception when others then
  return new;
end;
$$;

revoke execute on function
  public.send_tap_with_kind(uuid, text), public.get_recent_taps(), public.mark_taps_seen()
  from public, anon, authenticated;
grant execute on function
  public.send_tap_with_kind(uuid, text), public.get_recent_taps(), public.mark_taps_seen()
  to authenticated;
