-- EarnBridge verified job proof: customer-email confirmation and immutable verification events.
-- Run after supabase.sql, commerce-core.sql, work-passport.sql and saas-core.sql.
begin;

create extension if not exists pgcrypto;

create table if not exists public.eb_work_confirmations (
  id uuid primary key default gen_random_uuid(),
  record_id uuid not null references public.eb_work_records(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  customer_email text not null,
  token_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  decision text check (decision in ('confirmed','rejected')),
  feedback text,
  rating integer check (rating between 1 and 5),
  created_at timestamptz not null default now()
);

create table if not exists public.eb_work_verification_events (
  id uuid primary key default gen_random_uuid(),
  record_id uuid not null references public.eb_work_records(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in ('created','confirmation_requested','customer_confirmed','customer_rejected','verification_reset')),
  actor_type text not null check (actor_type in ('worker','customer','system')),
  actor_email text,
  notes text,
  created_at timestamptz not null default now()
);

-- Clear legacy verified labels because the previous version allowed workers to set them themselves.
-- Existing records return to pending/self-reported status until a customer confirms by email.
insert into public.eb_work_verification_events(record_id, owner_id, event_type, actor_type, notes)
select id, owner_id, 'verification_reset', 'system',
       'Legacy verified status cleared during secure customer-confirmation rollout.'
from public.eb_work_records where status = 'verified';

update public.eb_work_records
set status = 'submitted', verified_at = null, customer_feedback = null,
    customer_rating = null, updated_at = now()
where status = 'verified';

create index if not exists eb_work_confirmations_record_idx on public.eb_work_confirmations(record_id, created_at desc);
create index if not exists eb_work_events_owner_idx on public.eb_work_verification_events(owner_id, created_at desc);

alter table public.eb_work_confirmations enable row level security;
alter table public.eb_work_verification_events enable row level security;

drop policy if exists eb_work_confirmations_owner_read on public.eb_work_confirmations;
create policy eb_work_confirmations_owner_read on public.eb_work_confirmations
 for select to authenticated using (owner_id = auth.uid());

drop policy if exists eb_work_events_owner_read on public.eb_work_verification_events;
create policy eb_work_events_owner_read on public.eb_work_verification_events
 for select to authenticated using (owner_id = auth.uid());

-- Remove broad table privileges and re-grant only editable work-record columns.
drop policy if exists eb_work_records_owner_insert on public.eb_work_records;
drop policy if exists eb_work_records_owner_update on public.eb_work_records;
drop policy if exists eb_work_records_owner_delete on public.eb_work_records;

revoke insert, update, delete on public.eb_work_records from authenticated;
grant select on public.eb_work_records to authenticated;
grant insert (owner_id, client_name, client_email, project_title, work_description, start_date, completion_date, agreed_amount, currency, evidence_url, evidence_note)
 on public.eb_work_records to authenticated;
grant update (client_name, client_email, project_title, work_description, start_date, completion_date, agreed_amount, currency, evidence_url, evidence_note)
 on public.eb_work_records to authenticated;
grant delete on public.eb_work_records to authenticated;

create policy eb_work_records_owner_insert on public.eb_work_records
 for insert to authenticated with check (owner_id = auth.uid() and status = 'in_progress' and verified_at is null);
create policy eb_work_records_owner_update on public.eb_work_records
 for update to authenticated using (owner_id = auth.uid() and status <> 'verified')
 with check (owner_id = auth.uid() and status <> 'verified' and verified_at is null);
create policy eb_work_records_owner_delete on public.eb_work_records
 for delete to authenticated using (owner_id = auth.uid() and status <> 'verified');

-- Customer confirmation links are issued only by the trusted Edge Function using the service role.
create or replace function public.eb_issue_work_confirmation(p_record_id uuid)
returns table(token text, customer_email text, project_title text)
language plpgsql
security definer
set search_path = public, extensions
as $
declare
  v_record public.eb_work_records%rowtype;
  v_token text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Not authorised';
  end if;

  select * into v_record from public.eb_work_records where id = p_record_id for update;
  if not found then raise exception 'Work record not found'; end if;
  if v_record.client_email is null or btrim(v_record.client_email) = '' then
    raise exception 'A customer email address is required';
  end if;
  if v_record.status = 'verified' then raise exception 'This work record is already verified'; end if;
  if v_record.status = 'disputed' then raise exception 'This work record is disputed'; end if;

  update public.eb_work_confirmations
    set consumed_at = now()
    where record_id = p_record_id and consumed_at is null;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.eb_work_confirmations(record_id, owner_id, customer_email, token_hash, expires_at)
    values (v_record.id, v_record.owner_id, lower(v_record.client_email), encode(digest(v_token, 'sha256'), 'hex'), now() + interval '7 days');

  update public.eb_work_records set status = 'submitted', updated_at = now()
    where id = p_record_id;

  insert into public.eb_work_verification_events(record_id, owner_id, event_type, actor_type, actor_email, notes)
    values (v_record.id, v_record.owner_id, 'confirmation_requested', 'worker', lower(v_record.client_email), 'Customer confirmation email requested.');

  return query select v_token, lower(v_record.client_email), v_record.project_title;
end;
$$;

revoke all on function public.eb_issue_work_confirmation(uuid) from public, anon, authenticated;
grant execute on function public.eb_issue_work_confirmation(uuid) to service_role;

-- The customer link is single-use, expires after seven days and never exposes the token hash.
create or replace function public.eb_confirm_work_record(
  p_token text,
  p_decision text,
  p_feedback text default null,
  p_rating integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $
declare
  v_confirmation public.eb_work_confirmations%rowtype;
  v_status text;
begin
  if p_decision not in ('confirmed','rejected') then
    raise exception 'Invalid confirmation decision';
  end if;
  if p_rating is not null and (p_rating < 1 or p_rating > 5) then
    raise exception 'Rating must be between 1 and 5';
  end if;
  if p_token is null or length(p_token) < 40 then raise exception 'Invalid or expired link'; end if;

  select * into v_confirmation
    from public.eb_work_confirmations
    where token_hash = encode(digest(p_token, 'sha256'), 'hex')
    for update;

  if not found or v_confirmation.consumed_at is not null or v_confirmation.expires_at < now() then
    raise exception 'This confirmation link is invalid, expired or already used';
  end if;

  v_status := case when p_decision = 'confirmed' then 'verified' else 'disputed' end;

  update public.eb_work_confirmations
    set consumed_at = now(), decision = p_decision,
        feedback = nullif(left(coalesce(p_feedback,''),1000),''),
        rating = p_rating
    where id = v_confirmation.id;

  update public.eb_work_records
    set status = v_status,
        verified_at = case when p_decision = 'confirmed' then now() else null end,
        customer_feedback = nullif(left(coalesce(p_feedback,''),1000),''),
        customer_rating = p_rating,
        updated_at = now()
    where id = v_confirmation.record_id and owner_id = v_confirmation.owner_id
      and status = 'submitted';

  if not found then raise exception 'Work record is no longer awaiting confirmation'; end if;

  insert into public.eb_work_verification_events(record_id, owner_id, event_type, actor_type, actor_email, notes)
    values (v_confirmation.record_id, v_confirmation.owner_id,
      case when p_decision = 'confirmed' then 'customer_confirmed' else 'customer_rejected' end,
      'customer', v_confirmation.customer_email,
      nullif(left(coalesce(p_feedback,''),1000),''));

  return jsonb_build_object('success', true, 'decision', p_decision);
end;
$$;

revoke all on function public.eb_confirm_work_record(text,text,text,integer) from public;
grant execute on function public.eb_confirm_work_record(text,text,text,integer) to anon, authenticated;

-- Private evidence bucket. Files are stored under <auth.uid()>/<random filename>.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('eb-work-evidence','eb-work-evidence',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false, file_size_limit=10485760,
  allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists eb_work_evidence_owner_insert on storage.objects;
create policy eb_work_evidence_owner_insert on storage.objects
 for insert to authenticated with check (
   bucket_id='eb-work-evidence' and (storage.foldername(name))[1]=auth.uid()::text
 );
drop policy if exists eb_work_evidence_owner_select on storage.objects;
create policy eb_work_evidence_owner_select on storage.objects
 for select to authenticated using (
   bucket_id='eb-work-evidence' and (storage.foldername(name))[1]=auth.uid()::text
 );
drop policy if exists eb_work_evidence_owner_delete on storage.objects;
create policy eb_work_evidence_owner_delete on storage.objects
 for delete to authenticated using (
   bucket_id='eb-work-evidence' and (storage.foldername(name))[1]=auth.uid()::text
 );

grant select on public.eb_work_confirmations, public.eb_work_verification_events to authenticated;


-- Public passport endpoint exposes only approved professional information and confirmed jobs.
create or replace function public.eb_get_public_passport(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id', p.id,
      'full_name', p.full_name,
      'headline', p.headline,
      'bio', p.bio,
      'city', p.city,
      'country', p.country,
      'website_url', p.website_url
    ),
    'skills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'skill_name', s.skill_name,
        'skill_level', s.skill_level,
        'years_experience', s.years_experience
      ) order by s.skill_name)
      from public.eb_skills s where s.user_id = p.id
    ), '[]'::jsonb),
    'verified_work', coalesce((
      select jsonb_agg(jsonb_build_object(
        'project_title', w.project_title,
        'work_description', w.work_description,
        'completion_date', w.completion_date,
        'verified_at', w.verified_at,
        'customer_rating', w.customer_rating
      ) order by coalesce(w.completion_date, w.verified_at::date) desc)
      from public.eb_work_records w
      where w.owner_id = p.id and w.status = 'verified' and w.verified_at is not null
    ), '[]'::jsonb)
  )
  into v_result
  from public.eb_profiles p
  where p.id = p_user_id and p.profile_visibility = 'public';

  if v_result is null then
    return jsonb_build_object('error', 'This Work Passport is private or unavailable.');
  end if;
  return v_result;
end;
$;

revoke all on function public.eb_get_public_passport(uuid) from public;
grant execute on function public.eb_get_public_passport(uuid) to anon, authenticated;

commit;
