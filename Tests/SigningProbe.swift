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
  var add = query
  add.removeValue(forKey: kSecMatchSearchList as String)
  add[kSecUseKeychain as String] = keychain!
  add[kSecValueData as String] = Data("fictional-fixture-only".utf8)
  add[kSecAttrAccess as String] = access!
  precondition(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
  var code: SecCode?
  var staticCode: SecStaticCode?
  var information: CFDictionary?
  precondition(SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess)
  precondition(SecCodeCopyStaticCode(code!, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess)
  precondition(SecCodeCopySigningInformation(staticCode!, SecCSFlags(rawValue: 0), &information) == errSecSuccess)
  let hash = ((information as! [String: Any])[kSecCodeInfoUnique as String] as! Data).map { String(format: "%02x", $0) }.joined()
  let data = try PropertyListSerialization.data(fromPropertyList: ["Partitions": ["cdhash:" + hash]], format: .xml, options: 0)
  let descriptor = data.map { String(format: "%02x", $0) }.joined()
  var partition: SecACL?
  precondition(SecACLCreateWithSimpleContents(access!, nil, descriptor as CFString, SecKeychainPromptSelector(), &partition) == errSecSuccess)
  precondition(SecACLUpdateAuthorizations(partition!, [kSecACLAuthorizationPartitionID] as CFArray) == errSecSuccess)
  precondition(SecKeychainItemSetAccess(itemReference(), access!) == errSecSuccess)
  print("Created fictional legacy item with per-binary partition and legacy app trust")
} else if arguments[2] == "migrate" {
  precondition(KeychainAccess.isOfficialRelease())
  let migrated = try KeychainAccess.migrate(itemReference())
  precondition(migrated)
  print("Migrated access metadata while preserving fictional credential bytes")
} else {
  var lookup = query
  lookup[kSecReturnData as String] = true
  var value: CFTypeRef?
  let status = SecItemCopyMatching(lookup as CFDictionary, &value)
  if arguments[2] == "denied" {
    precondition(status == errSecAuthFailed || status == errSecInteractionNotAllowed)
    print("Unauthorized access denied")
  } else {
    precondition(status == errSecSuccess)
    precondition(value as? Data == Data("fictional-fixture-only".utf8))
    print("Fictional item read without authorization UI")
  }
}
