// Hint overlay script (structure ported from src/scripts/hints.js for the
// WKWebView port). Built into one self-contained IIFE; native drives it via
// window.__vimb_hint_* functions after injection.
//
// The generator (scripts/mkjsheader.sh) embeds this verbatim; the two
// __VIMB_*__ tokens are substituted at runtime by KeyboardWebView.
(function(){
'use strict';
function post(m){if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.vimb){window.webkit.messageHandlers.vimb.postMessage(m);}}
if(window.__vimb_hint_active){window.__vimb_hint_cleanup(true);return;}
var mode='__VIMB_MODE__';var keepOpen=__VIMB_KEEPOPEN__;
var alpha=['a','b','c','d','f','g','h','j','k','l','m','n','p','q','r','s','t','u','v','w','x','y','z'];
function lab(i){var s='',r=i;do{s=alpha[r%alpha.length]+s;r=Math.floor(r/alpha.length)-1;}while(r>=0);return s;}
// Per-mode behaviour (faithful to hints.js xpath/action/handleForm maps).
var xpath,dataMode=false,yankText=false,removeMode=false,openMode=false,handlesForm=false;
if('otY'.indexOf(mode)>=0){xpath='linkform';openMode=(mode==='o'||mode==='t');yankText=(mode==='Y');}
else if(mode==='k'){xpath='div';removeMode=true;}
else if(mode==='e'){xpath='edit';dataMode=true;}
else if('iI'.indexOf(mode)>=0){xpath='img';dataMode=true;}
else{xpath='linkimg';dataMode=true;}
if('eot'.indexOf(mode)>=0)handlesForm=true;
// Map the xpath family to a CSS selector that approximates it.
var sel='a[href],button,input:not([type=hidden]),select,summary,[onclick],[tabindex],[role=link],[role=button],[class=lk]';
if(xpath==='linkimg')sel='a[href],iframe[src],img[src]:not(a img)';
else if(xpath==='img')sel='img[src]';
else if(xpath==='div')sel='div';
else if(xpath==='edit')sel='input:not([type]),input[type=text],textarea';
function isVisible(e){if(!e)return false;var r=e.getBoundingClientRect();if(!r)return false;
if(r.bottom<0||r.right<0||r.top>window.innerHeight||r.left>window.innerWidth)return false;
var s=window.getComputedStyle(e);return !s||(s.display!=='none'&&s.visibility!=='hidden');}
var seen={};
var els=Array.prototype.slice.call(document.querySelectorAll(sel)).filter(function(e){if(seen[e]||!isVisible(e))return false;seen[e]=1;return true;});
if(els.length===0){post({t:'hintnone'});return;}
window.__vimb_hint_active=1;window.__vimb_hint_els=els;window.__vimb_hint_match='';window.__vimb_hint_activeIdx=null;window.__vimb_hint_vis=[];
window.__vimb_hint_mode=mode;window.__vimb_hint_keepopen=keepOpen;
var css=document.createElement('style');css.id='vimb-hint-css';
css.textContent='.vimb-hint-el{position:absolute;z-index:2147483647;padding:1px 4px;background:rgba(255,210,0,.95);color:#000;border-radius:2px;font:bold 12px monospace;pointer-events:none;box-shadow:0 1px 2px rgba(0,0,0,.3)}';
(document.head||document.documentElement).appendChild(css);
window.__vimb_hint_labels=els.map(function(el,i){
var r=el.getBoundingClientRect();var d=document.createElement('div');d.className='vimb-hint-el';d.textContent=lab(i);
d.setAttribute('data-i',String(i));d.style.left=(r.left-window.pageXOffset+4)+'px';d.style.top=(r.top-window.pageYOffset+4)+'px';
(document.body||document.documentElement).appendChild(d);return d;});
window.__vimb_hint_cleanup=function(){(window.__vimb_hint_labels||[]).forEach(function(d){try{d.remove();}catch(e){}});
var s=document.getElementById('vimb-hint-css');if(s)s.remove();
window.__vimb_hint_labels=[];window.__vimb_hint_els=[];window.__vimb_hint_match='';window.__vimb_hint_vis=[];window.__vimb_hint_activeIdx=null;window.__vimb_hint_active=0;};
function L(d){var i=+d.getAttribute('data-i'),s='',r=i;do{s=alpha[r%alpha.length]+s;r=Math.floor(r/alpha.length)-1;}while(r>=0);return s;}
function getSrc(e){if(!e)return '';if(e.href)return e.href;if(e.src)return e.src;if(e.getAttribute){var a=e.getAttribute('href');if(a)return a;a=e.getAttribute('src');if(a)return a;}return '';}
// fire: performs the per-mode action and reports it to native.
function fire(idx){var e=window.__vimb_hint_els[idx];if(!e)return;var out=null;
function data(){return {action:'DATA',value:getSrc(e)};}
function done(){return {action:'DONE',value:getSrc(e)};}
if(handlesForm){var tag=(e.nodeName||'').toLowerCase(),type=(e.type||'').toLowerCase();
if(tag==='input'||tag==='textarea'||tag==='select'){
if(type==='radio'||type==='checkbox'){try{e.focus();e.click();}catch(_){}}
else if(type==='submit'||type==='reset'||type==='button'||type==='image'){try{e.click();}catch(_){}}
else{try{e.focus();}catch(_){}out={action:'INSERT',value:getSrc(e)};}}
else if(tag==='iframe'||tag==='frame'){try{e.focus();}catch(_){}out=done();}
else if(removeMode){e.remove();out=done();}
else if(yankText){out=data();}
else if(openMode){if(mode==='t'){out=data();}else{try{e.click();}catch(_){}out=done();}}
else if(dataMode){out=data();}}
else{
if(removeMode){e.remove();out=done();}
else if(yankText){out=data();}
else if(openMode){if(mode==='t'){out=data();}else{try{e.click();}catch(_){}out=done();}}
else if(dataMode){out=data();}}
if(yankText&&out){var tv=(e.textContent||'').replace(/\s+/g,' ').replace(/^\s+/,'').replace(/\s+$/,'');out.value=tv;}
if(out){post({t:'hintdata',mode:mode,value:out.value==null?'':String(out.value),action:out.action});}
if(keepOpen){window.__vimb_hint_match='';show();}else{window.__vimb_hint_cleanup();}
}
// show: recompute visible labels from the filter text, manage focus.
function show(){var m=window.__vimb_hint_match;var vis=[];
window.__vimb_hint_labels.forEach(function(d){var i=+d.getAttribute('data-i');var on=(m.length===0||L(d).indexOf(m)===0);d.style.display=on?'':'none';if(on)vis.push(i);});
window.__vimb_hint_vis=vis;
if(window.__vimb_hint_activeIdx==null||vis.indexOf(window.__vimb_hint_activeIdx)<0){window.__vimb_hint_activeIdx=vis.length?vis[0]:null;}
if(m.length&&vis.length===1){fire(vis[0]);}
else if(m.length&&vis.length===0){post({t:'hintpending',n:0});window.__vimb_hint_cleanup();}
else{post({t:vis.length?'hintready':'hintnone',n:vis.length});}
}
window.__vimb_hint_type=function(ch){window.__vimb_hint_match+=String(ch);show();};
window.__vimb_hint_backspace=function(){if(window.__vimb_hint_match.length){window.__vimb_hint_match=window.__vimb_hint_match.slice(0,-1);show();}};
window.__vimb_hint_focus=function(back){var vis=window.__vimb_hint_vis;if(!vis||!vis.length)return;var idx=vis.indexOf(window.__vimb_hint_activeIdx);if(idx<0)idx=0;
if(back){idx--;if(idx<0)idx=vis.length-1;}else{idx++;if(idx>=vis.length)idx=0;}window.__vimb_hint_activeIdx=vis[idx];};
window.__vimb_hint_fire=function(){var i=window.__vimb_hint_activeIdx;if(i!=null&&window.__vimb_hint_els[i])fire(i);};
window.__vimb_hint_clear=function(){post({t:'hintnone'});window.__vimb_hint_cleanup();};
show();
})();
