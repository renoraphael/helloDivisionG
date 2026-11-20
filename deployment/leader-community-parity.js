/* Leader app: like the Member app, the Poster Generator opens empty. A poster left in progress is kept as a draft that
   "Resume last poster" brings back (db.ui is local to this browser). Runs once, as soon as the app state is ready. */
(function(){
 let done=false;
 function tick(){
  if(done)return;
  try{
   if(typeof db==='undefined'||!db||!db.ui)return;
   done=true;
   const g=db.ui.clubPosterGenerator;
   if(g&&g.clubId){
    db.ui.memberPosterDraft=g;
    db.ui.clubPosterGenerator={ratio:'4:5'};
    try{if(typeof window.renderPosterGenerator==='function')window.renderPosterGenerator(true);}catch(_){}
   }
  }catch(_){}
 }
 const timer=setInterval(()=>{tick();if(done)clearInterval(timer);},400);
 setTimeout(()=>clearInterval(timer),30000);
})();
