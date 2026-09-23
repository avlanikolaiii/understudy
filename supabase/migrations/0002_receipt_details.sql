-- Receipts show the skill, client, and report they belong to, even if the skill
-- is later deleted. `simulated` stays true until real connectors produce runs.
alter table public.receipts
  add column skill_name text check (skill_name is null or char_length(skill_name) <= 120),
  add column client text check (client is null or char_length(client) <= 120),
  add column report text check (report is null or char_length(report) <= 20000),
  add column simulated boolean not null default true;
