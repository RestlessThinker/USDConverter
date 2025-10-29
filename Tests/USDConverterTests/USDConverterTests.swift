import XCTest
@testable import USDConverter

final class USDConverterTests: XCTestCase {
    func testConvertWithNoInputsReturnsNoResults() {
        let converter = USDConverter()
        let results = converter.convert(inputs: [])
        XCTAssertTrue(results.isEmpty)
    }
}
