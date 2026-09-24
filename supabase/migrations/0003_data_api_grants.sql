-- The project doesn't expose new tables to the Data API automatically (Supabase's
-- recommended setting), so grant exactly what the app needs. Row-level security
-- still decides which rows each signed-in user can see. Signed-out users get nothing.
grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.skills to authenticated;
grant select, insert on public.receipts to authenticated;
-- Signed-out visitors never touch these tables, even though RLS would return no rows.
revoke all on public.profiles, public.skills, public.receipts from anon;
