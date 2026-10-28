package app.vela.ios.saved

import app.vela.core.data.ShortLinks

/** One list an import would write, and what it would land on. */
data class SavedPendingList(
    val title: String,
    val count: Int,
    /** The list already holding this import's source, or null when the import creates one. */
    val existingListId: String? = null,
    val existingCount: Int = 0,
)

/**
 * An import that is parsed but not written: a second import of the same list or file asks merge or
 * replace instead of silently doubling the places. [source] is `GOOGLE` or `FILE`, so Swift can
 * word the question.
 */
data class SavedPendingImport(
    val source: String,
    val title: String,
    val count: Int,
    val lists: List<SavedPendingList> = emptyList(),
) {
    val existingCount: Int get() = lists.sumOf { if (it.existingListId != null) it.existingCount else 0 }
    val hasExisting: Boolean get() = lists.any { it.existingListId != null }
}

/** A single place a share link resolved to. It opens the place sheet, never a fake list. */
data class SavedSharedPlace(
    val name: String,
    val lat: Double,
    val lng: Double,
)

/**
 * Reading a shared Google Maps list through the hidden WebView (IMP-GOOGLE).
 *
 * Google's share page no longer carries the list's places: for a direct list link the id sits in
 * the URL, and the places come from the keyless `/maps/preview/entitylist/getlist` RPC. A short
 * link (`maps.app.goo.gl/...`, `goo.gl/maps/...`) first redirects, in the WebView, to a
 * `/maps/@/data=...!11m2!2s<id>!3e2` page, often through a country host and its consent
 * interstitial. The script reads the id from the URL it actually landed on (or from the page),
 * moves to the canonical `www.google.com` page carrying that id, whose consent cookies the hidden
 * store already holds, then calls the RPC. The body is handed to `EntityListParser`, the parser the
 * Android app already uses; a page whose shape changed yields no list rather than a guessed one.
 */
object SavedListImport {
    /** The hidden page reports three stages: loaded, list located, reply fetched. */
    const val GOOGLE_STAGES = 3

    /** As many places as the Android import asks for. */
    const val LIST_PAGE_SIZE = 2000

    /** What the page script posts instead of a reply body when there is no list to read. */
    const val FAILURE_PREFIX = "#vela:"
    const val FAIL_CONSENT = FAILURE_PREFIX + "consent"
    const val FAIL_PRIVATE = FAILURE_PREFIX + "private"
    const val FAIL_CHANGED = FAILURE_PREFIX + "changed"
    const val FAIL_NO_ID = FAILURE_PREFIX + "noid"
    const val FAIL_PLACE = FAILURE_PREFIX + "place"

    /** The list id already present in a direct link, or empty for a short link. */
    fun listId(link: String): String = ShortLinks.listId(link).orEmpty()

    /**
     * The shared list id carried by the page a link landed on: the URL first (a resolved short
     * link keeps it in the `!11m2!2s<id>!3e` data blob, a consent interstitial in `continue`),
     * then the page itself (the older placelists path or the local userlists link).
     */
    fun listIdFromPage(pageUrl: String?, html: String?): String {
        val direct = listId(pageUrl.orEmpty())
        if (direct.isNotEmpty()) return direct
        val page = html.orEmpty()
        if (page.isEmpty()) return ""
        LIST_ID_DATA.find(page)?.let { return it.groupValues[1] }
        LIST_ID_PATH.find(page)?.let { return it.groupValues[1] }
        LIST_ID_USERLISTS.find(page)?.let { return it.groupValues[1] }
        return ""
    }

    private val LIST_ID_DATA = Regex("""!11m2!2s([A-Za-z0-9_-]+)!3e""")
    private val LIST_ID_PATH = Regex("""/maps/placelists/list/([A-Za-z0-9_-]+)""")
    private val LIST_ID_USERLISTS = Regex("""/local/userlists/list/([A-Za-z0-9_-]+)""")

    /**
     * Stable identity of a shared list: its id, never the short code, so the same list reached
     * through two different short links still asks Merge or Replace. The link is the fallback only
     * when no id was found, which is already a failed import.
     */
    fun sourceId(link: String, listId: String?): String {
        val id = listId?.trim().orEmpty()
        return "list:" + if (id.isNotEmpty()) id else link.trim()
    }

    /** True for a Google host a list link or its redirect can legitimately live on. */
    fun isGoogleLink(link: String): Boolean {
        val trimmed = link.trim()
        if (!trimmed.startsWith("http://", ignoreCase = true) && !trimmed.startsWith("https://", ignoreCase = true)) return false
        val host = trimmed.substringAfter("://").substringBefore('/').substringBefore('?').substringBefore('#')
            .substringBefore(':').lowercase()
        return host == "goo.gl" || host.endsWith(".goo.gl") ||
            host == "g.co" || host.endsWith(".g.co") ||
            host == "google.com" || host.endsWith(".google.com") ||
            host.startsWith("maps.google.") ||
            host.startsWith("consent.google.") ||
            GOOGLE_COUNTRY_HOST.matches(host)
    }

    /** Any `www.google.<tld>` / `maps.google.<tld>` country host the shortener can answer with. */
    private val GOOGLE_COUNTRY_HOST = Regex("""(^|.*\.)google\.[a-z]{2,3}(\.[a-z]{2})?$""")

    /**
     * The page script for request [requestId]. `VelaBridge` and `VelaPanel` are the readable names
     * the hidden WebView swaps for its per-process random ones before evaluation.
     *
     * It finishes with the raw getlist body, or with one of the `#vela:` reasons, so the store can
     * word an honest failure. A single place link reports its name and coordinates on `onInfo`
     * before `FAIL_PLACE`: Saved opens the place sheet instead of inventing a one-place list.
     */
    fun googleScript(requestId: String, listId: String): String {
        fun js(value: String): String =
            "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        val id = js(requestId)
        val known = js(listId)
        return """
            (function(){
              var ID=$id, KNOWN=$known, done=false;
              function post(n,a){ try{ VelaBridge[n](ID,a); }catch(e){} }
              function finish(t){ if(done) return; done=true; post('onResult', t||''); }
              function fail(r){ finish('$FAILURE_PREFIX'+r); }
              function html(){ try{ return document.documentElement?document.documentElement.innerHTML:''; }catch(e){ return ''; } }
              function idFrom(u){
                if(!u) return '';
                var m=u.match(/\/maps\/placelists\/list\/([A-Za-z0-9_-]+)/);
                if(m) return m[1];
                m=u.match(/\/local\/userlists\/list\/([A-Za-z0-9_-]+)/);
                if(m) return m[1];
                m=u.match(/!11m2!2s([A-Za-z0-9_-]+)!3e/);
                return m?m[1]:'';
              }
              function placeFrom(u){
                if(!u) return null;
                var m=u.match(/\/maps\/place\/([^\/@]+)\/@(-?[0-9.]+),(-?[0-9.]+)/);
                if(!m) return null;
                var name=m[1];
                try{ name=decodeURIComponent(name.split('+').join(' ')); }catch(e){}
                if(!name) return null;
                return {name:name,lat:m[2],lng:m[3]};
              }
              var href=location.href||'';
              var net='';
              try{ net=new URL(href).searchParams.get('continue')||''; }catch(e){}
              var host=(location.hostname||'').toLowerCase();
              var consent=host.indexOf('consent.')===0;
              var page=html();
              var id = KNOWN || idFrom(href) || idFrom(net) || idFrom(page);
              if(!id){
                var place=placeFrom(net)||placeFrom(href);
                if(place){
                  post('onInfo','place|'+place.name+'|'+place.lat+'|'+place.lng);
                  fail('place');
                  return;
                }
                fail(consent || /consent/i.test(page) ? 'consent' : 'noid');
                return;
              }
              // The hidden store seeds Google consent for .google.com only, so a country host can
              // answer with an interstitial. Move once to the canonical page carrying the id.
              var canonical = host==='www.google.com' || host==='google.com';
              if(!canonical){
                if(consent && /continue=[^&]*google\.com/.test(href)){ fail('consent'); return; }
                post('onProgress','2');
                try{
                  location.replace('https://www.google.com/maps/@/data=!3m1!4b1!4m3!11m2!2s'+id+'!3e2?vela=1');
                }catch(e){ fail('noid'); }
                return;
              }
              post('onProgress','2');
              var url='/maps/preview/entitylist/getlist?authuser=0&hl=en&gl=us&pb=!1m4!1s'+id+'!2e1!3m1!1e1!2e2!3e2!4i$LIST_PAGE_SIZE!28e2!16b1';
              fetch(url,{credentials:'same-origin'}).then(function(r){
                if(r.status===401 || r.status===403){ fail('private'); return ''; }
                if(!r.ok){ fail('changed'); return ''; }
                return r.text();
              }).then(function(t){
                if(!t){ fail('changed'); return; }
                post('onProgress','3');
                finish(t);
              }).catch(function(){ fail('changed'); });
            })();
        """.trimIndent()
    }
}
