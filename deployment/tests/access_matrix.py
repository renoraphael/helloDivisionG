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
    check("another leader cannot read this officer's ballot count", st in (None, '') or (isinstance(st, dict) and st.get('token') != tok), str(s))
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
check('an unknown account gets no setup context', ctx in (None, ''), str(ctx)[:60])

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

failed = [r for r in results if not r[0]]
for ok, name, detail in results:
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if not ok and detail else ''))
print(f'\n{len(results) - len(failed)}/{len(results)} access checks passed.')
sys.exit(1 if failed else 0)
