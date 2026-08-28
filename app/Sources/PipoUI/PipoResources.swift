import Foundation

enum PipoResources {
    private static let bundleName = "Pipo_PipoUI.bundle"

    static var bundleURL: URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        var searchRoots = [Bundle.main.bundleURL]
        if let resourceURL = Bundle.main.resourceURL { searchRoots.append(resourceURL) }
        if let executableURL = Bundle.main.executableURL {
            searchRoots.append(executableURL.deletingLastPathComponent())
        }
        for root in searchRoots {
            var directory = root
            for _ in 0..<5 {
                candidates.append(directory.appendingPathComponent(bundleName, isDirectory: true))
                directory.deleteLastPathComponent()
            }
        }

        if let packaged = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return packaged
        }

        var packageRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { packageRoot.deleteLastPathComponent() }
        let developmentRoots = [
            packageRoot.appendingPathComponent(".build", isDirectory: true),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(".build", isDirectory: true),
        ]
        for root in developmentRoots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.lastPathComponent == bundleName {
                return url
            }
        }
        return nil
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
