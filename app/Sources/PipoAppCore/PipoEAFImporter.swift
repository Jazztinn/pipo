import Foundation
import ImageIO
import UniformTypeIdentifiers

#if canImport(PDFKit)
  import PDFKit
#endif
#if canImport(Vision)
  import Vision
#endif

public enum PipoEAFImportError: LocalizedError, Sendable {
  case unsupportedType, fileTooLarge, tooManyPages, cancelled, unreadable
  public var errorDescription: String? {
    switch self {
    case .unsupportedType: return "Use a PDF, PNG, JPEG, or HEIC schedule file."
    case .fileTooLarge: return "Schedule file must be 20 MiB or smaller."
    case .tooManyPages: return "Schedule PDF must have 10 pages or fewer."
    case .cancelled: return "Schedule import was cancelled."
    case .unreadable: return "Schedule file could not be read."
    }
  }
}

public struct PipoEAFSourcePreview: Sendable {
  public var data: Data
  public var images: [Data]
  public init(data: Data, images: [Data] = []) {
    self.data = data
    self.images = images
  }
}
public struct PipoEAFImportResult: Sendable {
  public var parsed: ScheduleParseResult
  public var preview: PipoEAFSourcePreview
  public init(parsed: ScheduleParseResult, preview: PipoEAFSourcePreview) {
    self.parsed = parsed
    self.preview = preview
  }
}

public enum PipoEAFImporter {
  // A cancelled Vision request may take time to return. Keep the next document
  // queued until it does, so OCR buffers never overlap across imports.
  private actor ImportWorker {
    func extract(_ url: URL) throws -> PipoEAFImportResult { try importBlocking(url) }
  }
  private static let importWorker = ImportWorker()

  public static func importDocument(at url: URL) async throws -> PipoEAFImportResult {
    let worker = Task.detached(priority: .userInitiated) { try await importWorker.extract(url) }
    return try await withTaskCancellationHandler(
      operation: {
        do { return try await worker.value } catch is CancellationError {
          throw PipoEAFImportError.cancelled
        }
      }, onCancel: { worker.cancel() })
  }

  private static func importBlocking(_ url: URL) throws -> PipoEAFImportResult {
    try checkCancellation()
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else { throw PipoEAFImportError.unreadable }
    guard (values.fileSize ?? 0) <= 20 * 1024 * 1024 else { throw PipoEAFImportError.fileTooLarge }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    try checkCancellation()
    guard data.count <= 20 * 1024 * 1024 else { throw PipoEAFImportError.fileTooLarge }
    if data.starts(with: Array("%PDF-".utf8)) { return try importPDF(data) }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String),
      [UTType.png, .jpeg, .heic].contains(type)
    else { throw PipoEAFImportError.unsupportedType }
    let image = try downsample(data)
    let observations = try recognize(image, page: 0)
    let parsed = ScheduleImportParser.parse(observations: observations)
    return .init(parsed: parsed, preview: .init(data: data, images: [image]))
  }

  private static func importPDF(_ data: Data) throws -> PipoEAFImportResult {
    #if canImport(PDFKit)
      guard let document = PDFDocument(data: data), !document.isLocked else {
        throw PipoEAFImportError.unreadable
      }
      guard document.pageCount <= 10 else { throw PipoEAFImportError.tooManyPages }
      var observations: [ScheduleTextObservation] = []
      var previews: [Data] = []
      for index in 0..<document.pageCount {
        try checkCancellation()
        guard let page = document.page(at: index) else { throw PipoEAFImportError.unreadable }
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
          guard
            let image = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox)
              .pngData()
          else { throw PipoEAFImportError.unreadable }
          previews.append(image)
          observations += try recognize(image, page: index)
        } else {
          let selections =
            page.selection(for: NSRange(location: 0, length: page.numberOfCharacters))?
            .selectionsByLine() ?? []
          let pageBounds = page.bounds(for: .mediaBox)
          let lines: [(String, CGRect?)] =
            selections.isEmpty
            ? text.split(whereSeparator: \.isNewline).map { (String($0), nil) }
            : selections.map { ($0.string ?? "", $0.bounds(for: page)) }
          for (lineIndex, line) in lines.enumerated() {
            let lineText = line.0
            let cells: [String]
            if lineText.contains("|") {
              cells = lineText.split(separator: "|", omittingEmptySubsequences: false).map(
                String.init)
            } else if lineText.contains("\t") {
              cells = lineText.split(separator: "\t", omittingEmptySubsequences: false).map(
                String.init)
            } else {
              cells = [lineText]
            }
            for (column, cell) in cells.enumerated() {
              let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !trimmed.isEmpty else { continue }
              observations.append(
                ScheduleTextObservation(
                  text: trimmed, page: index, line: lineIndex + 1,
                  x: line.1.map { Double(($0.minX - pageBounds.minX) / pageBounds.width) },
                  y: line.1.map { Double((pageBounds.maxY - $0.maxY) / pageBounds.height) }
                    ?? Double(lineIndex),
                  width: line.1.map { Double($0.width / pageBounds.width) },
                  height: line.1.map { Double($0.height / pageBounds.height) }, confidence: nil,
                  candidates: [],
                  columnIndex: cells.count > 1 ? column : nil))
            }
          }
        }
      }
      return .init(
        parsed: ScheduleImportParser.parse(observations: observations),
        preview: .init(data: data, images: previews))
    #else
      throw PipoEAFImportError.unsupportedType
    #endif
  }

  private static func downsample(_ data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw PipoEAFImportError.unreadable
    }
    let options: CFDictionary =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true,
      ] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
      throw PipoEAFImportError.unreadable
    }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)
    else { throw PipoEAFImportError.unreadable }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw PipoEAFImportError.unreadable }
    return output as Data
  }

  private static func recognize(_ imageData: Data, page: Int) throws -> [ScheduleTextObservation] {
    #if canImport(Vision)
      try checkCancellation()
      guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { throw PipoEAFImportError.unreadable }
      var observations: [ScheduleTextObservation] = []
      var requestError: Error?
      let request = VNRecognizeTextRequest { request, error in
        requestError = error
        let results = request.results as? [VNRecognizedTextObservation] ?? []
        observations = results.enumerated().compactMap { index, result in
          let candidates = result.topCandidates(3)
          guard let top = candidates.first else { return nil }
          let box = result.boundingBox
          return ScheduleTextObservation(
            text: top.string, page: page, line: index + 1, x: Double(box.minX),
            y: Double(1 - box.maxY), width: Double(box.width), height: Double(box.height),
            confidence: Double(top.confidence), candidates: candidates.map(\.string))
        }
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      try VNImageRequestHandler(cgImage: image).perform([request])
      try checkCancellation()
      if let requestError { throw requestError }
      return observations
    #else
      throw PipoEAFImportError.unreadable
    #endif
  }

  private static func checkCancellation() throws {
    if Task.isCancelled { throw CancellationError() }
  }
}

#if canImport(AppKit)
  import AppKit
  extension NSImage {
    fileprivate func pngData() -> Data? {
      guard let tiffRepresentation, let representation = NSBitmapImageRep(data: tiffRepresentation)
      else { return nil }
      return representation.representation(using: .png, properties: [:])
    }
  }
#endif
