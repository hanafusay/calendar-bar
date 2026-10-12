import CredentialProtocol
import Foundation
import Security

final class CredentialService: NSObject, CredentialServiceProtocol, NSXPCListenerDelegate {
  private let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "io.github.calendar-bar.credentials",
    kSecAttrAccount as String: "google",
  ]

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.setCodeSigningRequirement(CredentialServiceIdentity.requirement(identifier: "io.github.calendar-bar"))
    connection.exportedInterface = NSXPCInterface(with: CredentialServiceProtocol.self)
    connection.exportedObject = self
    connection.resume()
    return true
  }

  func load(withReply reply: @escaping (Data?, Int32) -> Void) {
    var lookup = query
    lookup[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    reply(result as? Data, status)
  }

  func save(_ data: Data, withReply reply: @escaping (Int32) -> Void) {
    guard data.count <= 65536,
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let identifier = value["clientID"] as? String,
      identifier.hasSuffix(".apps.googleusercontent.com")
    else { reply(errSecParam); return }
    let updates = [kSecValueData as String: data]
    var status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
    if status == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(add as CFDictionary, nil)
    }
    reply(status)
  }

  func remove(withReply reply: @escaping (Int32) -> Void) {
    let status = SecItemDelete(query as CFDictionary)
    reply(status == errSecItemNotFound ? errSecSuccess : status)
  }
}

let listener = NSXPCListener.service()
let service = CredentialService()
listener.delegate = service
listener.resume()
