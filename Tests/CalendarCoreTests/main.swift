import Foundation

func XCTAssertEqual<T: Equatable>(
  _ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line
) {
  precondition(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
  precondition(value, "Expected true", file: file, line: line)
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
  precondition(value == nil, "Expected nil", file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
  precondition(value != nil, "Expected value", file: file, line: line)
}
func XCTAssertThrowsError<T>(
  _ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line
) {
  do {
    _ = try expression()
    preconditionFailure("Expected error", file: file, line: line)
  } catch {}
}
let tests = AgendaTests()
try tests.testBoundaryAndCompleted()
try tests.testFiltersAndMidnight()
try tests.testOrderingCountdownAndFullTitle()
try tests.testTimezoneAndLinkValidation()
try tests.testCallbackSecurity()
try tests.testCredentialImportAndForm()
Task {
  do {
    try await APITests().testPaginationUsesNativeGoogleEndpointsAndBearer()
    try await APITests().testFailedAuthorizationAndRepeatedPageToken()
    print("8 behavior checks passed.")
    exit(0)
  } catch {
    fputs("API behavior check failed.\n", stderr)
    exit(1)
  }
}
dispatchMain()
