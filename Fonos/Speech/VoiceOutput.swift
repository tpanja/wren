import AVFoundation
import Foundation
import Observation

/// Speaks translated text aloud. Prefers the patient's Personal Voice
/// (iOS 17+) when they have created one and allowed Fonos to use it.
@Observable
final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate {

    struct Voice: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
        let isPersonal: Bool
    }

    private(set) var isSpeaking = false
    private(set) var voices: [Voice] = []
    private(set) var personalVoiceStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus = .notDetermined
    /// Characters spoken so far in the current utterance, for highlighting.
    private(set) var spokenRange: NSRange?

    var selectedVoiceID: String? {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "fonos.voice") }
    }
    /// 0...1, maps onto the system's speech rate range.
    var rate: Double = 0.48 {
        didSet { UserDefaults.standard.set(rate, forKey: "fonos.rate") }
    }

    @ObservationIgnored private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
        selectedVoiceID = UserDefaults.standard.string(forKey: "fonos.voice")
        if UserDefaults.standard.object(forKey: "fonos.rate") != nil {
            rate = UserDefaults.standard.double(forKey: "fonos.rate")
        }
        personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        reloadVoices()
    }

    func requestPersonalVoice() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.personalVoiceStatus = status
                self?.reloadVoices()
            }
        }
    }

    func reloadVoices() {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let personal = all.filter { $0.voiceTraits.contains(.isPersonalVoice) }
        let quality = all
            .filter { !$0.voiceTraits.contains(.isPersonalVoice) && $0.quality != .default }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
        let fallback = all.filter { $0.quality == .default && $0.language == "en-US" }.prefix(4)

        voices = personal.map { Voice(id: $0.identifier, name: $0.name, detail: "Personal Voice", isPersonal: true) }
            + (quality + fallback).map {
                Voice(id: $0.identifier, name: $0.name,
                      detail: [$0.quality == .premium ? "Premium" : $0.quality == .enhanced ? "Enhanced" : nil,
                               Locale.current.localizedString(forIdentifier: $0.language)].compactMap { $0 }.joined(separator: " · "),
                      isPersonal: false)
            }
        // Default to Personal Voice when one exists and nothing is chosen yet.
        if selectedVoiceID == nil || !voices.contains(where: { $0.id == selectedVoiceID }) {
            selectedVoiceID = voices.first(where: \.isPersonal)?.id ?? voices.first?.id
        }
    }

    var selectedVoice: Voice? { voices.first { $0.id == selectedVoiceID } }

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)

        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        if let id = selectedVoiceID { u.voice = AVSpeechSynthesisVoice(identifier: id) }
        let lo = Double(AVSpeechUtteranceMinimumSpeechRate), hi = Double(AVSpeechUtteranceMaximumSpeechRate)
        u.rate = Float(lo + (hi - lo) * rate)
        u.postUtteranceDelay = 0.1
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .word)
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true; self.spokenRange = nil }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.spokenRange = r }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false; self.spokenRange = nil }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false; self.spokenRange = nil }
    }
}
