(function(){
'use strict';
/* Club Exco (schema 017, owner decisions 25 November 2026): every current officer of a club can change that
   club's Exco seats. A change applies at once (no Area Director confirmation): the new officer gets the club's
   officer access straight away and the previous one loses it. A Toastmasters officer list replaces a club's
   change only if the list is dated after it. Shown as a Community tab to people who are officers somewhere. */
if(window.__hdgClubExco)return;window.__hdgClubExco=true;
const SEAT={club_president:'President',club_vpe:'VP Education',club_vpm:'VP Membership',club_vppr:'VP Public Relations',
 club_secretary:'Secretary',club_treasurer:'Treasurer',club_saa:'Sergeant at Arms'};
const SOURCE={import:'Toastmasters officer list',club:'Changed by the club',leader:'Changed by a leader',legacy:'Earlier officer list'};
const H=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const day=v=>{if(!v)return '';const d=new Date(String(v).length===10?v+'T00:00:00':v);return isNaN(d)?String(v):d.toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'numeric'});};
const st={clubs:[],club:'',data:null,editing:'',busy:false,msg:''};
const cloud=()=>window.HDGCloud;

function body(){return document.getElementById('hdgExcoBody');}
function toast(t){if(typeof window.showDataSafetyNotice==='function'){try{window.showDataSafetyNotice(t,'good');return;}catch(_){}}}

function addTab(){
 const tabs=document.querySelector('#community .community-tabs');
 if(!tabs||document.querySelector('[data-community-panel="clubExco"]'))return;
 const b=document.createElement('button');b.type='button';b.dataset.communityPanel='clubExco';b.textContent='Club Exco';
 b.addEventListener('click',()=>window.showCommunityPanel('clubExco'));tabs.appendChild(b);
 const panels=[...document.querySelectorAll('#community .community-panel')];
 const panel=document.createElement('div');panel.className='community-panel';panel.id='communityPanelClubExco';
 panel.innerHTML='<div class="community-panel-head"><div><h2>Club Exco</h2><div class="small">Your club\'s officers. Any officer can change a seat; it applies at once.</div></div></div><div id="hdgExcoBody" class="hdg-exco"></div>';
 (panels[panels.length-1]||tabs).after(panel);
 const nav=document.querySelector('.member-community-nav');
 if(nav&&!nav.querySelector('[data-member-community-panel="clubExco"]')){
  const l=document.createElement('button');l.type='button';l.className='member-community-link';l.dataset.memberCommunityPanel='clubExco';l.setAttribute('aria-current','false');
  l.innerHTML='<span class="member-community-icon" aria-hidden="true">✎</span><span><strong>Club Exco</strong><small>Change your club\'s officers</small></span>';
  l.addEventListener('click',()=>typeof window.openMemberCommunityPanel==='function'?window.openMemberCommunityPanel('clubExco'):window.showCommunityPanel('clubExco'));
  nav.appendChild(l);
 }
 const show=window.showCommunityPanel;
 if(typeof show==='function'&&!show.__exco){
  const wrapped=function(p){const r=show.apply(this,arguments);if(p==='clubExco')load();return r;};
  wrapped.__exco=true;window.showCommunityPanel=wrapped;
 }
}

async function load(){
 const el=body();if(!el)return;
 if(!st.club)st.club=st.clubs[0]?.club||'';
 el.innerHTML='<div class="hdg-exco-note">Loading…</div>';
 try{st.data=await cloud().clubExco(st.club);st.editing='';st.msg='';render();}
 catch(e){el.innerHTML=`<div class="hdg-exco-note bad">Could not load the Exco: ${H(e&&e.message||e)}</div>`;}
}

function render(){
 const el=body(),d=st.data;if(!el||!d)return;
 const picker=st.clubs.length>1?`<label class="hdg-exco-club"><span>Club</span><select id="hdgExcoClub">${st.clubs.map(c=>`<option value="${H(c.club)}"${c.club===st.club?' selected':''}>${H(c.name)}</option>`).join('')}</select></label>`:'';
 const name=(st.clubs.find(c=>c.club===st.club)||{}).name||('Club '+st.club);
 const rows=(d.seats||[]).map(s=>{
  const who=s.person?`<b>${H(s.name)}</b>${s.memberId?` <small>#${H(String(s.memberId).replace(/^0+/,''))}</small>`:''}${s.mine?' <em class="hdg-exco-you">You</em>':''}`:'<span class="hdg-exco-empty">Empty</span>';
  const src=s.person?`${H(SOURCE[s.source]||'')}${s.changedAt&&s.source!=='legacy'?` · ${H(day(s.changedAt))}`:''}`:'';
  const btn=d.canEdit?`<button type="button" class="btn ghost hdg-exco-change" data-seat="${H(s.role)}">${st.editing===s.role?'Close':'Change'}</button>`:'';
  const row=`<tr class="${st.editing===s.role?'is-editing':''}"><td class="hdg-exco-seat">${H(SEAT[s.role]||s.role)}</td><td>${who}</td><td class="hdg-exco-since">${s.person?H(day(s.since)):''}</td><td class="hdg-exco-src">${src}</td><td class="hdg-exco-act">${btn}</td></tr>`;
  return row+(st.editing===s.role?editorRow(s):'');
 }).join('');
 el.innerHTML=`<div class="hdg-exco-card">
  <div class="hdg-exco-top"><div><div class="hdg-exco-kicker">Exco</div><h3>${H(name)}</h3>${d.officersAsOf?`<div class="hdg-exco-sub">Last Toastmasters officer list: ${H(day(d.officersAsOf))}</div>`:''}</div>${picker}</div>
  <div class="hdg-exco-wrap"><table class="hdg-exco-table"><thead><tr><th>Seat</th><th>Officer</th><th>Since</th><th>Set by</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>
  <p class="hdg-exco-foot">${d.canEdit?'Changes apply at once: the new officer gets this club\'s officer access straight away and the previous one loses it. A Toastmasters officer list dated after your change replaces it.':'Only this club\'s current officers can change its Exco.'}</p>
 </div>`;
}

function editorRow(s){
 const d=st.data,cands=d.candidates||[];
 const opts=['<option value="">Leave this seat empty</option>'].concat(cands.map(c=>`<option value="${H(c.person)}"${c.person===s.person?' selected':''}>${H(c.name)}${c.memberId?' · #'+H(String(c.memberId).replace(/^0+/,'')):''}</option>`)).join('');
 const selfWarn=s.mine?'<p class="hdg-exco-warn">This is your seat. If you give it to someone else and hold no other seat in this club, you lose the club\'s officer access at once.</p>':'';
 return `<tr class="hdg-exco-edit"><td colspan="5"><div class="hdg-exco-editor">
  <label><span>New ${H(SEAT[s.role]||s.role)}</span><select id="hdgExcoPick">${opts}</select></label>
  <p class="hdg-exco-hint">Only active members of this club are listed. Someone who joined recently appears after the next membership import.</p>
  ${selfWarn}
  <div class="hdg-exco-actions"><span class="hdg-exco-msg" role="status">${H(st.msg)}</span><button type="button" class="btn ghost" data-exco="cancel">Cancel</button><button type="button" class="btn primary" data-exco="save" data-seat="${H(s.role)}"${st.busy?' disabled':''}>${st.busy?'Saving…':'Save'}</button></div>
 </div></td></tr>`;
}

async function save(role){
 const seat=(st.data.seats||[]).find(s=>s.role===role);const pick=document.getElementById('hdgExcoPick');if(!seat||!pick)return;
 const person=pick.value||null;
 if((person||null)===(seat.person||null)){st.editing='';render();return;}
 if(seat.mine&&!confirm('Give your own seat away? You may lose this club\'s officer access at once.'))return;
 st.busy=true;st.msg='';render();
 try{
  st.data=await cloud().setClubOfficer(st.club,role,person);
  st.editing='';st.busy=false;render();
  const now=(st.data.seats||[]).find(s=>s.role===role);
  toast(`${SEAT[role]}: ${now&&now.person?now.name:'left empty'}`);
  if(!st.data.canEdit){st.clubs=await cloud().myExcoClubs().catch(()=>st.clubs);}
 }catch(e){st.busy=false;st.msg=String(e&&e.message||e);render();}
}

document.addEventListener('click',e=>{
 const panel=e.target.closest&&e.target.closest('#communityPanelClubExco');if(!panel)return;
 const ch=e.target.closest('.hdg-exco-change');if(ch){st.editing=st.editing===ch.dataset.seat?'':ch.dataset.seat;st.msg='';render();return;}
 const act=e.target.closest('[data-exco]');if(!act)return;
 if(act.dataset.exco==='cancel'){st.editing='';st.msg='';render();}
 else if(act.dataset.exco==='save')save(act.dataset.seat);
});
document.addEventListener('change',e=>{if(e.target&&e.target.id==='hdgExcoClub'){st.club=e.target.value;load();}});

async function boot(tries=0){
 const c=cloud();
 if(!c||typeof c.myExcoClubs!=='function'||typeof c.accountId!=='function'||!c.accountId()){if(tries<40)setTimeout(()=>boot(tries+1),1500);return;}
 try{st.clubs=await c.myExcoClubs();}catch(_){return;}
 if(Array.isArray(st.clubs)&&st.clubs.length)addTab();
}
/* ---------- Leader app: keep the Officer / Exco directory in step with what clubs set, and send officer list
   imports through the newer-wins rule. ---------- */
const LABEL={club_president:'Club President',club_vpe:'Club VP Education',club_vpm:'Club VP Membership',club_vppr:'Club VP PR',
 club_secretary:'Club Secretary',club_treasurer:'Club Treasurer',club_saa:'Club Sergeant at Arms'};
const nk=v=>String(v||'').toLowerCase().replace(/[^a-z0-9]/g,'');
const cn=v=>String(v||'').replace(/\D/g,'').replace(/^0+/,'');
function seatOf(role){const r=nk(role);
 if(/sergeant|^saa$|clubsaa/.test(r))return 'club_saa';if(/treasurer/.test(r))return 'club_treasurer';if(/secretary/.test(r))return 'club_secretary';
 if(/publicrelation|vppr|clubvppr/.test(r))return 'club_vppr';if(/membership|vpm/.test(r))return 'club_vpm';if(/education|vpe/.test(r))return 'club_vpe';
 if(/president/.test(r))return 'club_president';return '';}
const isLeaderApp=()=>typeof window.applyOfficerImport==='function'&&!!document.getElementById('officers')&&typeof db!=='undefined';
const today=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;};
/* Put one club's Exco (from the database) into the directory. Only seats set by the club or a leader, and seats a
   club change left empty, are applied; seats from officer lists are already in the directory. */
function reconcile(clubNumber,ex,vacated){
 const club=(db.clubs||[]).find(c=>cn(c.number)===cn(clubNumber));if(!club||!ex)return 0;
 let changed=0;const recs=db.officerRecords=db.officerRecords||[];
 const sameClub=o=>cn(o.clubNumber)===cn(club.number);
 const samePerson=(o,s)=>(s.memberId&&o.memberId&&cn(o.memberId)===cn(s.memberId))||nk(o.name)===nk(s.name);
 for(const s of ex.seats||[]){
  const holders=recs.filter(o=>!o.past&&sameClub(o)&&seatOf(o.role)===s.role);
  if(s.person&&(s.source==='club'||s.source==='leader')){
   if(holders.some(o=>samePerson(o,s)))continue;
   holders.forEach(o=>{o.past=true;o.pastOn=today();changed++;});
   const prior=recs.find(o=>sameClub(o)&&samePerson(o,s));
   const rec={id:`off-${club.number}-${s.memberId||nk(s.name)}-${s.role}`,name:s.name,role:LABEL[s.role],clubNumber:club.number,clubName:club.name,area:club.area,
    memberId:s.memberId||'',term:'',contact:prior?.contact||'',tli1:prior?prior.tli1??null:null,tli2:prior?prior.tli2??null:null,setBy:s.source,setAt:s.changedAt};
   if(typeof officerKey==='function')rec.key=officerKey(rec);
   const dup=recs.find(o=>o.id===rec.id);if(dup)Object.assign(dup,rec,{past:false,pastOn:undefined});else recs.push(rec);changed++;
  }else if(!s.person&&vacated&&vacated.has(s.role)){holders.forEach(o=>{o.past=true;o.pastOn=today();changed++;});}
 }
 return changed;
}
let mirroring=false;
async function mirror(){
 if(mirroring||!isLeaderApp())return;mirroring=true;
 try{
  db.database=db.database||{};
  const since=db.database.excoMirrorAt||null;
  const changes=await cloud().excoChanges(since);
  if(!Array.isArray(changes)||!changes.length)return;
  const byClub=new Map();
  for(const c of changes){if(!byClub.has(c.club))byClub.set(c.club,new Set());if(!c.active)byClub.get(c.club).add(c.role);}
  let n=0;
  for(const [club,ended] of byClub){const ex=await cloud().clubExco(club).catch(()=>null);n+=reconcile(club,ex,ended);}
  db.database.excoMirrorAt=changes.map(c=>c.changedAt).filter(Boolean).sort().pop()||since;
  try{updateOfficerCounts();}catch(_){}
  saveData();try{render();}catch(_){}
  if(n)toast(`Officer / Exco updated with ${n===1?'a change':'changes'} made by clubs.`);
 }catch(_){}finally{mirroring=false;}
}
function wrapImport(){
 const base=window.applyOfficerImport;if(typeof base!=='function'||base.__exco)return;
 const wrapped=function(){
  const before=(db.officerImports||[])[0];
  const r=base.apply(this,arguments);
  const imp=(db.officerImports||[])[0];
  if(imp&&imp!==before)sendImport(imp.date).catch(()=>{});
  return r;
 };
 wrapped.__exco=true;window.applyOfficerImport=wrapped;
}
async function sendImport(date){
 if(!date||date>today())return;
 const clubs=new Map();
 for(const o of db.officerRecords||[]){if(o.past)continue;const seat=seatOf(o.role);if(!seat)continue;const k=cn(o.clubNumber);if(!clubs.has(k))clubs.set(k,[]);clubs.get(k).push({role:seat,memberId:o.memberId||''});}
 const kept=[],unmatched=[];let n=0;
 for(const [club,seats] of clubs){
  try{const res=await cloud().importClubOfficers(club,date,seats);
   const name=((db.clubs||[]).find(c=>cn(c.number)===club)||{}).name||club;
   (res.kept||[]).forEach(k=>kept.push(`${name}: ${SEAT[k.role]||k.role}`));(res.unmatched||[]).forEach(u=>unmatched.push(`${name}: ${SEAT[u.role]||u.role}`));
   if((res.kept||[]).length){const ex=await cloud().clubExco(club).catch(()=>null);n+=reconcile(club,ex,null);}
  }catch(_){}
 }
 db.database=db.database||{};const had=db.database.excoUnmatched||0;db.database.excoUnmatched=unmatched.length;
 if(n||had!==unmatched.length){try{updateOfficerCounts();}catch(_){}saveData();try{render();}catch(_){}}
 const parts=[];
 if(kept.length)parts.push(`Kept ${kept.length} newer club change${kept.length===1?'':'s'} (${kept.join(', ')}).`);
 if(unmatched.length)parts.push(`${unmatched.length} officer${unmatched.length===1?' is':'s are'} not in the member list yet, so ${unmatched.length===1?'their':'their'} officer access waits for the next membership import (${unmatched.join(', ')}).`);
 if(parts.length&&typeof window.showDataSafetyNotice==='function')window.showDataSafetyNotice(parts.join(' '),kept.length?'warn':'good');
}
/* After a member list import: officers who were not in the member list yet get their seat now (same newer-wins rule). */
window.hdgExcoResend=function(){
 const imp=(db.officerImports||[])[0];
 if(!imp||!(db.database&&db.database.excoUnmatched))return Promise.resolve();
 return sendImport(imp.date).catch(()=>{});
};
/* A leader adds or changes an officer in the directory: give the seat's access too when the person is in the
   club's member list. */
window.hdgExcoLeaderSaved=async function(rec){
 try{
  const seat=seatOf(rec&&rec.role);if(!seat||!cloud()||!cloud().clubExco)return '';
  const ex=await cloud().clubExco(rec.clubNumber);if(!ex||!ex.canEdit)return '';
  const cur=(ex.seats||[]).find(s=>s.role===seat);
  const c=(ex.candidates||[]).filter(x=>(rec.memberId&&x.memberId&&cn(x.memberId)===cn(rec.memberId))||nk(x.name)===nk(rec.name));
  if(c.length!==1)return `${rec.name} is not in the club's member list, so their officer access follows the next import.`;
  if(cur&&cur.person===c[0].person)return '';
  await cloud().setClubOfficer(rec.clubNumber,seat,c[0].person);
  return `${rec.name} now has ${SEAT[seat]} access for the club.`;
 }catch(e){return '';}
};
function bootLeader(tries=0){
 if(!isLeaderApp())return;
 const c=cloud();if(!c||typeof c.excoChanges!=='function'||!c.accountId||!c.accountId()){if(tries<40)setTimeout(()=>bootLeader(tries+1),1500);return;}
 wrapImport();
 setTimeout(mirror,4000);setInterval(mirror,5*60*1000);
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')mirror();});
}

const css=document.createElement('style');css.id='hdg-club-exco-style';css.textContent=`
.hdg-exco-card{border:1px solid var(--v6-line,rgba(255,255,255,.2));border-radius:18px;background:var(--v6-card,#083f79);padding:18px;color:#fff}
.hdg-exco-top{display:flex;flex-wrap:wrap;align-items:flex-end;justify-content:space-between;gap:12px;margin-bottom:12px}
.hdg-exco-kicker{font-size:12px;font-weight:800;letter-spacing:.07em;text-transform:uppercase;color:var(--v6-acc,#f2b94b)}
.hdg-exco-top h3{margin:2px 0;font-size:20px;font-weight:800}
.hdg-exco-sub,.hdg-exco-foot,.hdg-exco-hint{font-size:13.5px;color:var(--v6-mut,#b7c6da);line-height:1.45}
.hdg-exco-club{display:flex;align-items:center;gap:8px;font-size:13px;font-weight:700;color:var(--v6-mut,#b7c6da)}
.hdg-exco-club select,.hdg-exco-editor select{min-height:44px;padding:8px 12px;border-radius:12px;border:1px solid var(--v6-line,rgba(255,255,255,.25));background:var(--v6-in,#06386f);color:#fff;font:inherit;font-size:16px}
.hdg-exco-wrap{overflow-x:auto}
.hdg-exco-table{width:100%;border-collapse:collapse}
.hdg-exco-table th{text-align:left;font-size:12px;font-weight:800;letter-spacing:.05em;text-transform:uppercase;color:var(--v6-mut,#b7c6da);padding:8px 10px;border-bottom:1px solid var(--v6-line,rgba(255,255,255,.2))}
.hdg-exco-table td{padding:10px;border-bottom:1px solid var(--v6-line,rgba(255,255,255,.12));font-size:14.5px;vertical-align:middle}
.hdg-exco-table tr.is-editing>td{background:rgba(242,185,75,.08)}
.hdg-exco-seat{font-weight:700;white-space:nowrap}
.hdg-exco-table small,.hdg-exco-since,.hdg-exco-src{color:var(--v6-mut,#b7c6da);font-size:13px}
.hdg-exco-you{font-style:normal;font-size:11.5px;font-weight:800;padding:2px 8px;border-radius:99px;background:rgba(79,204,151,.2);color:#c9f5df;margin-left:4px}
.hdg-exco-empty{color:var(--v6-mut,#b7c6da);font-style:italic}
.hdg-exco-act{text-align:right}
.hdg-exco-act .btn{min-height:38px;padding:0 16px;opacity:1!important}
.hdg-exco-edit>td{padding:0 6px 12px!important;border-bottom:0!important}
.hdg-exco-editor{border:1px solid var(--v6-acc,#f2b94b);border-radius:14px;background:var(--v6-deep,#052f62);padding:14px 16px;display:grid;gap:8px}
.hdg-exco-editor label{display:grid;gap:6px;font-size:13.5px;font-weight:700;color:var(--v6-mut,#b7c6da)}
.hdg-exco-editor p{margin:0}
.hdg-exco-warn{font-size:13.5px;color:#ffc9c9}
.hdg-exco-actions{display:flex;align-items:center;gap:10px;justify-content:flex-end;flex-wrap:wrap}
.hdg-exco-actions .btn{min-height:42px;padding:0 18px;opacity:1!important}
.hdg-exco-msg{flex:1;font-size:13.5px;font-weight:600;color:#ffb3b3}
.hdg-exco-note{padding:16px;border:1px dashed var(--v6-line,rgba(255,255,255,.25));border-radius:14px;color:var(--v6-mut,#b7c6da)}
.hdg-exco-note.bad{color:#ffc9c9}
@media(max-width:640px){.hdg-exco-table thead{display:none}.hdg-exco-table tr:not(.hdg-exco-edit){display:grid;grid-template-columns:1fr auto;gap:2px 10px;padding:8px 0;border-bottom:1px solid var(--v6-line,rgba(255,255,255,.12))}.hdg-exco-table td{border:0;padding:2px 4px}.hdg-exco-seat{grid-column:1}.hdg-exco-act{grid-column:2;grid-row:1/span 3;align-self:center}.hdg-exco-table tr.hdg-exco-edit,.hdg-exco-table tr.hdg-exco-edit>td{display:block}}
`;
document.head.appendChild(css);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{boot();bootLeader();},{once:true});else{boot();bootLeader();}
})();
