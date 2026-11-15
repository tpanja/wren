import SwiftUI

@main
struct WrenApp: App {
    @State private var engine = WrenEngine()
    @AppStorage("wren.appearance") private var appearance: Appearance = .light
    @Environment(\.scenePhase) private var phase

    init() {
        WrenType.register()
        WrenType.applyAppearance()
        DispatchQueue.global(qos: .utility).async { DemoClip.copyToFiles() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .font(.ui(.body))
                .preferredColorScheme(appearance.scheme)
                .tint(Theme.actionInk)
                .onChange(of: phase) { _, newPhase in
                    switch newPhase {
                    case .active: engine.didBecomeActive()
                    case .background: engine.didEnterBackground()
                    default: break
                    }
                }
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Match iPhone"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}
