#!/usr/bin/env python3
"""Clean-up of full copies (008): late copies after 7 days, revision history keeps the last 10 saves.

TEST project only. Re-run setup_test_project.py afterwards to restore the normal fixtures.
Usage: SUPABASE_CLI=/path/to/supabase python3 deployment/tests/retention_check.py
"""
import sys, uuid
from test_env import request, load_local, sql

cfg = load_local()
KEY = cfg['publishable_key']
a = cfg['accounts']['officer']
tok = request('POST', '/auth/v1/token?grant_type=password', KEY, body={'email': a['email'], 'password': a['password']})[1]['access_token']
results = []
check = lambda name, ok, detail='': results.append((bool(ok), name, detail))

sql(f"""
update public.hdg_sync_state set revision = 1000 where division_code = 'G';
truncate hdg_sync_private.revision_history; truncate hdg_sync_private.superseded_saves;
insert into hdg_sync_private.revision_history(revision, payload, updated_at)
  select r, '{{}}'::jsonb, now() - (1000 - r) * interval '1 hour' from generate_series(940, 999) r;
insert into hdg_sync_private.superseded_saves(request_id, at, actor, base_revision, current_revision, payload) values
  ('{uuid.uuid4()}', now() - interval '8 days', '{a['id']}', 1, 2, '{{}}'),
  ('{uuid.uuid4()}', now() - interval '1 day', '{a['id']}', 3, 4, '{{}}');
""")
state = request('GET', '/rest/v1/hdg_sync_state?select=revision,payload', KEY, tok)[1][0]
s, body = request('POST', '/rest/v1/rpc/hdg_save_web_state', KEY, tok,
                  {'p_expected_revision': state['revision'], 'p_payload': state['payload'], 'p_request_id': str(uuid.uuid4())})
check('a normal save still works', s == 200 and body.get('revision') == 1001, str(body)[:100])
h = sql('select count(*) n, min(revision) lo, max(revision) hi from hdg_sync_private.revision_history')[0]
check('revision history keeps exactly the last 10 saves', h['n'] == 10 and h['lo'] == 991 and h['hi'] == 1000, h)
ss = sql("select count(*) n, bool_and(at > now() - interval '7 days') recent from hdg_sync_private.superseded_saves")[0]
check('late copies older than 7 days are deleted, newer ones kept', ss['n'] == 1 and ss['recent'], ss)

sql(f"insert into hdg_sync_private.superseded_saves(request_id, at, actor, base_revision, current_revision, payload) values "
    f"('{uuid.uuid4()}', now() - interval '9 days', '{a['id']}', 1, 2, '{{}}')")
s, body = request('POST', '/rest/v1/rpc/hdg_save_web_state', KEY, tok,
                  {'p_expected_revision': 999, 'p_payload': state['payload'], 'p_request_id': str(uuid.uuid4())})
ss = sql("select count(*) n, bool_and(at > now() - interval '7 days') recent from hdg_sync_private.superseded_saves")[0]
check('a late save is still set aside quietly', s == 200 and body.get('superseded') is True, str(body)[:100])
check('a late save also clears copies older than 7 days', ss['n'] == 2 and ss['recent'], ss)

failed = [r for r in results if not r[0]]
for ok, name, detail in results:
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if not ok and detail else ''))
print(f'\n{len(results) - len(failed)}/{len(results)} clean-up checks passed.')
sys.exit(1 if failed else 0)
