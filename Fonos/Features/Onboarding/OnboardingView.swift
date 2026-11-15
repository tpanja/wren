import SwiftUI

/// First run: promise, privacy, fit check, then the range-finding warm-up.
struct OnboardingView: View {
    @Environment(CoachEngine.self) private var engine
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                promise.tag(0)
                privacy.tag(1)
                fit.tag(2)
                rangePage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page < 3 ? "Continue" : "Find my range") {
                if page < 3 { withAnimation { page += 1 } } else { finish(startSiren: true) }
            }
            .font(.ui(.headline))
            .foregroundStyle(Theme.onAction)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, Theme.gutter)
            if page == 3 {
                Button("Skip for now") { finish(startSiren: false) }
                    .font(.ui(.body, .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(minHeight: 44)
            }
        }
        .padding(.bottom, 12)
        .background(Theme.ground.ignoresSafeArea())
        .onChange(of: page) { _, p in
            if p == 2 { engine.startFitCheck() } else { engine.stopFitCheck() }
        }
    }

    private func finish(startSiren: Bool) {
        engine.stopFitCheck()
        engine.profile.onboarded = true
        if startSiren {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { engine.begin(.siren) }
        }
    }

    private func pageLayout<Visual: View>(_ title: String, _ body: String, @ViewBuilder visual: () -> Visual) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)
            visual()
            Text(title)
                .font(.metric(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.ui(.title3))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 60)
        }
        .padding(.horizontal, Theme.gutter + 8)
    }

    private var promise: some View {
        pageLayout("Sing better, one take at a time.",
                   "Fonos hears your voice and feels it at your throat. After every take, you get one thing to work on and a drill to do it.") {
            HStack(spacing: 14) {
                ForEach(MetricID.rings) { m in
                    MetricRing(metric: m, value: m == .range ? 19 : m == .pitchAccuracy ? 74 : 12, diameter: 76, lineWidth: 7, compact: true)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var privacy: some View {
        pageLayout("Your voice stays on your iPhone.",
                   "Audio and vibration are analyzed here and never uploaded. Personal feedback with Claude is off until you turn it on in Settings, and even then only numbers are sent.") {
            FonosIcon(.mic, size: 64, relativeTo: .largeTitle).foregroundStyle(Theme.action)
        }
    }

    private var fit: some View {
        pageLayout("Put on the band and hum.",
                   "Wear it just above your collarbone. When both sides move evenly, it fits.") {
            FoldView(streams: engine.streams)
                .frame(height: 120)
                .card()
        }
    }

    private var rangePage: some View {
        pageLayout("Let's find your range.",
                   "Glide gently from low to high and back on \"ng\". Fonos pitches every exercise to the notes you can sing comfortably.") {
            FonosIcon(.siren, size: 64, relativeTo: .largeTitle).foregroundStyle(Theme.rangeHue)
        }
    }
}
