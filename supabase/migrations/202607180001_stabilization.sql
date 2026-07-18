-- Salesman Tracker production stabilization.
-- Apply once to the existing Supabase project through the SQL editor or CLI.

begin;

-- Email-based admin accounts do not have a phone number. The original trigger
-- inserted an empty string, which prevented a second email user from existing.
alter table public.users alter column mobile drop not null;
update public.users set mobile = null where mobile = '';
alter table public.users alter column active set default false;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, mobile, active)
  values (new.id, nullif(regexp_replace(coalesce(new.phone, ''), '[^0-9]', '', 'g'), ''), false)
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 'admin' and active
  );
$$;

create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users where id = auth.uid() and active
  );
$$;

-- Inactive accounts may read only their own activation state. Every business
-- table requires an active account, and only a true admin receives global data.
drop policy if exists users_self_read on public.users;
drop policy if exists users_admin_write on public.users;
create policy users_self_read on public.users for select
  using (id = auth.uid() or public.is_admin());
create policy users_admin_write on public.users for update
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists customers_read on public.customers;
drop policy if exists customers_insert on public.customers;
drop policy if exists customers_update on public.customers;
create policy customers_read on public.customers for select
  using ((owner_user_id = auth.uid() and public.is_active_user()) or public.is_admin());
create policy customers_insert on public.customers for insert
  with check (owner_user_id = auth.uid() and public.is_active_user());
create policy customers_update on public.customers for update
  using ((owner_user_id = auth.uid() and public.is_active_user()) or public.is_admin())
  with check ((owner_user_id = auth.uid() and public.is_active_user()) or public.is_admin());

create or replace function public.protect_customer_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() = 'service_role' or auth.uid() is null then
    return new;
  end if;
  if public.is_admin() then
    if new.mobile is distinct from old.mobile then
      new.mobile_verified_at := null;
    end if;
    return new;
  end if;
  if new.owner_user_id is distinct from old.owner_user_id
    or new.mobile is distinct from old.mobile
    or new.mobile_verified_at is distinct from old.mobile_verified_at
    or new.lat is distinct from old.lat
    or new.lng is distinct from old.lng then
    raise exception 'Customer identity, verified mobile, and location pin require admin approval';
  end if;
  return new;
end;
$$;

drop trigger if exists customers_protect_identity on public.customers;
create trigger customers_protect_identity before update on public.customers
  for each row execute function public.protect_customer_identity();

drop policy if exists visits_read on public.visits;
drop policy if exists visits_insert on public.visits;
drop policy if exists visits_update on public.visits;
create policy visits_read on public.visits for select
  using ((user_id = auth.uid() and public.is_active_user()) or public.is_admin());
create policy visits_insert on public.visits for insert
  with check (
    user_id = auth.uid()
    and public.is_active_user()
    and exists (
      select 1 from public.customers c
      where c.id = customer_id
        and c.owner_user_id = auth.uid()
        and c.mobile_verified_at is not null
    )
  );
create policy visits_update on public.visits for update
  using ((user_id = auth.uid() and public.is_active_user()) or public.is_admin())
  with check ((user_id = auth.uid() and public.is_active_user()) or public.is_admin());

drop policy if exists req_read on public.requirements;
drop policy if exists req_insert on public.requirements;
drop policy if exists req_update on public.requirements;
create policy req_read on public.requirements for select
  using ((created_by = auth.uid() and public.is_active_user()) or public.is_admin());
create policy req_insert on public.requirements for insert
  with check (
    created_by = auth.uid() and public.is_active_user()
    and exists (
      select 1 from public.customers c
      where c.id = customer_id and c.owner_user_id = auth.uid()
    )
  );
create policy req_update on public.requirements for update
  using ((created_by = auth.uid() and public.is_active_user()) or public.is_admin())
  with check ((created_by = auth.uid() and public.is_active_user()) or public.is_admin());

drop policy if exists photos_read on public.visit_photos;
drop policy if exists photos_insert on public.visit_photos;
create policy photos_read on public.visit_photos for select
  using (exists (
    select 1 from public.visits v
    where v.id = visit_id
      and ((v.user_id = auth.uid() and public.is_active_user()) or public.is_admin())
  ));
create policy photos_insert on public.visit_photos for insert
  with check (exists (
    select 1 from public.visits v
    where v.id = visit_id and v.user_id = auth.uid() and public.is_active_user()
  ));

-- Verification fields must be written by trusted server code. A sales user can
-- complete a verified visit but cannot mark a planned visit verified directly.
create or replace function public.protect_verified_visit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() = 'service_role' or auth.uid() is null or public.is_admin() then
    return new;
  end if;

  if old.status = 'planned' and new.status <> 'planned' then
    raise exception 'A planned visit must be verified by the server';
  end if;
  if old.status = 'verified' and new.status not in ('verified', 'completed') then
    raise exception 'Invalid visit status transition';
  end if;
  if old.status in ('completed', 'missed', 'unverified') then
    raise exception 'Closed visits cannot be edited';
  end if;

  if old.status = 'verified' then
    if new.customer_id is distinct from old.customer_id
      or new.user_id is distinct from old.user_id
      or new.scheduled_at is distinct from old.scheduled_at
      or new.purpose is distinct from old.purpose then
      raise exception 'Verified visit identity cannot be changed';
    end if;
  end if;

  new.verified_at := old.verified_at;
  new.verified_lat := old.verified_lat;
  new.verified_lng := old.verified_lng;
  new.gps_accuracy_m := old.gps_accuracy_m;
  new.distance_from_pin_m := old.distance_from_pin_m;
  new.flags := old.flags;
  return new;
end;
$$;

-- Attendance is timestamped by PostgreSQL, not by the employee's device clock.
alter table public.attendance
  add column if not exists day_start_accuracy_m double precision,
  add column if not exists day_start_mock_location boolean,
  add column if not exists day_end_accuracy_m double precision,
  add column if not exists day_end_mock_location boolean;

drop policy if exists att_read on public.attendance;
drop policy if exists att_write on public.attendance;
drop policy if exists att_update on public.attendance;
create policy att_read on public.attendance for select
  using ((user_id = auth.uid() and public.is_active_user()) or public.is_admin());

create or replace function public.record_attendance(
  p_action text,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m double precision,
  p_mock_location boolean default false
)
returns public.attendance
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_row public.attendance;
begin
  if not public.is_active_user() then
    raise exception 'Account is not active';
  end if;
  if p_lat is null or p_lat not between -90 and 90
    or p_lng is null or p_lng not between -180 and 180
    or p_accuracy_m is null or p_accuracy_m < 0 then
    raise exception 'Invalid location';
  end if;

  if p_action = 'start' then
    insert into public.attendance (
      user_id, date, day_start_at, day_start_lat, day_start_lng,
      day_start_accuracy_m, day_start_mock_location
    ) values (
      auth.uid(), v_today, now(), p_lat, p_lng, p_accuracy_m, coalesce(p_mock_location, false)
    )
    on conflict (user_id, date) do update set
      day_start_at = coalesce(public.attendance.day_start_at, excluded.day_start_at),
      day_start_lat = coalesce(public.attendance.day_start_lat, excluded.day_start_lat),
      day_start_lng = coalesce(public.attendance.day_start_lng, excluded.day_start_lng),
      day_start_accuracy_m = coalesce(public.attendance.day_start_accuracy_m, excluded.day_start_accuracy_m),
      day_start_mock_location = coalesce(public.attendance.day_start_mock_location, excluded.day_start_mock_location)
    returning * into v_row;
  elsif p_action = 'end' then
    update public.attendance set
      day_end_at = coalesce(day_end_at, now()),
      day_end_lat = coalesce(day_end_lat, p_lat),
      day_end_lng = coalesce(day_end_lng, p_lng),
      day_end_accuracy_m = coalesce(day_end_accuracy_m, p_accuracy_m),
      day_end_mock_location = coalesce(day_end_mock_location, coalesce(p_mock_location, false))
    where user_id = auth.uid() and date = v_today and day_start_at is not null
    returning * into v_row;
    if v_row.id is null then
      raise exception 'Start the day before ending it';
    end if;
  else
    raise exception 'Action must be start or end';
  end if;
  return v_row;
end;
$$;

revoke all on function public.record_attendance(text,double precision,double precision,double precision,boolean) from public, anon;
grant execute on function public.record_attendance(text,double precision,double precision,double precision,boolean) to authenticated;

-- Orders existed in production but were missing from source control.
create table if not exists public.order_categories (
  id uuid primary key default uuid_generate_v4(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.order_categories
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.orders (
  id uuid primary key default uuid_generate_v4(),
  customer_id uuid not null references public.customers(id),
  category_id uuid references public.order_categories(id),
  sqft numeric check (sqft is null or sqft > 0),
  notes text,
  visit_status text not null default 'pending'
    check (visit_status in ('pending','done','not_required')),
  stage text not null default 'draft'
    check (stage in ('draft','need_quote','quoted','won','lost')),
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists orders_created_by_created_at
  on public.orders (created_by, created_at desc);
create index if not exists orders_customer on public.orders (customer_id);
create index if not exists orders_stage on public.orders (stage);

create table if not exists public.order_files (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  storage_path text not null,
  kind text not null check (kind in ('floor_plan','photo')),
  uploaded_by uuid not null references public.users(id),
  created_at timestamptz not null default now()
);
create index if not exists order_files_order on public.order_files (order_id);

alter table public.order_categories enable row level security;
alter table public.orders enable row level security;
alter table public.order_files enable row level security;

-- The live Orders feature was created outside source control, so normalize any
-- unknown legacy policy names before installing the canonical policies below.
do $$
declare
  p record;
begin
  for p in
    select tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('order_categories','orders','order_files')
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end;
$$;

drop policy if exists order_categories_read on public.order_categories;
drop policy if exists order_categories_admin_insert on public.order_categories;
drop policy if exists order_categories_admin_update on public.order_categories;
create policy order_categories_read on public.order_categories for select
  using ((active and public.is_active_user()) or public.is_admin());
create policy order_categories_admin_insert on public.order_categories for insert
  with check (public.is_admin());
create policy order_categories_admin_update on public.order_categories for update
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists orders_read on public.orders;
drop policy if exists orders_insert on public.orders;
drop policy if exists orders_update on public.orders;
create policy orders_read on public.orders for select
  using ((created_by = auth.uid() and public.is_active_user()) or public.is_admin());
create policy orders_insert on public.orders for insert
  with check (
    created_by = auth.uid() and public.is_active_user()
    and exists (
      select 1 from public.customers c
      where c.id = customer_id and c.owner_user_id = auth.uid()
    )
  );
create policy orders_update on public.orders for update
  using ((created_by = auth.uid() and public.is_active_user()) or public.is_admin())
  with check ((created_by = auth.uid() and public.is_active_user()) or public.is_admin());

create or replace function public.protect_sales_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() = 'service_role' or auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if new.created_by is distinct from old.created_by
    or new.customer_id is distinct from old.customer_id
    or new.category_id is distinct from old.category_id
    or new.sqft is distinct from old.sqft
    or new.notes is distinct from old.notes then
    raise exception 'Order details cannot be changed after creation';
  end if;
  if old.stage = 'draft' and new.stage not in ('draft','need_quote') then
    raise exception 'A draft can only be submitted for quotation';
  end if;
  if old.stage <> 'draft' and new.stage is distinct from old.stage then
    raise exception 'Only an admin can change the quotation stage';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_protect on public.orders;
create trigger orders_protect before update on public.orders
  for each row execute function public.protect_sales_order();

drop policy if exists order_files_read on public.order_files;
drop policy if exists order_files_insert on public.order_files;
create policy order_files_read on public.order_files for select
  using (exists (
    select 1 from public.orders o where o.id = order_id
      and ((o.created_by = auth.uid() and public.is_active_user()) or public.is_admin())
  ));
create policy order_files_insert on public.order_files for insert
  with check (
    uploaded_by = auth.uid() and public.is_active_user()
    and exists (
      select 1 from public.orders o where o.id = order_id and o.created_by = auth.uid()
    )
  );

-- Keep updated_at trustworthy and consistent.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['users','customers','visits','requirements','order_categories','orders']
  loop
    execute format('drop trigger if exists %I on public.%I', t || '_updated_at', t);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_updated_at', t
    );
  end loop;
end;
$$;

-- Storage buckets and policies are part of the deployable database definition.
insert into storage.buckets (id, name, public)
values ('visit-photos', 'visit-photos', false), ('order-files', 'order-files', false)
on conflict (id) do update set public = false;

do $$
declare
  p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (policyname ilike '%visit%photo%' or policyname ilike '%order%file%')
  loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end;
$$;

drop policy if exists visit_photos_storage_read on storage.objects;
drop policy if exists visit_photos_storage_insert on storage.objects;
create policy visit_photos_storage_read on storage.objects for select
  using (
    bucket_id = 'visit-photos'
    and exists (
      select 1 from public.visits v
      where v.id = ((storage.foldername(name))[1])::uuid
        and ((v.user_id = auth.uid() and public.is_active_user()) or public.is_admin())
    )
  );
create policy visit_photos_storage_insert on storage.objects for insert
  with check (
    bucket_id = 'visit-photos'
    and exists (
      select 1 from public.visits v
      where v.id = ((storage.foldername(name))[1])::uuid
        and v.user_id = auth.uid() and public.is_active_user()
    )
  );

drop policy if exists order_files_storage_read on storage.objects;
drop policy if exists order_files_storage_insert on storage.objects;
create policy order_files_storage_read on storage.objects for select
  using (
    bucket_id = 'order-files'
    and exists (
      select 1 from public.orders o
      where o.id = ((storage.foldername(name))[1])::uuid
        and ((o.created_by = auth.uid() and public.is_active_user()) or public.is_admin())
    )
  );
create policy order_files_storage_insert on storage.objects for insert
  with check (
    bucket_id = 'order-files'
    and exists (
      select 1 from public.orders o
      where o.id = ((storage.foldername(name))[1])::uuid
        and o.created_by = auth.uid() and public.is_active_user()
    )
  );

-- Safe to schedule hourly with Supabase Cron:
-- select public.mark_missed_visits();
create or replace function public.mark_missed_visits()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed integer;
begin
  update public.visits
  set status = 'missed'
  where status = 'planned' and scheduled_at < now() - interval '4 hours';
  get diagnostics changed = row_count;
  return changed;
end;
$$;
revoke all on function public.mark_missed_visits() from public, anon, authenticated;

commit;
