import CoreText
import PDFKit
import Testing

@testable import PipoAppCore

struct PipoEAFImporterTests {
  @Test func textPDFTableImportPreservesPageAndFields() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "schedule-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try makePDF(
      at: url,
      text: "Course Code | Course Name | Days | Time\nCS101 | Computing | MWF | 10AM - 11AM")
    let result = try await PipoEAFImporter.importDocument(at: url)
    #expect(result.parsed.rows.count == 1)
    let row = try #require(result.parsed.rows.first)
    #expect(row.subject.code == "CS101")
    #expect(row.subject.name == "Computing")
    #expect(row.sourceSpan?.page == 0)
    #expect(row.meetings.first?.startTime == .init(hour: 10, minute: 0))
  }

  private func makePDF(at url: URL, text: String) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    context.beginPDFPage(nil)
    context.textMatrix = .identity
    let attributes: [NSAttributedString.Key: Any] = [
      .font: CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    ]
    let framesetter = CTFramesetterCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    let path = CGPath(rect: CGRect(x: 36, y: 36, width: 540, height: 700), transform: nil)
    CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
    context.endPDFPage()
    context.closePDF()
  }
}
