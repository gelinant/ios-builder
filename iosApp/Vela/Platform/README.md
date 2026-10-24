# Platform seams in Swift

The Swift implementations of the Kotlin platform seams (`PORTAGE_IOS.md` 3.1) live here, one
file per seam: `Log`, `Clock`, `KeyValueStore`, `PlatformFiles`, `VelaHttp`, and so on. Each
one conforms to the callback-style Kotlin interface that VelaCore exports, and `IosGraph`
receives them when the app starts.

None is written yet: the interfaces land with F-2 and the first conformance (`VelaHttp` over
`URLSession`) with V-2. This file is excluded from the app target in `project.yml`.
