import AVFoundation
import ScreenCaptureKit

/// Records the screen to a video file while Watch runs. The person chooses what to record in
/// macOS's own picker (a display, a window, or an app), so Understudy never holds blanket Screen
/// Recording access, and macOS shows its recording indicator the whole time.
final class ScreenRecorder: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Frames per second. Enough to see each click and field change; small files.
    static let frameRate: Int32 = 10
    /// The longer side of the video, in pixels.
    static let maxSide = 1920.0

    private let url: URL
    private let queue = DispatchQueue(label: "app.understudy.screen-recorder")
    // Touched only on `queue` once capture starts.
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var wroteFrames = false
    // Touched only on the main thread.
    private var ready: ((Error?) -> Void)?

    init(url: URL) { self.url = url }

    /// Shows the picker, then starts recording what the person chose. `ready` runs on the main thread.
    @MainActor
    func start(ready: @escaping (Error?) -> Void) {
        self.ready = ready
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay, .singleWindow, .singleApplication]
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    /// Stops recording and finishes the file. `done` gets the file name, or nil if nothing was recorded.
    @MainActor
    func stop(done: @escaping (String?) -> Void) {
        closePicker()
        ready = nil
        queue.async { [self] in
            guard let stream else { return finish(done) }
            self.stream = nil
            stream.stopCapture { _ in self.queue.async { self.finish(done) } }
        }
    }

    // MARK: Picker

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async { [self] in
            guard ready != nil else { return }
            closePicker()
            begin(filter)
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { [self] in
            closePicker()
            report(CaptureError(message: "Watch didn't start: nothing was chosen to record."))
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { [self] in
            closePicker()
            report(CaptureError(message: "macOS couldn't show the screen picker: \(error.localizedDescription)"))
        }
    }

    @MainActor
    private func closePicker() {
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
    }

    @MainActor
    private func report(_ error: Error?) {
        let ready = self.ready
        self.ready = nil
        ready?(error)
    }

    // MARK: Capture

    @MainActor
    private func begin(_ filter: SCContentFilter) {
        let scale = Double(filter.pointPixelScale)
        let size = CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale)
        let fit = min(1, Self.maxSide / max(size.width, size.height, 1))
        // Even dimensions keep the HEVC encoder happy.
        let width = Int(size.width * fit) / 2 * 2, height = Int(size.height * fit) / 2 * 2
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.frameRate)
        configuration.showsCursor = true
        configuration.queueDepth = 6
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CaptureError(message: "The video file couldn't be prepared.") }
            writer.add(input)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            queue.sync { self.writer = writer; self.input = input; self.stream = stream }
            stream.startCapture { error in
                DispatchQueue.main.async { self.report(error) }
            }
        } catch {
            report(error)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Runs on `queue`. Frames without new content (the screen didn't change) carry no image.
        guard type == .screen, sampleBuffer.isValid, let writer, let input,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !wroteFrames {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            wroteFrames = true
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // The person stopped sharing from the menu bar, or the window closed. What was recorded is kept.
        queue.async { self.stream = nil }
    }

    /// Runs on `queue`.
    private func finish(_ done: @escaping (String?) -> Void) {
        guard let writer, let input, wroteFrames else {
            self.writer?.cancelWriting()
            self.writer = nil; self.input = nil
            return DispatchQueue.main.async { done(nil) }
        }
        self.writer = nil; self.input = nil
        input.markAsFinished()
        writer.finishWriting { [url] in
            let name = writer.status == .completed ? url.lastPathComponent : nil
            DispatchQueue.main.async { done(name) }
        }
    }
}
