// Permissions for window capture: Accessibility (keys), Screen Recording (capture), Input Monitoring (only if
// macOS refuses the listen-only key tap). Checks, requests and the System Settings pages.
import AppKit
import ApplicationServices

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
}
