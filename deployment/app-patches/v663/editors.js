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
 text(id,label,val,o={}){return `<label class="v663-f ${o.wide?'wide':''} ${o.full?'full':''}"><span>${label}</span><input id="${id}" type="${o.type||'text'}" value="${H(val)}"${o.ph?` placeholder="${H(o.ph)}"`:''}${o.list?` list="${o.list}"`:''}${o.min!=null?` min="${o.min}"`:''}${o.req?' required':''} autocomplete="off"${o.type==='number'?' inputmode="numeric"':''}>${o.hint?`<small>${o.hint}</small>`:''}</label>`;},
 select(id,label,val,opts,o={}){return `<label class="v663-f ${o.wide?'wide':''}"><span>${label}</span><select id="${id}">${opts.map(x=>{const [v,t]=Array.isArray(x)?x:[x,x];return `<option value="${H(v)}"${String(v)===String(val??'')?' selected':''}>${H(t)}</option>`;}).join('')}</select>${o.hint?`<small>${o.hint}</small>`:''}</label>`;},
 seg(name,label,val,opts){if(val&&!opts.includes(val))opts=[...opts,val];return `<div class="v663-f full"><span>${label}</span><div class="v663-seg" role="radiogroup" aria-label="${H(label)}" data-name="${name}">${opts.map(x=>`<button type="button" role="radio" aria-checked="${x===val}" data-v="${H(x)}">${H(x)}</button>`).join('')}</div></div>`;},
 area(id,label,val,o={}){return `<label class="v663-f full"><span>${label}</span><textarea id="${id}" rows="${o.rows||3}"${o.ph?` placeholder="${H(o.ph)}"`:''}>${H(val)}</textarea></label>`;},
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
function makeDialog(id,formless){
 let d=$i(id);if(d)return d;
 d=document.createElement('dialog');d.id=id;d.className='v663-dlg';d.setAttribute('aria-labelledby',id+'Title');
 const tag=formless?'div':'form';
 d.innerHTML=`<${tag} class="v663-shell"${formless?'':' novalidate'}>
  <header class="v663-head"><div class="v663-head-copy"><div class="v663-kicker"></div><h2 class="v663-title" id="${id}Title"></h2><div class="v663-sub"></div></div><button type="button" class="v663-x" data-act="close" aria-label="Close">×</button></header>
  <div class="v663-picker"><label><span>Editing</span><select class="v663-pick" aria-label="Choose what to edit"></select></label></div>
  <nav class="v663-tabs" role="tablist" hidden></nav>
  <div class="v663-body"></div>
  <footer class="v663-foot"><button type="button" class="btn danger v663-del" data-act="delete" hidden>Delete</button><span class="v663-msg" role="status" aria-live="polite"></span><button type="button" class="btn ghost" data-act="close">Cancel</button><button type="submit" class="btn primary v663-save">Save</button></footer>
 </${tag}>`;
 document.body.appendChild(d);
 d.addEventListener('cancel',e=>{e.preventDefault();tryClose(d);});
 d.addEventListener('close',()=>document.documentElement.classList.remove('v663-lock'));
 d.addEventListener('mousedown',e=>{d.__downOnBackdrop=e.target===d;});
 d.addEventListener('click',e=>{
  if(e.target===d&&d.__downOnBackdrop){tryClose(d);return;}
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
 d.querySelector('.v663-pick').addEventListener('change',e=>{
  const want=e.target.value,prev=d.__pickValue??'';
  if(d.__dirty?.()&&!confirm('Discard your unsaved changes?')){e.target.value=prev;return;}
  d.__onPick?.(want);
 });
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
function tryClose(d){if(d.__dirty?.()&&!confirm('Discard your unsaved changes?'))return;d.close();}
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
 d.querySelector('.v663-picker').hidden=!(pick&&pick.length);
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
 if(!d.open){d.showModal();document.documentElement.classList.add('v663-lock');}
 d.querySelector('.v663-body').scrollTop=0;
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
 const fr=fixedRound(s),d=makeDialog('v663Editor');
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
 const d=makeDialog('v663Editor');
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
 ['Membership',['clubCurrentMembers','baseMembers','newMembers','renewedMembers','lostMembers','mar27Override']],
 ['Club activity',['dcpGoals','meetings','attendance','guests','conversions','educationAwards','officersTrained']],
 ['Paperwork and risk',['duesPaid','officerList','cspSubmitted','renewalStatus','suspensionRisk','suspensionReason']],
 ['Notes',['clubNotes']]
];
const CLUB_WIDE=new Set(['clubName','clubAliases','suspensionReason']);
const CLUB_FULL=new Set(['clubNotes']);
const CLUB_LABELS={mar27Override:'Secured for Mar 2027',officersTrained:'Officers trained (from TLI attendance)',clubAliases:'Other names'};
function clubDialog(){
 const form=$i('clubForm');if(!form)return null;
 let d=$i('v663ClubDlg');if(d&&d.contains(form))return d;
 d=makeDialog('v663ClubDlg',true);
 const body=d.querySelector('.v663-body');
 const grid=form.querySelector('.form-grid');
 const used=new Set();
 let html='';
 const sections=CLUB_SECTIONS.map(([title,ids])=>{const sec=document.createElement('section');sec.className='v663-sec';sec.innerHTML=`<h3>${title}</h3><div class="v663-grid"></div>`;const g=sec.querySelector('.v663-grid');
  for(const id of ids){const el=$i(id),f=el?.closest('.field');if(!f||used.has(f))continue;used.add(f);g.appendChild(f);f.classList.add('v663-field');if(CLUB_WIDE.has(id))f.classList.add('wide');if(CLUB_FULL.has(id))f.classList.add('full');if(CLUB_LABELS[id]){const l=f.querySelector('label');if(l)l.textContent=CLUB_LABELS[id];}}
  return sec;});
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
 const d=clubDialog();if(!d)return;
 const club=id?(db.clubs||[]).find(c=>c.id===id):null;
 if(id&&!club)return;
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
  pick:[['','＋ New club'],...clubs.map(c=>[c.id,`${c.area?c.area+' · ':''}${c.name}`])],pickValue:club?club.id:'',body:null,del:!!club,saveLabel:'Save club'});
 syncSwitches(d);
 d.__onInput=el=>{const b=el?.closest?.('.v663-switch');if(b){const sel=$i(b.dataset.for);if(sel){sel.value=b.getAttribute('aria-pressed')==='true'?'true':'false';sel.dispatchEvent(new Event('change',{bubbles:true}));}}};
 d.__onPick=v=>openClub(v||null);
 d.__onDelete=()=>{if(!club)return;deleteClub(club.id);if(!(db.clubs||[]).some(c=>c.id===club.id)){d.__dirty=null;d.close();toast('Club deleted');}};
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
 window.v663OpenTli=openTli;
 window.editTli=id=>openTli(id);
 window.openTliEditorNew=()=>openTli(null);
 window.editContest=id=>openContest(id);
 window.v663NewContest=()=>openContest(null);
 window.editClub=id=>openClub(id);
 window.v663NewClub=()=>openClub(null);
 if($i('tli')&&typeof reconcileTliDatabaseV252==='function')window.renderTlis=renderTlisV663;
 if($i('contestSchedule')&&typeof roleScopedContests==='function')window.renderContestSchedule=renderContestScheduleV663;
 ['tliEditor','contestLogisticsEditor','clubEditor'].forEach(id=>{const e=$i(id);if(e){e.open=false;e.classList.add('v663-retired');}});
 const sched=$i('contestSchedule');
 if(sched&&!$i('v663AddContest')){const head=sched.previousElementSibling;if(head&&head.classList.contains('section-title')){head.classList.add('v663-head-row');head.insertAdjacentHTML('beforeend','<button type="button" class="btn primary" id="v663AddContest" onclick="v663NewContest()">＋ Add contest</button>');}}
 const heroCopy=document.querySelector('#tli .tli-center-hero p');
 if(heroCopy)heroCopy.textContent='Every Division G officer training session in one place. Open a session to update its details or tick off which officers attended.';
 const ce=$i('clubEditor');
 if(ce&&!$i('v663AddClub'))ce.insertAdjacentHTML('beforebegin','<div class="v663-addbar"><button type="button" class="btn primary" id="v663AddClub" onclick="v663NewClub()">＋ Add club</button></div>');
 try{render();}catch(_){}
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(install,0),{once:true});else install();
})();
