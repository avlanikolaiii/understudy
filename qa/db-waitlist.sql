-- Mass test of the waitlist and table security, as an anonymous visitor, rolled back at the end.
-- Paste into the Supabase SQL editor and run. It returns one row: each counter, what it should be,
-- and "ok". Nothing is kept: the transaction rolls back, and the last query confirms 0 rows remain.
begin;
set local role anon;

do $$
declare
  tok uuid; tok2 uuid; i int; n_join int := 0; n_same_token int := 0; n_details int := 0;
  n_wrong_token int := 0; n_invalid_rejected int := 0; n_denied int := 0; n_attempts int := 0;
  bad text[] := array['', ' ', 'plain', 'a@b', '@x.com', 'x@.com', 'a b@c.com', 'a@b c.com', 'a@@b.com', 'a@b.c'];
  statements text[] := array[
    'select count(*) from public.waitlist', 'insert into public.waitlist(email) values (''direct@example.com'')',
    'update public.waitlist set work = ''agency''', 'delete from public.waitlist',
    'select count(*) from public.skills', 'insert into public.skills(name) values (''x'')',
    'select count(*) from public.receipts', 'select count(*) from public.profiles'];
  s text;
begin
  -- 500 people join, with mixed case and stray spaces.
  for i in 1..500 loop
    tok := public.join_waitlist(case when i % 3 = 0 then '  QA-' || i || '@Example.com ' else 'qa-' || i || '@example.com' end, 'qa');
    if tok is not null then n_join := n_join + 1; end if;
    -- 300 of them answer the optional questions with their token.
    if i <= 300 then
      perform public.add_waitlist_details('qa-' || i || '@example.com', tok, 'agency', 'notch', 'Weekly report ' || i);
      n_details := n_details + 1;
    end if;
    -- 200 join again from another tab before answering: they must get the same token.
    if i > 300 then
      tok2 := public.join_waitlist('QA-' || i || '@example.com', 'qa');
      if tok2 = tok then n_same_token := n_same_token + 1; end if;
    end if;
  end loop;
  -- 100 answers with a wrong token change nothing.
  for i in 301..400 loop
    perform public.add_waitlist_details('qa-' || i || '@example.com', gen_random_uuid(), 'other', 'not-mac', 'forged');
    n_wrong_token := n_wrong_token + 1;
  end loop;
  -- 200 invalid emails (10 shapes × 20) are rejected.
  for i in 1..20 loop
    foreach s in array bad loop
      begin
        perform public.join_waitlist(s, 'qa');
      exception when invalid_parameter_value then n_invalid_rejected := n_invalid_rejected + 1;
      end;
    end loop;
  end loop;
  -- Direct table access is always denied.
  foreach s in array statements loop
    n_attempts := n_attempts + 1;
    begin
      execute s;
    exception when insufficient_privilege then n_denied := n_denied + 1;
    end;
  end loop;
  perform set_config('qa.join', n_join::text, true);
  perform set_config('qa.same_token', n_same_token::text, true);
  perform set_config('qa.details', n_details::text, true);
  perform set_config('qa.wrong_token', n_wrong_token::text, true);
  perform set_config('qa.invalid', n_invalid_rejected::text, true);
  perform set_config('qa.denied', n_denied::text, true);
  perform set_config('qa.attempts', n_attempts::text, true);
end $$;

reset role;
with facts as (
  select
    current_setting('qa.join')::int as joined,
    current_setting('qa.same_token')::int as same_token_on_rejoin,
    current_setting('qa.invalid')::int as invalid_rejected,
    current_setting('qa.denied')::int as direct_access_denied,
    current_setting('qa.attempts')::int as direct_access_attempts,
    (select count(*) from public.waitlist where email like 'qa-%@example.com') as rows_stored,
    (select count(*) from public.waitlist where email like 'qa-%' and email <> lower(trim(email))) as rows_not_normalized,
    (select count(*) from public.waitlist where email like 'qa-%' and details_at is not null) as rows_with_details,
    (select count(*) from public.waitlist where first_task = 'forged') as forged_details
)
select *,
  (joined = 500 and same_token_on_rejoin = 200 and invalid_rejected = 200 and direct_access_denied = direct_access_attempts
   and rows_stored = 500 and rows_not_normalized = 0 and rows_with_details = 300 and forged_details = 0) as ok
from facts;
rollback;

-- Must be 0: nothing from this test remains.
select count(*) as rows_left_after_rollback from public.waitlist where email like 'qa-%@example.com';
