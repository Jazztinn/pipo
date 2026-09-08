import Foundation

/// Preserves the established LPU account fingerprint through the migration.
/// A provider/school/origin prefix prevents future adapters sharing its state.
public enum PipoAccountNamespace {
  private static let lpuPrefix = "moodle:lpu-cavite:lms:"

  public static func lpuScope(for storedID: String) -> String {
    storedID.hasPrefix(lpuPrefix) ? storedID : lpuPrefix + storedID
  }

  public static func legacyLPUIdentifier(in scopedID: String) -> String? {
    guard scopedID.hasPrefix(lpuPrefix) else { return nil }
    let legacy = String(scopedID.dropFirst(lpuPrefix.count))
    guard legacy.count == 24, legacy.allSatisfy({ $0.isHexDigit }) else { return nil }
    return legacy
  }
}
