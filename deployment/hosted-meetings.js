(function(){
 'use strict';
 /* v660: every meeting is saved online under its meeting code (agenda-<club>-<date>, deployment/schema/015).
    The agenda, the timer's times, the typed-in ballots and the Table Topics names are separate parts, so the slide
    operator, the timer and the ballot counter can save at the same time from their own accounts. Leaders save every
    part; a member who holds a role in that meeting's agenda saves only that role's part (the server checks this).
    A copy that arrives late is set aside on the server and on this device, never merged over newer work.
    From v661 (schema 016) every role taker fixes their own agenda line, the Toastmaster of the Meeting edits the whole
    agenda, and club members put themselves into empty roles and step in on the meeting day; each meeting arrives with
    the reader's rights, so the app sends only the parts that count. Used by the Leader and the Member builds; no
    member records are stored here. */
 const cloud=window.HDGCloud;
 if(!cloud||typeof cloud.saveMeeting!=='function'||typeof agendaStore!=='function'||typeof agendaMeetingToolData!=='function')return;
 const FIELDS=['agenda','timer_log','ballots','topics'];
 const ROLE_LABEL={timer:'Timer',ballotCounter:'Ballot Counter',ttm:'Table Topics Master',tom:'Toastmaster of the Meeting',
  ge:'General Evaluator',grammarian:'Grammarian',ahCounter:'Ah-Counter',tableTopicsEvaluator:'Table Topics Evaluator',saa:'Sergeant at Arms',
  president:'presiding officer',actingPresident:'acting President',actingSaa:'acting Sergeant at Arms',guestGreeter:'Guest Greeter',
  registration:'registration host',documentation:'documentation host',speaker:'a speaker',evaluator:'an evaluator'};
 const ID=/^agenda-0*[1-9][0-9]*-[A-Za-z0-9-]{1,90}$/;
 const DAY=/^\d{4}-\d{2}-\d{2}$/;
 const WINDOW_DAYS=120;
 let state=null,stateKey='',busy=false,again=false,timer=0,forceServer=false,lastError='';
 const server=new Map();      // meeting id -> this account's rights from the last list (deployment/schema/016)
 const cooldown=new Map();    // meeting id -> time before which an own-line agenda is not resent after a trimmed save
 const denied=new Map();      // meeting id -> hash of the patch the server refused (not retried until it changes)

 // Key order is not kept by the database, so parts are compared with sorted keys.
 function canonical(value){
  if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
  if(value&&typeof value==='object')return '{'+Object.keys(value).filter(k=>value[k]!==undefined).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
  return JSON.stringify(value===undefined?null:value);
 }
 function hash(value){
  const text=canonical(value);
  let h=2166136261;
  for(let i=0;i<text.length;i++){h^=text.charCodeAt(i);h=Math.imul(h,16777619);}
  return (h>>>0).toString(36)+'.'+text.length;
 }
 function today(offset=0){const d=new Date();d.setDate(d.getDate()+offset);return d.toISOString().slice(0,10);}
 function empty(value){return value==null||(Array.isArray(value)?!value.length:typeof value==='object'&&!Object.keys(value).length);}
 function load(){
  const account=cloud.accountId&&cloud.accountId();
  if(!account)return false;
  const key='hdg.meetings.v1.'+account;
  if(stateKey===key&&state)return true;
  stateKey=key;
  try{state=JSON.parse(localStorage.getItem(key)||'null');}catch(_){state=null;}
  if(!state||typeof state!=='object'||typeof state.m!=='object')state={m:{}};
  return true;
 }
 function store(){try{localStorage.setItem(stateKey,JSON.stringify(state));}catch(_){}}
 function setAside(id,field,value){
  // The local copy that lost to newer online work stays on this device (last 30), never silently dropped.
  try{
   const key='hdg.meetings.setaside.v1';
   const list=JSON.parse(localStorage.getItem(key)||'[]');
   list.unshift({meetingId:id,field,at:new Date().toISOString(),value});
   localStorage.setItem(key,JSON.stringify(list.slice(0,30)));
  }catch(_){}
 }
 function agendaCopy(record){
  const copy=JSON.parse(JSON.stringify(record));
  delete copy.warnings;
  return copy;
 }
 function local(record){
  const tools=agendaMeetingToolData(record,false)||{};
  return {agenda:agendaCopy(record),timer_log:tools.timerLog||[],ballots:tools.ballots||[],topics:tools.topics||[]};
 }
 function candidates(){
  const from=today(-WINDOW_DAYS);
  return agendaStore().filter(r=>r&&ID.test(String(r.id||''))&&DAY.test(String(r.meetingDate||''))&&r.meetingDate>=from);
 }
 function allowedFields(id){
  const rights=server.get(id);
  if(!rights)return FIELDS;                          // not saved online yet: only a leader can create it (the server decides)
  return FIELDS.filter(f=>f==='agenda'?rights.agenda&&rights.agenda!=='none':f==='ballots'?rights.ballots&&rights.ballots!=='none':rights[f]===true);
 }
 function canSeeBallots(id){const rights=server.get(id);return !rights||rights.seeBallots===true;}
 function canMarkDownload(id){const rights=server.get(id);return !rights||rights.downloaded===true;}
 function persistQuietly(){
  try{if(typeof persistLocalState==='function')persistLocalState();}catch(error){console.warn('Meeting copy not kept on this device',error);}
 }
 function editing(){
  const a=document.activeElement;
  return !!a&&(a.tagName==='TEXTAREA'||(a.tagName==='INPUT'&&!/^(button|checkbox|radio|submit)$/i.test(a.type))||a.isContentEditable);
 }
 function rerender(ids){
  const current=typeof communityAgendaCurrentRecord==='function'?communityAgendaCurrentRecord():null;
  const calls=[
   ()=>typeof renderMeetingToolsMeetingSelector==='function'&&renderMeetingToolsMeetingSelector(),
  ];
  if(current&&ids.has(current.id)){
   calls.push(
    ()=>typeof renderCommunityAgendaRecord==='function'&&renderCommunityAgendaRecord(),
    ()=>typeof renderMeetingToolsMeetingSummary==='function'&&renderMeetingToolsMeetingSummary(current),
    ()=>typeof renderMeetingTimerLog==='function'&&renderMeetingTimerLog(current),
    ()=>typeof renderMeetingBallot==='function'&&renderMeetingBallot(current),
    ()=>typeof syncAgendaPresentationResults==='function'&&syncAgendaPresentationResults(current));
  }
  for(const call of calls){try{call();}catch(error){console.warn('Meeting view not refreshed',error);}}
  note();
 }
 function writeField(record,field,value){
  if(field==='agenda'){
   const id=record.id;
   for(const key of Object.keys(record))if(!(key in value))delete record[key];
   Object.assign(record,JSON.parse(JSON.stringify(value)),{id});
   try{if(typeof agendaValidateMeeting==='function')record.warnings=agendaValidateMeeting(record);}catch(_){}
   return;
  }
  const tools=agendaMeetingToolData(record,true);
  const key=field==='timer_log'?'timerLog':field;
  tools[key]=JSON.parse(JSON.stringify(value||[]));
 }
 // Bring online meetings into this device. Online work wins over a copy that was not saved online first.
 function adopt(rows,{force=false}={}){
  const changed=new Set();
  const records=agendaStore();
  const current=typeof communityAgendaCurrentRecord==='function'?communityAgendaCurrentRecord():null;
  for(const row of rows||[]){
   const id=String(row.meetingId||'');
   if(!ID.test(id))continue;
   server.set(id,row.rights&&typeof row.rights==='object'?row.rights:{leader:true,agenda:'full',timer_log:true,topics:true,ballots:'replace',seeBallots:true,downloaded:true,roles:[]});
   const st=state.m[id]||(state.m[id]={u:'',h:{}});
   if(!force&&st.u===row.updatedAt)continue;
   // Leave the meeting someone is typing into; the next check picks it up.
   if(current&&current.id===id&&editing())continue;
   let record=records.find(r=>r&&r.id===id)||null;
   const online={agenda:row.agenda||{},timer_log:row.timerLog||[],ballots:row.ballots||[],topics:row.topics||[]};
   if(!record){
    if(empty(online.agenda))continue;
    record=Object.assign(JSON.parse(JSON.stringify(online.agenda)),{id});
    if(!record.meetingDate&&row.meetingDate)record.meetingDate=row.meetingDate;
    records.push(record);
   }
   const mine=local(record);
   for(const field of FIELDS){
    if(field==='ballots'&&!canSeeBallots(id))continue;
    if(empty(online[field])&&!empty(mine[field]))continue;   // nothing online yet: this device's copy is sent next
    const onlineHash=hash(online[field]),mineHash=hash(mine[field]);
    if(onlineHash===mineHash){st.h[field]=onlineHash;continue;}
    const changedHere=st.u&&!force?mineHash!==st.h[field]:!empty(mine[field]);
    if(changedHere)setAside(id,field,mine[field]);
    writeField(record,field,online[field]);
    st.h[field]=onlineHash;
    changed.add(id);
   }
   st.u=row.updatedAt;
  }
  store();
  if(changed.size){persistQuietly();rerender(changed);}
  return changed;
 }
 async function pull(){
  const rows=await cloud.listMeetings(null,today(-WINDOW_DAYS),null);
  const force=forceServer;forceServer=false;
  adopt(Array.isArray(rows)?rows:[],{force});
 }
 async function push(){
  for(const record of candidates()){
   const id=record.id,st=state.m[id]||(state.m[id]={u:'',h:{}});
   const mine=local(record),allowed=allowedFields(id),patch={},hashes={};
   for(const field of allowed){
    if(field==='agenda'&&server.get(id)?.agenda==='own'&&(cooldown.get(id)||0)>Date.now())continue;
    const h=hash(mine[field]);
    if(h!==st.h[field]&&!(empty(mine[field])&&!st.h[field])){patch[field]=mine[field];hashes[field]=h;}
   }
   if(st.dl&&!st.dlSent&&canMarkDownload(id))patch.downloaded=true;
   if(!Object.keys(patch).length)continue;
   const patchHash=hash(patch);
   if(denied.get(id)===patchHash)continue;
   if(patch.agenda&&JSON.stringify(patch.agenda).length>350000){lastError='This meeting is too large to save online.';continue;}
   let result;
   try{result=await cloud.saveMeeting(id,record.meetingDate,patch,st.u||null);}
   catch(error){
    if(error.code==='42501'||error.status===403){denied.set(id,patchHash);continue;}
    throw error;
   }
   denied.delete(id);
   const late=Array.isArray(result?.set_aside)?result.set_aside:[];
   for(const field of Object.keys(hashes))if(!late.includes(field))st.h[field]=hashes[field];
   if(patch.downloaded)st.dlSent=true;
   if(result?.updated_at&&!late.length)st.u=result.updated_at;
   if(!server.has(id))server.set(id,{leader:true,agenda:'full',timer_log:true,topics:true,ballots:'replace',seeBallots:true,downloaded:true,roles:[]});
   // An agenda change that was not this person's to make comes back as "trimmed": show the stored agenda, keep theirs aside.
   const trimmed=(Array.isArray(result?.trimmed)?result.trimmed:[]).filter(f=>f!=='ballots');
   if(trimmed.length)cooldown.set(id,Date.now()+20000);
   store();
   if(late.length||trimmed.length){
    // Someone saved newer work first, or part of the change was not this person's: show the stored copy, keep this one aside.
    const rows=await cloud.listMeetings(null,null,id);
    st.u='';
    adopt(rows,{force:false});
   }
  }
 }
 async function run(){
  if(!load())return;
  if(busy){again=true;return;}
  busy=true;
  try{
   do{again=false;await pull();await push();}while(again);
   lastError='';
  }catch(error){lastError=error.status===401?'Sign in again to save meetings online.':'Meetings are saved on this device; they will be saved online when the connection is back.';}
  finally{busy=false;note();}
 }
 function soon(delay=1500){clearTimeout(timer);timer=setTimeout(run,delay);}

 // Every save on this device schedules an online save of the changed meeting parts.
 const basePersist=window.persistLocalState;
 if(typeof basePersist==='function'){
  window.persistLocalState=function(){
   const out=basePersist.apply(this,arguments);
   if(busy)again=true;else soon();
   return out;
  };
 }
 // The first agenda download marks the meeting as real (a beta or near-final agenda).
 const baseDownload=window.downloadCommunityAgendaPDFV413;
 if(typeof baseDownload==='function'){
  window.downloadCommunityAgendaPDFV413=async function(){
   const record=typeof communityAgendaCurrentRecord==='function'?communityAgendaCurrentRecord():null;
   const out=await baseDownload.apply(this,arguments);
   if(record&&ID.test(record.id)&&load()){
    const st=state.m[record.id]||(state.m[record.id]={u:'',h:{}});
    if(!st.dl){st.dl=true;store();}
    soon(200);
   }
   return out;
  };
 }
 // An older shared copy arriving through the Leader sync never wins over a saved meeting.
 if(Array.isArray(cloud.afterRemoteApply))cloud.afterRemoteApply.push(()=>{forceServer=true;soon(300);});

 // Meeting Tools: say what this account saves online for the selected meeting.
 function note(){
  const summary=document.getElementById('meetingToolsMeetingSummary');
  if(!summary)return;
  let box=document.getElementById('hdgMeetingShareNote');
  if(!box){box=document.createElement('p');box.id='hdgMeetingShareNote';box.className='small';box.setAttribute('role','status');summary.after(box);}
  const record=typeof communityAgendaCurrentRecord==='function'?communityAgendaCurrentRecord():null;
  let text='';
  if(lastError)text=lastError;
  else if(record&&ID.test(record.id)){
   const rights=server.get(record.id);
   if(rights&&rights.leader)text='Saved online for this meeting. Everyone running it sees the same agenda, times and ballots.';
   else if(rights&&(rights.agenda!=='none'||rights.timer_log||rights.ballots!=='none')){
    const roles=(rights.roles||[]).map(r=>ROLE_LABEL[r]||r);
    const who=roles.length?'You are '+roles.map(r=>/^(a|an|the|acting) /.test(r)?r:'the '+r).join(' and ')+' in this meeting.':'You are a member of this club.';
    const can=[];
    if(rights.agenda==='full')can.push('change this meeting’s agenda');
    else if(rights.agenda==='own')can.push('fix your own agenda line or put yourself into an empty role or a new speaker line');
    if(rights.timer_log)can.push('save timer times and Table Topics names');
    if(rights.ballots==='replace')can.push('enter ballots and see the results');
    else if(rights.ballots==='append')can.push('add ballots (the results stay with the Ballot Counter and the Toastmaster)');
    text=who+' You can '+can.join(', ')+'. Saved online for everyone running this meeting; anything else you change stays on this device.';
   }
   else if(rights||denied.has(record.id))text='This meeting stays on this device. Only the club’s officers, its members and that meeting’s role takers save it online.';
  }
  box.textContent=text;
  box.hidden=!text;
 }
 const baseSummary=window.renderMeetingToolsMeetingSummary;
 if(typeof baseSummary==='function'){
  window.renderMeetingToolsMeetingSummary=function(){const out=baseSummary.apply(this,arguments);note();return out;};
 }
 const baseTools=window.renderAgendaMeetingTools;
 if(typeof baseTools==='function'){
  window.renderAgendaMeetingTools=function(){const out=baseTools.apply(this,arguments);note();return out;};
 }
 document.addEventListener('change',event=>{
  if(event.target&&/^(meetingToolsMeetingSelect|agendaMeetingSelect|agendaImportClub)$/.test(event.target.id||''))setTimeout(note,0);
 });
 document.addEventListener('click',event=>{
  if(event.target?.closest?.('[data-community-panel="meetingTools"]'))setTimeout(note,0);
 });
 // Some app paths redraw Meeting Tools without the hooks above; keep the note current while it is on screen.
 let noted='';
 setInterval(()=>{
  const summary=document.getElementById('meetingToolsMeetingSummary');
  if(!summary||document.hidden||!summary.offsetParent)return;
  const id=(typeof communityAgendaCurrentRecord==='function'?communityAgendaCurrentRecord()?.id:'')||'';
  const box=document.getElementById('hdgMeetingShareNote');
  if(id!==noted||!box||box.previousElementSibling!==summary){noted=id;note();}
 },1500);

 // Check for other people's saves every 30 seconds, when the page comes back, and when the connection returns.
 const start=()=>{if(load())run();else setTimeout(start,2000);};
 setTimeout(start,1500);
 setInterval(()=>{if(!document.hidden)run();},30000);
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)soon(300);});
 window.addEventListener('online',()=>soon(300));
 window.HDGMeetings={run,state:()=>state,rights:id=>server.get(id)||null,roles:id=>server.get(id)?.roles||null};
})();
