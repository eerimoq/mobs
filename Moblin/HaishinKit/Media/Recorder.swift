import AVFoundation

protocol IORecorderDelegate: AnyObject {
    func recorderFinished()
    func recorderError()
}

private let lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.IORecorder.lock")

class Recorder: NSObject, AVAssetWriterDelegate {
    private static let defaultAudioOutputSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 0,
        AVNumberOfChannelsKey: 0,
    ]

    private static let defaultVideoOutputSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoHeightKey: 0,
        AVVideoWidthKey: 0,
    ]

    weak var delegate: (any IORecorderDelegate)?
    var audioOutputSettings = Recorder.defaultAudioOutputSettings
    var videoOutputSettings = Recorder.defaultVideoOutputSettings
    var url: URL?
    private var fileHandle: FileHandle?
    private var outputChannelsMap: [Int: Int] = [0: 0, 1: 1]

    private func isReadyForStartWriting() -> Bool {
        return writer?.inputs.count == 2
    }

    private var writer: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioConverter: AVAudioConverter?
    private var basePresentationTimeStamp: CMTime = .zero

    func setAudioChannelsMap(map: [Int: Int]) {
        lockQueue.async {
            self.outputChannelsMap = map
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        lockQueue.async {
            self.appendAudioInner(sampleBuffer)
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        lockQueue.async {
            self.appendVideoInner(sampleBuffer)
        }
    }

    func startRunning() {
        lockQueue.async {
            self.startRunningInner()
        }
    }

    func stopRunning() {
        lockQueue.async {
            self.stopRunningInner()
        }
    }

    private func appendAudioInner(_ sampleBuffer: CMSampleBuffer) {
        guard let writer else {
            return
        }
        guard let sampleBuffer = convert(sampleBuffer) else {
            return
        }
        guard
            let input = makeAudioWriterInput(sourceFormatHint: sampleBuffer.formatDescription),
            isReadyForStartWriting()
        else {
            return
        }
        start(writer: writer, presentationTimeStamp: sampleBuffer.presentationTimeStamp)
        guard input.isReadyForMoreMediaData else {
            return
        }
        guard let sampleBuffer = sampleBuffer
            .replacePresentationTimeStamp(sampleBuffer.presentationTimeStamp - basePresentationTimeStamp)
        else {
            return
        }
        if !input.append(sampleBuffer) {
            logger.info("""
            recorder: audio: Append failed with \(writer.error?.localizedDescription ?? "") \
            (status: \(writer.status))
            """)
            stopRunningInner()
        }
    }

    private func convert(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let converter = makeAudioConverter(sampleBuffer.formatDescription) else {
            return nil
        }
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: UInt32(sampleBuffer.numSamples)
        ) else {
            return nil
        }
        return try? sampleBuffer.withAudioBufferList { list, _ in
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.inputFormat,
                bufferListNoCopy: list.unsafePointer
            ) else {
                logger.info("recorder: Failed to create input buffer")
                return nil
            }
            do {
                try converter.convert(to: outputBuffer, from: inputBuffer)
            } catch {
                logger.info("recorder: audio: Convert failed with \(error.localizedDescription)")
                return nil
            }
            return outputBuffer.makeSampleBuffer(presentationTimeStamp: sampleBuffer.presentationTimeStamp)
        }
    }

    private func appendVideoInner(_ sampleBuffer: CMSampleBuffer) {
        guard let writer else {
            return
        }
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }
        guard
            let input = makeVideoWriterInput(width: pixelBuffer.width, height: pixelBuffer.height),
            isReadyForStartWriting()
        else {
            return
        }
        start(writer: writer, presentationTimeStamp: sampleBuffer.presentationTimeStamp)
        guard input.isReadyForMoreMediaData else {
            logger.info("recorder: video: Not ready")
            return
        }
        guard let sampleBuffer = sampleBuffer
            .replacePresentationTimeStamp(sampleBuffer.presentationTimeStamp - basePresentationTimeStamp)
        else {
            return
        }
        if !input.append(sampleBuffer) {
            logger.info("""
            recorder: video: Append failed with \(writer.error?.localizedDescription ?? "") \
            (status: \(writer.status))
            """)
            stopRunningInner()
        }
    }

    private func createAudioWriterInput(sourceFormatHint: CMFormatDescription?) -> AVAssetWriterInput? {
        var outputSettings: [String: Any] = [:]
        if let sourceFormatHint, let inSourceFormat = sourceFormatHint.streamBasicDescription?.pointee {
            for (key, value) in audioOutputSettings {
                switch key {
                case AVSampleRateKey:
                    outputSettings[key] = isZero(value) ? inSourceFormat.mSampleRate : value
                case AVNumberOfChannelsKey:
                    outputSettings[key] = isZero(value) ? min(Int(inSourceFormat.mChannelsPerFrame), 2) :
                        value
                default:
                    outputSettings[key] = value
                }
            }
        }
        return makeWriterInput(.audio, outputSettings, sourceFormatHint: sourceFormatHint)
    }

    private func makeAudioWriterInput(sourceFormatHint: CMFormatDescription?) -> AVAssetWriterInput? {
        if audioWriterInput == nil {
            audioWriterInput = createAudioWriterInput(sourceFormatHint: sourceFormatHint)
        }
        return audioWriterInput
    }

    private func createVideoWriterInput(width: Int, height: Int) -> AVAssetWriterInput? {
        var outputSettings: [String: Any] = [:]
        for (key, value) in videoOutputSettings {
            switch key {
            case AVVideoHeightKey:
                outputSettings[key] = isZero(value) ? height : value
            case AVVideoWidthKey:
                outputSettings[key] = isZero(value) ? width : value
            default:
                outputSettings[key] = value
            }
        }
        return makeWriterInput(.video, outputSettings, sourceFormatHint: nil)
    }

    private func makeVideoWriterInput(width: Int, height: Int) -> AVAssetWriterInput? {
        if videoWriterInput == nil {
            videoWriterInput = createVideoWriterInput(width: width, height: height)
        }
        return videoWriterInput
    }

    private func makeWriterInput(_ mediaType: AVMediaType,
                                 _ outputSettings: [String: Any],
                                 sourceFormatHint: CMFormatDescription?) -> AVAssetWriterInput?
    {
        var input: AVAssetWriterInput?
        input = AVAssetWriterInput(
            mediaType: mediaType,
            outputSettings: outputSettings,
            sourceFormatHint: sourceFormatHint
        )
        input?.expectsMediaDataInRealTime = true
        if let input {
            writer?.add(input)
        }
        return input
    }

    private func makeAudioConverter(_ formatDescription: CMFormatDescription?) -> AVAudioConverter? {
        guard audioConverter == nil else {
            return audioConverter
        }
        guard var streamBasicDescription = formatDescription?.streamBasicDescription?.pointee else {
            return nil
        }
        guard let inputFormat = makeAudioFormat(&streamBasicDescription) else {
            return nil
        }
        let outputNumberOfChannels = min(inputFormat.channelCount, 2)
        let outputFormat = AVAudioFormat(
            commonFormat: inputFormat.commonFormat,
            sampleRate: inputFormat.sampleRate,
            channels: outputNumberOfChannels,
            interleaved: inputFormat.isInterleaved
        )!
        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        audioConverter?.channelMap = makeChannelMap(
            numberOfInputChannels: Int(inputFormat.channelCount),
            numberOfOutputChannels: Int(outputNumberOfChannels),
            outputToInputChannelsMap: outputChannelsMap
        )
        return audioConverter
    }

    private func makeChannelLayout(_ numberOfChannels: UInt32) -> AVAudioChannelLayout? {
        guard numberOfChannels > 2 else {
            return nil
        }
        return AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | numberOfChannels)
    }

    private func makeAudioFormat(_ basicDescription: inout AudioStreamBasicDescription) -> AVAudioFormat? {
        if basicDescription.mFormatID == kAudioFormatLinearPCM,
           kLinearPCMFormatFlagIsBigEndian ==
           (basicDescription.mFormatFlags & kLinearPCMFormatFlagIsBigEndian)
        {
            // ReplayKit audioApp.
            guard basicDescription.mBitsPerChannel == 16 else {
                return nil
            }
            if let layout = makeChannelLayout(basicDescription.mChannelsPerFrame) {
                return .init(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: basicDescription.mSampleRate,
                    interleaved: true,
                    channelLayout: layout
                )
            }
            return AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: basicDescription.mSampleRate,
                channels: basicDescription.mChannelsPerFrame,
                interleaved: true
            )
        }
        if let layout = makeChannelLayout(basicDescription.mChannelsPerFrame) {
            return .init(streamDescription: &basicDescription, channelLayout: layout)
        }
        return .init(streamDescription: &basicDescription)
    }

    private func startRunningInner() {
        guard writer == nil, let url else {
            logger.info("recorder: Will not start recording as it is already running or missing URL")
            return
        }
        reset()
        writer = AVAssetWriter(contentType: UTType(AVFileType.mp4.rawValue)!)
        try? Data().write(to: url)
        fileHandle = FileHandle(forWritingAtPath: url.path)
    }

    private func stopRunningInner() {
        guard let writer else {
            logger.info("recorder: Will not stop recording as it is not running")
            return
        }
        guard writer.status == .writing else {
            logger.info("recorder: Failed to finish writing \(writer.error?.localizedDescription ?? "")")
            reset()
            delegate?.recorderError()
            return
        }
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        writer.finishWriting {
            self.delegate?.recorderFinished()
            self.reset()
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
    }

    private func reset() {
        writer = nil
        audioWriterInput = nil
        videoWriterInput = nil
    }

    private func start(writer: AVAssetWriter, presentationTimeStamp: CMTime) {
        guard writer.status == .unknown else {
            return
        }
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 5, preferredTimescale: 1)
        writer.delegate = self
        writer.initialSegmentStartTime = .zero
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        basePresentationTimeStamp = presentationTimeStamp
    }
}

extension Recorder {
    func assetWriter(
        _: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType _: AVAssetSegmentType
    ) {
        lockQueue.async {
            self.fileHandle?.write(segmentData)
        }
    }
}
