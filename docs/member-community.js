(function (global) {
 'use strict';

 const pages = [
  ['events','▦','Events & Calendar'],
  ['agenda','≡','Agenda'],
  ['ttm','▧','TTM Tool'],
  ['slides','▤','Slides'],
  ['meetingTools','◴','Timer & Ballot'],
  ['poster','▣','Poster Generator'],
  ['district87','◎','Explore District 87'],
  ['recognition','★','Recognition'],
  ['council','◇','Leadership Directory']
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

 function showCalendar(out, data) {
  const now = new Date();
  let month = new Date(now.getFullYear(),now.getMonth(),1);
  const toolbar = element('div',null,'member-tool-row');
  const title = element('h3');
  const eventType = select([['','All event types'],['Club meeting','Club meetings'],['TLI','TLI'],['Contest','Contest']]);
  const calendar = element('div',null,'member-calendar');
  const dayEvents = card('Meetings and activities');
  dayEvents.classList.add('member-calendar-events');
  const move = delta => {
   month = new Date(month.getFullYear(),month.getMonth()+delta,1);
   render();
  };
  toolbar.append(button('Previous month',()=>move(-1)),title,button('Next month',()=>move(1)),field('Event type',eventType));
  eventType.onchange = render;
  const clubSchedules = (data.clubs||[]).filter(c=>c.schedule&&c.inactive!=='true'&&!/inactive/i.test(c.mode||''));
  const events = [...(data.events||[]),...(data.meetings||[]).map(m=>({...m,kind:'Club meeting',title:m.club||'Club meeting'}))];
  function render() {
   const y = month.getFullYear(), m = month.getMonth(), prefix = dateKey(month).slice(0,7);
   title.textContent = month.toLocaleDateString('en',{month:'long',year:'numeric'});
   const monthEvents = events.filter(e=>e.date?.startsWith(prefix));
   for (const club of clubSchedules) {
    for (const day of recurringDays(club.schedule,y,m)) {
     const date = dateKey(new Date(y,m,day));
     if ((date>='2026-12-20'&&date<='2027-01-04')||(date>='2027-12-19'&&date<='2028-01-04')) continue;
     if (!monthEvents.some(e=>e.title===club.name&&e.date===date)) monthEvents.push({
      date,title:club.name,kind:'Club meeting',time:club.schedule.match(/\d{1,2}(?:[.:]\d{2})?\s*(?:AM|PM)/i)?.[0],timezone:club.timezone
     });
    }
   }
   const visible = monthEvents.filter(e=>!eventType.value||e.kind===eventType.value).sort((a,b)=>a.date.localeCompare(b.date)||a.title.localeCompare(b.title));
   calendar.replaceChildren(...['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map(d=>element('strong',d,'member-weekday')));
   const offset = (month.getDay()+6)%7;
   for (let i=0;i<offset;i++) calendar.append(element('div',null,'member-day-spacer'));
   for (let day=1;day<=new Date(y,m+1,0).getDate();day++) {
    const date=dateKey(new Date(y,m,day)), items=visible.filter(e=>e.date===date);
    const control=button(String(day),()=>showList(items,date),'member-day');
    control.setAttribute('aria-label',date+' · '+items.length+' events');
    if (items.length) control.append(element('span',String(items.length),'member-day-count'));
    if (date===dateKey(now)) control.setAttribute('aria-current','date');
    calendar.append(control);
   }
   showList(visible);
  }
  function showList(items,date) {
   dayEvents.replaceChildren(element('h3',date||'Meetings and activities'));
   const list=element('ul',null,'member-rows');
   for (const event of items) {
    const row=element('li');
    row.append(element('strong',event.title),element('span',[event.date,event.time,event.timezone,event.kind].filter(Boolean).join(' · ')));
    list.append(row);
   }
   dayEvents.append(items.length?list:element('p','No meetings or activities are scheduled for this selection.'));
  }
  out.append(toolbar,calendar,dayEvents);
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
  const menu=element('nav',null,'member-menu');
  menu.setAttribute('aria-label','Community tools');
  const nav=new Map();
  const main=element('main',null,'member-main');
  const header=element('header',null,'member-header');
  const identity=element('div');
  identity.append(element('h1','Division G Member'),element('p','Community'));
  header.append(identity,button('Sign out',signOut));
  const section=element('section',null,'member-workspace');
  section.id='community';
  const heading=element('h2');
  const content=element('div',null,'member-content');
  section.append(heading,content);
  main.append(header,section);
  sidebar.append(element('div','Hello Division G','member-wordmark'),element('span','Community','member-nav-heading'),menu);
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
   heading.textContent=pages.find(([id])=>id===key)[2];
   content.replaceChildren();
   if(key==='events') showCalendar(content,data);
   else if(['district87','recognition','council'].includes(key)) browse(content,data,key);
   else dispose=tools[key](content);
  }
  for(const [key,icon,label] of pages) {
   const control=button(label,()=>{history.replaceState(null,'','#community/'+key);show(key);},'member-nav-link');
   const glyph=element('span',icon,'member-nav-icon');
   glyph.setAttribute('aria-hidden','true');
   control.prepend(glyph);
   nav.set(key,control);
   menu.append(control);
  }
  global.addEventListener('hashchange',()=>show(location.hash.split('/')[1]));
  show(location.hash.split('/')[1]);
  return shell;
 }

 global.HDGMemberCommunity={mount};
})(window);
