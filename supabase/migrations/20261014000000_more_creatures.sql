-- 選べるいきものを増やす (いぬ・うさぎ・くま・ぺんぎん・きつね・ぶた・おばけ・スライム)。
-- 絵は character.json。古いアプリは知らないいきものを「まる」で表示する。

alter table public.profiles drop constraint profiles_creature_check;
alter table public.profiles add constraint profiles_creature_check check (creature in (
  'cat', 'frog', 'robot', 'chick',
  'dog', 'rabbit', 'bear', 'penguin', 'fox', 'pig', 'ghost', 'slime'
));
