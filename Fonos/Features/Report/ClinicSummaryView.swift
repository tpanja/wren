import SwiftUI

/// Builds, previews, and shares the two-page clinic summary.
///
/// The period runs from the last time a summary was shared (or from the
/// first session, the first time). Patient details are optional and stay
/// on this iPhone.
struct ClinicSummaryView: View {
    @Environment(FonosEngine.self) private var engine
    @AppStorage("fonos.patient.name") private var name = ""
    @AppStorage("fonos.patient.dob") private var dobStamp: Double = 0
    @AppStorage("fonos.report.lastExport") private var lastExportStamp: Double = 0

    @State private var justShared: Date?
    @State private var failed = false
    @FocusState private var nameFocused: Bool

    private var lastExport: Date? { lastExportStamp > 0 ? Date(timeIntervalSince1970: lastExportStamp) : nil }
    private var dob: Date? { dobStamp != 0 ? Date(timeIntervalSince1970: dobStamp) : nil }

    private var report: ClinicReport {
        ClinicReport.make(
            sessions: engine.store.visible,
            checks: engine.checks.visible,
            patient: .init(name: name.trimmingCharacters(in: .whitespaces), dateOfBirth: dob),
            lastExport: lastExport
        )
    }

    var body: some View {
        let r = report
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stack) {
                Text("A two-page report of your speech measures and weekly checks for your neurologist or speech therapist.")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(1...ClinicReportPage.pageCount, id: \.self) { PagePreview(report: r, page: $0) }

                coverage(r)
                patientCard
                if let justShared { sharedNote(justShared) }

                Text("The report is made on this iPhone. Fonos does not upload it anywhere; you choose where it goes.")
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.bottom, 96)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) { shareBar(r) }
        .navigationTitle("Clinic summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .alert("The summary couldn't be created", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again. If it keeps failing, restart Fonos.")
        }
    }

    // MARK: Pieces

    private func coverage(_ r: ClinicReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "What it covers", icon: .progress, color: Theme.pace)
            Text("\(Paper.date(r.periodStart)) to \(Paper.date(r.periodEnd))")
                .font(.metric(.title3, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(r.sinceLastExport
                 ? "Everything since your last summary. \(counts(r))."
                 : "Everything so far. \(counts(r)).")
                .font(.ui(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
            if r.sinceLastExport {
                Button("Include everything instead") { lastExportStamp = 0; justShared = nil }
                    .font(.ui(.subheadline, .semibold))
                    .frame(minHeight: 44)
            }
        }
        .card()
    }

    private func counts(_ r: ClinicReport) -> String {
        let s = r.quality.sessions, c = r.quality.checks
        return "\(s) session\(s == 1 ? "" : "s") and \(c) weekly check\(c == 1 ? "" : "s")"
    }

    private var patientCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Your details (optional)", icon: .settings, color: Theme.inkSecondary)
            TextField("Full name", text: $name)
                .font(.ui(.title3))
                .textContentType(.name)
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Toggle(isOn: Binding(
                get: { dobStamp != 0 },
                set: { dobStamp = $0 ? (dob ?? defaultDOB).timeIntervalSince1970 : 0 }
            )) {
                Text("Include date of birth").font(.ui(.body))
            }
            .frame(minHeight: 44)
            if dobStamp != 0 {
                DatePicker("Date of birth",
                           selection: Binding(get: { dob ?? defaultDOB }, set: { dobStamp = $0.timeIntervalSince1970 }),
                           in: ...Date.now, displayedComponents: .date)
                    .font(.ui(.body))
                    .frame(minHeight: 44)
            }
            Text("Left blank, the report prints empty lines your clinic can fill in. Saved on this iPhone only.")
                .font(.ui(.footnote))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var defaultDOB: Date {
        Calendar.current.date(from: DateComponents(year: 1960, month: 1, day: 1)) ?? .now
    }

    private func sharedNote(_ d: Date) -> some View {
        Label {
            Text("Shared. Your next summary will start from \(Paper.date(d)).")
                .font(.ui(.subheadline))
                .foregroundStyle(Theme.ink)
        } icon: {
            CheckDisc(color: Theme.good, size: 20)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shareBar(_ r: ClinicReport) -> some View {
        Button {
            nameFocused = false
            if let url = ReportRenderer.pdf(r) {
                SharePresenter.present([url]) { completed in
                    guard completed else { return }
                    // The next summary starts where this one ended.
                    lastExportStamp = r.periodEnd.timeIntervalSince1970
                    justShared = r.periodEnd
                }
            } else {
                failed = true
            }
        } label: {
            Label { Text("Share summary") } icon: { FonosIcon(.report, size: 22, relativeTo: .headline) }
                .font(.ui(.headline))
                .foregroundStyle(Theme.onAction)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(Theme.action, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityHint("Creates a PDF and opens sharing options such as Mail, Messages, Files, and Print")
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.ground.opacity(0.97).ignoresSafeArea(edges: .bottom))
    }
}

/// The real page, scaled to fit the screen width, on a paper card.
private struct PagePreview: View {
    let report: ClinicReport
    let page: Int

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / ClinicReportPage.size.width
            ClinicReportPage(report: report, page: page)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: ClinicReportPage.size.height * scale, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .aspectRatio(ClinicReportPage.size.width / ClinicReportPage.size.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the clinic summary, page \(page) of \(ClinicReportPage.pageCount)")
        .accessibilityValue(page == 1 ? report.summary : "Trend charts, data quality, and methods")
    }
}
