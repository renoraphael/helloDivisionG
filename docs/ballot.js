'use strict';

/* Meeting ballot. Works with a weak or lost signal (project/DISTRICT_PLAN.md rule 24):
   - once opened, the ballot is kept on this phone, so the page reopens without signal (ballot-sw.js keeps the page files);
   - a vote made without signal is kept on this phone and sent automatically when the signal returns;
   - each vote carries this browser's ID, so a vote sent twice is counted once. */
(async function(){
 const token=new URLSearchParams(location.hash.slice(1)).get('vote');
 const form=document.getElementById('ballot-form');
 const status=document.getElementById('ballot-status');
 const title=document.getElementById('ballot-title');
 if('serviceWorker' in navigator&&window.isSecureContext){
  try{navigator.serviceWorker.register('ballot-sw.js',{scope:'./ballot'}).catch(()=>{});}catch(_){}
 }
 if(!token||!/^([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/i.test(token)){
  status.textContent='This ballot link is incomplete. Ask the meeting host for the full link.';
  return;
 }
 const storageKey='hdg.vote.'+token;
 const get=k=>{try{return localStorage.getItem(storageKey+k);}catch(_){return null;}};
 const put=(k,v)=>{try{v===null?localStorage.removeItem(storageKey+k):localStorage.setItem(storageKey+k,v);}catch(_){}};
 const offline=error=>!error||error.status===undefined||error.status===0||error.status>=500;
 let browserId=get('')||crypto.randomUUID();
 put('',browserId);
 const received=()=>{
  put('.received','true');put('.pending',null);
  form.hidden=true;
  title.textContent='Vote received';
  status.textContent='Your choices have been recorded.';
 };
 if(get('.received')){
  title.textContent='Vote received';
  status.textContent='This browser has already submitted a vote for this ballot.';
  return;
 }
 let retryTimer=null;
 async function sendPending(){
  const pending=get('.pending');
  if(!pending)return;
  try{
   await HDGCloud.castBallot(token,browserId,JSON.parse(pending));
   clearInterval(retryTimer);received();
  }catch(error){
   if(offline(error)){
    title.textContent='Vote saved on this phone';
    status.textContent='No signal right now. Your vote will be sent automatically when the signal returns. Keep this page open.';
   }else{
    clearInterval(retryTimer);put('.pending',null);
    title.textContent='Vote not counted';
    status.textContent=error.message||'Voting is closed or this link is invalid.';
   }
  }
 }
 function keepTrying(){
  if(retryTimer)return;
  retryTimer=setInterval(sendPending,15000);
  window.addEventListener('online',sendPending);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)sendPending();});
 }
 if(get('.pending')){
  title.textContent='Sending your saved vote…';
  status.textContent='';
  keepTrying();
  await sendPending();
  return;
 }
 let ballot;
 try{
  ballot=await HDGCloud.openBallot(token);
  if(ballot)put('.ballot',JSON.stringify(ballot));else put('.ballot',null);
 }catch(error){
  try{ballot=JSON.parse(get('.ballot')||'null');}catch(_){ballot=null;}
  if(!ballot){
   status.textContent='Could not reach the ballot. Check your connection and refresh.';
   return;
  }
 }
 if(!ballot){
  status.textContent='Voting is closed or this link is invalid.';
  return;
 }
 title.textContent=ballot.title;
 status.textContent='Choose one option in each category.';
 for(const [key,label] of [
  ['prepared','Prepared Speaker'],['evaluation','Evaluation'],['topics','Table Topics']
 ]){
  const field=document.createElement('fieldset');
  const legend=document.createElement('legend');
  legend.textContent=label;
  field.append(legend);
  for(const choice of [...ballot.choices[key],{id:'',name:'No favorite'}]){
   const option=document.createElement('label');
   const input=document.createElement('input');
   input.type='radio';
   input.name=key;
   input.value=choice.id;
   input.required=true;
   option.append(input,choice.name);
   field.append(option);
  }
  form.append(field);
 }
 const submit=document.createElement('button');
 submit.type='submit';
 submit.textContent='Submit vote';
 form.append(submit);
 form.hidden=false;
 form.onsubmit=async event=>{
  event.preventDefault();
  submit.disabled=true;
  status.textContent='Submitting your vote…';
  const choices=Object.fromEntries(new FormData(form));
  try{
   await HDGCloud.castBallot(token,browserId,choices);
   received();
  }catch(error){
   if(offline(error)){
    put('.pending',JSON.stringify(choices));
    form.hidden=true;
    keepTrying();
    title.textContent='Vote saved on this phone';
    status.textContent='No signal right now. Your vote will be sent automatically when the signal returns. Keep this page open.';
   }else{
    status.textContent=error.message;
    submit.disabled=false;
   }
  }
 };
})();
