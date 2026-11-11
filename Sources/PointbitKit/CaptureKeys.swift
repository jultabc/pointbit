// ⌘ ⌘ + T · A · D · C · S · R · Z · X · 1 · 2 · 3 · L · O · B · M key taps.
// - A listen-only tap, on while the feature is on. It only reads keys; it cannot hold back or delay input.
// - A short-lived tap that can hold back the action key (the letter). It exists only from the second ⌘ press until that key is released,
//   and is removed after at most `swallowLimit` seconds whatever happens, so it can never block the keyboard
//   for longer than that (for example after Accessibility is removed while the app runs).
import AppKit

final class CaptureKeys {
    static let swallowLimit = 3.0   // seconds the key-holding tap may exist after a capture

    private var listenTap: CFMachPort?, listenSource: CFRunLoopSource?
    private var swallowTap: CFMachPort?, swallowSource: CFRunLoopSource?
    private var swallowTimer: Timer?
    private var sequence = CaptureSequence()
    /// Called on the main thread when ⌘ ⌘ + an action key completes.
    var onCapture: (CaptureKey) -> Void = { _ in }
    /// Called on the main thread when macOS turned the listen tap off.
    var onLostPermission: () -> Void = {}

    var isRunning: Bool { listenTap != nil }

    private static let keyMask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)

    private func makeTap(listenOnly: Bool, mask: CGEventMask) -> (CFMachPort, CFRunLoopSource)? {
        let me = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = listenOnly
            ? { _, type, event, info in Unmanaged<CaptureKeys>.fromOpaque(info!).takeUnretainedValue().listen(type, event) }
            : { _, type, event, info in Unmanaged<CaptureKeys>.fromOpaque(info!).takeUnretainedValue().swallow(type, event) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: listenOnly ? .listenOnly : .defaultTap,
                                        eventsOfInterest: mask, callback: callback, userInfo: me) else { return nil }
        let s = CFMachPortCreateRunLoopSource(nil, t, 0)!
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return (t, s)
    }

    private func remove(_ tap: inout CFMachPort?, _ source: inout CFRunLoopSource?) {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
    }

    /// Starts the listen tap. Returns false when Accessibility is not granted or macOS refuses the tap.
    @discardableResult
    func start(prompt: Bool) -> Bool {
        guard listenTap == nil else { return true }
        guard CapturePermissions.trusted(prompt: prompt),
              let (t, s) = makeTap(listenOnly: true, mask: Self.keyMask | CGEventMask(1 << CGEventType.flagsChanged.rawValue))
        else { return false }
        listenTap = t; listenSource = s
        return true
    }

    func stop() {
        removeSwallowTap()
        remove(&listenTap, &listenSource)
        sequence = CaptureSequence()
    }

    private func removeSwallowTap() {
        swallowTimer?.invalidate(); swallowTimer = nil
        remove(&swallowTap, &swallowSource)
    }

    /// Adds or removes the key-holding tap to match the sequence. Main thread.
    private func syncSwallowTap() {
        if sequence.wantsSwallowTap, swallowTap == nil, let (t, s) = makeTap(listenOnly: false, mask: Self.keyMask) {
            swallowTap = t; swallowSource = s
            let s = CaptureSequence()
            limitSwallowTap(s.tapMax + s.keyWindow + 0.1)   // second ⌘ press, its release, then the action key
        } else if !sequence.wantsSwallowTap, swallowTap != nil {
            removeSwallowTap()
        }
    }

    /// Removes the key-holding tap after `seconds`, whatever state the sequence is in.
    private func limitSwallowTap(_ seconds: Double) {
        swallowTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            self?.sequence.cancel(); self?.removeSwallowTap()
        }
        RunLoop.main.add(timer, forMode: .common)
        swallowTimer = timer
    }

    private func input(_ type: CGEventType, _ event: CGEvent) -> KeyInput {
        let now = Double(event.timestamp) / 1_000_000_000
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        switch type {
        case .flagsChanged:
            if code == 55 || code == 54 { return flags.contains(.maskCommand) ? .commandDown(now) : .commandUp(now) }   // ⌘
            return .otherModifier(now)
        case .keyUp:
            return .keyUp(code: code, at: now)
        default:
            let mods: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            return .key(code: code, modifiers: !flags.intersection(mods).isEmpty, at: now,
                        repeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        }
    }

    /// Listen-only tap: reads ⌘ taps (and keys while no key-holding tap exists). Its return value is ignored by macOS.
    /// Both taps run on the main run loop, so the key-holding tap is added here, synchronously, at the second ⌘ press.
    private func listen(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout, let t = listenTap { CGEvent.tapEnable(tap: t, enable: true) }
        if type == .tapDisabledByUserInput {
            DispatchQueue.main.async { self.stop(); self.onLostPermission() }
        }
        guard type == .flagsChanged || ((type == .keyDown || type == .keyUp) && swallowTap == nil) else {
            return Unmanaged.passUnretained(event)   // key events go to the key-holding tap while it exists
        }
        if case .capture(let k) = sequence.feed(input(type, event)) {
            // The key came before the holding tap existed (should not happen, it is added at the second ⌘ press):
            // act anyway; this key reaches the front app.
            limitSwallowTap(Self.swallowLimit); onCapture(k)
        }
        if sequence.wantsSwallowTap != (swallowTap != nil) { syncSwallowTap() }
        return Unmanaged.passUnretained(event)
    }

    /// key-holding tap: holds back the action key that completes the sequence, its repeats and its release.
    private func swallow(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {   // turned off by macOS: remove it, never re-enable
            DispatchQueue.main.async { self.sequence.cancel(); self.removeSwallowTap() }
            return Unmanaged.passUnretained(event)
        }
        let action = sequence.feed(input(type, event))
        if case .capture(let k) = action {
            DispatchQueue.main.async { self.limitSwallowTap(Self.swallowLimit); self.onCapture(k) }
        }
        if !sequence.wantsSwallowTap { DispatchQueue.main.async { self.syncSwallowTap() } }
        return action == .pass ? Unmanaged.passUnretained(event) : nil
    }
}
