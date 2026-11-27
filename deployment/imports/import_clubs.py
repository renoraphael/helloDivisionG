#!/usr/bin/env python3
"""Import a District 87 club CSV into the per-record tables (deployment/schema/009_club_directory.sql).

Usage:
  SUPABASE_CLI=/path/to/supabase python3 deployment/imports/import_clubs.py local-data/imports/clubs/district87-clubs-YYYY-MM-DD.csv
      -> imports into the TEST project (default)
  ... --production   -> imports into production (only with the owner's approval)

The CSV stays on this computer (local-data/ is git-ignored). The rows are passed to the database through a
temporary file that only this user can read and that is deleted straight after.
"""
import argparse, csv, json, os, subprocess, sys, tempfile
from pathlib import Path

PRODUCTION_REF = 'ovmdhkrkogivlvjnbqpj'
RETIRED_PRODUCTION_REF = 'bhbgusdxqbjwsdlzhurb'
TEST_REF = os.environ.get('HDG_TEST_REF')
EXPECTED = ('district division area club_number club_name dashboard_club_name program_year checked_on dashboard_suspended_since '
            'club_success_plan_submitted membership_base membership_to_date membership_net_growth dcp_goals_met '
            'dcp_1_level1_awards_target_4 dcp_2_level2_awards_target_2 dcp_3_additional_level2_awards_target_2 '
            'dcp_4_level3_awards_target_2 dcp_5_level4_path_completion_or_dtm_target_1 '
            'dcp_6_additional_level4_path_completion_or_dtm_target_1 dcp_7_new_members_target_4 '
            'dcp_8_additional_new_members_target_4 dcp_9a_officer_roles_trained_jun_aug_target_4 '
            'dcp_9b_officer_roles_trained_nov_feb_target_4 dcp_10a_on_time_dues_dashboard_value '
            'dcp_10b_on_time_officer_list_dashboard_value dcp_goals_achieved meeting_schedule meeting_timezone meeting_format '
            'venue street_address locality state_or_territory postal_code country membership_restrictions public_phone '
            'public_contact_form_url public_website_or_social_url public_secondary_link_url alternate_venue_1_address '
            'alternate_venue_1_public_phone alternate_venue_2_address alternate_venue_2_public_phone find_a_club_url '
            'alternate_find_a_club_url club_performance_url district_roster_url meeting_language language_evidence '
            'language_source_url published_venue_address find_a_club_area directory_check dashboard_chartered_on notes').split()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('csv', type=Path)
    ap.add_argument('--production', action='store_true', help='import into production (owner approval required)')
    args = ap.parse_args()
    ref = PRODUCTION_REF if args.production else TEST_REF
    if not args.production and (not ref or ref in (PRODUCTION_REF, RETIRED_PRODUCTION_REF)):
        sys.exit('Set HDG_TEST_REF to a separate synthetic test project, or explicitly choose --production.')
    with args.csv.open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != EXPECTED:
            missing = [c for c in EXPECTED if c not in (reader.fieldnames or [])]
            sys.exit(f'Header does not match deployment/imports/README.md. Missing: {missing}')
        rows = [{k: (v or '').strip() for k, v in r.items()} for r in reader]
    if not rows:
        sys.exit('The file has no rows.')
    payload = json.dumps(rows, ensure_ascii=False)
    tag = 'hdgclubs' + os.urandom(6).hex()
    query = f"select hdg_sync_private.import_clubs(${tag}${payload}${tag}$::jsonb) as result;"
    fd, tmp = tempfile.mkstemp(suffix='.sql')
    try:
        os.chmod(tmp, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as out:
            out.write(query)
        cli = os.environ.get('SUPABASE_CLI', 'supabase')
        run = subprocess.run([cli, 'db', 'query', f'--remote={ref}', '--yes', '--output-format', 'json', '--file', tmp],
                             capture_output=True, text=True, cwd=os.environ.get('SUPABASE_WORKDIR'))
    finally:
        os.remove(tmp)
    out = run.stdout
    if run.returncode or '"rows"' not in out:
        sys.exit('Import failed: ' + (run.stderr or out)[-1500:])
    result = json.loads(out[out.index('{'):])['rows'][0]['result']
    print(f"{'PRODUCTION' if args.production else 'test project'} {ref}: {len(rows)} rows read")
    print(json.dumps(result, indent=1))


if __name__ == '__main__':
    main()
