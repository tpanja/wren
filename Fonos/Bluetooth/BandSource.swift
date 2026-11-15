import Foundation

/// Where sensor frames come from. The engine does not care whether frames
/// arrive from the real band, the built-in demo, or the iPhone microphone.
enum SourceKind: String, CaseIterable, Identifiable, Codable {
    case band
    case demo
    case phoneMic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .band: "Fonos band"
        case .demo: "Demo band"
        case .phoneMic: "iPhone microphone"
        }
    }

    var detail: String {
        switch self {
        case .band: "Live signals from your throat band over Bluetooth."
        case .demo: "Synthetic signals so you can explore the app without the band."
        case .phoneMic: "Test translation with the phone's microphone. Piezo sensors are not available."
        }
    }

    var symbol: String {
        switch self {
        case .band: "dot.radiowaves.left.and.right"
        case .demo: "waveform.path"
        case .phoneMic: "iphone.gen3"
        }
    }
}

/// Frames are delivered on a background queue, roughly 100 per second.
protocol FrameSource: AnyObject {
    var onFrame: (@Sendable (SensorFrame) -> Void)? { get set }
    func startStreaming()
    func stopStreaming()
}
