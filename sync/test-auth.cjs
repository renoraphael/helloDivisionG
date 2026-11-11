const assert=require('node:assert/strict');
const vm=require('node:vm');const fs=require('node:fs');
const source=fs.readFileSync(__dirname+'/cloud-sync.js','utf8');
function fixture(hash=''){
 const nodes=new Map(),requests=[],store=new Map();
 class Node {
  constructor(){this.value='';this.events={};this.hidden=false;this.classList={add(){},remove(){}};}
  set innerHTML(value){this.html=value;for(const match of value.matchAll(/id="([^"]+)"/g)){if(!nodes.has(match[1]))nodes.set(match[1],new Node());}}
  get innerHTML(){return this.html;}
  appendChild(node){if(node.id)nodes.set(node.id,node);}
  replaceWith(node){if(node.id)nodes.set(node.id,node);}
  querySelector(){return new Node();}
  addEventListener(type,fn){this.events[type]=fn;}
  reportValidity(){return true;}
 }
 const body=new Node();
 const context={JSON,URLSearchParams,Date,structuredClone,crypto:{randomUUID:()=> 'fixture-request'},
 document:{body,getElementById:id=>nodes.get(id),createElement:()=>new Node(),addEventListener(){}},
 sessionStorage:{setItem:(k,v)=>store.set(k,v),getItem:k=>store.get(k)||null,removeItem:k=>store.delete(k)},
 location:{hash,protocol:'http:',origin:'http://localhost:3000',pathname:'/',search:'',reload(){}},history:{replaceState(){}},
 durableCommitRaw:async()=>true,setInterval(){},setTimeout(){},clearTimeout(){},
 fetch:async(url,options)=>{requests.push({url,...options});return {ok:true,status:200,json:async()=>url.includes('/auth/v1/user')?{id:'fixture-user'}:url.includes('/hdg_sync_state')?[]:{}};}
 };
 context.window=context;context.addEventListener=()=>{};vm.runInNewContext(source,context);
 return {context,nodes,requests,store};
}
async function run(){
 let f=fixture();await f.context.HDGCloud.boot();
 f.nodes.get('hdg-email').value='fixture@example.invalid';
 await f.nodes.get('hdg-email-link').onclick();
 let req=f.requests.at(-1);assert(req.url.includes('/otp?redirect_to='));assert.equal(req.method,'POST');assert.equal(JSON.parse(req.body).create_user,false);assert(!('password' in JSON.parse(req.body)));
 await f.nodes.get('hdg-forgot').onclick();req=f.requests.at(-1);assert(req.url.includes('/recover?redirect_to='));assert.equal(req.method,'POST');assert.deepEqual(JSON.parse(req.body),{email:'fixture@example.invalid'});
 f=fixture('#access_token=fixture-token&refresh_token=fixture-refresh&type=recovery');await f.context.HDGCloud.boot();
 assert(f.nodes.has('hdg-new-password'));assert(f.store.has('hdg.cloud.recovery.v1'));
 f.nodes.get('hdg-new-password').value='fixture-password-only';f.nodes.get('hdg-confirm-password').value='different';
 await f.nodes.get('hdg-auth-form').events.submit({preventDefault(){}});assert.equal(f.requests.length,1,'Mismatched passwords must not call update');
 f.nodes.get('hdg-confirm-password').value='fixture-password-only';
 await f.nodes.get('hdg-auth-form').events.submit({preventDefault(){}});
 req=f.requests.find(x=>x.method==='PUT');assert(req);assert(req.url.endsWith('/auth/v1/user'));assert.equal(JSON.parse(req.body).password,'fixture-password-only');assert(!f.store.has('hdg.cloud.recovery.v1'));
 console.log('PASS: email link, recovery request, reset callback, mismatch rejection, authenticated PUT password update (mock transport; no real email or password changed)');
}
module.exports=run();
