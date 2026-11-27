#!/usr/bin/env python3
"""Build the retired separate division app for synthetic tests only.

Do not release the separate Division K build. The 27 November 2026 owner decision uses one shared app.

Starts from the Member build (deployment/build_member_v632.py, which already removes Division G member records,
names, IDs and contacts) and then, following project/DISTRICT_PLAN.md rules 22-23 and the owner's decisions of
21-23 November 2026:
  1. removes Division G's club-owned designs: only the generic posters and agendas stay (window.HDG_GENERIC_TEMPLATES),
     club logos are emptied, club slide themes and the club-matching shortcuts are removed;
  2. labels the app for the division: name, time zone label (MYT for Malaysia), currency (RM) and its own storage;
  3. audits the result and stops if Division G designs, logos or labels are still present.
The division's clubs, areas and officers arrive at sign-in from the database (the same way the Member app receives
Division G's), so nothing about the division is built in.

Usage: python3 deployment/build_division_app.py --division K /private/HelloDivisionG_v655.html private-app/division-k.html
"""
import argparse, json, re, subprocess, sys, tempfile
from pathlib import Path

DIVISIONS = {'K': {'name': 'Division K', 'tz': 'MYT', 'currency': 'MYR'}}
GENERIC_POSTERS = ['split', 'field', 'fullbleed', 'datehero', 'halves']
GENERIC_AGENDAS = ['bintulu', 'btc', 'btcClassic', 'baliTnc', 'mbtc2026']
CLUB_LOGOS = ['BSC_LOGO_WHITE_V480', 'STC_LOGO_V501', 'SATURNET_LOGO_V501', 'BTC_LOGO_BLUE_V504',
              'BTC_LOGO_LINE_BLUE_V504', 'BTC_LOGO_LINE_V504', 'BTC_LOGO_WHITE_V504']

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('--division', required=True, choices=sorted(DIVISIONS))
ap.add_argument('source', type=Path)
ap.add_argument('output', type=Path)
args = ap.parse_args()
root = Path(__file__).resolve().parents[1]
if args.output.resolve().is_relative_to((root / 'docs').resolve()):
    ap.error('Division builds go to private storage, never into the public docs folder.')
D = DIVISIONS[args.division]
code = args.division

# ---------------------------------------------------------------- 1. the Member build (no Division G member data)
with tempfile.TemporaryDirectory() as tmp:
    member = Path(tmp) / 'member.html'
    run = subprocess.run([sys.executable, str(root / 'deployment/build_member_v632.py'), str(args.source), str(member)],
                         capture_output=True, text=True)
    if run.returncode:
        sys.exit('Member build failed: ' + (run.stderr or run.stdout)[-1500:])
    s = member.read_text(encoding='utf-8')
MEMBER_SCRIPT_ENDS = s.count('</script>')

def rep(old, new, n=1):
    global s
    c = s.count(old)
    assert c == n, f'{c} != {n}: {old[:90]}'
    s = s.replace(old, new)

def cut_function(name, replacement, end_marker='\nfunction '):
    """Replace a top-level function, up to the next top-level function (or end_marker), with a short replacement.
    Stops if the removed part contains any other top-level code."""
    global s
    assert s.count(f'\nfunction {name}(') == 1, name
    i = s.index(f'\nfunction {name}(')
    j = s.index(end_marker, i + 10)
    removed = s[i + 1:j]
    assert not re.search(r'\n(const |let |var |window\.|\(function|</script>|<script)', removed), f'{name}: cut would remove other code'
    s = s[:i] + '\n' + replacement + s[j:]

# ---------------------------------------------------------------- 2. generic designs only
# Posters: remove the club layouts' drawing code and keep only the generic layouts in the picker.
i = s.index('const LAYOUTS=['); j = s.index('];', i) + 2
rows = {m.group(1): m.group(0) for m in re.finditer(r"\['([a-z0-9]+)','[^\]]*\]", s[i:j])}
assert set(GENERIC_POSTERS) <= set(rows), rows.keys()
s = s[:i] + 'const LAYOUTS=[\n' + ',\n'.join('  ' + rows[k] for k in GENERIC_POSTERS) + '\n ];' + s[j:]
for key in sorted(set(rows) - set(GENERIC_POSTERS)):
    start = s.index(f'R.{key}=D=>{{')
    end = s.index('return o;};', start) + len('return o;};')
    nxt = re.search(r'R\.[a-z0-9]+=D=>\{', s[start + 5:])
    assert nxt is None or start + 5 + nxt.start() > end, f'layout {key} would cut into the next layout'
    s = s[:start] + f'R.{key}=D=>R.split(D);' + s[end:]
rep("function defaultLayout(club){const n=String((club&&club.name)||'').toLowerCase();",
    "function defaultLayout(club){return 'split';const n=String((club&&club.name)||'').toLowerCase();")

# Agendas: generic designs only; club designs fall back to Blue Structured.
i = s.index('BUILTIN=['); j = s.index('];', i)
builtin = [a for a in json.loads(s[i + 8:j + 1]) if a['id'] in GENERIC_AGENDAS]
for a in builtin:
    a['club'] = 'All divisions'
s = s[:i] + 'BUILTIN=' + json.dumps(builtin, ensure_ascii=False) + s[j + 1:]
i = s.index('<select class="app-standard-select" id="agendaVisualStyle"'); j = s.index('</select>', i)
opts = re.findall(r'<option value="([A-Za-z0-9]+)"[^>]*>[^<]*</option>', s[i:j])
keep = ''.join(m.group(0) for m in re.finditer(r'\s*<option value="([A-Za-z0-9]+)"[^>]*>[^<]*</option>', s[i:j])
               if m.group(1) in GENERIC_AGENDAS)
head = s[i:s.index('>', i) + 1]
s = s[:i] + head + '\n<option value="btc" selected>Blue Structured · Session Table</option>' + keep.replace(
    '<option value="btc">Blue Structured · Session Table</option>', '') + '\n' + s[j:]
rep("function agendaVisualStyle(record){",
    "function agendaVisualStyle(record){const g=" + json.dumps(GENERIC_AGENDAS) + ",v=agendaVisualStyleRaw(record);return g.includes(v)?v:'btc';}\nfunction agendaVisualStyleRaw(record){")
for name in ('agendaStcA4HTML', 'agendaStcFlippedA4HTML', 'agendaBscA4HTML'):
    cut_function(name, f'function {name}(record){{return agendaBtcA4HTML(record);}}')
cut_function('agendaClubStyleMatchV374', "function agendaClubStyleMatchV374(record){return '';}")
s, n = re.subn(r"const AGENDA_AUTO_VARIANTS_V374=Object\.freeze\(\[[^\]]*\]\);",
               'const AGENDA_AUTO_VARIANTS_V374=Object.freeze(' + json.dumps(GENERIC_AGENDAS) + ');', s)
assert n == 1, 'auto variants'

# Slides: no club slide themes.
i = s.index("  bsc:{name:'Bali Speakers Club'"); j = s.index("  universal:{name:'Universal Division G'", i)
s = s[:i] + s[j:]
rep("universal:{name:'Universal Division G'", "universal:{name:'Universal'")

# Slides: only the generic deck. The two clubs' own decks (Bali Speakers Club, Bali Toastmasters Club) are removed.
def remove_script(sid):
    global s
    i = s.index(f'<script id="{sid}">'); j = s.index('</script>', i) + len('</script>')
    s = s[:i] + s[j:]
remove_script('v481-bsc-canva-flow')
remove_script('v516-btc-slides')
cut_function('bscSlideSvgV469', "function bscSlideSvgV469(record,item){return '';}", end_marker='\n(function(){')
rep("function agendaPresentationTemplate(record){", "function agendaPresentationTemplate(record){return 'universal';")
s, n = re.subn(r'\s*<option value="(bsc|btc)">[^<]*</option>(?=[\s\S]{0,400}<option value="universal">)', '', s)
assert n == 2, 'slide template options'

# Calendar groups: the division's areas (from its clubs at sign-in) instead of Division G's islands.
rep("const COMMUNITY_REGION_VALUES=['east-java','bali','kalimantan','sulawesi','online'];",
    "const COMMUNITY_REGION_VALUES=[...new Set(((window.HDG_MEMBER_V632_DATA||{}).clubs||[]).map(c=>String(c.area||'')).filter(Boolean))].sort();")
cut_function('clubCalendarRegion', "function clubCalendarRegion(c,p){return String(c?.area||'');}")
cut_function('eventCalendarRegion', "function eventCalendarRegion(obj={}){if(obj.region&&COMMUNITY_REGION_VALUES.includes(obj.region))return obj.region;"
             "if(obj.clubNumber){const c=specialMeetingClub(obj.clubNumber);if(c)return clubCalendarRegion(c);}return '';}")
i = s.index('<span class="calendar-region-filter-label">Show clubs</span>'); j = s.index('</div>', i)
s = s[:i] + '<span class="calendar-region-filter-label">Show areas</span>' + s[j:]
_body = s.rindex('</body>')  # the document's own </body> is the last one; print templates contain earlier ones
s = s[:_body] + """<script id="hdg-division-areas">(function(){
 /* Area checkboxes for the division's calendar, built from its own clubs. */
 function fill(){const box=document.getElementById('calendarRegionFilter');if(!box||box.dataset.areas)return;box.dataset.areas='1';
  COMMUNITY_REGION_VALUES.forEach(code=>{const l=document.createElement('label'),i=document.createElement('input'),t=document.createElement('span');
   i.type='checkbox';i.value=code;i.checked=true;i.addEventListener('change',()=>onCalendarRegionFilterChange());t.textContent='Area '+code;l.append(i,t);box.append(l);});
  try{syncCalendarRegionControls();}catch(_){}}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',fill);else fill();
})();</script>
""" + s[_body:]

# Club logos: emptied.
for var in CLUB_LOGOS:
    s, n = re.subn(r'(window\.' + var + r'=)"data:image/[^"]*"', r'\1""', s)
    assert n == 1, var

# Division G data tables (areas, brands, club notes, TLI sessions, seeded events): emptied; the division's own data
# comes from the database at sign-in.
def empty_const(name, value):
    global s
    i = s.index(f'\nconst {name}={{'); j = s.index('\n};', i) + 3
    s = s[:i] + f'\nconst {name}={value};' + s[j:]
empty_const('DIVISION_G_CANONICAL_DATA', "{division:{code:'" + code + "',district:'87',region:'9',director:'Division Director'},"
            "areas:{},brands:{},clubMetadata:{},tliPatches:{},seededCommunityEvents:[]}")
empty_const('TLI_V252_CONFIRMED', '{}')

# ---------------------------------------------------------------- 3. the division's labels, time zone, currency, storage
rep("const KEY = 'tm_division_g_member_v632_' + (window.HDG_MEMBER_V632_ACCOUNT || 'preview');",
    f"const KEY = 'tm_division_{code.lower()}_app_' + (window.HDG_MEMBER_V632_ACCOUNT || 'preview');")
rep("const DURABLE_DB_NAME = 'hello_division_g_member_v632_' + (window.HDG_MEMBER_V632_ACCOUNT || 'preview');",
    f"const DURABLE_DB_NAME = 'hello_division_{code.lower()}_app_' + (window.HDG_MEMBER_V632_ACCOUNT || 'preview');")
rep("settings: { divisionCode: 'G',", f"settings: {{ divisionCode: '{code}',")
s, n = re.subn(r"st\(\)\.feeCurrency==='MYR'\|\|st\(\)\.feeCurrency==='USD'",
               f"(st().feeCurrency||'{D['currency']}')==='MYR'||st().feeCurrency==='USD'", s)
assert n >= 1, 'currency'
# Visible text outside embedded images and fonts.
blob = re.compile(r'data:[a-z/+.-]+;base64,[A-Za-z0-9+/=]+')
parts, last = [], 0
for m in blob.finditer(s):
    parts.append(('t', s[last:m.start()])); parts.append(('b', m.group(0))); last = m.end()
parts.append(('t', s[last:]))
def relabel(t):
    t = t.replace('Hello Division G', 'Hello ' + D['name']).replace('Division G', D['name'])
    t = t.replace('DIVISION G', D['name'].upper()).replace('WITA', D['tz'])
    return t
s = ''.join(relabel(t) if k == 't' else t for k, t in parts)
# Division G's Indonesia map and WIB toggle do not apply: hidden. (The calendar groups by area, above.)
_head = s.index('</head>'); assert s.find('<body', _head) - _head < 40, 'document head'
s = s[:_head] + '<style id="hdg-division-hide">#calendarTimezoneWIB,#communityViewMap{display:none!important}</style>\n' + s[_head:]
s = s.replace('<head>', '<head>\n<script id="hdg-division-build">window.HDG_DIVISION_BUILD=' + json.dumps(
    {'code': code, 'name': D['name'], 'timezone': D['tz'], 'currency': D['currency'],
     'generic': {'posters': GENERIC_POSTERS, 'agendas': GENERIC_AGENDAS}}) + ';</script>', 1)

# ---------------------------------------------------------------- 4. audit: stop if Division G designs or labels remain
text = blob.sub('', s)
problems = []
if re.search(r"R\.(phototop|event|minimal|typo|banner|pill|question|mbtc|stc2025)=D=>\{", text):
    problems.append('club poster layout code')
for var in CLUB_LOGOS:
    if re.search(r'window\.' + var + r'="data:', s):
        problems.append('club logo ' + var)
if re.search(r'"club":"(?!All divisions)', s[s.index('BUILTIN='):s.index('BUILTIN=') + 20000]):
    problems.append('club agenda in the design list')
for table in ('TLI_V252_CONFIRMED', 'DIVISION_G_CANONICAL_DATA'):
    if re.search(r'const ' + table + r'=\{\n', text):
        problems.append('Division G data table ' + table)
for sid in ('v481-bsc-canva-flow', 'v516-btc-slides'):
    if f'<script id="{sid}">' in s:
        problems.append('club slide deck ' + sid)
if 'east-java' in text[text.find('const COMMUNITY_REGION_VALUES='):text.find('const COMMUNITY_REGION_VALUES=') + 200]:
    problems.append('Division G island groups')
if "bsc:{name:'Bali Speakers Club'" in text:
    problems.append('club slide theme')
for label in ('Division G', 'DIVISION G', 'WITA'):
    if label in text:
        problems.append(f'label {label!r} x{text.count(label)}')
# script structure: the Member build's closing tags, minus the 2 club slide scripts, plus the 2 added scripts
if s.count('</script>') != MEMBER_SCRIPT_ENDS - 2 + 2:
    problems.append(f"script tags changed unexpectedly ({MEMBER_SCRIPT_ENDS} -> {s.count('</script>')})")
if problems:
    sys.exit('Audit failed: ' + '; '.join(problems))
# Club names that remain only as public district directory data or neutral code conditions are reported, not built in.
report = {n: text.count(n) for n in ('Bali Speakers', 'Bali Toastmasters', 'Magical', 'Surabaya', 'Makassar', 'Saturnet')}

args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(s, encoding='utf-8')
print(f"{D['name']} build: {len(s)} characters. Audit passed. Remaining club-name mentions (directory data and code conditions):", report)
