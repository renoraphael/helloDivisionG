/* No service key or member records belong in this adapter. */
(function(global){
'use strict';
const CONFIG={url:'https://bhbgusdxqbjwsdlzhurb.supabase.co',key:'sb_publishable_73Y-5z5ao1d97jUibxC97g_AMmmaiXh'};
function shared(payload){
 const out=JSON.parse(JSON.stringify({updated:payload.updated,settings:payload.settings||{},database:payload.database}));
 if(out.database?.meta)for(const key of ['revision','lastSavedAt','storageModel'])delete out.database.meta[key];
 return out;
}
function signature(payload){const value=shared(payload);delete value.updated;return JSON.stringify(value);}
class SyncQueue {
 constructor({send,persist,status,requestId}){Object.assign(this,{send,persist,status,requestId});this.revision=0;this.baseline='';this.pending=null;this.inflight=null;this.saving=false;this.conflict=false;}
 reset(revision,payload){this.revision=revision;this.baseline=signature(payload);this.pending=null;this.inflight=null;this.conflict=false;}
 async enqueue(payload){
  const snapshot=shared(payload);
  // If a request is in flight, retain a reversal to its previous value too.
  if(!this.saving&&!this.pending&&signature(snapshot)===this.baseline)return;
  this.pending=snapshot;await this.persist(this.pending);
  this.status('Saved on this device; waiting to sync.');
 }
 async flush(){
  if(this.saving||this.conflict||(!this.pending&&!this.inflight))return;
  this.saving=true;
  try{
   while((this.pending||this.inflight)&&!this.conflict){
    if(!this.inflight){
     const snapshot=this.pending;this.pending=null;
     if(signature(snapshot)===this.baseline){await this.persist(null);continue;}
     this.inflight={payload:snapshot,revision:this.revision,id:this.requestId()};
    }
    const job=this.inflight;
    const result=await this.send(job);
    this.revision=Number(result.revision);this.baseline=signature(job.payload);this.inflight=null;
    await this.persist(this.pending);
   }
   this.status('Synced · revision '+this.revision);
  }catch(error){
   if(error.code==='40001'||error.status===409){this.conflict=true;this.status('Conflict: newer web data exists. Your local edits are preserved.','conflict');}
   else if(error.status===401||error.status===403){this.status('Sign in or officer approval is required. Local changes are preserved.','auth');}
   else this.status('Saved on this device; not synced. Retry when online.','offline');
  }finally{this.saving=false;}
 }
 snapshot(){return this.pending||this.inflight?.payload||null;}
}
// Node tests use the same queue without a browser or real member records.
if(typeof module!=='undefined'&&module.exports){module.exports={SyncQueue,shared,signature};return;}
let session=null,refreshing=null,ready=false,applying=false,localReady=false,polling=false,baseSave;
const pendingId='cloud-pending-'+crypto.randomUUID();
let recoveredDrafts=[];
const sessionKey='hdg.cloud.session.v1';
// The legacy agenda otherwise creates this implicit global only after an edit.
if(typeof global.agendaGeneratedRecordId==='undefined')global.agendaGeneratedRecordId='';
const cloud={SyncQueue,shared,signature};
global.HDGCloud=cloud;
function el(id){return document.getElementById(id);}
function setSession(value){if(value&&!value.expires_at)value.expires_at=Math.floor(Date.now()/1000)+(value.expires_in||3600);session=value;if(value)sessionStorage.setItem(sessionKey,JSON.stringify(value));else sessionStorage.removeItem(sessionKey);}
function showStatus(message,kind='ok'){
 const text=el('hdg-cloud-status');if(text)text.textContent=message;
 const box=el('hdg-cloud-bar');if(box)box.dataset.kind=kind;
 if(kind==='conflict'){el('hdg-conflict').hidden=false;}
 if(kind==='auth'){ready=false;document.body.classList.remove('hdg-authorized');el('hdg-cloud-gate').hidden=false;el('hdg-auth-message').textContent=message;}
}
async function request(path,body,authenticated=true,retry=true,method){
 if(authenticated&&(!session||!session.access_token))throw Object.assign(new Error('Please sign in.'),{status:401});
 if(authenticated&&session.expires_at&&session.expires_at*1000<Date.now()+60000)await refresh();
 const headers={apikey:CONFIG.key,'Content-Type':'application/json'};
 if(authenticated)headers.Authorization='Bearer '+session.access_token;
 const response=await fetch(CONFIG.url+path,{method:method||(body===undefined?'GET':'POST'),headers,body:body===undefined?undefined:JSON.stringify(body)});
 const result=await response.json().catch(()=>({}));
 if(response.status===401&&authenticated&&retry){await refresh();return request(path,body,true,false,method);}
 if(!response.ok)throw Object.assign(new Error(result.msg||result.message||result.error_description||result.error||'Request failed'),{status:response.status,code:result.code});
 return result;
}
async function refresh(){
 if(!refreshing)refreshing=(async()=>{if(!session?.refresh_token)throw Object.assign(new Error('Please sign in again.'),{status:401});const next=await request('/auth/v1/token?grant_type=refresh_token',{refresh_token:session.refresh_token},false);setSession(next);})().finally(()=>refreshing=null);
 return refreshing;
}
function mount(){
 if(el('hdg-cloud-gate'))return;
 const gate=document.createElement('section');gate.id='hdg-cloud-gate';
 gate.innerHTML=`<div class="hdg-auth-card"><small>HELLO DIVISION G</small><h1>Sign in</h1><p>Access the shared Division G database with your approved account.</p><form id="hdg-auth-form"><label>Email<input id="hdg-email" type="email" autocomplete="username" required></label><label>Password<input id="hdg-password" type="password" autocomplete="current-password"></label><button id="hdg-sign-in" type="submit">Sign in</button><button id="hdg-forgot" type="button">Forgot password?</button><button id="hdg-create" type="button">Create account</button><hr><p class="hdg-small">Prefer to sign in without a password?</p><button id="hdg-email-link" type="button">Email me a sign-in link</button></form><p id="hdg-auth-message" role="status" aria-live="polite"></p><p class="hdg-small">Only approved Division G officers can access the shared database.</p></div>`;
 document.body.appendChild(gate);
 const bar=document.createElement('aside');bar.id='hdg-cloud-bar';bar.innerHTML=`<span id="hdg-cloud-status" role="status" aria-live="polite">Connecting…</span><button id="hdg-retry">Retry / refresh</button><button id="hdg-signout">Sign out</button><div id="hdg-conflict" hidden><p>A newer web version was saved. Your local edits have been kept.</p><button id="hdg-download-local">Download my local edits</button><button id="hdg-use-shared">Keep edits in recovery and load shared version</button></div>`;document.body.appendChild(bar);
 el('hdg-auth-form').addEventListener('submit',async event=>{event.preventDefault();await login(false);});
 el('hdg-email-link').onclick=()=>emailSignIn();
 el('hdg-forgot').onclick=()=>sendPasswordReset();
 el('hdg-create').onclick=()=>login(true);
 el('hdg-retry').onclick=async()=>{await queue.flush();await poll();};
 el('hdg-signout').onclick=async()=>{if(queue.snapshot())await preserveConflict();try{await request('/auth/v1/logout',{});}catch(_){}setSession(null);location.reload();};
 el('hdg-download-local').onclick=()=>downloadPending();
 el('hdg-use-shared').onclick=async()=>{try{await preserveConflict();const latest=await readState();await apply(latest);queue.reset(latest.revision,canonicalStoragePayload(db));await persistPending(null);el('hdg-conflict').hidden=true;showStatus('Synced · revision '+latest.revision);}catch(error){showStatus(error.message,'offline');}};
 const admin=document.createElement('details');admin.id='hdg-admin';admin.hidden=true;
 admin.innerHTML='<summary>Officer access</summary><label>Officer email <input id="hdg-officer-email" type="email" autocomplete="off"></label><button id="hdg-approve-officer">Approve</button><button id="hdg-revoke-officer">Revoke</button><p id="hdg-officer-result" role="status"></p>';
 bar.appendChild(admin);
 const manage=async active=>{
  const field=el('hdg-officer-email');if(!field.value.trim()||!field.reportValidity())return;
  const email=field.value.trim();
  if(!confirm((active?'Grant access to Division G member records for ':'Revoke Division G server access for ')+email+'?'))return;
  try{await request('/rest/v1/rpc/hdg_manage_officer',{p_email:email,p_active:active});el('hdg-officer-result').textContent=active?'Officer approved.':'Officer access revoked.';}
  catch(error){el('hdg-officer-result').textContent=error.message;}
 };
 el('hdg-approve-officer').onclick=()=>manage(true);el('hdg-revoke-officer').onclick=()=>manage(false);
}
function redirectUrl(){return location.protocol==='file:'?'http://localhost:3000/':location.origin+location.pathname;}
async function sendPasswordReset(){
 const input=el('hdg-email');if(!input.reportValidity())return;
 const button=el('hdg-forgot');button.disabled=true;
 el('hdg-auth-message').textContent='Requesting a password setup link…';
 try{
  await request('/auth/v1/recover?redirect_to='+encodeURIComponent(redirectUrl()),{email:input.value.trim()},false);
  el('hdg-auth-message').textContent='If this email has an account, a password setup link is on its way. Open the latest email on this Mac to choose your password.';
 }catch(error){el('hdg-auth-message').textContent=error.message;}
 finally{button.disabled=false;}
}
function showPasswordRecovery(){
 ready=false;
 sessionStorage.setItem('hdg.cloud.recovery.v1','true');
 const title=el('hdg-cloud-gate').querySelector('h1');title.textContent='Choose your password';
 const form=document.createElement('form');form.id='hdg-auth-form';
 form.innerHTML='<label>New password<input id="hdg-new-password" type="password" autocomplete="new-password" minlength="12" required></label><label>Confirm new password<input id="hdg-confirm-password" type="password" autocomplete="new-password" minlength="12" required></label><button id="hdg-save-password" type="submit">Save password and sign in</button>';
 el('hdg-auth-form').replaceWith(form);
 el('hdg-auth-message').textContent='Choose a password with at least 12 characters. Only you enter and submit it.';
 form.addEventListener('submit',async event=>{
  event.preventDefault();if(!form.reportValidity())return;
  const first=el('hdg-new-password'),second=el('hdg-confirm-password');
  if(first.value!==second.value){el('hdg-auth-message').textContent='The passwords do not match.';return;}
  const button=el('hdg-save-password');button.disabled=true;
  try{
   session.user=await request('/auth/v1/user',{password:first.value},true,true,'PUT');
   first.value='';second.value='';setSession(session);sessionStorage.removeItem('hdg.cloud.recovery.v1');
   el('hdg-auth-message').textContent='Password saved. Opening your database…';await connect();
  }catch(error){el('hdg-auth-message').textContent=error.message;}
  finally{button.disabled=false;}
 });
}
async function emailSignIn(){
 const input=el('hdg-email');if(!input.reportValidity())return;
 const button=el('hdg-email-link');button.disabled=true;
 el('hdg-auth-message').textContent='Sending your sign-in link…';
 try{
  const redirect=redirectUrl();
  await request('/auth/v1/otp?redirect_to='+encodeURIComponent(redirect),{email:input.value.trim(),create_user:false},false);
  el('hdg-auth-message').textContent='Sign-in link sent. Open the latest email on this Mac. It will return you to this website.';
 }catch(error){el('hdg-auth-message').textContent=error.message;}
 finally{button.disabled=false;}
}
async function login(create){
 const form=el('hdg-auth-form');if(!form.reportValidity())return;
 ready=false;
 const email=el('hdg-email').value.trim(),password=el('hdg-password').value;
 if(!password){el('hdg-auth-message').textContent='Enter your app password, or use Email me a sign-in link instead.';return;}
 if(create&&password.length<12){el('hdg-auth-message').textContent='For a new login, choose a password with at least 12 characters. For an existing login, use Sign in with its current password.';return;}
 el('hdg-auth-message').textContent=create?'Creating your login…':'Signing in…';
 el('hdg-sign-in').disabled=el('hdg-create').disabled=true;
 try{
  const result=await request(create?'/auth/v1/signup':'/auth/v1/token?grant_type=password',{email,password},false);
  el('hdg-password').value='';
  if(create&&!result.access_token){el('hdg-auth-message').textContent='Open the confirmation email, then return here, enter your password again, and click Sign in. Do not create another login.';return;}
  setSession(result);await connect();
 }catch(error){el('hdg-auth-message').textContent=error.message;}
 finally{el('hdg-sign-in').disabled=el('hdg-create').disabled=false;}
}
async function readState(){
 const fields=global.HDG_ENTRY_LOADER?'revision':'revision,payload,updated_at';
 const rows=await request('/rest/v1/hdg_sync_state?division_code=eq.G&select='+fields);
 if(!rows.length)throw Object.assign(new Error('Your login is not approved for Division G yet.'),{status:403});
 return rows[0];
}
async function persistPending(payload){
 if(!localReady)return;
 await durablePutRecord({id:pendingId,payload,baseRevision:queue.revision,request:queue.inflight,owner:session?.user?.id||null,savedAt:new Date().toISOString()});
}
const queue=new SyncQueue({
 send:job=>{if(!ready)throw Object.assign(new Error('Sign in required'),{status:401});return request('/rest/v1/rpc/hdg_save_web_state',{p_expected_revision:job.revision,p_payload:job.payload,p_request_id:job.id});},
 persist:persistPending,status:showStatus,requestId:()=>crypto.randomUUID()
});cloud.queue=queue;
async function preserveConflict(){
 const payload=queue.snapshot()||shared(canonicalStoragePayload(db));
 await durablePutRecord({id:'cloud-recovery-'+Date.now(),payload,baseRevision:queue.revision,owner:session?.user?.id||null,savedAt:new Date().toISOString()});
 for(const draft of recoveredDrafts){
  await durablePutRecord({...draft,id:'cloud-recovery-'+draft.id});
  await durablePutRecord({...draft,payload:null,request:null,recovered:true});
 }
 recoveredDrafts=[];
}
function downloadPending(){
 const payload=queue.snapshot();if(!payload)return;
 const blob=new Blob([JSON.stringify({format:'hello-division-dashboard',schemaVersion:1,sourceApp:'Hello Division G cloud recovery',exportedAt:new Date().toISOString(),data:{...payload,ui:db.ui||{}}},null,2)],{type:'application/json'});
 const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='hello-division-g-unsynced-edits.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);
}
async function apply(row){
 applying=true;
 try{
  const ui=db?.ui||{};
  db=prepareDashboardData({...structuredClone(row.payload),ui},{allowLegacyPromotion:false});
  await baseSave(JSON.stringify(canonicalStoragePayload(db)),canonicalStoragePayload(db),{allowEmpty:false});
  normalizeDashboardRoleState();applyDashboardUser();render();
 }finally{applying=false;}
}
async function connect(){
 const row=await readState();
 if(global.HDG_ENTRY_LOADER){
  el('hdg-auth-message').textContent='Opening v514…';
  const response=await fetch(CONFIG.url+'/storage/v1/object/authenticated/hdg-private-app/v514.html',{
   headers:{apikey:CONFIG.key,Authorization:'Bearer '+session.access_token},cache:'no-store'
  });
  if(!response.ok)throw new Error('The protected v514 app could not be loaded. Please contact the administrator.');
  const html=await response.text();
  if(!html.includes('hdg-cloud-adapter'))throw new Error('The protected app file is not a connected v514 build.');
  global.HDG_ENTRY_LOADER=false;
  document.open();document.write(html);document.close();
  return;
 }
 const access=await request('/rest/v1/hdg_officer_access?division_code=eq.G&select=app_role');
 el('hdg-admin').hidden=!access.some(a=>a.app_role==='administrator');
 // Only initialize the new, separate cloud cache after approval is verified.
 if(!localReady){await initializeDurableStorage();localReady=true;}
 const idb=await durableOpenDb();
 const records=await new Promise((resolve,reject)=>{const req=idb.transaction(DURABLE_STORE,'readonly').objectStore(DURABLE_STORE).getAll();req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
 recoveredDrafts=records.filter(record=>record.id.startsWith('cloud-pending')&&record.id!==pendingId&&record.owner===session.user.id&&!record.recovered&&(record.payload||record.request));
 const saved=recoveredDrafts[0];
 await apply(row);queue.reset(row.revision,canonicalStoragePayload(db));
 if(saved?.owner===session.user.id&&(saved.payload||saved.request)){
  queue.revision=Number(saved.baseRevision)||row.revision;
  queue.pending=saved.payload||null;queue.inflight=saved.request||null;
  // Keep the current central snapshot visible; do not replay pending edits into it.
  queue.conflict=true;el('hdg-conflict').hidden=false;
  showStatus('Recovered unsynced edits. Download them or load the shared version.','conflict');
 }else showStatus('Synced · revision '+row.revision);
 ready=true;document.body.classList.add('hdg-authorized');el('hdg-cloud-gate').hidden=true;
 setStorageBootGate(false);
}
async function poll(){
 if(!ready||polling||queue.saving||queue.conflict||queue.pending||queue.inflight||DURABLE_STORAGE.pendingJob||DURABLE_STORAGE.commitRunning)return;
 polling=true;
 try{const row=await readState();
  // An edit can start while the network request is in flight.
  if(queue.saving||queue.pending||queue.inflight||DURABLE_STORAGE.pendingJob||DURABLE_STORAGE.commitRunning||signature(canonicalStoragePayload(db))!==queue.baseline)return;
  if(row.revision!==queue.revision){await apply(row);queue.reset(row.revision,canonicalStoragePayload(db));showStatus('Synced · revision '+row.revision);}}
 catch(error){showStatus(error.message,error.status===401||error.status===403?'auth':'offline');}
 finally{polling=false;}
}
cloud.boot=async function(){
 mount();
 if(!global.HDG_ENTRY_LOADER){
  baseSave=durableCommitRaw;
  durableCommitRaw=async function(raw,payload,options){
  const result=await baseSave(raw,payload,options);
  if(ready&&!applying){await queue.enqueue(payload);clearTimeout(cloud.saveTimer);cloud.saveTimer=setTimeout(()=>queue.flush(),700);}
  return result;
  };
 }
 try{
  session=JSON.parse(sessionStorage.getItem(sessionKey)||'null');
  const fragment=new URLSearchParams(location.hash.slice(1));
  if(fragment.has('error_description')){el('hdg-auth-message').textContent=fragment.get('error_description');history.replaceState({},'',location.pathname+location.search);}
  if(fragment.has('access_token')){
   setSession({access_token:fragment.get('access_token'),refresh_token:fragment.get('refresh_token'),expires_in:Number(fragment.get('expires_in'))||3600});
   history.replaceState({},'',location.pathname+location.search);
  }
  if(session){if(!session.user){session.user=await request('/auth/v1/user');setSession(session);}if(fragment.get('type')==='recovery'||sessionStorage.getItem('hdg.cloud.recovery.v1'))showPasswordRecovery();else await connect();}
 }
 catch(error){el('hdg-auth-message').textContent=error.message;}
 setInterval(async()=>{await queue.flush();await poll();},30000);
 window.addEventListener('online',async()=>{await queue.flush();await poll();});
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)poll();});
 window.addEventListener('beforeunload',event=>{if(queue.snapshot()){event.preventDefault();event.returnValue='Local changes have not synced.';}});
};
})(typeof window!=='undefined'?window:globalThis);
