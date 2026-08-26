import Foundation

enum PipoResources {
    private static let bundleName = "Pipo_PipoUI.bundle"

    static var bundleURL: URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true))
        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL.deletingLastPathComponent()
                    .appendingPathComponent(bundleName, isDirectory: true)
            )
        }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    static func url(
        forResource name: String,
        withExtension fileExtension: String? = nil,
        subdirectory: String? = nil
    ) -> URL? {
        guard var url = bundleURL else { return nil }
        if let subdirectory {
            url.appendPathComponent(subdirectory, isDirectory: true)
        }
        url.appendPathComponent(name)
        if let fileExtension {
            url.appendPathExtension(fileExtension)
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
