import Foundation

/// A `https://maps.google.com/?cid=...` link names a Google place only by its numeric cid. Vela
/// cannot turn that into a name or a point without Google, but a saved place already carries the
/// feature id whose second half is the same number in hexadecimal, so that link can still open.
extension SavedModel {
    func incomingPlace(cid: String) -> SavedPlaceItem? {
        guard let value = UInt64(cid) else { return nil }
        let tail = "0x" + String(value, radix: 16)
        return savedPlaces.first { item in
            guard let featureID = item.featureId?.lowercased() else { return false }
            return featureID.split(separator: ":").last.map(String.init) == tail
        }
    }
}
