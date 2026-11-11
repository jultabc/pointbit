// Permissions for window capture: Accessibility (keys), Screen Recording (capture), Input Monitoring (only if
// macOS refuses the listen-only key tap); for voice: Microphone and Speech Recognition.
// Checks, requests and the System Settings pages.
import AppKit
import ApplicationServices
import AVFoundation
import Speech

enum CapturePermissions {
    /// Accessibility trust. With `prompt`, macOS shows its permission dialog when not trusted.
    static func trusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
    }
    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() { openPrivacy("Privacy_Accessibility") }
    /// Opens System Settings → Privacy & Security → Screen & System Audio Recording.
    static func openScreenRecordingSettings() { openPrivacy("Privacy_ScreenCapture") }
    private static func openPrivacy(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
    }
    /// Screen Recording granted (macOS applies a new grant after the app reopens).
    static var screenAllowed: Bool { CGPreflightScreenCaptureAccess() }
    /// Adds this app to the Screen Recording list and shows the system prompt (once).
    static func requestScreen() { _ = CGRequestScreenCaptureAccess() }
    /// Input Monitoring (listen-only key taps), when macOS asks for it in addition to Accessibility.
    static func requestListen() { _ = CGRequestListenEventAccess() }
    static func openInputMonitoringSettings() { openPrivacy("Privacy_ListenEvent") }

    static var microphoneAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var speechAllowed: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    /// Shows the system prompts (each once): Microphone, then Speech Recognition. `done` runs on the main thread.
    static func requestVoice(done: @escaping @Sendable () -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async(execute: done) }
        }
    }
    static func openMicrophoneSettings() { openPrivacy("Privacy_Microphone") }
    static func openSpeechSettings() { openPrivacy("Privacy_SpeechRecognition") }
}
