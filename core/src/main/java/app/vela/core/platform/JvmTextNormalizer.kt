package app.vela.core.platform

import java.text.Normalizer

/** [TextNormalizer] over `java.text.Normalizer`. */
object JvmTextNormalizer : TextNormalizer {
    override fun normalize(text: String, form: NormalForm): String = Normalizer.normalize(
        text,
        when (form) {
            NormalForm.NFC -> Normalizer.Form.NFC
            NormalForm.NFD -> Normalizer.Form.NFD
            NormalForm.NFKC -> Normalizer.Form.NFKC
            NormalForm.NFKD -> Normalizer.Form.NFKD
        },
    )
}
