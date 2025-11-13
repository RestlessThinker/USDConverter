import XCTest
import Foundation
import Dispatch
@testable import USDConverter

final class USDConverterTests: XCTestCase {
	func testConvertWithNoInputsReturnsNoResults() async throws {
		let converter = USDConverter()
		let results = await converter.convert(inputs: [])
		XCTAssertTrue(results.isEmpty)
	}

	func testConcurrentConvertCallsAreSerialized() async throws {
		let tracker = ConcurrencyTracker()
		let converter = USDConverter(
			fileManager: .default,
			conversionQueue: DispatchQueue(label: "com.captureforge.usdconverter.tests"),
			customConvert: { url, _ in
				tracker.didStart()
				defer { tracker.didFinish() }
				Thread.sleep(forTimeInterval: 0.05)
				return ConversionResult(source: url, artifacts: nil, error: .fileMissing(url))
			}
		)

		let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/usdconverter_test_\($0).usdz") }

		async let first = converter.convert(inputs: [urls[0]])
		async let second = converter.convert(inputs: [urls[1]])
		async let third = converter.convert(inputs: [urls[2]])

		_ = await (first, second, third)

		XCTAssertEqual(tracker.maxConcurrentOperations, 1, "Conversion work should be serialized to avoid concurrency crashes.")
	}
}

private final class ConcurrencyTracker {
	private let lock = NSLock()
	private var currentOperations = 0
	private(set) var maxConcurrentOperations = 0

	func didStart() {
		lock.lock()
		defer { lock.unlock() }
		currentOperations += 1
		maxConcurrentOperations = max(maxConcurrentOperations, currentOperations)
	}

	func didFinish() {
		lock.lock()
		defer { lock.unlock() }
		currentOperations -= 1
	}
}
