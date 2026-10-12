import Foundation

@objc public protocol CredentialServiceProtocol {
  func load(withReply reply: @escaping (Data?, Int32) -> Void)
  func save(_ data: Data, withReply reply: @escaping (Int32) -> Void)
  func remove(withReply reply: @escaping (Int32) -> Void)
}

public enum CredentialServiceIdentity {
  public static let name = "io.github.calendar-bar.credentials-service"
  public static func requirement(identifier: String) -> String {
    "identifier \"\(identifier)\" and certificate leaf = H\"a8ecbdb4c6955c102dbb9cecfd67371abd5e25af\""
  }
}
