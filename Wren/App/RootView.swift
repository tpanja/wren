import SwiftUI

struct RootView: View {
    @Environment(WrenEngine.self) private var engine
    @State private var tab: Tab = .speak
    @State private var showSettings = false

    enum Tab: Hashable { case speak, progress, band }

    var body: some View {
        TabView(selection: $tab) {
            SpeakScreen(showSettings: $showSettings)
                .tabItem { Label { Text("Speak") } icon: { Icon.speak.image } }
                .tag(Tab.speak)
            TrendsScreen(showSettings: $showSettings)
                .tabItem { Label { Text("Progress") } icon: { Icon.progress.image } }
                .tag(Tab.progress)
            BandScreen()
                .tabItem { Label { Text("Band") } icon: { Icon.band.image } }
                .tag(Tab.band)
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen()
        }
        .alert("Wren", isPresented: Binding(
            get: { engine.message != nil },
            set: { if !$0 { engine.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(engine.message ?? "")
        }
    }
}
