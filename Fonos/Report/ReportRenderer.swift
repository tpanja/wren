import SwiftUI
import UIKit

/// Renders the clinic summary page to a one-page vector PDF.
@MainActor
enum ReportRenderer {

    static func fileName(for report: ClinicReport) -> String {
        "Fonos speech summary \(report.generated.formatted(.iso8601.year().month().day())).pdf"
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

/// Wraps UIActivityViewController so we learn whether the user actually
/// shared, saved, or printed the file (ShareLink does not report that).
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
