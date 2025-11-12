import XCTest
@testable import USDConverter

final class USDConverterTests: XCTestCase {
    func testConvertWithNoInputsReturnsNoResults() async throws {
        let converter = USDConverter()
        let results = await converter.convert(inputs: [])
        XCTAssertTrue(results.isEmpty)
    }
}
