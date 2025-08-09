//
//  MainWindowManager.swift
//  MistralOCR_Desktop
//
//  Created by Gael Dauchy on 09/08/2025.
//


import AppKit
import SwiftUI

@MainActor
final class MainWindowManager {
    static let shared = MainWindowManager()

    let appModel = AppModel()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "MainWindow" }) {
            self.window = existing
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = MainWindow()
            .environmentObject(appModel)
            .frame(minWidth: 980, minHeight: 620)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = NSHostingView(rootView: content)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = newWindow
    }
}