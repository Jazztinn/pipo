import Foundation

/// Preview gates are independent. Enable only for fixture/beta acceptance;
/// stable defaults stay closed until document and packaged-app acceptance.
public enum PipoFeatureGates {
  public static var scheduleImport: Bool {
    UserDefaults.standard.bool(forKey: "pipo.features.schedule-import")
  }

  public static var schedulePresentation: Bool {
    UserDefaults.standard.bool(forKey: "pipo.features.schedule-presentation")
  }

  public static let schoolSelection = false
  public static let canvas = false
}
