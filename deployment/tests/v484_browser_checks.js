window.addEventListener('load',async()=>{
 const results=[];const check=(name,pass,detail='')=>results.push({name,pass:!!pass,detail});
 const pause=ms=>new Promise(r=>setTimeout(r,ms));
 try{
  await DURABLE_INIT_PROMISE;await pause(2200);
  check('v484 release loaded',window.__HDG_APP_RELEASE__==='v484');
  check('Only synthetic memberships retained',db.database.memberships.length===2&&db.database.memberships.every(m=>String(m.memberId).startsWith('fixture-')));
  check('Unrecognized database field preserved',db.database.v484FixtureSentinel?.keep==='unchanged');
  const bali=db.database.tlis.find(t=>t.id==='tli-main-bali-2');
  check('Bali TLI one-time date correction',bali?.date==='2026-12-06',bali?.date||'missing');
  if(bali){bali.date='2027-01-10';const prepared=prepareDashboardData(canonicalStoragePayload(db),{allowLegacyPromotion:false});check('Later user TLI date survives preparation',prepared.database.tlis.find(t=>t.id==='tli-main-bali-2')?.date==='2027-01-10');bali.date='2026-12-06';}
  const meeting=db.database.meetingAgendaRecords[0];
  agendaMeetingToolData(meeting).v482Extras={theme:'Fixture next theme',question:'Fixture question',winners:{prepared:'Fixture Speaker 1',evaluation:'Fixture Speaker 2',topics:'Fixture Topic Winner'}};
  saveData();await waitForDurableSave();await HDGCloud.queue.flush();
  const saved=window.__QA_SAVES__.at(-1)?.p_payload;
  check('New meeting extras reach shared save',JSON.stringify(saved?.database.meetingTools||{}).includes('Fixture next theme'));
  check('Device poster preferences stay out of shared data',!!saved&&!Object.prototype.hasOwnProperty.call(saved,'ui'));
  selectCommunityAgendaMeeting(meeting.id);
  renderAgendaPresentationPrototype(meeting,true);
  await pause(300);
  const deck=agendaPresentationSlides(meeting,'bsc');
  check('BSC Canva flow includes house rules and GE team',deck.some(s=>s.layout==='house-rules')&&deck.some(s=>s.layout==='ge-team'));
  check('Slide visibility controls render',document.querySelectorAll('.v481-hide').length>0);
  const firstHidden=deck[0].hiddenV481;document.querySelector('.v481-hide')?.click();
  check('Hide/show changes the meeting deck',agendaPresentationSlides(meeting,'bsc')[0].hiddenV481!==firstHidden);
  check('Selected meeting is remembered',String(localStorage.getItem('hdg_active_meeting_v478')).includes(meeting.id));
  check('Next-theme/winners form renders',!!document.getElementById('v482Extras'));
  showCommunityPanel('poster');
  db.ui.clubPosterGenerator={...(db.ui.clubPosterGenerator||{}),clubId:'fixture-bsc',date:'2026-11-12',theme:'Fixture poster theme'};
  renderPosterGenerator();posterRenderV483();await pause(200);
  const layouts=[...document.querySelectorAll('.v483-pick')].map(b=>b.dataset.layout);
  check('All 12 poster layouts available',layouts.length===12,String(layouts.length));
  check('All 7 poster palettes available',document.querySelectorAll('.v484-sw').length===7,String(document.querySelectorAll('.v484-sw').length));
  let rendered=0;
  const paletteKeys=[...document.querySelectorAll('.v484-sw')].map(b=>b.dataset.p);
  for(const id of layouts)for(const palette of paletteKeys){
   db.ui.clubPosterGenerator.v483Layout=id;db.ui.clubPosterGenerator.v484Palette=palette==='club'?'':palette;
   const svg=posterSvgV483();const parsed=new DOMParser().parseFromString(svg,'image/svg+xml');
   const invalid=[...parsed.querySelectorAll('*')].some(e=>[...e.attributes].some(a=>!['href','xlink:href','style'].includes(a.name)&&/\bNaN\b/.test(a.value)));
   if(!parsed.querySelector('parsererror')&&!invalid)rendered++;
  }
  check('All 84 layout/palette combinations generate valid SVG',rendered===84,String(rendered));
  showCommunityPanel('agenda');renderCommunityAgendaRecord();v483BuildRolesGlance();await pause(100);
  check('Roles-at-a-glance editor renders',!!document.querySelector('#v483Glance input[data-target="agendaEditTom"]'));
  const tom=document.querySelector('#v483Glance input[data-target="agendaEditTom"]');
  if(tom){tom.value='Fixture Updated Toastmaster';tom.dispatchEvent(new Event('input',{bubbles:true}));tom.dispatchEvent(new Event('change',{bubbles:true}));document.querySelector('#v483Glance .v483-save').click();await waitForDurableSave();await HDGCloud.queue.flush();}
  check('Roles-at-a-glance edit reaches shared save',window.__QA_SAVES__.at(-1)?.p_payload?.database.meetingAgendaRecords?.[0]?.roles?.tom==='Fixture Updated Toastmaster');

 }catch(error){check('QA execution',false,String(error.stack||error));}
 const box=document.createElement('section');box.id='qa-report';box.style.cssText='position:fixed;inset:20px;z-index:2147483647;overflow:auto;padding:24px;background:#101d30;color:white;font:16px monospace';
 const title=document.createElement('h1');title.textContent='v484 synthetic-data QA';box.appendChild(title);
 const summary=document.createElement('p');summary.id='qa-summary';summary.textContent=results.filter(r=>r.pass).length+'/'+results.length+' checks passed';box.appendChild(summary);
 const list=document.createElement('pre');list.textContent=results.map(r=>(r.pass?'PASS':'FAIL')+' '+r.name+(r.detail?' — '+r.detail:'')).join('\n');box.appendChild(list);document.body.appendChild(box);
});
