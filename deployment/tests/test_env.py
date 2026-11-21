"""Shared helpers for the Hello Division G test project. Synthetic data only.

The test project is a separate Supabase project. These helpers refuse the
production project so a test can never touch real member data.
"""
import json, os, subprocess, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRODUCTION_REF = 'bhbgusdxqbjwsdlzhurb'
TEST_REF = os.environ.get('HDG_TEST_REF', 'ovmdhkrkogivlvjnbqpj')
if TEST_REF == PRODUCTION_REF:
    raise SystemExit('Refusing to run: HDG_TEST_REF points at production.')
URL = f'https://{TEST_REF}.supabase.co'
LOCAL = ROOT / 'local-data' / 'test-project.json'   # git-ignored: test passwords and keys
CLI = os.environ.get('SUPABASE_CLI', 'supabase')


def cli_json(*args):
    run = subprocess.run([CLI, *args], capture_output=True, text=True)
    if run.returncode:
        raise SystemExit('Supabase CLI failed: ' + (run.stderr or run.stdout)[-1500:])
    out = run.stdout
    start = min(i for i in (out.find('['), out.find('{')) if i >= 0)
    return json.loads(out[start:])


def keys():
    """Publishable and secret keys of the TEST project, fetched with the logged-in CLI."""
    rows = cli_json('projects', 'api-keys', '--project-ref', TEST_REF, '-o', 'json')
    publishable = next(k['api_key'] for k in rows if k.get('type') == 'publishable')
    service = next(k['api_key'] for k in rows if k.get('name') == 'service_role')
    return publishable, service


def sql(query):
    """Run SQL on the TEST project through the CLI and return rows."""
    data = cli_json('db', 'query', f'--remote={TEST_REF}', '--output-format', 'json', '--yes', query)
    return data.get('rows', [])


def request(method, path, key, token=None, body=None, headers=None):
    h = {'apikey': key, 'Content-Type': 'application/json'}
    if token:
        h['Authorization'] = f'Bearer {token}'
    h.update(headers or {})
    data = body if isinstance(body, bytes) else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(URL + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            try:
                return r.status, json.loads(raw) if raw else None
            except ValueError:
                return r.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


def load_local():
    return json.loads(LOCAL.read_text())
