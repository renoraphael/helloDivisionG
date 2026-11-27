# Database structure and the test project

- `000_baseline.sql` and `001_member_community.sql` hold the production structure as of v645 (tables, constraints, functions, views, row-level security, policies, grants, auth trigger, private bucket). Structure only: no records.
- The Free synthetic test project is `oenawxeckerazwhvlpse` (Hello Division G Synthetic Test, Singapore). It was bootstrapped with schema 000–022 and populated with invented accounts, clubs, and app fixtures.
- Apply 000 and 001 only to a fresh test project. Numbered migrations reach production through a separate owner-approved release after the access suite and a permission diff pass (project/DISTRICT_PLAN.md rules 28–31). Singapore production is `ovmdhkrkogivlvjnbqpj`. The retired Seoul project `bhbgusdxqbjwsdlzhurb` is paused and is never a deployment target.

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
| 020_privacy.sql | Versioned privacy notice, self-service export and profile clearing, maintainer deletion requests, retention and per-account onboarding | synthetic testing; production release pending |
| 021_bulk_division_roles.sql | Maintainer-only preview and atomic Director, AD and council role assignment by imported member ID | synthetic only |
| 022_leader_records.sql | Scoped TLI sessions and attendance, contests, performance and visits, plus owner-only tasks and a scoped projection from 009 | synthetic only |

The setup script writes the synthetic test passwords and the test project's publishable key to `local-data/test-project.json` (git-ignored). The test scripts default to the synthetic Singapore project. An optional `HDG_TEST_REF` override must name a separate synthetic project. Both production refs are rejected.

Production note (21 November 2026): 002 resets all function grants in `public` and re-grants the app's own. Supabase's helper `public.rls_auto_enable()` lost its `anon` grant and was restored by hand (`grant execute on function public.rls_auto_enable() to anon`); afterwards all 81 existing permissions matched a snapshot taken before. Repeat that check whenever 002-style grant resets are applied.


## Privacy and onboarding release

- Publish approved notice text through `hdg_publish_privacy_notice` with a new immutable version. The launcher reads the current notice at sign-in, and each acceptance gets its own timestamp.
- A tutorial reads `hdg_my_context` for `accessMode`, current `roles` with scope, and `onboardingSeen`. It calls `hdg_mark_onboarding_seen` with a stable step ID when shown.
- `deployment/privacy-cron.sql` registers one pg_cron job for 02:30 Singapore/Bali time. Install it in the synthetic project before the access matrix. Production installation is a separate activation step because the job erases eligible records.
- Deletion is serialized against membership changes, and the 12-month calculation uses the latest membership end. Existing records without enough evidence to determine an end date are excluded until reviewed. Historical officer seats keep their terms with the display name “Former member.”
- The current per-record export does not include legacy Division G backups, private HTML or unstructured historical awards and meeting notes. A known legacy identity match flags exports and blocks completion or automatic erasure. The legacy cutover and archive remediation require separate review before describing the export or deletion as complete for those records.
- The separate Division K app is retired. Keep Division K imports closed until the owner approves the notice and production privacy release. Migration 020 additionally requires a current notice and an enabled retention job before a maintainer can open a new division.


## Bulk Division K roles

Use `deployment/tools/bulk_division_roles.py` with a private CSV containing the exact header `memberId,role,area,title`. Use role values `division_director`, `area_director` and `division_council`. Fill the area for Area Directors and the title for council. Preserve member IDs as text when preparing the CSV.

Set `HDG_SUPABASE_PUBLISHABLE_KEY` to the target project's publishable key. Run the tool with `--email <maintainer-email> --year 2026` to preview in the synthetic project. The tool prompts for the password. Production use requires the approved release, the imported roster, an open division, an explicitly approved batch, and `--target production --apply`. A preview neither creates nor replaces assignments. Occupied seats must be resolved explicitly outside the batch.

## Leader data shadow copy

- Migration 022 adds a per-record API without switching dashboard reads or writes. Division and Area Directors use their own scopes. A division council reads within its division and can write only with edit rights. Tasks are private to the signed-in account, including from maintainers.
- TLI attendance uses a session and a membership. Existing 009 data stays authoritative for official TI DCP figures. Supplemental performance data has its own record type.
- For an approved rehearsal, run `python3 deployment/tools/check_leader_copy.py <private-snapshot.json> <private-mapping.json>`. The mapping has `alignment` (program year → club number → approved area), `taskOwners` (legacy profile → Auth account UUID), and `attendanceSessions` (club number and round → verified session and member ID mappings). The tool reports counts and blockers without printing member information. Add `--shadow <private-extract.json>` to compare canonical rows by source ID and content hash.
- The planner reports multi-area sessions, unmapped round attendance, unverified task ownership, raw visit email and legacy performance overrides as explicit blockers. No live data was copied. Do not switch what the app reads or writes until an approved shadow copy reconciles and the owner approves the switch.
