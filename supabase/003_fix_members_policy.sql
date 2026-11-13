-- שפע: fixes the rule that lets a signed-in family member read the data.
-- The first version of this rule referred to itself, which made every read fail.
-- Run once in Supabase → SQL Editor.

drop policy if exists "members see members" on household_members;
drop policy if exists "members see themselves" on household_members;
create policy "members see themselves" on household_members for select
  using (user_id = auth.uid());

-- Makes sure the first user of the project, the one who set it up, belongs
-- to the household. Other family members are added one by one, never in bulk.
insert into household_members
  select id from auth.users order by created_at asc limit 1
  on conflict do nothing;
