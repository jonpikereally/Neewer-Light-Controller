//  main.swift — menu bar entry point.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let light = LightController()
    private let updater = Updater()
    private let layout = PopoverLayout()
    private lazy var server = ControlServer(light: light)
    private var monitor: Any?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lightbulb.max.fill",
                                           accessibilityDescription: "Neewer Light")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.target = self

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: ContentView(light: light, updater: updater, layout: layout))
        host.sizingOptions = .preferredContentSize   // popover follows the SwiftUI height
        popover.contentViewController = host

        // Loopback control surface for the Stream Deck plugin.
        server.start()

        updater.check()
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Room between the menu bar icon and the bottom of its screen, less the
            // popover's arrow and margins. Taller than this and macOS shoves the
            // popover up over the menu bar.
            if let win = button.window, let screen = win.screen {
                layout.maxHeight = win.frame.minY - screen.visibleFrame.minY - 40
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

final class PopoverLayout: ObservableObject {
    @Published var maxHeight: CGFloat = 600
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
