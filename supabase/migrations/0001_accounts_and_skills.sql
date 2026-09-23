-- Understudy prototype: accounts, skills, receipts.
-- Run once in the Supabase SQL editor (or with `supabase db push`).
-- Every table has row-level security: a signed-in user can only see and change their own rows.

-- Profiles: one per user, created automatically at sign-up. The plan can only be
-- changed server-side (later, by billing), never by the app.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  plan text not null default 'free' check (plan in ('free', 'pro', 'team')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "Users read their own profile" on public.profiles
  for select using ((select auth.uid()) = id);

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Skills: what Understudy has learned for a user.
create table public.skills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  client text check (client is null or char_length(client) <= 120),
  is_sample boolean not null default false,
  definition jsonb,
  created_at timestamptz not null default now()
);
create index skills_user_id_idx on public.skills (user_id);
-- One sample skill per user, so samples can't be used to get around the plan limit.
create unique index skills_one_sample_per_user on public.skills (user_id) where is_sample;
alter table public.skills enable row level security;
create policy "Users read their own skills" on public.skills
  for select using ((select auth.uid()) = user_id);
create policy "Users add their own skills" on public.skills
  for insert with check ((select auth.uid()) = user_id);
create policy "Users edit their own skills" on public.skills
  for update using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users delete their own skills" on public.skills
  for delete using ((select auth.uid()) = user_id);

-- Free plan: up to 5 skills (the sample skill doesn't count). Enforced on the server,
-- so a modified app can't skip it.
create function public.enforce_free_skill_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  user_plan text;
  owned int;
begin
  if new.is_sample then
    return new;
  end if;
  select plan into user_plan from public.profiles where id = new.user_id;
  if coalesce(user_plan, 'free') = 'free' then
    select count(*) into owned from public.skills where user_id = new.user_id and not is_sample;
    if owned >= 5 then
      raise exception 'The free plan includes up to 5 skills. Upgrade to Pro for unlimited skills.'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
create trigger skills_free_plan_limit
  before insert on public.skills
  for each row execute function public.enforce_free_skill_limit();

-- Receipts: one per run (used from the next build). Status and evidence are kept apart.
create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  skill_id uuid references public.skills (id) on delete set null,
  kind text not null check (kind in ('rehearsal', 'run')),
  ready_to_send boolean not null default false,
  steps jsonb not null default '[]'::jsonb,   -- [{ step, status, evidence, verification }]
  created_at timestamptz not null default now()
);
create index receipts_user_id_idx on public.receipts (user_id, created_at desc);
alter table public.receipts enable row level security;
create policy "Users read their own receipts" on public.receipts
  for select using ((select auth.uid()) = user_id);
create policy "Users add their own receipts" on public.receipts
  for insert with check ((select auth.uid()) = user_id);
