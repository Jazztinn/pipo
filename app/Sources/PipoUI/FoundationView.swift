import PipoAppCore
import SwiftUI

public struct PipoRootView: View {
    @Bindable private var model: PipoModel

    public init(model: PipoModel) {
        self.model = model
    }

    public var body: some View {
        Text("Pipo")
    }
}

public struct PipoSettingsView: View {
    @Bindable private var model: PipoModel

    public init(model: PipoModel) {
        self.model = model
    }

    public var body: some View {
        Text("Settings")
    }
}

