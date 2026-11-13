-- שפע: things both phones share (tasks, shopping, budget limits, savings goals).
-- Run once in Supabase → SQL Editor, after schema.sql.

create table if not exists shared_items (
  id text primary key,
  kind text not null,                 -- list, goal, budget
  data jsonb not null default '{}',
  deleted boolean not null default false,
  updated_ms bigint not null default 0  -- when it was last changed on a phone
);

alter table shared_items enable row level security;

drop policy if exists "members manage shared items" on shared_items;
create policy "members manage shared items" on shared_items for all
  using (auth.uid() in (select user_id from household_members))
  with check (auth.uid() in (select user_id from household_members));
