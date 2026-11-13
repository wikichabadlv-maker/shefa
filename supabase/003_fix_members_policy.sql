-- שפע: fixes the rule that lets a signed-in family member read the data.
-- The first version of this rule referred to itself, which made every read fail.
-- Run once in Supabase → SQL Editor.

drop policy if exists "members see members" on household_members;
drop policy if exists "members see themselves" on household_members;
create policy "members see themselves" on household_members for select
  using (user_id = auth.uid());

-- Makes sure every user created so far belongs to the household.
insert into household_members select id from auth.users on conflict do nothing;
