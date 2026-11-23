-- EarnBridge phone-friendly job receipts
-- Run once in the existing Garage Operations Supabase project SQL Editor.
-- This migration changes only EarnBridge's eb_ tables.
begin;
alter table public.eb_work_records
  add column if not exists client_phone text;
comment on column public.eb_work_records.client_phone is
  'Optional customer phone/WhatsApp contact used to share a work receipt; not a verified identity signal.';
grant select, insert, update, delete on public.eb_work_records to authenticated;
commit;
