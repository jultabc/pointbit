// Settings window. Writes through SettingsStore on every change.
import SwiftUI
import ServiceManagement

final class PrefsModel: ObservableObject {
    let store: SettingsStore
    let onChange: (ClickSettings) -> Void
    var playSound: () -> Void = {}
    /// Plays even when Audio is Off (the Play Sound button shown only then).
    var playSoundNow: () -> Void = {}
    @Published var s: ClickSettings {
        didSet {
            store.save(s); onChange(s)
            if s.clickSound != oldValue.clickSound || s.soundShape != oldValue.soundShape || s.soundVolume != oldValue.soundVolume {
                schedulePreview()
            }
        }
    }
    /// Seconds after the last sound change before the preview plays. Only the last of a burst of changes plays.
    var previewDelay = 0.3
    private var preview: DispatchWorkItem?
    /// Plays the click sound once, `previewDelay` after the last sound setting change.
    func schedulePreview() {
        preview?.cancel()
        // Plays even when Audio is Off: a setting change is a request to hear it.
        // Clicks stay silent while Audio is Off.
        let w = DispatchWorkItem { [weak self] in self?.playSound() }
        preview = w
        DispatchQueue.main.asyncAfter(deadline: .now() + previewDelay, execute: w)
    }
    @Published var loginItem = SMAppService.mainApp.status == .enabled
    /// Permission state for window capture, refreshed by the app while capture is on.
    @Published var keysAllowed = true
    @Published var screenAllowed = true
    /// macOS turned the key tap off; it stays off until the feature is turned off and on again.
    @Published var captureStopped = false
    /// Accessibility is granted but the listen-only key tap was refused (Input Monitoring missing).
    @Published var listenMissing = false
    var reopenApp: () -> Void = {}
    init(store: SettingsStore, onChange: @escaping (ClickSettings) -> Void) {
        // Set the wrapper directly: a plain assignment here runs didSet
        // and calls onChange while the app's lazy model is still being created.
        self.store = store; self.onChange = onChange
        _s = Published(initialValue: store.load())
    }
    func color(_ p: WritableKeyPath<ClickSettings, RGBA>) -> Binding<Color> {
        Binding(get: { let c = self.s[keyPath: p]; return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) },
                set: { if let c = NSColor($0).usingColorSpace(.sRGB) {
                    self.s[keyPath: p] = RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent) } })
    }
    /// Back to ClickSettings() and the default sound. Keeps the first-start flag,
    /// window capture, the save folder and the login item.
    func restoreDefaults() {
        let keep = s.hideStartMessage, capture = s.windowCapture, folder = s.saveFolder
        store.reset()
        var d = ClickSettings(); d.hideStartMessage = keep; d.windowCapture = capture; d.saveFolder = folder; s = d
    }
    /// Registers or removes this app as a login item. A failure is shown, not only beeped.
    /// "Requires approval" opens System Settings → Login Items, where the user allows it.
    func setLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch {
            let a = NSAlert(); a.messageText = "Launch on computer startup"
            a.informativeText = error.localizedDescription; a.runModal()
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        loginItem = SMAppService.mainApp.status == .enabled
    }
}

/// Slider that takes keyboard focus on click and moves with the arrow keys (1% of the range, Shift = 10%).
/// A plain NSSlider takes focus only with macOS "Keyboard navigation" turned on.
final class KeySlider: NSSlider {
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self); super.mouseDown(with: e) }
    override func keyDown(with e: NSEvent) {
        let step = (maxValue - minValue) / 100 * (e.modifierFlags.contains(.shift) ? 10 : 1)
        switch e.keyCode {
        case 123, 125: doubleValue = max(minValue, doubleValue - step)   // left, down
        case 124, 126: doubleValue = min(maxValue, doubleValue + step)   // right, up
        default: super.keyDown(with: e); return
        }
        sendAction(action, to: target)
    }
}

/// AppKit slider with tick marks (SwiftUI Slider has none).
struct TickSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    func makeNSView(context: Context) -> NSSlider {
        let s = KeySlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                          target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        s.numberOfTickMarks = 10; s.tickMarkPosition = .below; s.isContinuous = true
        return s
    }
    func updateNSView(_ s: NSSlider, context: Context) {
        s.doubleValue = value; s.isEnabled = context.environment.isEnabled; context.coordinator.parent = self
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: TickSlider
        init(_ p: TickSlider) { parent = p }
        @objc func changed(_ s: NSSlider) { parent.value = s.doubleValue }
    }
}

/// AppKit pop-up for the built-in sound (closes faster than a SwiftUI menu Picker).
struct SoundPopUp: NSViewRepresentable {
    @Binding var value: ClickSoundKind
    func makeNSView(context: Context) -> NSPopUpButton {
        let b = NSPopUpButton(frame: .zero, pullsDown: false)
        b.addItems(withTitles: ClickSoundKind.allCases.map(\.title))
        b.target = context.coordinator; b.action = #selector(Coordinator.changed(_:))
        return b
    }
    func updateNSView(_ b: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        b.selectItem(at: ClickSoundKind.allCases.firstIndex(of: value) ?? 0)
        b.isEnabled = context.environment.isEnabled   // AppKit views do not follow .disabled() by themselves
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: SoundPopUp
        init(_ p: SoundPopUp) { parent = p }
        @objc func changed(_ b: NSPopUpButton) {
            let all = ClickSoundKind.allCases
            if all.indices.contains(b.indexOfSelectedItem) { parent.value = all[b.indexOfSelectedItem] }
        }
    }
}

/// Settings window: a General section (launch at login), a Click Marks section (Visual and Audio boxes side by side),
/// a Capture and Record section, then Restore Defaults.
struct PrefsView: View {
    @ObservedObject var m: PrefsModel
    private let labelWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            section("General") { GroupBox {
                Toggle("Launch on computer startup", isOn: Binding(get: { m.loginItem }, set: { m.setLogin($0) }))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            } }
            section("Click Marks") {
                HStack(alignment: .top, spacing: 12) {
                    GroupBox { visual.padding(12).frame(maxWidth: .infinity) }
                    GroupBox { audio.padding(12).frame(maxWidth: .infinity) }
                }
            }
            section("Capture and Record") {
                GroupBox { capture.padding(12).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Button("Restore Defaults") { m.restoreDefaults() }
        }
        .padding(20)
        .frame(width: 760)
    }

    /// A titled part of the window: a heading over its boxes.
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The ⌘ ⌘ shortcuts: the switch, what each letter does, and the permissions they need.
    private var capture: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Turn on ⌘ ⌘ + T / A / C / S", isOn: $m.s.windowCapture)
                Text("Tap ⌘ twice, then press a letter. The window or screen under the pointer is used.")
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 20)
                Toggle("Copy the file path when it ends", isOn: $m.s.copyPath)
                Text("Paste it into a terminal or an agent's chat to share the file.")
                    .fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary).padding(.leading, 20)
                if m.s.windowCapture {
                    permission("Accessibility (keys)", ok: m.keysAllowed) {
                        Button("Open Settings") { CapturePermissions.openAccessibilitySettings() }
                    }
                    if m.listenMissing {
                        permission("Input Monitoring", ok: false) {
                            Button("Open Settings") { CapturePermissions.openInputMonitoringSettings() }
                        }
                    }
                    if m.captureStopped {
                        Text("macOS stopped the key capture. Turn this off and on to start it again.")
                            .fixedSize(horizontal: false, vertical: true).foregroundStyle(.red).padding(.leading, 20)
                    }
                    permission("Screen Recording", ok: m.screenAllowed) {
                        Button("Open Settings") { CapturePermissions.openScreenRecordingSettings() }
                        Button("Reopen App") { m.reopenApp() }
                    }
                } else {
                    Text("Off: the app does not watch the keyboard.").foregroundStyle(.secondary).padding(.leading, 20)
                }
            }
            .frame(width: 300, alignment: .leading)
            VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                key("C", "Picture of the window", "File and clipboard")
                key("S", "Picture of the whole screen", "File and clipboard")
                key("T", "Start or stop recording the window", m.s.copyPath ? "File and clipboard" : "File")
                key("A", "Start or stop recording the whole screen", m.s.copyPath ? "File and clipboard" : "File")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Save to:")
                    Button("Choose…") { if let p = SaveFolder.choose() { m.s.saveFolder = p } }
                    if !m.s.saveFolder.isEmpty { Button("Desktop") { m.s.saveFolder = "" } }
                }
                // The folder on its own line: a chosen path can be long.
                Text(SaveFolder.display(m.s.saveFolder)).lineLimit(2).truncationMode(.middle)
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .help(SaveFolder.resolve(m.s.saveFolder).path)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One shortcut row: the letter as a key cap, what it does, and where the file goes.
    private func key(_ letter: String, _ action: String, _ result: String) -> some View {
        GridRow {
            Text("⌘ ⌘ \(letter)").font(.body.monospaced())
            Text(action)
            Text(result).foregroundStyle(.secondary)
        }
    }

    /// One permission line: ✓ or ✗, its name, and buttons shown only while it is missing.
    private func permission<B: View>(_ name: String, ok: Bool, @ViewBuilder buttons: () -> B) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
            Text(name)
            if !ok { buttons() }
        }
        .padding(.leading, 20)
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).frame(width: labelWidth, alignment: .trailing)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Slider with end labels and the current value at the right.
    private func slider(_ v: Binding<Double>, _ r: ClosedRange<Double>, _ lo: String, _ hi: String,
                        _ show: @escaping (Double) -> String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                TickSlider(value: v, range: r)
                HStack { Text(lo); Spacer(); Text(hi) }.font(.caption2)
            }
            Text(show(v.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 52, alignment: .trailing).padding(.top, 2)
        }
    }

    private func onOff(_ b: Binding<Bool>) -> some View {
        Picker("", selection: b) { Text("On").tag(true); Text("Off").tag(false) }
            .pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
    }

    private func well(_ p: WritableKeyPath<ClickSettings, RGBA>, _ name: String) -> some View {
        VStack(spacing: 2) { ColorPicker(name, selection: m.color(p)).labelsHidden(); Text(name).font(.caption2) }
    }

    private var visual: some View {
        VStack(alignment: .leading, spacing: 18) {
            row("Visual Effect:") { onOff($m.s.visualFeedback) }
            row("Size:") { slider($m.s.diameter, markDiameterRange, "Small", "Large") { String(format: "%.0f pt", $0) } }
            row("Duration:") { slider($m.s.seconds, markSecondsRange, "Short", "Long") { String(format: "%.2f s", $0) } }
            row("Colors:") {
                HStack(spacing: 18) {
                    VStack(spacing: 2) { HStack { well(\.leftInner, "Inner"); well(\.leftOuter, "Outer") }; Text("Left Click").font(.caption2) }
                    VStack(spacing: 2) { HStack { well(\.rightInner, "Inner"); well(\.rightOuter, "Outer") }; Text("Right Click").font(.caption2) }
                }
            }
        }
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 18) {
            row("Audio:") {
                HStack(spacing: 12) {
                    onOff($m.s.playSound).fixedSize()
                    // Audio Off: a button beside Off plays the sound without changing a setting.
                    if !m.s.playSound { Button("Play Sound") { m.playSoundNow() } }
                }
            }
            row("Click Sound:") { SoundPopUp(value: $m.s.clickSound).fixedSize() }
            // Shown only for sounds the sliders change (hidden for TACS and Tink).
            if m.s.clickSound.adjustable {
                row("Pitch:") { slider($m.s.soundShape.pitch, SoundShape.pitchRange, "Low", "High") { String(format: "%.2f×", $0) } }
                row("Brightness:") { slider($m.s.soundShape.brightness, SoundShape.brightnessRange, "Dark", "Bright") { String(format: "%.2f×", $0) } }
                row("Ring:") { slider($m.s.soundShape.ring, SoundShape.ringRange, "Short", "Long") { String(format: "%.2f×", $0) } }
                row("") { Button("Reset Sound Shape") { m.s.soundShape = SoundShape() } }
            }
            row("Volume:") { slider($m.s.soundVolume, 0...1, "Soft", "Loud") { String(format: "%.0f%%", $0 * 100) } }
        }
    }
}
