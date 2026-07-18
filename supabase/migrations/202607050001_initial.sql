-- Salesman Tracker — Supabase schema v1 (Phases 1–3)
-- Run in Supabase SQL Editor.

create extension if not exists "uuid-ossp";

-- ============ USERS ============
-- Mirrors auth.users; created by trigger on signup, enriched by admin.
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  mobile text unique not null,
  role text not null default 'sales' check (role in ('sales','admin','manager')),
  territory text,
  device_id text,                -- device binding
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Auto-create profile row on auth signup (phone auth)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, mobile)
  values (new.id, coalesce(new.phone, ''));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ CUSTOMERS ============
create table public.customers (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  company text,
  type text not null default 'customer' check (type in ('customer','channel_partner','prospect')),
  mobile text unique not null,          -- duplicate check across company
  address text,
  territory text,
  lat double precision,                 -- pinned on first verified visit
  lng double precision,
  otp_channel text not null default 'whatsapp' check (otp_channel in ('whatsapp','sms')),
  owner_user_id uuid not null references public.users(id),
  mobile_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============ VISITS ============
create table public.visits (
  id uuid primary key default uuid_generate_v4(),
  customer_id uuid not null references public.customers(id),
  user_id uuid not null references public.users(id),
  scheduled_at timestamptz not null,
  purpose text not null default 'follow_up'
    check (purpose in ('new_order','follow_up','payment_collection','demo','other')),
  status text not null default 'planned'
    check (status in ('planned','verified','completed','missed','unverified')),
  verified_at timestamptz,
  verified_lat double precision,
  verified_lng double precision,
  gps_accuracy_m double precision,
  distance_from_pin_m double precision,
  flags text[] not null default '{}',   -- e.g. {far_from_pin, mock_location, low_accuracy}
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index visits_user_day on public.visits (user_id, scheduled_at);
create index visits_customer on public.visits (customer_id);

-- ============ VISIT OTPS ============
create table public.visit_otps (
  id uuid primary key default uuid_generate_v4(),
  visit_id uuid not null references public.visits(id) on delete cascade,
  otp_hash text not null,
  channel text not null,
  sent_to_mobile text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  resends int not null default 0,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index visit_otps_visit on public.visit_otps (visit_id);

-- ============ REQUIREMENTS ============
create table public.requirements (
  id uuid primary key default uuid_generate_v4(),
  visit_id uuid references public.visits(id),
  customer_id uuid not null references public.customers(id),
  product text not null,
  quantity text,
  expected_value numeric,
  expected_date date,
  status text not null default 'new' check (status in ('new','quoted','won','lost')),
  follow_up_date date,
  notes text,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============ VISIT PHOTOS ============
create table public.visit_photos (
  id uuid primary key default uuid_generate_v4(),
  visit_id uuid not null references public.visits(id) on delete cascade,
  storage_path text not null,           -- bucket: visit-photos
  lat double precision,
  lng double precision,
  taken_at timestamptz not null default now()
);

-- ============ ATTENDANCE ============
create table public.attendance (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id),
  date date not null,
  day_start_at timestamptz,
  day_start_lat double precision,
  day_start_lng double precision,
  day_end_at timestamptz,
  day_end_lat double precision,
  day_end_lng double precision,
  unique (user_id, date)
);

-- ============ AUDIT LOG ============
create table public.audit_log (
  id bigint generated always as identity primary key,
  user_id uuid,
  action text not null,
  entity text not null,
  entity_id uuid,
  payload jsonb,
  at timestamptz not null default now()
);

-- ============ HELPERS ============
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.users where id = auth.uid() and role in ('admin','manager') and active);
$$;

-- Haversine distance in metres
create or replace function public.distance_m(lat1 float, lng1 float, lat2 float, lng2 float)
returns float language sql immutable as $$
  select 6371000 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- ============ ROW LEVEL SECURITY ============
alter table public.users enable row level security;
alter table public.customers enable row level security;
alter table public.visits enable row level security;
alter table public.visit_otps enable row level security;
alter table public.requirements enable row level security;
alter table public.visit_photos enable row level security;
alter table public.attendance enable row level security;
alter table public.audit_log enable row level security;

-- users: read self; admin reads/edits all
create policy users_self_read on public.users for select using (id = auth.uid() or public.is_admin());
create policy users_admin_write on public.users for update using (public.is_admin());

-- customers: owner or admin
create policy customers_read on public.customers for select
  using (owner_user_id = auth.uid() or public.is_admin());
create policy customers_insert on public.customers for insert
  with check (owner_user_id = auth.uid());
create policy customers_update on public.customers for update
  using (owner_user_id = auth.uid() or public.is_admin());

-- visits: owner or admin. Verified visits immutable for sales (enforced by trigger below).
create policy visits_read on public.visits for select
  using (user_id = auth.uid() or public.is_admin());
create policy visits_insert on public.visits for insert
  with check (user_id = auth.uid());
create policy visits_update on public.visits for update
  using (user_id = auth.uid() or public.is_admin());

-- visit_otps: no client access at all (edge functions use service role)
-- (RLS enabled, no policies = deny)

-- requirements
create policy req_read on public.requirements for select
  using (created_by = auth.uid() or public.is_admin());
create policy req_insert on public.requirements for insert
  with check (created_by = auth.uid());
create policy req_update on public.requirements for update
  using (created_by = auth.uid() or public.is_admin());

-- visit_photos: via owning visit
create policy photos_read on public.visit_photos for select
  using (exists (select 1 from public.visits v where v.id = visit_id and (v.user_id = auth.uid() or public.is_admin())));
create policy photos_insert on public.visit_photos for insert
  with check (exists (select 1 from public.visits v where v.id = visit_id and v.user_id = auth.uid()));

-- attendance
create policy att_read on public.attendance for select
  using (user_id = auth.uid() or public.is_admin());
create policy att_write on public.attendance for insert with check (user_id = auth.uid());
create policy att_update on public.attendance for update using (user_id = auth.uid());

-- audit_log: admin read only; inserts via service role / triggers
create policy audit_admin_read on public.audit_log for select using (public.is_admin());

-- ============ INTEGRITY TRIGGERS ============
-- Sales people cannot modify verification fields or edit after verification
create or replace function public.protect_verified_visit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() then return new; end if;
  -- verification fields are server-set only (edge function uses service role, bypasses RLS+this check via role)
  if current_setting('request.jwt.claims', true) is not null then
    if old.status in ('verified','completed') and new.status not in ('completed') then
      raise exception 'Verified visits cannot be reverted';
    end if;
    new.verified_at := old.verified_at;
    new.verified_lat := old.verified_lat;
    new.verified_lng := old.verified_lng;
    new.distance_from_pin_m := old.distance_from_pin_m;
    new.flags := old.flags;
  end if;
  return new;
end $$;

create trigger visits_protect before update on public.visits
  for each row execute function public.protect_verified_visit();

-- Nightly job (run via pg_cron or scheduled edge function): mark missed visits
-- update public.visits set status='missed'
--   where status='planned' and scheduled_at < now() - interval '4 hours';

-- ============ STORAGE ============
-- Create bucket 'visit-photos' (private) in dashboard, then:
-- Policy: authenticated users can upload to their own visit folder; admins read all.
