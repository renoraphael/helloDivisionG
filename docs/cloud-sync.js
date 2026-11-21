/* No service key or member records belong in this adapter. */
(function(global){
'use strict';
const CONFIG={url:'https://bhbgusdxqbjwsdlzhurb.supabase.co',key:'sb_publishable_73Y-5z5ao1d97jUibxC97g_AMmmaiXh'};
function shared(payload){
 const out=JSON.parse(JSON.stringify({updated:payload.updated,settings:payload.settings||{},database:payload.database}));
 // Director workspace records belong outside the officer-readable shared snapshot.
 if(out.database)delete out.database.workspaceV614;
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
function serializeCacheWrites(write,withLock=job=>job()){
 let previous=Promise.resolve();
 return (...args)=>{
  const next=previous.then(()=>withLock(()=>write(...args)));
  previous=next.catch(()=>{});
  return next;
 };
}
// Node tests use the same queue without a browser or real member records.
if(typeof module!=='undefined'&&module.exports){module.exports={SyncQueue,shared,signature,serializeCacheWrites};return;}
let session=null,refreshing=null,ready=false,applying=false,localReady=false,polling=false,baseSave;
const pendingId='cloud-pending-'+crypto.randomUUID();
let recoveredDrafts=[], creatingAccount=false;
const sessionKey='hdg.cloud.session.v1';
// The legacy agenda otherwise creates this implicit global only after an edit.
if(typeof global.agendaGeneratedRecordId==='undefined')global.agendaGeneratedRecordId='';
const cloud={SyncQueue,shared,signature};
global.HDGCloud=cloud;
function el(id){return document.getElementById(id);}
function setSession(value){if(value&&!value.expires_at)value.expires_at=Math.floor(Date.now()/1000)+(value.expires_in||3600);session=value;if(value)sessionStorage.setItem(sessionKey,JSON.stringify(value));else{sessionStorage.removeItem(sessionKey);try{caches.delete('hdg-app-v1');}catch(_){}}}
/* Loads a protected app file. Tries the gzip copy first (about 40% of the size), shows progress, and reuses the copy kept in
   this browser only when the server answers "not modified" (HTTP 304), so access is still checked on every sign-in.
   If the gzip copy is missing or the browser cannot unzip, it falls back to the plain file. The kept copy is deleted on sign-out. */
const APP_CACHE='hdg-app-v1';
async function fetchAppHtml(name,onProgress){
 const base=CONFIG.url+'/storage/v1/object/authenticated/hdg-private-app/';
 const tries=typeof DecompressionStream==='function'?[name+'.gz',name]:[name];
 let cache=null;try{cache=await caches.open(APP_CACHE);}catch(_){}
 let lastStatus=0;
 for(let i=0;i<tries.length;i++){
  const object=tries[i],key='https://hdg.invalid/app/'+object;
  let cached=null;try{cached=cache?await cache.match(key):null;}catch(_){}
  const etag=cached&&cached.headers.get('x-etag');
  const headers={apikey:CONFIG.key,Authorization:'Bearer '+session.access_token};
  if(etag)headers['If-None-Match']=etag;
  const response=await fetch(base+object,{headers,cache:'no-store'});
  lastStatus=response.status;
  let bytes;
  if(response.status===304&&cached){
   bytes=new Uint8Array(await cached.arrayBuffer());
  }else if(response.ok){
   const total=Number(response.headers.get('content-length'))||0;
   if(response.body&&response.body.getReader){
    const reader=response.body.getReader(),chunks=[];let got=0;
    for(;;){const step=await reader.read();if(step.done)break;chunks.push(step.value);got+=step.value.length;if(onProgress)onProgress(got,total);}
    bytes=new Uint8Array(got);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}
   }else bytes=new Uint8Array(await response.arrayBuffer());
   const tag=response.headers.get('etag');
   if(cache&&tag){try{for(const k of await cache.keys())await cache.delete(k);await cache.put(key,new Response(bytes,{headers:{'x-etag':tag}}));}catch(_){}}
  }else if(i<tries.length-1&&(response.status===400||response.status===404)){
   continue;
  }else throw new Error('The protected app could not be loaded (status '+response.status+'). Please refresh and try again.');
  if(object.endsWith('.gz'))return await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
  return new TextDecoder().decode(bytes);
 }
 throw new Error('The protected app could not be loaded (status '+lastStatus+').');
}
function appProgress(label){return (got,total)=>{const m=el('hdg-auth-message');if(m)m.textContent=label+(total?' '+(got/1048576).toFixed(1)+' of '+(total/1048576).toFixed(1)+' MB':'');};}
/* A visible Sign out button in the top toolbar of the Leader app (the Member app has its own). It triggers the same sign-out as the status-bar button. */
function mountToolbarSignOut(){
 let tries=0;
 const place=()=>{
  if(global.HDG_ENTRY_LOADER||document.getElementById('hdgToolbarSignOut')||document.getElementById('hdgMemberSignOut')||document.body.classList.contains('role-member'))return true;
  const shell=document.querySelector('.toolbar-shell');if(!shell)return false;
  const b=document.createElement('button');b.type='button';b.id='hdgToolbarSignOut';b.className='toolbar-icon-btn';b.title='Sign out';b.setAttribute('aria-label','Sign out');
  b.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  b.onclick=()=>{b.disabled=true;const s=el('hdg-signout');if(s)s.click();else{try{sessionStorage.removeItem(sessionKey);}catch(_){}location.reload();}};
  shell.insertBefore(b,shell.querySelector('#v622ThemeBtn')||shell.querySelector('.toolbar-present')||null);
  return true;
 };
 const timer=setInterval(()=>{if(place()||++tries>80)clearInterval(timer);},500);
}
/* Sync status lives in a Settings card instead of a box that floats over the screen. Only a real problem (unsynced edits waiting,
   or changes that cannot be saved) shows a small pill that opens it. Roles without a Settings tab get the old floating box in that case. */
function openSyncSettings(){
 const card=el('hdg-sync-card');if(!card)return;
 const link=document.querySelector('.nav-link[data-tab="settings"]');
 if(link&&link.offsetParent!==null){link.click();setTimeout(()=>card.scrollIntoView({block:'center'}),200);}
 else card.classList.add('float');
}
function updateSyncAlert(){
 const pill=el('hdg-sync-alert'),bar=el('hdg-cloud-bar'),card=el('hdg-sync-card');if(!pill||!bar)return;
 const kind=bar.dataset.kind||'ok',urgent=kind==='conflict'||kind==='offline';
 if(!urgent){pill.dataset.dismissed='';card&&card.classList.remove('float');pill.hidden=true;return;}
 pill.textContent=kind==='conflict'?'Unsynced edits need attention':'Offline: changes not saved yet';
 pill.hidden=pill.dataset.dismissed===kind||(card&&card.classList.contains('float'));
}
function mountSyncCard(){
 let tries=0;
 const place=()=>{
  if(global.HDG_ENTRY_LOADER||el('hdg-sync-card'))return true;
  const settings=document.getElementById('settings'),bar=el('hdg-cloud-bar');
  if(!settings||!bar)return false;
  const card=document.createElement('div');card.id='hdg-sync-card';card.className='card';
  card.innerHTML='<h3>Sync &amp; account</h3><p class="small">Shows whether your changes are saved to the shared version, with sign-out and recovery options.</p>';
  card.appendChild(bar);settings.appendChild(card);
  const pill=document.createElement('button');pill.type='button';pill.id='hdg-sync-alert';pill.hidden=true;
  pill.onclick=()=>{pill.dataset.dismissed=(el('hdg-cloud-bar')||{dataset:{}}).dataset.kind||'';pill.hidden=true;openSyncSettings();};
  document.body.appendChild(pill);document.body.classList.add('hdg-sync-placed');
  updateSyncAlert();return true;
 };
 const timer=setInterval(()=>{if(place()||++tries>80)clearInterval(timer);},500);
}
function showStatus(message,kind='ok'){
 const text=el('hdg-cloud-status');if(text)text.textContent=message;
 const box=el('hdg-cloud-bar');if(box)box.dataset.kind=kind;
 updateSyncAlert();
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
cloud.signOutMember=async()=>{
 let timer;
 try{
  await Promise.race([
   request('/auth/v1/logout?scope=local',{}),
   new Promise(resolve=>{timer=setTimeout(resolve,2500);})
  ]);
 }catch(_){}
 finally{
  clearTimeout(timer);
  setSession(null);
  location.replace(location.pathname);
 }
};
async function refresh(){
 if(!refreshing)refreshing=(async()=>{if(!session?.refresh_token)throw Object.assign(new Error('Please sign in again.'),{status:401});const next=await request('/auth/v1/token?grant_type=refresh_token',{refresh_token:session.refresh_token},false);setSession(next);})().finally(()=>refreshing=null);
 return refreshing;
}
function mount(){
 if(el('hdg-cloud-gate'))return;
 const gate=document.createElement('section');gate.id='hdg-cloud-gate';
 gate.innerHTML=`<div class="hdg-auth-card"><aside class="hdg-signup-aside" aria-label="How sign-up works"><span class="hdg-signup-brand">HELLO DIVISION G</span><strong class="hdg-signup-title">Join your Division G community</strong><ol class="hdg-signup-steps"><li><b>Use your membership email</b><span>The one on your Toastmasters record.</span></li><li><b>Choose a password</b><span>At least 8 characters.</span></li><li><b>Confirm by email</b><span>Open the link we send you to continue.</span></li></ol><p class="hdg-signup-note">Leadership dashboards also need officer approval.</p></aside><small>HELLO DIVISION G</small><h1>Sign in</h1><p id="hdg-auth-intro"></p><form id="hdg-auth-form"><label>Email<input id="hdg-email" type="email" autocomplete="username" required></label><label>Password<input id="hdg-password" type="password"></label><p id="hdg-password-help" class="hdg-small" hidden>Use at least 8 characters.</p><button id="hdg-sign-in" class="hdg-main-action" type="submit">Sign in</button><div id="hdg-auth-alternatives"><button id="hdg-forgot" type="button">Forgot password?</button><button id="hdg-email-link" type="button">Email me a sign-in link</button></div></form><p id="hdg-auth-message" role="status" aria-live="polite"></p><div class="hdg-auth-switch"><span id="hdg-auth-prompt"></span> <button id="hdg-create" type="button"></button></div></div>`;
 document.body.appendChild(gate);
 const bar=document.createElement('aside');bar.id='hdg-cloud-bar';bar.innerHTML=`<span id="hdg-cloud-status" role="status" aria-live="polite">Connecting…</span><button id="hdg-retry">Retry / refresh</button><button id="hdg-signout">Sign out</button><div id="hdg-conflict" hidden><p>A newer web version was saved. Your local edits have been kept.</p><button id="hdg-download-local">Download my local edits</button><button id="hdg-use-shared">Keep edits in recovery and load shared version</button></div>`;document.body.appendChild(bar);
 el('hdg-auth-form').addEventListener('submit',async event=>{event.preventDefault();await login(creatingAccount);});
 el('hdg-email-link').onclick=()=>emailSignIn();
 el('hdg-forgot').onclick=()=>sendPasswordReset();
 el('hdg-create').onclick=()=>showAuthMode(!creatingAccount);
 el('hdg-password').addEventListener('input',()=>{el('hdg-password-help').dataset.ok=el('hdg-password').value.length>=8?'yes':'no';});
 showAuthMode(global.HDG_ENTRY_LOADER&&new URLSearchParams(location.search).get('view')==='signup');
 el('hdg-retry').onclick=async()=>{await queue.flush();await poll();};
 el('hdg-signout').onclick=async()=>{if(queue.snapshot())await preserveConflict();try{await request('/auth/v1/logout',{});}catch(_){}setSession(null);location.reload();};
 mountToolbarSignOut();
 mountSyncCard();
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
function showAuthMode(create){
 creatingAccount=create;
 el('hdg-cloud-gate').dataset.mode=create?'signup':'signin';
 el('hdg-password-help').dataset.ok=el('hdg-password').value.length>=8?'yes':'no';
 const signIn=el('hdg-sign-in'), password=el('hdg-password'), toggle=el('hdg-create');
 el('hdg-cloud-gate').querySelector('h1').textContent=create?'Create your account':'Sign in';
 el('hdg-auth-intro').textContent=create
  ?'Use the email on your Toastmasters membership record. Verify it to open Community.'
  :'Sign in to Community or your approved leadership dashboard.';
 el('hdg-auth-prompt').textContent=create?'Already have an account?':'New to Hello Division G?';
 signIn.textContent=create?'Create account':'Sign in';
 toggle.textContent=create?'Sign in instead':'Create an account';
 password.autocomplete=create?'new-password':'current-password';
 password.required=create;
 el('hdg-password-help').hidden=!create;
 el('hdg-auth-alternatives').hidden=create;
 el('hdg-auth-message').textContent='';
}
/* Which protected file to load: the release the maintainer made current (hdg_releases, one-step rollback), or the
   built-in names below if the database has no release list yet. Rolling back needs no new launcher. */
async function currentAppFile(channel,fallback){
 try{
  const r=await request('/rest/v1/rpc/hdg_current_release',{});
  if(r&&r.channel===channel&&/^v[0-9]{3,4}$/.test(r.version)&&r.file===r.version+'-'+channel+'.html')return{file:r.file,release:r.version+'-'+channel};
 }catch(_){}
 return{file:fallback,release:fallback.replace(/\.html$/,'')};
}
async function showMemberCommunity(data){
 const m=el('hdg-auth-message');if(m)m.textContent='Opening Hello Division G…';
 const app=await currentAppFile('member','v648-member.html');
 const html=await fetchAppHtml(app.file,appProgress('Opening Hello Division G…'));
 const marker='/* HDG_MEMBER_V632_CONTEXT */';
 if(!html.includes('<script id="hdg-member-context">'+marker+'</script>')||html.indexOf(marker)!==html.lastIndexOf(marker)){
  throw new Error('The stored file is not an original v632 Member build.');
 }
 const context=JSON.stringify({account:session.user.id,community:data}).replace(/</g,'\\u003c');
 // Greeting: show "Hello <name>!" as the page title when this login has a display name (Auth user metadata).
 const rawName=session.user&&session.user.user_metadata&&session.user.user_metadata.display_name;
 const name=typeof rawName==='string'?rawName.replace(/[\u0000-\u001f<>]/g,'').trim().slice(0,40):'';
 const greeting=name?'(function(n){var T="Division G Community",G="Hello "+n+"!";function fix(){var t=document.getElementById("pageTitle");if(t&&t.textContent===T)t.textContent=G;}function arm(){var t=document.getElementById("pageTitle");if(!t)return;fix();new MutationObserver(fix).observe(t,{childList:true,characterData:true,subtree:true});}if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",arm);else arm();})('+JSON.stringify(name).replace(/</g,'\\u003c')+');':'';
 global.HDG_ENTRY_LOADER=false;
 document.open();
 document.write(html.replace(marker,()=> 'window.HDG_MEMBER_V632_CONTEXT='+context+';'+greeting));
 document.close();
}
/* Error reports to the maintainer (rule 32): at most 5 per page, each different, sent without the sign-in token.
   Emails and long numbers are removed here and again on the server; the page address is sent without ? or #. */
(function(){
 let sent=0,off=false;const seen=new Set();
 const clean=t=>String(t||'').replace(/[^\s@]+@[^\s@]+\.[A-Za-z]{2,}/g,'[email]').replace(/\+?[0-9][0-9 .-]{5,}[0-9]/g,'[number]');
 function send(message,stack){
  const m=clean(message).slice(0,500);
  if(off||sent>=5||!m||seen.has(m))return;
  seen.add(m);sent++;
  try{fetch(CONFIG.url+'/rest/v1/rpc/hdg_report_error',{method:'POST',keepalive:true,headers:{apikey:CONFIG.key,'Content-Type':'application/json'},
   body:JSON.stringify({p_release:String(global.__HDG_APP_RELEASE__||'launcher').slice(0,40),p_page:location.pathname.slice(0,200),
    p_message:m,p_stack:clean(stack).slice(0,2000),p_browser:String(navigator.userAgent).slice(0,200)})})
   .then(r=>{if(r.status===404)off=true;}).catch(()=>{});}catch(_){}
 }
 global.addEventListener('error',e=>send(e.message,e.error&&e.error.stack));
 global.addEventListener('unhandledrejection',e=>{const r=e.reason;send(r&&r.message||String(r),r&&r.stack);});
 cloud.reportError=send;
})();
cloud.openBallot=token=>request('/rest/v1/rpc/hdg_open_ballot',{p_token:token},false);
cloud.castBallot=(token,browserId,choices)=>request('/rest/v1/rpc/hdg_cast_ballot',{p_token:token,p_browser_id:browserId,p_choices:choices},false);
cloud.manageBallot=(meetingId,action,title,choices)=>request('/rest/v1/rpc/hdg_manage_ballot',{
 p_meeting_id:meetingId,p_action:action,p_title:title??null,p_choices:choices??null
});
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
 form.innerHTML='<label>New password<input id="hdg-new-password" type="password" autocomplete="new-password" minlength="8" required></label><label>Confirm new password<input id="hdg-confirm-password" type="password" autocomplete="new-password" minlength="8" required></label><button id="hdg-save-password" type="submit">Save password and sign in</button>';
 el('hdg-auth-form').replaceWith(form);
 el('hdg-auth-message').textContent='Choose a password with at least 8 characters.';
 el('hdg-auth-prompt').parentElement.hidden=true;
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
 if(create&&password.length<8){el('hdg-auth-message').textContent='For a new login, choose a password with at least 8 characters. For an existing login, use Sign in with its current password.';return;}
 el('hdg-auth-message').textContent=create?'Creating your login…':'Signing in…';
 el('hdg-sign-in').disabled=el('hdg-create').disabled=true;
 try{
  const result=await request(create?'/auth/v1/signup?redirect_to='+encodeURIComponent(redirectUrl()):'/auth/v1/token?grant_type=password',{email,password},false);
  el('hdg-password').value='';el('hdg-password-help').dataset.ok='no';
  if(create&&!result.access_token){el('hdg-auth-message').textContent='Check your email and open the confirmation link to finish setting up your account.';return;}
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
/* Temporary access (deployment/schema/010): a leader whose division is still being set up sees its status
   (clubs and areas loaded, members imported or not) instead of "no access". Counts only; built with textContent. */
const ROLE_LABELS={maintainer:'Maintainer',district_director:'District Director',pqd:'Program Quality Director',cgd:'Club Growth Director',
 am:'Administration Manager',prm:'Public Relations Manager',fm:'Finance Manager',lm:'Logistics Manager',alignment_chair:'Alignment Chair',
 division_director:'Division Director',area_director:'Area Director',club_president:'Club President',club_vpe:'VP Education',
 club_vpm:'VP Membership',club_vppr:'VP Public Relations',club_secretary:'Club Secretary',club_treasurer:'Club Treasurer',club_saa:'Sergeant at Arms'};
function showDivisionSetup(ctx){
 ctx=ctx||{};
 const card=el('hdg-cloud-gate').querySelector('.hdg-auth-card');
 const node=(tag,text,cls)=>{const n=document.createElement(tag);if(text!=null)n.textContent=text;if(cls)n.className=cls;return n;};
 card.replaceChildren();
 card.classList.add('hdg-setup-card');
 card.append(node('small','HELLO DISTRICT 87'),node('h1','Hello'+(ctx.name?' '+String(ctx.name).slice(0,40):'')+'!'));
 const roles=(ctx.roles||[]).filter(r=>r.role!=='maintainer').map(r=>(ROLE_LABELS[r.role]||r.role)+(r.scope&&!/^(87|system)$/.test(r.scope)?' '+r.scope:''));
 if(roles.length)card.append(node('p',roles.join(' · ')+(ctx.provisional?' (temporary access)':''),'hdg-setup-roles'));
 card.append(node('p','Your division is being set up in Hello Division G. Club information is ready; members and club officers are imported next.'));
 for(const d of ctx.divisions||[]){
  const box=node('section',null,'hdg-setup-division');
  box.append(node('h2',d.name||('Division '+d.code)));
  const list=node('ul');
  list.append(node('li',`${d.clubs} clubs in ${d.areas} areas loaded`));
  list.append(node('li',d.members>0?`${d.members} members imported`:'Members and club officers: import first'));
  box.append(list);card.append(box);
 }
 if(!(ctx.divisions||[]).length)card.append(node('p','No division is linked to your role yet. Contact the maintainer.'));
 card.append(node('p','You will get the full app for your division once its member and officer lists are imported.','hdg-small'));
 const out=node('button','Sign out','hdg-main-action');out.type='button';
 out.onclick=async()=>{try{await request('/auth/v1/logout',{});}catch(_){}setSession(null);location.reload();};
 card.append(out);
 el('hdg-cloud-gate').hidden=false;
}
async function connect(){
 if(global.HDG_ENTRY_LOADER){
  const mode=await request('/rest/v1/rpc/hdg_access_mode',{});
  if(mode==='member'){
   await showMemberCommunity(await request('/rest/v1/rpc/hdg_member_community',{}));
   return;
  }
  if(mode==='setup'){showDivisionSetup(await request('/rest/v1/rpc/hdg_my_context',{}));return;}
  if(mode!=='leader')throw new Error('Your verified email is not matched to an active membership. Use the email on your Toastmasters record or contact your club.');
  await readState();
  el('hdg-auth-message').textContent='Opening Hello Division G…';
  const app=await currentAppFile('community','v648-community.html');
  const html=await fetchAppHtml(app.file,appProgress('Opening Hello Division G…'));
  if(!html.includes('hdg-cloud-adapter')||!html.includes('window.__HDG_APP_RELEASE__="'+app.release+'";'))throw new Error('The protected app file is not a connected '+app.release.replace('-community','')+' build.');
  global.HDG_ENTRY_LOADER=false;
  document.open();document.write(html);document.close();
  return;
 }
 const row=await readState();
 const access=await request('/rest/v1/hdg_officer_access?division_code=eq.G&select=app_role');
 el('hdg-admin').hidden=!access.some(a=>a.app_role==='administrator');
 // Only initialize the new, separate cloud cache after approval is verified.
 if(!localReady){
  await initializeDurableStorage();
  await waitForDurableSave();
  localReady=true;
 }
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
  const locks=global.navigator?.locks;
  baseSave=serializeCacheWrites(durableCommitRaw,locks?job=>locks.request('hdg-shared-cache',job):undefined);
  durableCommitRaw=async function(raw,payload,options){
   const shouldSync=ready&&!applying;
   const result=await baseSave(raw,payload,options);
   if(shouldSync&&ready&&!applying){await queue.enqueue(payload);clearTimeout(cloud.saveTimer);cloud.saveTimer=setTimeout(()=>queue.flush(),700);}
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
