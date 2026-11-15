-- EarnBridge Work Passport migration. Run once in the SAME Supabase project used by Garage Operations.
-- All objects are eb_-prefixed; no Garage Operations tables are read or changed.
create table if not exists public.eb_work_records (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 client_name text not null,
 client_email text,
 project_title text not null,
 work_description text not null,
 start_date date,
 completion_date date,
 agreed_amount numeric(14,2),
 currency text not null default 'KES',
 status text not null default 'in_progress' check(status in('in_progress','submitted','verified','disputed','cancelled')),
 evidence_url text,
 evidence_note text,
 customer_feedback text,
 customer_rating integer check(customer_rating between 1 and 5),
 verified_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists eb_work_records_owner_idx on public.eb_work_records(owner_id,created_at desc);
alter table public.eb_work_records enable row level security;
create policy eb_work_records_owner_select on public.eb_work_records for select to authenticated using(owner_id=auth.uid());
create policy eb_work_records_owner_insert on public.eb_work_records for insert to authenticated with check(owner_id=auth.uid());
create policy eb_work_records_owner_update on public.eb_work_records for update to authenticated using(owner_id=auth.uid() and status <> 'verified') with check(owner_id=auth.uid() and status <> 'verified');
create policy eb_work_records_owner_delete on public.eb_work_records for delete to authenticated using(owner_id=auth.uid() and status <> 'verified');
grant select,insert,update,delete on public.eb_work_records to authenticated;
