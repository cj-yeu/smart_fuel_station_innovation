create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null,
  phone text,
  role text not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view own profile"
on public.profiles
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (
    user_id,
    full_name,
    email
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.email, '')
  );

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

insert into public.profiles (
  user_id,
  full_name,
  email
)
select
  id,
  coalesce(raw_user_meta_data ->> 'full_name', ''),
  coalesce(email, '')
from auth.users
on conflict (user_id) do nothing;

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plate_number text not null,
  vehicle_type text not null,
  vehicle_model text not null,
  fuel_type text not null,
  registration_year integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint vehicles_user_plate_unique
    unique (user_id, plate_number),

  constraint vehicles_registration_year_valid
    check (
      registration_year >= 1950
      and registration_year <= 2100
    )
);

alter table public.vehicles enable row level security;

create policy "Users can view own vehicles"
on public.vehicles
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can create own vehicles"
on public.vehicles
for insert
to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own vehicles"
on public.vehicles
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can delete own vehicles"
on public.vehicles
for delete
to authenticated
using (auth.uid() = user_id);

create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger update_vehicles_updated_at
before update on public.vehicles
for each row
execute procedure public.update_updated_at_column();