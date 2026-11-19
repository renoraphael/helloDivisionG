(function (global) {
 'use strict';
 const input=global.HDG_MEMBER_V632_CONTEXT||{};
 const data=input.community||{};
 const byNumber=new Map();
 const safeText=(value,max=300)=>typeof value==='string'?value.slice(0,max):'';
 const clubs=(data.clubs||[]).map(club=>{
  const number=safeText(club.number,24);
  const info={
   id:number||safeText(club.name,160),
   number,
   name:safeText(club.name,160),
   area:safeText(club.area,16),
   city:safeText(club.city,100),
   island:safeText(club.island,100),
   mode:safeText(club.mode,50),
   dcpGoals:Number.isInteger(club.dcpGoals)&&club.dcpGoals>=0&&club.dcpGoals<=10?club.dcpGoals:null,
   officialAward:safeText(club.award,64),
   publicProfile:{
    meetingSchedule:safeText(club.schedule),
    timezone:safeText(club.timezone,64),
    meetingMode:safeText(club.meetingMode,50)||safeText(club.mode,50),
    locationTitle:safeText(club.locationTitle,160),
    locationAddress:safeText(club.locationAddress,220),
    publicLocation:safeText(club.publicLocation,300),
    inactive:club.inactive===true||club.inactive==='true'||club.mode==='Inactive',
    calendarBrand:club.fill?{
     fill:safeText(club.fill,7),text:safeText(club.text,7),accent:safeText(club.accent,7),
     shortName:safeText(club.shortName,100)
    }:null,
    calendarShortName:safeText(club.shortName,100)
   }
  };
  if(number)byNumber.set(number.replace(/^0+/,''),info);
  return info;
 });
 const clubAgendaDefaults=new Map();
 for(const [number,defaults] of Object.entries(data.clubAgendaDefaults||{})){
  if(!byNumber.has(number)||!defaults||typeof defaults!=='object')continue;
  const settings={zoomId:safeText(defaults.zoomId,100),zoomPass:safeText(defaults.zoomPass,100),people:new Map()};
  for(const [name,profile] of Object.entries(defaults.people||{})){
   if(!profile||typeof profile!=='object')continue;
   settings.people.set(name,{ig:safeText(profile.ig,100),email:safeText(profile.email,200)});
  }
  clubAgendaDefaults.set(number,settings);
 }
 const agendaMembers=[];
 for(const row of data.agendaMembers||[]){
  const club=byNumber.get(safeText(row.clubNumber,24).trim().replace(/^0+/,''));
  const name=safeText(row.name,160).trim();
  if(club&&name)agendaMembers.push({name,clubNumber:club.number,clubName:club.name,active:true});
 }
 const clubOfficers=new Map();
 for(const row of data.clubOfficers||[]){
  const number=safeText(row.clubNumber,24).trim().replace(/^0+/,'');
  const name=safeText(row.name,120).trim();
  if(!name||!byNumber.has(number)||!['Club President','Club VP Education','Club VP Membership','Club VP PR','Club Secretary','Club Treasurer','Club Sergeant at Arms'].includes(row.role))continue;
  if(!clubOfficers.has(number))clubOfficers.set(number,new Map());
  clubOfficers.get(number).set(row.role,{name});
 }
 const director=(data.leaders||[]).find(row=>row.role==='Division Director');
 const areas=(data.leaders||[]).filter(row=>row.role==='Area Director').map(row=>({code:safeText(row.scope,16),director:safeText(row.name,120)}));
 const tlis=[],contests=[],specialMeetings=[];
 for(const [index,event] of (data.events||[]).entries()){
  const item={
   id:'event-'+index,
   name:safeText(event.title,180),
   title:safeText(event.title,180),
   date:safeText(event.date,10),
   start:safeText(event.time,25),
   startTime:safeText(event.time,25),
   timezone:safeText(event.timezone,64)
  };
  if(event.kind==='TLI')tlis.push(item);
  if(event.kind==='Contest')contests.push(item);
  if(event.kind==='Club meeting'){
   const number=safeText(event.clubNumber,24);
   const club=byNumber.get(number.replace(/^0+/,''));
   if(club)specialMeetings.push({...item,clubNumber:club.number,clubName:club.name});
  }
 }
 global.HDG_MEMBER_V632_DATA={clubs,clubAgendaDefaults,agendaMembers,clubOfficers,areas,tlis,contests,specialMeetings,updated:safeText(data.updated,64),
  director:safeText(director?.name,120),memberName:safeText(data.memberName,120).trim()||'Member'};
 global.HDG_MEMBER_V632_ACCOUNT=/^[0-9a-f-]{36}$/i.test(input.account||'')?input.account:'preview';
 global.addEventListener('DOMContentLoaded',()=>{
  const switcher=document.getElementById('userSwitcher');
  if(!switcher)return;
  const signout=document.createElement('button');
  signout.type='button';
  signout.className='btn ghost';
  signout.textContent='Sign out';
  signout.onclick=()=>{
   window.sessionStorage.removeItem('hdg.cloud.session.v1');
   location.replace(location.pathname);
  };
  const summary=switcher.querySelector('summary');
  if(summary){summary.setAttribute('aria-disabled','true');summary.onclick=event=>event.preventDefault();}
  switcher.after(signout);
 });
})(window);
