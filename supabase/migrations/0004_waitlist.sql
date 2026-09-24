-- Early-access waitlist for the public pre-launch site.
-- Visitors never touch the table directly. They can only call two narrow functions:
-- join (email) and add optional details once. Nobody outside can read the list;
-- the owner reads it in the Supabase Table Editor.

create table public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique
    check (char_length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'),
  source text check (source is null or char_length(source) <= 40),
  work text check (work is null or work in ('agency', 'consultancy', 'freelancer', 'inhouse', 'other')),
  mac text check (mac is null or mac in ('notch', 'no-notch', 'not-mac')),
  first_task text check (first_task is null or char_length(first_task) <= 1200),
  details_token uuid,
  created_at timestamptz not null default now(),
  details_at timestamptz
);
alter table public.waitlist enable row level security;
-- No policies on purpose: no role can select, insert, update, or delete through the Data API.
revoke all on public.waitlist from anon, authenticated;

-- Join. Always answers the same way, so it never reveals whether an email is already listed.
-- Returns a one-time token that lets this visitor add optional details once.
create function public.join_waitlist(p_email text, p_source text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  token uuid := gen_random_uuid();
  clean text := lower(trim(p_email));
begin
  if clean is null or char_length(clean) > 254 or clean !~* '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then
    raise exception 'invalid email' using errcode = '22023';
  end if;
  insert into public.waitlist (email, source, details_token)
  values (clean, left(p_source, 40), token)
  on conflict (email) do update set details_token = case
      when public.waitlist.details_at is null then excluded.details_token
      else public.waitlist.details_token end;
  return token;
end;
$$;

-- Optional details: accepted once per email, and only with the token from join.
create function public.add_waitlist_details(p_email text, p_token uuid, p_work text, p_mac text, p_task text)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  changed int;
begin
  update public.waitlist
     set work = nullif(p_work, ''),
         mac = nullif(p_mac, ''),
         first_task = nullif(left(trim(p_task), 1200), ''),
         details_at = now(),
         details_token = null
   where email = lower(trim(p_email))
     and details_token = p_token
     and details_at is null;
  get diagnostics changed = row_count;
  return changed = 1;
end;
$$;

revoke execute on function public.join_waitlist(text, text) from public;
revoke execute on function public.add_waitlist_details(text, uuid, text, text, text) from public;
grant execute on function public.join_waitlist(text, text) to anon, authenticated;
grant execute on function public.add_waitlist_details(text, uuid, text, text, text) to anon, authenticated;
