import Foundation
import Testing
@testable import PipoAppCore

@Test func fixedLMSOrigin() {
    #expect(PipoFoundation.lmsOrigin.absoluteString == "https://lms.lpucavite.edu.ph")
}

