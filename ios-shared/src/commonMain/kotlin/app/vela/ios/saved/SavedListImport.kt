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

/**
 * Reading a shared Google Maps list through the hidden WebView (IMP-GOOGLE).
 *
 * Google's share page no longer carries the list's places: for a direct list link the id sits in
 * the URL, and the places come from the keyless `/maps/preview/entitylist/getlist` RPC. A short
 * link first has to resolve to that page, so the script reads the id from the page it actually
 * landed on, or lifts the RPC URL from the page when it has one. The body is handed to
 * `EntityListParser`, the parser the Android app already uses; a page whose shape changed yields
 * no list rather than a guessed one.
 */
object SavedListImport {
    /** The hidden page reports three stages: loaded, list located, reply fetched. */
    const val GOOGLE_STAGES = 3

    /** As many places as the Android import asks for. */
    const val LIST_PAGE_SIZE = 2000

    /** The list id already present in a direct link, or empty for a short link. */
    fun listId(link: String): String = ShortLinks.listId(link).orEmpty()

    /** True for a Google host a list link can legitimately live on. */
    fun isGoogleLink(link: String): Boolean {
        val trimmed = link.trim()
        if (!trimmed.startsWith("http://", ignoreCase = true) && !trimmed.startsWith("https://", ignoreCase = true)) return false
        val host = trimmed.substringAfter("://").substringBefore('/').substringBefore('?').substringBefore('#').lowercase()
        return host == "goo.gl" || host.endsWith(".goo.gl") ||
            host == "google.com" || host.endsWith(".google.com") ||
            host.startsWith("maps.google.")
    }

    /**
     * The page script for request [requestId]. `VelaBridge` and `VelaPanel` are the readable names
     * the hidden WebView swaps for its per-process random ones before evaluation.
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
              function idFrom(u){
                if(!u) return '';
                var m=u.match(/\/maps\/placelists\/list\/([A-Za-z0-9_-]+)/);
                if(m) return m[1];
                m=u.match(/!11m2!2s([A-Za-z0-9_-]+)!3e/);
                return m?m[1]:'';
              }
              var id = KNOWN || idFrom(location.href||'');
              var url = id ? '/maps/preview/entitylist/getlist?authuser=0&hl=en&gl=us&pb=!1m4!1s'+id+'!2e1!3m1!1e1!2e2!3e2!4i$LIST_PAGE_SIZE!28e2!16b1' : '';
              if(!url){
                var html='';
                try{ html=document.documentElement?document.documentElement.innerHTML:''; }catch(e){}
                var m=html.match(/\/maps\/preview\/entitylist\/getlist\?[^"'\s<>]+/);
                if(m){
                  url=m[0].split('&amp;').join('&').split('%214i500').join('%214i$LIST_PAGE_SIZE').split('!4i500').join('!4i$LIST_PAGE_SIZE');
                }
              }
              if(!url){ finish(''); return; }
              post('onProgress','2');
              fetch(url,{credentials:'same-origin'}).then(function(r){
                return r.ok ? r.text() : '';
              }).then(function(t){
                if(!t){ finish(''); return; }
                post('onProgress','3');
                finish(t);
              }).catch(function(){ finish(''); });
            })();
        """.trimIndent()
    }
}
