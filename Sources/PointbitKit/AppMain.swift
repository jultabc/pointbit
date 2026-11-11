// Pointbit — shows a mark (and optional sound) where the mouse is clicked.
// Menu bar app: Quit from the menu bar icon. No exit codes beyond 0 (normal quit).
// runApp() is the only public entry; Sources/Pointbit/main.swift calls it.
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = SettingsStore()
    lazy var model: PrefsModel = {
        let m = PrefsModel(store: store) { [weak self] s in self?.reloadSound(s); self?.capture.apply(s) }
        m.playSound = { [weak self] in self?.play(force: true) }   // preview after a sound setting change, also when Audio is Off
        m.playSoundNow = { [weak self] in self?.play(force: true) }   // Play Sound button, shown when Audio is Off
        m.reopenApp = { [weak self] in self?.reopen() }
        return m
    }()
    let overlay = ClickOverlay()
    lazy var capture = CaptureController(model: model, overlay: overlay,
                                         prefsVisible: { [weak self] in self?.prefs?.isVisible == true },
                                         showPrefs: { [weak self] in self?.openPrefs() })
    var item: NSStatusItem!
    let clock = RecordingClock()   // the seconds in the menu bar while recording
    var prefs: NSWindow?
    var sound: NSSound?
    var monitors: [Any] = []
    var visualItem: NSMenuItem!, soundItem: NSMenuItem!, stopRecordingItem: NSMenuItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        // `--transcribe <file.mov>`: writes the .txt for a recording made earlier (Record my voice), then quits.
        // Runs as its own copy (open -n), so the one-copy rule below does not apply to it.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count {
            let video = URL(fileURLWithPath: args[i + 1]), language = model.s.voiceLanguage
            Task { @MainActor in
                let text = await Transcript.write(for: video, language: language)
                if text == nil { NSSound.beep() }
                NSApp.terminate(nil)
            }
            return
        }
        // One copy only: a second copy (another path, same bundle id) would draw every mark twice.
        // The copy with the smallest PID stays, so two copies started at once do not both quit.
        let me = NSRunningApplication.current.processIdentifier
        let others = { NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me } }
        // Started by reopen() with the old copy's PID: wait up to 3 s for that process to be gone, then skip the
        // one-copy check (the old copy is the one this copy replaces).
        if let i = args.firstIndex(of: Self.reopenedArgument), i + 1 < args.count, let old = pid_t(args[i + 1]) {
            let until = Date().addingTimeInterval(3)
            while kill(old, 0) == 0 && Date() < until { usleep(50_000) }
        } else if others().contains(where: { $0.processIdentifier < me }) { NSApp.terminate(nil); return }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AppIcon.menuBar()
        let menu = NSMenu(); menu.delegate = self
        // accessory app: no responder chain finds the delegate, so every item gets target = self
        // Shown only while recording: a way to stop that does not depend on the ⌘ ⌘ keys.
        stopRecordingItem = menu.addItem(withTitle: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        stopRecordingItem.target = self; stopRecordingItem.isHidden = true
        menu.addItem(withTitle: "About \(appName)", action: #selector(about), keyEquivalent: "").target = self
        menu.addItem(.separator())
        visualItem = menu.addItem(withTitle: "Show Visual Feedback", action: #selector(toggleVisual), keyEquivalent: "")
        soundItem = menu.addItem(withTitle: "Play Click Sound", action: #selector(toggleSound), keyEquivalent: "")
        visualItem.target = self; soundItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openPrefs), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        NSApp.applicationIconImage = AppIcon.app(size: 512)
        reloadSound(model.s)
        capture.recording.onRecording = { [weak self] on in
            guard let self else { return }
            if on { self.clock.start(in: self.item) } else { self.clock.stop(showing: AppIcon.menuBar()) }
            self.stopRecordingItem.isHidden = !on
        }
        capture.apply(model.s)
        // Preferences open by themselves only on the first start; later only from the menu (or --settings).
        if !model.s.hideStartMessage { model.s.hideStartMessage = true; openPrefs() }
        else if CommandLine.arguments.contains("--settings") { openPrefs() }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in self?.clicked(e) } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in self?.clicked(e); return e } as Any)
    }

    /// Quitting while recording: finish the video file first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard capture.recording.isActive else { return .terminateNow }
        capture.recording.stop { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func menuWillOpen(_ menu: NSMenu) {
        visualItem.state = model.s.visualFeedback ? .on : .off
        soundItem.state = model.s.playSound ? .on : .off
    }
    @objc func stopRecording() { capture.recording.stop() }
    @objc func toggleVisual() { model.s.visualFeedback.toggle() }
    @objc func toggleSound() { model.s.playSound.toggle() }
    @objc func about() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        NSApp.orderFrontStandardAboutPanel(options: [.applicationIcon: AppIcon.app(size: 256)])
    }

    func clicked(_ e: NSEvent) {
        let button: ClickButton = e.type == .rightMouseDown ? .right : .left
        // The event's own location: NSEvent.mouseLocation is read later and drifts on fast moves.
        let p = e.window.map { $0.convertPoint(toScreen: e.locationInWindow) } ?? e.locationInWindow
        if let m = clickMark(for: button, settings: model.s) { overlay.show(m, at: p) }
        play()
    }

    func play(force: Bool = false) {
        var s = model.s; if force { s.playSound = true }
        let v = effectiveVolume(s)
        if v > 0, let snd = sound { snd.stop(); snd.volume = v; snd.play() }
    }

    /// Takes the settings as an argument: reading `model` here could re-enter its lazy initializer.
    /// Quits and opens this app again (a new Screen Recording grant applies after reopening).
    /// A helper process would not outlive the app (macOS ends it with the app), so the new copy starts first
    /// and waits for this one to quit.
    static let reopenedArgument = "--reopened"
    func reopen() {
        let c = NSWorkspace.OpenConfiguration()
        c.createsNewApplicationInstance = true
        c.arguments = [Self.reopenedArgument, String(getpid()), "--settings"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: c) { _, error in
            DispatchQueue.main.async { if error == nil { NSApp.terminate(nil) } else { NSSound.beep() } }
        }
    }

    func reloadSound(_ s: ClickSettings) {
        let k = s.clickSound
        if let name = k.systemName { sound = NSSound(named: name) }
        else { sound = NSSound(data: wavData(clickSamples(k, shape: s.soundShape))) }   // synthesized now, so the sliders apply at once
    }

    @objc func openPrefs() {
        if model.s.windowCapture { capture.refresh() }   // permissions may have changed while the window was closed
        model.refreshVoice()
        if prefs == nil {
            let host = NSHostingController(rootView: PrefsView(m: model))
            host.sizingOptions = .preferredContentSize   // window grows / shrinks when the sound sliders show or hide
            let w = NSWindow(contentViewController: host)
            w.title = "Preferences"; w.isReleasedWhenClosed = false
            w.styleMask.remove(.resizable)
            w.level = .floating   // stays in front while clicking other apps to try the mark
            w.hidesOnDeactivate = false
            w.setContentSize(host.view.fittingSize)
            prefs = w
        }
        prefs?.center()
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        prefs?.makeKeyAndOrderFront(nil)
        prefs?.orderFrontRegardless()
    }
}

/// Starts the menu bar app. Does not return.
@MainActor
public func runApp() -> Never {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // NSApplication.delegate is weak; keep the local delegate alive for the whole run.
    withExtendedLifetime(delegate) { app.run() }
    exit(0)
}
