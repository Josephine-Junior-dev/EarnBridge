-- EarnBridge commercial transaction core. Run once in the existing Garage Operations Supabase project.
-- Only eb_ objects are changed. No funds are moved by this migration.
alter table public.eb_orders
  add column if not exists delivery_note text,
  add column if not exists delivered_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists dispute_reason text,
  add column if not exists disputed_at timestamptz;

create table if not exists public.eb_order_events (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.eb_orders(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null,
 event_type text not null,
 note text,
 created_at timestamptz not null default now()
);
create index if not exists eb_order_events_order_idx on public.eb_order_events(order_id,created_at);
alter table public.eb_order_events enable row level security;
drop policy if exists eb_order_events_participant_read on public.eb_order_events;
create policy eb_order_events_participant_read on public.eb_order_events for select to authenticated
 using(exists(select 1 from public.eb_orders o where o.id=order_id and (o.provider_id=auth.uid() or o.customer_id=auth.uid())));
revoke insert,update,delete on public.eb_order_events from anon,authenticated;
grant select on public.eb_order_events to authenticated;

create or replace function public.eb_guard_order_write()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_actor uuid := auth.uid(); v_owner uuid;
begin
 if tg_op='INSERT' then
   if v_actor is null or new.customer_id<>v_actor or new.provider_id=v_actor then
     raise exception 'Only the customer can place an order for another provider.';
   end if;
   if new.status<>'requested' then raise exception 'New orders must start as requested.'; end if;
   if new.amount<0 then raise exception 'Order amount cannot be negative.'; end if;
   if new.service_id is not null then
     select user_id into v_owner from public.eb_services where id=new.service_id and status='published';
     if v_owner is null or v_owner<>new.provider_id then raise exception 'The selected service is not available from this provider.'; end if;
   end if;
   insert into public.eb_order_events(order_id,actor_id,event_type,note) values(new.id,v_actor,'requested','Order request created.');
   return new;
 end if;
 if new.id<>old.id or new.customer_id<>old.customer_id or new.provider_id<>old.provider_id or
    new.service_id is distinct from old.service_id or new.amount<>old.amount or new.currency<>old.currency or
    new.title<>old.title or new.description is distinct from old.description or new.due_date is distinct from old.due_date then
   raise exception 'Order terms cannot be changed after the request is placed.';
 end if;
 if v_actor=old.provider_id then
   if old.status='requested' and new.status in ('accepted','cancelled') then null;
   elsif old.status='accepted' and new.status='in_progress' then null;
   elsif old.status='in_progress' and new.status='delivered' then
     if coalesce(trim(new.delivery_note),'')='' then raise exception 'Add a delivery note before submitting work.'; end if;
     new.delivered_at=now();
   else raise exception 'This action is not allowed for the provider at this order stage.'; end if;
 elsif v_actor=old.customer_id then
   if old.status='requested' and new.status='cancelled' then null;
   elsif old.status='delivered' and new.status in ('completed','disputed') then
     if new.status='disputed' and coalesce(trim(new.dispute_reason),'')='' then raise exception 'Explain the dispute.'; end if;
     if new.status='completed' then new.completed_at=now(); else new.disputed_at=now(); end if;
   else raise exception 'This action is not allowed for the customer at this order stage.'; end if;
 else raise exception 'Only the order participants can update this order.'; end if;
 if new.status is distinct from old.status then
   insert into public.eb_order_events(order_id,actor_id,event_type,note)
   values(new.id,v_actor,new.status,case when new.status='delivered' then new.delivery_note when new.status='disputed' then new.dispute_reason else null end);
 end if;
 new.updated_at=now();
 return new;
end $$;
drop trigger if exists eb_orders_guard_write on public.eb_orders;
create trigger eb_orders_guard_write before insert or update on public.eb_orders
for each row execute function public.eb_guard_order_write();

-- A review is allowed only from the other participant after an order is completed.
create or replace function public.eb_guard_review()
returns trigger language plpgsql security definer set search_path=public as $$
declare o public.eb_orders%rowtype;
begin
 select * into o from public.eb_orders where id=new.order_id;
 if not found or o.status<>'completed' then raise exception 'Reviews are only allowed after an order is completed.'; end if;
 if new.reviewer_id<>auth.uid() then raise exception 'Review author must be the signed-in user.'; end if;
 if new.reviewer_id=o.customer_id and new.reviewee_id=o.provider_id then return new; end if;
 if new.reviewer_id=o.provider_id and new.reviewee_id=o.customer_id then return new; end if;
 raise exception 'Only the customer or provider can review the other order participant.';
end $$;
drop trigger if exists eb_reviews_guard_insert on public.eb_reviews;
create trigger eb_reviews_guard_insert before insert on public.eb_reviews
for each row execute function public.eb_guard_review();

grant select,insert,update on public.eb_orders to authenticated;
