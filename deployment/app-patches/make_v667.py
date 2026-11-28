#!/usr/bin/env python3
"""Build a private v667 Leader desktop preview from the connected v666 HTML."""
import argparse
from hashlib import sha256
from pathlib import Path

TITLE = '<title>Hello Division G! v666</title>'
MARKER = '        <div id="tiSyncImportPanel" class="ti-sync-import-panel">'
BRIDGE = 'cloud.accountId=()=>session&&session.user&&session.user.id||\'\';'
BRIDGE_METHOD = '''
cloud.leaderClubFigures=(year,division)=>request('/rest/v1/rpc/hdg_leader_club_figures',{
 p_year:year,p_division:division,p_area:null
});'''
PANEL = '''
        <div id="tiStoredFigures" class="help-box" style="margin-top:12px">
          <div class="section-title" style="margin-top:0">
            <h3>Official club figures in Supabase</h3>
            <button class="btn ghost" type="button" id="tiStoredFiguresRefresh">Refresh figures</button>
          </div>
          <p id="tiStoredFiguresStatus" role="status">Refresh to see the latest stored figures for your division.</p>
          <div class="database-explorer-table" id="tiStoredFiguresData" hidden>
            <table><thead><tr><th scope="col">Club number</th><th scope="col">Snapshot date</th>
              <th scope="col">Members</th><th scope="col">DCP goals</th><th scope="col">Club Success Plan</th>
            </tr></thead><tbody id="tiStoredFiguresBody"></tbody></table>
          </div>
        </div>
'''
SCRIPT = '''<script id="hdg-v667-stored-figures">
(() => {
 const refresh=document.getElementById('tiStoredFiguresRefresh');
 const status=document.getElementById('tiStoredFiguresStatus');
 const data=document.getElementById('tiStoredFiguresData');
 const body=document.getElementById('tiStoredFiguresBody');
 if(!refresh||!status||!data||!body)return;
 const presenter=new Intl.DateTimeFormat('en-GB',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Makassar'});
 refresh.addEventListener('click',async()=>{
  data.hidden=true;
  body.replaceChildren();
  const cloud=window.HDGCloud;
  if(!cloud?.accountId?.()||!cloud.leaderClubFigures){
   status.textContent='Sign in to the connected Leader app to load official figures.';
   return;
  }
  const division=String(db.settings?.divisionCode||'G').toUpperCase();
  const stamp=new Intl.DateTimeFormat('en-CA',{year:'numeric',month:'2-digit',timeZone:'Asia/Makassar'})
   .formatToParts(new Date());
  const year=Number(stamp.find(p=>p.type==='year').value)-(Number(stamp.find(p=>p.type==='month').value)<7);
  status.textContent='Loading official club figures…';
  refresh.disabled=true;
  try{
   const snapshots=await cloud.leaderClubFigures(year,division);
   const latest=new Map();
   for(const row of snapshots){
    if(!latest.has(row.club_number)||row.as_of>latest.get(row.club_number).as_of)latest.set(row.club_number,row);
   }
   const rows=[...latest.values()].sort((a,b)=>String(a.club_number).localeCompare(String(b.club_number),'en',{numeric:true}));
   for(const row of rows){
    const tr=document.createElement('tr');
    for(const value of [row.club_number,row.as_of,row.membership_to_date,row.dcp_goals_met,row.club_success_plan]){
     const cell=document.createElement('td');
     cell.textContent=value===null||value===undefined||value===''?'—':String(value);
     tr.append(cell);
    }
    body.append(tr);
   }
   data.hidden=!rows.length;
   const lastImport=Math.max(...rows.map(row=>Date.parse(row.imported_at)).filter(Number.isFinite));
   status.textContent=rows.length
    ? `${rows.length} clubs in your scope`+(Number.isFinite(lastImport)?` · latest import ${presenter.format(lastImport)} WITA`:'')
    : 'No official figures are stored for your scope this program year.';
  }catch{
   status.textContent='Could not load the stored figures. Try again when connected.';
  }finally{
   refresh.disabled=false;
  }
 });
})();
</script>'''


def build(source):
    for anchor in (TITLE, MARKER, BRIDGE):
        if source.count(anchor) != 1:
            raise ValueError('Unexpected connected v666 structure')
    if source.lower().count('</body>') == 0:
        raise ValueError('Missing document body closing tag')
    source = source.replace(TITLE, TITLE.replace('v666', 'v667 Preview'))
    source = source.replace(MARKER, PANEL + MARKER)
    source = source.replace(BRIDGE, BRIDGE + BRIDGE_METHOD)
    end = source.lower().rfind('</body>')
    return source[:end] + SCRIPT + '\n' + source[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('source_sha256')
    args = parser.parse_args()
    content = args.source.read_bytes()
    if sha256(content).hexdigest() != args.source_sha256:
        raise SystemExit('Unexpected v666 source hash')
    preview = build(content.decode('utf-8')).encode('utf-8')
    with args.output.open('xb') as output:
        output.write(preview)
    print(f'Private v667 preview built. SHA-256 {sha256(preview).hexdigest()}')


if __name__ == '__main__':
    main()
