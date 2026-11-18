(function (global) {
 'use strict';

 function create({data,accountId,ui}) {
  const {element,button,card,field,select,download,dateKey}=ui;
  const key='hdg.member.meetings.v1.'+accountId;
  const make=()=>({id:crypto.randomUUID(),club:'',date:dateKey(new Date()),theme:'',roster:'',topics:[],votes:{}});
  let state={active:null,meetings:[]};
  try {
   const saved=JSON.parse(localStorage.getItem(key)||'null');
   if(Array.isArray(saved?.meetings)&&saved.meetings.length)state=saved;
  } catch (_) {}
  if(!state.meetings.length)state.meetings.push(make());
  const active=()=>state.meetings.find(m=>m.id===state.active)||state.meetings[0];
  function save(status) {
   try {
    localStorage.setItem(key,JSON.stringify(state));
    if(status)status.textContent='Saved in this browser.';
   } catch (_) {
    if(status)status.textContent='Browser storage is full or unavailable. Keep this tab open to retain your work.';
   }
  }
  function meetingSelector(out, render) {
   const current=active();
   const choice=select(state.meetings.map(m=>[m.id,[m.club,m.date,m.theme].filter(Boolean).join(' · ')||'Untitled meeting']));
   choice.value=current.id;
   choice.onchange=()=>{state.active=choice.value;save();render();};
   const row=element('div',null,'member-tool-row');
   row.append(field('My meeting draft',choice),button('New meeting',()=>{
    const draft=make();
    state.meetings.push(draft);state.active=draft.id;save();render();
   }));
   out.append(row);
  }
  function resetPanel(out, draw) {
   const render=()=>{out.replaceChildren();meetingSelector(out,render);draw(active());};
   render();
  }
  function textInput(type,value) {
   const input=element('input');
   input.type=type;
   input.value=value||'';
   return input;
  }
  function agenda(out) {
   resetPanel(out,draft=>{
    const club=textInput('text',draft.club);
    const suggestions=element('datalist');
    suggestions.id='member-club-suggestions';
    for(const item of data.clubs||[]) {
     const option=element('option');
     option.value=item.name;
     suggestions.append(option);
    }
    club.setAttribute('list',suggestions.id);
    const date=textInput('date',draft.date), theme=textInput('text',draft.theme);
    const roster=element('textarea');
    roster.value=draft.roster;
    roster.rows=12;
    roster.placeholder='Toastmaster: …\nSpeaker 1: …\nEvaluator 1: …';
    const status=element('p','Drafts are stored in this browser.','member-tool-status');
    status.setAttribute('role','status');
    const printable=element('article',null,'member-agenda-print');
    function refresh() {
     Object.assign(draft,{club:club.value,date:date.value,theme:theme.value,roster:roster.value});
     printable.replaceChildren(element('h3',draft.club||'Meeting agenda'),
      element('p',[draft.date,draft.theme].filter(Boolean).join(' · ')),element('pre',draft.roster||'Add meeting roles and agenda items.'));
    }
    for(const control of [club,date,theme,roster])control.oninput=()=>{refresh();save(status);};
    const row=element('div',null,'member-tool-row');
    row.append(field('Club',club),field('Date',date),field('Theme',theme));
    out.append(card('Build a meeting agenda',row,suggestions,field('Paste or edit the WhatsApp roster',roster),
     button('Print / save PDF',()=>global.print()),status),printable);
    refresh();
   });
  }
  function ttm(out) {
   resetPanel(out,draft=>{
    draft.topics??=[];
    const question=textInput('text',''), file=textInput('file','');
    file.accept='image/*';
    const status=element('p',null,'member-tool-status');
    status.setAttribute('role','status');
    const board=element('div',null,'member-topic-board');
    function draw() {
     board.replaceChildren();
     for(const [i,topic] of draft.topics.entries()) {
      const tile=card('Topic '+(i+1),element('p',topic.question));
      if(/^data:image\/(?:png|webp);base64,/.test(topic.image||'')){
       const image=element('img');
       image.src=topic.image;image.alt='Table Topics image';
       tile.prepend(image);
      }
      tile.append(button('Remove',()=>{draft.topics.splice(i,1);save(status);draw();}));
      board.append(tile);
     }
     if(!draft.topics.length)board.append(element('p','Add a prompt or image to start your board.'));
    }
    const add=button('Add topic',async()=>{
     if(!question.value.trim()&&!file.files[0]){status.textContent='Enter a prompt or choose a picture.';return;}
     add.disabled=true;
     try {
      let image='';
      if(file.files[0]){
       const bitmap=await createImageBitmap(file.files[0]);
       const canvas=element('canvas');
       const scale=Math.min(1,1000/Math.max(bitmap.width,bitmap.height));
       canvas.width=Math.max(1,Math.round(bitmap.width*scale));
       canvas.height=Math.max(1,Math.round(bitmap.height*scale));
       canvas.getContext('2d').drawImage(bitmap,0,0,canvas.width,canvas.height);
       bitmap.close();
       image=canvas.toDataURL('image/webp',0.8);
      }
      draft.topics.push({question:question.value.trim(),image});
      question.value='';file.value='';save(status);draw();
     } catch (_) {status.textContent='This picture could not be opened.';}
     finally {add.disabled=false;}
    });
    out.append(card('Table Topics picture board',field('Prompt',question),field('Picture',file),add,status),board);
    draw();
   });
  }
  function slides(out) {
   resetPanel(out,draft=>{
    const slides=[[draft.club||'Toastmasters meeting',[draft.date,draft.theme].filter(Boolean).join(' · ')],
     ...draft.roster.split(/\r?\n/).filter(line=>line.trim()).map(line=>{
      const split=line.indexOf(':');
      return split<0?[line,'']:[line.slice(0,split),line.slice(split+1).trim()];
     }),...draft.topics.map(topic=>['Table Topics',topic.question,topic.image])];
    const dialog=element('dialog',null,'member-slide-dialog');
    const count=element('p'), surface=element('div',null,'member-slide-surface');
    let index=0;
    function display(delta) {
     index=Math.max(0,Math.min(slides.length-1,index+delta));
     const [title,content,image]=slides[index];
     count.textContent=(index+1)+' / '+slides.length;
     surface.replaceChildren(element('h3',title),element('p',content));
     if(/^data:image\/(?:png|webp);base64,/.test(image||'')){
      const pic=element('img');
      pic.src=image;pic.alt='Table Topics image';surface.append(pic);
     }
    }
    dialog.append(count,surface,button('Previous slide',()=>display(-1)),button('Next slide',()=>display(1)),button('Close',()=>dialog.close()));
    dialog.onkeydown=e=>{if(e.key==='ArrowRight')display(1);if(e.key==='ArrowLeft')display(-1);};
    out.append(card('Meeting presentation',element('p',slides.length+' slides from your agenda and Table Topics board.'),
     button('Present slides',()=>{index=0;display(0);dialog.showModal();})),dialog);
   });
  }
  function meetingTools(out) {
   let resetTimer=()=>{};
   resetPanel(out,draft=>{
    resetTimer();
    const preset=select([['5,6,7','Prepared speech · 5–7 min'],['2,2.5,3','Evaluation · 2–3 min'],['1,1.5,2','Table Topics · 1–2 min']]);
    const clock=element('output','00:00','member-timer');
    const stage=element('p','Ready');
    let elapsed=0,started=0,handle;
    function paint() {
     const seconds=Math.floor((elapsed+(started?performance.now()-started:0))/1000);
     clock.textContent=String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0');
     const [green,yellow,red]=preset.value.split(',').map(Number);
     const color=seconds>=red*60?'red':seconds>=yellow*60?'yellow':seconds>=green*60?'green':'';
     clock.dataset.stage=color;
     stage.textContent=color?color[0].toUpperCase()+color.slice(1):started?'Running':seconds?'Paused':'Ready';
    }
    function pause() {
     if(started)elapsed+=performance.now()-started;
     started=0;clearInterval(handle);paint();
    }
    resetTimer=()=>clearInterval(handle);
    preset.onchange=()=>{pause();elapsed=0;paint();};
    out.append(card('Speech timer',field('Timing preset',preset),clock,stage,button('Start',()=>{
     if(started)return;
     started=performance.now();handle=setInterval(paint,100);paint();
    }),button('Pause',pause),button('Reset timer',()=>{pause();elapsed=0;paint();})));
    draft.votes??={};
    const candidate=textInput('text',''), tally=element('ul',null,'member-rows');
    const voteStatus=element('p','Local counts are saved in this browser. Ask a leader to publish a link for attendees.','member-tool-status');
    const category=select([['prepared','Prepared Speaker'],['evaluation','Evaluation'],['topics','Table Topics']]);
    function renderTally() {
     tally.replaceChildren();
     const selected=draft.votes[category.value]||{};
     for(const [name,total] of Object.entries(selected).sort((a,b)=>b[1]-a[1]))tally.append(element('li',name+' · '+total));
    }
    category.onchange=renderTally;
    out.append(card('Manual ballot tally',field('Category',category),field('Candidate name',candidate),button('Record vote',()=>{
     const name=candidate.value.trim();
     if(!name)return;
     const votes=draft.votes[category.value]||{};
     draft.votes[category.value]={...votes,[name]:(Object.hasOwn(votes,name)?votes[name]:0)+1};
     candidate.value='';save();renderTally();
    }),voteStatus,tally));
    renderTally();
   });
   return ()=>resetTimer();
  }
  function poster(out) {
   resetPanel(out,draft=>{
    const title=textInput('text',draft.theme||'Club meeting');
    const club=textInput('text',draft.club||'Toastmasters');
    const date=textInput('text',draft.date);
    const palette=select([['#06436b','Toastmasters blue'],['#651c32','Toastmasters maroon']]);
    const canvas=element('canvas',null,'member-poster');
    canvas.width=1080;canvas.height=1080;
    canvas.setAttribute('aria-label','Club poster preview');
    const ctx=canvas.getContext('2d');
    function draw() {
     ctx.fillStyle=palette.value;ctx.fillRect(0,0,1080,1080);
     ctx.fillStyle='#f2df74';ctx.fillRect(76,92,90,8);
     ctx.font='bold 32px system-ui';
     ctx.fillText('TOASTMASTERS',76,160,920);
     ctx.fillStyle='#fff';ctx.font='bold 76px system-ui';
     const words=(title.value.trim()||'Club meeting').split(/\s+/);
     let row='',y=360;
     for(const word of words){
      if(row&&ctx.measureText(row+' '+word).width>920){ctx.fillText(row,76,y,920);row=word;y+=90;}
      else row=(row+' '+word).trim();
      if(y>700)break;
     }
     ctx.fillText(row,76,y,920);
     ctx.font='bold 43px system-ui';ctx.fillText(club.value,76,858,920);
     ctx.font='40px system-ui';ctx.fillText(date.value,76,938,920);
    }
    for(const input of [title,club,date,palette])input.oninput=draw;
    out.append(card('Create a club poster',field('Poster title',title),field('Club',club),field('Meeting date or time',date),field('Colour theme',palette),
     button('Download poster PNG',()=>canvas.toBlob(blob=>{if(blob)download(blob,'toastmasters-poster.png');}))),canvas);
    draw();
   });
  }
  return {agenda,ttm,slides,meetingTools,poster};
 }

 global.HDGMemberTools={create};
})(window);
