import AVFoundation
import SwiftUI
import UnderstudyCore

/// "Add step": build a step by hand (open an app, press keys, type, wait, open a link).
struct AddStepView: View {
    @ObservedObject var ui: WorkspaceState
    @ObservedObject var keys = KeyCapture.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Step", selection: $ui.addKind) {
                ForEach(ManualStep.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }.frame(maxWidth: 300)
            switch ui.addKind {
            case .openApp: appPicker
            case .keys:
                HStack {
                    Button(keys.listening ? "Press the keys now…" : ui.addKeys.isEmpty ? "Record keys" : "Record again") {
                        keys.capture { text, code in ui.addKeys = text; ui.addKeyCode = code }
                    }
                    Text(ui.addKeys.isEmpty ? "" : ui.addKeys).font(.system(.body, design: .monospaced))
                }
                appPicker
            case .type:
                TextField("Text to type (use {name} for a value asked when it runs)", text: $ui.addText).textFieldStyle(.roundedBorder)
                appPicker
            case .waitText:
                TextField("Text to wait for", text: $ui.addText).textFieldStyle(.roundedBorder)
                appPicker
            case .waitSeconds:
                Stepper("\(ui.addSeconds) seconds", value: $ui.addSeconds, in: 1...300).frame(maxWidth: 200)
            case .openLink:
                TextField("https://…, spotify:…, or a file path", text: $ui.addText).textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Cancel") { ui.adding = nil; keys.stop() }
                Button("Add step") { ui.finishAdding(); keys.stop() }.buttonStyle(.borderedProminent).disabled(ui.newStep == nil)
            }
        }
        .padding(12).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var appPicker: some View {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
        return Picker("App", selection: Binding(get: { ui.addApp }, set: { bundle in
            ui.addApp = bundle
            ui.addAppName = apps.first { $0.0 == bundle }?.1 ?? ""
        })) {
            Text(ui.addKind == .openApp ? "Choose an open app" : "The app in front").tag("")
            ForEach(apps, id: \.0) { Text($0.1).tag($0.0) }
        }.frame(maxWidth: 300)
    }
}

/// Records the next key press in Understudy's window, as Watch names keys ("⌘K", "↩", "E").
@MainActor
final class KeyCapture: ObservableObject {
    static let shared = KeyCapture()
    @Published private(set) var listening = false
    private var monitor: Any?

    func capture(_ done: @escaping (String, Int) -> Void) {
        stop()
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Modifier-only presses wait for the key that goes with them.
            done(ActionMonitor.keysText(event), Int(event.keyCode))
            self?.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        listening = false
    }
}

/// Frames of a recording's video at a step's moment, made once and kept next to the recording.
@MainActor
final class StepFrames: ObservableObject {
    static let shared = StepFrames()
    @Published private var images: [String: NSImage] = [:]
    private var requested: Set<String> = []

    func image(recording: UUID?, at time: String?) -> NSImage? {
        guard let recording, let time, let seconds = Double(time) else { return nil }
        let key = "\(recording.uuidString)@\(time)"
        if let image = images[key] { return image }
        guard !requested.contains(key) else { return nil }
        requested.insert(key)
        let folder = AppEnvironment.recordings.appendingPathComponent(recording.uuidString)
        let cached = folder.appendingPathComponent("frames/\(time).jpg")
        if let image = NSImage(contentsOf: cached) {
            DispatchQueue.main.async { self.images[key] = image }   // not during a view update
            return image
        }
        let video = folder.appendingPathComponent("screen.mov")
        guard FileManager.default.fileExists(atPath: video.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        generator.generateCGImageAsynchronously(for: CMTime(seconds: max(0, seconds), preferredTimescale: 600)) { cgImage, _, _ in
            guard let cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])?.write(to: cached)
            let image = NSImage(cgImage: cgImage, size: .zero)
            DispatchQueue.main.async { self.images[key] = image }
        }
        return nil
    }
}
