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

	func testTruckConversionProducesArtifacts() async throws {
		let truckURL = try fixtureURL(named: "truck", fileExtension: "usdz")
		let outputDirectory = try makeTemporaryOutputDirectory(named: "truck-conversion")
		defer { try? FileManager.default.removeItem(at: outputDirectory) }

		let converter = makeStubbedConverter()
		let options = ConversionOptions(outputDirectory: outputDirectory)
		let results = await converter.convert(inputs: [truckURL], options: options)

		guard let result = results.first else {
			XCTFail("No conversion result returned")
			return
		}

		XCTAssertNil(result.error, "Conversion failed: \(String(describing: result.error))")

		let artifacts = try XCTUnwrap(result.artifacts, "Conversion did not produce artifacts")
		XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.objFile.path), ".obj file missing for truck.usdz")
		XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.mtlFile.path), ".mtl file missing for truck.usdz")
	}

	func testConcurrentConvertCallsAreSerialized() async throws {
		let tracker = ConcurrencyTracker()
		let truckURL = try fixtureURL(named: "truck", fileExtension: "usdz")

		let outputDirs = try (0..<3).map { try makeTemporaryOutputDirectory(named: "truck-concurrency-\($0)") }
		defer {
			for dir in outputDirs {
				try? FileManager.default.removeItem(at: dir)
			}
		}

		let converter = makeStubbedConverter(tracker: tracker, workDelay: 0.05)

		let urls = Array(repeating: truckURL, count: 3)

		async let first = converter.convert(inputs: [urls[0]], options: ConversionOptions(outputDirectory: outputDirs[0]))
		async let second = converter.convert(inputs: [urls[1]], options: ConversionOptions(outputDirectory: outputDirs[1]))
		async let third = converter.convert(inputs: [urls[2]], options: ConversionOptions(outputDirectory: outputDirs[2]))

		let (firstResults, secondResults, thirdResults) = await (first, second, third)
		let allResults = firstResults + secondResults + thirdResults

		XCTAssertEqual(tracker.maxConcurrentOperations, 1, "Conversion work should be serialized to avoid concurrency crashes.")

		for (index, result) in allResults.enumerated() {
			let artifacts = try XCTUnwrap(result.artifacts, "Missing artifacts for concurrent run \(index)")
			XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.objFile.path), "Concurrent run \(index) missing .obj file")
			XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.mtlFile.path), "Concurrent run \(index) missing .mtl file")
		}
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

private func makeStubbedConverter(
	tracker: ConcurrencyTracker? = nil,
	workDelay: TimeInterval = 0
) -> USDConverter {
	return USDConverter(
		fileManager: .default,
		conversionQueue: DispatchQueue(label: "com.captureforge.usdconverter.tests.stub"),
		customConvert: { url, options in
			tracker?.didStart()
			defer { tracker?.didFinish() }

			if workDelay > 0 {
				Thread.sleep(forTimeInterval: workDelay)
			}

			let baseDirectory: URL = {
				if let provided = options.outputDirectory {
					return provided
				}

				let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
					"USDConverterTests-\(UUID().uuidString)",
					isDirectory: true
				)
				do {
					try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
				} catch {
					preconditionFailure("Failed to create temporary directory: \(error)")
				}
				return tempDirectory
			}()

			let baseName = url.deletingPathExtension().lastPathComponent
			let objURL = baseDirectory.appendingPathComponent(baseName).appendingPathExtension("obj")
			let mtlURL = baseDirectory.appendingPathComponent(baseName).appendingPathExtension("mtl")

			do {
				try "o \(baseName)Mesh".write(to: objURL, atomically: true, encoding: .utf8)
				try "newmtl \(baseName)Material".write(to: mtlURL, atomically: true, encoding: .utf8)
			} catch {
				preconditionFailure("Failed to write stub artifacts: \(error)")
			}

			return ConversionResult(
				source: url,
				artifacts: ConversionArtifacts(
					objFile: objURL,
					mtlFile: mtlURL,
					textureFiles: [],
					duplicatesReport: nil
				),
				error: nil
			)
		}
	)
}

private func fixtureURL(named name: String, fileExtension ext: String) throws -> URL {
	return try XCTUnwrap(
		Bundle.module.url(forResource: name, withExtension: ext),
		"Missing fixture \(name).\(ext)"
	)
}

private func makeTemporaryOutputDirectory(named name: String) throws -> URL {
	let base = FileManager.default.temporaryDirectory
	let directory = base.appendingPathComponent("USDConverterTests-\(name)-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	return directory
}
