import SwiftUI

struct RootView: View {
    @Environment(CoachEngine.self) private var engine
    @State private var tab: Tab = .sing
    @State private var showSettings = false

    enum Tab: Hashable { case sing, progress, band }

    var body: some View {
        @Bindable var engine = engine
        TabView(selection: $tab) {
            SingScreen(showSettings: $showSettings)
                .tabItem { Label { Text("Sing") } icon: { Icon.sing.image } }
                .tag(Tab.sing)
            TrendsScreen(showSettings: $showSettings)
                .tabItem { Label { Text("Progress") } icon: { Icon.progress.image } }
                .tag(Tab.progress)
            BandScreen()
                .tabItem { Label { Text("Band") } icon: { Icon.band.image } }
                .tag(Tab.band)
        }
        .sheet(isPresented: $showSettings) { SettingsScreen() }
        .fullScreenCover(isPresented: $engine.takeIsPresented) { TakeFlowView() }
        .fullScreenCover(isPresented: Binding(
            get: { !engine.profile.onboarded },
            set: { if !$0 { engine.profile.onboarded = true } }
        )) { OnboardingView() }
        .alert("Fonos", isPresented: Binding(
            get: { engine.message != nil },
            set: { if !$0 { engine.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(engine.message ?? "")
        }
    }
}
