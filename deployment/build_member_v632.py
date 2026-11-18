from pathlib import Path
import argparse
from hashlib import sha256
import json
import re
import unicodedata

parser=argparse.ArgumentParser(description="Compile the original v632 Member runtime with private seeds removed.")
parser.add_argument('source',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
if args.output.resolve().is_relative_to((root/'docs').resolve()) or args.source.resolve()==args.output.resolve():
 parser.error('Build into a new private path.')
original=args.source.read_bytes()
assert sha256(original).hexdigest()=="f25b7f5edd31d9b77c3b244dcb1016f67c88be482d54d7ef222bfdad1e096aa9"
source=original.decode()
known_rows=[]
for key in ('memberRecords','officerRecords'):
 literal=next(line.strip().split(':',1)[1].strip().removesuffix(',') for line in source.splitlines()
              if line.lstrip().startswith(key+':') and len(line)>5000)
 known_rows+=json.loads(literal)


def segment(start,end,replacement):
 global source
 before=source.index(start)
 after=source.index(end,before+len(start))
 source=source[:before]+replacement+source[after:]

def replace(before,after):
 global source
 assert source.count(before)==1,before[:80]
 source=source.replace(before,after,1)

def remove_script(name):
 global source
 start=source.index('<script id="'+name+'">')
 end=source.index('</script>',start)+len('</script>')
 source=source[:start]+source[end:]

def replace_literal_line(literal,value):
 global source
 pattern=r'(?m)^(\s*(?:const|let) '+literal+r'\s*=).+?;\s*$'
 source, hits=re.subn(pattern,lambda m:m[1]+value+';',source,count=1)
 assert hits==1,literal

replace_literal_line('TI_CLUB_DIRECTORY_SEED','[]')
replace_literal_line('AD_VISIT_SEED_REPORTS','[]')
segment('function applyADVisitReportMigration(data){','function applyTliVenueMigration',
 'function applyADVisitReportMigration(data){return data;}\n\n')

segment('function sampleData() {','const defaults = sampleData();','''function sampleData() {
  const data = window.HDG_MEMBER_V632_DATA || {};
  return {
    settings: { divisionCode: 'G', divisionDirector: data.director || 'Division Director' },
    ui: { activeDashboardUser: 'member' },
    areas: data.areas || [],
    clubs: data.clubs || [],
    tlis: data.tlis || [],
    contests: data.contests || [],
    specialMeetings: data.specialMeetings || [],
    updated: data.updated || new Date().toISOString()
  };
}

''')
segment('function isLegacyDivisionGShape(data){','function applyDataMigrations(data){',
 'function isLegacyDivisionGShape(){return false;}\n')
segment('function applyKnownMemberIdentityMigration(data){','function parseClubAliases',
 'function applyKnownMemberIdentityMigration(data){return data;}\n\n')
segment('function ensureMemberAliasRegistry(data){','function applyKnownMemberIdentityMigration',
 '''function ensureMemberAliasRegistry(data){
  if(data?.database) data.database.memberIdentityAliases ||= {};
  return data;
}

''')
segment('const DASHBOARD_USERS={','function dashboardUserCatalog(){', '''const DASHBOARD_USERS={
 division:{name:'Division Director'},
 member:{id:'member',role:'member',name:'Division G Member',shortName:'Member',area:'',label:'Community access',avatar:'G'}
};
''')
segment('function activeDashboardUser(){','function renderUserSwitcherChoices(){',
 'function activeDashboardUser(){return DASHBOARD_USERS.member;}\n\n')
segment('function renderUserSwitcherChoices(){','function adViewMode(',
 'function renderUserSwitcherChoices(){document.querySelector("#userSwitcher .user-switcher-menu")?.replaceChildren();}\n\n')
segment('function switchDashboardUser(id){','function normalizeDashboardRoleState(){',
 'function switchDashboardUser(){}\n\n')
segment('function applyDataMigrations(data){','const CANONICAL_BRAND_ASSETS', 'function applyDataMigrations(data){return data||{};}\n\n')
segment('function promoteLegacyDivisionGKnowledgeOnce(data){','function syncCentralDatabaseFromAliases', 'function promoteLegacyDivisionGKnowledgeOnce(data){return data;}\n\n')

for script in ('v365-exco-cleanup-startup','v367-membership-name-repair','v504-poster-history','v504-fee-note-fix',
 'v526-nickname-seed','v527-nickname-update','v586-tli-pic-registration','v588-surabaya-tli-details',
 'v614-projects-workspace','v615-tli2-surabaya','v617-past-exco'):
 remove_script(script)

# Preserve STC template code. Remove the data initializers for the historical contacts.
segment(" /* seed: the club's own published agendas", ' function clubContacts(num)', '')
# The join slide renderer still exists and can use club contacts entered by the member.
source=re.sub(r"contacts:\[\{name:'Sindhu',phone:.*?\}\]",'contacts:[]',source,count=1)

# Replace account-specific images of old printed agendas and QR codes with an
# empty placeholder. The generic runtime renderer still renders its templates.
blank='data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'
for length in (56124,32936,47920,43916,68456,54172,63956,78704,112696,39896,83796,81488):
 pat=re.compile(r'data:image/(?:jpeg|png);base64,([0-9A-Za-z/+=]{'+str(length)+r'})(?![0-9A-Za-z/+=])')
 source,hits=pat.subn(blank,source)
 assert hits==1,(length,hits)

# Keep District 87 browsing and the calendar's directory lookup. Use only
# details suitable for members from the approved club discovery fields.
pattern=r'(?m)^(const DISTRICT87_DISCOVERY_DETAILS=Object.freeze\()(.+)\);$'
m=re.search(pattern,source)
discovery=json.loads(m[2])
allowed={'meetingSchedule','meetingMode','timezone','ianaTimezone','onlineAttendance','verifiedAt','charterDate','restriction'}
projected={k:{name:value for name,value in row.items() if name in allowed} for k,row in discovery.items()}
source=source[:m.start(2)]+json.dumps(projected,ensure_ascii=False,separators=(',',':'))+source[m.end(2):]

# Create a separate offline storage namespace for the Member view.
replace("const KEY = 'tm_division_g_dashboard_v56';",
 "const KEY = 'tm_division_g_member_v632_' + (window.HDG_MEMBER_V632_ACCOUNT || 'preview');")
replace("const DURABLE_DB_NAME = 'hello_division_g_durable_v1';",
 "const DURABLE_DB_NAME = 'hello_division_g_member_v632_' + (window.HDG_MEMBER_V632_ACCOUNT || 'preview');")

# The launcher supplies only the authenticated Community projection. Escaping
# the JSON belongs at that boundary, before inserting it as an inline script.
runtime=(root/'deployment/member-v632-runtime.js').read_text()
assert '</script' not in runtime.lower()
source=source.replace('<head>','<head>\n<script id="hdg-member-context">/* HDG_MEMBER_V632_CONTEXT */</script>\n<script>'+runtime+'</script>',1)
replace('const DURABLE_INIT_PROMISE=initializeDurableStorage();',"""const DURABLE_INIT_PROMISE=initializeDurableStorage().then(result=>{
  const community=sampleData();
  for(const key of ['clubs','areas','tlis','contests','specialMeetings'])db.database[key]=community[key];
  db.settings.divisionDirector=community.settings.divisionDirector;
  db.updated=community.updated;
  normalizeDashboardRoleState();
  applyDashboardUser();
  render();
  return result;
});""")

# Drop any plaintext names from the bundled membership file that remain in
# examples, fill-in captions or legacy identity-specific branches.
patterns=set()
ids=set()
for row in known_rows:
 name=str(row.get('name') or '').strip()
 if len(name)>6 and ' ' in name:
  normalized=''.join(c for c in unicodedata.normalize('NFKD',name.casefold()) if c.isalnum() and not unicodedata.combining(c))
  patterns.update({name,normalized})
 number=str(row.get('memberId') or '').lstrip('0')
 if len(number)>=6 and number.isdigit(): ids.add(number)
escape=lambda terms:'|'.join(re.escape(t) for t in sorted(terms,key=len,reverse=True))
person=re.compile(r'(?<![\w])(?:'+escape(patterns)+r')(?![\w])',re.I)
person_id=re.compile(r'(?<![0-9])0*(?:'+escape(ids)+r')(?![0-9])')
opaque=re.compile(r'[0-9A-Za-z/+=]{220,}')
sections=[]
last=0
for blob in opaque.finditer(source):
 snippet=source[last:blob.start()]
 sections.extend([person_id.sub('0',person.sub('Member',snippet)),blob[0]])
 last=blob.end()
sections.append(person_id.sub('0',person.sub('Member',source[last:])))
source=''.join(sections)

# Stored poster/contact defaults are filled from the user's drafts at run time.
source=re.sub(r"((?<![\w])(?:contactName|contactValue|clubPosterContactName|clubPosterContactValue|clubPosterInstagram)\s*:\s*)(['\"])(?:\\.|(?!\2)[^\\\r\n])*?\2",lambda m:m[1]+"''",source)
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(source)
print('Local staging build:',len(source),'characters')
