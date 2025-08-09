import AppKit
import SwiftUI

import Combine

@MainActor final class StatusController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?
    
    func install() {
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusIcon")
            // Do not mark the status icon as a template: our asset uses the
            // Mistral orange coloring and should display its colors in the
            // menu bar.  Template images would be tinted monochrome by
            // macOS, which defeats the branding.
            button.image?.isTemplate = false
        }
        // Rebuild the menu initially and subscribe to history changes
        rebuildMenu()
        cancellable = HistoryStore.shared.objectWillChange.sink { [weak self] _ in
            // Rebuild the menu on the main queue to avoid UI updates from a background thread.
            DispatchQueue.main.async {
                self?.rebuildMenu()
            }
        }
    }
    
    private func rebuildMenu() {
        let menu = NSMenu()
        let showItem = NSMenuItem(title: NSLocalizedString("Menu.ShowWindow", comment: ""), action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())
        let last = HistoryStore.shared.fetchLast(limit: 3)
        if last.isEmpty == false {
            let header = NSMenuItem()
            header.title = NSLocalizedString("Menu.Last3", comment: "")
            header.isEnabled = false
            menu.addItem(header)
            for item in last {
                let mi = NSMenuItem(title: item.displayTitle, action: #selector(copyFromMenu(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.id.uuidString
                mi.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }
        let signInItem = NSMenuItem(title: NSLocalizedString("Menu.SignIn", comment: ""), action: #selector(openPrefs), keyEquivalent: "")
        signInItem.target = self
        menu.addItem(signInItem)
        let quitItem = NSMenuItem(title: NSLocalizedString("Menu.Quit", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = nil // system handles quit
        menu.addItem(quitItem)
        statusItem.menu = menu
    }
    
    @objc private func showWindow() {
        MainWindowManager.shared.show()
    }
    
    @objc private func openPrefs() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String, let id = UUID(uuidString: idStr),
              let item = HistoryStore.shared.item(id: id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.outputText ?? "", forType: .string)
    }
}
