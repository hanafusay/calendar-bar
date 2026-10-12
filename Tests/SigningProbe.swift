import CredentialProtocol
import Foundation
import Security
import Darwin
setbuf(stdout, nil)
#if UPDATE
print("Updated application")
#else
print("Initial application")
#endif
let arguments = CommandLine.arguments
let value = Data(#"{"clientID":"fictional.apps.googleusercontent.com","refreshToken":"fictional-fixture-only"}"#.utf8)
if arguments[1] == "create-legacy" {
  var keychain: SecKeychain?
  precondition(SecKeychainOpen(arguments[2], &keychain) == errSecSuccess)
  var current: SecTrustedApplication?
  var helper: SecTrustedApplication?
  precondition(SecTrustedApplicationCreateFromPath(nil, &current) == errSecSuccess)
  precondition(SecTrustedApplicationCreateFromPath(arguments[3], &helper) == errSecSuccess)
  var access: SecAccess?
  precondition(SecAccessCreate("Fictional credential fixture" as CFString, [current!, helper!] as CFArray, &access) == errSecSuccess)
  let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "io.github.calendar-bar.credentials", kSecAttrAccount as String: "google",
    kSecUseKeychain as String: keychain!, kSecAttrAccess as String: access!, kSecValueData as String: value]
  precondition(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
  print("Created fictional legacy credential with its helper authorized")
  exit(0)
}
let connection = NSXPCConnection(serviceName: CredentialServiceIdentity.name)
connection.remoteObjectInterface = NSXPCInterface(with: CredentialServiceProtocol.self)
connection.setCodeSigningRequirement(CredentialServiceIdentity.requirement(identifier: CredentialServiceIdentity.name))
connection.resume()
var transportFailed = false
let service = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in transportFailed = true } as! CredentialServiceProtocol
var status: Int32 = errSecNotAvailable
var received: Data?
let replacement = Data(#"{"clientID":"fictional.apps.googleusercontent.com","refreshToken":"fictional-reconnected"}"#.utf8)
let denied = arguments[1].hasPrefix("deny-")
switch arguments[1] {
case "save-initial": service.save(value) { status = $0 }
case "save", "deny-save": service.save(replacement) { status = $0 }
case "remove", "deny-remove": service.remove { status = $0 }
default: service.load { received = $0; status = $1 }
}
connection.invalidate()
if denied {
  precondition(transportFailed && received == nil, "Forged caller reached credential service")
  print("Forged request denied before credential access")
} else {
  if arguments[1] == "missing" { precondition(status == errSecItemNotFound); exit(0) }
  precondition(!transportFailed && status == errSecSuccess, "Credential service failed: \(status)")
  if arguments[1] == "read" { precondition(received == value) }
  if arguments[1] == "read-updated" { precondition(received == replacement) }
  print("Credential service request succeeded")
}
