//
//  ModelFile.swift
//  USDConverter
//
//  Created by Emma Alyx Wunder on 10.12.19.
//  Copyright © 2019 Emma Alyx Wunder.
//

import Foundation
import ImageIO
import ModelIO
#if canImport(MobileCoreServices)
import MobileCoreServices
#elseif canImport(CoreServices)
import CoreServices
#endif

final class ModelFile {

	let file: URL
	var materials: [ModelMaterial]

	private let asset: MDLAsset
	private let logger: ((String) -> Void)?

	init(modelFile: URL, logger: ((String) -> Void)? = nil) throws {
		self.file = modelFile
		self.materials = []
		self.logger = logger

		self.asset = MDLAsset(url: self.file)
		self.asset.loadTextures()

		var childIndex = 1
		for obj in self.asset.childObjects(of: MDLMesh.self) {
			guard let mesh = obj as? MDLMesh else {
				logger?("Skipping unexpected non-mesh child when reading \(modelFile.lastPathComponent)")
				continue
			}

			for rawSubmesh in mesh.submeshes ?? [] {
				guard let submesh = rawSubmesh as? MDLSubmesh else {
					logger?("Skipping unexpected non-submesh entry in \(modelFile.lastPathComponent)")
					continue
				}

				guard let material = submesh.material else {
					continue
				}

				let materialName = "material_\(childIndex)"
				childIndex += 1

				let mtlMaterial = ModelMaterial(simpleName: materialName, originalMaterial: material, assetURL: self.file)
				self.materials.append(mtlMaterial)
			}
		}
	}

	func generateMTL(_ convertToPNG: Bool, usedMaterials: [ModelMaterial]) -> String {
		var mtlString = "# USDConverter MTL File: \(self.file.deletingPathExtension().lastPathComponent).mtl\n\n"

		for material in usedMaterials {
			mtlString.append(material.generateMTL(includeMaterialName: true, convertToPNG: convertToPNG) + "\n\n")
		}

		return mtlString.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func extractTextures(_ convertToPNG: Bool, outputDirectory: URL, fileManager: FileManager, logger: ((String) -> Void)?) throws -> [URL] {
		var alreadySaved: [URL] = []
		var savedTextures: [URL] = []

		for material in self.materials {
			for semantic in ModelMaterial.allSemantics {
				guard let materialProp = material.get(semantic),
					  let texturePath = materialProp.stringValue,
					  let textureSampler = materialProp.textureSamplerValue else {
					continue
				}

				let texturePathParsed = ModelMaterial.parseTexturePath(texturePath)
				var urlComponents = URL(fileURLWithPath: texturePathParsed).pathComponents

				guard let textureFileName = urlComponents.popLast(),
					  let textureOutDir = urlComponents.popLast() else {
					logger?("Skipping texture with unexpected path: \(texturePathParsed)")
					continue
				}

				let textureDirectoryURL = outputDirectory.appendingPathComponent(textureOutDir, isDirectory: true)
				var textureURL = textureDirectoryURL.appendingPathComponent(textureFileName, isDirectory: false)

				guard let texture = textureSampler.texture else {
					continue
				}

				guard let cgImage = texture.imageFromTexture()?.takeRetainedValue() else {
					logger?("Failed to create CGImage from texture \(textureFileName)")
					continue
				}

				let destination = self.destinationInfo(for: textureURL, convertToPNG: convertToPNG)
				textureURL = destination.url

				guard !alreadySaved.contains(textureURL) else {
					continue
				}

				try fileManager.createDirectory(
					at: textureURL.deletingLastPathComponent(),
					withIntermediateDirectories: true
				)

				guard let imageDestination = CGImageDestinationCreateWithURL(
					textureURL as CFURL,
					destination.type,
					1,
					nil
				) else {
					logger?("Failed to create image destination for \(textureURL.lastPathComponent)")
					continue
				}

				CGImageDestinationAddImage(imageDestination, cgImage, destination.options)

				guard CGImageDestinationFinalize(imageDestination) else {
					logger?("Failed to write image data for \(textureURL.lastPathComponent)")
					continue
				}

				alreadySaved.append(textureURL)
				savedTextures.append(textureURL)
			}
		}

		return savedTextures
	}

	private func destinationInfo(for url: URL, convertToPNG: Bool) -> (type: CFString, url: URL, options: CFDictionary?) {
		var outputURL = url
		var type: CFString = kUTTypePNG
		var options: CFDictionary? = nil

		if convertToPNG {
			outputURL = url.deletingPathExtension().appendingPathExtension("png")
		} else {
			switch url.pathExtension.lowercased() {
			case "png":
				type = kUTTypePNG
			case "jpg", "jpeg":
				type = kUTTypeJPEG
				options = [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary
			default:
				type = kUTTypePNG
			}
		}

		return (type, outputURL, options)
	}

}
