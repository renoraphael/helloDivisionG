#!/usr/bin/env python3
"""Phase 0 step 7: copy a synthetic Division G shared record into the per-record tables and compare.

TEST project only (synthetic data). Clears the per-record tables, runs the copy twice, checks the
comparison, then restores the access-test fixtures. Exit code 1 if any check fails.
Usage: SUPABASE_CLI=/path/to/supabase python3 deployment/tests/legacy_copy_check.py
"""
import json, sys
from test_env import sql
from setup_test_project import foundation_sql

TABLES = ('public.hdg_roles, public.hdg_memberships, public.hdg_import_freshness, public.hdg_club_alignment, '
          'public.hdg_areas, public.hdg_people, public.hdg_clubs, public.hdg_divisions, public.hdg_program_years')


def legacy_payload():
    clubs = [
        {'number': '90001001', 'name': 'Synthetic Bali Club', 'area': 'G1', 'city': 'Testpura', 'island': 'Bali', 'dcpGoals': '4'},
        {'number': '90001002', 'name': 'Synthetic Sulawesi Club', 'area': 'G2', 'city': 'Sampleton', 'island': 'Sulawesi', 'mode': 'Hybrid'},
        {'number': '90001003', 'name': 'Synthetic Java Club', 'area': 'G2', 'city': 'Exampleburg', 'island': 'East Java'},
        {'number': '00004321', 'name': 'Synthetic Old Club', 'area': 'G1', 'city': 'Testpura', 'island': 'Bali'},   # TI leading zeros
    ]
    m = lambda mid, name, club, active=True, **kw: dict({'key': 'id:' + mid, 'memberId': mid, 'name': name,
        'email': name.split()[1].lower() + '@example.com', 'clubNumber': club, 'active': active,
        'pastMember': not active, 'clubJoinDate': '2024-01-15', 'renewThrough': '2027-03-31'}, **kw)
    memberships = [
        m('10000001', 'Test Alpha', '90001001', nickname='Al'),
        m('10000002', 'Test Bravo', '90001001', nicknames=['Bee', 'Bravo B']),
        m('10000003', 'Test Charlie', '90001001', notes='Prefers evening meetings'),
        m('10000003', 'Test Charlie', '90001003'),                     # one person, two clubs
        m('10000004', 'Test Delta', '90001002', active=False, renewThrough='2026-09-30'),
        m('10000005', 'Test Echo', '90001002'),
        m('10000006', 'Test Foxtrot', '90001003', email='Foxtrot.Mixed@Example.com'),
        m('10000007', 'Test Golf', '00004321'),
        m('10000006', 'Test Foxtrot', '4321', email='Foxtrot.Mixed@Example.com'),                       # same club written without the zeros
        {'key': 'id:', 'memberId': '', 'name': 'No Id Person', 'clubNumber': '90001003', 'active': True},  # skipped: no member ID
    ]
    exco = [
        {'clubNumber': '90001001', 'role': 'Club President', 'memberId': '10000001', 'name': 'Test Alpha', 'term': '2026-07-01 – 2027-06-30'},
        {'clubNumber': '90001001', 'role': 'Club VP Education', 'memberId': '10000002', 'name': 'Test Bravo', 'term': '2026-08-01 – 2027-06-30'},
        {'clubNumber': '90001003', 'role': 'Club Treasurer', 'memberId': '10000003', 'name': 'Test Charlie', 'term': '2026-07-01 – 2027-06-30'},
        {'clubNumber': '00004321', 'role': 'Club Secretary', 'memberId': '10000007', 'name': 'Test Golf', 'term': '2026-07-01 – 2027-06-30'},
        {'clubNumber': '90001002', 'role': 'Club Liaison no proxy', 'memberId': '10000005', 'name': 'Test Echo', 'term': ''},
    ]
    collections = ['reports', 'tlis', 'contests', 'prospects', 'membershipImports', 'officerImports', 'tasks',
                   'taskDismissals', 'specialMeetings', 'meetingAgendaRecords', 'leadershipTeams']
    db = {'schemaVersion': 4, 'clubs': clubs, 'memberships': memberships, 'exco': exco,
          'areas': [{'code': 'G1', 'director': 'Test Alpha'}, {'code': 'G2', 'director': ''}],
          'memberIdentityAliases': {'id:10000005': {'memberId': '10000005', 'canonicalName': 'Test Echo', 'nicknames': ['Eko']}}}
    db.update({k: [] for k in collections})
    return {'database': db, 'settings': {'divisionDirector': 'Test Bravo'}}


results = []
check = lambda name, ok, detail='': results.append((bool(ok), name, detail))
P = json.dumps(legacy_payload()).replace("'", "''")
q = lambda s: sql(s)[0]
copy = lambda: sql(f"select hdg_sync_private.copy_legacy_division('G', 2026, '{P}'::jsonb) r")[0]['r']
compare = lambda: sql(f"select * from hdg_sync_private.compare_legacy_division('G', 2026, '{P}'::jsonb)")
counts = lambda: sql("select (select count(*) from public.hdg_people) people, (select count(*) from public.hdg_memberships) memberships, "
                     "(select count(*) from public.hdg_roles) roles, (select count(*) from hdg_sync_private.edit_history) history")[0]

try:
    sql(f'truncate {TABLES} cascade; truncate hdg_sync_private.legacy_records;')
    first = copy()
    rows = compare()
    for r in rows:
        check(f"{r['check_name']}: {r['legacy']} in the shared record, {r['copied']} copied", r['ok'])
    check('the comparison covers every club', sum(r['check_name'].startswith('active members in club') for r in rows) == 4)
    check('a club number with leading zeros is stored once, without them',
          q("select count(*) n from public.hdg_clubs where club_number = '4321'")['n'] == 1
          and q("select count(*) n from public.hdg_memberships where club_number = '4321'")['n'] == 2
          and q("select count(*) n from public.hdg_roles where scope_code = '4321'")['n'] == 1)
    check('Area and Division Directors are listed for assignment by member ID, not matched by name',
          {(x['role'], x['scope']) for x in first['assign_in_app']} == {('area_director', 'G1'), ('division_director', 'G')}, first['assign_in_app'])

    check('a member of two clubs is one person with two memberships',
          q("select count(*) n from public.hdg_memberships m join public.hdg_people p on p.id = m.person_id where p.ti_member_id = '10000003'")['n'] == 2)
    check('a row without a member ID is not copied', q("select count(*) n from public.hdg_people where name = 'No Id Person'")['n'] == 0)
    check('a past member is copied as past', q("select status from public.hdg_memberships m join public.hdg_people p on p.id = m.person_id where p.ti_member_id = '10000004'")['status'] == 'past')
    check('email is stored in lower case', q("select email from public.hdg_people where ti_member_id = '10000006'")['email'] == 'foxtrot.mixed@example.com')
    bravo = q("select nickname, aliases from public.hdg_people where ti_member_id = '10000002'")
    check('nicknames are kept (first as nickname, the rest as aliases)', bravo['nickname'] and len(bravo['aliases']) == 1, bravo)
    check('identity-alias nicknames are kept', q("select nickname from public.hdg_people where ti_member_id = '10000005'")['nickname'] == 'Eko')
    check('leader notes about a member are kept privately, not in the record the member can read',
          q("select data->0->>'notes' n from hdg_sync_private.legacy_records where kind = 'member_notes' and key = '10000003'")['n'] == 'Prefers evening meetings'
          and q("select notes from public.hdg_people where ti_member_id = '10000003'")['notes'] is None)
    check('the liaison entry does not become an officer role', q("select count(*) n from public.hdg_roles r join public.hdg_people p on p.id = r.person_id where p.ti_member_id = '10000005'")['n'] == 0)
    check('an officer term starting in August starts then', q("select starts_on::text d from public.hdg_roles r join public.hdg_people p on p.id = r.person_id where p.ti_member_id = '10000002'")['d'] == '2026-08-01')
    tz = {r['club_number']: r['timezone'] for r in sql('select club_number, timezone from public.hdg_clubs')}
    check('East Java clubs get WIB, Bali and Sulawesi get WITA', tz == {'90001001': 'Asia/Makassar', '90001002': 'Asia/Makassar', '90001003': 'Asia/Jakarta', '4321': 'Asia/Makassar'}, tz)
    check('leader-only club fields are kept privately', q("select data->>'dcpGoals' g from hdg_sync_private.legacy_records where kind = 'club' and key = '90001001'")['g'] == '4')
    det = {r['club_number']: r['details'] for r in sql('select club_number, details from public.hdg_clubs')}
    check('the club details every member can read hold only public fields',
          all(set(d) <= {'meeting_mode'} for d in det.values()) and det['90001002'] == {'meeting_mode': 'Hybrid'}, det)

    # Re-running changes nothing, and manual or hand-corrected values survive.
    before = counts()
    copy()
    check('running the copy again changes nothing', counts() == before, (before, counts()))
    sql("update public.hdg_people set nickname = 'Ally', name = 'Test Alpha Corrected', hand_corrected = '{\"name\": {\"value\": \"Test Alpha Corrected\"}}' where ti_member_id = '10000001'")
    copy()
    alpha = q("select nickname, name from public.hdg_people where ti_member_id = '10000001'")
    check('a nickname edited in the app survives a re-copy', alpha['nickname'] == 'Ally', alpha)
    check('a hand-corrected name survives a re-copy', alpha['name'] == 'Test Alpha Corrected', alpha)
    check('the shared record itself is never changed', q("select count(*) n from public.hdg_sync_state where payload->'database' ? 'memberIdentityAliases'")['n'] == 1)
finally:
    sql(foundation_sql())   # restore the access-test fixtures

failed = [r for r in results if not r[0]]
for ok, name, detail in results:
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if not ok and detail else ''))
print(f'\n{len(results) - len(failed)}/{len(results)} copy checks passed.')
sys.exit(1 if failed else 0)
