# Database structure and the test project

- `000_baseline.sql` and `001_member_community.sql` hold the production structure as of v645 (tables, constraints, functions, views, row-level security, policies, grants, auth trigger, private bucket). Structure only: no records.
- The Free synthetic test project is `oenawxeckerazwhvlpse` (Hello Division G Synthetic Test, Singapore). It was bootstrapped with schema 000–019 and populated with invented accounts, clubs, and app fixtures.
- Apply 000 and 001 only to a fresh test project. Numbered migrations reach production through a separate owner-approved release after the access suite and a permission diff pass (project/DISTRICT_PLAN.md rules 28–31). Singapore production is `ovmdhkrkogivlvjnbqpj`. The retired Seoul project is paused.

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
| 013_division_releases.sql | Release slots for division apps (channel `division` + division code), download only for that division's leaders, launcher routing | test; production waits for approval |
| 014_division_community.sql | Data a division app receives at sign-in (`hdg_division_community`): clubs, DCP goals, officers, leaders, agenda names in read scope; no emails | test; production waits for approval |
| 015_meetings.sql | One record per club meeting under its meeting code (agenda, timer times, typed-in ballots, Table Topics names, first download); role takers from that meeting's agenda (Timer, Ballot Counter, TTM, Toastmaster) matched by name, unique names only, from the day before to the day after; one phone ballot per meeting; voting links work whoever published them | test; production 25 Nov 2026 (owner approved) |
| 016_meeting_rights.sql | Per-meeting rights (owner decision 25 Nov 2026): all club officers edit; the Toastmaster of the Meeting edits the whole agenda; every role taker (any role, speaker, evaluator) fixes their own line; club members see club meetings, sign up for empty roles or a new speaker line; on the day any role taker or club member saves times, Table Topics and adds ballots (results only for leaders, Ballot Counter, Toastmaster); others' agenda changes are trimmed, never merged | test; production 25 Nov 2026 (owner approved) |
| 017_club_exco.sql | Clubs manage their own Exco (owner decision 25 Nov 2026): any current officer of a club (and its leaders) gives a seat to an active member of the club, effective at once; officer list imports apply only to seats not changed by the club or a leader on or after the list date; seats missing from a newer list are vacated; hdg_roles gets source and source_at | test; production 25 Nov 2026 (owner approved) |
| 018_member_import.sql | Toastmasters member list into hdg_people and hdg_memberships: leaders of the club only, city only (other row fields refused), member ID match, hand-corrected fields kept and reported, newest list wins per club, snapshot marks missing members past, undo of a club's latest import, conflict choice | test; **production, applied 26 November 2026** (owner approved) |
| 019_district_imports.sql | Imports for clubs outside Division G (owner decisions 27 Nov 2026): hdg_import_clubs lists every club with whether the leader may import it; a division's imports open only when the maintainer opens them (hdg_set_division_import, after PDPA); the 017/018 import functions move behind that check; Division G open | test; **production, applied 28 November 2026 in Singapore** |

The setup script writes the synthetic test passwords and the test project's publishable key to `local-data/test-project.json` (git-ignored). The test scripts default to the synthetic Singapore project. An optional `HDG_TEST_REF` override must name a separate synthetic project. Both production refs are rejected.

Production note (21 November 2026): 002 resets all function grants in `public` and re-grants the app's own. Supabase's helper `public.rls_auto_enable()` lost its `anon` grant and was restored by hand (`grant execute on function public.rls_auto_enable() to anon`); afterwards all 81 existing permissions matched a snapshot taken before. Repeat that check whenever 002-style grant resets are applied.
