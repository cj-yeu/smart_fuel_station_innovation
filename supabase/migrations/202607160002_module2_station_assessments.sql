create table public.station_assessments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  location_name text not null,
  population_density numeric not null,
  traffic_level integer not null,
  registered_vehicle_count integer not null,
  nearby_fuel_stations integer not null,
  competitor_distance_km numeric not null,
  road_accessibility integer not null,
  commercial_activity integer not null,
  residential_activity integer not null,
  land_accessibility integer not null,

  final_score numeric not null,
  suitability_category text not null,
  recommendation text not null,
  explanation text not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint assessment_population_valid
    check (population_density >= 0),

  constraint assessment_traffic_valid
    check (traffic_level between 1 and 5),

  constraint assessment_vehicle_count_valid
    check (registered_vehicle_count >= 0),

  constraint assessment_nearby_stations_valid
    check (nearby_fuel_stations >= 0),

  constraint assessment_distance_valid
    check (competitor_distance_km >= 0),

  constraint assessment_road_accessibility_valid
    check (road_accessibility between 1 and 5),

  constraint assessment_commercial_valid
    check (commercial_activity between 1 and 5),

  constraint assessment_residential_valid
    check (residential_activity between 1 and 5),

  constraint assessment_land_accessibility_valid
    check (land_accessibility between 1 and 5),

  constraint assessment_score_valid
    check (final_score between 0 and 100)
);

alter table public.station_assessments enable row level security;

create policy "Users can view own assessments"
on public.station_assessments
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can create own assessments"
on public.station_assessments
for insert
to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own assessments"
on public.station_assessments
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can delete own assessments"
on public.station_assessments
for delete
to authenticated
using (auth.uid() = user_id);

create trigger update_station_assessments_updated_at
before update on public.station_assessments
for each row
execute procedure public.update_updated_at_column();