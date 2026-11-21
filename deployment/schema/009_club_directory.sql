-- 009: District 87 club directory import (Phase 1). TEST project first.
-- Source: local-data/imports/clubs/district87-clubs-YYYY-MM-DD.csv (git-ignored), converted to JSON rows by
-- deployment/imports/import_clubs.py and passed to hdg_sync_private.import_clubs as the database owner.
-- Owner decision 21 November 2026 (rule 1): public club information is published in full (venue and street
-- address, public phone, links, schedule). Rules 9, 11, 13 apply:
--  * clubs by TI club number without leading zeros; areas without zero padding (G01 = G1);
--  * an existing club keeps its name, city, time zone and currency (they may have been edited in the app);
--    the TI name is kept as details.directory.ti_name;
--  * the directory block and the figures are only replaced by a file with the same or a newer checked_on date;
--  * the agent's checking notes are kept privately, never shown to members.

alter table hdg_sync_private.legacy_records drop constraint if exists legacy_records_kind_check;
alter table hdg_sync_private.legacy_records add constraint legacy_records_kind_check
  check (kind in ('club', 'member_notes', 'club_import_notes'));

-- Club figures from the Toastmasters dashboard, one row per club and checked date (public on the TI dashboard).
create table if not exists public.hdg_club_figures (
 club_number text not null references public.hdg_clubs,
 as_of date not null,
 year_start int not null,
 membership_base int,
 membership_to_date int,
 membership_net_growth int,
 dcp_goals_met int,
 club_success_plan text,
 suspended_since date,
 dcp jsonb not null default '{}' check (jsonb_typeof(dcp) = 'object'),
 imported_at timestamptz not null default now(),
 primary key (club_number, as_of));
alter table public.hdg_club_figures enable row level security;
drop policy if exists hdg_club_figures_read on public.hdg_club_figures;
create policy hdg_club_figures_read on public.hdg_club_figures for select to authenticated
  using ((select hdg_sync_private.is_district_user()));
revoke all on public.hdg_club_figures from public, anon, authenticated;
grant select on public.hdg_club_figures to authenticated;

create or replace function hdg_sync_private.safe_int(t text) returns int language plpgsql immutable set search_path to ''
as $$ begin return nullif(regexp_replace(coalesce(t, ''), '[^0-9-]', '', 'g'), '')::int; exception when others then return null; end $$;

create or replace function hdg_sync_private.area_code(t text) returns text language sql immutable set search_path to ''
as $$ select case when upper(btrim(coalesce(t, ''))) ~ '^[A-Z]0*[0-9]{1,2}$'
  then regexp_replace(upper(btrim(t)), '^([A-Z])0*([0-9]+)$', '\1\2') end $$;

create or replace function hdg_sync_private.import_clubs(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare r jsonb; num text; area text; div text; yr int; asof date; tz text; cur text; country text; dir jsonb;
  added int := 0; updated int := 0; skipped_older int := 0; figures int := 0; realigned jsonb := '[]'; bad jsonb := '[]';
  existing public.hdg_clubs%rowtype;
begin
 if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'Rows must be a JSON array'; end if;
 for r in select * from jsonb_array_elements(p_rows) loop
   num := hdg_sync_private.club_no(r->>'club_number');
   div := upper(btrim(coalesce(r->>'division', '')));
   area := hdg_sync_private.area_code(r->>'area');
   yr := hdg_sync_private.safe_int(left(coalesce(r->>'program_year', ''), 4));
   asof := hdg_sync_private.safe_date(r->>'checked_on');
   if num is null or div !~ '^[A-Z]$' or area is null or left(area, 1) <> div or yr is null or asof is null
      or length(btrim(coalesce(r->>'club_name', ''))) = 0 then
     bad := bad || jsonb_build_array(jsonb_build_object('club_number', r->>'club_number', 'division', r->>'division', 'area', r->>'area'));
     continue;
   end if;
   country := btrim(coalesce(r->>'country', ''));
   if country = '' then  -- the division's usual country
     select case when count(*) filter (where x->>'country' = 'Malaysia') > count(*) filter (where x->>'country' = 'Indonesia') then 'Malaysia' else 'Indonesia' end
       into country from jsonb_array_elements(p_rows) x where upper(x->>'division') = div;
   end if;
   tz := case
     when country ilike 'Brunei%' then 'Asia/Brunei'
     when country = 'Malaysia' then 'Asia/Kuala_Lumpur'
     when r->>'meeting_timezone' like 'UTC+07%' then 'Asia/Jakarta'
     when r->>'meeting_timezone' like 'UTC+09%' then 'Asia/Jayapura'
     else 'Asia/Makassar' end;
   cur := case when country ilike 'Brunei%' then 'BND' when country = 'Malaysia' then 'MYR' else 'IDR' end;
   dir := jsonb_strip_nulls(jsonb_build_object(
     'as_of', asof, 'ti_name', coalesce(nullif(btrim(r->>'dashboard_club_name'), ''), nullif(btrim(r->>'club_name'), '')),
     'meeting_schedule', nullif(btrim(r->>'meeting_schedule'), ''), 'meeting_timezone', nullif(btrim(r->>'meeting_timezone'), ''),
     'meeting_format', nullif(btrim(r->>'meeting_format'), ''), 'meeting_language', nullif(btrim(r->>'meeting_language'), ''),
     'venue', nullif(btrim(r->>'venue'), ''), 'street_address', nullif(btrim(r->>'street_address'), ''),
     'locality', nullif(btrim(r->>'locality'), ''), 'state_or_territory', nullif(btrim(r->>'state_or_territory'), ''),
     'postal_code', nullif(btrim(r->>'postal_code'), ''), 'country', nullif(country, ''),
     'published_venue_address', nullif(btrim(r->>'published_venue_address'), ''),
     'membership_restrictions', nullif(btrim(r->>'membership_restrictions'), ''),
     'public_phone', nullif(btrim(r->>'public_phone'), ''), 'contact_form_url', nullif(btrim(r->>'public_contact_form_url'), ''),
     'website_url', nullif(btrim(r->>'public_website_or_social_url'), ''), 'secondary_url', nullif(btrim(r->>'public_secondary_link_url'), ''),
     'alternate_venues', (select jsonb_agg(jsonb_strip_nulls(v)) from (
        select case when coalesce(btrim(r->>'alternate_venue_1_address'), '') <> '' then jsonb_build_object('address', btrim(r->>'alternate_venue_1_address'), 'phone', nullif(btrim(r->>'alternate_venue_1_public_phone'), '')) end v
        union all
        select case when coalesce(btrim(r->>'alternate_venue_2_address'), '') <> '' then jsonb_build_object('address', btrim(r->>'alternate_venue_2_address'), 'phone', nullif(btrim(r->>'alternate_venue_2_public_phone'), '')) end) z
        where v is not null),
     'find_a_club_url', nullif(btrim(r->>'find_a_club_url'), ''), 'alternate_find_a_club_url', nullif(btrim(r->>'alternate_find_a_club_url'), ''),
     'club_performance_url', nullif(btrim(r->>'club_performance_url'), ''), 'district_roster_url', nullif(btrim(r->>'district_roster_url'), ''),
     'find_a_club_area', nullif(btrim(r->>'find_a_club_area'), '')));

   insert into public.hdg_divisions(code, name) values (div, 'Division ' || div) on conflict do nothing;
   insert into public.hdg_program_years(year_start, transition_opens) values (yr, make_date(yr, 5, 15)) on conflict do nothing;
   insert into public.hdg_areas(year_start, code, division_code) values (yr, area, div) on conflict do nothing;

   select * into existing from public.hdg_clubs where club_number = num;
   if not found then
     insert into public.hdg_clubs(club_number, name, city, timezone, currency, chartered_on, details)
     values (num, left(btrim(r->>'club_name'), 160), nullif(btrim(r->>'locality'), ''), tz, cur,
             hdg_sync_private.safe_date(r->>'dashboard_chartered_on'), jsonb_build_object('directory', dir));
     added := added + 1;
   elsif coalesce((existing.details->'directory'->>'as_of')::date, '-infinity') <= asof then
     update public.hdg_clubs set details = details || jsonb_build_object('directory', dir),
       chartered_on = coalesce(chartered_on, hdg_sync_private.safe_date(r->>'dashboard_chartered_on'))
     where club_number = num and (details->'directory' is distinct from dir
       or (chartered_on is null and hdg_sync_private.safe_date(r->>'dashboard_chartered_on') is not null));
     if found then updated := updated + 1; end if;
   else
     skipped_older := skipped_older + 1;
   end if;

   -- Alignment for that program year: new clubs get the file's area; a different existing area is reported, not changed.
   insert into public.hdg_club_alignment(year_start, club_number, area_code) values (yr, num, area) on conflict do nothing;
   if exists (select 1 from public.hdg_club_alignment where year_start = yr and club_number = num and area_code <> area) then
     realigned := realigned || jsonb_build_array(jsonb_build_object('club_number', num, 'file_area', area));
   end if;

   insert into public.hdg_club_figures(club_number, as_of, year_start, membership_base, membership_to_date, membership_net_growth,
     dcp_goals_met, club_success_plan, suspended_since, dcp)
   values (num, asof, yr, hdg_sync_private.safe_int(r->>'membership_base'), hdg_sync_private.safe_int(r->>'membership_to_date'),
     hdg_sync_private.safe_int(r->>'membership_net_growth'), hdg_sync_private.safe_int(r->>'dcp_goals_met'),
     nullif(btrim(r->>'club_success_plan_submitted'), ''), hdg_sync_private.safe_date(r->>'dashboard_suspended_since'),
     (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each_text(r) e(k, v) where k like 'dcp\_%' and btrim(v) <> ''))
   on conflict (club_number, as_of) do update set membership_base = excluded.membership_base, membership_to_date = excluded.membership_to_date,
     membership_net_growth = excluded.membership_net_growth, dcp_goals_met = excluded.dcp_goals_met,
     club_success_plan = excluded.club_success_plan, suspended_since = excluded.suspended_since, dcp = excluded.dcp, imported_at = now();
   figures := figures + 1;

   insert into hdg_sync_private.legacy_records(kind, key, data)
   select 'club_import_notes', num, n from (select jsonb_strip_nulls(jsonb_build_object('as_of', asof,
       'notes', nullif(btrim(r->>'notes'), ''), 'language_evidence', nullif(btrim(r->>'language_evidence'), ''),
       'language_source_url', nullif(btrim(r->>'language_source_url'), ''), 'directory_check', nullif(btrim(r->>'directory_check'), ''))) n) x
   where n - 'as_of' <> '{}'::jsonb
   on conflict (kind, key) do update set data = excluded.data, copied_at = now()
     where (hdg_sync_private.legacy_records.data->>'as_of')::date <= asof;
 end loop;
 return jsonb_build_object('rows', jsonb_array_length(p_rows), 'clubs_added', added, 'clubs_updated', updated,
   'older_than_stored', skipped_older, 'figures', figures, 'area_differs_from_app', realigned, 'rows_refused', bad);
end $$;

revoke execute on function hdg_sync_private.safe_int(text), hdg_sync_private.area_code(text), hdg_sync_private.import_clubs(jsonb)
  from public, anon, authenticated;
