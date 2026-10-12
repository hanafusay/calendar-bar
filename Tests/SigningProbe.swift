import Foundation
import Security
import Darwin
setbuf(stdout, nil)
#if UPDATE
print("Updated signing probe")
#else
print("Initial signing probe")
#endif
let arguments = CommandLine.arguments
var keychain: SecKeychain?
precondition(SecKeychainOpen(arguments[1], &keychain) == errSecSuccess)
precondition(SecKeychainSetUserInteractionAllowed(false) == errSecSuccess)
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
  kSecAttrService as String: "io.github.calendar-bar.signing-probe",
  kSecAttrAccount as String: "fictional", kSecMatchSearchList as String: [keychain!]]
func itemReference() -> SecKeychainItem {
  var referenceQuery = query
  referenceQuery[kSecReturnRef as String] = true
  var reference: CFTypeRef?
  precondition(SecItemCopyMatching(referenceQuery as CFDictionary, &reference) == errSecSuccess)
  return reference as! SecKeychainItem
}
if arguments[2] == "create" {
  precondition(KeychainAccess.isOfficialRelease())
  var current: SecTrustedApplication?
  var legacy: SecTrustedApplication?
  precondition(SecTrustedApplicationCreateFromPath(nil, &current) == errSecSuccess)
  precondition(SecTrustedApplicationCreateFromPath(arguments[3], &legacy) == errSecSuccess)
  var access: SecAccess?
  precondition(SecAccessCreate("Fictional migration fixture" as CFString, [current!, legacy!] as CFArray, &access) == errSecSuccess)
  var migrationGrant: SecACL?
  precondition(SecACLCreateWithSimpleContents(access!, [current!] as CFArray,
    "Authorized fictional migration" as CFString, SecKeychainPromptSelector(), &migrationGrant) == errSecSuccess)
  precondition(SecACLUpdateAuthorizations(migrationGrant!,
    [kSecACLAuthorizationChangeACL] as CFArray) == errSecSuccess)
  var add = query
  add.removeValue(forKey: kSecMatchSearchList as String)
  add[kSecUseKeychain as String] = keychain!
  add[kSecValueData as String] = Data("fictional-fixture-only".utf8)
  add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  add[kSecAttrAccess as String] = access!
  precondition(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
  print("Fictional value stored")
  print("Created fictional legacy item and authorized its migration")
} else if arguments[2] == "migrate" {
  precondition(KeychainAccess.isOfficialRelease())
  let migrated = try KeychainAccess.migrate(itemReference())
  precondition(migrated)
  print("Migrated access metadata while preserving fictional credential bytes")
} else if arguments[2] == "replace" {
  let changed = [kSecValueData as String: Data("fictional-reconnected".utf8)]
  precondition(SecItemUpdate(query as CFDictionary, changed as CFDictionary) == errSecSuccess)
  print("Replaced fictional value as during reconnection")
} else {
  var lookup = query
  lookup[kSecReturnData as String] = true
  var value: CFTypeRef?
  let status = SecItemCopyMatching(lookup as CFDictionary, &value)
  if arguments[2] == "denied" {
    precondition(status == errSecAuthFailed || status == errSecInteractionNotAllowed, "Unexpected access status: \(status)")
    print("Unauthorized access denied")
  } else {
    precondition(status == errSecSuccess)
    let expected = arguments[2] == "updated-value" ? "fictional-reconnected" : "fictional-fixture-only"
    precondition(value as? Data == Data(expected.utf8))
    print("Fictional item read without authorization UI")
  }
}
