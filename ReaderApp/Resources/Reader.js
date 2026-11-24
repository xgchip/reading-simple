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
// Keep an immutable anchor while the native color picker takes keyboard focus.
let editingMarkID=null, selectionPoint=null, markStyle='highlight', markColor='#E8C55A';
const presetColors=[['金黄','#E8C55A'],['草绿','#72B88A'],['天空蓝','#65A9E8'],['浅紫','#B593DA'],['玫瑰粉','#E990A5'],['橙色','#ED995A']];
function validColor(value){return /^#[0-9a-f]{6}$/i.test(value||'')?value:'#E8C55A';}
function dismissToolbar(){toolbar.hidden=true;editingMarkID=null;selected=null;selectionPoint=null;}
function placeToolbar(point){
 const box=toolbar.getBoundingClientRect(),gap=12,pad=8;
 const x=Math.max(pad,Math.min(innerWidth-box.width-pad,point.x-box.width/2));
 const below=point.y+gap;const y=below+box.height<=innerHeight-pad?below:point.y-box.height-gap;
 toolbar.style.left=x+'px';toolbar.style.top=Math.max(pad,Math.min(innerHeight-box.height-pad,y))+'px';
}
function applyAppearance(){
 toolbar.querySelectorAll('[data-style]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.style===markStyle)));
 toolbar.querySelectorAll('[data-color]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.color.toLowerCase()===markColor.toLowerCase())));
 const input=toolbar.querySelector('input[type=color]');input.value=markColor;
 toolbar.style.setProperty('--selected-mark-color',markColor);
 if(editingMarkID)send('appearance',{id:editingMarkID,style:markStyle,color:markColor});
}
function showToolbar(point,mark=null){
 editingMarkID=mark?.id||null;
 if(mark){markStyle=mark.style==='wave'?'wave':'highlight';markColor=validColor(mark.color);}
 toolbar.replaceChildren();toolbar.setAttribute('role','toolbar');toolbar.setAttribute('aria-label',mark?'编辑划线':'选中文字操作');
 const actions=document.createElement('div');actions.className='reader-selection-actions';
 for(const [value,label] of [['highlight','荧光笔'],['wave','波浪线']]){const b=button(label,()=>{markStyle=value;applyAppearance();});b.dataset.style=value;actions.append(b);}
 actions.append(button(mark?'写想法 / 编辑':'写想法',()=>{if(editingMarkID)send('edit',{id:editingMarkID});else if(selected)send('selection',{anchor:selected,action:'note',style:markStyle,color:markColor});dismissToolbar();getSelection()?.removeAllRanges();}));
 if(mark?.note)actions.append(button('查看想法',()=>{dismissToolbar();showPopup(mark);}));
 const save=button(mark?'完成':'划线',()=>{if(!editingMarkID&&selected)send('selection',{anchor:selected,action:'highlight',style:markStyle,color:markColor});dismissToolbar();getSelection()?.removeAllRanges();});save.className='reader-selection-save';actions.append(save);
 const close=button('×',dismissToolbar);close.setAttribute('aria-label','关闭工具栏');actions.append(close);toolbar.append(actions);
 const colors=document.createElement('div');colors.className='reader-selection-colors';colors.setAttribute('role','group');colors.setAttribute('aria-label','划线颜色');
 for(const [label,color] of presetColors){const b=button('',()=>{markColor=color;applyAppearance();});b.className='reader-color-swatch';b.dataset.color=color;b.style.background=color;b.title=label;b.setAttribute('aria-label',label);colors.append(b);}
 const label=document.createElement('label');label.className='reader-custom-color';label.textContent='自定义';const input=document.createElement('input');input.type='color';input.value=markColor;input.setAttribute('aria-label','自定义划线颜色');input.addEventListener('input',()=>{markColor=input.value;applyAppearance();});label.append(input);colors.append(label);toolbar.append(colors);
 // Initial population must not write an unchanged existing annotation.
 const savedID=editingMarkID;editingMarkID=null;applyAppearance();editingMarkID=savedID;
 toolbar.hidden=false;selectionPoint=point;placeToolbar(point);
}
function selection(point=null){
 selected=capture();if(!selected){dismissToolbar();return;}
 const range=rangeAt(selected.start,selected.end),rects=[...range.getClientRects()];
 const existing=marks.find(m=>m.start===selected.start&&m.end===selected.end&&m.quote===selected.quote);
 const sel=getSelection(),focus=sel?.focusNode;let rect=rects.at(-1)||range.getBoundingClientRect();
 if(focus){const caret=document.createRange();try{caret.setStart(focus,sel.focusOffset);caret.collapse(true);const r=caret.getBoundingClientRect();if(r.height)rect=r;}catch{}}
 showToolbar(point||{x:rect.right,y:rect.bottom},existing);
}
// Prevent toolbar buttons from collapsing browser selection. Color input remains focusable.
toolbar.addEventListener('mousedown',e=>{if(e.target.closest('button'))e.preventDefault();});
document.addEventListener('mousedown',e=>{if(!toolbar.contains(e.target)&&!e.target.closest('.reader-marker'))dismissToolbar();});
document.addEventListener('mouseup',e=>{if(toolbar.contains(e.target)||e.target.closest('.reader-marker')||popup.contains(e.target))return;const point={x:e.clientX,y:e.clientY};setTimeout(()=>selection(point),0);});
document.addEventListener('keyup',e=>{if(e.key==='Escape'){popup.hidden=true;dismissToolbar();return;}if(toolbar.contains(e.target)||popup.contains(e.target))return;if(e.key.startsWith('Arrow')&&e.shiftKey)selection();});
document.addEventListener('visibilitychange',()=>{if(document.hidden)dismissToolbar();});
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
  for(const rect of rects){const box=document.createElement('div');box.className='reader-highlight'+(m.style==='wave'?' reader-wave':'')+(activeID===m.id?' active':'');box.style.setProperty('--mark-color',validColor(m.color));Object.assign(box.style,{left:(rect.left+scrollX)+'px',top:(rect.top+scrollY)+'px',width:rect.width+'px',height:rect.height+'px'});highlights.append(box);}
  const rect=rects[0];if(!rect)continue;
  const marker=button(m.note?'●':'＋',()=>{const box=marker.getBoundingClientRect();selected=null;popup.hidden=true;showToolbar({x:box.left,y:box.bottom},m);});marker.className='reader-marker';marker.dataset.markId=m.id;marker.setAttribute('aria-label','编辑划线风格、颜色或想法');let markerY=rect.top+scrollY;while(markerRows.some(y=>Math.abs(y-markerY)<25))markerY+=25;markerRows.push(markerY);Object.assign(marker.style,{left:(root.getBoundingClientRect().right+scrollX+7)+'px',top:markerY+'px'});highlights.append(marker);
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
let resizeTimer;addEventListener('resize',()=>{dismissToolbar();if(!resizePoint)resizePoint={...stablePoint};clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{const p=resizePoint;resizePoint=null;if(p)jumpOffset(p.offset,p.delta);stablePoint=readingPoint();schedule();},80);});
new ResizeObserver(schedule).observe(root);root.querySelectorAll('img').forEach(img=>img.addEventListener('load',schedule));document.fonts?.ready.then(schedule);
let progressTimer;addEventListener('scroll',()=>{dismissToolbar();if(!resizePoint)stablePoint=readingPoint();const now=Date.now();if(now-lastProgress>200){lastProgress=now;send('progress',{offset:readingPoint().offset});}clearTimeout(progressTimer);progressTimer=setTimeout(()=>send('progress',{offset:readingPoint().offset}),250);}, {passive:true});
addEventListener('pagehide',()=>send('progress',{offset:readingPoint().offset}));
document.addEventListener('click',e=>{const a=e.target.closest('a');if(a&&root.contains(a)){e.preventDefault();send('link',{href:a.getAttribute('href')||''});}});
window.Reader.update(initial);let restoreTimer=setTimeout(()=>window.Reader.restore(initial.offset||0),80);send('ready',{textLength:text.length});
})();
