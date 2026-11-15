-- EarnBridge SaaS foundation. Run once AFTER supabase.sql, commerce-core.sql and work-passport.sql.
-- All objects are isolated with eb_ names. No Garage Operations objects are modified.

create table if not exists public.eb_plan_requests(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 requested_plan text not null check(requested_plan in('pro','business')),
 billing_cycle text not null default 'monthly' check(billing_cycle in('monthly','annual')),
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled')),
 note text,
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists eb_plan_requests_user_idx on public.eb_plan_requests(user_id,created_at desc);

create table if not exists public.eb_admins(
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null default 'admin' check(role in('admin','moderator','support')),
 created_at timestamptz not null default now()
);

create table if not exists public.eb_platform_settings(
 setting_key text primary key,
 setting_value jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);

create table if not exists public.eb_audit_log(
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references auth.users(id) on delete set null,
 action text not null,
 target_table text,
 target_id uuid,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists eb_audit_log_created_idx on public.eb_audit_log(created_at desc);

alter table public.eb_plan_requests enable row level security;
alter table public.eb_admins enable row level security;
alter table public.eb_platform_settings enable row level security;
alter table public.eb_audit_log enable row level security;

drop policy if exists eb_plan_requests_owner_read on public.eb_plan_requests;
create policy eb_plan_requests_owner_read on public.eb_plan_requests for select to authenticated using(user_id=auth.uid());
drop policy if exists eb_plan_requests_owner_insert on public.eb_plan_requests;
create policy eb_plan_requests_owner_insert on public.eb_plan_requests for insert to authenticated with check(user_id=auth.uid() and status='pending');
drop policy if exists eb_admins_self_read on public.eb_admins;
create policy eb_admins_self_read on public.eb_admins for select to authenticated using(user_id=auth.uid());
drop policy if exists eb_settings_admin_read on public.eb_platform_settings;
create policy eb_settings_admin_read on public.eb_platform_settings for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_settings_admin_write on public.eb_platform_settings;
create policy eb_settings_admin_write on public.eb_platform_settings for all to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role='admin')) with check(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role='admin'));
drop policy if exists eb_audit_admin_read on public.eb_audit_log;
create policy eb_audit_admin_read on public.eb_audit_log for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_audit_admin_insert on public.eb_audit_log;
create policy eb_audit_admin_insert on public.eb_audit_log for insert to authenticated with check(actor_id=auth.uid() and exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));

-- Admin-only access to operational records. Existing owner/participant policies remain in force.
drop policy if exists eb_admin_profiles_read on public.eb_profiles;
create policy eb_admin_profiles_read on public.eb_profiles for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_admin_businesses_read on public.eb_businesses;
create policy eb_admin_businesses_read on public.eb_businesses for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_admin_opportunities_read on public.eb_opportunities;
create policy eb_admin_opportunities_read on public.eb_opportunities for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_admin_opportunities_update on public.eb_opportunities;
create policy eb_admin_opportunities_update on public.eb_opportunities for update to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role in('admin','moderator'))) with check(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role in('admin','moderator')));
drop policy if exists eb_admin_reports_read on public.eb_reports;
create policy eb_admin_reports_read on public.eb_reports for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_admin_reports_update on public.eb_reports;
create policy eb_admin_reports_update on public.eb_reports for update to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role in('admin','moderator'))) with check(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role in('admin','moderator')));
drop policy if exists eb_admin_plan_requests_read on public.eb_plan_requests;
create policy eb_admin_plan_requests_read on public.eb_plan_requests for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_admin_plan_requests_update on public.eb_plan_requests;
create policy eb_admin_plan_requests_update on public.eb_plan_requests for update to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role='admin')) with check(exists(select 1 from public.eb_admins a where a.user_id=auth.uid() and a.role='admin'));
drop policy if exists eb_admin_subscriptions_read on public.eb_subscriptions;
create policy eb_admin_subscriptions_read on public.eb_subscriptions for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));
drop policy if exists eb_admin_payments_read on public.eb_payments;
create policy eb_admin_payments_read on public.eb_payments for select to authenticated using(exists(select 1 from public.eb_admins a where a.user_id=auth.uid()));

grant select,insert on public.eb_plan_requests to authenticated;
grant select on public.eb_admins,public.eb_platform_settings,public.eb_audit_log to authenticated;
grant insert on public.eb_audit_log to authenticated;
grant update on public.eb_platform_settings,public.eb_plan_requests,public.eb_opportunities,public.eb_reports to authenticated;
grant select on public.eb_profiles,public.eb_businesses to authenticated;
