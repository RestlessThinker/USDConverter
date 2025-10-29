//
//  main.swift
//  USDConverterCLI
//
//  Created by Emma Alyx Wunder on 27.11.21.
//  Updated for Swift Package support in 2024 by the USDConverter maintainers.
//

import Foundation
import ArgumentParser
import USDConverter

struct USDConverterCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "usdconv",
        abstract: "USDConverter v\(USDConverter.version)",
        discussion: "Convert USDZ or SceneKit files into OBJ/MTL output."
    )

    @Flag(name: .shortAndLong, help: "Show the version number and exit.")
    var version: Bool = false

    @Flag(name: .long, help: "Convert all texture formats to PNG.")
    var png: Bool = false

    @Flag(name: .long, help: "Allow unsupported input formats (best effort).")
    var force: Bool = false

    @Flag(name: .long, help: "Keep Model I/O intermediate files for inspection.")
    var includeGarbage: Bool = false

    @Option(name: .shortAndLong, help: "Directory to write generated files to. Defaults to the user's Documents directory or the source file directory.", completion: .directory)
    var outputDirectory: String?

    @Argument(help: "Input USDZ/SCN files to convert.", completion: .file())
    var input: [String] = []

    mutating func run() throws {
        guard !version else {
            print("USDConverter v\(USDConverter.version)")
            return
        }

        guard !input.isEmpty else {
            throw ValidationError("Specify at least one input file to convert.")
        }

        let converter = USDConverter()
        let inputs = input.map { URL(fileURLWithPath: $0) }
        let outputURL = outputDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }

        let options = ConversionOptions(
            convertTexturesToPNG: png,
            allowUnsupportedFormats: force,
            includeModelIOIntermediates: includeGarbage,
            outputDirectory: outputURL,
            logHandler: { message in print(message) }
        )

        let results = converter.convert(inputs: inputs, options: options)

        var failures: [ConversionResult] = []
        for result in results {
            if result.isSuccess, let artifacts = result.artifacts {
                print("Converted \(result.source.lastPathComponent) → \(artifacts.objFile.lastPathComponent)")
            } else {
                failures.append(result)
            }
        }

        guard failures.isEmpty else {
            for failure in failures {
                if let error = failure.error {
                    print("Error processing \(failure.source.path): \(error.localizedDescription)")
                }
            }
            throw ExitCode.failure
        }
    }
}

USDConverterCommand.main()
