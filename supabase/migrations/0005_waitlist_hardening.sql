-- Fixes from Codex's review of 0004:
-- 1. A second join for the same email (for example, another tab) keeps the outstanding
--    details token instead of replacing it, so the first tab's answers still save.
-- 2. Neither function reveals whether an email already finished signing up:
--    join always returns a token-shaped value, and details returns nothing.

create or replace function public.join_waitlist(p_email text, p_source text default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  clean text := lower(trim(p_email));
  stored uuid;
begin
  if clean is null or char_length(clean) > 254 or clean !~* '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' then
    raise exception 'invalid email' using errcode = '22023';
  end if;
  insert into public.waitlist as w (email, source, details_token)
  values (clean, left(p_source, 40), gen_random_uuid())
  on conflict (email) do update set details_token = case
      when w.details_at is null then coalesce(w.details_token, excluded.details_token)
      else null end
  returning w.details_token into stored;
  -- Finished signups get a throwaway token, indistinguishable from a real one.
  return coalesce(stored, gen_random_uuid());
end;
$$;

drop function public.add_waitlist_details(text, uuid, text, text, text);
create function public.add_waitlist_details(p_email text, p_token uuid, p_work text, p_mac text, p_task text)
returns void
language plpgsql security definer set search_path = '' as $$
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
end;
$$;
revoke execute on function public.add_waitlist_details(text, uuid, text, text, text) from public;
grant execute on function public.add_waitlist_details(text, uuid, text, text, text) to anon, authenticated;
