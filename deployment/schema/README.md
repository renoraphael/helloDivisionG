# Database structure and the test project

- `000_baseline.sql` and `001_member_community.sql` hold the production structure as of v645 (tables, constraints, functions, views, row-level security, policies, grants, auth trigger, private bucket). Structure only: no records.
- They were read from production with catalog queries and applied to the **test project** `ovmdhkrkogivlvjnbqpj` ("Hello Division G Test", Singapore, free plan). On 20 November 2026 a comparison found identical columns, constraints, policies and function bodies. The only differences were the order of permission entries and Supabase's own `rls_auto_enable` helper.
- Never apply these files to production (`bhbgusdxqbjwsdlzhurb`). New structure is added as numbered files (002, 003, …), tested in the test project with `deployment/tests/access_matrix.py`, and only reaches production as a separate, owner-approved step (project/DISTRICT_PLAN.md rules 28–31).

## Running the access tests

```bash
export SUPABASE_CLI=/path/to/supabase     # logged-in Supabase CLI
python3 deployment/tests/setup_test_project.py   # synthetic accounts and data; safe to re-run
python3 deployment/tests/access_matrix.py        # exit code 1 if any access check fails
```

The setup script writes the synthetic test passwords and the test project's publishable key to `local-data/test-project.json` (git-ignored). Both scripts refuse the production project.
