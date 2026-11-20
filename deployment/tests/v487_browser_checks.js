window.addEventListener('load',async()=>{
 const results=[];const check=(name,pass,detail='')=>results.push({name,pass:!!pass,detail});
 const pause=ms=>new Promise(r=>setTimeout(r,ms));
 try{
  await DURABLE_INIT_PROMISE;await pause(2200);
  check('v487 release loaded',window.__HDG_APP_RELEASE__==='v487');
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
  document.getElementById('agendaImportClub').value='fixture-bsc';agendaClubChanged('fixture-bsc');document.getElementById('agendaMeetingSelect').value=meeting.id;selectCommunityAgendaMeeting(meeting.id);
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

  document.querySelector('a[href="#community"]').click();showCommunityPanel('poster');renderPosterGenerator();posterRenderV483();document.querySelectorAll('#communityPanelPoster details').forEach(d=>d.open=true);await pause(350);
  const visible=id=>{const e=document.getElementById(id);return !!e&&e.getClientRects().length>0;};
  check('Poster title and meeting pickers visible',visible('clubPosterTitle')&&visible('clubPosterClub')&&visible('clubPosterMeeting'));
  check('Member and guest fee fields visible',visible('v487FeeMember')&&visible('v487FeeGuest'));
  const feature=document.getElementById('v487Feature');
  check('Featured person offers TOM and educational speaker only',feature&&[...feature.options].map(x=>x.value).join(',')==='tom,edu');
  const ps=db.ui.clubPosterGenerator;
  Object.assign(ps,{title:'Fixture Title',subtitle:'Fixture Subtitle',theme:'Stale unused theme',venue:'Fixture Hall',locationNote:'Fixture Hall, Fixture Street, Indonesia',feeMember:'Free',feeGuest:'75000',fee:'',formatLabel:'In-person',speakerName:'Fixture Host',speakerRole:'Toastmaster of the Meeting',registerUrl:'https://example.invalid/register',contactName:'Contact',contactValue:'+620000000000',instagram:'@fixtureclub'});
  let subtitles=0,addresses=0,fees=0,contacts=0;
  const svgText=()=>[...new DOMParser().parseFromString(posterSvgV483(),'image/svg+xml').querySelectorAll('text')].map(e=>e.textContent).join(' ').replace(/\s+/g,' ').toLowerCase();
  for(const id of layouts){ps.v483Layout=id;const t=svgText();if(t.includes('fixture subtitle')&&t.includes('fixture title')&&!t.includes('stale unused theme'))subtitles++;if(t.includes('fixture street')&&!t.includes('indonesia'))addresses++;if(t.includes('members free')&&t.includes('guests idr 75k'))fees++;if(t.includes('@fixtureclub')&&t.includes('+620000000000'))contacts++;}
  check('All 12 layouts use explicit title and subtitle',subtitles===12,String(subtitles));
  check('All 12 layouts include cleaned address',addresses===12,String(addresses));
  check('All 12 layouts include member and guest fees',fees===12,String(fees));
  check('All 12 layouts retain contacts alongside registration QR',contacts===12,String(contacts));
  ps.v483Layout='question';ps.registerUrl='';
  check('Registration is optional with welcoming CTA',svgText().includes('guests welcome')&&!svgText().includes('sign up now'));
  ps.feeMember='';ps.feeGuest='';ps.formatLabel='Online';
  check('Online meeting without fees shows Free',svgText().includes('free'));
  ps.v487Tom='Fixture Toastmaster';ps.v487Edu='Fixture Educator';ps.speakerRole='Toastmaster of the Meeting';
  feature.value='edu';feature.dispatchEvent(new Event('change',{bubbles:true}));
  check('Educational feature selection fills agenda name',ps.speakerName==='Fixture Educator'&&ps.speakerRole==='Educational Speaker');
  feature.value='tom';feature.dispatchEvent(new Event('change',{bubbles:true}));
  check('TOM feature selection restores agenda name',ps.speakerName==='Fixture Toastmaster'&&ps.speakerRole==='Toastmaster of the Meeting');

 }catch(error){check('QA execution',false,String(error.stack||error));}
 const box=document.createElement('section');box.id='qa-report';box.style.cssText='position:fixed;inset:20px;z-index:2147483647;overflow:auto;padding:24px;background:#101d30;color:white;font:16px monospace';
 const title=document.createElement('h1');title.textContent='v487 synthetic-data QA';box.appendChild(title);
 const summary=document.createElement('p');summary.id='qa-summary';summary.textContent=results.filter(r=>r.pass).length+'/'+results.length+' checks passed';box.appendChild(summary);
 const list=document.createElement('pre');list.textContent=results.map(r=>(r.pass?'PASS':'FAIL')+' '+r.name+(r.detail?' — '+r.detail:'')).join('\n');box.appendChild(list);document.body.appendChild(box);
});
