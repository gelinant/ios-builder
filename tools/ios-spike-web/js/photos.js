(function(){
  var ID="@@ID@@", CAP=80, EARLY=false, acc={}, tries=0, phase=0, cats=[], ci=0, sub=0, opened=false, pre={}, openedAt=0, rescued=0;
  // The gallery tabs worth tagging (skip All/Latest/Videos/Street View - All is the fallback
  // sweep). Menu names cover the app's 11 languages (tabs arrive localized).
  var CATRE=/^(menu|menú|menù|speisekarte|cardápio|menukaart|меню|meny|food|drink|vibe|by owner)/i;
  var MENURE=/^(menu|menú|menù|speisekarte|cardápio|menukaart|меню|meny)/i;
  function ok(u){ return !!u && u.indexOf('googleusercontent')>=0 && !/streetviewpixels/.test(u) && !/\/a[\/-]|ACg8oc|ALV-/.test(u); }
  function idOf(u){ return u.replace(/=[wshpc].*$/,''); }
  function urlOf(el){ var u=el.currentSrc||el.src||''; if(!u || u.indexOf('googleusercontent')<0){ var bg=el.style.backgroundImage||''; if(!bg){ try{ bg=getComputedStyle(el).backgroundImage||''; }catch(e){} } var m=bg.match(/url\(["']?([^"')]+)/); if(m) u=m[1]; } return u; }
  function collect(cat,skip){ [].slice.call(document.querySelectorAll('img,[role="img"],button,a,[style*="background"]')).forEach(function(el){ var u=urlOf(el); if(ok(u)){ var k=idOf(u); if(skip && skip[k]) return; if(!acc[k]) acc[k]={c:cat,u:u}; } }); }
  function snap(){ var s={}; [].slice.call(document.querySelectorAll('img,[role="img"],button,a,[style*="background"]')).forEach(function(el){ var u=urlOf(el); if(ok(u)) s[idOf(u)]=1; }); return s; }
  // Tabs come from role="tab" ONLY: the place overview also has a bare "Menu" ACTION LINK (an
  // <a> to the restaurant's own site) - clicking that would navigate the WebView off Maps and
  // kill the scrape. (The Kotlin side also blocks off-google navigations as a belt-and-braces.)
  function tabEls(){ return [].slice.call(document.querySelectorAll('[role="tab"]')); }
  function clickTab(name){ var ts=tabEls(); for(var i=0;i<ts.length;i++){ if((((ts[i].getAttribute('aria-label')||ts[i].textContent)||'').trim())===name){ try{ ts[i].click(); }catch(e){} return; } } }
  function tabSelected(name){ var ts=tabEls(); for(var i=0;i<ts.length;i++){ var t=(((ts[i].getAttribute('aria-label')||ts[i].textContent)||'').trim()); if(t===name) return ts[i].getAttribute('aria-selected')==='true'; } return false; }
  // One-shot: after the gallery opens, its own tiles carry "Photo 2 of 45"-style labels that
  // match /photos?/ - re-firing this would click INTO a photo lightbox and break the tab walk.
  function clickPhotos(){ if(opened) return; var bs=[].slice.call(document.querySelectorAll('button,a')); for(var i=0;i<bs.length;i++){ var l=((bs[i].getAttribute('aria-label')||'')+' '+(bs[i].textContent||'')).toLowerCase(); if((/(^|\s)photos?(\s|$)|see (all )?photos|all photos/.test(l)) && !/street ?view|review|profile|video/.test(l)){ try{ bs[i].click(); }catch(e){} opened=true; openedAt=tries; return; } } }
  function scroll(){ try{ [].slice.call(document.querySelectorAll('div')).forEach(function(d){ if(d.scrollHeight>d.clientHeight+300 && d.clientHeight>200) d.scrollTop=d.scrollHeight; }); }catch(e){} }
  // A real category tab is a clean name ("Menu", "Food & drink", "By owner") - EXCLUDE photo
  // captions that also start with a category word ("Menu · Photo 1 of 12") via the letters-only test.
  function tabsNow(){ var out=[]; tabEls().forEach(function(e){ var t=((e.getAttribute('aria-label')||e.textContent)||'').trim(); if(t && t.length<20 && CATRE.test(t) && /^[a-z &]+$/i.test(t) && out.indexOf(t)<0) out.push(t); }); return out; }
  function lines(){ var out=[]; for(var k in acc) out.push((acc[k].c||'')+'\t'+acc[k].u); return out.slice(0,CAP).join("\n"); }
  function finish(){ try{ VelaBridge.onInfo(ID, JSON.stringify({tabs:cats.length, opened:opened?1:0, openedAt:openedAt, rescued:rescued, ticks:tries})); }catch(e){} try{ VelaBridge.onResult(ID, lines()); }catch(e){ try{ VelaBridge.onResult(ID,''); }catch(e2){} } }
  var histSent=0;
  // The overview's rating-distribution table (each row: "5 stars, 612 reviews") - the
  // same rows the reviews panel carves; grabbed once in passing, costs nothing extra.
  function hist(){ if(histSent) return; var rows=[].slice.call(document.querySelectorAll('tr[aria-label]')).filter(function(r){ return /^\s*\d\s+stars?,/i.test(r.getAttribute('aria-label')||''); }); if(rows.length<5) return; var c={}; rows.forEach(function(r){ var m=(r.getAttribute('aria-label')||'').match(/^\s*(\d)\s+stars?,\s*([\d,]+)/i); if(m) c[m[1]]=parseInt(m[2].replace(/,/g,''),10); }); if(c['5']!==undefined && c['1']!==undefined){ histSent=1; try{ VelaBridge.onHistogram(ID, JSON.stringify([c['5']||0,c['4']||0,c['3']||0,c['2']||0,c['1']||0])); }catch(e){} } }
  var sentN=0;
  // Stream growth: the sheet fills in as photos are found instead of waiting ~20s for
  // the full tab walk (first partial = the OVERVIEW's hero photos, ~1 tick after load).
  function partial(){ var n=0; for(var k in acc) n++; if(n>sentN){ sentN=n; try{ VelaBridge.onPartial(ID, lines()); }catch(e){} } }
  // One-shot probe (menu-date hunt, user 2026-07-11): does the place page's own
  // APP_INITIALIZATION_STATE carry per-photo relative dates ("3 months ago")? If a
  // clean url-near-date shape shows in the snippet, extraction replaces the dead
  // hspqX RPC as the date source at zero extra requests. Logcat: VelaPhotoWalk.
  // Mine the page's APP_INITIALIZATION_STATE for per-photo posted dates - the
  // photo entries carry the url at [6][0] (the dead RPC's shape) with a relative
  // "N ago" string or an absolute [Y,M,D] array nearby. One shot per page; zero
  // extra requests (menu-date hunt, user 2026-07-11).
  // Mine the page's APP_INITIALIZATION_STATE for photo urls with a nearby date -
  // relative "N ago" string or absolute [Y,M,D] array. The url match is LOOSE (any
  // array carrying a googleusercontent string directly or as a member's [0]): the
  // first cut required the dead RPC's [6][0] shape and found nothing (2026-07-11).
  // Review photos pairing with their review's date is CORRECT data. One shot/page.
  function aisDates(){
    if(window.__velaAisDates) return; window.__velaAisDates=1;
    try{
      var out=[], urls=0, seen={};
      function isArr(x){ return Object.prototype.toString.call(x)==='[object Array]'; }
      function hunt(m,dd){
        if(!m || dd>4) return null;
        if(isArr(m)){
          if(m.length>=3 && m.length<=4 && typeof m[0]==='number' && m[0]>2004 && m[0]<2100 &&
             typeof m[1]==='number' && m[1]>=1 && m[1]<=12 && typeof m[2]==='number' && m[2]>=1 && m[2]<=31){
            return m[0]+'-'+m[1]+'-'+m[2];
          }
          for(var i=0;i<m.length;i++){ var r=hunt(m[i],dd+1); if(r) return r; }
        } else if(typeof m==='string' && / ago$/.test(m) && m.length<40){ return m; }
        return null;
      }
      function urlIn(n){
        for(var i=0;i<n.length;i++){
          var v=n[i];
          if(typeof v==='string' && v.indexOf('http')===0 && v.indexOf('googleusercontent.com')>=0) return v;
          if(isArr(v) && typeof v[0]==='string' && v[0].indexOf('http')===0 && v[0].indexOf('googleusercontent.com')>=0) return v[0];
        }
        return null;
      }
      function walk(n,d){
        if(!n || d>18 || out.length>=250) return;
        if(isArr(n)){
          var u=urlIn(n);
          if(u){
            var k=u.replace(/=[^=]*$/,'');
            if(!seen[k]){ seen[k]=1; urls++; var dt=hunt(n,0); if(dt) out.push([u,dt]); }
          }
          for(var i=0;i<n.length;i++) walk(n[i],d+1);
        }
      }
      // AIS's payloads are EMBEDDED JSON STRINGS (the ")]}'"-guarded blobs the
      // transit fetcher reads) - the live tree has no photo urls (probed: 0).
      // Parse every big string leaf that mentions photos and walk the PARSED tree.
      var blobs=0, bigStr=0, withImg=0, withAgo=0;
      function harvest(n,d){
        if(!n || d>40) return;
        if(isArr(n)){ for(var i=0;i<n.length;i++) harvest(n[i],d+1); }
        else if(typeof n==='string' && n.length>2000){
          bigStr++;
          if(n.indexOf(' ago')>=0) withAgo++;
          if(n.indexOf('googleusercontent')>=0 || n.indexOf('lh3.')>=0){
            withImg++;
            var t=n; if(t.indexOf(")]}'")===0) t=t.substring(4);
            var k=t.indexOf('['); if(k>=0 && k<8){
              try{ var parsed=JSON.parse(t.substring(k)); blobs++; walk(parsed,0); }catch(e3){}
            }
          }
        }
      }
      harvest(window.APP_INITIALIZATION_STATE,0);
      try{ VelaBridge.onInfo(ID, JSON.stringify({bigStr:bigStr, withImg:withImg, withAgo:withAgo, blobs:blobs, aisUrls:urls, aisDated:out.length, sample:((out[0]||[])[0]||'').slice(0,60)})); }catch(e2){}
      if(out.length) VelaBridge.onDates(ID, JSON.stringify(out));
    }catch(e){}
  }
  function tick(){
    tries++;
    aisDates();
    hist();
    if(phase===0){
      collect(''); clickPhotos(); scroll();
      // Wait until the gallery's category tabs actually exist. The old 8-tick (4 s)
      // cap counted from SCRIPT START - page load + finding the Photos button + the
      // gallery render routinely ate it all on a cold WebView, so real menu tabs got
      // skipped and the place walked tab-less (the inconsistent-Menu report, user
      // 2026-07-11). Now: give the OPENED gallery 6 more ticks to grow tabs, and only
      // hard-stop at 20 ticks when the gallery never opened at all.
      cats=tabsNow();
      if(cats.length>0 || (opened && tries>=openedAt+6) || tries>=20){ ci=0; sub=0; phase=1; }
    }
    else if(phase===1){
      if(ci>=cats.length){ phase=2; sub=0; }
      // Per tab: SNAPSHOT what's already on screen, click, then collect ONLY images that
      // appear after the switch (and only once aria-selected confirms it) - the whole-document
      // sweep was tagging page chrome + the previous grid's leftover tiles with the category
      // (the "Menu tab full of non-menu pics" report, 2026-07-10). Menu tabs get a LONGER
      // scroll dwell so a long menu is walked to the end, not sampled.
      else { if(sub===0){ pre=snap(); clickTab(cats[ci]); } scroll(); if(sub>=2 && tabSelected(cats[ci])) collect(cats[ci], pre); sub++; var dwell=MENURE.test(cats[ci])?14:6; if(sub>=dwell){ ci++; sub=0; } }
    }
    else {
      // Late-tab rescue: tabs that appeared AFTER phase 0 gave up would silently be
      // swept uncategorized - jump back and walk them once.
      if(sub===0 && cats.length===0 && !rescued){
        var late=tabsNow();
        if(late.length>0){ rescued=1; cats=late; ci=0; sub=0; phase=1; partial(); setTimeout(tick, 500); return; }
      }
      // The All sweep: click, give the grid one no-collect settle tick, then sweep uncategorized.
      if(sub===0) clickTab('All');
      scroll(); if(sub>=1) collect('');
      sub++; if(sub>=5){ finish(); return; }
    }
    if(tries>84){ collect(''); finish(); return; }
    partial();
    // First batch: done as soon as the cap is reached (a place tap needs a handful, not
    // every tab), so the page stops making requests.
    if(EARLY){ var have=0; for(var k0 in acc) have++; if(have>=CAP){ finish(); return; } }
    setTimeout(tick, 500);
  }
  tick();
})();