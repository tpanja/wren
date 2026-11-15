import AVFoundation
import Foundation
import Observation
import os
import UIKit

/// The app's coordinator. Streams band frames (from the simulated band or the
/// real one over Bluetooth) into the display buffers and the analyzer, and
/// runs the Speak flow: listen → translate → speak.
@MainActor
@Observable
final class FonosEngine {

    /// Which band feeds the app. Simulated until the user connects a real band.
    enum BandMode: String {
        case simulated, bluetooth
    }

    /// Which microphone the Speak flow listens with.
    enum MicSource: Equatable, Sendable {
        /// The band's throat mic, when a real band is connected.
        case band
        /// The iPhone mic, otherwise (for example for the demo recordings).
        case phone
    }

    enum SpeakState: Equatable {
        case idle
        case listening
        case translating
        case speaking
    }

    /// A Speech check task in progress, or its result.
    enum TaskState: Equatable {
        case idle
        case recording(CheckTask)
        case done(TaskResult)
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
    /// The microphone in use while listening, nil otherwise.
    private(set) var listeningSource: MicSource?
    private(set) var utterances: [Utterance] = []
    private(set) var live = SpeechAnalyzer.Live()
    private(set) var bandStatus = BandStatus()
    /// The Bluetooth link: connection state, bands found, signal strength.
    private(set) var link = BluetoothBand.Snapshot()
    private(set) var bandMode: BandMode {
        didSet { UserDefaults.standard.set(bandMode.rawValue, forKey: "fonos.band.mode") }
    }
    private(set) var sessionStart: Date?
    private(set) var taskState: TaskState = .idle
    /// Seconds into the current task recording.
    private(set) var taskElapsed: Double = 0
    /// 0...1 live voice level during a task, for the meter.
    private(set) var taskLevel: Double = 0
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
    let checks = CheckStore()
    let voice = VoiceOutput()

    @ObservationIgnored private let toy = ToyBand()
    @ObservationIgnored private let bluetooth = BluetoothBand()
    private var band: FrameSource { bandMode == .simulated ? toy : bluetooth }
    @ObservationIgnored private var scanStarted = Date.distantPast
    @ObservationIgnored private var listenVoiceSeen = false
    @ObservationIgnored private var listenLastVoice = Date.distantPast
    @ObservationIgnored private let clips = ClipTranslator()
    private var translator: SpeechTranslator { clips }
    @ObservationIgnored private let phoneMic = PhoneMic()
    /// Where listening audio comes from right now; nil when not listening.
    @ObservationIgnored private let listening = OSAllocatedUnfairLock<MicSource?>(initialState: nil)
    /// Phone-mic loudness during this listen, 10 per second, for the noise floor.
    @ObservationIgnored private var phoneLevels: [Float] = []
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var listenStarted = Date.distantPast
    @ObservationIgnored private var phrasesThisSession = 0
    /// Frames of the task being recorded (nil when no task is recording).
    @ObservationIgnored private let taskFrames = OSAllocatedUnfairLock<[SensorFrame]?>(initialState: nil)
    @ObservationIgnored private var taskStarted = Date.distantPast
    @ObservationIgnored private var taskVoiceSeen = false
    @ObservationIgnored private var taskLastVoice = Date.distantPast
    @ObservationIgnored private var taskFloorDb: Float = 0

    private static let log = Logger(subsystem: "com.fonos.app", category: "speak")

    static let defaultPhrases = [
        "Yes", "No", "Thank you", "Please wait, I'm still talking",
        "Could you repeat that?", "I need a moment", "I'm tired", "I need help",
    ]

    init() {
        let d = UserDefaults.standard
        quickPhrases = d.stringArray(forKey: "fonos.phrases") ?? Self.defaultPhrases
        autoStopSeconds = d.object(forKey: "fonos.autostop") as? Double ?? 3
        speakAutomatically = d.object(forKey: "fonos.autospeak") as? Bool ?? true
        bandMode = d.string(forKey: "fonos.band.mode").flatMap(BandMode.init(rawValue:)) ?? .simulated

        let streams = streams, analyzer = analyzer, listening = listening, clips = clips, taskFrames = taskFrames
        let route: @Sendable (SensorFrame) -> Void = { frame in
            let source = listening.withLock { $0 }
            // While the phone mic listens, it alone feeds the throat signal.
            if source == .phone { return }
            streams.append(frame)
            // Task speech stays out of the conversation session measures.
            let inTask = taskFrames.withLock { buf -> Bool in
                guard buf != nil else { return false }
                buf!.append(frame)
                return true
            }
            if !inTask { analyzer.ingest(frame) }
            if source == .band {
                clips.append(mic: frame.mic)
                clips.appendSpeech(samples: frame.mic)
            }
        }
        toy.onFrame = route
        phoneMic.onSamples = { samples in
            guard listening.withLock({ $0 }) == .phone else { return }
            streams.append(SensorFrame(mic: samples, left: [], right: []))
            clips.append(mic: samples)
        }
        phoneMic.onBuffer = { buffer in
            guard listening.withLock({ $0 }) == .phone else { return }
            clips.appendSpeech(buffer)
        }
        bluetooth.onFrame = route
        // A band connected before reconnects on its own.
        if bandMode == .bluetooth { bluetooth.activate() }
        // Always running, paused or not: band state (connecting, battery,
        // signal) has to reach the screen even while the signal is paused.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    // MARK: Band

    /// True when frames can flow: the simulated band, or a connected real band.
    var bandConnected: Bool {
        if bandMode == .simulated { return true }
        if case .connected = link.state { return true }
        return false
    }

    /// "Connect your band": switches to the real band, then reconnects the
    /// remembered one or, the first time, looks for bands nearby.
    func setUpBand() {
        use(.bluetooth)
        if BluetoothBand.remembered == nil { findBands() }
    }

    /// Looks for nearby Fonos bands (asks for Bluetooth permission the first time).
    func findBands() {
        scanStarted = .now
        bluetooth.scan()
    }

    func stopFindingBands() { bluetooth.stopScan() }

    /// Connects to a band and makes it the app's source from now on.
    func connectBand(_ id: UUID) {
        bluetooth.connect(id)
        use(.bluetooth)
    }

    /// Disconnects the real band. `forget` stops automatic reconnection.
    func disconnectBand(forget: Bool) {
        bluetooth.disconnect(forget: forget)
    }

    /// Switches between the simulated and the real band.
    func use(_ mode: BandMode) {
        guard mode != bandMode else { return }
        let wasStreaming = isStreaming
        if wasStreaming { stopStreaming() }
        bandMode = mode
        // Old signal from the other band must not look live.
        streams.reset()
        analyzer.reset()
        if mode == .simulated { bluetooth.disconnect(forget: false) } else { bluetooth.reconnect() }
        if wasStreaming { startStreaming() }
    }

    // MARK: Streaming / sessions

    func startStreaming() {
        guard !isStreaming else { return }
        band.startStreaming()
        isStreaming = true
        analyzer.reset()
        sessionStart = .now
        phrasesThisSession = 0
    }

    func stopStreaming() {
        if speakState == .listening { cancelListening() }
        if case .recording = taskState { cancelTask() }
        band.stopStreaming()
        isStreaming = false
        if let start = sessionStart,
           let record = analyzer.summary(started: start, isSample: bandMode == .simulated, phrases: phrasesThisSession) {
            store.add(record)
        }
        sessionStart = nil
    }

    private func poll() {
        let l = analyzer.liveState
        if l != live { live = l }
        let s = band.status
        if s != bandStatus { bandStatus = s }
        let snap = bluetooth.snapshot
        if snap != link { link = snap }
        // One band nearby after a short look: connect without asking.
        if case .scanning = snap.state, snap.found.count == 1, Date.now.timeIntervalSince(scanStarted) > 2 {
            scanStarted = .distantFuture
            connectBand(snap.found[0].id)
        }
        if case .recording(let task) = taskState { pollTask(task) }

        guard speakState == .listening, autoStopSeconds > 0 else { return }
        // Stop after `autoStopSeconds` of quiet once speech has started, or
        // after a short pause once the words are already clear.
        let voicing: Bool
        if listeningSource == .phone {
            // Voice is 10 dB above the room's usual noise (its 20th percentile
            // so far), so steady background noise doesn't keep listening open.
            let db = phoneMic.levelDb
            phoneLevels.append(db)
            let floor = phoneLevels.sorted()[phoneLevels.count / 5]
            voicing = phoneLevels.count > 5 && db > max(floor + 10, -65)
        } else {
            voicing = l.isVoicing
        }
        if voicing { listenVoiceSeen = true; listenLastVoice = .now }
        let quiet = Date.now.timeIntervalSince(listenLastVoice)
        let elapsed = Date.now.timeIntervalSince(listenStarted)
        // Room noise can keep the level up, so also stop once the recognizer
        // has heard no new words for the same stretch.
        let wordsDone = translator.lastWords.map { Date.now.timeIntervalSince($0) > autoStopSeconds } ?? false
        let done: Bool
        if translator.isConfident {
            // A recognized demo recording: stop just after it finishes playing
            // (they're at most 10 s, so 14 s is a safe cap).
            done = translator.heardEnough || elapsed > 14
        } else {
            done = (listenVoiceSeen && quiet > autoStopSeconds) || wordsDone || elapsed > 25
        }
        if done {
            Self.log.info("listening ends: clip done \(self.translator.heardEnough), no new words \(wordsDone), after \(elapsed, format: .fixed(precision: 1)) s")
            Task { await finishListening() }
        }
    }

    // MARK: Speak flow

    /// The one big button. Idle → listen. Listening → translate and speak.
    /// Speaking → stop speaking.
    func primaryAction() {
        switch speakState {
        case .idle: Task { await startListening() }
        case .listening: Task { await finishListening() }
        case .translating: break
        case .speaking: voice.stop(); speakState = .idle
        }
    }

    func startListening() async {
        guard speakState == .idle else { return }
        if !isStreaming { startStreaming() }
        // A connected band listens through its throat mic; otherwise the iPhone mic.
        let source: MicSource = bandMode == .bluetooth && bandConnected ? .band : .phone
        // Apple's recognizer handles speech that isn't a demo recording; without
        // permission only the demo recordings are understood.
        _ = await AppleSpeech.requestAuthorization()
        do {
            try translator.begin()
            if source == .phone {
                guard await PhoneMic.requestPermission() else { throw PhoneMic.MicError.notAllowed }
                voice.stop()
                // Claim the throat signal before clearing it, so no simulated frame slips in.
                listening.withLock { $0 = .phone }
                streams.reset()
                try phoneMic.start()
            }
        } catch {
            listening.withLock { $0 = nil }
            message = error.localizedDescription
            return
        }
        translator.onPartial = { [weak self] text in self?.partialText = text }
        partialText = ""
        listenStarted = .now
        listenLastVoice = .now
        listenVoiceSeen = false
        phoneLevels = []
        listeningSource = source
        listening.withLock { $0 = source }
        speakState = .listening
        UIAccessibility.post(notification: .announcement, argument: "Listening")
    }

    func finishListening() async {
        guard speakState == .listening else { return }
        stopMic()
        speakState = .translating
        let started = Date.now
        let result = await translator.finish()
        // "Translating…" stays up for a moment, so the words don't just pop in.
        let shown = Date.now.timeIntervalSince(started)
        if shown < 0.7 { try? await Task.sleep(for: .seconds(0.7 - shown)) }
        guard speakState == .translating else { return }
        guard let result else {
            speakState = .idle
            partialText = ""
            message = "Fonos couldn't make out the words. Try again."
            return
        }
        analyzer.addClarity(result.confidence)
        phrasesThisSession += 1
        utterances.insert(Utterance(date: .now, text: result.text, confidence: result.confidence, fromPhrase: false), at: 0)
        partialText = ""
        if speakAutomatically { say(result.text) } else { speakState = .idle }
    }

    func cancelListening() {
        stopMic()
        translator.cancel()
        partialText = ""
        speakState = .idle
    }

    private func stopMic() {
        listening.withLock { $0 = nil }
        if listeningSource == .phone {
            phoneMic.stop()
            streams.reset()
        }
        listeningSource = nil
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

    // MARK: Speech check

    /// Starts recording one task. The toy band performs it.
    func startTask(_ task: CheckTask) {
        if speakState == .listening { cancelListening() }
        if !isStreaming { startStreaming() }
        taskFrames.withLock { $0 = [] }
        taskStarted = .now
        taskElapsed = 0
        taskLevel = 0
        taskVoiceSeen = false
        taskLastVoice = .now
        taskFloorDb = 0
        toy.setMode(task.toyMode)
        taskState = .recording(task)
        UIAccessibility.post(notification: .announcement, argument: "Recording")
    }

    /// Ends the recording and measures it.
    func stopTask() {
        guard case .recording(let task) = taskState else { return }
        let frames = taskFrames.withLock { buf -> [SensorFrame] in
            defer { buf = nil }
            return buf ?? []
        }
        toy.setMode(.conversation)
        taskLevel = 0
        let result = TaskResult.analyze(task, frames: frames)
        taskState = .done(result)
        UIAccessibility.post(notification: .announcement, argument: result.measured ? "Done" : "Fonos couldn't measure that one")
    }

    func cancelTask() {
        taskFrames.withLock { $0 = nil }
        toy.setMode(.conversation)
        taskLevel = 0
        taskState = .idle
    }

    func clearTask() { if case .done = taskState { taskState = .idle } }

    func saveCheck(_ record: SpeechCheckRecord) {
        var record = record
        record.isSample = bandMode == .simulated
        checks.add(record)
    }

    /// Live level and the automatic stop: at the task's time limit, or for
    /// tasks that end with the voice, after a stretch of silence once the
    /// voice has started.
    private func pollTask(_ task: CheckTask) {
        taskElapsed = Date.now.timeIntervalSince(taskStarted)
        let recent = taskFrames.withLock { buf in (buf ?? []).suffix(10).map { DSP.dbfs(DSP.rms($0.mic)) } }
        let db = recent.max() ?? -90
        // Map −50…−10 dBFS onto the meter.
        taskLevel = Double(min(max((db + 50) / 40, 0), 1))
        // Voice is 15 dB above the quietest moment of this task, so it works
        // for any band gain (the simulated band's floor is about −50 dBFS).
        taskFloorDb = min(taskFloorDb, db)
        if db > max(taskFloorDb + 15, -60) { taskVoiceSeen = true; taskLastVoice = .now }

        let silence = Date.now.timeIntervalSince(taskLastVoice)
        let silenceLimit: Double = task == .passage ? 3 : 1.5
        if taskElapsed >= task.maxSeconds
            || (task.stopsOnSilence && taskVoiceSeen && silence >= silenceLimit)
            || (!taskVoiceSeen && taskElapsed >= 12) {
            stopTask()
        }
    }

    // MARK: App lifecycle

    func didBecomeActive() { startStreaming() }
    func didEnterBackground() { stopStreaming() }
}
