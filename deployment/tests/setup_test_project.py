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
}


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

    # Stand-in app files and the same per-file policies production uses.
    for name in ('v645-community.html', 'v645-member.html'):
        body = f'<!doctype html><title>{name}</title>synthetic test file'.encode()
        request('POST', f'/storage/v1/object/hdg-private-app/{name}', secret, secret, body,
                {'Content-Type': 'text/html', 'x-upsert': 'true'})
    policy = (LOCAL.parents[1] / 'deployment' / 'storage-policy-v645.sql').read_text()
    names = [w.split()[0] for w in policy.split('create policy ')[1:]]
    sql(' '.join(f'drop policy if exists {n} on storage.objects;' for n in names))
    sql(policy.replace('begin;', '').replace('commit;', ''))

    LOCAL.parent.mkdir(exist_ok=True)
    LOCAL.write_text(json.dumps({'project_ref': TEST_REF, 'publishable_key': publishable, 'accounts': accounts}, indent=1))
    LOCAL.chmod(0o600)
    print(f'Test project {TEST_REF} ready: {len(accounts)} synthetic accounts, 2 clubs, stand-in app files.')


if __name__ == '__main__':
    main()
