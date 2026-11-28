# Database structure and the test project

- `000_baseline.sql` and `001_member_community.sql` hold the production structure as of v645 (tables, constraints, functions, views, row-level security, policies, grants, auth trigger, private bucket). Structure only: no records.
- The Free synthetic test project is `oenawxeckerazwhvlpse` (Hello Division G Synthetic Test, Singapore). It was bootstrapped with schema 000–022 and populated with invented accounts, clubs, and app fixtures.
- Apply 000 and 001 only to a fresh test project. Numbered migrations reach production through a separate owner-approved release after the access suite and a permission diff pass (project/DISTRICT_PLAN.md rules 28–31). Verify project refs before running SQL:
  - **Singapore production** `ovmdhkrkogivlvjnbqpj` (`ap-southeast-1`) is **Hello Division G**.
  - **Singapore synthetic test** `oenawxeckerazwhvlpse` (`ap-southeast-1`) is **Hello Division G Synthetic Test**.
  - **Paused Seoul fallback** `bhbgusdxqbjwsdlzhurb` (`ap-northeast-2`) is **Hello Division G (Seoul, retired)** and is never a deployment target.

## Running the access tests

```bash
export SUPABASE_CLI=/path/to/supabase     # logged-in Supabase CLI
python3 deployment/tests/setup_test_project.py   # synthetic accounts and data; safe to re-run
python3 deployment/tests/access_matrix.py        # exit code 1 if any access check fails
python3 deployment/tests/legacy_copy_check.py    # Division G copy and comparison on a synthetic record
python3 deployment/tests/retention_check.py      # clean-up of full copies; re-run setup afterwards
python3 deployment/tests/club_import_check.py    # club CSV import on synthetic rows; re-run setup afterwards
```

## Files after the baseline

| File | What it adds | Where |
|---|---|---|
| 002_foundation.sql | Per-record tables, scoped access, roles with terms, edit history | test; **production, applied 21 November 2026** |
| 003_quiet_stale_saves.sql | Late saves of the shared record are set aside quietly (fixes the hanging save) | test; **production, applied 21 November 2026** with the owner's approval |
| 004_quiet_record_edits.sql | Late per-record edits: unchanged fields saved, late values set aside | test; **production, applied 21 November 2026** |
| 005_legacy_copy.sql | Copy a division's shared record into the new tables, and compare | test; **production, applied 21 November 2026** |
| 006_error_reports.sql | Error reports for the maintainer, grouped and scrubbed | test; **production, applied 21 November 2026** |
| 007_releases.sql | Release list, current file per channel, one-step rollback | test; **production, applied 21 November 2026** |
| 008_retention.sql | Clean-up: late copies after 7 days, revision history keeps the last 10 saves | test; **production, applied 21 November 2026** with the owner's approval |
| 009_club_directory.sql | Club directory import: public club information, dashboard figures per date, private checking notes | test; production structure applied 21 November 2026 (no rows imported yet) |
| 010_temporary_access.sql | Temporary access while a division is set up: provisional people, access mode `setup`, `hdg_my_context` | test; **production, applied 21 November 2026** |
| 011_division_council.sql | Division council role with a title: read-only across its division, editing by exception (`hdg_grant_role_edit`); titles in the leadership directory | test; **production, applied 23 November 2026** |
| 012_district_team_directory.sql | District team members (with titles) in the leadership directory; still no member records | test; **production, applied 23 November 2026** |
| 013_division_releases.sql | Release slots for division apps (channel `division` + division code), download only for that division's leaders, launcher routing | synthetic tests only; **do not release** (27 November 2026 decision) |
| 014_division_community.sql | Data a division app receives at sign-in (`hdg_division_community`): clubs, DCP goals, officers, leaders, agenda names in read scope; no emails | synthetic tests only; **do not release** (27 November 2026 decision) |
| 015_meetings.sql | One record per club meeting under its meeting code (agenda, timer times, typed-in ballots, Table Topics names, first download); role takers from that meeting's agenda (Timer, Ballot Counter, TTM, Toastmaster) matched by name, unique names only, from the day before to the day after; one phone ballot per meeting; voting links work whoever published them | test; production 25 Nov 2026 (owner approved) |
| 016_meeting_rights.sql | Per-meeting rights (owner decision 25 Nov 2026): all club officers edit; the Toastmaster of the Meeting edits the whole agenda; every role taker (any role, speaker, evaluator) fixes their own line; club members see club meetings, sign up for empty roles or a new speaker line; on the day any role taker or club member saves times, Table Topics and adds ballots (results only for leaders, Ballot Counter, Toastmaster); others' agenda changes are trimmed, never merged | test; production 25 Nov 2026 (owner approved) |
| 017_club_exco.sql | Clubs manage their own Exco (owner decision 25 Nov 2026): any current officer of a club (and its leaders) gives a seat to an active member of the club, effective at once; officer list imports apply only to seats not changed by the club or a leader on or after the list date; seats missing from a newer list are vacated; hdg_roles gets source and source_at | test; production 25 Nov 2026 (owner approved) |
| 018_member_import.sql | Toastmasters member list into hdg_people and hdg_memberships: leaders of the club only, city only (other row fields refused), member ID match, hand-corrected fields kept and reported, newest list wins per club, snapshot marks missing members past, undo of a club's latest import, conflict choice | test; **production, applied 26 November 2026** (owner approved) |
| 019_district_imports.sql | Imports for clubs outside Division G (owner decisions 27 Nov 2026): hdg_import_clubs lists every club with whether the leader may import it; a division's imports open only when the maintainer opens them (hdg_set_division_import, after PDPA); the 017/018 import functions move behind that check; Division G open | test; **production, applied 28 November 2026 in Singapore** |
| 020_privacy.sql | Versioned privacy notice, self-service export and profile clearing, maintainer correction and deletion requests, retention and per-account onboarding | **production, applied 28 November 2026 in Singapore**. Notice approval pending |
| 021_bulk_division_roles.sql | Maintainer-only preview and atomic Director, Area Director and council assignments by imported member ID | synthetic test; **Singapore production, applied 28 November 2026** |
| 022_leader_records.sql | Scoped events and visits, multi-area event coverage, session and round attendance, supplemental club figures, private tasks, and an official DCP projection from 009 | synthetic test; **Singapore production, applied 28 November 2026** |
| 023_leader_cutover.sql | Timed save pause, event compatibility writes and one-step route reset | synthetic draft, rollout gated by end-to-end app rehearsal |

The setup script writes the synthetic test passwords and the test project's publishable key to `local-data/test-project.json` (git-ignored). The test scripts default to the synthetic Singapore project. An optional `HDG_TEST_REF` override must name a separate synthetic project. Both production refs are rejected.

Production note (21 November 2026): 002 resets all function grants in `public` and re-grants the app's own. Supabase's helper `public.rls_auto_enable()` lost its `anon` grant and was restored by hand (`grant execute on function public.rls_auto_enable() to anon`); afterwards all 81 existing permissions matched a snapshot taken before. Repeat that check whenever 002-style grant resets are applied.


## Privacy and onboarding release

- Production rollout on 28 November 2026 verified the overnight encrypted backup from 07:12 WITA and the Docker practice restore (69 matching tables, including Auth). The migration rehearsal rolled back before application.
- Migration 020 added 30 permission entries. Existing grants, row-level policies, column grants and default privileges were unchanged. Thirteen new public RPCs granted EXECUTE to authenticated and service_role. The nine private functions, seven private tables, and retention-run sequence are owner-only. No anon or PUBLIC grant was added by migration 020.
- Cron installation added 17 managed permission entries without changing existing permissions. Supabase's nine object-level PUBLIC ACLs in the new cron schema are unreachable by anon or authenticated because neither has schema USAGE. The nightly job runs as postgres.
- Production probes under the authenticated role used the existing account identities for a leader, an active member and the sole maintainer. The exports were account-scoped, the active member's deletion request was rejected, and only the maintainer could see either queue. The probes rolled back and logged no individual data. The notice is still unpublished.


- Publish approved notice text through `hdg_publish_privacy_notice` with a new immutable version. The launcher reads the current notice at sign-in, and each acceptance gets its own timestamp.
- A tutorial reads `hdg_my_context` for `accessMode`, current `roles` with scope, and `onboardingSeen`. It calls `hdg_mark_onboarding_seen` with a stable step ID when shown.
- `deployment/privacy-cron.sql` registers one pg_cron job for 02:30 Singapore/Bali time. Install it in the synthetic project before the access matrix. Production activation was approved on 28 November 2026. The first run started and finished at 2026-11-28 07:33:43 WITA. Count erased was 0.
- Deletion is serialized against membership changes, and the 12-month calculation uses the latest membership end. Existing records without enough evidence to determine an end date are excluded until reviewed. Historical officer seats and normalized individual awards keep their history with the display name “Former member.”
- The retention log contains only timestamps, run status and the total erased count. Roster corrections are private cases available to their requester through self-export and to the maintainer through Reports. They never enter the application error report feed.
- The current per-record export does not include legacy Division G backups, private HTML or unstructured historical awards and meeting notes. A known legacy identity match flags exports and blocks completion or automatic erasure. The legacy cutover and archive remediation require separate review before describing the export or deletion as complete for those records.
- The separate Division K app is retired. Keep Division K imports closed until the owner approves and publishes the notice. Migration 020 additionally requires a current notice and an enabled retention job before a maintainer can open a new division.

## Division G leader data shadow copy

- The production dry run rolled back. The applied permission snapshot matched it exactly, with 19 new entries, zero existing changes or removals, and no new anonymous or PUBLIC access. The combined synthetic access matrix passed 441/441.
- The Division G shadow copy of revision 28 matched all 177 rows. It contains 5 TLI sessions, 3 contests, 11 visits, 16 supplemental club performance records, and 142 round attendance records. Six events cover multiple areas. No session attendance was inferred and no manual tasks were present. There were zero missing, extra or changed rows in the mapped copy. The shared revision, 10 historical revisions and release pointers stayed unchanged.
- The four comparable DCP differences were between 009 figures dated 21 November and the legacy dashboard captured on 25 November. Both sources kept their dates. Two automatic task dismissals and 11 raw visit emails stay in the shared record for review. Division K imports stay closed.
- District plan rule 31 keeps the Division G shared record and revision history authoritative during the shadow copy. Migration 022 does not change dashboard routing. A switch requires a separate owner decision.
- Events use approved alignment for their Toastmasters year. Combined events retain every covered area on one record. Officer round flags are deduplicated by membership, year and round. Unknown remains unknown, and session attendance requires evidence connecting the person to a specific session.
- Legacy club dashboard figures keep the date the source revision was captured. Official Toastmasters values remain in `hdg_club_figures`. Hold free-text fields, raw visit email and automatic task dismissals in the shared record pending review.
- `deployment/tools/bulk_division_roles.py` takes a private CSV with header `memberId,role,area,title`. Use `division_director`, `area_director` or `division_council`, with area for an Area Director and a title for council. Preview is the default. Applying a batch requires a signed-in maintainer, an eligible imported roster, and an open division.
- `deployment/tools/check_leader_copy.py <private-source.json> <private-mapping.json> --shadow <private-extract.json>` compares canonical records and prints counts only. The mapping holds `sourceDate`, `alignment` (program year → club number → approved area), and `memberships` (normalized club number and Toastmasters member ID joined by a colon → membership UUID). Use files for synthetic fixtures and keep production source and extracts in memory.
- The private v667 desktop preview adds a read-only view of scoped official figures and the latest Supabase import. The 6 PM WITA District 87 Dashboard Sync continues producing its ChatGPT report. Automatic ingestion needs a verified dated payload from the collector and a separate production deployment decision.

## Division G cutover rehearsal

- The owner approved the switch plan. Activate the per-record dashboard only after the original TLI, contest, visit, performance and task workflows pass end to end on fictional data and the refreshed production shadow matches the approved scope.
- The migration starts with the shared dashboard selected. A maintainer can pause migrated saves for up to five minutes and resume manually. Existing open tabs keep pending edits for retry. The synthetic route returns to shared with one maintainer call to `hdg_return_leader_to_shared`.
- The synthetic compatibility mirror supports structured updates to linked events. It commits the per-record row and shared fallback together, keeps independently changed fields, and sets aside conflicts. The existing fallback retains excluded text and original attachments. Event creation and deletion, attendance writes and the existing editors still require complete compatibility checks.
- The v668 preview uses the owner-only task APIs independently of the source for leader events. The protected build has not been released. No production pause or routing change has been applied.
