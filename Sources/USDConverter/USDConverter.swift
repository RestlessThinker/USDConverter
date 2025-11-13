//
//  USDConverter.swift
//  USDConverter
//
//  Created by Emma Alyx Wunder on 11.06.19.
//  Updated for Swift Package support in 2024 by the USDConverter maintainers.
//

import Foundation
import Dispatch
import ModelIO
import SceneKit
import SceneKit.ModelIO

public struct ConversionOptions {
	public var convertTexturesToPNG: Bool
	public var allowUnsupportedFormats: Bool
	public var includeModelIOIntermediates: Bool
	public var outputDirectory: URL?
	public var logHandler: ((String) -> Void)?

	public init(
		convertTexturesToPNG: Bool = false,
		allowUnsupportedFormats: Bool = false,
		includeModelIOIntermediates: Bool = false,
		outputDirectory: URL? = nil,
		logHandler: ((String) -> Void)? = nil
	) {
		self.convertTexturesToPNG = convertTexturesToPNG
		self.allowUnsupportedFormats = allowUnsupportedFormats
		self.includeModelIOIntermediates = includeModelIOIntermediates
		self.outputDirectory = outputDirectory
		self.logHandler = logHandler
	}
}

public struct ConversionArtifacts {
	public let objFile: URL
	public let mtlFile: URL
	public let textureFiles: [URL]
	public let duplicatesReport: URL?
}

public struct ConversionResult {
	public let source: URL
	public let artifacts: ConversionArtifacts?
	public let error: ConverterError?

	public var isSuccess: Bool { self.error == nil }
}

public enum ConverterError: Error {
	case fileMissing(URL)
	case invalidOutputDirectory(URL)
	case unsupportedInput(URL)
	case modelIOCannotImport(URL)
	case invalidSceneKitFile(URL)
	case exportFailed(URL, underlying: Error)
	case garbageReadFailed(URL, underlying: Error)
	case modelFileCreationFailed(URL)
	case objRewriteFailed(URL, underlying: Error)
	case mtlWriteFailed(URL, underlying: Error)
	case duplicateListWriteFailed(URL, underlying: Error)
	case textureExtractionUnsupported
	case textureExtractionFailed(URL, underlying: Error)
	case garbageCleanupFailed([URL], underlying: Error)
}

public struct USDConverter {

	public static let version = "1.7"

	private let fileManager: FileManager
	private let conversionQueue: DispatchQueue
	private let customConvert: ((URL, ConversionOptions) -> ConversionResult)?

	public init(fileManager: FileManager = .default) {
		self.init(
			fileManager: fileManager,
			conversionQueue: DispatchQueue(
				label: "com.captureforge.usdconverter.convert",
				qos: .userInitiated
			),
			customConvert: nil
		)
	}

	internal init(
		fileManager: FileManager,
		conversionQueue: DispatchQueue,
		customConvert: ((URL, ConversionOptions) -> ConversionResult)?
	) {
		self.fileManager = fileManager
		self.conversionQueue = conversionQueue
		self.customConvert = customConvert
	}

	@available(macOS 10.15, iOS 15, *)
	public func convert(inputs: [URL], options: ConversionOptions = ConversionOptions()) async -> [ConversionResult] {
		// Serialize conversion work to avoid concurrent SceneKit/ModelIO access, which is not thread safe.
		return await withCheckedContinuation { continuation in
			self.conversionQueue.async {
				let results = inputs.map { input -> ConversionResult in
					if let customConvert = self.customConvert {
						return customConvert(input, options)
					}
					return self.convertSingle(input: input, options: options)
				}
				continuation.resume(returning: results)
			}
		}
	}

	private func convertSingle(input: URL, options: ConversionOptions) -> ConversionResult {
		let log = options.logHandler ?? { _ in }

		guard self.fileManager.fileExists(atPath: input.path) else {
			return ConversionResult(source: input, artifacts: nil, error: .fileMissing(input))
		}

		let modelExt = input.pathExtension.lowercased()
		let fileIsSceneKit = modelExt == "scn" || modelExt == "scnz"
		let fileIsUSDZ = modelExt == "usdz"

		if !fileIsUSDZ && !fileIsSceneKit && !options.allowUnsupportedFormats {
			return ConversionResult(source: input, artifacts: nil, error: .unsupportedInput(input))
		}

		let modelIsImportable = MDLAsset.canImportFileExtension(modelExt)
		if !modelIsImportable && !fileIsSceneKit {
			return ConversionResult(source: input, artifacts: nil, error: .modelIOCannotImport(input))
		}

		let outputDirectory: URL
		do {
			outputDirectory = try self.resolveOutputDirectory(for: input, options: options)
		} catch let converterError as ConverterError {
			return ConversionResult(source: input, artifacts: nil, error: converterError)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .invalidOutputDirectory(input))
		}

		let modelBase = input.deletingPathExtension().lastPathComponent

		let modelObjURL = outputDirectory.appendingPathComponent("\(modelBase).obj", isDirectory: false)
		let modelMtlURL = outputDirectory.appendingPathComponent("\(modelBase).mtl", isDirectory: false)
		let garbageObjURL = outputDirectory.appendingPathComponent("\(modelBase)_ModelIO.obj", isDirectory: false)
		let garbageMtlURL = outputDirectory.appendingPathComponent("\(modelBase)_ModelIO.mtl", isDirectory: false)
		let duplicatesURL = outputDirectory.appendingPathComponent("\(modelBase)_duplicates.txt", isDirectory: false)

		do {
			try self.ensureParentDirectoryExists(for: modelObjURL)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .invalidOutputDirectory(outputDirectory))
		}

		let asset: MDLAsset
		do {
			asset = try self.loadAsset(from: input, isSceneKit: fileIsSceneKit)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .invalidSceneKitFile(input))
		}

		if asset.frameInterval != 0 && (asset.endTime - asset.startTime) > 0.05 {
			log("NOTE: \(input.lastPathComponent) contains animation data that will be discarded when exporting to OBJ.")
		}

		do {
			try asset.export(to: garbageObjURL)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .exportFailed(input, underlying: error))
		}

		guard modelIsImportable || fileIsSceneKit else {
			return ConversionResult(source: input, artifacts: nil, error: .modelIOCannotImport(input))
		}

		guard let modelFile = try? ModelFile(modelFile: input, logger: log) else {
			return ConversionResult(source: input, artifacts: nil, error: .modelFileCreationFailed(input))
		}

		let materialCountDict = Dictionary(grouping: modelFile.materials, by: { $0 })
		let sortedMaterialCount = materialCountDict.sorted(by: { $0.value.count > $1.value.count })

		let duplicatesList = self.renderDuplicateList(for: input, distinctMaterials: sortedMaterialCount)

		let objContents: String
		do {
			objContents = try String(contentsOf: garbageObjURL, encoding: .utf8)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .garbageReadFailed(garbageObjURL, underlying: error))
		}

		var usedMaterials: [ModelMaterial] = []
		var newObjLines: [String] = []
		objContents.enumerateLines { line, _ in
			if line.starts(with: "mtllib") {
				newObjLines.append("mtllib \(modelMtlURL.lastPathComponent)")
				return
			} else if line.starts(with: "# Apple ModelIO OBJ File") {
				newObjLines.append("# USDConverter OBJ File: \(modelObjURL.deletingPathExtension().lastPathComponent).obj")
				return
			}

			guard line.starts(with: "usemtl ") else {
				newObjLines.append(line)
				return
			}

			let matName = String(line.dropFirst("usemtl ".count))
			guard let match = materialCountDict.first(where: { entry in
				entry.value.map(\.name).contains(matName)
			}) else {
				return
			}

			usedMaterials.append(match.key)
			newObjLines.append("usemtl \(match.key.simpleName)")
		}

		usedMaterials = Array(Set(usedMaterials)).sorted {
			$0.simpleName.localizedStandardCompare($1.simpleName) == .orderedAscending
		}

		do {
			try newObjLines.joined(separator: "\n").write(to: modelObjURL, atomically: true, encoding: .utf8)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .objRewriteFailed(modelObjURL, underlying: error))
		}

		let mtlContents = modelFile.generateMTL(options.convertTexturesToPNG, usedMaterials: usedMaterials)
		do {
			try mtlContents.write(to: modelMtlURL, atomically: true, encoding: .utf8)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .mtlWriteFailed(modelMtlURL, underlying: error))
		}

		var duplicatesReportURL: URL?
		if options.includeModelIOIntermediates {
			do {
				try duplicatesList.write(to: duplicatesURL, atomically: true, encoding: .utf8)
				duplicatesReportURL = duplicatesURL
			} catch {
				return ConversionResult(source: input, artifacts: nil, error: .duplicateListWriteFailed(duplicatesURL, underlying: error))
			}
		}

		let textureURLs: [URL]
		do {
			textureURLs = try modelFile.extractTextures(
				options.convertTexturesToPNG,
				outputDirectory: outputDirectory,
				fileManager: self.fileManager,
				logger: log
			)
		} catch {
			return ConversionResult(source: input, artifacts: nil, error: .textureExtractionFailed(outputDirectory, underlying: error))
		}

		if !options.includeModelIOIntermediates {
			do {
				if self.fileManager.fileExists(atPath: garbageObjURL.path) {
					try self.fileManager.removeItem(at: garbageObjURL)
				}
				if self.fileManager.fileExists(atPath: garbageMtlURL.path) {
					try self.fileManager.removeItem(at: garbageMtlURL)
				}
			} catch {
				return ConversionResult(
					source: input,
					artifacts: nil,
					error: .garbageCleanupFailed([garbageObjURL, garbageMtlURL], underlying: error)
				)
			}
		}

		return ConversionResult(
			source: input,
			artifacts: ConversionArtifacts(
				objFile: modelObjURL,
				mtlFile: modelMtlURL,
				textureFiles: textureURLs,
				duplicatesReport: duplicatesReportURL
			),
			error: nil
		)
	}

	private func resolveOutputDirectory(for input: URL, options: ConversionOptions) throws -> URL {
		if let provided = options.outputDirectory {
			try self.ensureDirectoryExists(at: provided)
			return provided
		}

		if let documents = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
			try self.ensureDirectoryExists(at: documents)
			return documents
		}

		let fallback = input.deletingLastPathComponent()
		try self.ensureDirectoryExists(at: fallback)
		return fallback
	}

	private func ensureDirectoryExists(at url: URL) throws {
		var isDir: ObjCBool = false
		if self.fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
			if !isDir.boolValue {
				throw ConverterError.invalidOutputDirectory(url)
			}
			return
		}

		try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
	}

	private func ensureParentDirectoryExists(for fileURL: URL) throws {
		let parent = fileURL.deletingLastPathComponent()
		try self.ensureDirectoryExists(at: parent)
	}

	private func loadAsset(from url: URL, isSceneKit: Bool) throws -> MDLAsset {
		if isSceneKit {
			let scene = try SCNScene(url: url, options: nil)
			return MDLAsset(scnScene: scene)
		} else {
			return MDLAsset(url: url)
		}
	}

	private func renderDuplicateList(for input: URL, distinctMaterials: [(key: ModelMaterial, value: [ModelMaterial])]) -> String {
		var auxString = "# USDConverter List Of Duplicate Materials: \(input.deletingPathExtension().lastPathComponent).obj\n"
		auxString.append("\(distinctMaterials.count) distinct materials in total\n\n")

		for entry in distinctMaterials {
			let occurrenceStr = entry.value.count == 1 ? "occurrence" : "occurrences"
			auxString.append("\(entry.key.name): \(entry.value.count) \(occurrenceStr)\n")
		}

		return auxString.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

extension ConverterError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .fileMissing(let url):
			return "Input file not found: \(url.path)"
		case .invalidOutputDirectory(let url):
			return "Output path is not a directory or cannot be created: \(url.path)"
		case .unsupportedInput(let url):
			return "Unsupported input file type: \(url.path)"
		case .modelIOCannotImport(let url):
			return "Model I/O cannot import files of type \(url.pathExtension.uppercased()) (\(url.lastPathComponent))"
		case .invalidSceneKitFile(let url):
			return "SceneKit could not open scene: \(url.path)"
		case .exportFailed(let url, let underlying):
			return "Failed to export \(url.lastPathComponent): \(underlying.localizedDescription)"
		case .garbageReadFailed(let url, let underlying):
			return "Failed to read intermediate Model I/O output at \(url.path): \(underlying.localizedDescription)"
		case .modelFileCreationFailed(let url):
			return "Failed to read materials from \(url.lastPathComponent)"
		case .objRewriteFailed(let url, let underlying):
			return "Failed to write OBJ file (\(url.path)): \(underlying.localizedDescription)"
		case .mtlWriteFailed(let url, let underlying):
			return "Failed to write MTL file (\(url.path)): \(underlying.localizedDescription)"
		case .duplicateListWriteFailed(let url, let underlying):
			return "Failed to write duplicate material summary (\(url.path)): \(underlying.localizedDescription)"
		case .textureExtractionUnsupported:
			return "Texture extraction is unavailable on this platform"
		case .textureExtractionFailed(_, let underlying):
			return "Failed to extract textures: \(underlying.localizedDescription)"
		case .garbageCleanupFailed(let urls, let underlying):
			let list = urls.map { $0.lastPathComponent }.joined(separator: ", ")
			return "Failed to clean up Model I/O intermediates (\(list)): \(underlying.localizedDescription)"
		}
	}
}
