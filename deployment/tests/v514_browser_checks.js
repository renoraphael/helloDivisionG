window.addEventListener('load',async()=>{
 const results=[];const check=(name,pass,detail='')=>results.push({name,pass:!!pass,detail});
 const pause=ms=>new Promise(r=>setTimeout(r,ms));
 try{
  await DURABLE_INIT_PROMISE;await pause(2200);
  check('v514 release loaded',window.__HDG_APP_RELEASE__==='v514');
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
  check('Selected meeting is remembered',String(localStorage.getItem('hdg_active_meeting_v478')).includes(meeting.id),String(localStorage.getItem('hdg_active_meeting_v478')));
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
  if(tom){tom.value='Fixture Updated Toastmaster';tom.dispatchEvent(new Event('input',{bubbles:true}));tom.dispatchEvent(new Event('change',{bubbles:true}));if(document.querySelector('#v483Glance .v483-save'))document.querySelector('#v483Glance .v483-save').click();else saveAgendaRecordEditor();await waitForDurableSave();await HDGCloud.queue.flush();}
  check('Roles-at-a-glance edit reaches shared save',window.__QA_SAVES__.at(-1)?.p_payload?.database.meetingAgendaRecords?.[0]?.roles?.tom==='Fixture Updated Toastmaster');


  check('Roster comma and ordinal date parsing',agendaParseDate('Friday, November 13th, 2026')==='2026-11-13'&&agendaParseDate('Wed 2nd December 2026')==='2026-12-02');
  const edu=agendaParseEducationV491('Education session\nSpeaker: Fixture Educator\nTitle: Fixture Education\nProject: Successful Club Series\nTime: 10-15 mins\nSilent Evaluator: Fixture Evaluator\nPrepared Speakers\nSpeaker 1: Fixture Speaker');
  check('Education block parser retains structured fields',edu?.speaker==='Fixture Educator'&&edu?.title==='Fixture Education'&&edu?.time==='10-15 mins');
  db.ui.agendaClubFlowV490={'28680376':AGENDA_FLOW_C};
  check('Future meeting uses remembered club order',agendaMeetingFlow({...meeting,agendaFlowChosenV490:false,meetingDate:'2099-01-01'})===AGENDA_FLOW_C);
  document.querySelector('a[href="#community"]').click();showCommunityPanel('agenda');renderCommunityAgendaRecord();v489Tidy();await pause(200);
  check('Meeting format control exists',!!document.getElementById('v491Format'));
  check('Single compact meeting roles editor exists',!!document.getElementById('v483Glance')&&!!document.querySelector('.agenda-role-groups-v406')?.closest('.v489-hidden'));
  showCommunityPanel('poster');renderPosterGenerator();posterRenderV483();await pause(350);
  check('Theme picture panel renders',!!document.getElementById('v512Pic'));
  const ps=db.ui.clubPosterGenerator;
  Object.assign(ps,{clubId:'fixture-bsc',title:'Fixture Title',subtitle:'Fixture Subtitle',venue:'Fixture Hall',locationNote:'Fixture Hall, Fixture Street, Indonesia',feeMember:'Free',feeGuest:'75000',fee:'',formatLabel:'In-person',speakerName:'Fixture Host',speakerRole:'Toastmaster of the Meeting',registerUrl:'https://example.invalid/r',contactValue:'+620000000000',instagram:'@fixtureclub',regStyle:'link'});
  let valid=0;for(const id of layouts){ps.v483Layout=id;const svg=posterSvgV483();if(!new DOMParser().parseFromString(svg,'image/svg+xml').querySelector('parsererror'))valid++;}
  check('All 12 updated layouts render in link-text mode',valid===12,String(valid));
  const canvas=document.createElement('canvas');canvas.width=60;canvas.height=60;canvas.getContext('2d').fillRect(15,15,20,20);
  const png=await new Promise(r=>canvas.toBlob(r,'image/png'));posterBackgroundImageChangedV365(new File([png],'synthetic-transparent.png',{type:'image/png'}));await pause(500);
  check('Transparent import retains PNG and alpha flag',ps.backgroundImageAlpha===true&&ps.backgroundImage.startsWith('data:image/png'));
  canvas.getContext('2d').fillRect(0,0,60,60);const jpeg=await new Promise(r=>canvas.toBlob(r,'image/jpeg'));posterBackgroundImageChangedV365(new File([jpeg],'synthetic-photo.jpg',{type:'image/jpeg'}));await pause(500);
  check('Opaque photo import stays JPEG',db.ui.clubPosterGenerator.backgroundImageAlpha===false&&db.ui.clubPosterGenerator.backgroundImage.startsWith('data:image/jpeg'));

 }catch(error){check('QA execution',false,String(error.stack||error));}
 const box=document.createElement('section');box.id='qa-report';box.style.cssText='position:fixed;inset:20px;z-index:2147483647;overflow:auto;padding:24px;background:#101d30;color:white;font:16px monospace';
 const title=document.createElement('h1');title.textContent='v514 synthetic-data QA';box.appendChild(title);
 const summary=document.createElement('p');summary.id='qa-summary';summary.textContent=results.filter(r=>r.pass).length+'/'+results.length+' checks passed';box.appendChild(summary);
 const list=document.createElement('pre');list.textContent=results.map(r=>(r.pass?'PASS':'FAIL')+' '+r.name+(r.detail?' — '+r.detail:'')).join('\n');box.appendChild(list);document.body.appendChild(box);
});
