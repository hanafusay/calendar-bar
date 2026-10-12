// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CalendarBar", platforms: [.macOS(.v13)],
  products: [.executable(name: "CalendarBar", targets: ["CalendarBar"])],
  targets: [
    .target(name: "CalendarCore"),
    .target(name: "CredentialProtocol"),
    .executableTarget(name: "CalendarBar", dependencies: ["CalendarCore", "CredentialProtocol"]),
    .executableTarget(name: "CalendarCredentials", dependencies: ["CredentialProtocol"]),
    .executableTarget(
      name: "CalendarChecks", dependencies: ["CalendarCore"], path: "Tests/CalendarCoreTests"),
  ])
