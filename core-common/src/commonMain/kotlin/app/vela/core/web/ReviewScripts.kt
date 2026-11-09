package app.vela.core.web

/**
 * The hidden reviews scrape's page script, shared by Android's `WebReviewsFetcher` and the iOS
 * `ReviewsWebFetcher` so both inject the same bytes. Moved from `app.vela.web` unchanged
 * (`ReviewScriptsTest` pins the output). The bridge is written `VelaBridge`; each app swaps in
 * its per-process random name before the script runs.
 */
object ReviewScripts {
    /**
     * `velaNoName(label)` for the two review scripts: Google's tab and button labels carry the PLACE
     * NAME ("Overview of Davis Food Co-op", 「X」總覽), and the review-word pattern holds the word in
     * every language, so a name containing one of them ("D-avis" matches the French "avis") made the
     * Overview tab read as the Reviews tab. The full review page then reported ready on the Overview
     * and its More reviews button reloaded back to it (issue #535). The name is cut out before any
     * label is tested: the page heading when there is one, else the longest run shared by two tab
     * labels (every labeled tab repeats the name).
     */
    const val STRIP_PLACE_NAME_JS = """
function velaPlaceName(){
  var h=document.querySelector('h1'); var n=h&&(h.textContent||'').trim();
  if(n&&n.length>=2) return n;
  var ls=[].slice.call(document.querySelectorAll('[role="tab"]')).map(function(t){ return ((t.getAttribute('aria-label')||t.textContent)||'').trim(); }).sort(function(a,b){ return b.length-a.length; });
  if(ls.length<2) return '';
  var a=ls[0], b=ls[1], best='';
  for(var i=0;i<a.length;i++){ for(var j=i+best.length+1;j<=a.length;j++){ var s=a.slice(i,j); if(b.indexOf(s)>=0){ best=s; } else break; } }
  best=best.trim();
  return best.length>=4 ? best : '';
}
function velaNoName(t){ t=t||''; var n=velaPlaceName(); return n ? t.split(n).join(' ') : t; }
"""

    // Compiled selector defaults (the calibration bundle's `reviewSelectors` overrides per key).
    const val DEFAULT_CARD_SEL = ".jJc9Ad"
    const val DEFAULT_ID_SEL = "[data-review-id]"
    const val DEFAULT_MORE_TOGGLE_SEL = "button.w8nwRe"
    const val DEFAULT_AUTHOR_SEL = ".d4r55,.Vpc5Fe,.TSUbDb"
    const val DEFAULT_TEXT_SEL = ".wiI7pd"
    const val DEFAULT_DATE_SEL = ".rsqaWe"

    /**
     * The self-polling scraper for request [id]: open the full reviews list, then scroll it a
     * window at a time, accumulating each review card into a keyed set, and bridge the JSON array
     * back once the list is exhausted or [cap] is hit. [reviewPattern] and [morePattern] are the
     * review-word regexes (calibration `reviewWords`, else `ReviewWords`); [selectors] overrides
     * the default selectors per key (calibration `reviewSelectors`).
     */
    fun reviews(
        id: String,
        cap: Int,
        reviewPattern: String,
        morePattern: String,
        selectors: Map<String, String> = emptyMap(),
        /** Add the `tr` flag to each card: 1 when it carries Google's own translation notice. */
        translations: Boolean = false,
    ): String {
        fun reviewPatternJs(): String = jsString(reviewPattern)
        fun morePatternJs(): String = jsString(morePattern)
        fun selectorsJs(): String {
            fun sel(k: String, def: String) = "\"$k\":" + jsString(selectors[k] ?: def)
            return "{" + listOf(
                sel("card", DEFAULT_CARD_SEL), sel("id", DEFAULT_ID_SEL), sel("moreToggle", DEFAULT_MORE_TOGGLE_SEL),
                sel("author", DEFAULT_AUTHOR_SEL), sel("text", DEFAULT_TEXT_SEL), sel("date", DEFAULT_DATE_SEL),
            ).joinToString(",") + "}"
        }
        val idj = "\"" + id.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        val script = """
            (function(){
              var ID=$idj, tries=0, opened=false, acc={}, accN=0, lastN=0, noGrow=0, atBottom=0;
              try{ VelaBridge.onInfo(ID, JSON.stringify({start:1,title:(document.title||'').slice(0,40),url:location.pathname.split('/@')[0].slice(0,60),ready:document.readyState,w:window.innerWidth,h:window.innerHeight})); }catch(e){}
              window.onerror=function(m,src,l){ try{ VelaBridge.onInfo(ID,'jserror '+m+' @'+l); }catch(e){} };
              var openedAt=-1, lastRep=-1, openedBy='', sawEntry=false, everCards=false, btnReclicks=0, allClicked=false;
              var CAP=$cap;
              // The rating sits at the FRONT of the star widget's aria-label in every language
              // ("5 stars", "5 顆星", "5 étoiles"), so read the leading number rather than looking
              // for the English word - that match returned 0 for every review the moment the page
              // was not English (issue #278).
              function num(s){ var m=(s||'').match(/^\s*([1-5])(?:[.,]0)?\b/); return m?parseInt(m[1],10):0; }
              // "Reviews" across the languages Vela ships, for the TAB (matched only against
              // role="tab", where the choices are Overview / Reviews / About, so a loose contains
              // is safe) and for the "more reviews" BUTTON. The button additionally requires a
              // "more" word: a bare review-word match there would hit "Write a review" (zh-TW
              // "撰寫評論"), and clicking that opens the review composer instead of the list.
              // The word lists live in :core ReviewWords so they can be unit-tested; a list that
              // silently stops matching is invisible until someone reports missing reviews.
              // Kotlin templates: `${'$'}{...}` here would emit the LITERAL text into the page
              // (it did from 2026-09-06 to 2026-09-13: "missing ) after argument list" at this
              // line, every scrape timed out with nothing, issue #359 for every language).
              var REVIEW_WORD=new RegExp(${reviewPatternJs()},'i');
              $STRIP_PLACE_NAME_JS
              var MORE_WORD=new RegExp(${morePatternJs()},'i');
              var SEL=${selectorsJs()};
              function t1(c,sel){ var e=c.querySelector(sel); return e?(e.textContent||'').trim():''; }
              function extract(){
                // Review cards are `.jJc9Ad`, each with a unique `data-review-id` - far more robust than the
                // old "div with one star + text" heuristic, which also matched the place header ("4.6 stars
                // (57,969)") and affiliate ticket cards, and missed most real reviews.
                var revs=[].slice.call(document.querySelectorAll(SEL.card));
                return revs.map(function(c){
                  var idEl=c.querySelector(SEL.id); var rid=idEl?(idEl.getAttribute('data-review-id')||idEl.getAttribute('data-id')||''):'';
                  // Rating: the star widget's aria-label LEADS WITH THE NUMBER in every language
                  // ("5 stars", "5 顆星", "5 étoiles", "5 звёзд"), so key on that instead of the
                  // English word. The old `aria-label*="star"` selector matched nothing the moment
                  // the page was served in the user's own language, and every rating came back
                  // null (issue #278; verified live on a zh-TW page where the label read "5 顆星").
                  var star=null;
                  var cand=[].slice.call(c.querySelectorAll('[role="img"][aria-label],span[aria-label]'));
                  for(var si=0;si<cand.length;si++){
                    var sl=(cand[si].getAttribute('aria-label')||'').trim();
                    if(/^[1-5]([.,]0)?(\s|\u00a0)*\D/.test(sl)){ star=cand[si]; break; }
                  }
                  // author: Google's review name class, else pull the NAME out of a button aria - the
                  // name is always right before "'s review" (after a "Share "/"Photo N on " prefix) or
                  // after "Photo of ". (Class names rotate; the aria phrasing is stable + semantic.)
                  var author=t1(c,SEL.author);
                  if(!author){ var bs=[].slice.call(c.querySelectorAll('button[aria-label],a[aria-label]'));
                    var strip=/^(?:Share|Like|Response from|Photo of|Photo\s*\d*\s*on|\+?\s*\d*\s*(?:more\s*)?photos?\s*on|\d+\s*photos?\s*on)\s+/i;
                    for(var i=0;i<bs.length;i++){ var a=bs[i].getAttribute('aria-label')||'';
                      var m=a.match(/^(.+?)'s review\b/); var cand=m?m[1]:(a.match(/^Photo of (.+)${'$'}/)||[])[1];
                      if(cand){ var nm=cand.replace(strip,'').trim(); if(nm){ author=nm; break; } } } }
                  // review text: the wiI7pd body, else the longest leaf span that isn't chrome.
                  var text=t1(c,SEL.text);
                  if(!text){ var best=0; [].slice.call(c.querySelectorAll('span')).forEach(function(s){ if(s.childElementCount===0){ var tt=(s.textContent||'').trim(); if(tt.length>best && tt.length>12 && !/^(see more|more|like|share|response from|local guide)/i.test(tt) && !/\bstar/i.test(tt)){ best=tt.length; text=tt; } } }); }
                  // relative date. `.rsqaWe` is the date element when present; else scan leaf spans.
                  // The old fallback grabbed the FIRST span merely CONTAINING "ago" (tt<22, /\bago\b/) -
                  // which also matches a short sentence in the review body ("been pthere ago"… any body
                  // span with "ago") and only knew English "ago"/bare-year. Anchor to the full relative-
                  // date shape ("10 months ago", "a year ago", "Edited 2 weeks ago") or a lone year,
                  // skip owner "Response" lines, and skip spans whose text is part of the review body -
                  // so we pick the real date, not a phrase out of the prose.
                  var date=t1(c,SEL.date);
                  if(!date){ var body=(text||'').toLowerCase();
                    var reRel=/^(?:edited\s+)?(?:an?|\d+)\s+(?:second|minute|hour|day|week|month|year)s?\s+ago${'$'}/i;
                    [].slice.call(c.querySelectorAll('span')).forEach(function(s){ if(date||s.childElementCount>0) return;
                      var tt=(s.textContent||'').trim();
                      if(tt.length<28 && (reRel.test(tt)||/^20\d\d${'$'}/.test(tt)) && !/^response/i.test(tt) && body.indexOf(tt.toLowerCase())<0) date=tt; }); }
                  var avatar=''; var ai=c.querySelector('img'); if(ai && /googleusercontent/.test(ai.src||'')) avatar=ai.src;
                  var photos=[];
                  function addPhoto(u){ if(u && u!==avatar && /googleusercontent/.test(u) && !/\/a[\/-]|ACg8oc|ALV-/.test(u) && photos.indexOf(u)<0) photos.push(u); }
                  // Uploaded review photos are a <button>/<a> with a background-image on most layouts, but
                  // some cards expose them as plain <img> tiles - collect BOTH (avatar-filtered) so a card
                  // whose photos aren't button-backed still gets a tappable, author·date-captioned strip.
                  // (Was button-background-only, which silently dropped the whole strip on those cards.)
                  [].slice.call(c.querySelectorAll('button,a')).forEach(function(b){
                    var bg=''; try{ bg=getComputedStyle(b).backgroundImage||''; }catch(e){}
                    var mm=bg.match(/url\(["']?(https:\/\/[^"')]+googleusercontent[^"')]+)/);
                    if(mm) addPhoto(mm[1]);
                  });
                  [].slice.call(c.querySelectorAll('img')).forEach(function(im){ addPhoto(im.src||''); });
                  return { rid:rid, r:num(star&&star.getAttribute('aria-label')), a:author.slice(0,80), d:date, t:text, av:avatar, p:photos.slice(0,10) };
                  // Require an AUTHOR (rid stays the de-dup key): the parser drops author-less entries
                  // anyway, so letting them through only wastes CAP slots on cards we can't render.
                }).filter(function(x){ return x.a; });
              }
              // Expand truncated review bodies. The class hook (`.w8nwRe` is the card's More toggle)
              // works in EVERY UI language; the label regex stays as a fallback for older layouts
              // (it only knows English, which silently skipped expansion under any other hl).
              function expand(){
                [].slice.call(document.querySelectorAll(SEL.moreToggle)).forEach(function(b){ try{ b.click(); }catch(e){} });
                [].slice.call(document.querySelectorAll('button')).forEach(function(b){ var l=((b.getAttribute('aria-label')||b.textContent)||'').trim(); if(/^(see more|more)${'$'}/i.test(l)){ try{ b.click(); }catch(e){} } });
              }
              // De-dupe across scroll windows by the review's stable id (falls back to author+date+text).
              function key(x){ return x.rid || ((x.a||'')+'|'+(x.d||'')+'|'+((x.t||'').slice(0,48))); }
              // The accumulated reviews so far, capped - used for both the partial streams and the
              // final result, so a partial is always a prefix-consistent snapshot of the final list.
              function snap(){ var o=[]; for(var k in acc) o.push(acc[k]); return o.slice(0,CAP); }
              // Scroll each tall left-column panel down by ~80% of a viewport (windows overlap so no
              // card is skipped past). Returns true if anything actually moved (false ⇒ at the bottom).
              function scrollStep(){
                var moved=false;
                try{ [].slice.call(document.querySelectorAll('div')).forEach(function(d){
                  if(d.scrollHeight>d.clientHeight+200 && d.clientHeight>250 && d.getBoundingClientRect().left<640){
                    var before=d.scrollTop; d.scrollTop=Math.min(d.scrollHeight, d.scrollTop+Math.round(d.clientHeight*0.8));
                    if(d.scrollTop>before+5) moved=true;
                  }
                }); }catch(e){}
                // Narrow layout (the hidden WebView is ~450 CSS px wide on a 2.75x phone): the
                // review feed is not always an inner scroller, the DOCUMENT pages it. Scroll the
                // window too, or the scrape settles on the first 5 cards (2026-09-13).
                if(!moved){ try{ var y0=window.scrollY; window.scrollBy(0, Math.round(window.innerHeight*0.8)); if(window.scrollY>y0+5) moved=true; }catch(e){} }
                return moved;
              }
              // Open the FULL reviews list. The canonical entry is the "Reviews" role=tab; fall back to a
              // "More reviews" button for layouts that only expose that. On busy pages (food/retail) the
              // tab's list can take ~8 s to render after the click - the idle-bail is gated on `sawCards`
              // below so we never quit during that blank window (that was the "only 3 reviews" bug).
              function openFull(){
                // Prefer the "Reviews" role=tab. Click it every tick UNTIL it actually reports selected -
                // a click on a not-yet-hydrated tab silently no-ops, so one-and-done can leave the list
                // unopened. Once selected we latch `opened` and STOP clicking: re-clicking a selected-but-
                // still-loading list restarts its ~8 s render (that regression turned busy pages back to 3).
                var ts=[].slice.call(document.querySelectorAll('[role="tab"]'));
                for(var i=0;i<ts.length;i++){
                  var tl=velaNoName(((ts[i].getAttribute('aria-label')||ts[i].textContent)||'').trim());
                  if(REVIEW_WORD.test(tl)){
                    sawEntry=true;
                    if((ts[i].getAttribute('aria-selected')||'')==='true'){ if(!opened){ opened=true; openedAt=tries; openedBy='tab'; } return; }
                    try{ ts[i].click(); }catch(e){}
                    return;
                  }
                }
                // No reviews tab in this layout - fall back to the "More reviews" button. Unlike the
                // tab there's no aria-selected to confirm the click took, so it's clicked once and
                // the tick loop re-arms it ONE time if nothing ever renders (a not-yet-hydrated
                // button silently no-ops, same as the tab).
                if(opened) return;
                var bs=[].slice.call(document.querySelectorAll('button'));
                for(var i=0;i<bs.length;i++){ var l=velaNoName((bs[i].getAttribute('aria-label')||bs[i].textContent)||''); if(REVIEW_WORD.test(l)&&MORE_WORD.test(l)){ sawEntry=true; try{ bs[i].click(); }catch(e){} opened=true; openedAt=tries; openedBy='btn'; return; } }
              }
              var histSent=false;
              function hist(){ if(histSent) return; var c={};
                [].slice.call(document.querySelectorAll('tr[aria-label]')).forEach(function(r){
                  var m=(r.getAttribute('aria-label')||'').match(/^\s*([1-5])(?!\d|[.,]\d)\D+?(\d[\d.,\s\u00a0\u202f]*)/);
                  if(m) c[m[1]]=parseInt(m[2].replace(/\D/g,''),10);
                });
                if(c['5']!==undefined && c['1']!==undefined){ histSent=true; try{ VelaBridge.onHistogram(ID, JSON.stringify([c['5']||0,c['4']||0,c['3']||0,c['2']||0,c['1']||0])); }catch(e){} }
              }
              function tick(){
                tries++;
                hist();
                // Let the SPA hydrate a beat before clicking the Reviews tab - clicking a not-yet-live
                // tab on tick 1 can silently no-op, and then the list only renders much later.
                if(tries>=2) openFull();
                expand();
                // ACCUMULATE this window's cards (don't replace) - the panel virtualizes, so each
                // scroll position exposes a fresh ~10 that would otherwise be lost when recycled.
                // Except the TEXT: a card is often harvested on the tick its More toggle was
                // clicked, before Google's async re-render swaps in the full body - so a longer
                // text for a known key REPLACES the stored entry (the "…"-truncated first capture
                // otherwise won forever; the ellipsis was in our data, not the UI).
                var revs=extract();
                for(var i=0;i<revs.length;i++){ var k=key(revs[i]); if(k.length>2){ if(!acc[k]){ acc[k]=revs[i]; accN++; } else if((revs[i].t||'').length>(acc[k].t||'').length){ acc[k]=revs[i]; } } }
                // Stream progress whenever the count grows: the running count (drives the "N of ~M"
                // bar) AND the accumulated reviews themselves, so the sheet fills in under the bar
                // while the scrape grinds instead of making the user stare at a bar for 30 s.
                if(accN!==lastRep){ lastRep=accN;
                  try{ VelaBridge.onProgress(ID, accN); }catch(e){}
                  try{ VelaBridge.onPartial(ID, JSON.stringify(snap())); }catch(e){}
                }
                // Are review cards rendered RIGHT NOW? On busy business pages (food, retail) the Reviews
                // tab's list can take ~8 s to populate after the click; until then the panel holds only
                // the rating histogram + topic chips, NOT the cards. This must be a per-tick check, not a
                // once-latched flag: the OVERVIEW's 3 preview cards render briefly before the tab click
                // blanks the panel, and a latch set by those let the idle-bail fire during the blank
                // window with exactly 3 accumulated (the "loaded 3 then stopped" bug).
                var cardsNow = document.querySelectorAll(SEL.card).length>0;
                if(cardsNow) everCards=true;
                if(tries===2 || tries%16===0){
                  try{
                    var tabLabels=[].slice.call(document.querySelectorAll('[role="tab"]')).map(function(t){ return ((t.getAttribute('aria-label')||t.textContent)||'').trim().slice(0,40); }).slice(0,4);
                    VelaBridge.onInfo(ID, JSON.stringify({tries:tries,tabs:tabLabels,sawEntry:sawEntry,opened:opened,by:openedBy,cardsNow:document.querySelectorAll(SEL.card).length,acc:accN,w:window.innerWidth,h:window.innerHeight,main:!!document.querySelector('[role="main"]'),title:(document.title||'').slice(0,40),body:((document.body&&document.body.innerText)||'').length,url:location.pathname.split('/@')[0].slice(0,60)}));
                  }catch(e){}
                }
                var moved=scrollStep();
                atBottom = moved ? 0 : atBottom+1;
                noGrow = (accN===lastN) ? noGrow+1 : 0;
                lastN=accN;
                // Desktop layout (2026-09-13): the Reviews TAB shows a handful of cards and an
                // "All reviews" button opens the full paged list. The tab path latches `opened`,
                // so that button was never pressed and the scrape settled on the handful. Press
                // it once, after the tab has had its render window, if the list is still short.
                if(opened && openedBy==='tab' && !allClicked && tries>=openedAt+10 && accN<=12){
                  allClicked=true;
                  var abs=[].slice.call(document.querySelectorAll('button'));
                  for(var i=0;i<abs.length;i++){ var al=((abs[i].getAttribute('aria-label')||abs[i].textContent)||''); if(REVIEW_WORD.test(al)&&MORE_WORD.test(al)){ try{ abs[i].click(); }catch(e){} openedAt=tries; break; } }
                }
                // Button-path no-op retry: the click was fired blind (no aria-selected to confirm)
                // and nothing has rendered since - re-arm openFull once. Tab clicks self-retry.
                if(opened && openedBy==='btn' && !everCards && tries>=openedAt+18 && btnReclicks<1){ opened=false; openedAt=-1; btnReclicks++; }
                // Idle-bail ONLY while cards are actually on screen. When an entry (tab/button)
                // exists but hasn't opened yet, hold longer so a late-hydrating tab still gets its
                // click; a layout with NO entry at all (a tiny place whose full list IS the
                // overview) settles quickly - there's nothing more to open.
                var settled = cardsNow && (opened ? tries>=openedAt+13 : (sawEntry ? tries>=30 : tries>=17));
                // Zero-review places: no card will EVER render, so "settled" never fires - bail on
                // a generous empty deadline instead of grinding to the 60-tick hard stop (~33 s of
                // blank spinner on every review-less place).
                var emptyDone = !everCards && accN===0 && (opened ? tries>=openedAt+52 : tries>=65);
                // Idle patience: the OPENED full list pages over the network - Google's lazy-loader
                // routinely takes >2 s to fetch the next ~10 on a busy place, and 4 quiet ticks
                // (2.2 s) misread that as "done" (Taco Bell returned ~15 of 612). The unopened
                // overview has nothing to page, so it keeps the short fuse.
                var idle = opened ? (atBottom>=13 && noGrow>=18) : (atBottom>=9 && noGrow>=9);
                // Done: cap hit, OR settled at the bottom with no new reviews, OR provably empty,
                // OR ran long.
                if( accN>=CAP || (settled && idle) || emptyDone || tries>130 ){
                  try{ VelaBridge.onResult(ID, JSON.stringify(snap())); }catch(e){ try{ VelaBridge.onResult(ID,'[]'); }catch(e2){} }
                  return;
                }
                setTimeout(tick, 250);
              }
              tick();
            })();
        """.trimIndent()
        return if (translations) withTranslations(script) else script
    }

    /** Google's translation notice, in every page language the reviews scraper serves. The text is
     *  content, so it survives the class-name rotation that breaks selectors. */
    private const val TRANSLATED_PATTERN =
        "translated by google|traduit par google|von google übersetzt|traducido por google|" +
            "tradotto da google|traduzido pelo google|vertaald door google|переведено google|" +
            "перекладено google|przetłumaczone przez google|översatt av google|" +
            "google által lefordítva|tradus de google|תורגם על ידי google|" +
            "由 google 翻译|由 google 翻譯|google で翻訳|google 翻訳|自動翻訳|已翻译|已翻譯"

    /**
     * The base scraper plus the translation flag. Kept as an append so the bytes Android sends are
     * unchanged when [translations] is off (the moved-script test pins them).
     */
    private fun withTranslations(script: String): String {
        val helper = """
            var TR_WORD=new RegExp(${jsString(TRANSLATED_PATTERN)},'i');
            function velaTranslated(c){
              var els=[].slice.call(c.querySelectorAll('span,div,a,button'));
              for(var i=0;i<els.length;i++){
                if(els[i].childElementCount>0) continue;
                var tt=(els[i].textContent||'').trim();
                if(tt.length>0 && tt.length<=70 && TR_WORD.test(tt)) return 1;
              }
              return 0;
            }
        """.trimIndent()
        return script
            .replace("function tick(){", "$helper\n              function tick(){")
            .replace(
                "av:avatar, p:photos.slice(0,10) };",
                "av:avatar, p:photos.slice(0,10), tr:velaTranslated(c) };",
            )
    }

    /** [v] as a double-quoted JavaScript string literal. */
    fun jsString(v: String): String =
        "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}
