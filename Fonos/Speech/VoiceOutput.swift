import AVFoundation
import Foundation
import Observation

/// Speaks translated text aloud in the most natural voice on the iPhone: the
/// patient's Personal Voice when they allow it, otherwise one of Apple's
/// neural Premium voices, then Enhanced. Sentences are read with short pauses
/// at commas, clause breaks and sentence ends, the way people speak.
@Observable
final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate {

    struct Voice: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
        let isPersonal: Bool
        /// Personal Voice, Premium or Enhanced: the voices that sound human.
        let isNatural: Bool
    }

    private(set) var isSpeaking = false
    private(set) var voices: [Voice] = []
    private(set) var personalVoiceStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus = .notDetermined
    /// Characters spoken so far in the current utterance, for highlighting.
    private(set) var spokenRange: NSRange?

    var selectedVoiceID: String? {
        didSet {
            UserDefaults.standard.set(selectedVoiceID, forKey: "fonos.voice")
            // Picking a voice by hand stops Wren from switching it later.
            if !autoPicking { UserDefaults.standard.set(true, forKey: "fonos.voice.chosen") }
        }
    }
    /// 0...1, maps onto the system's speech rate range.
    var rate: Double = 0.48 {
        didSet { UserDefaults.standard.set(rate, forKey: "fonos.rate") }
    }

    /// True when the voice in use is one of the natural-sounding ones.
    var hasNaturalVoice: Bool { selectedVoice?.isNatural ?? false }

    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var autoPicking = false
    @ObservationIgnored private var voicesObserver: NSObjectProtocol?

    override init() {
        super.init()
        synth.delegate = self
        selectedVoiceID = UserDefaults.standard.string(forKey: "fonos.voice")
        if UserDefaults.standard.object(forKey: "fonos.rate") != nil {
            rate = UserDefaults.standard.double(forKey: "fonos.rate")
        }
        personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        reloadVoices()
        // A voice downloaded in iPhone Settings shows up without a relaunch.
        voicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reloadVoices() }
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
        // Natural first: Premium, then Enhanced; US English ahead of other English.
        func rank(_ v: AVSpeechSynthesisVoice) -> (Int, Int, String) {
            let quality = v.quality == .premium ? 0 : v.quality == .enhanced ? 1 : 2
            return (quality, v.language == "en-US" ? 0 : 1, v.name)
        }
        let natural = all.filter { !$0.voiceTraits.contains(.isPersonalVoice) && $0.quality != .default }
            .sorted { rank($0) < rank($1) }
        // Basic voices only as a fallback: the standard ones (Samantha first),
        // never the novelty voices (Albert, Bells…) or the Eloquence set.
        let fallback = all.filter {
            $0.quality == .default && $0.language == "en-US" && !$0.voiceTraits.contains(.isPersonalVoice)
                && !$0.identifier.contains("speech.synthesis.voice") && !$0.identifier.contains("eloquence")
        }
        .sorted { ($0.name == "Samantha" ? 0 : 1, $0.name) < ($1.name == "Samantha" ? 0 : 1, $1.name) }
        .prefix(4)

        voices = personal.map { Voice(id: $0.identifier, name: $0.name, detail: "Personal Voice", isPersonal: true, isNatural: true) }
            + (natural + fallback).map {
                Voice(id: $0.identifier, name: $0.name,
                      detail: [$0.quality == .premium ? "Premium" : $0.quality == .enhanced ? "Enhanced" : "Basic",
                               Locale.current.localizedString(forIdentifier: $0.language)].compactMap { $0 }.joined(separator: " · "),
                      isPersonal: false, isNatural: $0.quality != .default)
            }
        // Until the user picks one, always use the best voice available, so a
        // Premium voice downloaded later is picked up on its own.
        let chosen = UserDefaults.standard.bool(forKey: "fonos.voice.chosen")
        if !chosen || selectedVoiceID == nil || !voices.contains(where: { $0.id == selectedVoiceID }) {
            autoPicking = true
            selectedVoiceID = voices.first?.id
            autoPicking = false
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
        let voice = selectedVoiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:))
        let u = AVSpeechUtterance(ssmlRepresentation: Self.ssml(for: text, rate: rate)) ?? {
            // Plain text if the SSML is ever rejected: same words, no added pauses.
            let plain = AVSpeechUtterance(string: text)
            let lo = Double(AVSpeechUtteranceMinimumSpeechRate), hi = Double(AVSpeechUtteranceMaximumSpeechRate)
            plain.rate = Float(lo + (hi - lo) * rate)
            return plain
        }()
        u.voice = voice
        u.prefersAssistiveTechnologySettings = false
        u.preUtteranceDelay = 0.05
        u.postUtteranceDelay = 0.1
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .word)
    }

    // MARK: Natural pauses

    /// The sentence as SSML with pauses where a person would take them:
    /// after commas, at clause breaks in longer sentences, and between
    /// sentences. `rate` is the speaking-speed setting (0.5 is normal).
    static func ssml(for text: String, rate: Double) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let conjunctions: Set<String> = ["and", "but", "because", "so", "or", "then", "when", "while", "if", "although", "unless"]
        var out = ""
        var sinceBreak = 0
        for (i, word) in words.enumerated() {
            let isLast = i == words.count - 1
            let bare = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            // A breath before a new clause once the current one has run a while.
            if !out.isEmpty, conjunctions.contains(bare), sinceBreak >= 5, words.count - i >= 3 {
                out += "<break time=\"150ms\"/> "
                sinceBreak = 0
            }
            out += escape(word)
            sinceBreak += 1
            guard !isLast, let mark = word.last else { out += " "; continue }
            let pause: Int? = switch mark {
            case ",": 250
            case ";", ":", "—", "–": 350
            case ".", "?", "!": 550
            default: nil
            }
            if let pause {
                out += "<break time=\"\(pause)ms\"/>"
                sinceBreak = 0
            }
            out += " "
        }
        let percent = Int((rate / 0.5 * 100).rounded())
        return "<speak><prosody rate=\"\(percent)%\">\(out.trimmingCharacters(in: .whitespaces))</prosody></speak>"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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
