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

## How the importer will use it (planned, Phase 1; not built yet)

- **Identity:** `club_number`, stored without leading zeros (`00763437` and `763437` are the same club) and always
  shown without them.
- **Alignment:** `division` + `area` for `program_year`, written to `hdg_club_alignment` for that year only, and only
  inside the importing person's scope (rule 14).
- **Club information everyone may see** (rule 2): name, city (`locality`), meeting schedule, format, time zone
  (`meeting_timezone` mapped to WIB / WITA / WIT / MYT), language, the club's public venue, and its public links.
- **Club performance** (membership base and to date, DCP goals, Club Success Plan, suspension): stored per club and
  `checked_on` date, so an older file never overwrites newer figures (rule 13).
- **Contact columns are club-level public directory data, not member data.** Member street addresses and member
  phone numbers are never stored (rule 1). Before the import, the owner decides whether the club's public phone and
  street-level venue address are kept or reduced to city only.
- `notes`, `language_evidence`, `directory_check` are checking notes for the maintainer, not shown to members.
- Manual club edits made in the app are never overwritten by an import (rule 11); a differing value is asked about.
