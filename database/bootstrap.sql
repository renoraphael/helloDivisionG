begin;
create schema if not exists hdg_private;
revoke all on schema hdg_private from public, anon, authenticated;

create table if not exists hdg_private.web_imports (
  id uuid primary key default gen_random_uuid(),
  source_sha256 text not null unique check (source_sha256 ~ '^[0-9a-f]{64}$'),
  exported_at timestamptz not null,
  imported_at timestamptz not null default now(),
  source_text text not null,
  payload jsonb not null,
  check (payload ->> 'format' = 'hello-division-dashboard'),
  check (jsonb_typeof(payload #> '{data,database}') = 'object'),
  check (encode(sha256(convert_to(source_text, 'UTF8')), 'hex') = source_sha256),
  check (payload = source_text::jsonb)
);
alter table hdg_private.web_imports enable row level security;
revoke all on hdg_private.web_imports from public, anon, authenticated;

create table if not exists hdg_private.import_collections (
  import_id uuid not null references hdg_private.web_imports(id),
  collection text not null,
  value jsonb not null,
  primary key (import_id, collection)
);
alter table hdg_private.import_collections enable row level security;
revoke all on hdg_private.import_collections from public, anon, authenticated;

-- These staging views retain every source record without guessing person identity.
create or replace view hdg_private.web_areas with (security_invoker = true) as
select c.import_id, r.ordinality as source_position, r.value ->> 'code' as area_code, r.value as source_record
from hdg_private.import_collections c
cross join lateral jsonb_array_elements(c.value) with ordinality r(value, ordinality)
where c.collection = 'areas';
create or replace view hdg_private.web_clubs with (security_invoker = true) as
select c.import_id, r.ordinality as source_position, r.value ->> 'number' as club_number,
       r.value ->> 'area' as area_code, r.value as source_record
from hdg_private.import_collections c
cross join lateral jsonb_array_elements(c.value) with ordinality r(value, ordinality)
where c.collection = 'clubs';
create or replace view hdg_private.web_memberships with (security_invoker = true) as
select c.import_id, r.ordinality as source_position, r.value ->> 'memberId' as member_id,
       r.value ->> 'clubNumber' as club_number, r.value ->> 'key' as source_key,
       r.value as source_record
from hdg_private.import_collections c
cross join lateral jsonb_array_elements(c.value) with ordinality r(value, ordinality)
where c.collection = 'memberships';
create or replace view hdg_private.web_officer_assignments with (security_invoker = true) as
select c.import_id, r.ordinality as source_position, r.value ->> 'memberId' as member_id,
       r.value ->> 'clubNumber' as club_number, r.value ->> 'role' as officer_role,
       r.value as source_record
from hdg_private.import_collections c
cross join lateral jsonb_array_elements(c.value) with ordinality r(value, ordinality)
where c.collection = 'exco';
revoke all on all tables in schema hdg_private from public, anon, authenticated;

-- Empty approval registry: roster entries never automatically grant app access.
create table if not exists public.hdg_officer_access (
  user_id uuid not null references auth.users(id),
  division_code text not null default 'G',
  app_role text not null check (app_role in ('administrator','officer')),
  active boolean not null default true,
  approved_at timestamptz not null default now(),
  primary key (user_id, division_code)
);
alter table public.hdg_officer_access enable row level security;
revoke all on public.hdg_officer_access from public, anon, authenticated;
-- No client grants or policies yet. Configure them alongside the tested auth adapter.
commit;
select 'Private staging schema ready; no app access granted' as result;
