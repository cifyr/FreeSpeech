import AVFoundation
import FreeSpeechCore

// Headless mode for mechanical verification: model-load and transcription timing
// against a known audio file, no GUI, no permissions needed.
enum TranscribeFileCommand {
    static func run(arguments: [String]) -> Int32 {
        guard let flagIndex = arguments.firstIndex(of: "--transcribe-file"),
              arguments.count > flagIndex + 1 else {
            FileHandle.standardError.write(Data("usage: FreeSpeech --transcribe-file <audio> [--model <name>]\n".utf8))
            return 2
        }
        let path = arguments[flagIndex + 1]
        var modelName = Settings().modelName
        if let modelIndex = arguments.firstIndex(of: "--model"), arguments.count > modelIndex + 1 {
            modelName = arguments[modelIndex + 1]
        }

        do {
            let samples = try loadSamples(path: path)
            let engine = WhisperCppEngine()

            let loadStart = CFAbsoluteTimeGetCurrent()
            try engine.loadModel(at: AppPaths.modelFile(named: modelName))
            let loadTime = CFAbsoluteTimeGetCurrent() - loadStart

            let start = CFAbsoluteTimeGetCurrent()
            let raw = try engine.transcribe(samples: samples, timeout: 120)
            let transcribeTime = CFAbsoluteTimeGetCurrent() - start

            let cleaned = TranscriptCleaner.clean(raw) ?? ""
            print("model: \(modelName)")
            print(String(format: "model_load_s: %.3f", loadTime))
            print(String(format: "audio_s: %.1f", Double(samples.count) / Double(WhisperCppEngine.sampleRate)))
            print(String(format: "transcribe_s: %.3f", transcribeTime))
            print("transcript: \(cleaned)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func loadSamples(path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioRecorderError.converterInitFailed
        }
        try file.read(into: buffer)

        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(WhisperCppEngine.sampleRate),
            channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw AudioRecorderError.converterInitFailed
        }
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * target.sampleRate / format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw AudioRecorderError.converterInitFailed
        }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw error ?? AudioRecorderError.converterInitFailed
        }
        guard let channel = out.floatChannelData?[0] else {
            throw AudioRecorderError.converterInitFailed
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}
