import Foundation
import Security

enum KeychainAccess {
  static func isOfficialRelease() -> Bool {
    let fingerprint = "a8ecbdb4c6955c102dbb9cecfd67371abd5e25af"
    let expression = "identifier \"io.github.calendar-bar\" and certificate leaf = H\"\(fingerprint)\""
    var requirement: SecRequirement?
    var code: SecCode?
    let flags = SecCSFlags(rawValue: 0)
    guard SecRequirementCreateWithString(expression as CFString, flags, &requirement) == errSecSuccess,
      SecCodeCopySelf(flags, &code) == errSecSuccess, let code, let requirement
    else { return false }
    return SecCodeCheckValidity(code, flags, requirement) == errSecSuccess
  }

  static func restrictedToCurrentApp() throws -> SecAccess {
    var application: SecTrustedApplication?
    try check(SecTrustedApplicationCreateFromPath(nil, &application))
    guard let application else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecParam)) }
    var access: SecAccess?
    try check(SecAccessCreate("Calendar Bar" as CFString, [application] as CFArray, &access))
    guard let access else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecParam)) }
    return access
  }

  static func migrate(_ item: SecKeychainItem) throws -> Bool {
    guard isOfficialRelease() else { return false }
    var existing: SecAccess?
    try check(SecKeychainItemCopyAccess(item, &existing))
    guard let existing else { return false }
    var entries: CFArray?
    try check(SecAccessCopyACLList(existing, &entries))
    let hasBinaryPartition = (entries as? [SecACL] ?? []).contains { entry in
      (SecACLCopyAuthorizations(entry) as? [String] ?? []).contains(kSecACLAuthorizationPartitionID as String)
    }
    guard hasBinaryPartition else { return false }
    // Legacy per-binary partitions reject updates even when the certificate requirement matches.
    try check(SecKeychainItemSetAccess(item, restrictedToCurrentApp()))
    return true
  }

  private static func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
  }
}
