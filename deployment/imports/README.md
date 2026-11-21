# Club CSV imports (Division K and other divisions)

## Where to put the file

Save each export in **`local-data/imports/clubs/`** inside the checkout, named
`district87-clubs-YYYY-MM-DD.csv` (the `checked_on` date). The whole `local-data/` folder is git-ignored.
**Never commit these files, and never copy them into `docs/` or any other tracked folder**: the repository is public
and the file holds contact details. Do not edit an earlier file; add a new dated one (freshest data wins, rule 13).

One row per club, for any division of District 87. UTF-8, comma-separated, header row exactly as below.

## Expected columns

`district, division, area, club_number, club_name, dashboard_club_name, program_year, checked_on,
dashboard_suspended_since, club_success_plan_submitted, membership_base, membership_to_date, membership_net_growth,
dcp_goals_met, dcp_1_level1_awards_target_4, dcp_2_level2_awards_target_2, dcp_3_additional_level2_awards_target_2,
dcp_4_level3_awards_target_2, dcp_5_level4_path_completion_or_dtm_target_1, dcp_6_additional_level4_path_completion_or_dtm_target_1,
dcp_7_new_members_target_4, dcp_8_additional_new_members_target_4, dcp_9a_officer_roles_trained_jun_aug_target_4,
dcp_9b_officer_roles_trained_nov_feb_target_4, dcp_10a_on_time_dues_dashboard_value, dcp_10b_on_time_officer_list_dashboard_value,
dcp_goals_achieved, meeting_schedule, meeting_timezone, meeting_format, venue, street_address, locality, state_or_territory,
postal_code, country, membership_restrictions, public_phone, public_contact_form_url, public_website_or_social_url,
public_secondary_link_url, alternate_venue_1_address, alternate_venue_1_public_phone, alternate_venue_2_address,
alternate_venue_2_public_phone, find_a_club_url, alternate_find_a_club_url, club_performance_url, district_roster_url,
meeting_language, language_evidence, language_source_url, published_venue_address, find_a_club_area, directory_check,
dashboard_chartered_on, notes`

## Running the import

```bash
export SUPABASE_CLI=/path/to/supabase SUPABASE_WORKDIR=/path/to/supabase-workdir
python3 deployment/imports/import_clubs.py local-data/imports/clubs/district87-clubs-YYYY-MM-DD.csv               # test project
python3 deployment/imports/import_clubs.py local-data/imports/clubs/district87-clubs-YYYY-MM-DD.csv --production  # owner approval
```

## What the import does (deployment/schema/009_club_directory.sql)

- **Identity:** `club_number` without leading zeros (`00763437` = `763437`), always shown without them. Areas without
  zero padding (`G01` = `G1`). Rows whose area is outside their division, or that lack a number, name, year or date,
  are refused and listed.
- **New clubs:** name, city (`locality`), time zone and currency from `country` + `meeting_timezone`
  (Malaysia: MYT/MYR, Brunei: BNT/BND, Indonesia UTC+7: WIB, UTC+8: WITA, UTC+9: WIT), charter date, and the
  program year's division, area and alignment.
- **Existing clubs** keep their name, city, time zone, currency and area (they may have been edited in the app);
  the TI name is kept beside it and a different area is reported, not changed.
- **Published club information** (owner decision, rule 1: public club information is published in full): schedule,
  format, language, venue, street address, locality, state, postal code, country, public phone, links, alternate
  venues, Find a Club and dashboard links, in `hdg_clubs.details.directory` with its `as_of` date. Readable by every
  district user, like all club information.
- **Figures** (membership base and to date, net growth, DCP goals and every `dcp_*` column, Club Success Plan,
  suspended since) in `hdg_club_figures`, one row per club and `checked_on` date, so history is kept.
- **Freshest data wins** (rule 13): a file older than the stored directory block does not replace it.
- **Checking notes** (`notes`, `language_evidence`, `language_source_url`, `directory_check`) are kept privately in
  `hdg_sync_private.legacy_records` and never shown to members.
- Re-importing the same file changes nothing. Club officers (with phone numbers) come from the separate officer CSV.
