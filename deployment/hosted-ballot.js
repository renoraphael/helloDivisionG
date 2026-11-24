(function(){
 'use strict';
 const categories={
  prepared:'Prepared Speaker',evaluation:'Evaluation',topics:'Table Topics'
 };
 const drafts=new Map();
 const working=new Set();
 const messages=new Map();

 function shareURL(token){
  const url=new URL('ballot.html',location.href);
  url.hash='vote='+token;
  return url.href;
 }
 function element(tag,text){
  const node=document.createElement(tag);
  node.textContent=text;
  return node;
 }
 function candidateChoices(record){
  return Object.fromEntries(Object.keys(categories).map(category=>[category,
   (meetingBallotCategoryCandidates(record,category)||[])
    .filter(candidate=>candidate.timing?.qualified!==false)
    .map(candidate=>({id:String(candidate.id),name:String(candidate.name)}))
  ]));
 }
 async function manage(record,action){
  if(!record||working.has(record.id))return;
  working.add(record.id);
  messages.set(record.id,'Contacting the ballot server…');
  window.renderMeetingBallotPublicSession(record);
  try{
   const isPublish=action==='publish';
   const state=await HDGCloud.manageBallot(record.id,action,
    isPublish?(record.clubName||'Toastmasters')+' ballot':undefined,
    isPublish?candidateChoices(record):undefined);
   drafts.set(record.id,state);
   messages.set(record.id,state?'':'Publish this meeting’s ballot to create its voting link.');
   return state;
  }catch(error){
   messages.set(record.id,error.message);
  }finally{
   working.delete(record.id);
   if(communityAgendaCurrentRecord()?.id===record.id)window.renderMeetingBallotPublicSession(record);
  }
 }
 window.meetingBallotPublish=()=>manage(communityAgendaCurrentRecord(),'publish');
 window.meetingBallotCloseVoting=()=>manage(communityAgendaCurrentRecord(),'close');
 window.meetingBallotOpenPublicPreview=function(){
  const record=communityAgendaCurrentRecord();
  if(!record)return;
  const state=drafts.get(record.id);
  if(state?.open){window.open(shareURL(state.token),'_blank','noopener');return;}
  messages.set(record.id,'Publish the ballot or refresh its link first.');
  window.renderMeetingBallotPublicSession(record);
 };
 window.renderMeetingBallotPublicSession=function(record){
  const host=document.getElementById('meetingBallotPublicSession');
  if(!host)return;
  if(!record){host.textContent='Select a meeting to publish its ballot.';return;}
  const state=drafts.get(record.id);
  const instructions='Publish the candidate names to a voting link. Anyone with the link can vote while it’s open.';
  const status=element('p',messages.get(record.id)||instructions);
  status.setAttribute('role','status');
  const refresh=element('button','Refresh link & tally');
  refresh.type='button';
  refresh.className='btn ghost';
  refresh.disabled=working.has(record.id);
  refresh.onclick=()=>manage(record,'status');
  host.replaceChildren(status,refresh);
  if(!state)return;
  const count=element('p',(state.open?'Voting open':'Voting closed')+' · '+state.responses+' link votes');
  host.append(count);
  if(state.open){
   const url=shareURL(state.token);
   const link=element('a','Open voting link');
   link.href=url;
   link.target='_blank';
   link.rel='noopener noreferrer';
   const copy=element('button','Copy voting link');
   copy.type='button';
   copy.className='btn ghost';
   copy.onclick=async()=>{
    try{await navigator.clipboard.writeText(url);status.textContent='Voting link copied.';}
    catch(_){window.prompt('Copy this voting link',url);}
   };
   const actions=document.createElement('div');
   actions.append(link,' ',copy);
   host.append(actions);
  }
  const tally=document.createElement('details');
  tally.append(element('summary','Private link tally'));
  for(const [category,label] of Object.entries(categories)){
   tally.append(element('h4',label));
   const list=document.createElement('ul');
   for(const candidate of state.choices[category]){
    list.append(element('li',candidate.name+' · '+(state.counts[category]?.[candidate.id]||0)));
   }
   list.append(element('li','No favorite · '+(state.counts[category]?.['']||0)));
   tally.append(list);
  }
  host.append(tally);
 };
 // The published vote page uses its own server-backed form.
 window.meetingBallotSubmitPublic=window.meetingBallotOpenPublicPreview;

 // v659: votes cast on phones through the voting link count together with ballots entered on this device,
 // in the Ballot Counter's private results and in the result slides. Matched by candidate name, so a later
 // change to the candidate order cannot move votes to the wrong person. Disqualified speakers stay at zero.
 const norm=value=>String(value||'').toLowerCase().replace(/\s+/g,' ').trim();
 function linkCounts(record,category){
  const state=record&&drafts.get(record.id);
  if(!state)return null;
  const names=new Map((state.choices?.[category]||[]).map(choice=>[String(choice.id),choice.name]));
  const out=new Map();
  for(const [id,count] of Object.entries(state.counts?.[category]||{})){
   const name=names.get(String(id));
   if(id&&name)out.set(norm(name),(out.get(norm(name))||0)+Number(count||0));
  }
  return out;
 }
 const baseTally=window.meetingBallotTallyFor;
 if(typeof baseTally==='function'){
  window.meetingBallotTallyFor=function(record,category){
   const rows=baseTally.apply(this,arguments),extra=linkCounts(record,category);
   if(!extra||!extra.size)return rows;
   return rows.map(row=>{
    const add=row.timing?.qualified===false?0:(extra.get(norm(row.name))||0);
    return add?{...row,count:row.count+add,linkCount:add}:row;
   }).sort((a,b)=>{
    const aOut=a.timing?.qualified===false,bOut=b.timing?.qualified===false;
    if(aOut!==bOut)return aOut?1:-1;
    return b.count-a.count||String(a.name).localeCompare(String(b.name));
   });
  };
 }
 const baseCard=window.meetingBallotTallyCard;
 if(typeof baseCard==='function'){
  window.meetingBallotTallyCard=function(record){
   const html=baseCard.apply(this,arguments),state=record&&drafts.get(record.id);
   if(!state||!state.responses)return html;
   const here=agendaMeetingToolData(record)?.ballots?.length||0;
   return html.replace(/<strong>\d+ ballots entered<\/strong>/,
    '<strong>'+(here+state.responses)+' ballots entered</strong><small>'+here+' on this device · '+state.responses+' by voting link</small>');
  };
 }
 let refreshing=false,rerendering=false;
 async function refreshLinkVotes(){
  const record=communityAgendaCurrentRecord();
  if(!record||refreshing||working.has(record.id)||!window.HDGCloud?.manageBallot)return;
  refreshing=true;
  try{
   const state=await HDGCloud.manageBallot(record.id,'status');
   if(state)drafts.set(record.id,state);else drafts.delete(record.id);
  }catch(_){return;}
  finally{refreshing=false;}
  if(communityAgendaCurrentRecord()?.id!==record.id)return;
  rerendering=true;
  try{
   if(typeof renderMeetingBallot==='function')renderMeetingBallot(record);
   try{if(typeof syncAgendaPresentationResults==='function')syncAgendaPresentationResults(record);}
   catch(error){console.warn('Result slides not refreshed',error);}
  }finally{rerendering=false;}
 }
 const baseToggle=window.meetingBallotTogglePrivateResults;
 if(typeof baseToggle==='function'){
  // Every ballot render re-applies this toggle, so refresh only when the panel goes from hidden to shown.
  window.meetingBallotTogglePrivateResults=function(show){
   const wasHidden=document.getElementById('meetingBallotResultsPrivate')?.hidden!==false;
   const out=baseToggle.apply(this,arguments);
   if(show&&wasHidden&&!rerendering)refreshLinkVotes();
   return out;
  };
 }
 // While the private results are open, pick up new phone votes every 10 seconds.
 setInterval(()=>{
  const panel=document.getElementById('meetingBallotResultsPrivate');
  if(panel&&!panel.hidden&&!document.hidden)refreshLinkVotes();
 },10000);
 // "Refresh link & tally" also updates the private results.
 const baseManage=manage;
 window.meetingBallotRefreshLinkVotes=refreshLinkVotes;
 const basePublic=window.renderMeetingBallotPublicSession;
 window.renderMeetingBallotPublicSession=function(record){
  basePublic.apply(this,arguments);
  const button=[...(document.getElementById('meetingBallotPublicSession')?.querySelectorAll('button')||[])].find(b=>b.textContent==='Refresh link & tally');
  if(button)button.onclick=async()=>{await baseManage(record,'status');refreshLinkVotes();};
 };
})();
