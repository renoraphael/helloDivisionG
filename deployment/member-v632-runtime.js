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
   officialAward:safeText(club.award,64),
   publicProfile:{
    meetingSchedule:safeText(club.schedule),
    timezone:safeText(club.timezone,64),
    meetingMode:safeText(club.mode,50),
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
 global.HDG_MEMBER_V632_DATA={clubs,areas,tlis,contests,specialMeetings,updated:safeText(data.updated,64),
  director:safeText(director?.name,120)};
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
