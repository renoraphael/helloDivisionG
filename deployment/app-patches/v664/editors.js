(function(){
'use strict';
/* v663: one pop-up editor for TLI sessions, contests and clubs, a TLI attendance checklist, and refreshed TLI and
   contest schedule cards. The pop-up opens in the middle of the screen (full screen on phones) instead of expanding
   at the top of the page. */
if(window.__v663Editors)return;window.__v663Editors=true;
const $i=id=>document.getElementById(id);
const H=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const num=v=>{const x=Number(v);return Number.isFinite(x)?x:0;};
const norm=v=>typeof normalized==='function'?normalized(v):String(v||'').toLowerCase().replace(/[^a-z0-9]/g,'');
const clubNo=v=>String(v||'').replace(/^0+/,'');
const byDate=(a,b)=>String(a.date||'9999').localeCompare(String(b.date||'9999'));
const user=()=>{try{return activeDashboardUser();}catch(_){return {role:'division-director'};}};
const pretty=d=>{try{return d?prettyDate(d):'';}catch(_){return d||'';}};
const MONTHS=['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

/* ---------- field builders ---------- */
const F={
 text(id,label,val,o={}){return `<label class="v663-f ${o.wide?'wide':''} ${o.full?'full':''}"><span>${label}</span><input id="${id}"${o.name?` name="${o.name}"`:''} type="${o.type||'text'}" value="${H(val)}"${o.ph?` placeholder="${H(o.ph)}"`:''}${o.list?` list="${o.list}"`:''}${o.min!=null?` min="${o.min}"`:''}${o.req?' required':''} autocomplete="off"${o.type==='number'?' inputmode="numeric"':''}>${o.hint?`<small>${o.hint}</small>`:''}</label>`;},
 select(id,label,val,opts,o={}){return `<label class="v663-f ${o.wide?'wide':''}"><span>${label}</span><select id="${id}"${o.name?` name="${o.name}"`:''}>${opts.map(x=>{const [v,t]=Array.isArray(x)?x:[x,x];return `<option value="${H(v)}"${String(v)===String(val??'')?' selected':''}>${H(t)}</option>`;}).join('')}</select>${o.hint?`<small>${o.hint}</small>`:''}</label>`;},
 seg(name,label,val,opts){if(val&&!opts.includes(val))opts=[...opts,val];return `<div class="v663-f full"><span>${label}</span><div class="v663-seg" role="radiogroup" aria-label="${H(label)}" data-name="${name}">${opts.map(x=>`<button type="button" role="radio" aria-checked="${x===val}" data-v="${H(x)}">${H(x)}</button>`).join('')}</div></div>`;},
 area(id,label,val,o={}){return `<label class="v663-f full"><span>${label}</span><textarea id="${id}"${o.name?` name="${o.name}"`:''} rows="${o.rows||3}"${o.ph?` placeholder="${H(o.ph)}"`:''}>${H(val)}</textarea></label>`;},
 check(id,label,on,hint){return `<button type="button" class="v663-check" id="${id}" aria-pressed="${!!on}"><span class="v663-box" aria-hidden="true"></span><span class="v663-check-copy"><b>${label}</b>${hint?`<small>${hint}</small>`:''}</span></button>`;},
 sec(title,inner,note){return `<section class="v663-sec"><h3>${title}</h3>${note?`<p>${note}</p>`:''}<div class="v663-grid">${inner}</div></section>`;}
};
const val=id=>($i(id)?.value??'');
const segVal=(d,name)=>d.querySelector(`.v663-seg[data-name="${name}"] [aria-checked="true"]`)?.dataset.v||'';
const pressed=id=>$i(id)?.getAttribute('aria-pressed')==='true';

/* ---------- shared dialog ---------- */
function peopleList(){
 let list=$i('v663People');if(!list){list=document.createElement('datalist');list.id='v663People';document.body.appendChild(list);}
 const seen=new Set(),opts=[];
 const add=(name,label)=>{name=String(name||'').trim();if(!name||seen.has(name.toLowerCase()))return;seen.add(name.toLowerCase());const o=document.createElement('option');o.value=name;if(label)o.label=label;opts.push(o);};
 for(const m of (db.memberRecords||db.database?.memberRecords||[]))add(m.name,[m.nickname,m.clubName].filter(Boolean).join(' · '));
 for(const o of (db.officerRecords||[]))if(!o.past)add(o.name,[o.role,o.clubName].filter(Boolean).join(' · '));
 list.replaceChildren(...opts);
}
/* The editor opens inside the page, right under the row (or card) whose Edit button was clicked. Pop-ups are kept
   for detail views only (owner, 25 November 2026). */
const ANCHOR_SEL='tr, .member-mobile-card, .v663-card, .contest-schedule-card';
let lastTrigger=null;
const PANELS=new Map(); /* by id: a panel taken out of the page by a redraw is still found here */
document.addEventListener('click',e=>{const t=e.target.closest?.('button,[onclick],a');if(t&&!t.closest('.v663-dlg'))lastTrigger=t;},true);
function holder(){let h=$i('v663Holder');if(!h){h=document.createElement('div');h.id='v663Holder';h.hidden=true;document.body.appendChild(h);}return h;}
function attrSel(v){return String(v).replace(/\\/g,'\\\\').replace(/"/g,'\\"');}
function findAnchor(trig){
 if(!trig||!document.contains(trig))return null;
 return trig.closest(ANCHOR_SEL)||trig.closest('.section-title,.directory-title-row,.tli-center-hero,.v663-addbar,.member-directory-toolbar')||trig;
}
function unplace(d){
 d.__anchor?.classList.remove('v663-editing-row');
 holder().appendChild(d);
 if(d.__wrap){d.__wrap.remove();d.__wrap=null;}
 d.__anchor=null;
}
function place(d,anchor){
 unplace(d);
 if(!anchor){const tab=document.querySelector('section.tab:not([hidden])')||document.querySelector('main')||document.body;tab.prepend(d);return;}
 anchor.classList.add('v663-editing-row');d.__anchor=anchor;
 if(anchor.tagName==='TR'){
  const cols=[...anchor.children].reduce((n,c)=>n+(c.colSpan||1),0)||1;
  const tr=document.createElement('tr');tr.className='v663-edit-tr';const td=document.createElement('td');td.colSpan=cols;td.appendChild(d);tr.appendChild(td);
  anchor.after(tr);d.__wrap=tr;
 }else anchor.after(d);
}
/* A list that redraws while someone is typing takes the editor with it; put it back under the same row. */
new MutationObserver(()=>{
 for(const d of PANELS.values()){
  if(!d.__isOpen)continue;
  if(d.parentElement&&d.parentElement.id!=='v663Holder'&&document.contains(d))continue;
  const trig=d.__anchorSel?document.querySelector(d.__anchorSel):null;
  place(d,findAnchor(trig));
 }
}).observe(document.documentElement,{childList:true,subtree:true});
function canSwitch(d){return !(d.__isOpen&&d.__dirty?.()&&!confirm('Discard your unsaved changes?'));}
function makeDialog(id,formless){
 let d=PANELS.get(id);if(d)return d;
 d=document.createElement('div');d.id=id;PANELS.set(id,d);d.className='v663-dlg';d.hidden=true;d.setAttribute('role','region');d.setAttribute('aria-labelledby',id+'Title');
 const tag=formless?'div':'form';
 d.innerHTML=`<${tag} class="v663-shell"${formless?'':' novalidate'}>
  <header class="v663-head"><div class="v663-head-copy"><div class="v663-kicker"></div><h2 class="v663-title" id="${id}Title"></h2><div class="v663-sub"></div></div><button type="button" class="v663-x" data-act="close" aria-label="Close">×</button></header>
  <div class="v663-picker" hidden><label><span>Editing</span><select class="v663-pick" aria-label="Choose what to edit"></select></label></div>
  <nav class="v663-tabs" role="tablist" hidden></nav>
  <div class="v663-body"></div>
  <footer class="v663-foot"><button type="button" class="btn danger v663-del" data-act="delete" hidden>Delete</button><span class="v663-msg" role="status" aria-live="polite"></span><button type="button" class="btn ghost" data-act="close">Cancel</button><button type="submit" class="btn primary v663-save">Save</button></footer>
 </${tag}>`;
 holder().appendChild(d);
 Object.defineProperty(d,'open',{get:()=>!!d.__isOpen});
 d.close=()=>{d.__isOpen=false;d.hidden=true;unplace(d);};
 d.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();e.stopPropagation();tryClose(d);}});
 d.addEventListener('click',e=>{
  const act=e.target.closest('[data-act]');
  if(act){if(act.dataset.act==='close')tryClose(d);else if(act.dataset.act==='delete')d.__onDelete?.();return;}
  const tab=e.target.closest('.v663-tabs button');if(tab){showTab(d,tab.dataset.tab);return;}
  const sb=e.target.closest('.v663-seg button');
  if(sb){sb.parentElement.querySelectorAll('button').forEach(x=>x.setAttribute('aria-checked',String(x===sb)));d.__onInput?.(sb);return;}
  const ck=e.target.closest('.v663-check');
  if(ck){ck.setAttribute('aria-pressed',String(ck.getAttribute('aria-pressed')!=='true'));d.__onInput?.(ck);return;}
  d.__onClick?.(e);
 });
 d.addEventListener('input',e=>d.__onInput?.(e.target));
 d.addEventListener('change',e=>{if(e.target.classList.contains('v663-pick'))return;d.__onInput?.(e.target);});
 if(!formless)d.querySelector('form').addEventListener('submit',e=>{e.preventDefault();d.__onSave?.();});
 return d;
}
function snapshot(d){
 const parts=[];
 d.querySelectorAll('.v663-body input,.v663-body select,.v663-body textarea').forEach(e=>{if(e.classList.contains('v663-nosnap')||e.type==='hidden')return;parts.push((e.id||e.name)+'='+(e.type==='checkbox'?e.checked:e.value));});
 d.querySelectorAll('.v663-body .v663-seg').forEach(s=>parts.push(s.dataset.name+'='+(s.querySelector('[aria-checked="true"]')?.dataset.v||'')));
 d.querySelectorAll('.v663-body .v663-check').forEach(t=>parts.push(t.id+'='+t.getAttribute('aria-pressed')));
 return parts.join('\u0001')+'\u0002'+(d.__extraSnap?d.__extraSnap():'');
}
function armDirty(d){d.__snap=snapshot(d);d.__dirty=()=>snapshot(d)!==d.__snap;}
function tryClose(d){if(d.__dirty?.()&&!confirm('Discard your unsaved changes?'))return;d.__dirty=null;d.close();}
function showTab(d,tab){
 d.querySelectorAll('.v663-tabs button').forEach(b=>b.setAttribute('aria-selected',String(b.dataset.tab===tab)));
 d.querySelectorAll('.v663-body [data-panel]').forEach(p=>p.hidden=p.dataset.panel!==tab);
 d.__tab=tab;d.querySelector('.v663-body').scrollTop=0;d.__onTab?.(tab);
}
function setup(d,{kicker,title,sub,pick,pickValue,tabs,tab,body,del,saveLabel}){
 ['__onSave','__onDelete','__onPick','__onInput','__onClick','__onTab','__extraSnap','__dirty'].forEach(k=>{d[k]=null;});
 d.querySelector('.v663-kicker').textContent=kicker||'';
 d.querySelector('.v663-title').textContent=title||'';
 d.querySelector('.v663-sub').textContent=sub||'';
 const sel=d.querySelector('.v663-pick');
 sel.innerHTML=(pick||[]).map(([v,t])=>`<option value="${H(v)}">${H(t)}</option>`).join('');
 sel.value=pickValue||'';d.__pickValue=pickValue||'';
 d.querySelector('.v663-picker').hidden=true;
 const nav=d.querySelector('.v663-tabs');
 nav.hidden=!(tabs&&tabs.length>1);
 nav.innerHTML=(tabs||[]).map(([k,t])=>`<button type="button" role="tab" data-tab="${k}" aria-selected="false">${H(t)}</button>`).join('');
 if(body!=null)d.querySelector('.v663-body').innerHTML=body;
 d.querySelector('.v663-del').hidden=!del;
 d.querySelector('.v663-save').textContent=saveLabel||'Save';
 msg(d,'');
 if(tabs&&tabs.length)showTab(d,tab&&tabs.some(x=>x[0]===tab)?tab:tabs[0][0]);
}
function openDlg(d){
 peopleList();
 const trig=lastTrigger&&document.contains(lastTrigger)?lastTrigger:null;
 const oc=trig?.getAttribute('onclick');
 d.__anchorSel=oc?`[onclick="${attrSel(oc)}"]`:(trig?.id?`#${trig.id}`:null);
 place(d,findAnchor(trig));
 d.hidden=false;d.__isOpen=true;
 requestAnimationFrame(()=>{try{d.scrollIntoView({block:'nearest',behavior:'smooth'});}catch(_){}});
}
function msg(d,text){const m=d.querySelector('.v663-msg');if(m)m.textContent=text||'';}
function toast(text){
 let t=$i('v663Toast');if(!t){t=document.createElement('div');t.id='v663Toast';t.className='v663-toast';t.setAttribute('role','status');document.body.appendChild(t);}
 t.textContent=text;t.classList.add('show');clearTimeout(t.__h);t.__h=setTimeout(()=>t.classList.remove('show'),2600);
}
function invalid(d,tab,id,text){msg(d,text);if(tab)showTab(d,tab);const el=$i(id);if(el){el.focus();el.setAttribute('aria-invalid','true');el.addEventListener('input',()=>el.removeAttribute('aria-invalid'),{once:true});}}

/* ---------- TLI ---------- */
const TLI_STATUS=['Planned','Registration open','Registration closed','Completed','Postponed','Cancelled'];
const areasOf=v=>[...new Set((String(v||'').match(/G\s*\d/gi)||[]).map(x=>x.replace(/\s/g,'').toUpperCase()))];
function fixedRound(t){const s=String((typeof tliSemanticSlot==='function'?tliSemanticSlot(t):'')||'');return /^main-.*-1$/.test(s)?'tli1':/^main-.*-2$/.test(s)?'tli2':'';}
function roundOf(t){return fixedRound(t)||(t.round==='tli1'||t.round==='tli2'?t.round:'');}
const ROUND_LABEL={tli1:'TLI 1',tli2:'TLI 2'};
const personKey=o=>clubNo(o.clubNumber)+'|'+(norm(o.memberId)||norm(o.name));
function officerPeople(areas,field){
 const map=new Map();
 for(const o of (db.officerRecords||[])){
  if(!norm(o.name))continue;
  const area=String(o.area||'').toUpperCase();if(!areas.includes(area))continue;
  const k=personKey(o);let p=map.get(k);
  if(!p){p={key:k,name:String(o.name).trim(),club:o.clubName||'',clubNumber:clubNo(o.clubNumber),area,roles:[],recs:[],past:true};map.set(k,p);}
  p.recs.push(o);if(o.role&&!p.roles.includes(o.role))p.roles.push(o.role);if(!o.past)p.past=false;
 }
 for(const p of map.values()){const v=p.recs.map(o=>o[field]);p.value=v.includes(true)?true:v.includes(false)?false:null;}
 return [...map.values()];
}
function coverage(field,areas){
 const ppl=new Map();
 for(const o of (db.officerRecords||[])){
  if(o.past||!norm(o.name))continue;
  if(areas&&!areas.includes(String(o.area||'').toUpperCase()))continue;
  const k=personKey(o);ppl.set(k,(ppl.get(k)||false)||o[field]===true);
 }
 return {total:ppl.size,done:[...ppl.values()].filter(Boolean).length};
}
function tliPick(u){return [['','＋ New TLI session'],...roleScopedTlis(u).slice().sort(byDate).map(x=>[x.id,`${x.name}${x.date?' · '+pretty(x.date):''}`])];}
function openTli(id,tab){
 if(typeof db==='undefined')return;
 const u=user();
 const t=id?(db.tlis||[]).find(x=>x.id===id):null;
 if(id&&(!t||!relevantTliForRole(t,u)))return;
 const s=t||{type:'Supplementary TLI',status:'Planned',mode:'In-person',areas:u.role==='area-director'?u.area:''};
 const fr=fixedRound(s),d=makeDialog('v663Editor');if(!canSwitch(d))return;
 const confirmed=t&&typeof TLI_V252_CONFIRMED!=='undefined'&&TLI_V252_CONFIRMED[tliSemanticSlot(t)];
 const details=
  F.sec('Session',F.text('v663TName','Session name',s.name,{req:1,wide:1,ph:'e.g. Supplementary TLI — Denpasar'})+F.select('v663TType','Type',s.type||'Main TLI',['Main TLI','Supplementary TLI'])+F.select('v663TMode','Format',s.mode||'In-person',['In-person','Hybrid','Online'])+F.seg('status','Status',s.status||'Planned',TLI_STATUS))+
  F.sec('Date and time',F.text('v663TDate','Date',s.date,{type:'date'})+F.text('v663TStart','Starts',s.start,{type:'time'})+F.text('v663TEnd','Ends',s.end,{type:'time'})+F.select('v663TZone','Time zone',s.timezone||'',[['','Not set'],'WIB','WITA','WIT']))+
  F.sec('Place',F.text('v663TVenue','Venue or online link label',s.venue,{wide:1,ph:'e.g. Kedai Ori Tenggilis'})+F.text('v663TCity','City',s.city)+F.text('v663TIsland','Island / region',s.island))+
  F.sec('Who it is for',F.text('v663TAreas','Areas covered',s.areas,{wide:1,ph:'G1, G2',hint:'Officers in these Areas appear on the attendance list.'})+F.text('v663TLead','Lead / PIC',s.lead,{wide:1,list:'v663People',ph:'Search a member or type a name'}))+
  F.sec('Results',F.text('v663TReg','Registered',num(s.registered),{type:'number',min:0})+F.text('v663TAtt','Total attendance',num(s.attendance),{type:'number',min:0,hint:'Everyone who signed in, guests included'})+F.text('v663TClubs','Clubs represented',num(s.clubs),{type:'number',min:0})+F.text('v663TOff','Officers trained',num(s.officers),{type:'number',min:0,hint:fr?'Updated from the attendance list when you change it.':''}))+
  F.sec('Notes',F.area('v663TNotes','Notes / follow-up',s.notes,{rows:4,ph:'Anything to follow up after the session'}));
 const attHead=fr
  ?`<div class="v663-round">Counts toward <b>${ROUND_LABEL[fr]}</b> on each officer's record.</div>`
  :`<div class="v663-grid">${F.select('v663TRound','Counts toward',s.round||'',[['','Not counted toward TLI 1 or 2'],['tli1','TLI 1'],['tli2','TLI 2']],{wide:1})}</div>`;
 const att=`<section class="v663-sec"><h3>Officer attendance</h3><p>Mark each club officer in the Areas covered. This sets the TLI badge on their Officer / Exco record.</p>${attHead}
  <div class="v663-att-tools"><input type="search" id="v663AttSearch" class="v663-nosnap" placeholder="Search officer or club" aria-label="Search officers"><div class="v663-att-count" id="v663AttCount"></div></div>
  <div class="v663-att-bulk"><button type="button" class="btn ghost" data-bulk="no">Mark everyone not recorded as didn't attend</button></div>
  <div id="v663AttList" class="v663-att-list"></div></section>`;
 setup(d,{kicker:t?(t.type||'TLI session'):'New TLI session',title:t?t.name:'Add a TLI session',sub:t?[pretty(t.date)||'Date TBA',typeof tliTimeLabel==='function'?tliTimeLabel(t):''].filter(Boolean).join(' · '):'Main sessions already exist for each round; use this for supplementary sessions.',
  pick:tliPick(u),pickValue:t?t.id:'',tabs:[['details','Details'],['attendance','Officer attendance']],tab,
  body:`<div data-panel="details">${details}</div><div data-panel="attendance" hidden>${att}</div>`,del:t&&!confirmed});
 d.__att=new Map();d.__att0=new Map();d.__recs=new Map();d.__fixedRound=fr;
 d.__extraSnap=()=>[...d.__att].filter(([k,v])=>d.__att0.get(k)!==v).map(([k,v])=>k+'='+v).join(',');
 const refresh=()=>renderAttendance(d);
 d.__onInput=el=>{if(!el)return;if(el.id==='v663TAreas'||el.id==='v663TRound'||el.id==='v663AttSearch'||el.id==='v663TName'||el.id==='v663TType')refresh();};
 d.__onClick=e=>{
  const b=e.target.closest('.v663-tri button');
  if(b){const row=b.closest('[data-key]');const v=b.dataset.v==='yes'?true:b.dataset.v==='no'?false:null;d.__att.set(row.dataset.key,v);paintRow(row,v);countAttendance(d);return;}
  const bulk=e.target.closest('[data-bulk]');
  if(bulk){for(const p of d.__people||[]){const k=p.key+'|'+d.__round;if(d.__att.get(k)==null)d.__att.set(k,false);}refresh();}
 };
 d.__onPick=v=>openTli(v||null,d.__tab);
 d.__onSave=()=>saveTli(d,t);
 d.__onDelete=()=>{if(!t)return;deleteTli(t.id);if(!(db.tlis||[]).some(x=>x.id===t.id)){d.__dirty=null;d.close();toast('Session deleted');}};
 refresh();
 openDlg(d);armDirty(d);
}
function attRound(d){return d.__fixedRound||val('v663TRound');}
function renderAttendance(d){
 const list=$i('v663AttList');if(!list)return;
 const u=user(),round=attRound(d);
 let areas=areasOf(val('v663TAreas'));if(u.role==='area-director')areas=areas.filter(a=>a===u.area);
 const tools=d.querySelectorAll('.v663-att-tools,.v663-att-bulk');
 d.__people=[];d.__round=round;
 if(!round||!areas.length){
  tools.forEach(x=>x.hidden=true);
  list.innerHTML=`<div class="v663-empty">${!round?'Choose which round this session counts toward to record officer attendance.':'Add the Areas covered on the Details tab (for example G1, G2) to list their officers.'}</div>`;
  countAttendance(d);return;
 }
 tools.forEach(x=>x.hidden=false);
 const people=officerPeople(areas,round);
 for(const p of people){const k=p.key+'|'+round;if(!d.__att0.has(k))d.__att0.set(k,p.value);if(!d.__att.has(k))d.__att.set(k,p.value);d.__recs.set(k,p.recs);}
 d.__people=people;
 const q=norm(val('v663AttSearch'));
 const shown=people.filter(p=>!q||norm(p.name).includes(q)||norm(p.club).includes(q)||norm(p.roles.join(' ')).includes(q));
 const clubs=new Map();
 for(const p of shown){const k=p.area+'|'+p.club;if(!clubs.has(k))clubs.set(k,{area:p.area,club:p.club,number:p.clubNumber,people:[]});clubs.get(k).people.push(p);}
 const groups=[...clubs.values()].sort((a,b)=>a.area.localeCompare(b.area)||a.club.localeCompare(b.club));
 list.innerHTML=groups.length?groups.map(g=>{
  g.people.sort((a,b)=>(a.past-b.past)||a.name.localeCompare(b.name));
  return `<div class="v663-club" data-club="${H(g.area+'|'+g.club)}"><div class="v663-club-head"><b>${H(g.club||'Club')}</b><span>Area ${H(g.area)}${g.number?' · #'+H(g.number):''}</span><em class="v663-club-count"></em></div>${g.people.map(p=>{
   const k=p.key+'|'+round,v=d.__att.get(k);
   return `<div class="v663-person" data-key="${H(k)}"><div class="v663-pname"><b>${H(p.name)}</b><small>${H(p.roles.join(', ')||'Officer')}${p.past?' · Past Exco':''}</small></div><div class="v663-tri" role="radiogroup" aria-label="${H(p.name)}"><button type="button" role="radio" data-v="yes">Attended</button><button type="button" role="radio" data-v="no">Didn't attend</button><button type="button" role="radio" data-v="unk" aria-label="Not recorded" title="Not recorded">—</button></div></div>`;
  }).join('')}</div>`;}).join(''):'<div class="v663-empty">No officer matches that search.</div>';
 list.querySelectorAll('[data-key]').forEach(r=>paintRow(r,d.__att.get(r.dataset.key)));
 countAttendance(d);
}
function paintRow(row,v){
 row.classList.toggle('is-yes',v===true);row.classList.toggle('is-no',v===false);
 row.querySelectorAll('.v663-tri button').forEach(b=>b.setAttribute('aria-checked',String((b.dataset.v==='yes'&&v===true)||(b.dataset.v==='no'&&v===false)||(b.dataset.v==='unk'&&v==null))));
}
function countAttendance(d){
 const el=$i('v663AttCount');if(!el)return;
 const people=d.__people||[],round=d.__round;let y=0,no=0,un=0;
 for(const p of people){const v=d.__att.get(p.key+'|'+round);if(v===true)y++;else if(v===false)no++;else un++;}
 el.innerHTML=people.length?`<span class="ok">${y} attended</span><span class="no">${no} didn't attend</span><span>${un} not recorded</span>`:'';
 document.querySelectorAll('#v663AttList .v663-club').forEach(c=>{const rows=[...c.querySelectorAll('[data-key]')];const yes=rows.filter(r=>d.__att.get(r.dataset.key)===true).length;const e=c.querySelector('.v663-club-count');if(e)e.textContent=`${yes} of ${rows.length} attended`;});
 const tab=d.querySelector('.v663-tabs [data-tab="attendance"]');if(tab)tab.textContent=people.length?`Officer attendance · ${y}/${people.length}`:'Officer attendance';
}
function saveTli(d,t){
 const name=val('v663TName').trim();
 if(!name)return invalid(d,'details','v663TName','Add a session name.');
 db.tlis=db.tlis||[];
 let id=t?.id||uid();
 const draft={id,name,type:val('v663TType'),status:segVal(d,'status')||'Planned',date:val('v663TDate'),start:val('v663TStart'),end:val('v663TEnd'),timezone:val('v663TZone'),mode:val('v663TMode'),city:val('v663TCity').trim(),island:val('v663TIsland').trim(),venue:val('v663TVenue').trim(),areas:val('v663TAreas').trim(),lead:val('v663TLead').trim(),notes:val('v663TNotes'),registered:num(val('v663TReg')),attendance:num(val('v663TAtt')),clubs:num(val('v663TClubs')),officers:num(val('v663TOff'))};
 if($i('v663TRound'))draft.round=val('v663TRound');
 if(draft.end&&draft.start&&draft.end<draft.start)return invalid(d,'details','v663TEnd','The end time is before the start time.');
 let changed=0;
 for(const [k,v] of d.__att){if(d.__att0.get(k)===v)continue;const recs=d.__recs.get(k)||[];const round=k.slice(k.lastIndexOf('|')+1);for(const o of recs)o[round]=v;changed++;}
 const fr=fixedRound(draft);
 if(fr&&changed)draft.officers=officerPeople(areasOf(draft.areas),fr).filter(p=>p.value===true).length;
 if(!t){const slot=tliSemanticSlot(draft);const same=slot?db.tlis.find(x=>tliSemanticSlot(x)===slot):null;if(same)id=same.id;}
 const idx=db.tlis.findIndex(x=>x.id===id),existing=idx>=0?db.tlis[idx]:{};
 const item={...existing,...draft,id};
 if(idx>=0)db.tlis[idx]=item;else db.tlis.push(item);
 try{reconcileTliDatabaseV252();}catch(_){}
 try{updateOfficerCounts();}catch(_){}
 d.__dirty=null;d.close();saveData();try{render();}catch(_){}
 toast(changed?`Saved · ${changed} officer${changed===1?'':'s'} updated`:'Session saved');
}

/* ---------- Contests ---------- */
const CONTEST_STATUS=['Not started','Planning','Confirmed','Registration open','Completed','Postponed'];
const contestAllowed=(c,u)=>!(u.role==='area-director'&&(c.level==='Division'||!relevantContestForRole(c,u)));
function openContest(id,tab){
 if(typeof db==='undefined')return;
 const u=user();
 const c=id?(db.contests||[]).find(x=>x.id===id):null;
 if(id&&(!c||!contestAllowed(c,u)))return;
 const s=c||{level:'Area',status:'Planning',mode:'In-person',area:u.role==='area-director'?u.area:''};
 const d=makeDialog('v663Editor');if(!canSwitch(d))return;
 const areas=(db.areas||[]).map(a=>a.code).filter(Boolean);
 const levels=u.role==='area-director'?['Area','Club']:['Area','Division','Club'];
 const details=
  F.sec('Contest',F.text('v663CTitle','Contest name',s.title,{req:1,wide:1,ph:'e.g. Joint Area G1 & G2 Contest'})+F.select('v663CLevel','Level',s.level||'Area',levels)+F.select('v663CArea','Main Area',s.area||'',[['','Not area-specific'],...areas])+F.text('v663CCoverage','Areas taking part',s.coverage,{wide:1,ph:'G1 + G2 or Division G'})+F.seg('status','Status',s.status||'Planning',CONTEST_STATUS))+
  F.sec('Date and time',F.text('v663CDate','Date',s.date,{type:'date'})+F.text('v663CStart','Starts',s.start,{type:'time'})+F.text('v663CEnd','Ends',s.end,{type:'time'})+F.text('v663CWindow','Planned window',s.targetWindow,{ph:'e.g. End Mar 2027',hint:'Shown until a date is set.'}))+
  F.sec('Place',F.text('v663CVenue','Venue',s.venue,{wide:1,ph:'Venue name or TBA'})+F.select('v663CMode','Format',s.mode||'In-person',['In-person','Hybrid','Online'])+F.text('v663CCity','City',s.city)+F.text('v663CIsland','Island / region',s.island))+
  F.sec('Notes',F.area('v663CNotes','Notes / next action',s.notes,{rows:4}));
 const team=
  F.sec('Contest team',F.text('v663CChair','Contest Chair',s.chair,{wide:1,list:'v663People',ph:'Search a member or type a name'})+F.text('v663CJudge','Chief Judge',s.chiefJudge,{wide:1,list:'v663People',ph:'Search a member or type a name'}))+
  F.sec('Expected numbers',F.text('v663CContestants','Contestants',num(s.contestants),{type:'number',min:0})+F.text('v663CAttendance','Attendance',num(s.attendance),{type:'number',min:0}))+
  `<section class="v663-sec"><h3>Readiness</h3><div class="v663-meter"><i id="v663CMeter"></i></div><p id="v663CMeterText"></p><div class="v663-grid">${F.check('v663CVenueOk','Venue confirmed',s.venueConfirmed,'Booked and paid')+F.check('v663CJudgesOk','Judges confirmed',s.judgesConfirmed,'Chief Judge has the full panel')+F.check('v663CContestantsOk','Contestants confirmed',s.contestantsConfirmed,'Every Area or club winner has replied')+F.check('v663CPromoOk','Promotion ready',s.promoReady,'Poster and registration link are out')}</div></section>`;
 const pick=[['','＋ New contest'],...roleScopedContests(u).filter(x=>contestAllowed(x,u)).sort(byDate).map(x=>[x.id,`${x.title}${x.date?' · '+pretty(x.date):x.targetWindow?' · '+x.targetWindow:''}`])];
 setup(d,{kicker:c?`${c.level||''} contest`:'New contest',title:c?c.title:'Add a contest',sub:c?[typeof contestScheduleLabel==='function'?contestScheduleLabel(c):'',c.venue&&c.venue!=='TBA'?c.venue:'',c.city].filter(Boolean).join(' · '):'',
  pick,pickValue:c?c.id:'',tabs:[['details','Details'],['team','Team & readiness']],tab,
  body:`<div data-panel="details">${details}</div><div data-panel="team" hidden>${team}</div>`,del:!!c});
 const meter=()=>{const ids=['v663CVenueOk','v663CJudgesOk','v663CContestantsOk','v663CPromoOk'],k=ids.filter(pressed).length;const m=$i('v663CMeter');if(m)m.style.width=(k*25)+'%';const t=$i('v663CMeterText');if(t)t.textContent=`${k} of 4 ready`;const tb=d.querySelector('.v663-tabs [data-tab="team"]');if(tb)tb.textContent=`Team & readiness · ${k}/4`;};
 d.__onInput=el=>{if(el?.classList?.contains('v663-check'))meter();};
 d.__onPick=v=>openContest(v||null,d.__tab);
 d.__onSave=()=>saveContest(d,c);
 d.__onDelete=()=>{if(!c)return;deleteContest(c.id);if(!(db.contests||[]).some(x=>x.id===c.id)){d.__dirty=null;d.close();toast('Contest deleted');try{render();}catch(_){}}};
 meter();openDlg(d);armDirty(d);
}
function saveContest(d,c){
 const title=val('v663CTitle').trim();
 if(!title)return invalid(d,'details','v663CTitle','Add a contest name.');
 if(val('v663CEnd')&&val('v663CStart')&&val('v663CEnd')<val('v663CStart'))return invalid(d,'details','v663CEnd','The end time is before the start time.');
 const id=c?.id||uid(),coverage=val('v663CCoverage').trim();
 const item={...(c||{}),id,level:val('v663CLevel'),area:val('v663CArea'),coverage,owner:coverage||title,title,type:'Multiple / Combined',categories:typeof CONTEST_CATEGORIES!=='undefined'?CONTEST_CATEGORIES:(c?.categories||[]),
  status:segVal(d,'status')||'Planning',targetWindow:val('v663CWindow').trim(),date:val('v663CDate'),start:val('v663CStart'),end:val('v663CEnd'),mode:val('v663CMode'),city:val('v663CCity').trim(),island:val('v663CIsland').trim(),venue:val('v663CVenue').trim(),
  chair:val('v663CChair').trim(),chiefJudge:val('v663CJudge').trim(),contestants:num(val('v663CContestants')),attendance:num(val('v663CAttendance')),
  venueConfirmed:pressed('v663CVenueOk'),judgesConfirmed:pressed('v663CJudgesOk'),contestantsConfirmed:pressed('v663CContestantsOk'),promoReady:pressed('v663CPromoOk'),notes:val('v663CNotes')};
 db.contests=db.contests||[];
 const idx=db.contests.findIndex(x=>x.id===id);if(idx>=0)db.contests[idx]=item;else db.contests.push(item);
 d.__dirty=null;d.close();saveData();try{render();}catch(_){}
 toast('Contest saved');
}

/* ---------- Clubs: the existing club form, shown in the pop-up ---------- */
const CLUB_SECTIONS=[
 ['Club',['clubName','clubNumber','clubArea','clubStatus','clubAliases','clubMode','clubCity','clubIsland']],
 ['Numbers from Toastmasters data',['mar27Override']],
 ['Paperwork',['duesPaid','officerList','cspSubmitted','renewalStatus']],
 ['Suspension risk',['suspensionRisk','suspensionReason']],
 ['Notes',['clubNotes']]
];
/* Filled by imports, the member roster or TLI attendance (shown as read-only tiles), or never used (all 16 clubs empty on
   25 Nov 2026). The inputs stay in the form, hidden, so a save keeps their stored values. */
const CLUB_HIDDEN=['clubCurrentMembers','baseMembers','newMembers','renewedMembers','lostMembers','dcpGoals','meetings','attendance','guests','conversions','educationAwards','officersTrained'];
const CLUB_WIDE=new Set(['clubName','clubAliases','suspensionReason','mar27Override']);
const CLUB_FULL=new Set(['clubNotes']);
const CLUB_LABELS={mar27Override:'Override the secured count for Mar 2027',clubAliases:'Other names',suspensionRisk:'Flag suspension risk',suspensionReason:'Reason / remarks'};
function clubDialog(){
 const form=PANELS.get('v663ClubDlg')?.querySelector('#clubForm')||$i('clubForm');if(!form)return null;
 let d=PANELS.get('v663ClubDlg');if(d&&d.contains(form))return d;
 d=makeDialog('v663ClubDlg',true);
 const body=d.querySelector('.v663-body');
 const grid=form.querySelector('.form-grid');
 const used=new Set();
 let html='';
 const sections=CLUB_SECTIONS.map(([title,ids])=>{const sec=document.createElement('section');sec.className='v663-sec';sec.innerHTML=`<h3>${title}</h3><div class="v663-grid"></div>`;const g=sec.querySelector('.v663-grid');
  for(const id of ids){const el=$i(id),f=el?.closest('.field');if(!f||used.has(f))continue;used.add(f);g.appendChild(f);f.classList.add('v663-field');if(CLUB_WIDE.has(id))f.classList.add('wide');if(CLUB_FULL.has(id))f.classList.add('full');if(CLUB_LABELS[id]){const l=f.querySelector('label');if(l)l.textContent=CLUB_LABELS[id];}}
  return sec;});
 const hidden=document.createElement('div');hidden.className='v663-hidden-fields';hidden.hidden=true;
 for(const id of CLUB_HIDDEN){const f=$i(id)?.closest('.field');if(f&&!used.has(f)){used.add(f);hidden.appendChild(f);}}
 sections.push(hidden);
 const numSec=sections[1];if(numSec){const p=document.createElement('p');p.textContent='These update with each Toastmasters import, the member roster and TLI attendance, so they are not typed here.';const tiles=document.createElement('div');tiles.className='v663-tiles';tiles.id='v663ClubTiles';numSec.querySelector('h3').after(p,tiles);}
 const riskSec=sections[3];if(riskSec){const p=document.createElement('p');p.textContent='Clubs with 2 or fewer members, or under 8 after 31 Mar 2027, are flagged automatically. Tick this only for another reason.';riskSec.querySelector('h3').after(p);}
 const rest=grid?[...grid.querySelectorAll(':scope > .field')].filter(f=>!used.has(f)):[];
 if(rest.length){const sec=document.createElement('section');sec.className='v663-sec';sec.innerHTML='<h3>More</h3><div class="v663-grid"></div>';rest.forEach(f=>{f.classList.add('v663-field');sec.querySelector('.v663-grid').appendChild(f);});sections.push(sec);}
 if(grid)grid.replaceWith(...sections);else sections.forEach(s=>form.appendChild(s));
 form.querySelectorAll('select').forEach(sel=>{
  const vals=[...sel.options].map(o=>o.value).sort().join(',');if(vals!=='false,true')return;
  const f=sel.closest('.field');const label=f?.querySelector('label')?.textContent||'';
  const b=document.createElement('button');b.type='button';b.className='v663-check v663-switch';b.dataset.for=sel.id;
  b.innerHTML=`<span class="v663-box" aria-hidden="true"></span><span class="v663-check-copy"><b>${H(label.replace(/\?$/,''))}</b></span>`;
  sel.hidden=true;sel.tabIndex=-1;f.classList.add('v663-has-switch');sel.after(b);
 });
 form.querySelector('.help-box')?.remove();
 const oldSave=form.querySelector('button[type="submit"]');oldSave?.parentElement&&oldSave.parentElement!==form?oldSave.parentElement.remove():oldSave?.remove();
 form.classList.add('v663-club-form');
 body.replaceChildren(form);
 const save=d.querySelector('.v663-save');save.setAttribute('form','clubForm');
 form.addEventListener('submit',e=>{
  const id=$i('clubId')?.value;d.__before=id?{...((db.clubs||[]).find(c=>c.id===id)||{})}:null;
 },true);
 form.addEventListener('submit',()=>{
  const before=d.__before;d.__before=null;
  if(before&&before.id){const now=(db.clubs||[]).find(c=>c.id===before.id);if(now){let restored=false;for(const k of Object.keys(before))if(!(k in now)){now[k]=before[k];restored=true;}if(restored){try{saveData();}catch(_){}}}}
  d.__dirty=null;if(d.open)d.close();toast('Club saved');
 });
 const ed=$i('clubEditor');if(ed){ed.open=false;ed.classList.add('v663-retired');}
 return d;
}
function syncSwitches(d){d.querySelectorAll('.v663-switch').forEach(b=>{const sel=$i(b.dataset.for);b.setAttribute('aria-pressed',String(sel?.value==='true'));});}
function openClub(id){
 if(typeof db==='undefined')return;
 const d=clubDialog();if(!d)return;if(!canSwitch(d))return;
 const club=id?(db.clubs||[]).find(c=>c.id===id):null;
 if(!club)return; /* clubs come from the Toastmasters club list; there is no manual 'new club' */
 $i('clubForm').querySelectorAll('option[data-v663-kept]').forEach(o=>o.remove());
 if(club){
  setClubFormValues(club);
  /* A stored value that is not one of the list's choices (e.g. meeting mode "Inactive") used to show blank and be erased on save. */
  for(const [fid,key] of [['clubMode','mode'],['clubStatus','status'],['renewalStatus','renewalStatus'],['clubArea','area']]){
   const sel=$i(fid),v=club[key];if(!sel||v==null||v==='')continue;
   if(![...sel.options].some(o=>o.value===String(v))){const o=document.createElement('option');o.value=o.textContent=String(v);o.dataset.v663Kept='1';sel.appendChild(o);}
   sel.value=String(v);
  }
 }else{try{resetClubForm();}catch(_){}}
 const clubs=(db.clubs||[]).slice().sort((a,b)=>String(a.area||'').localeCompare(String(b.area||''))||String(a.name||'').localeCompare(String(b.name||'')));
 setup(d,{kicker:club?`Area ${club.area||'—'} · Club${club.number?' #'+clubNo(club.number):''}`:'New club',title:club?club.name:'Add a club',sub:club?[club.city,club.island].filter(Boolean).join(' · '):'Most numbers fill in automatically from the Toastmasters imports.',
  pick:[...clubs.map(c=>[c.id,`${c.area?c.area+' · ':''}${c.name}`])],pickValue:club.id,body:null,del:true,saveLabel:'Save club'});
 syncSwitches(d);clubTiles(club);
 d.__onInput=el=>{const b=el?.closest?.('.v663-switch');if(b){const sel=$i(b.dataset.for);if(sel){sel.value=b.getAttribute('aria-pressed')==='true'?'true':'false';sel.dispatchEvent(new Event('change',{bubbles:true}));}}};
 d.__onPick=v=>v&&openClub(v);
 d.__onDelete=()=>{if(!club)return;deleteClub(club.id);if(!(db.clubs||[]).some(c=>c.id===club.id)){d.__dirty=null;d.close();toast('Club deleted');}};
 openDlg(d);armDirty(d);
}

function clubTiles(club){
 const box=$i('v663ClubTiles');if(!box)return;
 if(!club){box.innerHTML='<div class="v663-empty">Numbers appear after the next Toastmasters import.</div>';return;}
 const safe=f=>{try{return f();}catch(_){return '—';}};
 const ov=club.mar27Override!==null&&club.mar27Override!==undefined&&club.mar27Override!=='';
 const tiles=[
  ['Base (1 Jul)',num(club.baseMembers),'Toastmasters import'],
  ['Current members',safe(()=>currentClubMemberCount(club)),'Member roster'],
  ['New',num(club.newMembers),'Toastmasters import'],
  ['Renewed',num(club.renewedMembers),'Member roster'],
  ['Lost',num(club.lostMembers),'Member roster'],
  ['Secured for Mar 2027',safe(()=>mar27SecuredCount(club)),ov?'Manual override':'Calculated'],
  ['DCP goals',num(club.dcpGoals)+'/10','Toastmasters dashboard'],
  ['Officers trained',num(club.officersTrained),'TLI attendance']
 ];
 box.innerHTML=tiles.map(([l,v,src])=>`<div class="v663-tile"><span>${H(l)}</span><b>${H(v)}</b><small>${H(src)}</small></div>`).join('');
}

/* ---------- Members: quick edit in the pop-up ---------- */
function openMember(key){
 if(typeof db==='undefined')return;
 const m=(db.memberRecords||[]).find(x=>x.key===key);if(!m)return;
 const club=(db.clubs||[]).find(c=>norm(c.number)===norm(m.clubNumber));
 const u=user();if(u.role==='area-director'&&(club?.area||m.area||'')!==u.area)return;
 const d=makeDialog('v663Editor');if(!canSwitch(d))return;
 const designation=typeof memberDesignation==='function'?memberDesignation(m):'';
 const aliases=typeof memberNicknames==='function'?memberNicknames(m).join(', '):(m.nickname||'');
 const chinese=typeof memberChineseName==='function'?memberChineseName(m):(m.chineseName||'');
 const paths=(typeof memberPathways==='function'?memberPathways(m):[]).filter(x=>x.status!=='completed');
 const body=
  F.sec('Name',F.text('v663MName','Full name',m.name,{name:'name',req:1,wide:1})+F.text('v663MChinese','Chinese name / 中文名',chinese,{name:'chineseName',ph:'Hanzi'})+F.select('v663MCred','Credential',designation,[['','TM'],['DTM','DTM']],{name:'designation'})+F.text('v663MAliases','Nicknames',aliases,{name:'aliases',full:1,ph:'e.g. Dick, Mochi',hint:'Separate with commas. Used to recognise them in agendas and WhatsApp messages.'}))+
  `<section class="v663-sec"><h3>Membership</h3><p>From the Toastmasters club roster; the next roster import updates these.</p><div class="v663-tiles">${[['Club',club?`${club.area?club.area+' · ':''}${club.name}`:(m.clubName||'—')],['Status',m.active===false?'Past / lapsed':'Active'],['Member ID',m.memberId||'—'],['Paid through',m.renewThrough||'—'],['Joined the club',m.clubJoinDate?pretty(String(m.clubJoinDate).slice(0,10)):'—']].map(([l,v])=>`<div class="v663-tile"><span>${H(l)}</span><b class="v663-tile-text">${H(v)}</b></div>`).join('')}</div>
   <input type="hidden" name="clubId" value="${H(club?.id||'')}"><input type="hidden" name="status" value="${m.active===false?'inactive':'active'}"><input type="hidden" name="memberId" value="${H(m.memberId||'')}"><input type="hidden" name="renewThrough" value="${H(m.renewThrough||'')}"><input type="hidden" name="clubJoinDate" value="${H(String(m.clubJoinDate||'').slice(0,10))}"></section>`+
  /* Plan rule 1: a regular member's phone and street address are not kept, so they are not offered here; any old
     values pass through unchanged. */
  F.sec('Contact',F.text('v663MEmail','Email',m.email,{name:'email',type:'email',wide:1})+`<input type="hidden" name="phone" value="${H(m.phone||'')}"><input type="hidden" name="address" value="${H(m.address||'')}">`)+
  F.sec('Notes',F.area('v663MNotes','Notes',m.notes,{name:'notes',rows:3}))+
  `<section class="v663-sec"><h3>Pathways</h3><div class="v663-paths">${paths.length?paths.map(x=>`<span class="${x.primary?'is-primary':''}">${H(x.pathway)}</span>`).join(''):'<em>None yet</em>'}</div><div class="v663-row"><button type="button" class="btn ghost" data-profile="paths">Manage pathways</button><button type="button" class="btn ghost" data-profile="open">Open full profile</button></div></section>`;
 const same=(db.memberRecords||[]).filter(x=>norm(x.clubNumber)===norm(m.clubNumber)).sort((a,b)=>((a.active===false)-(b.active===false))||String(a.name||'').localeCompare(String(b.name||'')));
 setup(d,{kicker:[club?.name||m.clubName,m.memberId?'#'+m.memberId:''].filter(Boolean).join(' · ')||'Member',title:m.name||'Member',sub:[m.active===false?'Past member':'Active',m.renewThrough?'paid through '+m.renewThrough:''].filter(Boolean).join(' · '),
  pick:same.map(x=>[x.key,`${x.name||'—'}${x.active===false?' (past)':''}`]),pickValue:m.key,body,del:true,saveLabel:'Save member'});
 d.__onPick=v=>v&&openMember(v);
 d.__onClick=e=>{const b=e.target.closest('[data-profile]');if(!b)return;if(d.__dirty?.()&&!confirm('Discard your unsaved changes?'))return;d.__dirty=null;d.close();window.memberInlineOpenProfileV529?window.memberInlineOpenProfileV529(encodeURIComponent(m.key),b.dataset.profile==='paths'):showMemberDetail(m.key);};
 d.__onSave=()=>{
  if(!val('v663MName').trim())return invalid(d,null,'v663MName','Add the member\'s name.');
  if(!club)return invalid(d,null,'v663MName','This member\'s club is not in the club list, so the record cannot be saved here.');
  const form=d.querySelector('form.v663-shell');d.__dirty=null;d.close();
  saveInlineMemberEdit(m.key,form);
 };
 d.__onDelete=()=>{deleteMemberRecord(m.key);if(!(db.memberRecords||[]).some(x=>x.key===m.key)){d.__dirty=null;d.close();try{renderMemberDirectory();}catch(_){}toast('Member deleted');}};
 openDlg(d);armDirty(d);
}

/* ---------- Exco: the Toastmasters officer list fills this, but leaders can add or correct a seat at once
   (for example a mid-term change) without waiting for the next list. ---------- */
function officerRoles(){const sel=$i('officerRoleEdit');return sel?[...sel.options].map(o=>[o.value,o.textContent]):[['Club President','Club President'],['Other','Other']];}
function openOfficer(id,clubId){
 if(typeof db==='undefined')return;
 const u=user();
 const o=id?(db.officerRecords||[]).find(x=>x.id===id):null;if(id&&!o)return;
 const clubs=(db.clubs||[]).filter(c=>u.role!=='area-director'||c.area===u.area).sort((a,b)=>String(a.area||'').localeCompare(String(b.area||''))||String(a.name||'').localeCompare(String(b.name||'')));
 const club=o?(db.clubs||[]).find(c=>norm(c.number)===norm(o.clubNumber)):clubs.find(c=>clubNo(c.number)===clubNo(clubId));
 if(o&&u.role==='area-director'&&(o.area||club?.area||'')!==u.area)return;
 const d=makeDialog('v663Editor');if(!canSwitch(d))return;
 const tri=v=>v===true?'Attended':v===false?"Didn't attend":'Not recorded';
 const opts=['Attended',"Didn't attend",'Not recorded'];
 const roles=officerRoles(),role=o?(typeof canonicalExcoRole==='function'?canonicalExcoRole(o.role):o.role):'Club President';
 const body=
  F.sec('Officer',F.text('v663OName','Name',o?.name,{req:1,wide:1,list:'v663People',ph:'Search a member or type a name'})+F.select('v663ORole','Position',role,roles.some(r=>r[0]===role)?roles:[...roles,[role,role]],{wide:1})+F.select('v663OClub','Club',club?clubNo(club.number):'',[['','Choose a club'],...clubs.map(c=>[clubNo(c.number),`${c.area?c.area+' · ':''}${c.name}`])],{wide:1})+F.text('v663OTerm','Term',o?.term,{wide:1,ph:'1 Jul 2026 – 30 Jun 2027'})+F.text('v663OContact','Contact',o?.contact,{full:1}),
   'The Toastmasters officer list import fills this. Change it here when a seat changes before the next import.')+
  F.sec('TLI attendance',F.seg('tli1','TLI 1',tri(o?.tli1),opts)+F.seg('tli2','TLI 2',tri(o?.tli2),opts),'You can also record a whole session at once from the TLI page.');
 const same=o?(db.officerRecords||[]).filter(x=>norm(x.clubNumber)===norm(o.clubNumber)&&!x.past).sort((a,b)=>String(a.role||'').localeCompare(String(b.role||''))):[];
 setup(d,{kicker:o?[club?.name||o.clubName,o.past?'Past Exco':''].filter(Boolean).join(' · '):'New officer',title:o?(o.name||'Officer'):'Add an officer',sub:o?(o.role||''):'For a seat the last officer list does not show yet.',pick:same.length>1?same.map(x=>[x.id,`${x.name} · ${x.role||''}`]):null,pickValue:o?.id||'',body,del:!!o,saveLabel:o?'Save officer':'Add officer'});
 d.__onPick=v=>v&&openOfficer(v);
 const back=v=>v==='Attended'?true:v==="Didn't attend"?false:null;
 d.__onSave=()=>{
  const name=val('v663OName').trim(),c=clubs.find(x=>clubNo(x.number)===val('v663OClub'));
  if(!name)return invalid(d,null,'v663OName','Add the officer\'s name.');
  if(!c)return invalid(d,null,'v663OClub','Choose the club.');
  const pickedRole=val('v663ORole');const rec={name,role:o&&pickedRole===role?o.role:pickedRole,clubNumber:c.number,clubName:c.name,area:c.area,term:val('v663OTerm').trim(),contact:val('v663OContact').trim(),tli1:back(segVal(d,'tli1')),tli2:back(segVal(d,'tli2'))};
  db.officerRecords=db.officerRecords||[];
  if(o){const moved=o.name!==rec.name||o.role!==rec.role||norm(o.clubNumber)!==norm(rec.clubNumber);Object.assign(o,rec);if(moved&&typeof officerKey==='function')o.key=officerKey(o);}
  else{const n={id:uid(),...rec};if(typeof officerKey==='function')n.key=officerKey(n);
   if(db.officerRecords.some(x=>!x.past&&x.key&&x.key===n.key))return invalid(d,null,'v663OName',`${name} is already listed in this seat.`);
   db.officerRecords.push(n);}
  try{updateOfficerCounts();}catch(_){}
  d.__dirty=null;d.close();saveData();try{render();}catch(_){}toast(o?'Officer saved':`${name} added`);
  /* Hosted app: give the seat's access too (deployment/club-exco.js, schema 017). */
  if(typeof window.hdgExcoLeaderSaved==='function'){const saved=o||db.officerRecords[db.officerRecords.length-1];window.hdgExcoLeaderSaved(saved).then(m=>{if(m)toast(m);});}
 };
 d.__onDelete=()=>{if(!o)return;deleteOfficerRecord(o.id);if(!(db.officerRecords||[]).some(x=>x.id===o.id)){d.__dirty=null;d.close();toast('Officer removed');}};
 openDlg(d);armDirty(d);
}

/* ---------- TLI page ---------- */
function dateBlock(iso){
 const m=String(iso||'').match(/^(\d{4})-(\d{2})-(\d{2})/);
 return m?`<div class="v663-date"><b>${+m[3]}</b><span>${MONTHS[+m[2]-1]}</span><small>${m[1]}</small></div>`:'<div class="v663-date tba"><b>?</b><span>DATE</span><small>TBA</small></div>';
}
function statusTone(s){return s==='Completed'||s==='Confirmed'?'good':s==='Cancelled'||s==='Postponed'?'bad':'warn';}
function whenLabel(t){if(t.status==='Completed')return '';const dd=taskDaysUntil(t.date);if(dd===null)return 'Date TBA';if(dd<0)return 'Date has passed · update the status';if(dd===0)return 'Today';if(dd===1)return 'Tomorrow';return `In ${dd} days`;}
function tliCard(t,next){
 const r=roundOf(t),areas=areasOf(t.areas),cov=r&&areas.length?coverage(r,areas):null;
 const place=[t.venue&&!/^tba$/i.test(t.venue)?t.venue:'',t.city].filter(Boolean).join(', ')||'Venue TBA';
 const when=whenLabel(t);
 const stats=[[num(t.attendance),'attended'],[num(t.officers),'officers trained'],[num(t.clubs),'clubs'],[num(t.registered),'registered']].filter(([v],i)=>v||i<2);
 return `<article class="v663-card${next?' is-next':''}">${dateBlock(t.date)}
  <div class="v663-main">
   <div class="v663-top"><span class="badge ${statusTone(t.status)}">${H(t.status||'Planned')}</span><span class="v663-pill">${H(t.type||'TLI')}${t.areas?' · '+H(t.areas):''}</span>${when?`<span class="v663-when">${H(when)}</span>`:''}</div>
   <h3>${H(t.name)}</h3>
   <div class="v663-line">${H(typeof tliTimeLabel==='function'?tliTimeLabel(t):'')} · ${H(place)}</div>
   ${t.status==='Completed'||num(t.attendance)||num(t.officers)?`<div class="v663-stats">${stats.map(([v,l])=>`<div><b>${v}</b><span>${l}</span></div>`).join('')}</div>`:''}
   ${cov&&cov.total?`<div class="v663-cov"><div class="v663-bar"><i style="width:${Math.round(cov.done/cov.total*100)}%"></i></div><span>${cov.done} of ${cov.total} current officers in ${H(areas.join(', '))} have ${ROUND_LABEL[r]}</span></div>`:''}
   ${t.lead?`<div class="v663-line small">Lead: ${H(t.lead)}</div>`:''}
  </div>
  <div class="v663-actions"><button type="button" class="btn primary" onclick="editTli('${H(t.id)}')">Edit</button>${r?`<button type="button" class="btn ghost" onclick="v663OpenTli('${H(t.id)}','attendance')">Attendance</button>`:''}</div>
 </article>`;
}
function renderTlisV663(){
 if(!$i('tliFocus'))return;
 const fixed=reconcileTliDatabaseV252();if(fixed)saveData();
 const u=user(),tl=roleScopedTlis(u).slice().sort(byDate);
 const done=tl.filter(t=>['Completed','Cancelled'].includes(t.status)).reverse(),upcoming=tl.filter(t=>!done.includes(t));
 const scope=u.role==='area-director'?[u.area]:null,c1=coverage('tli1',scope),c2=coverage('tli2',scope);
 const next=upcoming.find(t=>(taskDaysUntil(t.date)??0)>=0);
 const pct=c=>c.total?Math.round(c.done/c.total*100):0;
 $i('tliKpis').innerHTML=[
  ['Next session',next?`<span class="v663-kpi-text">${H(next.name)}</span>`:'—',next?[pretty(next.date),whenLabel(next)].filter(Boolean).join(' · '):'Nothing scheduled','amber','calendar'],
  ['TLI 1 trained',`${c1.done}<small>/${c1.total}</small>`,`${pct(c1)}% of current officers`,'green','shield'],
  ['TLI 2 trained',`${c2.done}<small>/${c2.total}</small>`,`${pct(c2)}% of current officers`,'blue','readiness'],
  ['Sessions',`${done.filter(t=>t.status==='Completed').length}<small>/${tl.length}</small>`,'completed so far','blue','calendar']
 ].map(([label,value,sub,tone,icon])=>`<div class="tli-summary-card tone-${tone}"><div class="tli-summary-top"><div class="tli-summary-label">${label}</div><span class="tli-summary-icon">${typeof iconSVG==='function'?iconSVG(icon):''}</span></div><div class="tli-summary-value">${value}</div><div class="tli-summary-sub">${H(sub)}</div></div>`).join('');
 const heads=document.querySelectorAll('#tli .tli-section-head');
 if(heads[0])heads[0].innerHTML='<div><h2>Upcoming sessions</h2><div class="small">Open a session to change its details or record who attended.</div></div>';
 if(heads[1])heads[1].innerHTML='<div><h2>Completed sessions</h2><div class="small">Most recent first. Attendance here sets the TLI badges in Officer / Exco.</div></div>';
 $i('tliFocus').className='v663-list';$i('tliHistory').className='v663-list';
 $i('tliFocus').innerHTML=upcoming.length?upcoming.map(t=>tliCard(t,t===next)).join(''):'<div class="v663-empty">No upcoming sessions. Use “Add TLI session” to schedule one.</div>';
 $i('tliHistory').innerHTML=done.length?done.map(t=>tliCard(t,false)).join(''):'<div class="v663-empty">No completed sessions yet.</div>';
 const notice=$i('tliDataNotice');if(notice){notice.classList.toggle('show',fixed);notice.innerHTML=fixed?'<strong>TLI records tidied.</strong> Duplicate sessions were merged and saved.':'';}
}

/* ---------- Contest schedule ---------- */
function renderContestScheduleV663(){
 const box=$i('contestSchedule');if(!box)return;
 const u=user(),order={Area:1,Division:2,Club:3};
 const rows=roleScopedContests(u).sort((a,b)=>byDate(a,b)||(order[a.level]||9)-(order[b.level]||9));
 box.classList.add('v663-list');
 box.innerHTML=rows.length?rows.map(c=>{
  const ok=contestAllowed(c,u),checks=[['Venue',c.venueConfirmed],['Judges',c.judgesConfirmed],['Contestants',c.contestantsConfirmed],['Promotion',c.promoReady]];
  const place=[c.venue&&!/^tba$/i.test(c.venue)?c.venue:'',c.city].filter(Boolean).join(', ')||'Venue TBA';
  const dd=c.date?taskDaysUntil(c.date):null;
  const when=c.status==='Completed'?'':c.date?(dd<0?'Date has passed':dd===0?'Today':`In ${dd} days`):(c.targetWindow&&c.targetWindow!=='TBA'?'Planned: '+c.targetWindow:'Date not set');
  const time=c.start?(typeof tliTimeLabel==='function'?tliTimeLabel({start:c.start,end:c.end}):c.start)+' · ':'';
  return `<article class="v663-card">${dateBlock(c.date)}
   <div class="v663-main">
    <div class="v663-top"><span class="badge ${statusTone(c.status)}">${H(c.status||'Planning')}</span><span class="v663-pill">${H(c.level||'')} contest${c.coverage?' · '+H(c.coverage):''}</span>${when?`<span class="v663-when">${H(when)}</span>`:''}</div>
    <h3>${H(c.title)}</h3>
    <div class="v663-line">${H(time)}${H(place)}</div>
    <div class="v663-team"><div><span>Contest Chair</span><b>${H(c.chair||'Not assigned')}</b></div><div><span>Chief Judge</span><b>${H(c.chiefJudge||'Not assigned')}</b></div></div>
    <div class="v663-ready">${checks.map(([l,v])=>`<span class="${v?'ok':''}">${v?'✓':'○'} ${l}</span>`).join('')}</div>
   </div>
   <div class="v663-actions">${ok?`<button type="button" class="btn primary" onclick="editContest('${H(c.id)}')">Edit</button>`:'<span class="v663-when">Division context</span>'}</div>
  </article>`;}).join(''):'<div class="v663-empty">No contests scheduled yet.</div>';
}

/* ---------- install ---------- */
function install(){
 /* A full redraw rebuilds the tables and, at its end, reads the club form; park open editors in the page first,
    then put them back under their rows. */
 const baseRender=window.render;
 if(typeof baseRender==='function'&&!baseRender.__v664){
  const wrapped=function(){
   const open=[...PANELS.values()].filter(d=>d.__isOpen);
   open.forEach(unplace);
   try{return baseRender.apply(this,arguments);}
   finally{open.forEach(d=>{if(d.__isOpen)place(d,findAnchor(d.__anchorSel?document.querySelector(d.__anchorSel):null));});}
  };
  wrapped.__v664=true;window.render=wrapped;
 }
 window.v663OpenTli=openTli;
 window.editTli=id=>openTli(id);
 window.openTliEditorNew=()=>openTli(null);
 window.editContest=id=>openContest(id);
 window.v663NewContest=()=>openContest(null);
 window.editClub=id=>openClub(id);
 if(typeof saveInlineMemberEdit==='function')window.editMemberRecord=key=>openMember(key);
 if(typeof deleteOfficerRecord==='function'&&$i('officerForm'))window.editOfficerRecord=id=>openOfficer(id);
 if($i('tli')&&typeof reconcileTliDatabaseV252==='function')window.renderTlis=renderTlisV663;
 if($i('contestSchedule')&&typeof roleScopedContests==='function')window.renderContestSchedule=renderContestScheduleV663;
 ['tliEditor','contestLogisticsEditor','clubEditor'].forEach(id=>{const e=$i(id);if(e){e.open=false;e.classList.add('v663-retired');}});
 const sched=$i('contestSchedule');
 if(sched&&!$i('v663AddContest')){const head=sched.previousElementSibling;if(head&&head.classList.contains('section-title')){head.classList.add('v663-head-row');head.insertAdjacentHTML('beforeend','<button type="button" class="btn primary" id="v663AddContest" onclick="v663NewContest()">＋ Add contest</button>');}}
 const heroCopy=document.querySelector('#tli .tli-center-hero p');
 if(heroCopy)heroCopy.textContent='Every Division G officer training session in one place. Open a session to update its details or tick off which officers attended.';
 const me=$i('memberEditor');
 /* Members and clubs come from Toastmasters downloads (club roster, club list): no manual "add". Exco keeps one for seats that change between officer lists. */
 if(me){me.open=false;me.classList.add('v663-retired');}
 const xe=$i('excoEditor');if(xe){xe.open=false;xe.classList.add('v663-retired');}
 window.v663NewOfficer=()=>openOfficer(null,null);
 const xa=document.querySelector('#officers .directory-title-actions');if(xa&&!$i('v663AddOfficer'))xa.insertAdjacentHTML('afterbegin','<button class="btn primary" id="v663AddOfficer" type="button" onclick="v663NewOfficer()">＋ Add officer</button>');
 try{render();}catch(_){}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(install,0),{once:true});else install();
})();
