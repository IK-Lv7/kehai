-- アカウント削除 (App Store 審査ガイドライン 5.1.1(v))。
-- auth.users の行を消すと、profiles / user_states / pairs / invites / taps は
-- on delete cascade で、まとめて消える。

create function public.delete_account()
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
  delete from auth.users where id = me;
end;
$$;

revoke execute on function public.delete_account() from public, anon, authenticated;
grant execute on function public.delete_account() to authenticated;
