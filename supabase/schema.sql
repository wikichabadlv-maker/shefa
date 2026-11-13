-- שפע: shared household database. Run once in Supabase → SQL Editor.
-- Bank rows are written only by the sync engine (service key). The app reads them
-- and keeps its own answers (category, items, notes) in transaction_details,
-- so a re-sync never overwrites what the family wrote.

create table if not exists bank_transactions (
  id text primary key,
  source text not null,              -- discount, max, max_2, visaCal ...
  company text not null,
  account text,                      -- last 4 digits only
  date date not null,
  processed_date date,
  amount numeric(12,2) not null,     -- negative = money out
  original_amount numeric(12,2),
  original_currency text default 'ILS',
  description text not null,
  memo text,
  status text not null default 'completed',
  installment_number int,
  installment_total int,
  bank_category text,
  reference text,
  synced_at timestamptz not null default now()
);
create index if not exists bank_transactions_date on bank_transactions (date desc);

create table if not exists transaction_details (
  transaction_id text primary key references bank_transactions(id) on delete cascade,
  kind text check (kind in ('expense','income','maaser','saving','transfer')),
  category text,
  sub_category text,
  items jsonb,                       -- [{name, qty, price}] from a receipt or an answer
  note text,
  splits jsonb,                      -- [{category, sub_category, amount}]
  answered_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists account_balances (
  id bigserial primary key,
  source text not null,
  account text,
  balance numeric(14,2) not null,
  as_of timestamptz not null default now()
);

create table if not exists sync_runs (
  id bigserial primary key,
  source text not null,
  ran_at timestamptz not null default now(),
  ok boolean not null,
  error_type text,
  count int not null default 0
);

-- Only signed-in members of the household can read; the app writes only its own details.
alter table bank_transactions enable row level security;
alter table transaction_details enable row level security;
alter table account_balances enable row level security;
alter table sync_runs enable row level security;

create table if not exists household_members (user_id uuid primary key);
alter table household_members enable row level security;

create policy "members read transactions" on bank_transactions for select
  using (auth.uid() in (select user_id from household_members));
create policy "members read balances" on account_balances for select
  using (auth.uid() in (select user_id from household_members));
create policy "members read runs" on sync_runs for select
  using (auth.uid() in (select user_id from household_members));
create policy "members manage details" on transaction_details for all
  using (auth.uid() in (select user_id from household_members))
  with check (auth.uid() in (select user_id from household_members));
create policy "members see themselves" on household_members for select
  using (user_id = auth.uid());
