-- VIMS Research & Internship Opportunity Board
-- Run this entire script in the Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.opportunities (
  id uuid primary key default gen_random_uuid(),
  opportunity_name text not null
    check (char_length(trim(opportunity_name)) between 3 and 160),
  description text not null
    check (char_length(trim(description)) between 20 and 5000),
  qualification text,
  opportunity_type text not null default 'Research'
    check (opportunity_type in (
      'Research', 'Internship', 'Paid employment',
      'Independent study', 'Capstone', 'Volunteer'
    )),
  academic_term text,
  student_level text,
  start_date date,
  end_date date,
  application_deadline date,
  expiration_date date,
  compensation_type text not null default 'Unpaid/volunteer'
    check (compensation_type in (
      'Paid', 'Stipend', 'Academic credit', 'Unpaid/volunteer', 'Varies'
    )),
  compensation_details text,
  work_setting text,
  location text,
  department_center text not null,
  time_commitment text,
  contact_name text not null,
  contact_email text not null
    check (lower(contact_email) ~ '^[a-z0-9._%+\-]+@vims\.edu$'),
  application_url text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'closed', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint opportunity_date_order
    check (end_date is null or start_date is null or end_date >= start_date)
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists opportunities_set_updated_at on public.opportunities;
create trigger opportunities_set_updated_at
before update on public.opportunities
for each row execute function public.set_updated_at();

alter table public.opportunities enable row level security;

-- API permissions. The public app can read and submit, but cannot edit or delete.
grant usage on schema public to anon;
grant select, insert on table public.opportunities to anon;
revoke update, delete on table public.opportunities from anon;

-- Re-running this file is safe because existing policies are replaced.
drop policy if exists "Public can read active approved opportunities" on public.opportunities;
drop policy if exists "Public can submit pending opportunities" on public.opportunities;

create policy "Public can read active approved opportunities"
on public.opportunities
for select
to anon
using (
  status = 'approved'
  and (expiration_date is null or expiration_date >= current_date)
);

create policy "Public can submit pending opportunities"
on public.opportunities
for insert
to anon
with check (
  status = 'pending'
  and lower(contact_email) ~ '^[a-z0-9._%+\-]+@vims\.edu$'
);

-- No anonymous UPDATE or DELETE policies are created.
-- Approve, close, edit, and delete records in the Supabase Table Editor.
