import UIKit
import VelaCore

/// The categorized gallery walk of Android's `WebPhotoFetcher`. The RPC remains the cheap source
/// for pages and dates; this page runs only for categories or after an RPC paging failure.
/// Main thread only.
final class PhotosWebFetcher: HiddenWebView {
    static let shared = PhotosWebFetcher(tag: "photos", size: CGSize(width: 1200, height: 3200))

    private static let settle: TimeInterval = 1.2
    private static let maxLoad: TimeInterval = 7

    private final class Active {
        let id: String
        let request: WebPhotosRequest
        let sink: WebPhotosSink
        let done: () -> Void
        var injected = false
        var injectedByCap = false
        var heard = false
        var lastPartial: String?

        init(id: String, request: WebPhotosRequest, sink: WebPhotosSink, done: @escaping () -> Void) {
            self.id = id
            self.request = request
            self.sink = sink
            self.done = done
        }
    }

    private var active: Active?

    func photos(request: WebPhotosRequest, sink: WebPhotosSink) -> any VelaCore.Cancellable {
        let handle = WebFetchHandle()
        session { [weak self] done in
            guard let self, !handle.cancelled else {
                sink.onResult(payload: nil)
                done()
                return
            }
            let id = self.nextId()
            let active = Active(id: id, request: request, sink: sink, done: done)
            self.active = active
            handle.onCancel = { [weak self] in self?.giveUp(id) }
            self.evaluate("try{document.documentElement.innerHTML=''}catch(e){}")
            self.load(request.url, id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxLoad) { [weak self] in
                self?.inject(id, byCap: true)
            }
        }
        return handle
    }

    override func allowNavigation(_ url: URL) -> Bool {
        let host = url.host ?? ""
        return host == "google.com" || host.hasSuffix(".google.com")
    }

    override func pageFinished(url: URL?, requestId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
            self?.inject(requestId, byCap: false)
        }
    }

    override func bridgeCall(method: String, requestId: String, argument: String) {
        guard let active, active.id == requestId else { return }
        active.heard = true
        switch method {
        case "onResult": finish(requestId, argument)
        case "onPartial":
            active.lastPartial = argument
            active.sink.onPartial(payload: argument)
        case "onDates": active.sink.onDates(json: argument)
        case "onHistogram": active.sink.onHistogram(json: argument)
        case "onInfo": webLog.debug("photos: gallery probe received")
        default: break
        }
    }

    override func pageDied(requestId: String) {
        finish(requestId, active?.lastPartial)
    }

    private func inject(_ id: String, byCap: Bool) {
        guard let active, active.id == id else { return }
        if active.injected {
            guard !byCap, active.injectedByCap, !active.heard else { return }
            webLog.debug("photos: injecting again after the page finished")
        }
        active.injected = true
        active.injectedByCap = byCap
        evaluate(PhotoScripts.walk(id: id, cap: Int(active.request.cap)))
    }

    private func giveUp(_ id: String) {
        guard active?.id == id else { return }
        stop()
        finish(id, nil)
    }

    private func finish(_ id: String, _ payload: String?) {
        guard let active, active.id == id else { return }
        self.active = nil
        webLog.debug("photos: gallery answered")
        // Same rule as the reviews page: once answered, the hidden Google document is dead weight
        // in the window and in the accessibility tree, so it must not wait for the idle timer.
        reapNow()
        active.sink.onResult(payload: payload)
        active.done()
    }
}

/// The DOM scraper, ported from Android because its source has not moved to core-common. It visits
/// Menu, Food and drink, Vibe, and By owner, then sweeps All. Partial results stream as tabs grow.
private enum PhotoScripts {
    static func walk(id: String, cap: Int) -> String {
        let requestId = quoted(id)
        return #"""
        (function(){
          var ID=\#(requestId), CAP=\#(cap), EARLY=false, acc={}, tries=0, phase=0, cats=[], ci=0, sub=0, opened=false, pre={}, openedAt=0, rescued=0;
          var CATRE=/^(menu|menú|menù|speisekarte|cardápio|menukaart|меню|meny|food|drink|vibe|by owner)/i;
          var MENURE=/^(menu|menú|menù|speisekarte|cardápio|menukaart|меню|meny)/i;
          function ok(u){ return !!u && u.indexOf('googleusercontent')>=0 && !/streetviewpixels/.test(u) && !/\/a[\/-]|ACg8oc|ALV-/.test(u); }
          function idOf(u){ return u.replace(/=[wshpc].*$/,''); }
          function urlOf(el){ var u=el.currentSrc||el.src||''; if(!u || u.indexOf('googleusercontent')<0){ var bg=el.style.backgroundImage||''; if(!bg){ try{ bg=getComputedStyle(el).backgroundImage||''; }catch(e){} } var m=bg.match(/url\(["']?([^"')]+)/); if(m) u=m[1]; } return u; }
          function collect(cat,skip){ [].slice.call(document.querySelectorAll('img,[role="img"],button,a,[style*="background"]')).forEach(function(el){ var u=urlOf(el); if(ok(u)){ var k=idOf(u); if(skip && skip[k]) return; if(!acc[k]) acc[k]={c:cat,u:u}; } }); }
          function snap(){ var s={}; [].slice.call(document.querySelectorAll('img,[role="img"],button,a,[style*="background"]')).forEach(function(el){ var u=urlOf(el); if(ok(u)) s[idOf(u)]=1; }); return s; }
          function tabEls(){ return [].slice.call(document.querySelectorAll('[role="tab"]')); }
          function clickTab(name){ var ts=tabEls(); for(var i=0;i<ts.length;i++){ if((((ts[i].getAttribute('aria-label')||ts[i].textContent)||'').trim())===name){ try{ ts[i].click(); }catch(e){} return; } } }
          function tabSelected(name){ var ts=tabEls(); for(var i=0;i<ts.length;i++){ var t=(((ts[i].getAttribute('aria-label')||ts[i].textContent)||'').trim()); if(t===name) return ts[i].getAttribute('aria-selected')==='true'; } return false; }
          function clickPhotos(){ if(opened) return; var bs=[].slice.call(document.querySelectorAll('button,a')); for(var i=0;i<bs.length;i++){ var l=((bs[i].getAttribute('aria-label')||'')+' '+(bs[i].textContent||'')).toLowerCase(); if((/(^|\s)photos?(\s|$)|see (all )?photos|all photos/.test(l)) && !/street ?view|review|profile|video/.test(l)){ try{ bs[i].click(); }catch(e){} opened=true; openedAt=tries; return; } } }
          function scroll(){ try{ [].slice.call(document.querySelectorAll('div')).forEach(function(d){ if(d.scrollHeight>d.clientHeight+300 && d.clientHeight>200) d.scrollTop=d.scrollHeight; }); }catch(e){} }
          function tabsNow(){ var out=[]; tabEls().forEach(function(e){ var t=((e.getAttribute('aria-label')||e.textContent)||'').trim(); if(t && t.length<20 && CATRE.test(t) && /^[a-z &]+$/i.test(t) && out.indexOf(t)<0) out.push(t); }); return out; }
          function lines(){ var out=[]; for(var k in acc) out.push((acc[k].c||'')+'\t'+acc[k].u); return out.slice(0,CAP).join("\n"); }
          function finish(){ try{ VelaBridge.onInfo(ID, JSON.stringify({tabs:cats.length,opened:opened?1:0,openedAt:openedAt,rescued:rescued,ticks:tries})); }catch(e){} try{ VelaBridge.onResult(ID, lines()); }catch(e){ try{ VelaBridge.onResult(ID,''); }catch(e2){} } }
          var histSent=0;
          function hist(){ if(histSent) return; var rows=[].slice.call(document.querySelectorAll('tr[aria-label]')).filter(function(r){ return /^\s*\d\s+stars?,/i.test(r.getAttribute('aria-label')||''); }); if(rows.length<5) return; var c={}; rows.forEach(function(r){ var m=(r.getAttribute('aria-label')||'').match(/^\s*(\d)\s+stars?,\s*([\d,]+)/i); if(m) c[m[1]]=parseInt(m[2].replace(/,/g,''),10); }); if(c['5']!==undefined && c['1']!==undefined){ histSent=1; try{ VelaBridge.onHistogram(ID, JSON.stringify([c['5']||0,c['4']||0,c['3']||0,c['2']||0,c['1']||0])); }catch(e){} } }
          var sentN=0;
          function partial(){ var n=0; for(var k in acc) n++; if(n>sentN){ sentN=n; try{ VelaBridge.onPartial(ID, lines()); }catch(e){} } }
          function aisDates(){
            if(window.__velaAisDates) return; window.__velaAisDates=1;
            try{
              var out=[], seen={};
              function isArr(x){ return Object.prototype.toString.call(x)==='[object Array]'; }
              function hunt(m,dd){
                if(!m || dd>4) return null;
                if(isArr(m)){
                  if(m.length>=3 && m.length<=4 && typeof m[0]==='number' && m[0]>2004 && m[0]<2100 && typeof m[1]==='number' && m[1]>=1 && m[1]<=12 && typeof m[2]==='number' && m[2]>=1 && m[2]<=31){ return m[0]+'-'+m[1]+'-'+m[2]; }
                  for(var i=0;i<m.length;i++){ var r=hunt(m[i],dd+1); if(r) return r; }
                } else if(typeof m==='string' && / ago$/.test(m) && m.length<40){ return m; }
                return null;
              }
              function urlIn(n){ for(var i=0;i<n.length;i++){ var v=n[i]; if(typeof v==='string' && v.indexOf('http')===0 && v.indexOf('googleusercontent.com')>=0) return v; if(isArr(v) && typeof v[0]==='string' && v[0].indexOf('http')===0 && v[0].indexOf('googleusercontent.com')>=0) return v[0]; } return null; }
              function walk(n,d){
                if(!n || d>18 || out.length>=250) return;
                if(isArr(n)){
                  var u=urlIn(n);
                  if(u){ var k=u.replace(/=[^=]*$/,''); if(!seen[k]){ seen[k]=1; var dt=hunt(n,0); if(dt) out.push([u,dt]); } }
                  for(var i=0;i<n.length;i++) walk(n[i],d+1);
                }
              }
              function harvest(n,d){
                if(!n || d>40) return;
                if(isArr(n)){ for(var i=0;i<n.length;i++) harvest(n[i],d+1); }
                else if(typeof n==='string' && n.length>2000 && (n.indexOf('googleusercontent')>=0 || n.indexOf('lh3.')>=0)){
                  var t=n; if(t.indexOf(")]}'")===0) t=t.substring(4);
                  var k=t.indexOf('['); if(k>=0 && k<8){ try{ walk(JSON.parse(t.substring(k)),0); }catch(e3){} }
                }
              }
              harvest(window.APP_INITIALIZATION_STATE,0);
              if(out.length) VelaBridge.onDates(ID, JSON.stringify(out));
            }catch(e){}
          }
          function tick(){
            tries++;
            aisDates(); hist();
            if(phase===0){
              collect(''); clickPhotos(); scroll(); cats=tabsNow();
              if(cats.length>0 || (opened && tries>=openedAt+6) || tries>=20){ ci=0; sub=0; phase=1; }
            } else if(phase===1){
              if(ci>=cats.length){ phase=2; sub=0; }
              else { if(sub===0){ pre=snap(); clickTab(cats[ci]); } scroll(); if(sub>=2 && tabSelected(cats[ci])) collect(cats[ci],pre); sub++; var dwell=MENURE.test(cats[ci])?14:6; if(sub>=dwell){ ci++; sub=0; } }
            } else {
              if(sub===0 && cats.length===0 && !rescued){ var late=tabsNow(); if(late.length>0){ rescued=1; cats=late; ci=0; sub=0; phase=1; partial(); setTimeout(tick,500); return; } }
              if(sub===0) clickTab('All'); scroll(); if(sub>=1) collect(''); sub++; if(sub>=5){ finish(); return; }
            }
            if(tries>84){ collect(''); finish(); return; }
            partial();
            if(EARLY){ var have=0; for(var k0 in acc) have++; if(have>=CAP){ finish(); return; } }
            setTimeout(tick,500);
          }
          tick();
        })();
        """#
    }

    private static func quoted(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}
