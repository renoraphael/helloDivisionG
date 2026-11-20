from pathlib import Path
import argparse
from hashlib import sha256
import json
import re
import unicodedata
from urllib.parse import urlsplit, urlunsplit

parser=argparse.ArgumentParser(description="Compile the original v632 Member runtime with private seeds removed.")
parser.add_argument('source',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
if args.output.resolve().is_relative_to((root/'docs').resolve()) or args.source.resolve()==args.output.resolve():
 parser.error('Build into a new private path.')
original=args.source.read_bytes()
# v632 is the original; v633 adds the rebuilt Division Map; v634 adds the elective-level / misspelt-title parser fix; v637 adds the picker themes, name pickers and the Magical-Bali poster layout; v638 makes that layout follow the Toastmasters logo picker.
assert sha256(original).hexdigest() in (
 "f25b7f5edd31d9b77c3b244dcb1016f67c88be482d54d7ef222bfdad1e096aa9",
 "38c29a459e7ed676eb0afcde1ec43d87435a2585c465b1d7c5733c4fef6398f5",
 "b79fb8fae85f81edde772b5adb2318fe683e0c35e237e2dc77bd1ca0a979c9bd",
 "bb46e07fd7135eda1ee53156403dfe4e7a3580a37821b3970bc826ecc0b0c879",
 "9cac07ade113f8002506bbb8c04c6d9bc22ee488c9e702df7c6eaae340947daa",
 "2b74d32589711e92ad474bc36f31e83e3446efd1b36956db3eaa56c7c3717b14")
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
replace('<div class="subbrand">District 87 · Region 9 · Toastmasters reporting system</div>',
 '<div class="subbrand">District 87 · Region 9</div>')
segment('        <div class="member-community-nav-head">','        <button type="button" class="member-community-link active"', '')
# The original council renderer hard-coded a name. The Member asset uses the
# authorised Community projection instead of that redacted literal.
source,director_calls=re.subn(r"(leadershipDirectorCard\('division','G','DIVISION G DIRECTOR',)'[^']*'(,'District 87 · Region 9'\))",r"\1(db.settings?.divisionDirector||'Division Director')\2",source)
assert director_calls==2
# Reuse the v632 Agenda lookup and datalist with a read-only names projection.
# Keep the operational membership roster out of the Member workspace.
for start,end,expected in (
 ('function resolveMemberIdentity(input,preferredClubNumber=', 'function agendaCleanInformalName', 1),
 ('function agendaIdentityMemberships(hit,opts=', 'function agendaLinkMeetingIdentities', 3),
 ('function agendaRefreshMemberDatalist(clubNumber)', 'function agendaRecordsForClub', 1),
 ('window.agendaRefreshMemberDatalist=function(clubNumber)', 'function normalizeAgendaPathwayRowsV309', 1),
):
 before=source.index(start)
 after=source.index(end,before+len(start))
 code=source[before:after]
 if start.startswith('function resolveMemberIdentity'):
  first=code.index("  if(tokens.includes('suzie'))")
  last=code.index('  // Conservative short-name inference:',first)
  code=code[:first]+code[last:]
  first=code.index('  // Fallback to the central alias registry')
  code=code[:first]+'  return null;\n}\n'
 if start.startswith('function agendaIdentityMemberships'):
  code=code.replace('m.key===opts.memberKey','memberKey(m)===opts.memberKey')
  code=code.replace('m.key===exact.key','memberKey(m)===memberKey(exact)')
 assert code.count('(db.memberRecords||[])')==expected,start
 source=source[:before]+code.replace('(db.memberRecords||[])','window.HDG_MEMBER_V632_DATA.agendaMembers')+source[after:]
replace('<div><strong>${rec.goals}/10</strong><span>DCP</span></div>',
 '<div><strong>${c.dcpGoals==null?\"—\":rec.goals+\"/10\"}</strong><span>DCP</span></div>')
replace("function councilOfficer(c,role){return (db.officerRecords||[]).find(o=>normalized(o.clubNumber)===normalized(c.number)&&o.role===role&&!officerIsPast(o))}",
 "function councilOfficer(c,role){return window.HDG_MEMBER_V632_DATA.clubOfficers.get(String(c.number||'').trim().replace(/^0+/,''))?.get(role);}")
replace('<span class="leadership-elected-note">Elected position · cannot dismiss</span>','')
replace('  return ensureLeadershipTeams().filter(x=>x.scopeType===scopeType&&x.scope===scope);',
 '  return ensureLeadershipTeams().filter(x=>x.scopeType===scopeType&&x.scope===scope&&x.name!==\"Member\");')
# Keep the existing v632 theme control in the Member toolbar and cycle the
# two Toastmasters palettes through the original theme setter.
replace('body.role-member .toolbar-shell > :not(.user-switcher){display:none!important}',
 """body.role-member .toolbar-shell > :not(.user-switcher):not(#v622ThemeBtn):not(#hdgMemberSignOut){display:none!important}
body.role-member .toolbar-shell .user-switcher-summary .chevron{display:none}
body.role-member .toolbar-shell #hdgMemberSignOut{
  min-height:44px;
  padding-inline:12px;
  white-space:nowrap;
  flex-shrink:0;
}
body.role-member .toolbar-shell #v622ThemeBtn{
  width:46px!important;
  height:46px!important;
  min-width:46px!important;
  min-height:46px!important;
  flex-shrink:0;
  border:1px solid rgba(245,245,245,.65)!important;
}
body.role-member .toolbar-shell #v622ThemeBtn svg{width:30px!important;height:30px!important;flex:none}
@media screen and (max-width:760px){
  body.role-member .app-header .toolbar-shell #hdgMemberSignOut,
  body.role-member .app-header .toolbar-shell #v622ThemeBtn{
    position:fixed!important;
    top:12px;
    z-index:150;
    min-height:46px;
    color:#fff!important;
    background:#004165!important;
    border:1px solid rgba(245,245,245,.65)!important;
  }
  html.theme-maroon body.role-member .app-header .toolbar-shell #hdgMemberSignOut,
  html.theme-maroon body.role-member .app-header .toolbar-shell #v622ThemeBtn{background:#772432!important}
  body.role-member .app-header .toolbar-shell #v622ThemeBtn{right:12px}
  body.role-member .app-header .toolbar-shell #hdgMemberSignOut{right:66px}
}""")
replace("ORDER=['classic','ti','maroon'];","ORDER=['ti','maroon'];")
replace("b.setAttribute('aria-pressed',t==='classic'?'false':'true')","b.setAttribute('aria-pressed',String(t==='maroon'))")
segment('const DASHBOARD_USERS={','function dashboardUserCatalog(){', '''const DASHBOARD_USERS={
 division:{name:'Division Director'},
 member:{id:'member',role:'member',name:window.HDG_MEMBER_V632_DATA.memberName,shortName:window.HDG_MEMBER_V632_DATA.memberName,area:'',label:'Community access',avatar:Array.from(window.HDG_MEMBER_V632_DATA.memberName)[0].toUpperCase()}
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

# The Member parser starts with no selection. Clearing the input also clears
# the selected club and meeting, while the saved agenda stays in its store.
remove_script('v478-remember-active-meeting')
# A Poster meeting enters Agenda only through the explicit Open in Agenda action.
replace("      if(panel==='agenda')setTimeout(adoptContextInAgenda,0);\n", '')
replace("    try{showCommunityPanel('agenda');}catch(_){}\n    const btn=document.querySelector('.community-tabs",
 "    try{showCommunityPanel('agenda');adoptContextInAgenda();}catch(_){}\n    const btn=document.querySelector('.community-tabs")

segment('  function resetAgendaWorkspaceFromImport(removeImportedRecord=true){',
 "  document.addEventListener('DOMContentLoaded',bindEmptyRosterReset);",
 """  function resetAgendaWorkspaceFromImport(){
    agendaGeneratedRecordId='';
    const paste=$('agendaRosterPaste');
    const club=$('agendaImportClub');
    const meeting=$('agendaMeetingSelect');
    if(paste)paste.value='';
    if(club)club.value='';
    if(meeting)meeting.value='';
    const status=$('agendaImportStatus');
    if(status){
      status.className='agenda-import-status';
      status.textContent='Paste a WhatsApp roster, choose a club, or start a meeting manually.';
    }
    renderCommunityAgendaPrototype();
  }
  window.resetAgendaWorkspaceFromImport=resetAgendaWorkspaceFromImport;
  window.clearAgendaPaste=resetAgendaWorkspaceFromImport;

  function bindEmptyRosterReset(){
    const paste=$('agendaRosterPaste');
    if(!paste||paste.dataset.v319EmptyResetBound)return;
    paste.dataset.v319EmptyResetBound='1';
    paste.addEventListener('input',()=>{
      if(!paste.value.trim())resetAgendaWorkspaceFromImport();
    });
  }
""")
# Leave the Poster picker empty unless the member explicitly loads a draft or club.
segment('  function adoptAgendaInPoster(record){', '  function adoptContextInAgenda(){', '')
replace("          adoptAgendaInPoster(record);\n", '')
segment('  const baseShow=window.showCommunityPanel;\n  if(typeof baseShow', '  window.openPosterMeetingInAgenda=function(){', '')
replace('<div class="poster-quick-meeting-note-v393" id="clubPosterMeetingSource">Meeting details are loaded from Agenda or club schedules.</div>',
 '<div class="poster-quick-meeting-note-v393" id="clubPosterMeetingSource">Meeting details are loaded from Agenda or club schedules.</div>'
 '<button id="hdgResumePoster" class="btn ghost compact" type="button" onclick="resumeMemberPosterDraft()" hidden>Resume last poster</button>')
replace("    window.renderPosterGenerator=function(){const result=basePosterRender.apply(this,arguments);refreshLinkUI();return result;};",
 """    window.renderPosterGenerator=function(){
      const result=basePosterRender.apply(this,arguments);
      const resume=$('hdgResumePoster');
      if(resume)resume.hidden=!db.ui?.memberPosterDraft?.clubId||!!posterState().clubId;
      refreshLinkUI();
      return result;
    };""")
replace('  window.openPosterMeetingInAgenda=function(){',
 """  window.resumeMemberPosterDraft=function(){
    const saved=db.ui?.memberPosterDraft;
    if(!saved||!clubById(saved.clubId))return;
    db.ui.clubPosterGenerator=structuredClone(saved);
    persist();
    window.renderPosterGenerator(true);
  };
  window.openPosterMeetingInAgenda=function(){""")
# Preserve the published club handle and channels while removing historical
# personal contacts and meeting access details from the Member bundle.
segment(" /* seed: the club's own published agendas", ' function clubContacts(num)', '')
replace(" function clubContacts(num){const S=STORE();return S[normalized(num)]||S[num]||null;}",
 """ function clubContacts(num){
  const S=STORE(), key=normalized(num);
  const local=S[key]||S[num];
  const shared=window.HDG_MEMBER_V632_DATA.clubAgendaDefaults.get(key.replace(/^0+/,''));
  return shared?{zoomId:shared.zoomId,zoomPass:shared.zoomPass,...local}:local||null;
 }""")
replace(" function personContacts(num,name){const c=clubContacts(num);if(!c||!c.people)return null;const k=nk(name);if(!k)return null;if(c.people[k])return c.people[k];",
 """ function personContacts(num,name){
  const key=normalized(num), k=nk(name);
  if(!k)return null;
  const shared=window.HDG_MEMBER_V632_DATA.clubAgendaDefaults.get(key.replace(/^0+/,''));
  const stored=shared?.people.get(k);
  const people=clubContacts(num)?.people||{};
  if(stored)return {...stored,...people[k]};
  if(people[k])return people[k];
  const c={people};""")
replace('Saved per club and matched to officers by name, so contacts carry over between meetings and terms.',
 'Shared defaults carry over to future agendas. Edits here are saved in this browser.')

replace("  const net=(cc.networks&&cc.networks.length?cc.networks:['instagram']).filter(k=>SVG[k]);\n  const social=agendaPrintValue(cc.social||profile.instagram||'');",
 """  const isSurabaya=normalized(record.clubNumber).replace(/^0+/,'')==='692744';
  const defaultChannels=isSurabaya?['instagram','tiktok','youtube']:['instagram'];
  const net=(cc.networks&&cc.networks.length?cc.networks:defaultChannels).filter(k=>SVG[k]);
  const defaultSocial=isSurabaya?'@surabaya_toastmasters':'';
  const social=agendaPrintValue(cc.social||profile.instagram||defaultSocial);""")
segment('function agendaCurrentOfficers(clubNumber){', 'function agendaNextMeetingDateForClub',
 """function agendaCurrentOfficers(clubNumber){
  const rows=window.HDG_MEMBER_V632_DATA.clubOfficers.get(String(clubNumber||'').trim().replace(/^0+/,''));
  const name=role=>rows?.get('Club '+role)?.name||'';
  return {president:name('President'),vpEducation:name('VP Education'),vpMembership:name('VP Membership'),
    saa:name('Sergeant at Arms'),secretary:name('Secretary'),vpPr:name('VP PR'),treasurer:name('Treasurer')};
}
""")
replace("    venue:p.locationTitle||p.publicLocation||[club.city,club.island].filter(Boolean).join(' · '),",
 "    venue:p.publicLocation||p.locationTitle||[club.city,club.island].filter(Boolean).join(' · '),")
replace("function agendaRefreshRecordClubData(record,club){",
 """function agendaDefaultAttendance(record,club){
  if(!club)return '';
  const series=window.meetingSeriesOfClubV500?.(club).find(item=>item.key===record.meetingSeriesV500);
  const profile=publicClubProfile(club);
  const mode=series?.mode||clubRecurringSeries(club).find(item=>item.primary)?.meetingMode||
    profile.meetingMode||club.mode||'In-person';
  return {'ONLINE':'Online','HYBRID':'Hybrid','IN PERSON':'In-person'}[calendarModeShort(mode)]||'';
}
function agendaRefreshRecordClubData(record,club){""")
segment("function agendaRefreshRecordClubData(record,club){", "function agendaCreateDraftForClub(club){",
 source[source.index("function agendaRefreshRecordClubData(record,club){"):source.index("function agendaCreateDraftForClub(club){")].replace(
  "  record.venue=record.venue||defaults.venue;",
  "  const formerVenueDefault=[club.city,club.island].filter(Boolean).join(' · ');\n  if(!record.venue||record.venue===formerVenueDefault)record.venue=defaults.venue;").replace(
  "  record.clubName=club.name;",
  "  record.clubName=club.name;\n  record.mode=record.attendanceOverride||agendaDefaultAttendance(record,club);"))
replace('<div class="field agenda-core-venue"><label>Venue</label><input id="agendaEditVenue"></div>',
 '<div class="field agenda-core-venue"><label>Venue</label><input id="agendaEditVenue"></div>\n'
 '<div class="field"><label for="agendaEditMeetingMode">Attendance</label><select class="app-standard-select" id="agendaEditMeetingMode">'
 '<option value="">Use club default</option><option>Hybrid</option><option>Online</option><option>In-person</option></select></div>')
replace("    const [date,template,theme,wod,venue]=fields;", "    const [date,template,theme,wod,venue,attendance]=fields;")
replace("    secondaryGrid.append(template,venue);", "    secondaryGrid.append(template,venue,attendance);")
replace("  set('agendaEditVenue',record.venue);",
 "  set('agendaEditVenue',record.venue);\n  set('agendaEditMeetingMode',record.attendanceOverride||'');\n  const attendanceDefault=$('agendaEditMeetingMode')?.options[0];\n  if(attendanceDefault){const effective=agendaDefaultAttendance(record,(db.clubs||[]).find(c=>c.number===record.clubNumber));attendanceDefault.textContent=effective?'Club default · '+effective:'Use club default';}")
# The screen backdrop belongs to the app chrome. The A4 style is club-owned.
replace('.agenda-a4-stage{display:flex;justify-content:center;overflow:auto;padding:14px;border:1px solid #2C609C;border-radius:13px;background:#062E5D}',
 """ .agenda-a4-stage{display:flex;justify-content:center;overflow:auto;padding:14px;border:1px solid #2C609C;border-radius:13px;background:#062E5D}
@media screen {
 html.theme-ti #agendaGeneratedView{background:#004165;border-color:rgba(169,178,177,.48)}
 html.theme-maroon #agendaGeneratedView{background:#772432;border-color:rgba(169,178,177,.48)}
}""")
replace("  record.venue=get('agendaEditVenue');",
 "  record.venue=get('agendaEditVenue');\n  if($('agendaEditMeetingMode'))record.attendanceOverride=get('agendaEditMeetingMode');\n  record.mode=record.attendanceOverride||agendaDefaultAttendance(record,club);")
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
projected={}
for number, row in discovery.items():
 profile={name:value for name,value in row.items() if name in allowed}
 provenance=row.get('source','')
 if provenance in ('Toastmasters Find a Club','Division G local directory') or re.fullmatch(r'Division G club schedule update · [0-9-]+',provenance):
  profile['source']=provenance
 url=urlsplit(row.get('officialUrl',''))
 match=re.fullmatch(r'(/find-a-club/([0-9]+)(?:-[a-z0-9-]*)?)/?(?:contact-club/?|)$',url.path,re.I)
 if url.scheme=='https' and url.netloc.lower()=='www.toastmasters.org' and match and int(match[2])==int(number):
  profile['officialUrl']=urlunsplit(('https','www.toastmasters.org',match[1],'',''))
 projected[number]=profile
source=source[:m.start(2)]+json.dumps(projected,ensure_ascii=False,separators=(',',':'))+source[m.end(2):]

# Earlier Member builds cached public details without their provenance. Restore
# the metadata for matching schedules, without relabeling a changed schedule.
replace("  window.district87ProfileMap=function(){ensureOperationalDataV315(db);return db.database?.district87Profiles||{};};", """  const directorySourcesRepaired = new WeakSet();
  window.district87ProfileMap=function(){
    ensureOperationalDataV315(db);
    const profiles=db.database.district87Profiles;
    if(!directorySourcesRepaired.has(profiles)){
      for(const [number,profile] of Object.entries(profiles)){
        const seed=DISTRICT87_DISCOVERY_DETAILS[number];
        if(!seed||!profile||typeof profile!=='object')continue;
        if(!profile.source&&seed.source&&profile.meetingSchedule===seed.meetingSchedule)profile.source=seed.source;
        if(!profile.officialUrl&&seed.officialUrl)profile.officialUrl=seed.officialUrl;
      }
      directorySourcesRepaired.add(profiles);
    }
    return profiles;
  };""")
replace("  const sourceLabel=official?'Official profile':d?'Division G local':'Not yet enriched';",
 "  const sourceLabel=official?'Official profile':d?.source?.startsWith('Division G')&&c.division==='G'?'Division G local':d?'Source unverified':'Not yet enriched';")


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
  if(db.ui?.clubPosterGenerator?.clubId){
    db.ui.memberPosterDraft=db.ui.clubPosterGenerator;
    db.ui.clubPosterGenerator={ratio:'4:5'};
  }
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
