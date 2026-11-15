import SwiftUI

struct RootView: View {
    @Environment(FonosEngine.self) private var engine
    @State private var tab: Tab = .speak
    @State private var showSettings = false

    enum Tab: Hashable { case speak, progress, band }

    var body: some View {
        TabView(selection: $tab) {
            SpeakScreen(showSettings: $showSettings)
                .tabItem { Label("Speak", systemImage: "waveform") }
                .tag(Tab.speak)
            TrendsScreen(showSettings: $showSettings)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
            BandScreen()
                .tabItem { Label("Band", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.band)
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen()
        }
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
