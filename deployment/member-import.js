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
  let club=null;
  try{club=findClubForImport(c.map.clubNumber?r[c.map.clubNumber]:'',c.map.clubName?r[c.map.clubName]:'');}catch(_){}
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
 const out={date:c.date,clubs:0,newPeople:0,newMemberships:0,updated:0,left:0,skipped:0,stale:[],outside:[],failed:[],conflicts:[],imports:[]};
 const nameOf=new Map();
 for(const [k,{club,rows}] of byClub){
  rows.forEach(r=>{if(r.memberId)nameOf.set(cn(r.memberId),r.name);});
  try{
   const res=await cloud().importClubMembers(k,c.date,rows,c.snapshot);
   if(res&&res.stale){out.stale.push(`${club.name} (has a list dated ${res.newerAsOf})`);continue;}
   out.clubs++;out.newPeople+=res.newPeople||0;out.newMemberships+=res.newMemberships||0;
   out.updated+=(res.updatedPeople||0)+(res.updatedMemberships||0);out.left+=res.left||0;out.skipped+=res.skipped||0;
   (res.conflicts||[]).forEach(x=>out.conflicts.push({...x,club:club.name,who:nameOf.get(cn(x.memberId))||x.yours}));
   if(res.import)out.imports.push({club:k,name:club.name,id:res.import});
  }catch(e){(e&&e.status===403||e&&e.code==='42501'?out.outside:out.failed).push(club.name);}
 }
 imp.dbImports=out.imports;
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
  const r=base.apply(this,arguments);
  const imp=(db.membershipImports||[])[0];
  if(imp&&imp!==before)send(c,imp).catch(()=>show('<div class="hdg-mdb-card bad">The member database could not be updated. Try Sync Membership again.</div>'));
  return r;
 };
 wrapped.__hdgDb=true;window.applyMembershipImport=wrapped;
}
function boot(tries=0){
 if(!isLeaderApp()){if(tries<40)setTimeout(()=>boot(tries+1),1500);return;}
 wrap();
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
