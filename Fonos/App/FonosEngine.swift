import Foundation
import Observation
import os
import UIKit

/// The app's coordinator. Streams toy band frames into the display buffers
/// and the analyzer, and runs the Speak flow: listen → translate → speak.
@MainActor
@Observable
final class FonosEngine {

    enum SpeakState: Equatable {
        case idle
        case listening
        case translating
        case speaking
    }

    struct Utterance: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let text: String
        let confidence: Double?
        let fromPhrase: Bool
    }

    // MARK: Published state

    private(set) var isStreaming = false
    private(set) var speakState: SpeakState = .idle
    private(set) var partialText = ""
    private(set) var utterances: [Utterance] = []
    private(set) var live = SpeechAnalyzer.Live()
    private(set) var bandStatus = BandStatus()
    private(set) var sessionStart: Date?
    var message: String?

    var quickPhrases: [String] {
        didSet { UserDefaults.standard.set(quickPhrases, forKey: "fonos.phrases") }
    }
    /// Seconds of silence after speech that ends listening. 0 = tap to stop only.
    var autoStopSeconds: Double {
        didSet { UserDefaults.standard.set(autoStopSeconds, forKey: "fonos.autostop") }
    }
    var speakAutomatically: Bool {
        didSet { UserDefaults.standard.set(speakAutomatically, forKey: "fonos.autospeak") }
    }

    // MARK: Collaborators

    let streams = StreamStore()
    let analyzer = SpeechAnalyzer()
    let store = SessionStore()
    let voice = VoiceOutput()

    @ObservationIgnored private let band = ToyBand()
    @ObservationIgnored private let translator: SpeechTranslator = ToyTranslator()
    @ObservationIgnored private let listening = OSAllocatedUnfairLock(initialState: false)
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var listenStarted = Date.distantPast
    @ObservationIgnored private var phrasesThisSession = 0

    static let defaultPhrases = [
        "Yes", "No", "Thank you", "Please wait, I'm still talking",
        "Could you repeat that?", "I need a moment", "I'm tired", "I need help",
    ]

    init() {
        let d = UserDefaults.standard
        quickPhrases = d.stringArray(forKey: "fonos.phrases") ?? Self.defaultPhrases
        autoStopSeconds = d.object(forKey: "fonos.autostop") as? Double ?? 3
        speakAutomatically = d.object(forKey: "fonos.autospeak") as? Bool ?? true

        let streams = streams, analyzer = analyzer, listening = listening, translator = translator
        band.onFrame = { frame in
            streams.append(frame)
            analyzer.ingest(frame)
            if listening.withLock({ $0 }) {
                DispatchQueue.main.async { translator.append(mic: frame.mic) }
            }
        }
    }

    // MARK: Streaming / sessions

    func startStreaming() {
        guard !isStreaming else { return }
        band.startStreaming()
        isStreaming = true
        analyzer.reset()
        sessionStart = .now
        phrasesThisSession = 0
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stopStreaming() {
        if speakState == .listening { cancelListening() }
        band.stopStreaming()
        isStreaming = false
        pollTimer?.invalidate()
        if let start = sessionStart,
           let record = analyzer.summary(started: start, isSample: true, phrases: phrasesThisSession) {
            store.add(record)
        }
        sessionStart = nil
    }

    private func poll() {
        let l = analyzer.liveState
        if l != live { live = l }
        let s = band.status
        if s != bandStatus { bandStatus = s }
        // The toy wearer "speaks" for a few seconds, then listening ends on its own,
        // the way silence would end it with a real band.
        if speakState == .listening, autoStopSeconds > 0,
           Date.now.timeIntervalSince(listenStarted) > autoStopSeconds {
            Task { await finishListening() }
        }
    }

    // MARK: Speak flow

    /// The one big button. Idle → listen. Listening → translate and speak.
    /// Speaking → stop speaking.
    func primaryAction() {
        switch speakState {
        case .idle: startListening()
        case .listening: Task { await finishListening() }
        case .translating: break
        case .speaking: voice.stop(); speakState = .idle
        }
    }

    func startListening() {
        if !isStreaming { startStreaming() }
        do {
            try translator.begin()
        } catch {
            message = error.localizedDescription
            return
        }
        translator.onPartial = { [weak self] text in self?.partialText = text }
        partialText = ""
        listenStarted = .now
        band.setTalking(true)
        listening.withLock { $0 = true }
        speakState = .listening
        UIAccessibility.post(notification: .announcement, argument: "Listening")
    }

    func finishListening() async {
        guard speakState == .listening else { return }
        listening.withLock { $0 = false }
        band.setTalking(false)
        speakState = .translating
        guard let result = await translator.finish() else {
            speakState = .idle
            partialText = ""
            message = "Fonos couldn't make out the words. Try a shorter phrase."
            return
        }
        analyzer.addClarity(result.confidence)
        phrasesThisSession += 1
        utterances.insert(Utterance(date: .now, text: result.text, confidence: result.confidence, fromPhrase: false), at: 0)
        partialText = ""
        if speakAutomatically { say(result.text) } else { speakState = .idle }
    }

    func cancelListening() {
        listening.withLock { $0 = false }
        band.setTalking(false)
        translator.cancel()
        partialText = ""
        speakState = .idle
    }

    func say(_ text: String, asPhrase: Bool = false) {
        if asPhrase {
            utterances.insert(Utterance(date: .now, text: text, confidence: nil, fromPhrase: true), at: 0)
        }
        speakState = .speaking
        voice.speak(text)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            while voice.isSpeaking { try? await Task.sleep(for: .milliseconds(150)) }
            if speakState == .speaking { speakState = .idle }
        }
    }

    // MARK: App lifecycle

    func didBecomeActive() { startStreaming() }
    func didEnterBackground() { stopStreaming() }
}
