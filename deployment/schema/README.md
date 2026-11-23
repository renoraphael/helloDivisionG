# Database structure and the test project

- `000_baseline.sql` and `001_member_community.sql` hold the production structure as of v645 (tables, constraints, functions, views, row-level security, policies, grants, auth trigger, private bucket). Structure only: no records.
- They were read from production with catalog queries and applied to the **test project** `ovmdhkrkogivlvjnbqpj` ("Hello Division G Test", Singapore, free plan). On 20 November 2026 a comparison found identical columns, constraints, policies and function bodies. The only differences were the order of permission entries and Supabase's own `rls_auto_enable` helper.
- Never apply 000 or 001 to production (they describe it). Never apply the numbered files to production (`bhbgusdxqbjwsdlzhurb`). New structure is added as numbered files (002, 003, …), tested in the test project with `deployment/tests/access_matrix.py`, and only reaches production as a separate, owner-approved step (project/DISTRICT_PLAN.md rules 28–31).

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
| 012_district_team_directory.sql | District team members (with titles) in the leadership directory; still no member records | test; production waits for approval |

The setup script writes the synthetic test passwords and the test project's publishable key to `local-data/test-project.json` (git-ignored). Both scripts refuse the production project.

Production note (21 November 2026): 002 resets all function grants in `public` and re-grants the app's own. Supabase's helper `public.rls_auto_enable()` lost its `anon` grant and was restored by hand (`grant execute on function public.rls_auto_enable() to anon`); afterwards all 81 existing permissions matched a snapshot taken before. Repeat that check whenever 002-style grant resets are applied.
