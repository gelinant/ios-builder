import Contacts
import Foundation

/// The person and number behind a spoken or typed "call X".
struct ContactMatch: Equatable {
    let name: String
    let phone: String
}

/// The only place iOS reads the address book. It is never touched at launch and never written to
/// disk: a "call" command asks for access the first time, reads the matching contacts, and keeps
/// nothing after the answer. A refusal is reported so the map can offer the ordinary place search
/// instead.
enum ContactsBridge {
    enum Access: Equatable {
        case granted
        case denied

        var label: String { self == .granted ? "granted" : "denied" }
    }

    /// The installed app's own words, not a pre-flight dialog: iOS shows this string in its system
    /// prompt when the first "call" command asks.
    static let rationale = "Vela looks up the person you asked for, on this phone only. Contacts are never uploaded or kept."

    /// Resolve [name] to the first contact with a phone number, after asking for access if this is
    /// the first call. Returns the access state with the match, so the caller can explain a refusal.
    static func resolve(name: String, store: CNContactStore = CNContactStore()) async -> (Access, ContactMatch?) {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return (permission(store), nil) }
        #if DEBUG
        if let fixture = fixturePermission {
            guard fixture == .granted else { return (.denied, nil) }
            return (.granted, fixtureContacts.first {
                $0.name.localizedCaseInsensitiveContains(query)
            })
        }
        #endif
        let access = await access(store)
        guard access == .granted else { return (access, nil) }
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
        ] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        for contact in contacts {
            guard let number = contact.phoneNumbers.first?.value.stringValue, !number.isEmpty else { continue }
            let full = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            return (.granted, ContactMatch(name: full.isEmpty ? query : full, phone: number))
        }
        return (.granted, nil)
    }

    /// The current state without prompting: used by the debug line only.
    static func permission(_ store: CNContactStore = CNContactStore()) -> Access {
        #if DEBUG
        if let fixture = fixturePermission { return fixture }
        #endif
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .granted
        case .notDetermined: return .denied
        default:
            if #available(iOS 18.0, *),
               CNContactStore.authorizationStatus(for: .contacts) == .limited {
                return .granted
            }
            return .denied
        }
    }

    /// True under the UI-test address book, where opening a `tel:` URL would leave the app.
    static var usesFixture: Bool {
        #if DEBUG
        return fixturePermission != nil
        #else
        return false
        #endif
    }

    private static func access(_ store: CNContactStore) async -> Access {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return .granted }
        if #available(iOS 18.0, *), status == .limited { return .granted }
        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            return granted ? .granted : .denied
        }
        return .denied
    }

    #if DEBUG
    /// UI scenarios cannot tap a system permission alert reliably, so they name the answer and a
    /// small address book on the launch line. Read only when a "call" command runs.
    private static var fixturePermission: Access? {
        guard let raw = argument("VelaContactsPermission")?.lowercased() else { return nil }
        return raw == "granted" || raw == "allow" ? .granted : .denied
    }

    private static var fixtureContacts: [ContactMatch] {
        guard let raw = argument("VelaContactsFixture") else { return [] }
        return raw.split(separator: ";").compactMap { row in
            let parts = row.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let phone = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !phone.isEmpty else { return nil }
            return ContactMatch(name: name, phone: phone)
        }
    }

    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
    #endif
}
