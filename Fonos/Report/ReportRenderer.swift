import SwiftUI
import UIKit

/// Renders the clinic summary page to a one-page vector PDF.
@MainActor
enum ReportRenderer {

    static func fileName(for report: ClinicReport) -> String {
        // Local calendar date, so the file name matches the "Generated" date on the page.
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return "Fonos speech summary \(f.string(from: report.generated)).pdf"
    }

    /// Writes the PDF to a temporary file and returns its URL.
    static func pdf(_ report: ClinicReport) -> URL? {
        let size = ClinicReportPage.size
        let renderer = ImageRenderer(content: ClinicReportPage(report: report))
        renderer.proposedSize = ProposedViewSize(size)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(for: report))
        try? FileManager.default.removeItem(at: url)
        var box = CGRect(origin: .zero, size: size)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "Fonos Speech Monitoring Summary",
            kCGPDFContextCreator: "Fonos \(Paper.appVersion)",
            kCGPDFContextSubject: "Speech measures \(Paper.date(report.periodStart)) to \(Paper.date(report.periodEnd))",
        ]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return nil }
        renderer.render { _, draw in
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }
}

/// Presents the system share sheet from UIKit. Hosting
/// UIActivityViewController inside a SwiftUI `.sheet` shows a blank sheet,
/// and ShareLink does not report whether the user actually shared.
@MainActor
enum SharePresenter {
    static func present(_ items: [Any], completion: @escaping (Bool) -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var top = scene.keyWindow?.rootViewController else { completion(false); return }
        while let next = top.presentedViewController { top = next }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }
}
