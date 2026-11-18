'use strict';

(async function(){
 const token=new URLSearchParams(location.hash.slice(1)).get('vote');
 const form=document.getElementById('ballot-form');
 const status=document.getElementById('ballot-status');
 const title=document.getElementById('ballot-title');
 if(!token||!/^([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/i.test(token)){
  status.textContent='This ballot link is incomplete. Ask the meeting host for the full link.';
  return;
 }
 let ballot;
 try{
  ballot=await HDGCloud.openBallot(token);
 }catch(_){
  status.textContent='Could not reach the ballot. Check your connection and refresh.';
  return;
 }
 if(!ballot){
  status.textContent='Voting is closed or this link is invalid.';
  return;
 }
 const storageKey='hdg.vote.'+token;
 let browserId=crypto.randomUUID();
 try{
  browserId=localStorage.getItem(storageKey)||browserId;
  localStorage.setItem(storageKey,browserId);
  if(localStorage.getItem(storageKey+'.received')){
   title.textContent='Vote received';
   status.textContent='This browser has already submitted a vote for this ballot.';
   return;
  }
 }catch(_){}
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
  try{
   await HDGCloud.castBallot(token,browserId,Object.fromEntries(new FormData(form)));
   try{localStorage.setItem(storageKey+'.received','true');}catch(_){}
   form.hidden=true;
   title.textContent='Vote received';
   status.textContent='Your choices have been recorded.';
  }catch(error){
   status.textContent=error.message;
   submit.disabled=false;
  }
 };
})();
