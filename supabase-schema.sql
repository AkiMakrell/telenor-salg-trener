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
