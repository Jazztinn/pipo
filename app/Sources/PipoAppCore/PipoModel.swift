import Observation

@MainActor
@Observable
public final class PipoModel {
    public init() {}

    public static func live() -> PipoModel {
        PipoModel()
    }
}

