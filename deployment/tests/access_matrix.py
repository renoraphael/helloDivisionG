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
s, rows = request('GET', '/rest/v1/hdg_sync_state?select=revision,payload', KEY, T['officer'])
if s == 200 and rows:
    import time
    t0 = time.time()
    old_rev = rows[0]['revision'] - 1
    late = dict(rows[0]['payload']); late['settings'] = dict(late['settings'], divisionDirector='Late Edit')
    s, body = rpc('hdg_save_web_state', T['officer'], {'p_expected_revision': old_rev,
                  'p_payload': late, 'p_request_id': str(uuid.uuid4())})
    quick = time.time() - t0 < 10
    check('a late save answers at once with no error', s == 200 and quick, f'{s} {round(time.time() - t0, 1)}s')
    check('a late save is marked set aside and keeps the app on its old revision (so it reloads)',
          isinstance(body, dict) and body.get('superseded') is True and body.get('revision') == old_rev, str(body)[:120])
    s2, now_rows = request('GET', '/rest/v1/hdg_sync_state?select=revision,payload', KEY, T['officer'])
    check('a late save does not change the newer shared data',
          now_rows[0]['revision'] == rows[0]['revision'] and now_rows[0]['payload']['settings'].get('divisionDirector') != 'Late Edit', '')
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
    # 015: a meeting has one ballot, so another leader sees the same count (owner request 25 November 2026).
    check("another leader sees the same meeting's ballot count", isinstance(st, dict) and st.get('token') == tok and st.get('responses') == 1, str(s))
    rpc('hdg_manage_ballot', T['officer'], {'p_meeting_id': MEETING, 'p_action': 'close'})
    s, o = rpc('hdg_open_ballot', None, {'p_token': tok})
    check('a closed ballot link no longer opens', o in (None, ''), str(s))

# ---------------------------------------------------------------- 002 foundation: scoped access
P = cfg['people']
for r in ('dd_g', 'ad_g1', 'am', 'prm', 'cross', 'member_k', 'chair', 'past_ad', 'dd_k', 'council_k'):
    T[r] = token(r)


def seen_people(r):
    s, rows = request('GET', '/rest/v1/hdg_people?select=id', KEY, T[r])
    return {x['id'] for x in rows} if isinstance(rows, list) else set()


ALPHA = {P[k] for k in ('admin', 'officer', 'member', 'ad_g1', 'cross')}
BETA = {P[k] for k in ('past_member', 'dd_g', 'prm', 'past_ad')}
KAPPA = {P[k] for k in ('am', 'member_k', 'chair', 'kappa_no_account')}      # area K1
KAPPA2 = {P[k] for k in ('dd_k', 'kappa2_no_account', 'council_k')}          # area K2
expect_people = {
    'member': {P['member']},                        # own record only
    'officer': ALPHA,                               # club officer: own club
    'ad_g1': ALPHA,                                 # Area Director G1: clubs in G1
    'dd_g': ALPHA | BETA,                           # Division Director G: all of G, not K
    'am': ALPHA | BETA | KAPPA | KAPPA2,            # Administration Manager: everyone
    'prm': {P['prm']},                              # PRM: roll-ups only, so own record only
    'cross': {P['cross']} | KAPPA,                  # member in G (own record) + Area Director in K1, not K2
    'dd_k': KAPPA | KAPPA2,                         # Division Director K: every area in K, not G
    'council_k': KAPPA | KAPPA2,                    # Division K council member: reads all of K, not G
    'admin': {P['admin']},                          # maintainer: no silent access; uses the logged function
    'past_ad': {P['past_ad']},                      # last year's Area Director: term ended
    'outsider': set(),
}
for r, want in expect_people.items():
    got = seen_people(r)
    check(f'{r} sees exactly the people in their scope ({len(want)})', got == want, f'got {len(got)}')

s, rows = request('GET', '/rest/v1/hdg_clubs?select=club_number', KEY, T['member_k'])
check('a member sees every club in the district', isinstance(rows, list) and len(rows) == 4, str(len(rows) if isinstance(rows, list) else s))
s, rows = request('GET', '/rest/v1/hdg_clubs?select=club_number', KEY, T['outsider'])
check('an unknown account sees no clubs', rows == [], str(rows)[:80])
s, rows = request('GET', '/rest/v1/hdg_people?select=*', KEY, None)
check('signed-out sees no people', s != 200 or rows == [], str(s))

# Maintainer reads through a function that logs every use
s, rows = rpc('hdg_maintainer_people', T['admin'], {'p_division': 'K'})
check('maintainer can read Division K people through the logged function', s == 200 and {x['id'] for x in rows} == KAPPA | KAPPA2, str(s))
s, rows = rpc('hdg_maintainer_people', T['am'], {'p_division': 'K'})
check('non-maintainer cannot use the maintainer function', s != 200, str(s))


def person(r, pid):
    s, rows = request('GET', f'/rest/v1/hdg_people?id=eq.{pid}&select=*', KEY, T[r])
    return rows[0] if isinstance(rows, list) and rows else None


# Profiles and manual fields
me = person('member', P['member'])
s, res = rpc('hdg_update_my_profile', T['member'], {'p_person': P['member'], 'p_patch': {'nickname': 'Tester', 'aliases': ['T1', 'T2']}, 'p_expected_updated_at': me['updated_at']})
check('a member can set their own nickname and aliases', s == 200 and res.get('applied') is True, str(res)[:120])
ts = res.get('updated_at') if isinstance(res, dict) else None
s, res = rpc('hdg_update_my_profile', T['member'], {'p_person': P['member'], 'p_patch': {'nickname': 'Again'}, 'p_expected_updated_at': me['updated_at']})
check('a late edit of the same field answers with no error', s == 200, str(s))
check('a late edit of the same field keeps the newer value and sets the late one aside',
      isinstance(res, dict) and res.get('applied') is False and res.get('set_aside') == ['nickname']
      and person('member', P['member'])['nickname'] == 'Tester', str(res)[:120])
s, res = rpc('hdg_update_person', T['officer'], {'p_person': P['member'], 'p_patch': {'city': 'Testville'}, 'p_expected_updated_at': me['updated_at']})
merged = person('officer', P['member'])
check('a late edit of a different field is still saved (both changes kept)',
      s == 200 and res.get('applied') is True and merged['city'] == 'Testville' and merged['nickname'] == 'Tester', str(res)[:120])
s, _ = rpc('hdg_update_my_profile', T['member'], {'p_person': P['member'], 'p_patch': {'email': 'x@example.com'}, 'p_expected_updated_at': ts})
check('a member cannot change TI fields through their profile', s != 200, str(s))
s, _ = rpc('hdg_update_my_profile', T['member'], {'p_person': P['officer'], 'p_patch': {'nickname': 'X'}, 'p_expected_updated_at': me['updated_at']})
check("a member cannot edit someone else's profile", s != 200, str(s))

target = person('officer', P['member'])
s, ts2 = rpc('hdg_update_person', T['officer'], {'p_person': P['member'], 'p_patch': {'name': 'Test Member Corrected'}, 'p_expected_updated_at': target['updated_at']})
after = person('officer', P['member'])
check('a club officer can correct a member of their club', s == 200 and ts2.get('applied') is True, str(ts2)[:120])
check('a hand-corrected TI field is recorded for the next import', bool(after and 'name' in after['hand_corrected']), '')
check('manual nickname survives a leader edit', bool(after and after['nickname'] == 'Tester'), '')
k = person('am', P['member_k'])
s, _ = rpc('hdg_update_person', T['ad_g1'], {'p_person': P['member_k'], 'p_patch': {'nickname': 'X'}, 'p_expected_updated_at': k['updated_at']})
check('an Area Director cannot edit a member in another division', s != 200, str(s))
s, _ = rpc('hdg_update_person', T['cross'], {'p_person': P['member_k'], 'p_patch': {'nickname': 'Kay'}, 'p_expected_updated_at': k['updated_at']})
check('a cross-division role holder can edit inside their K1 area', s == 200, str(s))
k2 = person('dd_k', P['kappa2_no_account'])
s, _ = rpc('hdg_update_person', T['cross'], {'p_person': P['kappa2_no_account'], 'p_patch': {'nickname': 'X'}, 'p_expected_updated_at': k2['updated_at']})
check('the K1 Area Director cannot edit a member in area K2', s != 200, str(s))
s, _ = rpc('hdg_update_person', T['dd_k'], {'p_person': P['kappa2_no_account'], 'p_patch': {'nickname': 'Kay Two'}, 'p_expected_updated_at': k2['updated_at']})
check('the Division K Director can edit a member in any K area', s == 200, str(s))
s, _ = rpc('hdg_update_person', T['dd_k'], {'p_person': P['member'], 'p_patch': {'nickname': 'X'}, 'p_expected_updated_at': merged['updated_at']})
check('the Division K Director cannot edit a Division G member', s != 200, str(s))

# Edit history and undo
s, hist = rpc('hdg_edit_history', T['officer'], {'p_table': 'hdg_people', 'p_key': P['member']})
check('an officer can see the edit history of their club member', s == 200 and isinstance(hist, list) and len(hist) >= 2, str(s))
s, hist2 = rpc('hdg_edit_history', T['member_k'], {'p_table': 'hdg_people', 'p_key': P['member']})
check("a member cannot see another person's edit history", s == 200 and hist2 == [], str(hist2)[:80])
if isinstance(hist, list) and hist:
    last = hist[0]
    s, _ = rpc('hdg_undo_edit', T['officer'], {'p_history_id': last['id']})
    restored = person('officer', P['member'])
    check('the officer can undo their own edit', s in (200, 204) and restored['name'] != 'Test Member Corrected', str(s))
    s, _ = rpc('hdg_undo_edit', T['member_k'], {'p_history_id': last['id'] - 1})
    check("a member cannot undo someone else's edit", s != 200, str(s))

# Clubs
alpha = request('GET', '/rest/v1/hdg_clubs?club_number=eq.9000001&select=*', KEY, T['officer'])[1][0]
s, _ = rpc('hdg_update_club', T['officer'], {'p_club': '9000001', 'p_patch': {'details': {'venue': 'Test Hall'}}, 'p_expected_updated_at': alpha['updated_at']})
check('a club officer can edit their club details', s == 200, str(s))
beta = request('GET', '/rest/v1/hdg_clubs?club_number=eq.9000002&select=*', KEY, T['officer'])[1][0]
s, _ = rpc('hdg_update_club', T['officer'], {'p_club': '9000002', 'p_patch': {'details': {'venue': 'X'}}, 'p_expected_updated_at': beta['updated_at']})
check('a club officer cannot edit another club', s != 200, str(s))
s, _ = rpc('hdg_update_club', T['member'], {'p_club': '9000001', 'p_patch': {'details': {'venue': 'X'}}, 'p_expected_updated_at': alpha['updated_at']})
check('a member cannot edit club details', s != 200, str(s))
s, _ = rpc('hdg_update_club', T['dd_g'], {'p_club': '9000002', 'p_patch': {'timezone': 'Mars/Base'}, 'p_expected_updated_at': beta['updated_at']})
check('only supported time zones are accepted', s != 200, str(s))
s, lab = rpc('hdg_timezone_label', T['member'], {'tz': 'Asia/Kuala_Lumpur'})
check('Malaysian clubs show MYT', lab == 'MYT', str(lab))

# Roles and terms
def assign(r, person_key, role, code, year):
    return rpc('hdg_assign_role', T[r], {'p_person': P[person_key], 'p_role': role, 'p_scope_code': code, 'p_year': year})

s, rid = assign('ad_g1', 'member', 'club_vpe', '9000001', 2026)
check('an Area Director can give a club role inside their area', s == 200, str(rid)[:120])
s, _ = assign('ad_g1', 'member_k', 'club_vpe', '9000003', 2026)
check('an Area Director cannot give a role in another division', s != 200, str(s))
s, _ = assign('dd_g', 'prm', 'area_director', 'G2', 2026)
check('a Division Director can give an Area Director role in their division', s == 200, str(s))
s, _ = assign('dd_g', 'member', 'pqd', '87', 2026)
check('a Division Director cannot give district roles', s != 200, str(s))
s, _ = assign('officer', 'member', 'club_saa', '9000001', 2026)
check('a club officer cannot give roles', s != 200, str(s))
s, _ = assign('am', 'member', 'pqd', '87', 2027)
check("next year's officers are refused before the transition window opens", s != 200 and 'can be entered from' in str(_), str(_)[:120])
s, _ = assign('am', 'member_k', 'club_president', '9000003', 2026)
check('the Administration Manager can give any role', s == 200, str(s))
s, _ = assign('am', 'member', 'maintainer', 'system', 2026)
check('only a maintainer can give the maintainer role', s != 200, str(s))
if s != 200:
    s, rows = request('GET', f"/rest/v1/hdg_roles?role=eq.maintainer&select=id", KEY, T['admin'])
    mid = rows[0]['id'] if isinstance(rows, list) and rows else None
    s, _ = rpc('hdg_end_role', T['admin'], {'p_role_id': mid, 'p_ends_on': '2026-12-31'})
    check('the last maintainer cannot be removed', s != 200, str(s))
s, d = rpc('hdg_leadership_directory', T['member_k'], {})
roles = {(x['role'], x['scope_code']) for x in d} if isinstance(d, list) else set()
check('the leadership directory lists current leaders', {('division_director', 'G'), ('division_director', 'K'), ('area_director', 'K1')} <= roles, str(len(roles)))
check('the leadership directory does not list the maintainer', ('maintainer', 'system') not in roles, '')
s, d = rpc('hdg_leadership_directory', T['outsider'], {})
check('an unknown account gets an empty leadership directory', d == [], str(d)[:60])

# Realignment
s, _ = rpc('hdg_set_alignment', T['chair'], {'p_year': 2027, 'p_club': '9000002', 'p_area': 'G1'})
check('the Alignment Chair can draft next year\'s alignment', s in (200, 204), str(_)[:120])
s, _ = rpc('hdg_set_alignment', T['dd_g'], {'p_year': 2027, 'p_club': '9000001', 'p_area': 'K2'})
check('a Division Director cannot realign clubs', s != 200, str(s))
s, rows = request('GET', '/rest/v1/hdg_club_alignment?year_start=eq.2027&select=club_number,status', KEY, T['member'])
check('members do not see draft alignments', rows == [], str(rows)[:80])
s, rows = request('GET', '/rest/v1/hdg_club_alignment?year_start=eq.2027&select=club_number,status', KEY, T['am'])
check('the Administration Manager sees draft alignments', isinstance(rows, list) and len(rows) == 1 and rows[0]['status'] == 'draft', str(rows)[:80])
s, _ = rpc('hdg_set_alignment', T['chair'], {'p_year': 2026, 'p_club': '9000001', 'p_area': 'G2'})
check('mid-year realignment of an existing club is refused', s != 200, str(s))
s, n = rpc('hdg_approve_alignment', T['chair'], {'p_year': 2027})
check('the Alignment Chair can approve next year\'s alignment', s == 200 and n == 1, str(n))

# ---------------------------------------------------------------- 006 error reports
report = {'p_release': 'v645-community', 'p_page': '/ballot.html#vote=11111111-2222-4333-8444-555555555555',
          'p_message': 'TypeError: cannot read name of hdg-member@example.com, member 12345678, +62 812 3456 7890',
          'p_stack': 'at render (app.html:120:7)', 'p_browser': 'Test browser'}
s1, _ = rpc('hdg_report_error', None, report)
s2, _ = rpc('hdg_report_error', T['member'], dict(report, p_stack='at render (app.html:121:9)'))
check('anyone, even signed out, can send an error report', s1 in (200, 204) and s2 in (200, 204), f'{s1} {s2}')
s, reps = rpc('hdg_error_reports', T['admin'], {})
rep = reps[0] if isinstance(reps, list) and len(reps) == 1 else {}
check('the same error is grouped into one report with a count', rep.get('times') == 2, str(reps)[:160])
text = ' '.join(str(rep.get(k)) for k in ('page', 'message', 'stack'))
check('error reports carry no emails, member IDs, phone numbers or ballot links',
      '@' not in text and '12345678' not in text and '3456' not in text and 'vote=' not in text and '1111' not in text, text[:200])
for r in ('officer', 'member', 'am', 'signed_out'):
    s, body = rpc('hdg_error_reports', T[r], {})
    check(f'{r} cannot read error reports', s != 200, str(s))
s, _ = rpc('hdg_resolve_error', T['admin'], {'p_fingerprint': rep.get('fingerprint'), 'p_release': 'v646'})
s, reps = rpc('hdg_error_reports', T['admin'], {})
check('a resolved error leaves the open list', s == 200 and reps == [], str(reps)[:80])
rpc('hdg_report_error', None, report)
s, reps = rpc('hdg_error_reports', T['admin'], {})
check('a resolved error that happens again reopens', isinstance(reps, list) and len(reps) == 1 and reps[0]['times'] == 3, str(reps)[:80])

# ---------------------------------------------------------------- 007 releases and rollback
def current(r):
    s, body = rpc('hdg_current_release', T[r], {})
    return body.get('file') if isinstance(body, dict) else None

def download(r, f):
    return request('GET', f'/storage/v1/object/authenticated/hdg-private-app/{f}', KEY, T[r] or KEY)[0]

check('a leader is told to load the current community file', current('officer') == 'v645-community.html', str(current('officer')))
check('a member is told to load the current member file', current('member') == 'v645-member.html', str(current('member')))
check('an unknown account is told no file', current('outsider') is None, '')
check('an uploaded but not yet current release cannot be downloaded', download('officer', 'v646-community.html') != 200, '')
s, _ = rpc('hdg_set_release', T['officer'], {'p_channel': 'community', 'p_version': 'v646'})
check('only the maintainer can switch releases', s != 200, str(s))
s, _ = rpc('hdg_set_release', T['admin'], {'p_channel': 'community', 'p_version': 'v646'})
check('the maintainer can make a new release current', s == 200 and current('officer') == 'v646-community.html', str(s))
check('leaders can download the new current file', download('officer', 'v646-community.html') == 200, '')
check('members cannot download the community file', download('member', 'v646-community.html') != 200, '')
check('members keep their own channel', current('member') == 'v645-member.html', '')
s, back = rpc('hdg_rollback_release', T['admin'], {'p_channel': 'community'})
check('rollback is one step back to the previous release', s == 200 and current('officer') == 'v645-community.html', str(back)[:120])
# The storage CDN can repeat a cached answer for the exact same address and sign-in token, so check with a fresh request.
check('after rollback the newer file is no longer downloadable', download('officer', 'v646-community.html?after=rollback') != 200, '')
s, _ = rpc('hdg_rollback_release', T['admin'], {'p_channel': 'member'})
check('rollback with no earlier release is refused', s != 200, str(s))

# ---------------------------------------------------------------- 010 temporary access while a division is set up
T['k_new'] = token('k_new')
s, mode = rpc('hdg_access_mode', T['k_new'])
check('a new Division K leader without a record has no access yet', mode == 'none', str(mode))
s, _ = rpc('hdg_add_provisional_person', T['dd_g'], {'p_name': 'Test K Director', 'p_email': cfg['accounts']['k_new']['email']})
check('a Division Director cannot add provisional people', s != 200, str(s))
s, pid = rpc('hdg_add_provisional_person', T['admin'], {'p_name': 'Test K Director', 'p_email': cfg['accounts']['k_new']['email'].upper()})
check('the maintainer can add a provisional person by email', s == 200 and isinstance(pid, str), str(pid)[:80])
s, pid2 = rpc('hdg_add_provisional_person', T['admin'], {'p_name': 'Again', 'p_email': cfg['accounts']['k_new']['email']})
check('adding the same email again reuses the record', pid2 == pid, '')
s, mode = rpc('hdg_access_mode', T['k_new'])
check('a provisional person without a role still has no access', mode == 'none', str(mode))
s, _ = rpc('hdg_assign_role', T['admin'], {'p_person': pid, 'p_role': 'division_director', 'p_scope_code': 'K', 'p_year': 2026})
s, mode = rpc('hdg_access_mode', T['k_new'])
check('with a temporary Division Director role they get the setup mode', mode == 'setup', str(mode))
s, ctx = rpc('hdg_my_context', T['k_new'])
divs = {d['code']: d for d in ctx.get('divisions', [])} if isinstance(ctx, dict) else {}
check('the setup page shows only their division, with its clubs and areas', set(divs) == {'K'} and divs['K']['clubs'] == 2
      and divs['K']['areas'] == 2 and ctx.get('provisional') is True, str(ctx)[:160])
check('the setup page carries no member names or emails', '@' not in str(ctx) and 'Test Member' not in str(ctx), '')
for f in ('v646-community.html', 'v645-member.html'):
    st, _ = request('GET', f'/storage/v1/object/authenticated/hdg-private-app/{f}?setup=1', KEY, T['k_new'])
    check(f'the setup mode cannot download {f}', st != 200, str(st))
s, rows = request('GET', '/rest/v1/hdg_sync_state?select=division_code', KEY, T['k_new'])
check('the setup mode cannot read the Division G shared record', rows == [], str(rows)[:60])
for r, want in (('admin', 'leader'), ('officer', 'leader'), ('member', 'member'), ('outsider', 'none')):
    s, mode = rpc('hdg_access_mode', T[r])
    check(f'{r} keeps access mode {want}', mode == want, str(mode))
s, ctx = rpc('hdg_my_context', T['outsider'])
check('an unknown account gets onboarding context without district setup details',
      s == 200 and ctx.get('accessMode') == 'none' and ctx.get('name') is None
      and ctx.get('roles') == [] and ctx.get('divisions') == [])

# ---------------------------------------------------------------- 011 division council: read-only, edit by exception
kk = person('dd_k', P['kappa2_no_account'])
s, res = rpc('hdg_update_person', T['council_k'], {'p_person': P['kappa2_no_account'], 'p_patch': {'nickname': 'Council edit'}, 'p_expected_updated_at': kk['updated_at']})
check('a division council member cannot edit by default', s != 200, str(s))
s, rows = request('GET', f"/rest/v1/hdg_roles?person_id=eq.{P['council_k']}&role=eq.division_council&select=id,title", KEY, T['council_k'])
council_role = rows[0]['id'] if isinstance(rows, list) and rows else None
check('the council role carries its title', isinstance(rows, list) and rows and rows[0]['title'] == 'Assistant Director Program Quality', str(rows)[:120])
for r in ('dd_g', 'cross', 'council_k'):
    s, _ = rpc('hdg_grant_role_edit', T[r], {'p_role_id': council_role, 'p_granted': True})
    check(f'{r} cannot grant editing to a Division K council member', s != 200, str(s))
s, _ = rpc('hdg_grant_role_edit', T['dd_k'], {'p_role_id': council_role, 'p_granted': True})
check('the Division K Director can grant editing to their council member', s in (200, 204), str(s))
kk = person('dd_k', P['kappa2_no_account'])
s, res = rpc('hdg_update_person', T['council_k'], {'p_person': P['kappa2_no_account'], 'p_patch': {'nickname': 'Council edit'}, 'p_expected_updated_at': kk['updated_at']})
check('with the exception granted, the council member can edit in Division K', s == 200 and res.get('applied') is True, str(res)[:100])
s, _ = rpc('hdg_update_person', T['council_k'], {'p_person': P['member'], 'p_patch': {'nickname': 'X'}, 'p_expected_updated_at': kk['updated_at']})
check('even with editing granted, a Division K council member cannot edit Division G', s != 200, str(s))
rpc('hdg_grant_role_edit', T['dd_k'], {'p_role_id': council_role, 'p_granted': False})
kk = person('dd_k', P['kappa2_no_account'])
s, _ = rpc('hdg_update_person', T['council_k'], {'p_person': P['kappa2_no_account'], 'p_patch': {'nickname': 'Again'}, 'p_expected_updated_at': kk['updated_at']})
check('after the exception is withdrawn, editing is refused again', s != 200, str(s))
s, nid = rpc('hdg_assign_role', T['dd_k'], {'p_person': P['kappa2_no_account'], 'p_role': 'division_council', 'p_scope_code': 'K', 'p_year': 2026})
check('the Division K Director can add a council member', s == 200, str(nid)[:80])
s, _ = rpc('hdg_assign_role', T['dd_g'], {'p_person': P['kappa2_no_account'], 'p_role': 'division_council', 'p_scope_code': 'K', 'p_year': 2026})
check('the Division G Director cannot add Division K council members', s != 200, str(s))
s, _ = rpc('hdg_assign_role', T['cross'], {'p_person': P['kappa2_no_account'], 'p_role': 'division_council', 'p_scope_code': 'K', 'p_year': 2026})
check('an Area Director cannot add council members', s != 200, str(s))
s, _ = rpc('hdg_set_role_title', T['dd_k'], {'p_role_id': nid, 'p_title': 'Public Relations Manager'})
s, d = rpc('hdg_leadership_directory', T['member_k'], {})
titles = {(x['role'], x['scope_code'], x.get('title')) for x in d} if isinstance(d, list) else set()
check('the leadership directory shows council members with their titles',
      ('division_council', 'K', 'Assistant Director Program Quality') in titles and ('division_council', 'K', 'Public Relations Manager') in titles, str(titles)[:160])
s, mode = rpc('hdg_access_mode', T['council_k'])
check('a council member without Division G membership gets the setup page', mode == 'setup', str(mode))
s, ctx = rpc('hdg_my_context', T['council_k'])
check("the council member's setup page shows Division K and the title",
      isinstance(ctx, dict) and [x['code'] for x in ctx.get('divisions', [])] == ['K'] and any(r.get('title') for r in ctx.get('roles', [])), str(ctx)[:160])

# ---------------------------------------------------------------- 012 district team: no member records, listed with a title
s, tid = rpc('hdg_assign_role', T['dd_k'], {'p_person': P['past_member'], 'p_role': 'district_team', 'p_scope_code': '87', 'p_year': 2026})
check('a Division Director cannot give district team roles', s != 200, str(s))
s, tid = rpc('hdg_assign_role', T['am'], {'p_person': P['past_member'], 'p_role': 'district_team', 'p_scope_code': '87', 'p_year': 2026})
check('a district admin can give a district team role', s == 200, str(tid)[:80])
s, _ = rpc('hdg_set_role_title', T['am'], {'p_role_id': tid, 'p_title': 'Club Retention Chair'})
check('a district admin can set the district team title', s in (200, 204), str(s))
s, d = rpc('hdg_leadership_directory', T['member'], {})
rows = {(x['role'], x.get('title')) for x in d} if isinstance(d, list) else set()
check('the leadership directory lists district team members with their title', ('district_team', 'Club Retention Chair') in rows, str(rows)[:160])
check('the leadership directory still leaves out the maintainer', not any(x[0] == 'maintainer' for x in rows), '')
check('a district team role gives no extra member records', seen_people('past_member') == {P['past_member']}, f"got {len(seen_people('past_member'))}")

# ---------------------------------------------------------------- 013 division apps: only that division's leaders
def fresh(r, f):
    return request('GET', f'/storage/v1/object/authenticated/hdg-private-app/{f}?t={uuid.uuid4().hex[:8]}', KEY, T[r] or KEY)[0]
s, rel = rpc('hdg_current_release', T['k_new'], {})
check('a Division K leader is told to open the Division K app', isinstance(rel, dict) and rel.get('file') == 'v655-division-k.html' and rel.get('division') == 'K', str(rel)[:120])
s, rel = rpc('hdg_current_release', T['council_k'], {})
check('a Division K council member is told to open the Division K app', isinstance(rel, dict) and rel.get('division') == 'K', str(rel)[:120])
for r in ('k_new', 'council_k'):
    check(f'{r} can download the Division K app', fresh(r, 'v655-division-k.html') == 200, '')
for r in ('admin', 'officer', 'member', 'dd_g', 'outsider', 'signed_out'):
    check(f'{r} cannot download the Division K app', fresh(r, 'v655-division-k.html') != 200, '')
s, rel = rpc('hdg_current_release', T['officer'], {})
check('Division G leaders keep their own app', isinstance(rel, dict) and rel.get('channel') == 'community', str(rel)[:120])
s, _ = rpc('hdg_add_division_release', T['dd_k'], {'p_division': 'K', 'p_version': 'v656', 'p_file': 'v656-division-k.html', 'p_sha256': None})
check('only the maintainer can register a division app', s != 200, str(s))
s, _ = rpc('hdg_clear_division_release', T['admin'], {'p_division': 'K'})
s, rel = rpc('hdg_current_release', T['k_new'], {})
check('with no current Division K app, the leader is told nothing (setup page stays)', rel in (None, ''), str(rel)[:80])
check('with no current Division K app, its file cannot be downloaded', fresh('k_new', 'v655-division-k.html') != 200, '')
s, _ = rpc('hdg_set_division_release', T['admin'], {'p_division': 'K', 'p_version': 'v655'})
check('the maintainer can make the Division K app current again', s == 200, str(s))

# ---------------------------------------------------------------- 014 division data feed
s, feed = rpc('hdg_division_community', T['k_new'], {'p_division': 'K'})
clubs = {c['number']: c for c in feed.get('clubs', [])} if isinstance(feed, dict) else {}
check('a Division K leader gets the Division K clubs only', set(clubs) == {'9000003', '9000004'}, str(sorted(clubs))[:80])
check('each club carries its area and time zone label', clubs.get('9000003', {}).get('area') == 'K1' and clubs.get('9000003', {}).get('timezone') == 'MYT', str(clubs.get('9000003'))[:160])
leaders = {(l['role'], l['scope']): l['name'] for l in feed.get('leaders', [])} if isinstance(feed, dict) else {}
check('the feed names the Division Director and lists every area', leaders.get(('Division Director', 'K')) == 'Test K Director'
      and ('Area Director', 'K1') in leaders and ('Area Director', 'K2') in leaders, str(leaders)[:200])
check('the feed carries no emails', '@' not in str(feed), '')
check('agenda names include Division K members only', isinstance(feed, dict) and all(m['clubNumber'] in ('9000003', '9000004') for m in feed.get('agendaMembers', []))
      and len(feed.get('agendaMembers', [])) >= 1, str(len(feed.get('agendaMembers', []) if isinstance(feed, dict) else 0)))
s, f2 = rpc('hdg_division_community', T['council_k'], {'p_division': 'K'})
check('a Division K council member gets the feed', isinstance(f2, dict) and len(f2.get('clubs', [])) == 2, str(s))
for r, div in (('dd_g', 'K'), ('member', 'K'), ('outsider', 'K'), ('k_new', 'G'), ('past_member', 'K')):
    s, f3 = rpc('hdg_division_community', T[r], {'p_division': div})
    check(f'{r} gets no Division {div} feed', f3 in (None, ''), str(f3)[:60])
s, f4 = rpc('hdg_division_community', None, {'p_division': 'K'})
check('signed-out visitors get no feed', s != 200 or f4 in (None, ''), str(s))
s, f5 = rpc('hdg_division_community', T['admin'], {'p_division': 'K'})
check('the maintainer can read the feed', isinstance(f5, dict) and len(f5.get('clubs', [])) == 2, str(s))

# ---------------------------------------------------------------- 015 meetings: one record per meeting, role takers per meeting
from test_env import sql
sql("delete from public.hdg_meetings where club_number in ('9000001', '9000002', '9000003'); "
    "delete from hdg_community_private.votes where ballot_id in (select id from hdg_community_private.ballots where meeting_id like 'agenda-9000001-%'); "
    "delete from hdg_community_private.ballots where meeting_id like 'agenda-9000001-%'; "
    "update public.hdg_people set nickname = null where nickname = 'Twin'")
TODAY = sql("select hdg_sync_private.today()::text d")[0]['d']
MID = f'agenda-9000001-{TODAY}'
# Role takers hold no standing role over the club: a former Area Director, a member from another area's scope, a past member.
ROLES_TODAY = {'timer': 'Test Past Ad', 'ballotCounter': 'Test Cross (BTC)', 'tom': 'Test Past Member', 'ttm': 'Test Officer'}
def save_meeting(r, mid, patch, expected=None, date=TODAY):
    return rpc('hdg_save_meeting', T[r], {'p_meeting_id': mid, 'p_meeting_date': date, 'p_patch': patch, 'p_expected_updated_at': expected})
s, first = save_meeting('officer', MID, {'agenda': {'theme': 'Courage', 'roles': ROLES_TODAY}, 'downloaded': True})
check('a Division G leader saves a new meeting under its meeting code', s == 200 and first.get('applied') and first.get('created'), str(first)[:120])
s, again = save_meeting('officer', MID, {'agenda': {'theme': 'Courage, updated', 'roles': ROLES_TODAY}}, first.get('updated_at'))
check('saving the same meeting again updates the same record', s == 200 and again.get('applied') and not again.get('created'), str(again)[:120])
n = sql(f"select count(*)::int n, bool_and(first_downloaded_at is not null) d from public.hdg_meetings where meeting_id = '{MID}'")[0]
check('one record per meeting, first download recorded', n['n'] == 1 and n['d'], str(n))
for r in ('outsider', 'member_k', 'signed_out'):
    s, _ = rpc('hdg_save_meeting', T[r], {'p_meeting_id': MID, 'p_meeting_date': TODAY, 'p_patch': {'agenda': {}}, 'p_expected_updated_at': None})
    check(f'{r} cannot save the meeting', s != 200, str(s))
s, acc = rpc('hdg_my_meeting_access', T['past_ad'], {'p_meeting_id': MID})
check('today\'s Timer (from another club) runs the tools, fixes only their own line, adds ballots without seeing results',
      isinstance(acc, dict) and acc.get('canSaveTimer') and acc.get('canSaveTopics') and acc.get('ballots') == 'append'
      and acc.get('agenda') == 'own' and not acc.get('canSeeResults') and not acc.get('leader'), str(acc)[:200])
s, acc = rpc('hdg_my_meeting_access', T['cross'], {'p_meeting_id': MID})
check('today\'s Ballot Counter (name with a club suffix) gets the ballot and results', isinstance(acc, dict) and acc.get('canSaveBallots')
      and acc.get('ballots') == 'replace' and acc.get('canSeeResults') and acc.get('agenda') == 'own', str(acc)[:200])
s, acc = rpc('hdg_my_meeting_access', T['past_member'], {'p_meeting_id': MID})
check('the Toastmaster of the Meeting edits the whole agenda and sees results', isinstance(acc, dict) and acc.get('agenda') == 'full'
      and acc.get('canSeeResults') and acc.get('ballots') == 'replace', str(acc)[:200])
cur = again.get('updated_at')
s, t1 = save_meeting('past_ad', MID, {'timer_log': [{'id': 'time-1', 'person': 'Speaker', 'seconds': 400}]}, cur)
check('the Timer saves the timer times', s == 200 and t1.get('applied'), str(t1)[:120])
s, b1 = save_meeting('cross', MID, {'ballots': [{'id': 'ballot-1', 'prepared': 'p0'}]}, cur)
check('the Ballot Counter saves at the same time without overwriting the timer (both kept)', s == 200 and b1.get('applied') and not b1.get('set_aside'), str(b1)[:120])
row = sql(f"select jsonb_array_length(timer_log) t, jsonb_array_length(ballots) b from public.hdg_meetings where meeting_id = '{MID}'")[0]
check('timer times and ballots are both in the meeting', row == {'t': 1, 'b': 1}, str(row))
for r, patch in (('member_k', {'timer_log': []}), ('outsider', {'ballots': []}), ('member_k', {'agenda': {}})):
    s, _ = save_meeting(r, MID, patch, None)
    check(f'{r} (another club, no role) cannot save {list(patch)[0]}', s != 200, str(s))
s, helper = save_meeting('past_ad', MID, {'ballots': []}, None)
row = sql(f"select jsonb_array_length(ballots) b from public.hdg_meetings where meeting_id = '{MID}'")[0]
check('a helper sending an empty ballot list removes nobody\'s ballots', s == 200 and row['b'] == 1, f'{helper} {row}')
s, late = save_meeting('officer', MID, {'agenda': {'theme': 'Late copy', 'roles': ROLES_TODAY}}, first.get('updated_at'))
row = sql(f"select agenda->>'theme' t from public.hdg_meetings where meeting_id = '{MID}'")[0]
check('a late agenda save answers normally, keeps the newer agenda and sets the late one aside', s == 200 and late.get('set_aside') == ['agenda']
      and row['t'] == 'Courage, updated', f'{late} {row}')
s, lst = rpc('hdg_meetings_list', T['past_ad'], {'p_meeting_id': MID})
check('the Timer reads the meeting but not the ballots', isinstance(lst, list) and len(lst) == 1 and lst[0]['ballots'] == [] and lst[0]['myRoles'] == ['timer'], str(lst)[:160])
s, lst = rpc('hdg_meetings_list', T['cross'], {'p_meeting_id': MID})
check('the Ballot Counter reads the ballots', isinstance(lst, list) and len(lst) == 1 and len(lst[0]['ballots']) == 1, str(lst)[:160])
s, lst = rpc('hdg_meetings_list', T['outsider'], {})
check('an outsider reads no meetings', lst == [], str(lst)[:80])
s, lst = rpc('hdg_meetings_list', T['dd_g'], {'p_club': '00009000001'})
check('a Division Director reads the club\'s meetings (leading zeros ignored)', isinstance(lst, list) and len(lst) == 1, str(lst)[:80])
# Next meeting, different role takers: last week's Timer has no function in it.
NEXT = sql("select (hdg_sync_private.today())::text d")[0]['d']
MID2 = f'agenda-9000001-{NEXT}-b'
save_meeting('officer', MID2, {'agenda': {'roles': {'timer': 'Test Cross', 'ballotCounter': 'Test Past Ad'}}})
s, acc = rpc('hdg_my_meeting_access', T['past_ad'], {'p_meeting_id': MID2})
check('roles follow each meeting: the same member is Ballot Counter in another meeting', isinstance(acc, dict) and acc.get('roles') == ['ballotCounter']
      and acc.get('ballots') == 'replace' and acc.get('canSeeResults'), str(acc)[:160])
OLD = sql("select (hdg_sync_private.today() - 10)::text d")[0]['d']
MID3 = f'agenda-9000001-{OLD}'
save_meeting('officer', MID3, {'agenda': {'roles': {'timer': 'Test Past Ad'}}}, None, OLD)
s, acc = rpc('hdg_my_meeting_access', T['past_ad'], {'p_meeting_id': MID3})
check('a role in a meeting 10 days ago no longer works', isinstance(acc, dict) and not acc.get('canSaveTimer'), str(acc)[:160])
sql(f"update public.hdg_people set nickname = 'Twin' where id in ('00000000-0000-4000-8000-000000000009', '00000000-0000-4000-8000-000000000001')")
MID4 = f'agenda-9000001-{TODAY}-twin'
save_meeting('officer', MID4, {'agenda': {'roles': {'timer': 'Twin'}}})
s, acc = rpc('hdg_my_meeting_access', T['cross'], {'p_meeting_id': MID4})
check('a name that fits two members gives nobody the role', isinstance(acc, dict) and 'timer' not in (acc.get('roles') or []), str(acc)[:160])
sql("update public.hdg_people set nickname = null where nickname = 'Twin'")

# 016: own agenda lines, the Toastmaster's agenda, club members signing up and stepping in.
def meeting(mid):
    return sql(f"select agenda, ballots from public.hdg_meetings where meeting_id = '{mid}'")[0]
MID6 = f'agenda-9000001-{TODAY}-own'
base = {'theme': 'Stored theme', 'roles': {'timer': 'Test Past Ad', 'ballotCounter': 'Test Officer', 'tom': 'Test Past Member'},
        'speakers': [{'name': 'Test Past Ad', 'title': 'Old title', 'evaluator': 'Test Officer'}, {'name': 'Test Officer', 'title': 'Officer speech'}]}
s, m6 = save_meeting('officer', MID6, {'agenda': base})
try_agenda = {'theme': 'Changed by the Timer',
              'roles': {'timer': 'Test Past Ad (Area)', 'ballotCounter': 'Test Past Ad', 'tom': 'Test Past Member', 'ge': 'Test Past Ad'},
              'speakers': [{'name': 'Test Past Ad', 'title': 'My new title', 'evaluator': 'Test Past Ad'}, {'name': 'Test Officer', 'title': 'Edited by someone else'}]}
s, own = save_meeting('past_ad', MID6, {'agenda': try_agenda}, m6.get('updated_at'))
a = meeting(MID6)['agenda']
check('a role taker\'s agenda save is answered normally and reported as trimmed', s == 200 and own.get('applied') and own.get('trimmed') == ['agenda'], str(own)[:160])
check('a role taker fixes their own speech title and role spelling', a['speakers'][0]['title'] == 'My new title' and a['roles']['timer'] == 'Test Past Ad (Area)', str(a)[:200])
check('a role taker signs up for an empty role', a['roles'].get('ge') == 'Test Past Ad', str(a['roles']))
check('a role taker cannot change the theme, another person\'s role, speech or evaluator part',
      a['theme'] == 'Stored theme' and a['roles']['ballotCounter'] == 'Test Officer' and a['speakers'][1]['title'] == 'Officer speech'
      and a['speakers'][0]['evaluator'] == 'Test Officer', str(a)[:240])
cur6 = sql(f"select updated_at::text u from public.hdg_meetings where meeting_id = '{MID6}'")[0]['u']
s, tm = save_meeting('past_member', MID6, {'agenda': dict(a, theme='Toastmaster theme')}, cur6)
check('the Toastmaster of the Meeting changes the whole agenda', s == 200 and meeting(MID6)['agenda']['theme'] == 'Toastmaster theme', str(tm)[:120])
# A club member with no role in the meeting.
MID5 = f'agenda-9000001-{TODAY}-open'
s, m5 = save_meeting('officer', MID5, {'agenda': {'theme': 'Open meeting', 'roles': {'timer': ''}, 'speakers': []}})
s, acc = rpc('hdg_my_meeting_access', T['cross'], {'p_meeting_id': MID5})
check('a club member without a role reads the meeting, signs up and steps in, but sees no results',
      isinstance(acc, dict) and acc.get('clubMember') and acc.get('agenda') == 'own' and acc.get('canSaveTimer')
      and acc.get('ballots') == 'append' and not acc.get('canSeeResults'), str(acc)[:200])
s, su = save_meeting('cross', MID5, {'agenda': {'theme': 'Member theme', 'roles': {'timer': 'Test Cross'}, 'speakers': [{'name': 'Test Cross', 'title': 'My speech', 'evaluator': 'Test Officer'}]}}, m5.get('updated_at'))
a = meeting(MID5)['agenda']
check('a club member puts themselves into an empty role and a new speaker line', a['roles'].get('timer') == 'Test Cross'
      and len(a['speakers']) == 1 and a['speakers'][0]['title'] == 'My speech' and 'evaluator' not in a['speakers'][0], str(a)[:200])
check('a club member cannot change the theme', a['theme'] == 'Open meeting', a.get('theme'))
for r in ('past_ad', 'outsider', 'member_k'):
    s, acc = rpc('hdg_my_meeting_access', T[r], {'p_meeting_id': MID5})
    check(f'{r} (other club, no role) gets nothing in the club\'s meeting', isinstance(acc, dict) and acc.get('agenda') == 'none'
          and not acc.get('canSaveTimer') and acc.get('ballots') == 'none' and not acc.get('read'), str(acc)[:160])
    s, _ = save_meeting(r, MID5, {'agenda': {'roles': {'ge': 'Test Past Ad'}}}, None)
    check(f'{r} cannot sign up in another club\'s meeting', s != 200, str(s))
s, h1 = save_meeting('cross', MID5, {'ballots': [{'id': 'ballot-h1', 'prepared': 'p0'}], 'timer_log': [{'id': 'time-h1', 'seconds': 300}]}, None)
cur5 = sql(f"select updated_at::text u from public.hdg_meetings where meeting_id = '{MID5}'")[0]['u']
s, h2 = save_meeting('officer', MID5, {'ballots': [{'id': 'ballot-h1', 'prepared': 'p0'}, {'id': 'ballot-o1', 'prepared': 'p0'}]}, cur5)
s, h3 = save_meeting('cross', MID5, {'ballots': [{'id': 'ballot-h2', 'prepared': 'p0'}]}, None)
check('a stepping-in member adds ballots without removing others', len(meeting(MID5)['ballots']) == 3, str(meeting(MID5)['ballots'])[:160])
s, lst = rpc('hdg_meetings_list', T['cross'], {'p_meeting_id': MID5})
check('a stepping-in member does not see the ballots', isinstance(lst, list) and lst[0]['ballots'] == [], str(lst)[:120])
s, lst = rpc('hdg_meetings_list', T['cross'], {'p_meeting_id': MID3})
check('a club member reads the club\'s recent meetings', isinstance(lst, list) and len(lst) == 1, str(lst)[:80])
s, lst = rpc('hdg_meetings_list', T['past_ad'], {'p_meeting_id': MID3})
check('a role taker from another club no longer reads a past meeting', lst == [], str(lst)[:80])
# Phone votes: one ballot per meeting, whoever publishes.
CH = {'prepared': [{'id': 'p0', 'name': 'Speaker One'}], 'evaluation': [], 'topics': []}
s, pub = rpc('hdg_manage_ballot', T['officer'], {'p_meeting_id': MID, 'p_action': 'publish', 'p_title': 'Test ballot', 'p_choices': CH})
check('a leader publishes the meeting\'s voting link', s == 200 and isinstance(pub, dict) and pub.get('token'), str(pub)[:120])
s, pub2 = rpc('hdg_manage_ballot', T['dd_g'], {'p_meeting_id': MID, 'p_action': 'publish', 'p_title': 'Test ballot', 'p_choices': CH})
check('publishing again from another account keeps the same link', isinstance(pub2, dict) and pub2.get('token') == pub.get('token'), str(pub2)[:120])
token_id = pub.get('token') if isinstance(pub, dict) else None
s, _ = rpc('hdg_cast_ballot', None, {'p_token': token_id, 'p_browser_id': str(uuid.uuid4()), 'p_choices': {'prepared': 'p0', 'evaluation': '', 'topics': ''}})
for r in ('cross', 'past_member', 'dd_g'):
    s, st = rpc('hdg_manage_ballot', T[r], {'p_meeting_id': MID, 'p_action': 'status'})
    check(f'{r} sees the phone votes of the meeting', isinstance(st, dict) and st.get('responses') == 1, f'{s} {str(st)[:100]}')
for r in ('past_ad', 'outsider', 'member_k'):
    s, st = rpc('hdg_manage_ballot', T[r], {'p_meeting_id': MID, 'p_action': 'status'})
    check(f'{r} cannot see the phone votes', s != 200, str(s))
s, _ = rpc('hdg_manage_ballot', T['past_member'], {'p_meeting_id': MID, 'p_action': 'close'})
check('the Toastmaster of the Meeting cannot close voting', s != 200, str(s))
s, op = rpc('hdg_open_ballot', None, {'p_token': token_id})
check('the voting link opens for phones without sign-in', isinstance(op, dict) and op.get('title'), str(op)[:80])
s, cl = rpc('hdg_manage_ballot', T['cross'], {'p_meeting_id': MID, 'p_action': 'close'})
check('the Ballot Counter can close voting', isinstance(cl, dict) and cl.get('open') is False, str(cl)[:100])
sql("delete from public.hdg_meetings where club_number = '9000001'; "
    "delete from hdg_community_private.votes where ballot_id in (select id from hdg_community_private.ballots where meeting_id like 'agenda-9000001-%'); "
    "delete from hdg_community_private.ballots where meeting_id like 'agenda-9000001-%'")

# 017: clubs manage their own Exco. Any current officer of the club, at once; newer of club change and officer list wins.
C1 = '9000001'
def exco(r):
    return rpc('hdg_club_exco', T[r], {'p_club': C1})
def seat(e, role):
    return next((x for x in (e or {}).get('seats') or [] if x.get('role') == role), {}) if isinstance(e, dict) else {}
def set_seat(r, role, person):
    return rpc('hdg_set_club_officer', T[r], {'p_club': C1, 'p_role': role, 'p_person': person})
s, mine = rpc('hdg_my_exco_clubs', T['officer'])
check('017 an officer gets their club for the Club Exco tab', s == 200 and any(c.get('club') == C1 for c in mine), str(mine)[:120])
s, mine = rpc('hdg_my_exco_clubs', T['outsider'])
check('017 someone with no seat gets no Club Exco tab', s == 200 and mine == [], str(mine)[:120])
s, e = exco('cross')
check('017 a member without a seat cannot open the club Exco editor', s != 200, str(s))
s, _ = set_seat('cross', 'club_treasurer', P['cross'])
check('017 a member without a seat cannot take a seat', s != 200, str(s))
s, e = exco('officer')
check('017 a club officer sees the Exco and may edit', s == 200 and e.get('canEdit') is True and seat(e, 'club_president').get('person') == P['officer'], str(e)[:160])
check('017 the officer gets the club\'s active members to choose from', s == 200 and P['cross'] in [c['person'] for c in e.get('candidates', [])]
      and P['past_member'] not in [c['person'] for c in e.get('candidates', [])], str(e.get('candidates'))[:160])
s, _ = set_seat('officer', 'club_secretary', P['past_member'])
check('017 a seat only goes to an active member of the club', s != 200, str(s))
s, e = set_seat('officer', 'club_treasurer', P['cross'])
check('017 a club officer gives a seat to a club member', s == 200 and seat(e, 'club_treasurer').get('person') == P['cross']
      and seat(e, 'club_treasurer').get('source') == 'club', str(e)[:200])
s, e = exco('cross')
check('017 the new officer has access at once', s == 200 and e.get('canEdit') is True, str(s))
s, e = set_seat('cross', 'club_saa', P['officer'])
check('017 any officer (not only the President) can change a seat', s == 200 and seat(e, 'club_saa').get('person') == P['officer'], str(e)[:160])
for r in ('member_k', 'outsider', 'past_member', 'past_ad'):
    s, _ = set_seat(r, 'club_vpe', P[r] if r in P else None)
    check(f'017 {r} cannot change this club\'s Exco', s != 200, str(s))
s, e = set_seat('ad_g1', 'club_vpe', P['admin'])
check('017 the club\'s Area Director can change a seat (source leader)', s == 200 and seat(e, 'club_vpe').get('source') == 'leader', str(e)[:160])
s, _ = rpc('hdg_import_club_officers', T['cross'], {'p_club': C1, 'p_as_of': TODAY, 'p_seats': []})
check('017 a club officer cannot import an officer list', s != 200, str(s))
YDAY = sql("select (hdg_sync_private.today() - 1)::text d")[0]['d']
mid = lambda k: sql(f"select ti_member_id m from public.hdg_people where id = '{P[k]}'")[0]['m']
listed = [{'role': 'club_president', 'memberId': mid('officer')}, {'role': 'club_treasurer', 'memberId': mid('admin')},
          {'role': 'club_saa', 'memberId': mid('officer')}, {'role': 'club_vpe', 'memberId': mid('admin')}, {'role': 'club_secretary', 'memberId': '999999999'}]
s, res = rpc('hdg_import_club_officers', T['ad_g1'], {'p_club': C1, 'p_as_of': YDAY, 'p_seats': listed})
s2, e = exco('officer')
check('017 an older officer list keeps the club\'s newer change', s == 200 and seat(e, 'club_treasurer').get('person') == P['cross']
      and any(k['role'] == 'club_treasurer' for k in res.get('kept', [])), str(res)[:200])
check('017 the list\'s unknown member ID is reported, not applied', any(u['role'] == 'club_secretary' for u in res.get('unmatched', [])), str(res)[:200])
check('017 the president from the list stays (same person, now from the list)', seat(e, 'club_president').get('person') == P['officer']
      and seat(e, 'club_president').get('source') == 'import', str(seat(e, 'club_president'))[:120])
sql(f"update public.hdg_roles set source_at = now() - interval '10 days' where scope_code = '{C1}' and role = 'club_treasurer' and person_id = '{P['cross']}'")
s, res = rpc('hdg_import_club_officers', T['ad_g1'], {'p_club': C1, 'p_as_of': YDAY, 'p_seats': listed})
s2, e = exco('officer')
check('017 a newer officer list replaces an older club change', s == 200 and seat(e, 'club_treasurer').get('person') == P['admin'], str(e)[:200])
check('017 a seat missing from a newer list is left empty', not seat(e, 'club_vppr').get('person'), str(seat(e, 'club_vppr')))
s, _ = set_seat('cross', 'club_vppr', P['cross'])
check('017 the replaced officer loses Exco access at once', s != 200, str(s))
s, ch = rpc('hdg_exco_changes', T['ad_g1'], {'p_since': None})
check('017 leaders see club-made Exco changes', s == 200 and any(c['club'] == C1 and c['source'] == 'club' for c in ch), str(ch)[:160])
s, ch = rpc('hdg_exco_changes', T['member_k'], {'p_since': None})
check('017 others see no Exco changes', s == 200 and ch == [], str(ch)[:120])
s, _ = rpc('hdg_club_exco', None, {'p_club': C1})
check('017 signed out: no Exco', s != 200, str(s))
sql(f"delete from public.hdg_roles where scope_type = 'club' and scope_code = '{C1}'; "
    f"insert into public.hdg_roles(person_id, role, scope_type, scope_code, year_start, starts_on, ends_on) "
    f"values ('{P['officer']}', 'club_president', 'club', '{C1}', 2026, make_date(2026, 7, 1), make_date(2027, 6, 30)); "
    f"delete from public.hdg_import_freshness where club_number = '{C1}' and kind = 'officers'")

# 018: member list import into the per-record tables. Leaders of the club only; city only; member ID match;
# hand-corrected fields are asked about; newest list wins; snapshot marks missing members as past; undo.
C2 = '9000002'
def imp(r, rows, as_of=None, snap=True, club=C2):
    return rpc('hdg_import_club_members', T[r], {'p_club': club, 'p_as_of': as_of or YDAY, 'p_rows': rows, 'p_snapshot': snap})
def mstatus(k, club=C2):
    x = sql(f"select status from public.hdg_memberships where person_id = '{P[k]}' and club_number = '{club}'")
    return x[0]['status'] if x else None
def joiner():
    return sql("select p.id, p.ti_member_id, m.status from public.hdg_people p left join public.hdg_memberships m on m.person_id = p.id "
               "where ltrim(p.ti_member_id, '0') = '1234567'")
sql(f"update public.hdg_people set hand_corrected = '{{\"name\": {{\"value\": \"Hand Name\"}}}}' where id = '{P['dd_g']}'")
NAME_DDG = sql(f"select name from public.hdg_people where id = '{P['dd_g']}'")[0]['name']
ROWS = [{'memberId': mid('dd_g'), 'name': 'TI Spelling Of DD', 'active': True},
        {'memberId': mid('past_ad'), 'name': 'Test Past AD', 'active': False, 'paidUntil': '2026-09-30'},
        {'memberId': '1234567', 'name': 'Test New Joiner', 'email': 'NEW.JOINER@example.com ', 'city': 'Denpasar', 'active': True, 'joinedOn': '2026-11-20'},
        {'memberId': '', 'name': 'No ID Row'}]
for r in ('member', 'cross', 'past_ad', 'ad_g1', 'member_k', 'signed_out'):
    s, _ = imp(r, ROWS) if r != 'signed_out' else rpc('hdg_import_club_members', None, {'p_club': C2, 'p_as_of': YDAY, 'p_rows': ROWS, 'p_snapshot': True})
    check(f'018 {r} cannot import this club\'s member list', s != 200, str(s))
s, _ = imp('dd_g', [{'memberId': '1234567', 'name': 'X', 'phone': '0812'}])
check('018 a row with a phone number is refused (city only)', s != 200, str(s))
s, _ = imp('dd_g', [{'memberId': '1234567', 'name': 'X', 'address': 'Jl. Test 1'}])
check('018 a row with a street address is refused', s != 200, str(s))
s, _ = imp('dd_g', ROWS, as_of=sql("select (hdg_sync_private.today() + 1)::text d")[0]['d'])
check('018 a list dated in the future is refused', s != 200, str(s))
s, res = imp('dd_g', ROWS)
j = joiner()
check('018 the Division Director imports the club\'s list', s == 200 and res.get('newPeople') == 1 and res.get('skipped') == 1, str(res)[:200])
check('018 a new joiner gets a person (member ID padded to 8 digits) and an active membership',
      len(j) == 1 and j[0]['ti_member_id'] == '01234567' and j[0]['status'] == 'active', str(j))
nj = sql("select email, city from public.hdg_people where ti_member_id = '01234567'")
check('018 email is tidied and only the city is kept', nj and nj[0]['email'] == 'new.joiner@example.com' and nj[0]['city'] == 'Denpasar', str(nj))
check('018 a member marked not active becomes lapsed', mstatus('past_ad') == 'lapsed', str(mstatus('past_ad')))
check('018 a member missing from the list becomes past (snapshot)', mstatus('prm') == 'past', str(mstatus('prm')))
check('018 a hand-corrected name is kept and asked about',
      sql(f"select name from public.hdg_people where id = '{P['dd_g']}'")[0]['name'] == NAME_DDG
      and any(c['field'] == 'name' and c['ti'] == 'TI Spelling Of DD' for c in res.get('conflicts', [])), str(res.get('conflicts'))[:200])
fr = sql(f"select as_of::text a from public.hdg_import_freshness where club_number = '{C2}' and kind = 'roster'")
check('018 the list date is recorded for the club', fr and fr[0]['a'] == YDAY, str(fr))
s, e = rpc('hdg_club_exco', T['dd_g'], {'p_club': C2})
check('018 the new joiner can be chosen for an Exco seat at once', s == 200 and j and j[0]['id'] in [c['person'] for c in e.get('candidates', [])], str(e)[:160])
OLDER = sql("select (hdg_sync_private.today() - 5)::text d")[0]['d']
s, old = imp('dd_g', [{'memberId': mid('prm'), 'name': 'Test PRM', 'active': True}], as_of=OLDER)
check('018 an older list changes nothing', s == 200 and old.get('stale') is True and mstatus('prm') == 'past', str(old)[:160])
s, _ = rpc('hdg_undo_member_import', T['ad_g1'], {'p_import': res.get('import')})
check('018 someone else cannot undo the import', s != 200, str(s))
s, u = rpc('hdg_undo_member_import', T['dd_g'], {'p_import': res.get('import')})
check('018 the importer undoes it: memberships back, new joiner gone, list date cleared',
      s == 200 and mstatus('prm') == 'active' and mstatus('past_ad') == 'active' and not joiner()
      and not sql(f"select 1 from public.hdg_import_freshness where club_number = '{C2}' and kind = 'roster'"), str(u))
s, _ = rpc('hdg_undo_member_import', T['dd_g'], {'p_import': res.get('import')})
check('018 an import is undone only once', s != 200, str(s))
s, res = imp('dd_g', ROWS, snap=False)
check('018 update-only mode never marks missing members as past', s == 200 and mstatus('prm') == 'active', str(res)[:160])
s, _ = rpc('hdg_resolve_import_conflict', T['ad_g1'], {'p_person': P['dd_g'], 'p_field': 'name', 'p_ti_value': 'TI Spelling Of DD', 'p_take': True})
check('018 a leader outside the club cannot settle its differences', s != 200, str(s))
s, _ = rpc('hdg_resolve_import_conflict', T['dd_g'], {'p_person': P['dd_g'], 'p_field': 'name', 'p_ti_value': 'TI Spelling Of DD', 'p_take': False})
s2, again = imp('dd_g', ROWS, snap=False)
check('018 "keep mine" is remembered: the same difference is not asked again', s in (200, 204) and s2 == 200 and again.get('conflicts') == [], str(again)[:160])
s, _ = rpc('hdg_resolve_import_conflict', T['dd_g'], {'p_person': P['dd_g'], 'p_field': 'name', 'p_ti_value': 'TI Spelling Of DD', 'p_take': True})
check('018 "take TI\'s" applies the list\'s value', s in (200, 204) and sql(f"select name from public.hdg_people where id = '{P['dd_g']}'")[0]['name'] == 'TI Spelling Of DD', str(s))
sql(f"update public.hdg_people set name = '{NAME_DDG}', hand_corrected = '{{}}' where id = '{P['dd_g']}'; "
    f"update public.hdg_memberships set status = 'active' where club_number = '{C2}' and person_id in ('{P['prm']}', '{P['past_ad']}', '{P['dd_g']}'); "
    "delete from public.hdg_people where ltrim(ti_member_id, '0') = '1234567'; "
    f"delete from public.hdg_import_freshness where club_number = '{C2}'; delete from hdg_sync_private.member_imports where club_number = '{C2}'")

# 019: lists for clubs outside Division G. A division's imports open only when the maintainer opens them (PDPA first);
# leaders import only clubs they lead.
CK = '9000003'
K_ROWS = [{'memberId': mid('member_k'), 'name': 'Test Member K', 'active': True}, {'memberId': '7654321', 'name': 'Test Kappa Joiner', 'active': True}]
def club_row(r, club):
    s, cl = rpc('hdg_import_clubs', T[r])
    return s, next((c for c in (cl or []) if isinstance(cl, list) and c.get('club') == club), {})
s, k = club_row('dd_k', CK)
check('019 every club is listed for imports, Division K closed for now', s == 200 and k.get('division') == 'K' and k.get('canImport') is False
      and k.get('reason') == 'closed', str(k))
s, g = club_row('dd_k', C2)
check('019 a club outside the leader\'s scope says so', s == 200 and g.get('canImport') is False and g.get('reason') == 'scope', str(g))
s, _ = imp('dd_k', K_ROWS, club=CK)
check('019 Division K member lists are refused until the division is opened', s != 200
      and not sql("select 1 from public.hdg_people where ltrim(ti_member_id, '0') = '7654321'"), str(s))
s, _ = rpc('hdg_import_club_officers', T['dd_k'], {'p_club': CK, 'p_as_of': YDAY, 'p_seats': []})
check('019 Division K officer lists are refused until the division is opened', s != 200, str(s))
for r in ('dd_k', 'dd_g', 'am'):
    s, _ = rpc('hdg_set_division_import', T[r], {'p_division': 'K', 'p_open': True})
    check(f'019 {r} cannot open a division\'s imports', s != 200, str(s))
s, _ = rpc('hdg_set_division_import', T['admin'], {'p_division': 'K', 'p_open': True})
check('020 Division K cannot open until a privacy notice is published', s != 200 and s != 204)
gate_notice = 'test-gate-' + uuid.uuid4().hex
s, _ = rpc('hdg_publish_privacy_notice', T['admin'], {'p_version': gate_notice, 'p_body': 'Fictional import gate notice.'})
assert s in (200, 204), f'Could not publish synthetic import gate notice: HTTP {s}'
s, _ = rpc('hdg_set_division_import', T['admin'], {'p_division': 'K', 'p_open': True})
check('019 the maintainer opens Division K imports', s in (200, 204) and club_row('dd_k', CK)[1].get('canImport') is True, str(s))
s, _ = imp('dd_g', K_ROWS, club=CK)
check('019 the Division G Director cannot import a Division K club', s != 200, str(s))
s, _ = imp('ad_g1', K_ROWS, club=CK)
check('019 an Area Director of another division cannot either', s != 200, str(s))
s, res = imp('dd_k', K_ROWS, club=CK)
check('019 the Division K Director imports a Division K club once open', s == 200 and res.get('newPeople') == 1, str(res)[:160])
s, res = imp('admin', K_ROWS, club=CK, as_of=TODAY)
check('019 the maintainer can import it too', s == 200 and res.get('newPeople') == 0, str(res)[:160])
s, res = imp('dd_g', ROWS)
check('019 Division G imports keep working', s == 200 and 'import' in res, str(res)[:160])
s, _ = rpc('hdg_import_clubs', None)
check('019 signed out: no club list for imports', s != 200 or _ == [], str(s))
sql("update public.hdg_divisions set config = '{}' where code = 'K'; "
    "delete from public.hdg_people where ltrim(ti_member_id, '0') = '7654321'; "
    f"update public.hdg_memberships set status = 'active' where club_number = '{C2}' and person_id in ('{P['prm']}', '{P['past_ad']}', '{P['dd_g']}'); "
    "delete from public.hdg_people where ltrim(ti_member_id, '0') = '1234567'; "
    f"update public.hdg_people set name = '{NAME_DDG}', hand_corrected = '{{}}' where id = '{P['dd_g']}'; "
    f"delete from public.hdg_import_freshness where club_number in ('{C2}', '{CK}'); delete from hdg_sync_private.member_imports where club_number in ('{C2}', '{CK}')")

sql(f"delete from hdg_sync_private.privacy_notices where version='{gate_notice}'")

# 020: privacy rights, retention and onboarding on fictional data.
from test_env import keys
from secrets import token_urlsafe

stamp = uuid.uuid4().hex[:12]
v1, v2 = f'test-{stamp}-1', f'test-{stamp}-2'
for fn in ('hdg_privacy_notice', 'hdg_my_privacy', 'hdg_export_my_data', 'hdg_remove_my_details',
           'hdg_request_deletion', 'hdg_privacy_deletion_queue', 'hdg_my_context'):
    s, _ = rpc(fn, None)
    check(f'020 signed out cannot call {fn}', s not in (200, 204), str(s))
s, _ = rpc('hdg_publish_privacy_notice', T['member'], {'p_version': v1, 'p_body': 'Fictional notice version one.'})
check('020 member cannot publish a notice', s not in (200, 204), str(s))
s, _ = rpc('hdg_publish_privacy_notice', T['admin'], {'p_version': v1, 'p_body': 'Fictional notice version one.'})
check('020 maintainer can publish a notice', s in (200, 204), str(s))
s, n = rpc('hdg_privacy_notice', T['member'])
check('020 current notice includes version and text and is unaccepted at first', s == 200 and n.get('version') == v1
      and n.get('body') == 'Fictional notice version one.' and n.get('acceptedAt') is None, str(s))
s, accepted = rpc('hdg_accept_privacy_notice', T['member'], {'p_version': v1})
s2, duplicate = rpc('hdg_accept_privacy_notice', T['member'], {'p_version': v1})
s3, other_notice = rpc('hdg_privacy_notice', T['officer'])
check('020 acceptance has a timestamp, retries preserve it, and it is isolated per account',
      s == s2 == s3 == 200 and accepted and accepted == duplicate and other_notice.get('acceptedAt') is None)
s, _ = rpc('hdg_publish_privacy_notice', T['admin'], {'p_version': v2, 'p_body': 'Fictional notice version two.'})
s2, changed = rpc('hdg_privacy_notice', T['member'])
s3, _ = rpc('hdg_accept_privacy_notice', T['member'], {'p_version': v1})
check('020 new version requires acceptance again and a stale version cannot be accepted',
      s in (200, 204) and s2 == 200 and changed.get('version') == v2 and changed.get('acceptedAt') is None and s3 != 200)
s, _ = rpc('hdg_accept_privacy_notice', T['member'], {'p_version': v2})
check('020 the new notice is accepted separately', s == 200)

s, _ = rpc('hdg_request_deletion', T['member'])
check('020 active member cannot request full deletion', s != 200, str(s))
s, _ = rpc('hdg_privacy_deletion_queue', T['am'])
check('020 district officer cannot read the maintainer queue', s != 200, str(s))
s, _ = rpc('hdg_complete_deletion', T['am'], {'p_request': str(uuid.uuid4())})
check('020 district officer cannot process queued requests', s != 200, str(s))

step = 'member-welcome-' + stamp
s, _ = rpc('hdg_mark_onboarding_seen', None, {'p_step': step})
check('020 signed out cannot mark an onboarding step', s != 200, str(s))
s, first_seen = rpc('hdg_mark_onboarding_seen', T['member'], {'p_step': step})
s2, still_seen = rpc('hdg_mark_onboarding_seen', T['member'], {'p_step': step})
s3, member_context = rpc('hdg_my_context', T['member'])
s4, officer_context = rpc('hdg_my_context', T['officer'])
check('020 only the signed-in account sees its onboarding progress, and retries keep the first timestamp',
      s == s2 == s3 == s4 == 200 and first_seen and first_seen == still_seen
      and member_context['onboardingSeen'].get(step) == first_seen and step not in officer_context['onboardingSeen'])
s, k_context = rpc('hdg_my_context', T['dd_k'])
check('020 current roles include role and scope for tutorial selection', s == 200 and
      any(r['role'] == 'division_director' and r['scopeType'] == 'division' and r['scope'] == 'K' for r in k_context['roles']))
s, stranger_context = rpc('hdg_my_context', T['outsider'])
check('020 a signed-in account without a membership still gets its onboarding context',
      s == 200 and stranger_context.get('roles') == [] and stranger_context.get('onboardingSeen') == {})

# Seed dedicated fixtures so testing irreversible operations never touches the standard test accounts.
_, svc = keys()
pw = token_urlsafe(24)
privacy_email = f'privacy-fixture-{stamp}@example.com'
s, user = request('POST', '/auth/v1/admin/users', svc, svc,
                  {'email': privacy_email, 'password': pw, 'email_confirm': True})
assert s in (200, 201), f'Could not create synthetic privacy account: HTTP {s}'
account = user['id']
s, signed = request('POST', '/auth/v1/token?grant_type=password', KEY,
                    body={'email': privacy_email, 'password': pw})
assert s == 200, f'Could not sign in synthetic privacy account: HTTP {s}'
pt = signed['access_token']
person, role, expired, recent, multi, legacy = [str(uuid.uuid4()) for _ in range(6)]
ids = ','.join(f"'{x}'" for x in (person, expired, recent, multi, legacy))
try:
    sql(f"""
    insert into public.hdg_people(id,name,email,user_id,nickname,aliases,pronunciation,photo_path,photo_consent)
      values ('{person}','Synthetic Privacy Subject','{privacy_email}','{account}','Fixture alias',array['Fixture other'],
              'Fixture pronunciation','fixture-photo',true),
      ('{expired}','Nightly expired',null,null,null,'{{}}',null,null,false),
      ('{recent}','Nightly recent',null,null,null,'{{}}',null,null,false),
      ('{multi}','Nightly multi-club',null,null,null,'{{}}',null,null,false),
      ('{legacy}','Nightly legacy',null,null,null,'{{}}',null,null,false);
    insert into public.hdg_memberships(person_id,club_number,status,ended_on)
      values ('{person}','9000003','past',current_date-2),
      ('{expired}','9000003','past',(hdg_sync_private.today()-interval '12 months')::date),
      ('{recent}','9000003','past',(hdg_sync_private.today()-interval '12 months')::date + 1),
      ('{multi}','9000003','past',current_date-500),('{multi}','9000004','active',null),
      ('{legacy}','9000003','past',current_date-500);
    insert into public.hdg_roles(id,person_id,role,scope_type,scope_code,year_start,starts_on,ends_on)
      values ('{role}','{person}','club_vpe','club','9000003',2025,'2025-07-01','2026-06-30');
    insert into hdg_sync_private.legacy_records(kind,key,data)
      values ('member_notes','{legacy}',jsonb_build_object('personId','{legacy}'));
    """)
    s, exported = rpc('hdg_export_my_data', pt)
    s2, member_export = rpc('hdg_export_my_data', T['member'])
    check('020 export includes only own account, profiles, memberships and roles, without auth credentials',
          s == s2 == 200 and exported['account']['id'] == account and 'encrypted_password' not in exported['account']
          and [row['id'] for row in exported['people']] == [person]
          and exported['memberships'][0]['club_number'] == '9000003' and exported['roles'][0]['id'] == role
          and all(row['id'] != person for row in member_export['people']))
    check('020 export includes both per-version acceptances and own onboarding progress',
          {a['version'] for a in member_export['consents']} >= {v1, v2} and step in member_export['onboarding'])
    s, removed = rpc('hdg_remove_my_details', pt)
    s2, after_profile = rpc('hdg_export_my_data', pt)
    current = after_profile['people'][0]
    check('020 self-service clears profile fields and their copies in edit history, keeping required identity fields',
          s == s2 == 200 and removed == 1 and current['name'] == 'Synthetic Privacy Subject'
          and current['email'] == privacy_email and current['aliases'] == [] and current['photo_consent'] is False
          and all(current[f] is None for f in ('nickname','pronunciation','photo_path'))
          and 'Fixture alias' not in str(after_profile['recordHistory']))
    s, pending = rpc('hdg_request_deletion', pt)
    s2, repeated = rpc('hdg_request_deletion', pt)
    s3, queue = rpc('hdg_privacy_deletion_queue', T['admin'])
    request_id = pending['id']
    check('020 eligible requests enter the queue once with a 30-day deadline',
          s == s2 == s3 == 200 and pending == repeated and any(r['id'] == request_id and r['email'] == privacy_email
          and r['dueAt'] == pending['due_at'] for r in queue)
          and sql(f"""select abs(extract(epoch from (due_at-requested_at))-2592000)<1 as correct
                     from hdg_sync_private.privacy_deletion_requests where id='{request_id}'""")[0]['correct'])
    sql(f"update public.hdg_memberships set status='active' where person_id='{person}'")
    s, _ = rpc('hdg_complete_deletion', T['admin'], {'p_request': request_id})
    check('020 maintainer completion rechecks membership after the request was submitted', s != 200)
    sql(f"update public.hdg_memberships set status='past' where person_id='{person}'")
    s, completed = rpc('hdg_complete_deletion', T['admin'], {'p_request': request_id})
    ret = sql(f"""select not exists(select 1 from auth.users where id='{account}') as account_gone,
       not exists(select 1 from public.hdg_people where id='{person}') as person_gone,
       exists(select 1 from public.hdg_roles where id='{role}' and person_id is null and former_member_name='Former member') as anonymized,
       exists(select 1 from hdg_sync_private.privacy_deletion_requests where id='{request_id}' and user_id is null
         and completed_at is not null) as completed""")[0]
    check('020 completion erases the account and profile and preserves the anonymized historical seat',
          s == 200 and completed is True and all(ret.values()), str(s))

    sql("select hdg_sync_private.privacy_nightly_erase()")
    remaining = {r['id'] for r in sql(f'select id from public.hdg_people where id in ({ids})')}
    check('020 nightly retention erases at exactly 12 months and protects newer, active and legacy-linked records',
          remaining == {recent, multi, legacy}, str(len(remaining)))
    job = sql("""select schedule, command, active from cron.job where jobname='hdg-privacy-retention'""")
    check('020 pg_cron schedules the private retention task once every night',
          len(job) == 1 and job[0]['active'] and job[0]['schedule'] == '30 18 * * *'
          and 'privacy_nightly_erase()' in job[0]['command'])
finally:
    sql(f"""delete from hdg_sync_private.privacy_deletion_requests where user_id='{account}' or id::text='{locals().get('request_id','')}';
       delete from hdg_sync_private.legacy_records where kind='member_notes' and key='{legacy}';
       delete from public.hdg_roles where id='{role}'; delete from public.hdg_people where id in ({ids});
       delete from auth.users where id='{account}';
       delete from hdg_sync_private.onboarding_seen where step='{step}';
       delete from hdg_sync_private.privacy_acceptances where version in ('{v1}','{v2}');
       delete from hdg_sync_private.privacy_notices where version in ('{v1}','{v2}');""")


failed =[r for r in results if not r[0]]
for ok, name, detail in results:
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if not ok and detail else ''))
print(f'\n{len(results) - len(failed)}/{len(results)} access checks passed.')
sys.exit(1 if failed else 0)
