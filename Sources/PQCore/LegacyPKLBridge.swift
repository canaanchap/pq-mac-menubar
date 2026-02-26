import Foundation

public enum LegacyPKLError: Error {
    case converterMissing
    case failed(Int32)
}

public final class LegacyPKLBridge {
    private let converterPath: URL

    public init(converterPath: URL) {
        self.converterPath = converterPath
    }

    public func importPKL(from input: URL, to outputJSON: URL) throws {
        try run(mode: "import", input: input, output: outputJSON)
    }

    public func exportPKL(from inputJSON: URL, to outputPKL: URL) throws {
        try run(mode: "export", input: inputJSON, output: outputPKL)
    }

    private func run(mode: String, input: URL, output: URL) throws {
        guard FileManager.default.fileExists(atPath: converterPath.path) else {
            throw LegacyPKLError.converterMissing
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", converterPath.path, mode, input.path, output.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw LegacyPKLError.failed(process.terminationStatus)
        }
    }
}
