// Core page helper injected as a WKUserScript at document start.
// Parity role: src/scripts/scroll.js + focus_tracking.js (the WKWebView port
// merges both into one user script bridged over window.webkit.messageHandlers).
//
// Exposes window.__vimb with scroll primitives and posts focus/scroll events
// back to native (KeyboardWebView's script-message handler).
window.__vimb = (function(){
  function post(msg){
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimb){
      window.webkit.messageHandlers.vimb.postMessage(msg);
    }
  }
  function scrollElement(el){
    var n = el, depth = 0;
    for (;n && depth < 40; n=n.parentElement, depth++){
      if (n.scrollHeight > n.clientHeight + 1 || n.scrollWidth > n.clientWidth + 1){ return n; }
    }
    return null;
  }
  function isEditable(t){
    var n=t, d=0;
    if(!n||!n.tagName)return false;
    var tag=(n.tagName||'').toLowerCase();
    if(tag==='textarea'||tag==='input'&&['text','search','url','password','email','tel','number'].indexOf((n.type||'').toLowerCase())>-1)return true;
    if(tag==='input'||tag==='select')return false;
    for(;n&&d<4;n=n.parentElement,d++){
      if(n.isContentEditable||(n.getAttribute&&n.getAttribute('contenteditable')==='true'))return true;
    }
    return false;
  }
  window.__vb_editable=function(){ return isEditable(document.activeElement); };
  var lastFocused;
  document.addEventListener('focusin',function(e){
    var el=e.target;
    if(isEditable(el)){ window.__vb_editable_active=1; post({t:'focusactive'}); }
    else { window.__vb_editable_active=0; }
    lastFocused=el;
  },true);
  document.addEventListener('focusout',function(e){
    if(isEditable(e.target)){ window.__vb_editable_active=0; }
  },true);
  return {
    scrollToTop:function(){ var s = scrollElement(document.scrollingElement || document.documentElement);
        var e = document.scrollingElement || document.documentElement;
        e.scrollTop = 0; window.scrollTo(0,0); post({t:'scrollTop'}); },
    scrollToBottom:function(){ var e = document.scrollingElement || document.documentElement;
        e.scrollTop = e.scrollHeight; window.scrollTo(0, e.scrollHeight); post({t:'scrollBottom'}); },
    scrollBy:function(dx,dy){
        var s = scrollElement(document.activeElement);
        var e = s || (document.scrollingElement || document.documentElement);
        var nx = (e.scrollLeft||0)+dx, ny = (e.scrollTop||0)+dy;
        if (s){ try{ s.scrollBy(dx,dy); }catch(_){} } else { window.scrollBy(dx,dy); }
        post({t:'scrolled', left:nx, top:ny}); },
    pageTop:function(){ try{ window.webkit.messageHandlers.vimb.postMessage({t:'ping'}); }catch(_){} }
  };
})();
