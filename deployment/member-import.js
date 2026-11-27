/* Hello Division G: the Toastmasters member list goes into the member database (schema 018).
   Leader app only. "Sync Membership" works as before on the app's member list; afterwards each club's rows are sent
   to hdg_import_club_members, which decides by member ID, keeps hand-corrected fields (and asks), lets the newest
   list win per club, and can be undone. Only member ID, name, email, city, status and dates leave the browser
   (project/DISTRICT_PLAN.md rule 1: never a street address or phone number). */
(function(){
'use strict';
const cloud=()=>window.HDGCloud;
const $id=id=>document.getElementById(id);
const esc=v=>String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const cn=v=>String(v||'').replace(/\D/g,'').replace(/^0+/,'');
const pad=n=>String(n).padStart(2,'0');
const ymd=d=>`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
const today=()=>ymd(new Date());
const FIELD={name:'Name',email:'Email',city:'City'};
const isLeaderApp=()=>typeof window.applyMembershipImport==='function'&&typeof db!=='undefined'&&!!$id('membershipFile');

function toDate(v,monthEnd){
 if(v===null||v===undefined||v==='')return '';
 let d=null;
 try{d=typeof parseRenewThrough==='function'?parseRenewThrough(v):new Date(v);}catch(_){d=null;}
 if(!(d instanceof Date)||isNaN(d))return '';
 /* "Mar 2027" means paid through the end of March. */
 if(monthEnd&&typeof v==='string'&&!/\d{1,2}[\/\-.\s]\d{1,2}[\/\-.\s]\d{2,4}|\d{4}-\d{2}-\d{2}/.test(v))d=new Date(d.getFullYear(),d.getMonth()+1,0);
 return ymd(d);
}
/* 019: every club in the district, with whether this leader may import it (scope, and the division's imports open). */
let DIST=null;
async function loadDistrict(){try{const l=await cloud().importClubs();if(Array.isArray(l))DIST=l;}catch(_){}}
const nn=v=>String(v||'').toLowerCase().replace(/[^a-z0-9]/g,'');
function districtClub(num,name){
 if(!DIST)return null;
 const k=cn(num);if(k){const c=DIST.find(x=>x.club===k);if(c)return c;}
 const n=nn(name);return n?DIST.find(x=>nn(x.name)===n)||null:null;
}
function localClub(num,name){try{return findClubForImport(num||'',name||'');}catch(_){return null;}}
/* Rows for clubs the app's own lists do not have (other divisions) go to the member database only. */
function split(rows,numCol,nameCol){
 const local=[],other=[];
 for(const r of rows){const a=numCol?r[numCol]:'',b=nameCol?r[nameCol]:'';
  if(localClub(a,b)||!districtClub(a,b))local.push(r);else other.push(r);}
 return {local,other};
}
function header(headers,test){return (headers||[]).find(h=>test(String(h)))||'';}

/* Read the file the app just synced, with the app's own column choices. */
function capture(){
 let rows=[],headers=[];
 try{rows=(typeof membershipRawRows!=='undefined'&&membershipRawRows)||[];}catch(_){}
 try{headers=(typeof membershipHeaders!=='undefined'&&membershipHeaders)||Object.keys(rows[0]||{});}catch(_){headers=Object.keys(rows[0]||{});}
 const v=id=>($id(id)&&$id(id).value)||'';
 return {rows:rows.slice(),headers:headers.slice(),
  map:{name:v('mapMemberName'),memberId:v('mapMemberId'),clubNumber:v('mapClubNumber'),clubName:v('mapClubName'),renewThrough:v('mapRenewThrough'),status:v('mapMemberStatus')},
  date:v('membershipImportDate')||today(),snapshot:v('membershipSyncMode')==='snapshot'};
}

function perClub(c){
 const memberIdCol=c.map.memberId||header(c.headers,h=>/^(member\s*(id|number|no)|customer\s*id)$/i.test(h.trim()));
 const emailCol=header(c.headers,h=>/^e-?mail(\s*address)?$/i.test(h.trim()));
 const cityCol=header(c.headers,h=>/city/i.test(h)&&!/club/i.test(h));
 const byClub=new Map();let noClub=0;
 for(const r of c.rows){
  const a=c.map.clubNumber?r[c.map.clubNumber]:'',b=c.map.clubName?r[c.map.clubName]:'';
  let club=localClub(a,b);
  if(!club){const d=districtClub(a,b);if(d)club={number:d.club,name:d.name,district:d};}
  if(!club||!cn(club.number)){noClub++;continue;}
  const parts=[r['First Name'],r['Middle Name'],r['Last Name']].map(x=>String(x||'').trim()).filter(Boolean).join(' ').replace(/\s+/g,' ').trim();
  let name=c.map.name?String(r[c.map.name]||'').trim():parts;
  if(parts&&String(name).toLowerCase()===String(club.name||'').toLowerCase())name=parts;
  if(!name)name=parts;
  const st=c.map.status?String(r[c.map.status]||'').trim().toLowerCase():'';
  /* Only these fields are sent. */
  const row={memberId:String(memberIdCol?r[memberIdCol]||'':'').trim(),name,active:c.map.status?(st==='yes'||st==='active'||st==='paid'):true};
  if(emailCol&&String(r[emailCol]||'').trim())row.email=String(r[emailCol]).trim();
  if(cityCol&&String(r[cityCol]||'').trim())row.city=String(r[cityCol]).trim();
  const join=toDate(r['Club Join Date'],false);if(join)row.joinedOn=join;
  const paid=c.map.renewThrough?toDate(r[c.map.renewThrough],true):'';if(paid)row.paidUntil=paid;
  const k=cn(club.number);
  if(!byClub.has(k))byClub.set(k,{club,rows:[]});
  byClub.get(k).rows.push(row);
 }
 return {byClub,noClub};
}

let last=null; /* the latest result, for the panel */
function panel(){
 let p=$id('hdgMemberDbResult');
 if(!p){
  const btn=document.querySelector('button[onclick^="applyMembershipImport"]');
  const host=btn&&btn.closest('.flex');if(!host)return null;
  p=document.createElement('div');p.id='hdgMemberDbResult';p.className='hdg-mdb';
  host.insertAdjacentElement('afterend',p);
 }
 return p;
}
function show(html){const p=panel();if(p){p.innerHTML=html;p.hidden=!html;}}

async function send(c,imp){
 if(!cloud()||typeof cloud().importClubMembers!=='function')return;
 if(c.date>today()){show(`<div class="hdg-mdb-card bad">The member database was not updated: the import date ${esc(c.date)} is in the future.</div>`);return;}
 const {byClub}=perClub(c);
 if(!byClub.size)return;
 show(`<div class="hdg-mdb-card">Saving the member list to the member database…</div>`);
 const out={date:c.date,clubs:0,newPeople:0,newMemberships:0,updated:0,left:0,skipped:0,stale:[],outside:[],closed:[],failed:[],conflicts:[],imports:[],other:new Map()};
 const nameOf=new Map();
 for(const [k,{club,rows}] of byClub){
  rows.forEach(r=>{if(r.memberId)nameOf.set(cn(r.memberId),r.name);});
  const d=club.district||(DIST&&DIST.find(x=>x.club===k));
  if(d&&!d.canImport){(d.reason==='closed'?out.closed:out.outside).push(club.name);continue;}
  try{
   const res=await cloud().importClubMembers(k,c.date,rows,c.snapshot);
   if(res&&res.stale){out.stale.push(`${club.name} (has a list dated ${res.newerAsOf})`);continue;}
   out.clubs++;out.newPeople+=res.newPeople||0;out.newMemberships+=res.newMemberships||0;
   out.updated+=(res.updatedPeople||0)+(res.updatedMemberships||0);out.left+=res.left||0;out.skipped+=res.skipped||0;
   (res.conflicts||[]).forEach(x=>out.conflicts.push({...x,club:club.name,who:nameOf.get(cn(x.memberId))||x.yours}));
   if(res.import)out.imports.push({club:k,name:club.name,id:res.import});
   if(club.district){const dv='Division '+club.district.division;out.other.set(dv,(out.other.get(dv)||0)+1);}
  }catch(e){(e&&e.status===403||e&&e.code==='42501'?(/not open/i.test(e.message||'')?out.closed:out.outside):out.failed).push(club.name);}
 }
 if(imp)imp.dbImports=out.imports;
 else{db.database=db.database||{};db.database.districtMemberImports=[{date:c.date,at:new Date().toISOString(),dbImports:out.imports},...(db.database.districtMemberImports||[])].slice(0,20);}
 try{saveData();}catch(_){}
 last=out;render();
 if(out.clubs&&typeof window.hdgExcoResend==='function')window.hdgExcoResend();
}

function render(){
 const o=last;if(!o){show('');return;}
 const s=(n,one,many)=>`${n} ${n===1?one:many}`;
 const lines=[];
 if(o.clubs){
  const moved=Math.max(0,o.newMemberships-o.newPeople);
  const bits=[o.newPeople&&s(o.newPeople,'new member','new members'),moved&&s(moved,'member added to another club','members added to another club'),
   o.updated&&s(o.updated,'update','updates'),o.left&&s(o.left,'member marked as left','members marked as left')].filter(Boolean);
  lines.push(`<strong>Member database updated</strong> for ${s(o.clubs,'club','clubs')} (list of ${esc(o.date)}): ${bits.length?bits.join(', '):'already up to date'}.${o.newPeople?' New members can be chosen for Club Exco seats now.':''}`);
 }
 if(o.skipped)lines.push(`${s(o.skipped,'row was','rows were')} skipped: no member ID${o.skipped===1?'':'s'} (people are matched by Toastmasters member ID).`);
 if(o.stale.length)lines.push(`Not changed, because the database already has a newer list: ${o.stale.map(esc).join(', ')}.`);
 if(o.other&&o.other.size)lines.push(`Other divisions (${[...o.other].map(([d,n])=>`${esc(d)}: ${n} club${n===1?'':'s'}`).join(', ')}) are saved to the member database only; Division G's lists here do not show them.`);
 if(o.closed.length)lines.push(`Not imported, because member imports for their division are not open yet (the privacy notice comes first): ${o.closed.map(esc).join(', ')}.`);
 if(o.outside.length)lines.push(`Not changed, outside your area or division: ${o.outside.map(esc).join(', ')}.`);
 if(o.failed.length)lines.push(`Could not save (try Sync Membership again): ${o.failed.map(esc).join(', ')}.`);
 const conflicts=o.conflicts.filter(x=>!x.done);
 const cRows=conflicts.map((x,i)=>`<div class="hdg-mdb-row" data-i="${o.conflicts.indexOf(x)}">
   <div><strong>${esc(x.who)}</strong> <span class="hdg-mdb-mut">${esc(x.club)} · ${esc(FIELD[x.field]||x.field)}</span><br>
   Yours: <b>${esc(x.yours||'(empty)')}</b> · Toastmasters list: <b>${esc(x.ti)}</b></div>
   <div class="hdg-mdb-acts"><button class="btn" type="button" data-act="keep">Keep yours</button><button class="btn primary" type="button" data-act="take">Use the list's</button></div></div>`).join('');
 const undo=o.imports.length&&!o.undone?`<div class="hdg-mdb-foot"><button class="btn" type="button" data-act="undo">Undo the member database changes</button>
   <span class="hdg-mdb-mut">Puts the member database back as it was before this import (rows someone changed since are left alone).</span></div>`:'';
 show(`<div class="hdg-mdb-card${o.failed.length?' bad':''}">${lines.map(l=>`<p>${l}</p>`).join('')}
  ${cRows?`<p class="hdg-mdb-q">These were corrected by hand and differ from the Toastmasters list. Which should stay?</p>${cRows}`:''}
  ${o.undone?`<p>${esc(o.undone)}</p>`:''}${undo}</div>`);
}

document.addEventListener('click',async ev=>{
 const b=ev.target.closest('#hdgMemberDbResult [data-act]');if(!b||!last)return;
 const act=b.dataset.act;b.disabled=true;
 try{
  if(act==='undo'){
   if(!confirm('Undo the member database changes from this import? The app\'s own member list is not changed.')){b.disabled=false;return;}
   let restored=0,since=0;const failed=[];
   for(const i of last.imports.slice().reverse()){
    try{const r=await cloud().undoMemberImport(i.id);restored+=r.restored||0;since+=r.changedSince||0;}catch(e){failed.push(i.name);}
   }
   last.undone=`Undone: ${restored} change${restored===1?'':'s'} put back${since?`, ${since} left as they are because someone changed them since`:''}.${failed.length?` Not undone (a newer import exists): ${failed.join(', ')}.`:''}`;
   last.conflicts.forEach(x=>x.done=true);
   const imp=(db.membershipImports||[]).find(x=>x.dbImports&&x.dbImports.some(d=>last.imports.some(l=>l.id===d.id)));
   if(imp){imp.dbUndone=new Date().toISOString();try{saveData();}catch(_){}}
  }else{
   const row=b.closest('[data-i]');const x=last.conflicts[+row.dataset.i];
   await cloud().resolveImportConflict(x.person,x.field,x.ti,act==='take');
   x.done=true;
  }
 }catch(e){b.disabled=false;alert('Could not save that choice. Please try again.');return;}
 render();
});

function wrap(){
 const base=window.applyMembershipImport;if(typeof base!=='function'||base.__hdgDb)return;
 const wrapped=function(){
  const before=(db.membershipImports||[])[0];
  const c=capture();
  const fail=()=>show('<div class="hdg-mdb-card bad">The member database could not be updated. Try Sync Membership again.</div>');
  let parts={local:c.rows,other:[]};
  try{parts=split(c.rows,c.map.clubNumber,c.map.clubName);}catch(_){}
  if(parts.other.length&&!parts.local.length){send(c,null).catch(fail);return;}
  let r;
  if(parts.other.length){const all=membershipRawRows;membershipRawRows=parts.local;try{r=base.apply(this,arguments);}finally{membershipRawRows=all;}}
  else r=base.apply(this,arguments);
  const imp=(db.membershipImports||[])[0];
  if(imp&&imp!==before)send(c,imp).catch(fail);
  return r;
 };
 wrapped.__hdgDb=true;window.applyMembershipImport=wrapped;
}
/* Officer lists: rows for clubs outside Division G become Exco seats in the member database (newer-wins, 017). */
function seatOf(role){const r=nn(role);
 if(/sergeant|^saa$|clubsaa/.test(r))return 'club_saa';if(/treasurer/.test(r))return 'club_treasurer';if(/secretary/.test(r))return 'club_secretary';
 if(/publicrelation|vppr|clubvppr/.test(r))return 'club_vppr';if(/membership|vpm/.test(r))return 'club_vpm';if(/education|vpe/.test(r))return 'club_vpe';
 if(/president/.test(r))return 'club_president';return '';}
const SEAT={club_president:'President',club_vpe:'VP Education',club_vpm:'VP Membership',club_vppr:'VP Public Relations',club_secretary:'Secretary',club_treasurer:'Treasurer',club_saa:'Sergeant at Arms'};
function officerPanel(html){
 let p=$id('hdgOfficerDbResult');
 if(!p){const btn=document.querySelector('button[onclick^="applyOfficerImport"]');const host=btn&&(btn.closest('.flex')||btn.parentElement);if(!host)return;
  p=document.createElement('div');p.id='hdgOfficerDbResult';p.className='hdg-mdb';host.insertAdjacentElement('afterend',p);}
 p.innerHTML=html;p.hidden=!html;
}
async function sendOfficers(rows,map,date,headers){
 const idCol=(headers||[]).find(h=>/^member\s*(id|number|no)$/i.test(String(h).trim()));
 if(!idCol){officerPanel('<div class="hdg-mdb-card bad">Officers of clubs outside Division G need the Member ID column; nothing was changed for them.</div>');return;}
 if(!date||date>today()){officerPanel('<div class="hdg-mdb-card bad">The officer list date is missing or in the future; nothing was changed for clubs outside Division G.</div>');return;}
 const byClub=new Map();
 for(const r of rows){const d=districtClub(map.clubNumber?r[map.clubNumber]:'',map.clubName?r[map.clubName]:'');if(!d)continue;
  const seat=seatOf(r[map.role]);if(!seat)continue;
  if(!byClub.has(d.club))byClub.set(d.club,{d,seats:[]});byClub.get(d.club).seats.push({role:seat,memberId:String(r[idCol]||'').trim()});}
 const ok=[],closed=[],outside=[],failed=[],kept=[],unmatched=[];
 officerPanel('<div class="hdg-mdb-card">Saving officers of other divisions to the member database…</div>');
 for(const [k,{d,seats}] of byClub){
  if(!d.canImport){(d.reason==='closed'?closed:outside).push(d.name);continue;}
  try{const res=await cloud().importClubOfficers(k,date,seats);ok.push(d.name);
   (res.kept||[]).forEach(x=>kept.push(`${d.name}: ${SEAT[x.role]||x.role}`));(res.unmatched||[]).forEach(x=>unmatched.push(`${d.name}: ${SEAT[x.role]||x.role}`));}
  catch(e){(e&&(e.status===403||e.code==='42501')?(/not open/i.test(e.message||'')?closed:outside):failed).push(d.name);}
 }
 const l=[];
 if(ok.length)l.push(`<strong>Exco saved to the member database</strong> for ${ok.length} club${ok.length===1?'':'s'} outside Division G (list of ${esc(date)}). Officers get their club's officer access at once.`);
 if(kept.length)l.push(`Kept ${kept.length} newer club change${kept.length===1?'':'s'}: ${kept.map(esc).join(', ')}.`);
 if(unmatched.length)l.push(`Not in the member list yet, so their seat waits for the next member list import: ${unmatched.map(esc).join(', ')}.`);
 if(closed.length)l.push(`Not imported, because imports for their division are not open yet: ${closed.map(esc).join(', ')}.`);
 if(outside.length)l.push(`Not changed, outside your area or division: ${outside.map(esc).join(', ')}.`);
 if(failed.length)l.push(`Could not save (try again): ${failed.map(esc).join(', ')}.`);
 officerPanel(`<div class="hdg-mdb-card${failed.length?' bad':''}">${l.map(x=>`<p>${x}</p>`).join('')}</div>`);
}
function wrapOfficers(){
 const base=window.applyOfficerImport;if(typeof base!=='function'||base.__hdgDist)return;
 const wrapped=function(){
  const v=id=>($id(id)&&$id(id).value)||'';
  const map={role:v('mapOfficerRole'),clubNumber:v('mapOfficerClubNumber'),clubName:v('mapOfficerClubName')};
  let rows=[],headers=[];try{rows=officerRawRows||[];headers=officerHeaders||[];}catch(_){}
  let parts={local:rows,other:[]};
  try{if(map.role&&(map.clubNumber||map.clubName))parts=split(rows,map.clubNumber,map.clubName);}catch(_){}
  if(!parts.other.length)return base.apply(this,arguments);
  const date=v('officerImportDate')||today();
  const fail=()=>officerPanel('<div class="hdg-mdb-card bad">Officers of other divisions could not be saved. Try again.</div>');
  if(!parts.local.length){sendOfficers(parts.other,map,date,headers).catch(fail);return;}
  const all=officerRawRows;let r;officerRawRows=parts.local;try{r=base.apply(this,arguments);}finally{officerRawRows=all;}
  sendOfficers(parts.other,map,date,headers).catch(fail);
  return r;
 };
 wrapped.__hdgDist=true;window.applyOfficerImport=wrapped;
}
function boot(tries=0){
 if(!isLeaderApp()||!cloud()||typeof cloud().importClubs!=='function'||!(cloud().accountId&&cloud().accountId())){if(tries<40)setTimeout(()=>boot(tries+1),1500);return;}
 wrap();loadDistrict();
 /* After club-exco.js wraps the officer import (its boot waits for sign-in too). */
 setTimeout(wrapOfficers,3000);
 setInterval(loadDistrict,10*60*1000);
}

const css=document.createElement('style');css.id='hdg-member-import-style';css.textContent=`
.hdg-mdb{margin-top:12px}
.hdg-mdb-card{border:1px solid rgba(79,204,151,.45);background:rgba(79,204,151,.08);border-radius:14px;padding:12px 14px;display:grid;gap:8px;font-size:14px;line-height:1.45}
.hdg-mdb-card.bad{border-color:rgba(255,140,140,.5);background:rgba(255,140,140,.08)}
.hdg-mdb-card p{margin:0}
.hdg-mdb-q{font-weight:700}
.hdg-mdb-row{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:10px;padding:10px 0;border-top:1px solid rgba(255,255,255,.12)}
.hdg-mdb-acts,.hdg-mdb-foot{display:flex;flex-wrap:wrap;align-items:center;gap:8px}
.hdg-mdb-acts .btn,.hdg-mdb-foot .btn{min-height:40px;padding:0 16px;opacity:1!important}
.hdg-mdb-foot{padding-top:8px;border-top:1px solid rgba(255,255,255,.12)}
.hdg-mdb-mut{opacity:.75;font-size:13px}
`;
document.head.appendChild(css);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>boot(),{once:true});else boot();
})();
