const assert=require('node:assert/strict');
const {SyncQueue}=require('./cloud-sync.js');
const payload=n=>({updated:'ignored',settings:{label:n},database:{schemaVersion:4,meta:{revision:999,lastSavedAt:'device'},clubs:[{id:'club'}],memberships:[{id:'member'}]},ui:{private:'device'}});
async function run(){
 let calls=[],saved=[],id=0;
 let q=new SyncQueue({send:async j=>{calls.push(j);return {revision:j.revision+1};},persist:async p=>saved.push(p),status:()=>{},requestId:()=>String(++id)});
 q.reset(10,payload(0));await q.enqueue(payload(0));await q.flush();assert.equal(calls.length,0);
 const input=payload(1);await q.enqueue(input);input.settings.label=99;await q.flush();assert.equal(calls[0].payload.settings.label,1);assert.equal(calls[0].payload.ui,undefined);assert.equal(calls[0].payload.database.meta.revision,undefined);assert.equal(q.revision,11);
 await q.enqueue(payload(2));await q.enqueue(payload(3));await q.flush();assert.equal(calls.at(-1).payload.settings.label,3);assert.equal(q.revision,12);
 // An edit that reverses an in-flight save must also reach the server.
 let resolveFirst;calls=[];q=new SyncQueue({send:j=>{calls.push(j);return calls.length===1?new Promise(r=>resolveFirst=r):Promise.resolve({revision:j.revision+1});},persist:async()=>{},status:()=>{},requestId:()=>String(++id)});
 q.reset(1,payload(0));await q.enqueue(payload(1));let active=q.flush();await q.enqueue(payload(0));resolveFirst({revision:2});await active;assert.equal(calls.length,2);assert.equal(calls[1].payload.settings.label,0);assert.equal(calls[1].revision,2);
 // A network retry keeps the exact same request id and payload.
 let fail=true;calls=[];q=new SyncQueue({send:async j=>{calls.push(j);if(fail)throw Error('offline');return {revision:2};},persist:async()=>{},status:()=>{},requestId:()=>String(++id)});
 q.reset(1,payload(0));await q.enqueue(payload(1));await q.flush();assert(q.snapshot());fail=false;await q.flush();assert.equal(calls[0].id,calls[1].id);assert.equal(q.snapshot(),null);
 // Conflicts never silently retry over a newer server revision.
 calls=[];q=new SyncQueue({send:async j=>{calls.push(j);throw Object.assign(Error('stale'),{code:'40001'});},persist:async()=>{},status:()=>{},requestId:()=>String(++id)});
 q.reset(1,payload(0));await q.enqueue(payload(1));await q.flush();await q.flush();assert(q.conflict);assert(q.snapshot());assert.equal(calls.length,1);
 console.log('PASS: unchanged saves, immutable snapshots, coalescing, in-flight reversals, offline idempotency, conflict preservation');
}
run().catch(e=>{console.error(e);process.exitCode=1;});
