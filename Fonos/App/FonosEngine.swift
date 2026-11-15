import Foundation
import Observation
import os
import UIKit

/// The app's coordinator: picks the frame source, fans frames out to the
/// display buffers, the analyzer, and (while listening) the translator, and
/// runs the Speak flow: listen → translate → speak.
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

    private(set) var source: SourceKind
    private(set) var isStreaming = false
    private(set) var speakState: SpeakState = .idle
    private(set) var partialText = ""
    private(set) var utterances: [Utterance] = []
    private(set) var live = SpeechAnalyzer.Live()
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
    private(set) var band: BandConnection?

    @ObservationIgnored private let demo = DemoBand()
    @ObservationIgnored private let phoneMic = PhoneMicSource()
    @ObservationIgnored private var translator: SpeechTranslator
    @ObservationIgnored private let listening = OSAllocatedUnfairLock(initialState: false)
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var heardVoice = false
    @ObservationIgnored private var lastVoiceAt = Date.distantPast
    @ObservationIgnored private var phrasesThisSession = 0

    static let defaultPhrases = [
        "Yes", "No", "Thank you", "Please wait, I'm still talking",
        "Could you repeat that?", "I need a moment", "I'm tired", "I need help",
    ]

    init() {
        let d = UserDefaults.standard
        source = SourceKind(rawValue: d.string(forKey: "fonos.source") ?? "") ?? .demo
        quickPhrases = d.stringArray(forKey: "fonos.phrases") ?? Self.defaultPhrases
        autoStopSeconds = d.object(forKey: "fonos.autostop") as? Double ?? 1.8
        speakAutomatically = d.object(forKey: "fonos.autospeak") as? Bool ?? true
        translator = TranslatorFactory.make(for: source)
        store.showDemo = source == .demo
        if source == .band { band = BandConnection() }
        wire(currentSource)
    }

    // MARK: Source

    private var currentSource: FrameSource {
        switch source {
        case .band: band ?? demo
        case .demo: demo
        case .phoneMic: phoneMic
        }
    }

    func select(_ kind: SourceKind) {
        guard kind != source else { return }
        stopStreaming()
        source = kind
        UserDefaults.standard.set(kind.rawValue, forKey: "fonos.source")
        if kind == .band, band == nil { band = BandConnection() }
        translator = TranslatorFactory.make(for: kind)
        store.showDemo = kind == .demo
        streams.reset()
        wire(currentSource)
        startStreaming()
    }

    private func wire(_ src: FrameSource) {
        let streams = streams, analyzer = analyzer, listening = listening
        let sink: @Sendable (SensorFrame) -> Void = { [weak self] frame in
            streams.append(frame)
            analyzer.ingest(frame)
            if listening.withLock({ $0 }) {
                Task { @MainActor in self?.translator.append(mic: frame.mic) }
            }
        }
        demo.onFrame = nil; phoneMic.onFrame = nil; band?.onFrame = nil
        src.onFrame = sink
    }

    // MARK: Streaming / sessions

    func startStreaming() {
        guard !isStreaming else { return }
        if source == .band, band?.isConnected != true {
            // The band will be asked to stream as soon as it connects.
            band?.startStreaming()
            isStreaming = band?.isConnected == true
        } else {
            currentSource.startStreaming()
            isStreaming = true
        }
        analyzer.reset()
        sessionStart = .now
        phrasesThisSession = 0
        startPolling()
    }

    func stopStreaming() {
        if speakState == .listening { cancelListening() }
        currentSource.stopStreaming()
        isStreaming = false
        pollTimer?.invalidate()
        closeSession()
    }

    /// Saves the session summary when there was enough speech to measure.
    private func closeSession() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        if let record = analyzer.summary(started: start, isDemo: source == .demo, phrases: phrasesThisSession) {
            store.add(record)
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let l = analyzer.liveState
        if l != live { live = l }
        if source == .band, let band {
            // Band may connect after the user pressed start.
            if band.isConnected, !isStreaming { isStreaming = true }
            if !band.isConnected, isStreaming, band.state != .idle { isStreaming = band.status.isStreaming }
        }
        guard speakState == .listening else { return }
        if l.isVoicing { heardVoice = true; lastVoiceAt = .now }
        if autoStopSeconds > 0, heardVoice, Date.now.timeIntervalSince(lastVoiceAt) > autoStopSeconds {
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
        heardVoice = false
        lastVoiceAt = .now
        listening.withLock { $0 = true }
        speakState = .listening
        UIAccessibility.post(notification: .announcement, argument: "Listening")
    }

    func finishListening() async {
        guard speakState == .listening else { return }
        listening.withLock { $0 = false }
        speakState = .translating
        let result = await translator.finish()
        guard let result else {
            speakState = .idle
            partialText = ""
            message = heardVoice ? "Fonos couldn't make out the words. Try a shorter phrase." : "No speech was picked up. Check that the band sits snugly."
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
            // Return to idle when the synthesizer finishes.
            try? await Task.sleep(for: .milliseconds(300))
            while voice.isSpeaking { try? await Task.sleep(for: .milliseconds(150)) }
            if speakState == .speaking { speakState = .idle }
        }
    }

    // MARK: App lifecycle

    func didBecomeActive() {
        if source != .band || band?.rememberedBandID != nil { startStreaming() }
    }

    func didEnterBackground() {
        stopStreaming()
    }
}
