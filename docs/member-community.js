(function (global) {
 'use strict';

 const pages = [
  ['events','Events & Calendar','Meetings and activities','Division Calendar','Dated Division activities plus recurring club meeting schedules.'],
  ['agenda','Agenda','Build meeting agendas','Meeting Automation','Paste a WhatsApp roster or choose a meeting draft to build the agenda.'],
  ['ttm','TTM Tool','Table Topics picture board','Table Topics','Prepare questions and pictures for your meeting.'],
  ['slides','Slides','Meeting presentation','Club Presentation','Present slides from the current meeting draft.'],
  ['meetingTools','Timer & Ballot','Speech timer and voting','Meeting Tools','Time speeches and record votes during the meeting.'],
  ['poster','Poster Generator','Create club social posters','Club Posters','Create a social poster for your club meeting.'],
  ['district87','Explore District 87','Discover other clubs','Visit Other Clubs','Browse District 87 by club, Division, or Area.'],
  ['recognition','Recognition','Club milestones','Club Recognition','Official club recognition recorded for Division G.'],
  ['council','Leadership Directory','Find Division and club leaders','Leadership Directory','Find Division and Area Directors.']
 ];

 function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text != null) node.textContent = text;
  if (className) node.className = className;
  return node;
 }

 function button(text, action, className = 'member-button') {
  const node = element('button',text,className);
  node.type = 'button';
  node.onclick = action;
  return node;
 }

 function card(title, ...content) {
  const node = element('section',null,'member-card');
  node.append(element('h3',title),...content);
  return node;
 }

 function field(label, input) {
  const node = element('label',null,'member-field');
  node.append(element('span',label),input);
  return node;
 }

 function select(choices) {
  const node = element('select');
  for (const [value,label] of choices) {
   const opt = element('option',label);
   opt.value = value;
   node.append(opt);
  }
  return node;
 }

 function download(blob, name) {
  const url = URL.createObjectURL(blob);
  const link = element('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url),1000);
 }

 function dateKey(date) {
  return [date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');
 }

 function recurringDays(schedule, year, month) {
  const name = /sunday|monday|tuesday|wednesday|thursday|friday|saturday/i.exec(schedule)?.[0].toLowerCase();
  if (!name) return [];
  const weekday = ['sunday','monday','tuesday','wednesday','thursday','friday','saturday'].indexOf(name);
  const dates = [];
  const last = new Date(year,month+1,0).getDate();
  for (let i=1; i<=last; i++) if (new Date(year,month,i).getDay()===weekday) dates.push(i);
  if (/\blast\b/i.test(schedule)) return dates.slice(-1);
  const ordinals = [...new Set(Array.from(schedule.matchAll(/\b([1-5])(?:st|nd|rd|th)\b/gi),m=>Number(m[1])))];
  return ordinals.length ? ordinals.map(n=>dates[n-1]).filter(Boolean) : /\bevery\b/i.test(schedule) ? dates : [];
 }

 const regions = [['east-java','East Java'],['bali','Bali'],['kalimantan','Kalimantan'],['sulawesi','Sulawesi'],['online','Online']];

 function clubRegion(club) {
  if (/online/i.test([club.mode,club.city,club.island].join(' '))) return 'online';
  const place = [club.city,club.island].join(' ');
  if (/east java|surabaya|malang|kediri|pare|sidoarjo/i.test(place)) return 'east-java';
  if (/bali|denpasar|sanur|ubud|jimbaran|canggu/i.test(place)) return 'bali';
  if (/kalimantan|samarinda|tarakan/i.test(place)) return 'kalimantan';
  if (/sulawesi|makassar/i.test(place)) return 'sulawesi';
  return '';
 }

 function eventColour(item) {
  if(item.kind==='TLI')return {fill:'#167A91',text:'#fff'};
  if(item.kind==='Contest')return {fill:'#F5D66E',text:'#163C80'};
  const hex=(value,fallback)=>/^#?[0-9a-f]{6}$/i.test(value||'')?'#'+value.replace(/^#/,''):fallback;
  return {fill:hex(item.club?.fill,'#315F9D'),text:hex(item.club?.text,'#fff'),accent:hex(item.club?.accent,'')};
 }

 function zoneOffset(zone) {
  if(/wib|jakarta/i.test(zone||''))return 7;
  if(/wit$|jayapura/i.test(zone||''))return 9;
  return 8;
 }

 function convertEvent(event, zone) {
  const match=/^(\d{1,2})(?:[:.](\d{2}))?\s*(AM|PM)?\b/i.exec(event.time||'');
  if(!match)return {...event,localTime:'',displayDate:event.date};
  const period=match[3]?.toUpperCase();
  const hours=period ? Number(match[1])%12+(period==='PM'?12:0) : Number(match[1]);
  const minutes=Number(match[2]||0);
  if(hours>23||minutes>59)return {...event,localTime:'',displayDate:event.date};
  const delta=(zoneOffset(zone)-zoneOffset(event.timezone))*60;
  const date=new Date(event.date+'T00:00:00');
  date.setMinutes(hours*60+minutes+delta);
  const localHour=date.getHours(), minute=String(date.getMinutes()).padStart(2,'0');
  return {...event,displayDate:dateKey(date),localTime:(localHour%12||12)+':'+minute+(localHour<12?' AM':' PM'),
   icsTime:String(localHour).padStart(2,'0')+minute+'00'};
 }

 function exportCalendar(events,zone,month) {
  const esc=value=>String(value||'').replace(/[\\;,]/g,'\\$&').replace(/[\r\n]+/g,'\\n');
  const offset=zone==='WIB'?'+07:00':'+08:00';
  const timestamp=new Date().toISOString().replace(/[-:]/g,'').replace(/\.\d+Z$/,'Z');
  const lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Hello Division G//Community//EN'];
  for(const [index,e] of events.entries()){
   const day=e.displayDate.replace(/-/g,'');
   const time=e.icsTime?.replace(/(..)(..)(..)/,'$1:$2:$3');
   const start=time?'DTSTART:'+new Date(e.displayDate+'T'+time+offset).toISOString().replace(/[-:]/g,'').replace(/\.\d+Z$/,'Z'):'DTSTART;VALUE=DATE:'+day;
   lines.push('BEGIN:VEVENT','UID:'+day+'-'+index+'@hello-division-g','DTSTAMP:'+timestamp,
    start,
    'SUMMARY:'+esc(e.title),'END:VEVENT');
  }
  lines.push('END:VCALENDAR','');
  download(new Blob([lines.join('\r\n')],{type:'text/calendar;charset=utf-8'}),'division-g-'+month+'.ics');
 }

 function showCalendar(out, data, panelActions) {
  const now = new Date();
  let month = new Date(now.getFullYear(),now.getMonth(),1);
  let zone='WITA', visible=[], selectedDate='';
  const showRegions=new Set(regions.map(([value])=>value));
  const shell=element('div',null,'member-calendar-shell');
  const toolbar=element('div',null,'member-calendar-toolbar');
  const left=element('div',null,'member-calendar-tools');
  const right=element('div',null,'member-calendar-tools');
  const title=element('h3',null,'member-calendar-title');
  const eventType=select([['','All event types'],['TLI','TLI'],['Contest','Contest'],['Club meeting','Club meetings']]);
  eventType.setAttribute('aria-label','Event type');
  const grid=element('div',null,'member-calendar');
  const weekdays=element('div',null,'member-weekdays');
  weekdays.append(...['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map(d=>element('strong',d)));
  const regionStrip=element('div',null,'member-region-strip');
  regionStrip.append(element('strong','Show clubs','member-region-label'));
  for(const [key,label] of regions){
   const check=element('input');
   check.type='checkbox';check.checked=true;
   check.onchange=()=>{if(check.checked)showRegions.add(key);else showRegions.delete(key);render();};
   const control=element('label',null,'member-region');
   control.append(check,element('span',label));
   regionStrip.append(control);
  }
  const legend=element('div',null,'member-calendar-legend');
  const agenda=card('Events & Meetings');
  const map=element('section',null,'member-map');
  const mapCanvas=element('div',null,'member-map-canvas');
  const mapLegend=element('aside',null,'member-map-legend');
  mapCanvas.append(element('h3','Division G footprint'),element('div',null,'member-map-shape'));
  map.append(mapCanvas,mapLegend);
  const clubs=(data.clubs||[]).filter(c=>c.inactive!=='true'&&!/inactive/i.test(c.mode||''));
  const byName=new Map(clubs.map(c=>[c.name,c]));
  for(const [key,label] of regions){
   const rows=clubs.filter(c=>clubRegion(c)===key);
   if(!rows.length)continue;
   mapLegend.append(card(label,...rows.map(c=>element('p',c.name))));
   const coords={'east-java':[25,77],'bali':[45,82],kalimantan:[61,34],sulawesi:[83,58]}[key];
   if(coords){
    const marker=button(label+' · '+rows.length,()=>{
     mapLegend.replaceChildren(card(label,...rows.map(c=>element('p',[c.name,c.city,c.schedule].filter(Boolean).join(' · ')))),button('Show all regions',()=>renderMapLegend()));
    },'member-map-marker');
    marker.style.left=coords[0]+'%';marker.style.top=coords[1]+'%';
    mapCanvas.append(marker);
   }
  }
  const initialLegend=[...mapLegend.children];
  function renderMapLegend(){mapLegend.replaceChildren(...initialLegend);}
  const switcher=element('div',null,'member-segment');
  const calendarMode=button('Calendar',()=>switchView(false));
  const mapMode=button('Division Map',()=>switchView(true));
  switcher.append(calendarMode,mapMode);
  panelActions.append(switcher,eventType);
  function switchView(enabled){
   shell.hidden=agenda.hidden=eventType.hidden=enabled;
   map.hidden=!enabled;
   calendarMode.setAttribute('aria-pressed',String(!enabled));
   mapMode.setAttribute('aria-pressed',String(enabled));
  }
  function move(delta) {
   month=new Date(month.getFullYear(),month.getMonth()+delta,1);selectedDate='';render();
  }
  const previous=button('←',()=>move(-1)), next=button('→',()=>move(1));
  previous.setAttribute('aria-label','Previous month');next.setAttribute('aria-label','Next month');
  left.append(previous,button('Today',()=>{
   month=new Date(now.getFullYear(),now.getMonth(),1);selectedDate='';render();
  }));
  const zoneGroup=element('div',null,'member-segment member-zone');
  zoneGroup.append(element('span','Display time'));
  const zoneControls=new Map();
  for(const name of ['WIB','WITA']){
   const control=button(name,()=>{zone=name;selectedDate='';render();});
   zoneControls.set(name,control);zoneGroup.append(control);
  }
  right.append(zoneGroup,button('Calendar .ics',()=>exportCalendar(visible,zone,dateKey(month).slice(0,7))),next);
  toolbar.append(left,title,right);
  eventType.onchange=()=>{selectedDate='';render();};
  shell.append(toolbar,regionStrip,legend,weekdays,grid);
  out.append(shell,agenda,map);
  switchView(false);
  const events=[...(data.events||[]),...(data.meetings||[]).map(m=>({...m,kind:'Club meeting',title:m.club||'Club meeting'}))];
  function render(){
   const y=month.getFullYear(),m=month.getMonth(),prefix=dateKey(month).slice(0,7);
   title.textContent=month.toLocaleDateString('en',{month:'long',year:'numeric'});
   for(const [name,control] of zoneControls)control.setAttribute('aria-pressed',String(name===zone));
   const monthEvents=events.map(e=>({...e,club:byName.get(e.club||e.title)}));
   for(const club of clubs.filter(c=>c.schedule)){
    for(const day of recurringDays(club.schedule,y,m)){
     const date=dateKey(new Date(y,m,day));
     if((date>='2026-12-20'&&date<='2027-01-04')||(date>='2027-12-19'&&date<='2028-01-04'))continue;
     if(!monthEvents.some(e=>e.date===date&&e.title===club.name))monthEvents.push({
      date,title:club.name,kind:'Club meeting',time:club.schedule.match(/\d{1,2}(?:[.:]\d{2})?\s*(?:AM|PM)/i)?.[0],timezone:club.timezone,club
     });
    }
   }
   visible=monthEvents.filter(e=>(!eventType.value||e.kind===eventType.value)&&(!e.club||!clubRegion(e.club)||showRegions.has(clubRegion(e.club))))
    .map(e=>convertEvent(e,zone)).filter(e=>e.displayDate?.startsWith(prefix))
    .sort((a,b)=>a.displayDate.localeCompare(b.displayDate)||(a.icsTime||'').localeCompare(b.icsTime||'')||a.title.localeCompare(b.title));
   const brandLegend=new Map();
   for(const item of visible){
    if(item.kind==='Club meeting'&&item.club?.fill)brandLegend.set(item.club.shortName||item.title,eventColour(item).fill);
   }
   legend.replaceChildren(element('strong','Colors = club identity'),element('span','Format is shown on each event'));
   for(const [label,fill] of brandLegend){
    const key=element('span',label,'member-legend-key');
    const dot=element('i');dot.style.backgroundColor=fill;key.prepend(dot);legend.append(key);
   }
   grid.replaceChildren();
   const offset=(month.getDay()+6)%7;
   const days=new Date(y,m+1,0).getDate();
   const cells=Math.ceil((days+offset)/7)*7;
   for(let index=0;index<cells;index++){
    const day=index-offset+1, date=dateKey(new Date(y,m,day));
    const inMonth=day>=1&&day<=days;
    const cell=element('div',null,'member-day'+(inMonth?'':' muted-month'));
    cell.append(element('strong',String(new Date(y,m,day).getDate()),'member-day-number'));
    if(date===dateKey(now))cell.setAttribute('aria-current','date');
    const items=visible.filter(e=>e.displayDate===date);
    for(const event of items){
     const tile=button('',()=>{selectedDate=date;showList();agenda.scrollIntoView({block:'nearest'});},'member-calendar-event');
     tile.setAttribute('aria-label',event.title+' '+(event.localTime||''));
     const brand=eventColour(event);tile.style.backgroundColor=brand.fill;tile.style.color=brand.text;
     if(brand.accent)tile.style.borderLeft='4px solid '+brand.accent;
     const top=element('div',null,'member-event-top');
     const mode=event.club?.mode||event.kind;
     top.append(element('span',event.localTime||''),element('small',mode));
     tile.append(top,element('strong',event.club?.shortName||event.title));
     cell.append(tile);
    }
    grid.append(cell);
   }
   showList();
  }
  function showList(){
   agenda.replaceChildren(element('h3',selectedDate||'Events & Meetings'));
   if(selectedDate)agenda.append(button('Show month',()=>{selectedDate='';showList();}));
   const list=element('ul',null,'member-rows');
   for(const e of visible.filter(e=>!selectedDate||e.displayDate===selectedDate)){
    const row=element('li');
    row.append(element('strong',e.title),element('span',[e.displayDate,e.localTime,e.localTime?zone:'',e.kind].filter(Boolean).join(' · ')));
    list.append(row);
   }
   agenda.append(list.childElementCount?list:element('p','No meetings or activities are scheduled for this selection.'));
  }
  render();
 }

 function browse(out, data, key) {
  if (key==='district87') {
   const status=element('p','Loading District 87 clubs…');
   const search=element('input');
   search.type='search';
   const link=element('a','Toastmasters Find a Club');
   link.href='https://www.toastmasters.org/find-a-club';
   link.target='_blank';
   link.rel='noopener noreferrer';
   out.append(field('Search club name, number or division',search),link,status);
   fetch(new URL('district87-clubs.json',location.href)).then(r=>{
    if (!r.ok) throw Error('Directory unavailable');
    return r.json();
   }).then(clubs=>{
    function render() {
     const term=search.value.trim().toLowerCase();
     const rows=clubs.filter(c=>[c.name,c.number,'Division '+c.division].join(' ').toLowerCase().includes(term));
     status.replaceChildren(element('strong',rows.length+' clubs'));
     const list=element('ul',null,'member-rows');
     for(const c of rows) {
      const row=element('li');
      row.append(element('strong',c.name),element('span',['Division '+c.division,'Area '+c.area,c.meetingSchedule,c.meetingMode].filter(Boolean).join(' · ')));
      list.append(row);
     }
     status.after(list);
     search.oninput=()=>{list.remove();render();};
    }
    render();
   }).catch(()=>{status.textContent='The club directory is unavailable. You can still open Toastmasters Find a Club.';});
   return;
  }
  const list=element('ul',null,'member-rows');
  const rows=key==='council'?(data.leaders||[]):(data.clubs||[]).filter(c=>c.award);
  for(const row of rows) {
   const item=element('li');
   item.append(element('strong',row.name),element('span',key==='council'?[row.role,row.scope].join(' · '):[row.area,row.award].join(' · ')));
   list.append(item);
  }
  out.append(rows.length?list:element('p',key==='council'?'No leadership entries are available.':'No official club recognition is recorded yet.'));
 }

 function mount(data,{accountId,signOut}) {
  const shell=element('div',null,'member-shell');
  const sidebar=element('aside',null,'member-sidebar');
  const sidebarPanel=element('div',null,'member-sidebar-panel');
  const brand=element('div',null,'member-brand-block');
  brand.append(element('div','Hello Division G!','member-wordmark'),element('p','District 87 · Region 9 · Toastmasters reporting system','member-subbrand'));
  const menu=element('nav',null,'member-menu');
  menu.setAttribute('aria-label','Community tools');
  const nav=new Map();
  const main=element('main',null,'member-main');
  const header=element('header',null,'member-header');
  const identity=element('div');
  identity.append(element('h1','Division G Community'));
  if(data.updated){
   const date=new Date(data.updated);
   if(!Number.isNaN(date.getTime()))identity.append(element('p','Dashboard updated: '+date.toLocaleString('en-GB',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Makassar'})));
  }
  header.append(identity,button('Sign out',signOut));
  const section=element('section',null,'member-workspace');
  section.id='community';
  const panelHead=element('div',null,'member-panel-head');
  const panelTitle=element('div');
  const eyebrow=element('div',null,'member-eyebrow');
  const heading=element('h2');
  const description=element('p');
  const panelActions=element('div',null,'member-panel-actions');
  panelTitle.append(eyebrow,heading,description);
  panelHead.append(panelTitle,panelActions);
  const content=element('div',null,'member-content');
  section.append(panelHead,content);
  main.append(header,section);
  const navHeading=element('div',null,'member-nav-heading');
  navHeading.append(element('span','Community'),element('small','Member tools'));
  menu.append(navHeading);
  sidebarPanel.append(brand,menu);
  sidebar.append(sidebarPanel);
  shell.append(sidebar,main);
  const tools=global.HDGMemberTools.create({data,accountId,ui:{element,button,card,field,select,download,dateKey}});
  let dispose;
  function show(key) {
   if(!nav.has(key))key='events';
   dispose?.();
   dispose=undefined;
   for(const [id,node] of nav) {
    if(id===key)node.setAttribute('aria-current','page');
    else node.removeAttribute('aria-current');
   }
   const [,label,,kicker,detail]=pages.find(([id])=>id===key);
   eyebrow.textContent=kicker;
   heading.textContent=label;
   description.textContent=detail;
   panelActions.replaceChildren();
   content.replaceChildren();
   if(key==='events') showCalendar(content,data,panelActions);
   else if(['district87','recognition','council'].includes(key)) browse(content,data,key);
   else dispose=tools[key](content);
  }
  for(const [key,label,caption] of pages) {
   const control=button('',()=>{history.replaceState(null,'','#community/'+key);show(key);},'member-nav-link');
   control.setAttribute('aria-label',label);
   control.append(element('strong',label),element('small',caption));
   nav.set(key,control);
   menu.append(control);
  }
  global.addEventListener('hashchange',()=>show(location.hash.split('/')[1]));
  show(location.hash.split('/')[1]);
  return shell;
 }

 global.HDGMemberCommunity={mount};
})(window);
