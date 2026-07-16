create table public.business_evaluations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  station_name text not null,
  fuel_price numeric not null,
  fuel_purchase_cost numeric not null,
  daily_customers integer not null,
  average_litres numeric not null,

  monthly_rental numeric not null,
  monthly_staff_salary numeric not null,
  monthly_utilities numeric not null,
  monthly_maintenance numeric not null,
  monthly_other_cost numeric not null,
  initial_investment numeric not null,

  monthly_sales_volume numeric not null,
  monthly_revenue numeric not null,
  monthly_fuel_cost numeric not null,
  monthly_operating_cost numeric not null,
  monthly_profit numeric not null,
  profit_margin numeric not null,
  roi numeric not null,
  break_even_months numeric,
  profitability_score numeric not null,

  profitability_category text not null,
  recommendation text not null,
  explanation text not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint evaluation_fuel_price_valid
    check (fuel_price >= 0),

  constraint evaluation_fuel_cost_valid
    check (fuel_purchase_cost >= 0),

  constraint evaluation_customer_count_valid
    check (daily_customers >= 0),

  constraint evaluation_average_litres_valid
    check (average_litres >= 0),

  constraint evaluation_costs_valid
    check (
      monthly_rental >= 0
      and monthly_staff_salary >= 0
      and monthly_utilities >= 0
      and monthly_maintenance >= 0
      and monthly_other_cost >= 0
      and initial_investment >= 0
    ),

  constraint evaluation_score_valid
    check (profitability_score between 0 and 100)
);

alter table public.business_evaluations enable row level security;

create policy "Users can view own business evaluations"
on public.business_evaluations
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can create own business evaluations"
on public.business_evaluations
for insert
to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own business evaluations"
on public.business_evaluations
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can delete own business evaluations"
on public.business_evaluations
for delete
to authenticated
using (auth.uid() = user_id);

create trigger update_business_evaluations_updated_at
before update on public.business_evaluations
for each row
execute procedure public.update_updated_at_column();