#!/usr/bin/env python3
"""Create synthetic accounts and data in the Hello Division G TEST project.

Safe to re-run. Never run against production (test_env refuses it).
Writes test passwords to local-data/test-project.json (git-ignored).
Usage: SUPABASE_CLI=/path/to/supabase python3 deployment/tests/setup_test_project.py
"""
import json, secrets, string
from test_env import TEST_REF, LOCAL, keys, sql, request

ACCOUNTS = {   # role in the test -> synthetic email
    'admin': 'hdg-admin@example.com',
    'officer': 'hdg-officer@example.com',
    'inactive_officer': 'hdg-inactive-officer@example.com',
    'member': 'hdg-member@example.com',
    'past_member': 'hdg-past-member@example.com',
    'beta': 'hdg-beta@example.com',
    'outsider': 'hdg-outsider@example.com',
    # Foundation (002) roles
    'dd_g': 'hdg-dd-g@example.com',
    'ad_g1': 'hdg-ad-g1@example.com',
    'am': 'hdg-am@example.com',
    'prm': 'hdg-prm@example.com',
    'cross': 'hdg-cross@example.com',          # member in Division G, Area Director in Division K
    'member_k': 'hdg-member-k@example.com',
    'chair': 'hdg-alignment-chair@example.com',
    'past_ad': 'hdg-past-ad@example.com',      # Area Director last year only
    'dd_k': 'hdg-dd-k@example.com',            # Division Director K (areas K1 and K2)
    'k_new': 'hdg-k-director-new@example.com', # signs up before Division K is imported (010 temporary access)
    'council_k': 'hdg-council-k@example.com',  # Division K council member (011): read-only across Division K
}

# Fixed IDs for synthetic people, so tests can refer to them.
PEOPLE = {
    'admin': '00000000-0000-4000-8000-000000000001', 'officer': '00000000-0000-4000-8000-000000000002',
    'member': '00000000-0000-4000-8000-000000000003', 'past_member': '00000000-0000-4000-8000-000000000004',
    'dd_g': '00000000-0000-4000-8000-000000000005', 'ad_g1': '00000000-0000-4000-8000-000000000006',
    'am': '00000000-0000-4000-8000-000000000007', 'prm': '00000000-0000-4000-8000-000000000008',
    'cross': '00000000-0000-4000-8000-000000000009', 'member_k': '00000000-0000-4000-8000-000000000010',
    'chair': '00000000-0000-4000-8000-000000000011', 'past_ad': '00000000-0000-4000-8000-000000000012',
    'kappa_no_account': '00000000-0000-4000-8000-000000000013',
    'dd_k': '00000000-0000-4000-8000-000000000014', 'kappa2_no_account': '00000000-0000-4000-8000-000000000015',
    'council_k': '00000000-0000-4000-8000-000000000016',
}
# (person, club, status)
MEMBERSHIPS = [('admin', '9000001', 'active'), ('officer', '9000001', 'active'), ('member', '9000001', 'active'),
    ('past_member', '9000002', 'past'), ('dd_g', '9000002', 'active'), ('ad_g1', '9000001', 'active'),
    ('am', '9000003', 'active'), ('prm', '9000002', 'active'), ('cross', '9000001', 'active'),
    ('member_k', '9000003', 'active'), ('chair', '9000003', 'active'), ('past_ad', '9000002', 'active'),
    ('kappa_no_account', '9000003', 'active'), ('dd_k', '9000004', 'active'), ('kappa2_no_account', '9000004', 'active'), ('council_k', '9000004', 'active')]
# (person, role, scope_code, year_start)
ROLES = [('admin', 'maintainer', 'system', None), ('officer', 'club_president', '9000001', 2026),
    ('dd_g', 'division_director', 'G', 2026), ('ad_g1', 'area_director', 'G1', 2026), ('am', 'am', '87', 2026),
    ('prm', 'prm', '87', 2026), ('cross', 'area_director', 'K1', 2026), ('chair', 'alignment_chair', '87', 2026),
    ('past_ad', 'area_director', 'G2', 2025), ('dd_k', 'division_director', 'K', 2026), ('council_k', 'division_council', 'K', 2026)]


def foundation_sql():
    q = lambda v: 'null' if v is None else "'" + str(v).replace("'", "''") + "'"
    people = ','.join(f"({q(pid)}, {q('T' + pid[-7:])}, {q('Test ' + k.replace('_', ' ').title())}, "
                      f"{q(ACCOUNTS.get(k))})" for k, pid in PEOPLE.items())
    mships = ','.join(f"({q(PEOPLE[k])}, {q(c)}, {q(st)})" for k, c, st in MEMBERSHIPS)
    roles = []
    for k, role, code, year in ROLES:
        scope = ('club' if role.startswith('club_') else 'area' if role == 'area_director' else
                 'division' if role in ('division_director', 'division_council') else 'system' if role == 'maintainer' else 'district')
        start = "current_date" if year is None else f"make_date({year}, 7, 1)"
        end = 'null' if year is None else f"make_date({year + 1}, 6, 30)"
        roles.append(f"({q(PEOPLE[k])}, {q(role)}, {q(scope)}, {q(code)}, {q(year)}::int, {start}, {end})")
    return f"""
    truncate public.hdg_roles, public.hdg_memberships, public.hdg_import_freshness, public.hdg_club_alignment,
      public.hdg_areas, public.hdg_people, public.hdg_clubs, public.hdg_divisions, public.hdg_program_years cascade;
    insert into public.hdg_program_years(year_start, transition_opens) values (2025, '2025-05-15'), (2026, '2026-05-15'), (2027, '2027-05-15');
    insert into public.hdg_divisions(code, name) values ('G', 'Division G'), ('K', 'Division K');
    insert into public.hdg_areas(year_start, code, division_code) values
      (2025, 'G1', 'G'), (2025, 'G2', 'G'), (2026, 'G1', 'G'), (2026, 'G2', 'G'), (2026, 'K1', 'K'), (2026, 'K2', 'K'),
      (2027, 'G1', 'G'), (2027, 'K1', 'K'), (2027, 'K2', 'K');
    insert into public.hdg_clubs(club_number, name, city, timezone, currency) values
      ('9000001', 'Test Alpha Club', 'Testville', 'Asia/Makassar', 'IDR'),
      ('9000002', 'Test Beta Club', 'Sampletown', 'Asia/Jakarta', 'IDR'),
      ('9000003', 'Test Kappa Club', 'Kuching', 'Asia/Kuala_Lumpur', 'MYR'),
      ('9000004', 'Test Kappa Two Club', 'Bandar', 'Asia/Brunei', 'BND');
    insert into public.hdg_club_alignment(year_start, club_number, area_code) values
      (2025, '9000001', 'G1'), (2025, '9000002', 'G2'),
      (2026, '9000001', 'G1'), (2026, '9000002', 'G2'), (2026, '9000003', 'K1'), (2026, '9000004', 'K2');
    insert into public.hdg_people(id, ti_member_id, name, email) values {people};
    insert into public.hdg_memberships(person_id, club_number, status) values {mships};
    insert into public.hdg_roles(person_id, role, scope_type, scope_code, year_start, starts_on, ends_on) values {','.join(roles)};
    update public.hdg_roles set title = 'Assistant Director Program Quality' where role = 'division_council';
    """



def password():
    a = string.ascii_letters + string.digits
    return ''.join(secrets.choice(a) for _ in range(16))


def payload():
    clubs = [
        {'number': '9000001', 'name': 'Test Alpha Club', 'area': 'G1', 'city': 'Testville', 'mode': 'In person', 'dcpGoals': '3'},
        {'number': '9000002', 'name': 'Test Beta Club', 'area': 'G2', 'city': 'Sampletown', 'mode': 'Hybrid', 'dcpGoals': '0'},
    ]
    people = [
        ('Test Admin', 'admin', '9000001', True, False),
        ('Test Officer', 'officer', '9000001', True, False),
        ('Test Inactive Officer', 'inactive_officer', '9000002', True, False),
        ('Test Member', 'member', '9000001', True, False),
        ('Test Past Member', 'past_member', '9000002', False, True),
    ]
    memberships = [{'key': f'T{i}', 'memberId': f'T{i:07d}', 'name': n, 'email': ACCOUNTS[r], 'clubNumber': c,
                    'active': a, 'pastMember': p} for i, (n, r, c, a, p) in enumerate(people, 1)]
    exco = [{'clubNumber': '9000001', 'role': 'Club President', 'name': 'Test Officer', 'contact': ACCOUNTS['officer']}]
    collections = ['reports', 'tlis', 'contests', 'prospects', 'membershipImports', 'officerImports', 'tasks',
                   'taskDismissals', 'specialMeetings', 'meetingAgendaRecords', 'leadershipTeams']
    db = {'schemaVersion': 4, 'areas': [{'code': 'G1', 'director': 'Test Area Director'}, {'code': 'G2', 'director': ''}],
          'clubs': clubs, 'memberships': memberships, 'exco': exco, 'memberIdentityAliases': {}}
    db.update({k: [] for k in collections})
    return {'database': db, 'settings': {'divisionDirector': 'Test Division Director'}}


def main():
    publishable, secret = keys()
    stored = json.loads(LOCAL.read_text()) if LOCAL.exists() else {}
    accounts = stored.get('accounts', {})
    status, existing = request('GET', '/auth/v1/admin/users?per_page=200', secret, secret)
    by_email = {u['email']: u['id'] for u in existing.get('users', [])}
    for role, email in ACCOUNTS.items():
        pw = accounts.get(role, {}).get('password') or password()
        if email in by_email:
            request('PUT', f'/auth/v1/admin/users/{by_email[email]}', secret, secret, {'password': pw, 'email_confirm': True})
            uid = by_email[email]
        else:
            s, u = request('POST', '/auth/v1/admin/users', secret, secret,
                           {'email': email, 'password': pw, 'email_confirm': True, 'user_metadata': {'display_name': role}})
            if s >= 300:
                raise SystemExit(f'Could not create {role}: {s} {u}')
            uid = u['id']
        accounts[role] = {'email': email, 'password': pw, 'id': uid}

    p = json.dumps(payload()).replace("'", "''")
    sql(f"""
    insert into public.hdg_sync_state(division_code, revision, payload) values ('G', 1, '{p}'::jsonb)
      on conflict (division_code) do update set payload = excluded.payload;
    delete from public.hdg_officer_access;
    insert into public.hdg_officer_access(user_id, division_code, app_role, active) values
      ('{accounts['admin']['id']}', 'G', 'administrator', true),
      ('{accounts['officer']['id']}', 'G', 'officer', true),
      ('{accounts['inactive_officer']['id']}', 'G', 'officer', false);
    delete from hdg_community_private.beta_members;
    insert into hdg_community_private.beta_members(user_id) values ('{accounts['beta']['id']}');
    """)

    sql(foundation_sql())

    # Stand-in app files and the same per-file policies production uses.
    for name in ('v645-community.html', 'v645-member.html', 'v646-community.html', 'v655-division-k.html'):
        body = f'<!doctype html><title>{name}</title>synthetic test file'.encode()
        request('POST', f'/storage/v1/object/hdg-private-app/{name}', secret, secret, body,
                {'Content-Type': 'text/html', 'x-upsert': 'true'})
    policy = (LOCAL.parents[1] / 'deployment' / 'storage-policy-v645.sql').read_text()
    names = [w.split()[0] for w in policy.split('create policy ')[1:]]
    sql(' '.join(f'drop policy if exists {n} on storage.objects;' for n in names))
    sql(policy.replace('begin;', '').replace('commit;', ''))

    # Registered releases (007): v645 is current for both channels; v646 community is uploaded but not current.
    sql("""
    truncate public.hdg_releases; truncate hdg_sync_private.error_reports;
    insert into public.hdg_releases(channel, version, file, is_current, made_current_at) values
      ('community', 'v645', 'v645-community.html', true, now() - interval '1 day'),
      ('member', 'v645', 'v645-member.html', true, now() - interval '1 day'),
      ('community', 'v646', 'v646-community.html', false, null);
    insert into public.hdg_releases(channel, division_code, version, file, is_current, made_current_at) values
      ('division', 'K', 'v655', 'v655-division-k.html', true, now());
    """)

    LOCAL.parent.mkdir(exist_ok=True)
    LOCAL.write_text(json.dumps({'project_ref': TEST_REF, 'publishable_key': publishable, 'accounts': accounts, 'people': PEOPLE}, indent=1))
    LOCAL.chmod(0o600)
    print(f'Test project {TEST_REF} ready: {len(accounts)} synthetic accounts, 4 clubs in 2 divisions, stand-in app files.')


if __name__ == '__main__':
    main()
