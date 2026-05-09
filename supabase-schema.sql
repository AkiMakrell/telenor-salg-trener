create table if not exists public.user_app_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  state_key text not null,
  state_value jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, state_key)
);

create or replace function public.set_user_app_state_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.get_stats_week_start(input_date date)
returns date
language sql
immutable
as $$
  select (input_date - ((extract(isodow from input_date)::int - 1)))::date;
$$;

create table if not exists public.user_stats_activity_entries (
  entry_id text not null primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  source_entry_type text not null check (source_entry_type in ('introSuccess', 'introAttempt')),
  source_intro_id text,
  source_text text not null default '',
  occurred_at timestamptz not null,
  local_date date not null,
  week_start_date date not null,
  month_start_date date not null,
  session_date date,
  session_id text,
  session_label text,
  intro_success_count integer not null default 0 check (intro_success_count >= 0),
  over6_count integer not null default 0 check (over6_count >= 0),
  sales_count integer not null default 0 check (sales_count >= 0),
  port_sales_count integer not null default 0 check (port_sales_count >= 0),
  ov_sales_count integer not null default 0 check (ov_sales_count >= 0),
  addon_count integer not null default 0 check (addon_count >= 0),
  leaderboard_points integer not null default 0 check (leaderboard_points >= 0),
  quick_entry boolean not null default false,
  source_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.user_stats_activity_entries
  add column if not exists source_entry_type text not null default 'introAttempt',
  add column if not exists source_intro_id text,
  add column if not exists source_text text not null default '',
  add column if not exists local_date date,
  add column if not exists week_start_date date,
  add column if not exists month_start_date date,
  add column if not exists session_date date,
  add column if not exists session_id text,
  add column if not exists session_label text,
  add column if not exists intro_success_count integer not null default 0,
  add column if not exists over6_count integer not null default 0,
  add column if not exists sales_count integer not null default 0,
  add column if not exists port_sales_count integer not null default 0,
  add column if not exists ov_sales_count integer not null default 0,
  add column if not exists addon_count integer not null default 0,
  add column if not exists leaderboard_points integer not null default 0,
  add column if not exists quick_entry boolean not null default false,
  add column if not exists source_payload jsonb not null default '{}'::jsonb;

create index if not exists user_stats_activity_entries_user_occurred_idx
  on public.user_stats_activity_entries (user_id, occurred_at desc);

create index if not exists user_stats_activity_entries_user_local_date_idx
  on public.user_stats_activity_entries (user_id, local_date desc);

create index if not exists user_stats_activity_entries_user_week_start_idx
  on public.user_stats_activity_entries (user_id, week_start_date desc);

create index if not exists user_stats_activity_entries_user_month_start_idx
  on public.user_stats_activity_entries (user_id, month_start_date desc);

drop trigger if exists user_stats_activity_entries_set_updated_at on public.user_stats_activity_entries;
create trigger user_stats_activity_entries_set_updated_at
before update on public.user_stats_activity_entries
for each row
execute function public.set_user_app_state_updated_at();

alter table public.user_stats_activity_entries enable row level security;

grant select, insert, update, delete on public.user_stats_activity_entries to authenticated;

drop policy if exists "Users can read own canonical stats activity" on public.user_stats_activity_entries;
create policy "Users can read own canonical stats activity"
on public.user_stats_activity_entries
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own canonical stats activity" on public.user_stats_activity_entries;
create policy "Users can insert own canonical stats activity"
on public.user_stats_activity_entries
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own canonical stats activity" on public.user_stats_activity_entries;
create policy "Users can update own canonical stats activity"
on public.user_stats_activity_entries
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own canonical stats activity" on public.user_stats_activity_entries;
create policy "Users can delete own canonical stats activity"
on public.user_stats_activity_entries
for delete
using (auth.uid() = user_id);

create or replace function public.get_competition_team_name(target_rules_json jsonb, target_user_id uuid)
returns text
language sql
stable
as $$
  select coalesce((
    select nullif(trim(team.value ->> 'name'), '')
    from jsonb_array_elements(coalesce(target_rules_json -> 'teamConfigs', '[]'::jsonb)) as team(value)
    where exists (
      select 1
      from jsonb_array_elements_text(coalesce(team.value -> 'memberIds', '[]'::jsonb)) as member(user_id_text)
      where member.user_id_text = target_user_id::text
    )
    limit 1
  ), '');
$$;

create or replace function public.get_competition_team_color(target_rules_json jsonb, target_team_name text)
returns text
language sql
stable
as $$
  select coalesce((
    select nullif(trim(team.value ->> 'color'), '')
    from jsonb_array_elements(coalesce(target_rules_json -> 'teamConfigs', '[]'::jsonb)) as team(value)
    where nullif(trim(team.value ->> 'name'), '') = nullif(trim(target_team_name), '')
    limit 1
  ), '');
$$;

create or replace function public.get_user_stats_snapshot(target_user_id uuid default auth.uid(), reference_date date default current_date)
returns table (
  user_id uuid,
  reference_date date,
  total_intro_successes integer,
  total_over6 integer,
  total_sales integer,
  total_points integer,
  day_intro_successes integer,
  day_over6 integer,
  day_sales integer,
  day_points integer,
  week_intro_successes integer,
  week_over6 integer,
  week_sales integer,
  week_points integer,
  month_intro_successes integer,
  month_over6 integer,
  month_sales integer,
  month_points integer,
  latest_entry_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  with authorized_target as (
    select target_user_id as user_id
    where auth.uid() = target_user_id
  ),
  reference_values as (
    select
      reference_date as ref_date,
      public.get_stats_week_start(reference_date) as ref_week_start,
      date_trunc('month', reference_date::timestamp)::date as ref_month_start
  ),
  base as (
    select *
    from public.user_stats_activity_entries e
    join authorized_target t on t.user_id = e.user_id
  ),
  aggregated as (
    select
      coalesce(sum(b.intro_success_count), 0)::int as total_intro_successes,
      coalesce(sum(b.over6_count), 0)::int as total_over6,
      coalesce(sum(b.sales_count), 0)::int as total_sales,
      coalesce(sum(b.leaderboard_points), 0)::int as total_points,
      coalesce(sum(case when b.local_date = rv.ref_date then b.intro_success_count else 0 end), 0)::int as day_intro_successes,
      coalesce(sum(case when b.local_date = rv.ref_date then b.over6_count else 0 end), 0)::int as day_over6,
      coalesce(sum(case when b.local_date = rv.ref_date then b.sales_count else 0 end), 0)::int as day_sales,
      coalesce(sum(case when b.local_date = rv.ref_date then b.leaderboard_points else 0 end), 0)::int as day_points,
      coalesce(sum(case when b.week_start_date = rv.ref_week_start then b.intro_success_count else 0 end), 0)::int as week_intro_successes,
      coalesce(sum(case when b.week_start_date = rv.ref_week_start then b.over6_count else 0 end), 0)::int as week_over6,
      coalesce(sum(case when b.week_start_date = rv.ref_week_start then b.sales_count else 0 end), 0)::int as week_sales,
      coalesce(sum(case when b.week_start_date = rv.ref_week_start then b.leaderboard_points else 0 end), 0)::int as week_points,
      coalesce(sum(case when b.month_start_date = rv.ref_month_start then b.intro_success_count else 0 end), 0)::int as month_intro_successes,
      coalesce(sum(case when b.month_start_date = rv.ref_month_start then b.over6_count else 0 end), 0)::int as month_over6,
      coalesce(sum(case when b.month_start_date = rv.ref_month_start then b.sales_count else 0 end), 0)::int as month_sales,
      coalesce(sum(case when b.month_start_date = rv.ref_month_start then b.leaderboard_points else 0 end), 0)::int as month_points,
      max(b.occurred_at) as latest_entry_at,
      max(b.updated_at) as updated_at
    from reference_values rv
    left join base b on true
  )
  select
    t.user_id,
    rv.ref_date,
    aggregated.total_intro_successes,
    aggregated.total_over6,
    aggregated.total_sales,
    aggregated.total_points,
    aggregated.day_intro_successes,
    aggregated.day_over6,
    aggregated.day_sales,
    aggregated.day_points,
    aggregated.week_intro_successes,
    aggregated.week_over6,
    aggregated.week_sales,
    aggregated.week_points,
    aggregated.month_intro_successes,
    aggregated.month_over6,
    aggregated.month_sales,
    aggregated.month_points,
    aggregated.latest_entry_at,
    aggregated.updated_at
  from authorized_target t
  cross join reference_values rv
  cross join aggregated;
$$;

revoke all on function public.get_user_stats_snapshot(uuid, date) from public;
grant execute on function public.get_user_stats_snapshot(uuid, date) to authenticated;

drop trigger if exists user_app_state_set_updated_at on public.user_app_state;
create trigger user_app_state_set_updated_at
before update on public.user_app_state
for each row
execute function public.set_user_app_state_updated_at();

alter table public.user_app_state enable row level security;

drop policy if exists "Users can read own app state" on public.user_app_state;
create policy "Users can read own app state"
on public.user_app_state
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own app state" on public.user_app_state;
create policy "Users can insert own app state"
on public.user_app_state
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own app state" on public.user_app_state;
create policy "Users can update own app state"
on public.user_app_state
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own app state" on public.user_app_state;
create policy "Users can delete own app state"
on public.user_app_state
for delete
using (auth.uid() = user_id);

create table if not exists public.user_intro_history_events (
  event_id uuid not null primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  entry_id text,
  event_type text not null check (event_type in ('upsert', 'delete', 'clear')),
  entry_payload jsonb,
  event_source text not null default 'app',
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists user_intro_history_events_user_created_idx
  on public.user_intro_history_events (user_id, created_at desc);

alter table public.user_intro_history_events enable row level security;

grant select, insert on public.user_intro_history_events to authenticated;

drop policy if exists "Users can read own intro history events" on public.user_intro_history_events;
create policy "Users can read own intro history events"
on public.user_intro_history_events
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own intro history events" on public.user_intro_history_events;
create policy "Users can insert own intro history events"
on public.user_intro_history_events
for insert
with check (auth.uid() = user_id);

create table if not exists public.user_app_snapshots (
  snapshot_id uuid not null primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  snapshot_source text not null default 'app',
  state_value jsonb not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists user_app_snapshots_user_created_idx
  on public.user_app_snapshots (user_id, created_at desc);

alter table public.user_app_snapshots enable row level security;

grant select, insert, delete on public.user_app_snapshots to authenticated;

drop policy if exists "Users can read own app snapshots" on public.user_app_snapshots;
create policy "Users can read own app snapshots"
on public.user_app_snapshots
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own app snapshots" on public.user_app_snapshots;
create policy "Users can insert own app snapshots"
on public.user_app_snapshots
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own app snapshots" on public.user_app_snapshots;
create policy "Users can delete own app snapshots"
on public.user_app_snapshots
for delete
using (auth.uid() = user_id);

create table if not exists public.user_backend_migration_state (
  user_id uuid not null references auth.users (id) on delete cascade,
  migration_scope text not null default 'stats-leaderboard-spill-v1',
  migration_version integer not null default 1 check (migration_version > 0),
  read_source_preference text not null default 'legacy' check (read_source_preference in ('legacy', 'hybrid', 'backend')),
  backfill_status text not null default 'pending' check (backfill_status in ('pending', 'running', 'complete', 'failed')),
  parity_status text not null default 'pending' check (parity_status in ('pending', 'running', 'matched', 'mismatch', 'failed')),
  backend_ready boolean not null default false,
  fallback_enabled boolean not null default true,
  last_successful_step text not null default 'rollback-anchor',
  rollback_tag text not null default 'pre-backend-migration-2026-05-09',
  notes_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id)
);

alter table public.user_backend_migration_state
  add column if not exists migration_scope text not null default 'stats-leaderboard-spill-v1',
  add column if not exists migration_version integer not null default 1,
  add column if not exists read_source_preference text not null default 'legacy',
  add column if not exists backfill_status text not null default 'pending',
  add column if not exists parity_status text not null default 'pending',
  add column if not exists backend_ready boolean not null default false,
  add column if not exists fallback_enabled boolean not null default true,
  add column if not exists last_successful_step text not null default 'rollback-anchor',
  add column if not exists rollback_tag text not null default 'pre-backend-migration-2026-05-09',
  add column if not exists notes_json jsonb not null default '{}'::jsonb;

drop trigger if exists user_backend_migration_state_set_updated_at on public.user_backend_migration_state;
create trigger user_backend_migration_state_set_updated_at
before update on public.user_backend_migration_state
for each row
execute function public.set_user_app_state_updated_at();

alter table public.user_backend_migration_state enable row level security;

grant select, insert, update, delete on public.user_backend_migration_state to authenticated;

drop policy if exists "Users can read own backend migration state" on public.user_backend_migration_state;
create policy "Users can read own backend migration state"
on public.user_backend_migration_state
for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert own backend migration state" on public.user_backend_migration_state;
create policy "Users can insert own backend migration state"
on public.user_backend_migration_state
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own backend migration state" on public.user_backend_migration_state;
create policy "Users can update own backend migration state"
on public.user_backend_migration_state
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own backend migration state" on public.user_backend_migration_state;
create policy "Users can delete own backend migration state"
on public.user_backend_migration_state
for delete
using (auth.uid() = user_id);

create table if not exists public.user_public_stats (
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null,
  total_intro_successes integer not null default 0 check (total_intro_successes >= 0),
  total_over6 integer not null default 0 check (total_over6 >= 0),
  total_sales integer not null default 0 check (total_sales >= 0),
  latest_entry_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id)
);

alter table public.user_public_stats
  add column if not exists team text,
  add column if not exists day_over6 integer not null default 0 check (day_over6 >= 0),
  add column if not exists day_sales integer not null default 0 check (day_sales >= 0),
  add column if not exists day_points integer not null default 0 check (day_points >= 0),
  add column if not exists week_over6 integer not null default 0 check (week_over6 >= 0),
  add column if not exists week_sales integer not null default 0 check (week_sales >= 0),
  add column if not exists week_points integer not null default 0 check (week_points >= 0),
  add column if not exists month_over6 integer not null default 0 check (month_over6 >= 0),
  add column if not exists month_sales integer not null default 0 check (month_sales >= 0),
  add column if not exists month_points integer not null default 0 check (month_points >= 0);

drop trigger if exists user_public_stats_set_updated_at on public.user_public_stats;
create trigger user_public_stats_set_updated_at
before update on public.user_public_stats
for each row
execute function public.set_user_app_state_updated_at();

alter table public.user_public_stats enable row level security;

grant select, insert, update, delete on public.user_public_stats to authenticated;

drop policy if exists "Authenticated users can read leaderboard stats" on public.user_public_stats;
create policy "Authenticated users can read leaderboard stats"
on public.user_public_stats
for select
using (auth.role() = 'authenticated');

drop policy if exists "Users can insert own leaderboard stats" on public.user_public_stats;
create policy "Users can insert own leaderboard stats"
on public.user_public_stats
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own leaderboard stats" on public.user_public_stats;
create policy "Users can update own leaderboard stats"
on public.user_public_stats
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own leaderboard stats" on public.user_public_stats;
create policy "Users can delete own leaderboard stats"
on public.user_public_stats
for delete
using (auth.uid() = user_id);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_public_stats'
  ) then
    alter publication supabase_realtime add table public.user_public_stats;
  end if;
end;
$$;

create table if not exists public.user_public_profiles (
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null,
  team text,
  avatar_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id)
);

alter table public.user_public_profiles
  add column if not exists avatar_url text;

drop trigger if exists user_public_profiles_set_updated_at on public.user_public_profiles;
create trigger user_public_profiles_set_updated_at
before update on public.user_public_profiles
for each row
execute function public.set_user_app_state_updated_at();

alter table public.user_public_profiles enable row level security;

grant select, insert, update, delete on public.user_public_profiles to authenticated;

drop policy if exists "Authenticated users can read public profiles" on public.user_public_profiles;
create policy "Authenticated users can read public profiles"
on public.user_public_profiles
for select
using (auth.role() = 'authenticated');

drop policy if exists "Users can insert own public profile" on public.user_public_profiles;
create policy "Users can insert own public profile"
on public.user_public_profiles
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own public profile" on public.user_public_profiles;
create policy "Users can update own public profile"
on public.user_public_profiles
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own public profile" on public.user_public_profiles;
create policy "Users can delete own public profile"
on public.user_public_profiles
for delete
using (auth.uid() = user_id);

create or replace function public.sync_public_profile_from_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  next_display_name text := nullif(trim(coalesce(
    metadata ->> 'display_name',
    metadata ->> 'full_name',
    metadata ->> 'name',
    split_part(new.email, '@', 1)
  )), '');
  next_team text := nullif(trim(coalesce(metadata ->> 'team', '')), '');
begin
  insert into public.user_public_profiles (user_id, display_name, team)
  values (new.id, coalesce(next_display_name, 'Bruker'), next_team)
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        team = excluded.team;

  return new;
end;
$$;

create or replace function public.get_leaderboard_snapshot(reference_date date default current_date)
returns table (
  user_id uuid,
  display_name text,
  team text,
  total_intro_successes integer,
  total_over6 integer,
  total_sales integer,
  day_over6 integer,
  day_sales integer,
  day_points integer,
  week_over6 integer,
  week_sales integer,
  week_points integer,
  month_over6 integer,
  month_sales integer,
  month_points integer,
  latest_entry_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  with reference_values as (
    select
      reference_date as ref_date,
      public.get_stats_week_start(reference_date) as ref_week_start,
      date_trunc('month', reference_date::timestamp)::date as ref_month_start
  ),
  aggregated as (
    select
      e.user_id,
      coalesce(sum(e.intro_success_count), 0)::int as total_intro_successes,
      coalesce(sum(e.over6_count), 0)::int as total_over6,
      coalesce(sum(e.sales_count), 0)::int as total_sales,
      coalesce(sum(case when e.local_date = rv.ref_date then e.over6_count else 0 end), 0)::int as day_over6,
      coalesce(sum(case when e.local_date = rv.ref_date then e.sales_count else 0 end), 0)::int as day_sales,
      coalesce(sum(case when e.local_date = rv.ref_date then e.leaderboard_points else 0 end), 0)::int as day_points,
      coalesce(sum(case when e.week_start_date = rv.ref_week_start then e.over6_count else 0 end), 0)::int as week_over6,
      coalesce(sum(case when e.week_start_date = rv.ref_week_start then e.sales_count else 0 end), 0)::int as week_sales,
      coalesce(sum(case when e.week_start_date = rv.ref_week_start then e.leaderboard_points else 0 end), 0)::int as week_points,
      coalesce(sum(case when e.month_start_date = rv.ref_month_start then e.over6_count else 0 end), 0)::int as month_over6,
      coalesce(sum(case when e.month_start_date = rv.ref_month_start then e.sales_count else 0 end), 0)::int as month_sales,
      coalesce(sum(case when e.month_start_date = rv.ref_month_start then e.leaderboard_points else 0 end), 0)::int as month_points,
      max(e.occurred_at) as latest_entry_at,
      max(e.updated_at) as updated_at
    from public.user_stats_activity_entries e
    cross join reference_values rv
    group by e.user_id
  ),
  user_ids as (
    select a.user_id from aggregated a
    union
    select p.user_id from public.user_public_profiles p
  ),
  rows as (
    select
      ids.user_id,
      coalesce(nullif(trim(p.display_name), ''), 'Ukjent bruker') as display_name,
      coalesce(nullif(trim(p.team), ''), '') as team,
      coalesce(a.total_intro_successes, 0)::int as total_intro_successes,
      coalesce(a.total_over6, 0)::int as total_over6,
      coalesce(a.total_sales, 0)::int as total_sales,
      coalesce(a.day_over6, 0)::int as day_over6,
      coalesce(a.day_sales, 0)::int as day_sales,
      coalesce(a.day_points, 0)::int as day_points,
      coalesce(a.week_over6, 0)::int as week_over6,
      coalesce(a.week_sales, 0)::int as week_sales,
      coalesce(a.week_points, 0)::int as week_points,
      coalesce(a.month_over6, 0)::int as month_over6,
      coalesce(a.month_sales, 0)::int as month_sales,
      coalesce(a.month_points, 0)::int as month_points,
      a.latest_entry_at,
      coalesce(greatest(a.updated_at, p.updated_at), a.updated_at, p.updated_at) as updated_at
    from user_ids ids
    left join aggregated a on a.user_id = ids.user_id
    left join public.user_public_profiles p on p.user_id = ids.user_id
  )
  select *
  from rows
  where
    day_sales > 0
    or day_over6 > 0
    or day_points > 0
    or week_sales > 0
    or week_over6 > 0
    or week_points > 0
    or month_sales > 0
    or month_over6 > 0
    or month_points > 0;
$$;

revoke all on function public.get_leaderboard_snapshot(date) from public;
grant execute on function public.get_leaderboard_snapshot(date) to authenticated;

drop trigger if exists sync_public_profile_from_auth_user on auth.users;
create trigger sync_public_profile_from_auth_user
after insert or update of email, raw_user_meta_data on auth.users
for each row
execute function public.sync_public_profile_from_auth_user();

insert into public.user_public_profiles (user_id, display_name, team)
select
  u.id,
  coalesce(
    nullif(trim(coalesce(
      u.raw_user_meta_data ->> 'display_name',
      u.raw_user_meta_data ->> 'full_name',
      u.raw_user_meta_data ->> 'name',
      split_part(u.email, '@', 1)
    )), ''),
    'Bruker'
  ) as display_name,
  nullif(trim(coalesce(u.raw_user_meta_data ->> 'team', '')), '') as team
from auth.users u
on conflict (user_id) do update
  set display_name = excluded.display_name,
      team = excluded.team;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-avatars',
  'profile-avatars',
  true,
  3145728,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Avatar images are readable" on storage.objects;
create policy "Avatar images are readable"
on storage.objects
for select
using (bucket_id = 'profile-avatars');

drop policy if exists "Users can upload own avatar images" on storage.objects;
create policy "Users can upload own avatar images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "Users can update own avatar images" on storage.objects;
create policy "Users can update own avatar images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

drop policy if exists "Users can delete own avatar images" on storage.objects;
create policy "Users can delete own avatar images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create table if not exists public.user_public_activity_entries (
  entry_id text not null primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  occurred_at timestamptz not null,
  intro_success_count integer not null default 0 check (intro_success_count >= 0),
  over6_count integer not null default 0 check (over6_count >= 0),
  sales_count integer not null default 0 check (sales_count >= 0),
  port_sales_count integer not null default 0 check (port_sales_count >= 0),
  ov_sales_count integer not null default 0 check (ov_sales_count >= 0),
  addon_count integer not null default 0 check (addon_count >= 0),
  points integer not null default 0 check (points >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.user_public_activity_entries
  add column if not exists port_sales_count integer not null default 0 check (port_sales_count >= 0),
  add column if not exists ov_sales_count integer not null default 0 check (ov_sales_count >= 0),
  add column if not exists addon_count integer not null default 0 check (addon_count >= 0);

create index if not exists user_public_activity_entries_user_occurred_idx
  on public.user_public_activity_entries (user_id, occurred_at desc);

create index if not exists user_public_activity_entries_occurred_idx
  on public.user_public_activity_entries (occurred_at desc);

drop trigger if exists user_public_activity_entries_set_updated_at on public.user_public_activity_entries;
create trigger user_public_activity_entries_set_updated_at
before update on public.user_public_activity_entries
for each row
execute function public.set_user_app_state_updated_at();

alter table public.user_public_activity_entries enable row level security;

grant select, insert, update, delete on public.user_public_activity_entries to authenticated;

drop policy if exists "Authenticated users can read public activity entries" on public.user_public_activity_entries;
create policy "Authenticated users can read public activity entries"
on public.user_public_activity_entries
for select
using (auth.role() = 'authenticated');

drop policy if exists "Users can insert own public activity entries" on public.user_public_activity_entries;
create policy "Users can insert own public activity entries"
on public.user_public_activity_entries
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own public activity entries" on public.user_public_activity_entries;
create policy "Users can update own public activity entries"
on public.user_public_activity_entries
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own public activity entries" on public.user_public_activity_entries;
create policy "Users can delete own public activity entries"
on public.user_public_activity_entries
for delete
using (auth.uid() = user_id);

create table if not exists public.competition_games (
  competition_id uuid not null primary key,
  creator_user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  description text not null default '',
  game_type text not null check (game_type in ('sales-race', 'over6-challenge', 'points-race', 'target-hit')),
  metric_type text not null check (metric_type in ('sales', 'over6', 'points')),
  target_value integer check (target_value is null or target_value > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled', 'active', 'completed', 'archived')),
  rules_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (ends_at > starts_at)
);

create index if not exists competition_games_creator_idx
  on public.competition_games (creator_user_id, starts_at desc);

create index if not exists competition_games_status_idx
  on public.competition_games (status, starts_at desc);

drop trigger if exists competition_games_set_updated_at on public.competition_games;
create trigger competition_games_set_updated_at
before update on public.competition_games
for each row
execute function public.set_user_app_state_updated_at();

alter table public.competition_games enable row level security;

grant select, insert, update, delete on public.competition_games to authenticated;

create table if not exists public.competition_participants (
  competition_id uuid not null references public.competition_games (competition_id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  invited_by_user_id uuid not null references auth.users (id) on delete cascade,
  participant_role text not null default 'participant' check (participant_role in ('participant', 'viewer')),
  invite_status text not null default 'invited' check (invite_status in ('invited', 'accepted', 'declined')),
  joined_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (competition_id, user_id)
);

alter table public.competition_participants
  add column if not exists participant_role text not null default 'participant' check (participant_role in ('participant', 'viewer'));

create index if not exists competition_participants_user_idx
  on public.competition_participants (user_id, created_at desc);

create index if not exists competition_participants_competition_idx
  on public.competition_participants (competition_id, invite_status);

drop trigger if exists competition_participants_set_updated_at on public.competition_participants;
create trigger competition_participants_set_updated_at
before update on public.competition_participants
for each row
execute function public.set_user_app_state_updated_at();

alter table public.competition_participants enable row level security;

grant select, insert, update, delete on public.competition_participants to authenticated;

create or replace function public.is_competition_creator(target_competition_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
begin
  return exists (
    select 1
    from public.competition_games g
    where g.competition_id = target_competition_id
      and g.creator_user_id = auth.uid()
  );
end;
$$;

create or replace function public.is_competition_participant(target_competition_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
begin
  return exists (
    select 1
    from public.competition_participants p
    where p.competition_id = target_competition_id
      and p.user_id = auth.uid()
  );
end;
$$;

create or replace function public.user_can_access_competition(target_competition_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
set row_security = off
as $$
begin
  return public.is_competition_creator(target_competition_id)
    or public.is_competition_participant(target_competition_id);
end;
$$;

create or replace function public.get_competition_player_standings(target_competition_id uuid)
returns table (
  user_id uuid,
  display_name text,
  team text,
  team_color text,
  score integer,
  total_sales integer,
  total_over6 integer,
  total_points integer,
  current_score integer,
  baseline_score integer,
  progress_label text,
  reached_at timestamptz
)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  with game as (
    select
      g.competition_id,
      g.game_type,
      g.metric_type,
      g.target_value,
      g.rules_json,
      g.starts_at,
      g.ends_at,
      case
        when coalesce(g.rules_json ->> 'competitionMode', 'ffa') = 'team' then 'team'
        else 'ffa'
      end as competition_mode,
      greatest(1, coalesce(nullif(g.rules_json ->> 'pointsPerSale', '')::integer, 300)) as points_per_sale,
      greatest(1, coalesce(nullif(g.rules_json ->> 'pointsPerOver6', '')::integer, 100)) as points_per_over6,
      greatest(0, coalesce(
        nullif(g.rules_json ->> 'pointsPerOv', '')::integer,
        greatest(1, coalesce(nullif(g.rules_json ->> 'pointsPerSale', '')::integer, 300))
      )) as points_per_ov,
      greatest(0, coalesce(nullif(g.rules_json ->> 'pointsPerAddon', '')::integer, 0)) as points_per_addon
    from public.competition_games g
    where g.competition_id = target_competition_id
      and public.user_can_access_competition(g.competition_id)
  ),
  participants as (
    select p.user_id
    from public.competition_participants p
    join game g on g.competition_id = p.competition_id
    where p.participant_role <> 'viewer'
      and p.invite_status <> 'declined'
  ),
  scored_entries as (
    select
      p.user_id,
      e.entry_id,
      e.occurred_at,
      coalesce(e.sales_count, 0)::int as sales_count,
      coalesce(e.over6_count, 0)::int as over6_count,
      coalesce(e.leaderboard_points, 0)::int as total_points,
      case
        when g.metric_type = 'sales' then coalesce(e.sales_count, 0)::int
        when g.metric_type = 'over6' then coalesce(e.over6_count, 0)::int
        else (
          (coalesce(e.port_sales_count, 0) * g.points_per_sale)
          + (coalesce(e.ov_sales_count, 0) * g.points_per_ov)
          + (coalesce(e.over6_count, 0) * g.points_per_over6)
          + (coalesce(e.addon_count, 0) * g.points_per_addon)
        )::int
      end as metric_value
    from participants p
    cross join game g
    left join public.user_stats_activity_entries e
      on e.user_id = p.user_id
     and e.occurred_at >= g.starts_at
     and e.occurred_at <= g.ends_at
  ),
  aggregated as (
    select
      p.user_id,
      coalesce(sum(se.metric_value), 0)::int as current_score,
      coalesce(sum(se.sales_count), 0)::int as total_sales,
      coalesce(sum(se.over6_count), 0)::int as total_over6,
      coalesce(sum(se.total_points), 0)::int as total_points
    from participants p
    left join scored_entries se on se.user_id = p.user_id
    group by p.user_id
  ),
  target_hits as (
    select distinct on (ranked.user_id)
      ranked.user_id,
      ranked.occurred_at as reached_at
    from (
      select
        se.user_id,
        se.entry_id,
        se.occurred_at,
        sum(se.metric_value) over (
          partition by se.user_id
          order by se.occurred_at, se.entry_id
          rows between unbounded preceding and current row
        ) as running_score
      from scored_entries se
      where se.occurred_at is not null
    ) ranked
    join game g on true
    where g.game_type = 'target-hit'
      and coalesce(g.target_value, 0) > 0
      and ranked.running_score >= g.target_value
    order by ranked.user_id, ranked.occurred_at, ranked.entry_id
  )
  select
    p.user_id,
    coalesce(nullif(trim(profile.display_name), ''), 'Ukjent bruker') as display_name,
    case
      when g.competition_mode = 'team' then public.get_competition_team_name(g.rules_json, p.user_id)
      else coalesce(nullif(trim(profile.team), ''), '')
    end as team,
    case
      when g.competition_mode = 'team'
        then public.get_competition_team_color(g.rules_json, public.get_competition_team_name(g.rules_json, p.user_id))
      else ''
    end as team_color,
    agg.current_score as score,
    agg.total_sales,
    agg.total_over6,
    agg.total_points,
    agg.current_score,
    0::integer as baseline_score,
    case
      when g.game_type = 'target-hit' and coalesce(g.target_value, 0) > 0 and th.reached_at is not null
        then 'Mal traff ' || to_char(th.reached_at at time zone 'Europe/Oslo', 'DD.MM.YYYY HH24:MI')
      when g.game_type = 'target-hit' and coalesce(g.target_value, 0) > 0
        then agg.current_score::text || '/' || g.target_value::text
      else agg.current_score::text || ' ' || lower(
        case g.metric_type
          when 'sales' then 'Abo'
          when 'over6' then '6-minuttere'
          else 'Abo og 6-minuttere'
        end
      )
    end as progress_label,
    th.reached_at
  from participants p
  join aggregated agg on agg.user_id = p.user_id
  join game g on true
  left join public.user_public_profiles profile on profile.user_id = p.user_id
  left join target_hits th on th.user_id = p.user_id
  order by
    case
      when g.game_type = 'target-hit' and coalesce(g.target_value, 0) > 0 and th.reached_at is not null then 0
      when g.game_type = 'target-hit' and coalesce(g.target_value, 0) > 0 then 1
      else 0
    end,
    case when g.game_type = 'target-hit' and coalesce(g.target_value, 0) > 0 then th.reached_at end asc nulls last,
    agg.current_score desc,
    agg.total_sales desc,
    agg.total_over6 desc,
    coalesce(nullif(trim(profile.display_name), ''), 'Ukjent bruker') asc;
$$;

create or replace function public.get_competition_team_standings(target_competition_id uuid)
returns table (
  team text,
  team_color text,
  score numeric,
  total_score integer,
  average_score numeric,
  total_sales integer,
  total_over6 integer,
  total_points integer,
  player_count integer
)
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  with game as (
    select
      g.rules_json,
      case
        when coalesce(g.rules_json ->> 'competitionMode', 'ffa') = 'team' then true
        else false
      end as is_team,
      case
        when coalesce(g.rules_json ->> 'teamScoreMode', 'total') = 'average' then 'average'
        else 'total'
      end as team_score_mode
    from public.competition_games g
    where g.competition_id = target_competition_id
      and public.user_can_access_competition(g.competition_id)
  ),
  player_rows as (
    select *
    from public.get_competition_player_standings(target_competition_id)
    where coalesce(nullif(trim(team), ''), '') <> ''
  )
  select
    pr.team,
    public.get_competition_team_color(g.rules_json, pr.team) as team_color,
    case
      when g.team_score_mode = 'average' then round((sum(pr.score)::numeric / greatest(count(*), 1)::numeric), 2)
      else sum(pr.score)::numeric
    end as score,
    sum(pr.score)::int as total_score,
    round((sum(pr.score)::numeric / greatest(count(*), 1)::numeric), 2) as average_score,
    sum(pr.total_sales)::int as total_sales,
    sum(pr.total_over6)::int as total_over6,
    sum(pr.total_points)::int as total_points,
    count(*)::int as player_count
  from player_rows pr
  join game g on g.is_team
  group by pr.team, g.rules_json, g.team_score_mode
  order by
    case
      when g.team_score_mode = 'average' then round((sum(pr.score)::numeric / greatest(count(*), 1)::numeric), 2)
      else sum(pr.score)::numeric
    end desc,
    sum(pr.score) desc,
    sum(pr.total_sales) desc,
    sum(pr.total_over6) desc,
    pr.team asc;
$$;

revoke all on function public.get_competition_player_standings(uuid) from public;
grant execute on function public.get_competition_player_standings(uuid) to authenticated;

revoke all on function public.get_competition_team_standings(uuid) from public;
grant execute on function public.get_competition_team_standings(uuid) to authenticated;

drop policy if exists "Visible users can read competition participants" on public.competition_participants;
create policy "Visible users can read competition participants"
on public.competition_participants
for select
using (
  auth.uid() = user_id
  or auth.uid() = invited_by_user_id
  or public.is_competition_creator(competition_id)
  or public.is_competition_participant(competition_id)
);

drop policy if exists "Creators can insert competition participants" on public.competition_participants;
create policy "Creators can insert competition participants"
on public.competition_participants
for insert
with check (
  auth.uid() = invited_by_user_id
  and public.is_competition_creator(competition_id)
);

drop policy if exists "Participants and creators can update competition participants" on public.competition_participants;
create policy "Participants and creators can update competition participants"
on public.competition_participants
for update
using (
  auth.uid() = user_id
  or public.is_competition_creator(competition_id)
)
with check (
  auth.uid() = user_id
  or public.is_competition_creator(competition_id)
);

drop policy if exists "Participants and creators can delete competition participants" on public.competition_participants;
create policy "Participants and creators can delete competition participants"
on public.competition_participants
for delete
using (
  auth.uid() = user_id
  or public.is_competition_creator(competition_id)
);

drop policy if exists "Visible users can read competition games" on public.competition_games;
create policy "Visible users can read competition games"
on public.competition_games
for select
using (
  public.user_can_access_competition(competition_id)
);

drop policy if exists "Creators can insert competition games" on public.competition_games;
create policy "Creators can insert competition games"
on public.competition_games
for insert
with check (auth.uid() = creator_user_id);

drop policy if exists "Creators can update competition games" on public.competition_games;
create policy "Creators can update competition games"
on public.competition_games
for update
using (auth.uid() = creator_user_id)
with check (auth.uid() = creator_user_id);

drop policy if exists "Creators can delete competition games" on public.competition_games;
create policy "Creators can delete competition games"
on public.competition_games
for delete
using (auth.uid() = creator_user_id);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_public_profiles'
  ) then
    alter publication supabase_realtime add table public.user_public_profiles;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_public_activity_entries'
  ) then
    alter publication supabase_realtime add table public.user_public_activity_entries;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'competition_games'
  ) then
    alter publication supabase_realtime add table public.competition_games;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'competition_participants'
  ) then
    alter publication supabase_realtime add table public.competition_participants;
  end if;
end;
$$;
