import Foundation
import Security
#if UPDATE
print("Updated signing probe")
#else
print("Initial signing probe")
#endif
let arguments = CommandLine.arguments
var keychain: SecKeychain?
precondition(SecKeychainOpen(arguments[1], &keychain) == errSecSuccess)
precondition(SecKeychainSetUserInteractionAllowed(false) == errSecSuccess)
let service = "io.github.calendar-bar.signing-probe"
var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service, kSecAttrAccount as String: "fictional"]
if arguments[2] == "create" {
    query[kSecUseKeychain as String] = keychain!
    query[kSecValueData as String] = Data("fictional-fixture-only".utf8)
    precondition(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
    print("Created fictional item")
} else {
    query[kSecMatchSearchList as String] = [keychain!]
    query[kSecReturnData as String] = true
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &value)
    if arguments[2] == "denied" {
        precondition(status == errSecAuthFailed || status == errSecInteractionNotAllowed)
        print("Unrelated signer denied")
    } else {
        precondition(status == errSecSuccess)
        precondition(value as? Data == Data("fictional-fixture-only".utf8))
        print("Fictional item read without authorization UI")
    }
}
