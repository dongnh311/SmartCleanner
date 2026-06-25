import AppKit
import SwiftUI
import UserNotifications

/// Keeps the menu-bar agent alive when the user "Quit"s the main window.
///
/// Default Quit behaviour (Dock context-menu Quit / Cmd+Q): hide the
/// window, drop to `.accessory` activation policy (no Dock icon), and
/// cancel the actual termination — the process keeps running so the
/// `MenuBarExtra` stays in the status bar. Mirrors how CMM keeps
/// its menu bar component alive after the window closes.
///
/// To fully terminate, the menu-bar popover sets `quitForReal = true`
/// before calling `NSApp.terminate(_:)` (the power button in the footer).
@MainActor
final class MacCleanerAppDelegate: NSObject, NSApplicationDelegate {

    nonisolated(unsafe) static var quitForReal = false

    /// Become the notification delegate at launch so alerts (malware
    /// detections, threshold alerts) surface as banners **even while the app
    /// is active or running as a menu-bar agent** — without a delegate macOS
    /// silently swallows foreground notifications. Also prompts for
    /// permission once so the very first detection can actually show.
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in await AlertEngine.shared.requestAuthorizationIfNeeded() }
    }

    nonisolated func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.quitForReal { return .terminateNow }
        MainActor.assumeIsolated {
            hideMainWindowsKeepingMenuBar()
            NSApp.setActivationPolicy(.accessory)
        }
        return .terminateCancel
    }

    /// Closing the last visible main window while in `.regular` should not
    /// auto-terminate — we want the same accessory-mode behaviour.
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func hideMainWindowsKeepingMenuBar() {
        for window in NSApp.windows where window.isVisible {
            // Status-bar popover windows are private NSStatusBarWindow /
            // NSPopoverWindow subclasses — keep them alive.
            let className = String(describing: type(of: window))
            if className.contains("StatusBar") || className.contains("Popover") {
                continue
            }
            window.orderOut(nil)
        }
    }
}

extension MacCleanerAppDelegate: UNUserNotificationCenterDelegate {
    /// Present malware/alert banners even when MacCleaner is the active app
    /// or sitting in the menu bar — otherwise the OS only files them quietly
    /// in Notification Center and the user never sees the threat.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

/// Re-show the main window from accessory mode and restore the Dock icon.
@MainActor
enum AppPresenter {
    static func showMainWindow(openWindow: OpenWindowAction) {
        dismissMenuBarPopover()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: {
            let cls = String(describing: type(of: $0))
            return $0.canBecomeMain
                && $0.contentViewController != nil
                && !cls.contains("StatusBar")
                && !cls.contains("Popover")
                && !cls.contains("MenuBar")
        }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    static func quitForReal() {
        MacCleanerAppDelegate.quitForReal = true
        NSApp.terminate(nil)
    }

    /// Open the Settings scene from anywhere. The reliable approach is
    /// to enumerate the app menu, find the menu item SwiftUI installed
    /// for "Settings…" / "Preferences…" (label changes between macOS 13
    /// and 14), and trigger its action directly. The naked
    /// `NSApp.sendAction(showSettingsWindow:)` route fails when no first
    /// responder is established (e.g. coming back from accessory mode).
    static func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            for item in appMenu.items {
                let lower = item.title.lowercased()
                if lower.hasPrefix("settings") || lower.hasPrefix("preferences") {
                    if let action = item.action {
                        NSApp.sendAction(action, to: item.target, from: nil)
                        return
                    }
                }
            }
        }

        // Fallback if the menu wasn't populated yet.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    /// Modal "Quit MacCleaner?" alert. Sits in its own NSAlert window so
    /// the menu bar popover keeps its state — a SwiftUI `.confirmationDialog`
    /// inside MenuBarExtra dismisses the popover when the user taps
    /// Cancel and leaves the dialog state stuck on, so it pops up again
    /// the next time the popover opens.
    static func confirmAndQuit() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Quit MacCleaner completely?"
        alert.informativeText = "The status bar icon and background metrics will stop. Reopen MacCleaner from the Dock to bring them back."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            quitForReal()
        }
    }

    /// `MenuBarExtra(style: .window)` renders the popover inside a private
    /// SwiftUI window. There's no first-party dismiss API, but the popover
    /// is the only `keyWindow` while it's visible — the small status-bar
    /// item that holds the icon + CPU/RAM label never becomes key. Closing
    /// the keyWindow therefore dismisses the panel without taking the
    /// status bar icon with it.
    private static func dismissMenuBarPopover() {
        guard let key = NSApp.keyWindow else { return }
        // Skip our main app window — its content is much larger than a
        // popover and it shouldn't be closed here.
        let frame = key.frame
        let isPopoverShape = frame.width < 600 && frame.height < 700
        guard isPopoverShape else { return }
        key.orderOut(nil)
    }
}
