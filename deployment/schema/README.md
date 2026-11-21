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
```

## Files after the baseline

| File | What it adds | Where |
|---|---|---|
| 002_foundation.sql | Per-record tables, scoped access, roles with terms, edit history | test |
| 003_quiet_stale_saves.sql | Late saves of the shared record are set aside quietly (fixes the hanging save) | test; **production, applied 21 November 2026** with the owner's approval |
| 004_quiet_record_edits.sql | Late per-record edits: unchanged fields saved, late values set aside | test |
| 005_legacy_copy.sql | Copy a division's shared record into the new tables, and compare | test |
| 006_error_reports.sql | Error reports for the maintainer, grouped and scrubbed | test |
| 007_releases.sql | Release list, current file per channel, one-step rollback | test |
| 008_retention.sql | Clean-up: late copies after 7 days, revision history keeps the last 10 saves | test; **production, applied 21 November 2026** with the owner's approval |

The setup script writes the synthetic test passwords and the test project's publishable key to `local-data/test-project.json` (git-ignored). Both scripts refuse the production project.
