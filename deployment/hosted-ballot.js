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
})();
