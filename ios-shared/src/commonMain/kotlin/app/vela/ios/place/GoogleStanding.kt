package app.vela.ios.place

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Whether Google gives this session its limited view, as Android's `GoogleStanding` judges it: a
 * first photo page of at most [LIMITED_PHOTO_PAGE_MAX] with a next page waiting marks it, one of
 * at least [FULL_PHOTO_PAGE_MIN] clears it. On iOS every launch is a new Google session (the
 * cookie jar and the WKWebView store live in memory), Android's `SessionRotation` "launch" mode,
 * so the mark is kept in memory only.
 */
class GoogleStanding {
    private val _limited = MutableStateFlow(false)
    val limited: StateFlow<Boolean> = _limited.asStateFlow()

    fun onPhotoPage(count: Int, hasMore: Boolean) {
        when {
            count >= FULL_PHOTO_PAGE_MIN -> _limited.value = false
            hasMore && count in 1..LIMITED_PHOTO_PAGE_MAX -> _limited.value = true
        }
    }

    /** Android's all-reviews panel marks the session when its More reviews button adds nothing. */
    fun onMoreReviewsStalled() {
        _limited.value = true
    }

    companion object {
        const val LIMITED_PHOTO_PAGE_MAX = 20
        const val FULL_PHOTO_PAGE_MIN = 40
    }
}
