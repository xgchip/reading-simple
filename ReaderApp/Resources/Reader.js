(()=>{
'use strict';
const session=__SESSION__, chapter=__CHAPTER__, initial=__INITIAL__;
const root=document.getElementById('book-text'), canvas=document.getElementById('reader-canvas');
const highlights=document.getElementById('reader-highlights'), notes=document.getElementById('reader-notes');
const toolbar=document.getElementById('reader-selection'), popup=document.getElementById('reader-popup');
let marks=[], selected=null, desiredSidebar=true, font=19, raf=0, lastProgress=0, expanded=new Set(), activeID=null;
const textNodes=[];let text='';
const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode:n=>n.parentElement.closest('script,style,noscript,[data-reader-ui]')?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT});
let node;while(node=walker.nextNode()){textNodes.push({node,start:text.length,end:text.length+node.data.length});text+=node.data;}
function send(type,data={}){window.webkit.messageHandlers.reader.postMessage({type,session,chapter,...data});}
function rangeAt(start,end){
 if(start<0||end>text.length||end<=start)return null;
 const a=textNodes.find(n=>n.start<=start&&n.end>start),b=[...textNodes].reverse().find(n=>n.start<end&&n.end>=end);
 if(!a||!b)return null;const r=document.createRange();try{r.setStart(a.node,start-a.start);r.setEnd(b.node,end-b.start);return r;}catch{return null;}
}
function resolve(a){
 if(a.anchorVersion!==undefined&&a.anchorVersion!==1)return null;
 if(a.start>=0&&a.end>a.start&&text.slice(a.start,a.end)===a.quote)return rangeAt(a.start,a.end);
 if(!a.quote)return null;let matches=[],at=-1;
 while((at=text.indexOf(a.quote,at+1))!==-1){
  if(text.slice(Math.max(0,at-a.prefix.length),at)===a.prefix&&text.slice(at+a.quote.length,at+a.quote.length+a.suffix.length)===a.suffix)matches.push(at);
  if(matches.length>1000)break;
 }
 return matches.length===1?rangeAt(matches[0],matches[0]+a.quote.length):null;
}
function offsetAt(container,offset){
 const own=textNodes.find(n=>n.node===container);if(own)return own.start+Math.min(offset,own.node.data.length);
 const boundary=document.createRange();boundary.setStart(container,offset);boundary.collapse(true);let total=0;
 for(const entry of textNodes){if(boundary.comparePoint(entry.node,entry.node.data.length)<=0)total=entry.end;else break;}return total;
}
function capture(){const s=getSelection();if(!s||s.isCollapsed||!s.rangeCount)return null;const r=s.getRangeAt(0);if(!root.contains(r.startContainer)||!root.contains(r.endContainer))return null;
 const start=offsetAt(r.startContainer,r.startOffset),end=offsetAt(r.endContainer,r.endOffset);if(end<=start||end-start>200000)return null;
 return {start,end,quote:text.slice(start,end),prefix:text.slice(Math.max(0,start-48),start),suffix:text.slice(end,end+48)};
}
function selection(){selected=capture();if(!selected){toolbar.hidden=true;return;}const r=rangeAt(selected.start,selected.end),box=r.getBoundingClientRect();toolbar.hidden=false;
 toolbar.style.left=Math.max(8,Math.min(innerWidth-220,box.left))+'px';toolbar.style.top=Math.max(8,Math.min(innerHeight-45,box.bottom+8))+'px';}
for(const button of toolbar.querySelectorAll('button')){button.addEventListener('mousedown',e=>e.preventDefault());button.addEventListener('click',()=>{if(selected)send('selection',{anchor:selected,action:button.dataset.action});toolbar.hidden=true;getSelection().removeAllRanges();});}
document.addEventListener('mouseup',()=>setTimeout(selection,0));document.addEventListener('keyup',e=>{if(e.key==='Escape'){popup.hidden=true;toolbar.hidden=true;}else selection();});
function readingPoint(){
 const x=Math.max(4,root.getBoundingClientRect().left+Math.min(30,root.clientWidth/4)),y=60;
 const caret=document.caretRangeFromPoint?.(x,y);
 if(caret&&root.contains(caret.startContainer)){const offset=offsetAt(caret.startContainer,caret.startOffset),rect=rectForOffset(offset);return {offset,delta:rect?.top||60};}
 // Binary search the immutable text stream, retaining a position inside long paragraphs.
 let lo=0,hi=Math.max(0,text.length-1),best=0;
 while(lo<=hi){const mid=(lo+hi)>>1,r=rectForOffset(mid);if(!r){hi=mid-1;continue;}if(r.bottom<60){lo=mid+1;}else{best=mid;hi=mid-1;}}
 const rect=rectForOffset(best);return {offset:best,delta:rect?.top||60};
}
let stablePoint={offset:0,delta:48},resizePoint=null;
function rectForOffset(offset){const n=textNodes.find(n=>n.end>offset)||textNodes.at(-1);if(!n)return null;const start=Math.min(Math.max(offset,n.start),n.end-1);return rangeAt(start,start+1)?.getBoundingClientRect();}
function jumpOffset(offset,delta=48){const rect=rectForOffset(offset);if(rect)scrollBy(0,rect.top-delta);}
function keepPosition(change){const p=readingPoint();change();requestAnimationFrame(()=>{jumpOffset(p.offset,p.delta);stablePoint=readingPoint();schedule();});}
function sidebarVisible(){return desiredSidebar&&innerWidth>=810;}
function schedule(){if(!raf)raf=requestAnimationFrame(()=>{raf=0;layout();});}
function button(label,action){const b=document.createElement('button');b.textContent=label;b.addEventListener('click',e=>{e.stopPropagation();action();});return b;}
function openMark(id){activeID=id;const m=marks.find(m=>m.id===id);if(!m)return;const r=resolve(m);if(r){r.startContainer.parentElement?.classList.add('reader-flash');setTimeout(()=>r.startContainer.parentElement?.classList.remove('reader-flash'),1800);}
 send('openMark',{id});}
function showPopup(m){popup.replaceChildren();const quote=document.createElement('blockquote');quote.textContent=m.quote;const body=document.createElement('p');body.textContent=m.note||'这是一条划线，可以补写想法。';popup.append(quote,body,button(m.draft!==null&&m.draft!==undefined?'继续草稿':'写想法 / 编辑',()=>{popup.hidden=true;send('edit',{id:m.id});}),button('关闭',()=>{popup.hidden=true;document.querySelector(`[data-mark-id="${m.id}"]`)?.focus();}));popup.hidden=false;}
function layout(){
 const side=sidebarVisible();canvas.classList.toggle('with-notes',side);highlights.replaceChildren();notes.replaceChildren();let bottom=0;const markerRows=[];
 const ordered=marks.map(m=>({m,r:resolve(m)})).filter(x=>x.r).sort((a,b)=>a.m.start-b.m.start||a.m.end-b.m.end);
 for(const {m,r} of ordered){
  const rects=[...r.getClientRects()].filter(x=>x.width>0&&x.height>0);
  for(const rect of rects){const box=document.createElement('div');box.className='reader-highlight'+(activeID===m.id?' active':'');Object.assign(box.style,{left:(rect.left+scrollX)+'px',top:(rect.top+scrollY)+'px',width:rect.width+'px',height:rect.height+'px'});highlights.append(box);}
  const rect=rects[0];if(!rect)continue;
  const marker=button(m.note?'●':'＋',()=>{if(!m.note){send('edit',{id:m.id});return;}openMark(m.id);if(!side||!m.note)showPopup(m);schedule();});marker.className='reader-marker';marker.dataset.markId=m.id;marker.setAttribute('aria-label',m.note?'查看这句话的备注':'为划线写想法');let markerY=rect.top+scrollY;while(markerRows.some(y=>Math.abs(y-markerY)<25))markerY+=25;markerRows.push(markerY);Object.assign(marker.style,{left:(root.getBoundingClientRect().right+scrollX+7)+'px',top:markerY+'px'});highlights.append(marker);
  if(side&&m.note){const card=document.createElement('article');card.className='reader-note'+(activeID===m.id?' active':'');card.dataset.id=m.id;
   const body=document.createElement('p');body.textContent=m.note;body.className=expanded.has(m.id)?'':'collapsed';card.append(body);
   if(m.note.length>90||m.note.split('\n').length>4)card.append(button(expanded.has(m.id)?'收起':'展开',()=>{expanded.has(m.id)?expanded.delete(m.id):expanded.add(m.id);schedule();}));
   card.append(button('编辑',()=>send('edit',{id:m.id})));card.addEventListener('click',()=>{activeID=m.id;r.startContainer.parentElement?.scrollIntoView({block:'center',behavior:'smooth'});send('openMark',{id:m.id});schedule();});
   notes.append(card);const origin=canvas.getBoundingClientRect().top+scrollY;const y=Math.max(rect.top+scrollY,bottom+12);card.style.top=(y-origin)+'px';bottom=y+card.offsetHeight;
  }
 }
 document.body.style.minHeight=Math.max(root.getBoundingClientRect().bottom+scrollY+80,bottom+60)+'px';
}
window.Reader={
 update(payload){document.documentElement.dataset.texture=payload.texture===false?'off':'on';document.documentElement.dataset.theme=['white','paper','dark'].includes(payload.theme)?payload.theme:'paper';marks=payload.marks||[];desiredSidebar=payload.sidebar;const newFont=payload.font;
  if(font!==newFont||canvas.classList.contains('with-notes')!==sidebarVisible()){keepPosition(()=>{font=newFont;root.style.fontSize=font+'px';canvas.classList.toggle('with-notes',sidebarVisible());});}layout();schedule();},
 focus(id){clearTimeout(restoreTimer);const m=marks.find(m=>m.id===id),r=m&&resolve(m);activeID=id;schedule();if(!r){send('anchorFailed',{id});return false;}
  const y=r.getBoundingClientRect().top+scrollY;scrollTo(0,Math.max(0,y-110));if(sidebarVisible())expanded.add(id);else showPopup(m);schedule();return true;},
 restore(offset){jumpOffset(offset);stablePoint=readingPoint();schedule();},
 chapterFragment(id){const el=document.getElementById(id);if(el&&root.contains(el))el.scrollIntoView();},
 diagnostics(){return {text,textLength:text.length,marks:marks.map(m=>({id:m.id,resolved:!!resolve(m)})),sidebar:sidebarVisible()};},
 testAnchor(start,end){return {start,end,quote:text.slice(start,end),prefix:text.slice(Math.max(0,start-48),start),suffix:text.slice(end,end+48)};},
 testResolve(a){const r=resolve(a);return r?offsetAt(r.startContainer,r.startOffset):null;},
 testGeometry(){return [...notes.children].map(n=>({id:n.dataset.id,top:n.getBoundingClientRect().top,height:n.offsetHeight}));}
};
let resizeTimer;addEventListener('resize',()=>{if(!resizePoint)resizePoint={...stablePoint};clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{const p=resizePoint;resizePoint=null;if(p)jumpOffset(p.offset,p.delta);stablePoint=readingPoint();schedule();},80);});
new ResizeObserver(schedule).observe(root);root.querySelectorAll('img').forEach(img=>img.addEventListener('load',schedule));document.fonts?.ready.then(schedule);
let progressTimer;addEventListener('scroll',()=>{toolbar.hidden=true;if(!resizePoint)stablePoint=readingPoint();const now=Date.now();if(now-lastProgress>200){lastProgress=now;send('progress',{offset:readingPoint().offset});}clearTimeout(progressTimer);progressTimer=setTimeout(()=>send('progress',{offset:readingPoint().offset}),250);}, {passive:true});
addEventListener('pagehide',()=>send('progress',{offset:readingPoint().offset}));
document.addEventListener('click',e=>{const a=e.target.closest('a');if(a&&root.contains(a)){e.preventDefault();send('link',{href:a.getAttribute('href')||''});}});
window.Reader.update(initial);let restoreTimer=setTimeout(()=>window.Reader.restore(initial.offset||0),80);send('ready',{textLength:text.length});
})();
