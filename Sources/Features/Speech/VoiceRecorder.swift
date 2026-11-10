import AVFoundation
import Observation
import Speech
import SwiftUI

struct RecordedAudio {
    let data: Data
    let duration: Double
    let transcript: String
}

enum SpeechSetupError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case unavailable
    case noCompatibleFormat
    case assetsUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "没有麦克风权限，请到设置中开启"
        case .speechDenied: "没有语音识别权限，请到设置中开启"
        case .unavailable: "当前设备暂不支持语音转写"
        case .noCompatibleFormat: "无法准备音频格式"
        case .assetsUnavailable: "语音模型尚未安装，已切换系统识别"
        }
    }
}

/// Owns the real-time audio tap state. Access is serialized by the audio tap
/// thread, hence `@unchecked Sendable`.
final class AudioPipeline: @unchecked Sendable {
    var audioFile: AVAudioFile?
    var converter: AVAudioConverter?
    var analyzerFormat: AVAudioFormat?
    var continuation: AsyncStream<AnalyzerInput>.Continuation?
    var fallbackRequest: SFSpeechAudioBufferRecognitionRequest?

    func handle(_ buffer: AVAudioPCMBuffer) {
        try? audioFile?.write(from: buffer)
        if let fallbackRequest {
            fallbackRequest.append(buffer)
            return
        }
        guard let analyzerFormat, let continuation else { return }
        let converted = converter?.convert(buffer, to: analyzerFormat) ?? buffer
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func finish() {
        continuation?.finish()
        continuation = nil
        fallbackRequest?.endAudio()
        fallbackRequest = nil
    }
}

extension AVAudioConverter {
    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / max(1, buffer.format.sampleRate)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var delivered = false
        var conversionError: NSError?
        let status = convert(to: output, error: &conversionError) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status == .haveData, output.frameLength > 0 else { return nil }
        return output
    }
}

@MainActor
@Observable
final class VoiceRecorder {
    var isRecording = false
    var isPaused = false
    var isPreparing = false
    var elapsed: TimeInterval = 0
    var finalText = ""
    var volatileText = ""
    var levels: [CGFloat] = Array(repeating: 0.12, count: 36)
    var errorMessage: String?
    var usesAnalyzer = false

    var displayText: String {
        (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ObservationIgnored var onTranscript: ((String) -> Void)?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private let pipeline = AudioPipeline()
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var transcriber: SpeechTranscriber?
    @ObservationIgnored private var resultTask: Task<Void, Never>?
    @ObservationIgnored private var fallbackTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var levelCounter = 0
    @ObservationIgnored private var cancelled = false

    func start() async {
        guard !isRecording, !isPreparing else { return }
        cancelled = false
        errorMessage = nil
        finalText = ""
        volatileText = ""
        elapsed = 0
        levels = Array(repeating: 0.12, count: 36)
        usesAnalyzer = false
        isPreparing = true
        defer { isPreparing = false }

        do {
            try await requestPermissions()
            guard !cancelled else { cleanup(); return }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true, options: [])

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0 else { throw SpeechSetupError.noCompatibleFormat }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lumen-recording-\(UUID().uuidString).caf")
            audioURL = url
            pipeline.audioFile = try AVAudioFile(
                forWriting: url,
                settings: inputFormat.settings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )
            audioEngine = engine

            if #available(iOS 26.0, *) {
                do {
                    try await prepareAnalyzer(inputFormat: inputFormat)
                    usesAnalyzer = true
                } catch {
                    usesAnalyzer = false
                    try prepareFallback()
                }
            } else {
                try prepareFallback()
            }
            guard !cancelled else {
                pipeline.finish()
                cleanup()
                return
            }

            let pipeline = self.pipeline
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                pipeline.handle(buffer)
                let level = Self.rms(buffer)
                Task { @MainActor [weak self] in
                    self?.appendLevel(level)
                }
            }
            engine.prepare()
            try engine.start()

            isRecording = true
            isPaused = false
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
            cleanup()
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        audioEngine?.pause()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused else { return }
        do {
            try audioEngine?.start()
            isPaused = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async -> RecordedAudio? {
        guard isRecording else { return nil }
        isRecording = false
        timerTask?.cancel()
        timerTask = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        pipeline.finish()

        if #available(iOS 26.0, *), let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        if let resultTask {
            await resultTask.value
        }
        resultTask = nil
        fallbackTask?.cancel()
        fallbackTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        var data = Data()
        if let audioURL {
            data = (try? Data(contentsOf: audioURL)) ?? Data()
            try? FileManager.default.removeItem(at: audioURL)
        }
        let result = RecordedAudio(data: data, duration: elapsed, transcript: displayText)
        cleanup(keepText: true)
        return result
    }

    func cancel() {
        cancelled = true
        isRecording = false
        timerTask?.cancel()
        timerTask = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        pipeline.finish()
        resultTask?.cancel()
        fallbackTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        cleanup(keepText: false)
    }

    // MARK: - Analyzer

    @available(iOS 26.0, *)
    private func prepareAnalyzer(inputFormat: AVAudioFormat) async throws {
        guard SpeechTranscriber.isAvailable else { throw SpeechSetupError.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw SpeechSetupError.unavailable
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw SpeechSetupError.assetsUnavailable
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: inputFormat
        ) else {
            throw SpeechSetupError.noCompatibleFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        if format.sampleRate != inputFormat.sampleRate || format.channelCount != inputFormat.channelCount {
            pipeline.converter = AVAudioConverter(from: inputFormat, to: format)
        }
        pipeline.analyzerFormat = format
        self.transcriber = transcriber
        self.analyzer = analyzer

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        pipeline.continuation = continuation
        try await analyzer.start(inputSequence: stream)

        resultTask = Task { [weak self] in
            guard let transcriber = self?.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalText += text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                    self.onTranscript?(self.displayText)
                }
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareFallback() throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            throw SpeechSetupError.unavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        pipeline.fallbackRequest = request
        fallbackTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finalText = text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                    self.onTranscript?(self.displayText)
                }
                if let error, self.isRecording {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Levels

    private nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let value = sqrt(sum / Float(count))
        return CGFloat(min(1, max(0.03, value * 8)))
    }

    private func appendLevel(_ level: CGFloat) {
        levelCounter += 1
        guard levelCounter % 2 == 0 else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.isRecording, !self.isPaused else { continue }
                self.elapsed += 0.2
            }
        }
    }

    private func cleanup(keepText: Bool = false) {
        audioEngine = nil
        audioURL = nil
        analyzer = nil
        transcriber = nil
        resultTask = nil
        fallbackTask = nil
        pipeline.audioFile = nil
        pipeline.converter = nil
        pipeline.analyzerFormat = nil
        pipeline.continuation = nil
        pipeline.fallbackRequest = nil
        isPaused = false
        if !keepText {
            finalText = ""
            volatileText = ""
            elapsed = 0
        }
    }

    private func requestPermissions() async throws {
        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard mic else { throw SpeechSetupError.microphoneDenied }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else { throw SpeechSetupError.speechDenied }
    }
}
