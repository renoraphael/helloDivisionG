'use strict';
/* Keeps the ballot page's own files on the phone so the page reopens without signal.
   Network first: a fresh copy is used whenever there is signal. Only these four same-site files are kept;
   nothing from the database (ballots, votes) passes through this cache. */
const CACHE='hdg-ballot-v1';
const FILES=['ballot.html','ballot.js','cloud-sync.js','cloud-sync.css'];
self.addEventListener('install',event=>{
 event.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES.map(f=>new Request(f,{cache:'reload'})))).catch(()=>{}));
 self.skipWaiting();
});
self.addEventListener('activate',event=>{
 event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('hdg-ballot-')&&k!==CACHE).map(k=>caches.delete(k))))
  .then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==location.origin)return;
 const name=url.pathname.split('/').pop();
 if(!FILES.includes(name))return;
 event.respondWith(fetch(event.request).then(response=>{
  if(response.ok){const copy=response.clone();caches.open(CACHE).then(c=>c.put(name,copy)).catch(()=>{});}
  return response;
 }).catch(()=>caches.match(name)));
});
