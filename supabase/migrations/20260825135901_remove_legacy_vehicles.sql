-- The vehicle-registration feature is no longer part of the application.
-- Do not use CASCADE: an unexpected dependency must abort this migration.
drop table public.vehicles;
