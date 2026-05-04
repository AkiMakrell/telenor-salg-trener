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

create table if not exists public.user_public_profiles (
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null,
  team text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id)
);

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

create table if not exists public.user_public_activity_entries (
  entry_id text not null primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  occurred_at timestamptz not null,
  intro_success_count integer not null default 0 check (intro_success_count >= 0),
  over6_count integer not null default 0 check (over6_count >= 0),
  sales_count integer not null default 0 check (sales_count >= 0),
  points integer not null default 0 check (points >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

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
  invite_status text not null default 'invited' check (invite_status in ('invited', 'accepted', 'declined')),
  joined_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (competition_id, user_id)
);

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

drop policy if exists "Visible users can read competition participants" on public.competition_participants;
create policy "Visible users can read competition participants"
on public.competition_participants
for select
using (
  auth.uid() = user_id
  or exists (
    select 1
    from public.competition_games g
    where g.competition_id = competition_id
      and g.creator_user_id = auth.uid()
  )
  or exists (
    select 1
    from public.competition_participants self
    where self.competition_id = competition_id
      and self.user_id = auth.uid()
  )
);

drop policy if exists "Creators can insert competition participants" on public.competition_participants;
create policy "Creators can insert competition participants"
on public.competition_participants
for insert
with check (
  auth.uid() = invited_by_user_id
  and exists (
    select 1
    from public.competition_games g
    where g.competition_id = competition_id
      and g.creator_user_id = auth.uid()
  )
);

drop policy if exists "Participants and creators can update competition participants" on public.competition_participants;
create policy "Participants and creators can update competition participants"
on public.competition_participants
for update
using (
  auth.uid() = user_id
  or exists (
    select 1
    from public.competition_games g
    where g.competition_id = competition_id
      and g.creator_user_id = auth.uid()
  )
)
with check (
  auth.uid() = user_id
  or exists (
    select 1
    from public.competition_games g
    where g.competition_id = competition_id
      and g.creator_user_id = auth.uid()
  )
);

drop policy if exists "Participants and creators can delete competition participants" on public.competition_participants;
create policy "Participants and creators can delete competition participants"
on public.competition_participants
for delete
using (
  auth.uid() = user_id
  or exists (
    select 1
    from public.competition_games g
    where g.competition_id = competition_id
      and g.creator_user_id = auth.uid()
  )
);

drop policy if exists "Visible users can read competition games" on public.competition_games;
create policy "Visible users can read competition games"
on public.competition_games
for select
using (
  auth.uid() = creator_user_id
  or exists (
    select 1
    from public.competition_participants p
    where p.competition_id = competition_id
      and p.user_id = auth.uid()
  )
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
