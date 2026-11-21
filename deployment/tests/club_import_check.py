#!/usr/bin/env python3
"""Club directory import (009) on synthetic rows, TEST project only. Re-run setup_test_project.py afterwards.
Usage: SUPABASE_CLI=/path/to/supabase python3 deployment/tests/club_import_check.py
"""
import csv, json, os, subprocess, sys, tempfile
from pathlib import Path
from test_env import sql, request, load_local, ROOT

sys.path.insert(0, str(ROOT / 'deployment' / 'imports'))
from import_clubs import EXPECTED

results = []
check = lambda name, ok, detail='': results.append((bool(ok), name, detail))
q = lambda s: sql(s)[0]


def row(**kw):
    r = {c: '' for c in EXPECTED}
    r.update(district='87', program_year='2026-2027', checked_on='2026-11-21', membership_base='20', membership_to_date='22',
             dcp_goals_met='3', dcp_7_new_members_target_4='2', meeting_timezone='UTC+08:00', country='Malaysia')
    r.update(kw)
    return r


def run(rows, name):
    d = tempfile.mkdtemp()
    p = Path(d) / name
    with p.open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=EXPECTED); w.writeheader(); w.writerows(rows)
    out = subprocess.run([sys.executable, str(ROOT / 'deployment/imports/import_clubs.py'), str(p)], capture_output=True, text=True)
    p.unlink(); os.rmdir(d)
    if out.returncode:
        raise SystemExit(out.stderr or out.stdout)
    return json.loads(out.stdout[out.stdout.index('{'):])


rows = [
    row(division='K', area='K01', club_number='00912345', club_name='Synthetic Kuching Club', locality='Kuching',
        venue='Test Hall', street_address='1 Test Road', public_phone='+60 0000 0000', meeting_schedule='Every Monday',
        alternate_venue_1_address='2 Other Road', notes='checked by agent', language_evidence='seen on page'),
    row(division='K', area='K2', club_number='912346', club_name='Synthetic Brunei Club', country='Brunei Darussalam', locality='Bandar'),
    row(division='G', area='G01', club_number='9000001', club_name='TI Name For Alpha', country='Indonesia', locality='Elsewhere'),
    row(division='G', area='G2', club_number='9000002', club_name='Beta', country='Indonesia', meeting_timezone='UTC+07:00'),  # app has G2
    row(division='J', area='J1', club_number='912347', club_name='Synthetic Java Club', country='Indonesia', meeting_timezone='UTC+07:00'),
    row(division='K', area='G3', club_number='912348', club_name='Wrong Area Club'),     # area outside its division: refused
]
res = run(rows, 'district87-clubs-2026-11-21.csv')
check('new clubs are added, bad rows refused', res['clubs_added'] == 3 and len(res['rows_refused']) == 1, res)
k = q("select c.timezone, c.currency, c.city, c.details->'directory' d from public.hdg_clubs c where club_number = '912345'")
check('club numbers are stored without leading zeros', k is not None)
check('a Malaysian club gets MYT and MYR', k['timezone'] == 'Asia/Kuala_Lumpur' and k['currency'] == 'MYR', k)
check('public venue, street address and phone are published on the club', k['d'].get('street_address') == '1 Test Road'
      and k['d'].get('public_phone') == '+60 0000 0000' and k['d'].get('alternate_venues') == [{'address': '2 Other Road'}], k['d'])
b = q("select timezone, currency from public.hdg_clubs where club_number = '912346'")
check('a Brunei club gets Brunei time and BND', b == {'timezone': 'Asia/Brunei', 'currency': 'BND'}, b)
j = q("select timezone from public.hdg_clubs where club_number = '912347'")
check('an Indonesian UTC+7 club gets WIB', j['timezone'] == 'Asia/Jakarta', j)
a = q("select name, city, timezone, details->'directory'->>'ti_name' ti from public.hdg_clubs where club_number = '9000001'")
check('an existing club keeps its name, city and time zone; the TI name is kept beside it',
      a['name'] == 'Test Alpha Club' and a['city'] == 'Testville' and a['timezone'] == 'Asia/Makassar' and a['ti'] == 'TI Name For Alpha', a)
check('G01 in the file is the same area as G1', res['area_differs_from_app'] == [], res['area_differs_from_app'])
al = sql("select club_number, area_code from public.hdg_club_alignment where year_start = 2026 and club_number in ('912345','912346','912347')")
check('new clubs are aligned to their area for the program year', {(x['club_number'], x['area_code']) for x in al}
      == {('912345', 'K1'), ('912346', 'K2'), ('912347', 'J1')}, al)
f = q("select membership_base, membership_to_date, dcp_goals_met, dcp->>'dcp_7_new_members_target_4' d7 from public.hdg_club_figures where club_number = '912345'")
check('dashboard figures are stored per club and date', f == {'membership_base': 20, 'membership_to_date': 22, 'dcp_goals_met': 3, 'd7': '2'}, f)
n = q("select data->>'notes' n, data->>'language_evidence' e from hdg_sync_private.legacy_records where kind = 'club_import_notes' and key = '912345'")
check("the agent's checking notes are kept privately", n == {'n': 'checked by agent', 'e': 'seen on page'}, n)
check('checking notes are not on the club record', 'notes' not in k['d'] and 'language_evidence' not in k['d'], k['d'])

before = q("select count(*) n from hdg_sync_private.edit_history")['n']
res2 = run(rows, 'district87-clubs-2026-11-21.csv')
check('importing the same file again changes no club', res2['clubs_added'] == 0 and res2['clubs_updated'] == 0, res2)
older = [dict(rows[0], checked_on='2026-10-01', public_phone='+60 1111 1111')]
res3 = run(older, 'district87-clubs-2026-10-01.csv')
k2 = q("select details->'directory'->>'public_phone' p from public.hdg_clubs where club_number = '912345'")
check('an older file does not overwrite newer club information', res3['older_than_stored'] == 1 and k2['p'] == '+60 0000 0000', (res3, k2))
moved = [dict(rows[3], area='G1')]
res4 = run(moved, 'district87-clubs-2026-11-22.csv')
check('a different area for an existing club is reported, not changed', res4['area_differs_from_app'] == [{'club_number': '9000002', 'file_area': 'G1'}]
      and q("select area_code from public.hdg_club_alignment where year_start = 2026 and club_number = '9000002'")['area_code'] == 'G2', res4)

# What a member can read: published club information and figures, not the checking notes.
cfg = load_local(); KEY = cfg['publishable_key']; a_ = cfg['accounts']['member_k']
tok = request('POST', '/auth/v1/token?grant_type=password', KEY, body={'email': a_['email'], 'password': a_['password']})[1]['access_token']
s, clubs = request('GET', '/rest/v1/hdg_clubs?club_number=eq.912345&select=details', KEY, tok)
check('a member can read the published club information', s == 200 and clubs and clubs[0]['details']['directory'].get('public_phone'), str(s))
s, figs = request('GET', '/rest/v1/hdg_club_figures?club_number=eq.912345&select=as_of,membership_to_date&order=as_of', KEY, tok)
check('a member can read club figures, kept per checked date', s == 200 and [x['as_of'] for x in figs] == ['2026-10-01', '2026-11-21'], str(figs)[:120])
s, body = request('GET', '/rest/v1/legacy_records?select=*', KEY, tok, headers={'Accept-Profile': 'hdg_sync_private'})
check('a member cannot read the checking notes', s != 200, str(s))
s, body = request('GET', '/rest/v1/hdg_clubs?select=club_number', KEY, None)
check('signed-out visitors cannot read clubs', s != 200 or body == [], str(s))

failed = [r for r in results if not r[0]]
for ok, name, detail in results:
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if not ok and detail else ''))
print(f'\n{len(results) - len(failed)}/{len(results)} club import checks passed.')
sys.exit(1 if failed else 0)
