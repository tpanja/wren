import SwiftUI

@main
struct FonosApp: App {
    @State private var engine = CoachEngine()
    @AppStorage("fonos.appearance") private var appearance: Appearance = .dark
    @Environment(\.scenePhase) private var phase

    init() {
        FonosType.register()
        FonosType.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .font(.ui(.body))
                .preferredColorScheme(appearance.scheme)
                .tint(Theme.action)
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
    case dark, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
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
