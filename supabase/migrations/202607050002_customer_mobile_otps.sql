-- Run after schema.sql — table for one-time customer mobile verification
create table public.customer_mobile_otps (
  customer_id uuid primary key references public.customers(id) on delete cascade,
  otp_hash text not null,
  expires_at timestamptz not null,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.customer_mobile_otps enable row level security;
-- no policies: service-role access only
