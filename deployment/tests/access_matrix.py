#!/usr/bin/env python3
"""Automatic access tests: sign in as each role and check what it can and cannot reach.

Runs against the TEST project only (synthetic data). Exit code 1 if any check fails,
which blocks a release (project/DISTRICT_PLAN.md rule 29).
Usage: python3 deployment/tests/setup_test_project.py   (once, or after a reset)
       python3 deployment/tests/access_matrix.py
"""
import sys, uuid
from test_env import request, load_local

cfg = load_local()
KEY = cfg['publishable_key']
ROLES = list(cfg['accounts'])
results = []


def check(name, ok, detail=''):
    results.append((ok, name, detail))


def token(role):
    a = cfg['accounts'][role]
    s, r = request('POST', '/auth/v1/token?grant_type=password', KEY, body={'email': a['email'], 'password': a['password']})
    return r.get('access_token') if s == 200 else None


def rpc(fn, tok, body=None):
    return request('POST', f'/rest/v1/rpc/{fn}', KEY, tok, body or {})


T = {r: token(r) for r in ROLES}
T['signed_out'] = None
for r in ROLES:
    check(f'{r} can sign in', bool(T[r]))

# 1. Access mode for every role
# A deactivated officer who is still an active club member drops back to member access.
expected_mode = {'admin': 'leader', 'officer': 'leader', 'inactive_officer': 'member', 'member': 'member',
                 'past_member': 'none', 'beta': 'member', 'outsider': 'none'}
for r, want in expected_mode.items():
    s, got = rpc('hdg_access_mode', T[r])
    check(f'{r} access mode is {want}', s == 200 and got == want, f'{s} {got}')
s, got = rpc('hdg_access_mode', None)
check('signed-out cannot get a leader or member mode', got not in ('leader', 'member'), f'{s} {got}')

# 2. The shared division record (all member data) is readable by leaders only
for r in list(expected_mode) + ['signed_out']:
    s, rows = request('GET', '/rest/v1/hdg_sync_state?select=division_code', KEY, T[r])
    n = len(rows) if isinstance(rows, list) else 0
    want = 1 if expected_mode.get(r) == 'leader' else 0
    check(f'{r} sees {want} shared division record(s)', n == want, f'{s} {n}')

# 3. Officer approvals: each account sees only its own active row
for r in expected_mode:
    s, rows = request('GET', '/rest/v1/hdg_officer_access?select=user_id', KEY, T[r])
    ids = {x['user_id'] for x in rows} if isinstance(rows, list) else set()
    own = cfg['accounts'][r]['id']
    check(f'{r} sees no other account approvals', ids <= {own}, f'{s} {len(ids)}')

# 4. Member Community projection: members and leaders only
for r, mode in expected_mode.items():
    s, body = rpc('hdg_member_community', T[r])
    allowed = mode in ('leader', 'member')
    check(f'{r} {"can" if allowed else "cannot"} open the Community projection', (s == 200) == allowed, str(s))
s, body = rpc('hdg_member_community', None)
check('signed-out cannot open the Community projection', s != 200, str(s))
s, body = rpc('hdg_member_community', T['member'])
if s == 200:
    text = str(body)
    check('Community projection carries no member emails', '@example.com' not in text.replace(cfg['accounts']['officer']['email'], ''), '')

# 5. Saving the shared record: active officers only; private tables are not reachable
for r in ('member', 'beta', 'outsider', 'inactive_officer', 'past_member'):
    s, body = rpc('hdg_save_web_state', T[r], {'p_expected_revision': 1, 'p_payload': {}, 'p_request_id': str(uuid.uuid4())})
    check(f'{r} cannot save the shared record', s != 200, str(s))
for schema, table in (('hdg_sync_private', 'revision_history'), ('hdg_community_private', 'votes'), ('hdg_private', 'web_imports')):
    for r in ('admin', 'member', 'signed_out'):
        s, body = request('GET', f'/rest/v1/{table}?select=*', KEY, T[r], headers={'Accept-Profile': schema})
        check(f'{r} cannot read {schema}.{table} directly', s != 200, str(s))

# 6. Officer management: administrators only
s, body = rpc('hdg_manage_officer', T['officer'], {'p_email': cfg['accounts']['outsider']['email'], 'p_active': True})
check('officer cannot approve new officers', s != 200, str(s))
s, body = rpc('hdg_manage_officer', T['member'], {'p_email': cfg['accounts']['outsider']['email'], 'p_active': True})
check('member cannot approve officers', s != 200, str(s))

# 7. Protected app files
files = {'v645-community.html': 'leader', 'v645-member.html': 'member'}
for r, mode in list(expected_mode.items()) + [('signed_out', 'none')]:
    for f, who in files.items():
        s, _ = request('GET', f'/storage/v1/object/authenticated/hdg-private-app/{f}', KEY, T[r] or KEY)
        allowed = mode == who
        check(f'{r} {"can" if allowed else "cannot"} download {f}', (s == 200) == allowed, str(s))

# 8. Ballots: leaders publish; anyone with the link votes once per browser; votes stay anonymous
MEETING = 'test-meeting-' + uuid.uuid4().hex[:8]
s, b = rpc('hdg_manage_ballot', T['member'], {'p_meeting_id': MEETING, 'p_action': 'publish', 'p_title': 'X',
                                              'p_choices': {'prepared': [], 'evaluation': [], 'topics': []}})
check('member cannot publish a ballot', s != 200, str(s))
choices = {'prepared': [{'id': 'p1', 'name': 'Speaker One'}], 'evaluation': [], 'topics': []}
s, b = rpc('hdg_manage_ballot', T['officer'], {'p_meeting_id': MEETING, 'p_action': 'publish', 'p_title': 'Test ballot', 'p_choices': choices})
check('officer can publish a ballot', s == 200 and isinstance(b, dict), str(s))
if s == 200:
    tok = b['token']
    s, o = rpc('hdg_open_ballot', None, {'p_token': tok})
    check('signed-out guest can open the ballot link', s == 200 and o and o.get('title') == 'Test ballot', str(s))
    browser = str(uuid.uuid4())
    vote = {'p_token': tok, 'p_browser_id': browser, 'p_choices': {'prepared': 'p1', 'evaluation': '', 'topics': ''}}
    s1, _ = rpc('hdg_cast_ballot', None, vote)
    s2, _ = rpc('hdg_cast_ballot', None, vote)
    s, st = rpc('hdg_manage_ballot', T['officer'], {'p_meeting_id': MEETING, 'p_action': 'status'})
    responses = st.get('responses') if isinstance(st, dict) else None
    check('a vote sent twice from one browser counts once', s1 == 200 and s2 == 200 and responses == 1, f'{responses}')
    s, st = rpc('hdg_manage_ballot', T['admin'], {'p_meeting_id': MEETING, 'p_action': 'status'})
    check("another leader cannot read this officer's ballot count", st in (None, '') or (isinstance(st, dict) and st.get('token') != tok), str(s))
    rpc('hdg_manage_ballot', T['officer'], {'p_meeting_id': MEETING, 'p_action': 'close'})
    s, o = rpc('hdg_open_ballot', None, {'p_token': tok})
    check('a closed ballot link no longer opens', o in (None, ''), str(s))

failed = [r for r in results if not r[0]]
for ok, name, detail in results:
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if not ok and detail else ''))
print(f'\n{len(results) - len(failed)}/{len(results)} access checks passed.')
sys.exit(1 if failed else 0)
