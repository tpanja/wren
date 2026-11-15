import SwiftUI

/// Progress card for the weekly Speech check: due now, or when it's next due.
struct WeeklyCheckCard: View {
    let store: CheckStore
    let start: () -> Void

    var body: some View {
        let due = store.isDue()
        let next = store.nextDue()
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Weekly speech check", icon: .checklist, color: Theme.action, ink: Theme.actionInk,
                       detail: store.latest.map { "Last: \($0.date.formatted(.dateTime.month(.abbreviated).day()))" })
            Text(due ? "Your check is due" : "Next check \(nextText(next))")
                .font(.metric(.title3, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Four short tasks, about 3 minutes. The same tasks each week make changes easier to see.")
                .font(.ui(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if due {
                Button(action: start) {
                    Label { Text("Start check") } icon: { FonosIcon(.speak, size: 20, relativeTo: .headline) }
                        .font(.ui(.headline))
                        .foregroundStyle(Theme.onAction)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.actionInk, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(PressScale())
            } else {
                Button("Do a check now", action: start).buttonStyle(.well)
            }
        }
        .card()
    }

    private func nextText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInTomorrow(d) { return "tomorrow" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: d)).day ?? 0
        return days <= 6 ? "on \(d.formatted(.dateTime.weekday(.wide)))" : "on \(d.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

/// A gentle prompt to bank the patient's voice while speaking is easier.
/// iPhone's Personal Voice is free and built in, and Fonos already speaks
/// in it once it exists.
struct VoiceBankingCard: View {
    let dismiss: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Your voice", icon: .speak, color: Theme.symmetry, ink: Theme.rightInk)
            Text("Consider saving your voice")
                .font(.metric(.title3, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Recording your voice now, while speaking is easier, lets your iPhone make a Personal Voice that sounds like you. Wren then speaks your words in it.")
                .font(.ui(.body))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Open Settings, then Accessibility, then Personal Voice.")
                    step(2, "Tap Create a Personal Voice and read the phrases aloud. It takes about 15 minutes, and you can stop and come back.")
                    step(3, "Your iPhone prepares the voice on its own. Then choose it in Wren Settings under Voice.")
                    Text("Your speech therapist can also tell you about other voice and message banking options.")
                        .font(.ui(.footnote)).foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(expanded ? "Got it" : "How to do it") {
                    if expanded { dismiss() } else { withAnimation { expanded = true } }
                }
                .buttonStyle(.well(Theme.action))
                Button("Not now", action: dismiss).buttonStyle(.well(Theme.inkSecondary))
            }
        }
        .card()
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.metric(.subheadline, weight: .bold)).foregroundStyle(Theme.rightInk)
                .frame(width: 18)
            Text(text).font(.ui(.body)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
