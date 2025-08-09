import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryView: View {
    // The list of all OCR items loaded from the store.  This state is
    // updated whenever the store publishes a change.
    @State private var items: [OcrItem] = HistoryStore.shared.fetchAll()
    // The set of selected item identifiers in the list.  Multi‑selection
    // enables copy/delete operations on multiple elements.  We use UUIDs
    // because OcrItem conforms to Identifiable.
    @State private var selection: Set<UUID> = []

    // Remember the anchor index for shift‑click range selection.  Whenever
    // the user performs a plain click (without modifier keys) the anchor
    // is updated to that row’s index.  Shift‑click then selects the
    // contiguous range between this anchor and the clicked row.
    @State private var anchorIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(LocalizedStringKey("Sidebar.History"))
                .font(.headline)
                .padding(8)
            // Action bar for selected items
            if !selection.isEmpty {
                HStack(spacing: 12) {
                    Button(action: copySelected) {
                        Label(LocalizedStringKey("History.CopySelected"), systemImage: "doc.on.doc")
                    }
                    Button(action: deleteSelected) {
                        Label(LocalizedStringKey("History.DeleteSelected"), systemImage: "trash")
                    }
                    Button(action: selectAll) {
                        Label(LocalizedStringKey("History.SelectAll"), systemImage: "square.3.stack.3d")
                    }
                    Button(action: clearHistory) {
                        Label(LocalizedStringKey("History.ClearAll"), systemImage: "trash.slash")
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
            // The list of history items.  We handle selection manually to
            // support plain, shift and option+shift click behaviours.  See
            // handleClick() for details.
            List {
                ForEach(items.indices, id: \.self) { idx in
                    let item = items[idx]
                    HStack(spacing: 8) {
                        Image(nsImage: item.thumbnail() ?? NSWorkspace.shared.icon(for: .pdf))
                            .resizable()
                            .frame(width: 20, height: 20)
                            .cornerRadius(3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle).lineLimit(1)
                            Text(item.createdAt.formatted())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    // Highlight the row when selected by applying a subtle
                    // accent‑colored background.  The contentShape ensures
                    // the entire row responds to clicks.
                    .padding(2)
                    .background(selection.contains(item.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 1)
                            .modifiers(.control)
                            .onEnded {
                                if !selection.contains(item.id) {
                                    selection = [item.id]
                                    anchorIndex = idx
                                }
                            }
                    )
                    // Context menu: ensure the clicked item participates in
                    // the selection (use alt+shift semantics: add it if not
                    // already selected).  The menu entries mirror the
                    // existing operations.
                    .contextMenu {
                        Button(LocalizedStringKey("History.Copy")) { copy(item) }
                        Button(LocalizedStringKey("History.RevealSource")) { revealSource(item) }
                        if item.outputPath != nil {
                            Divider()
                            Button(LocalizedStringKey("History.RevealOCR")) { revealOCR(item) }
                            Button(LocalizedStringKey("History.CopyAsFile")) { copyAsFile(item) }
                        }
                        Divider()
                        Button(role: .destructive) { delete(item) } label: { Text(LocalizedStringKey("History.Delete")) }
                    }
                    // Tap gesture: handle selection logic based on current
                    // modifier keys.  Right‑clicks do not trigger this
                    // gesture so the context menu can still be invoked.
                    .onTapGesture {
                        let flags = NSEvent.modifierFlags
                        handleClick(itemID: item.id, index: idx, flags: flags)
                    }
                }
            }
        }
        .onReceive(HistoryStore.shared.objectWillChange) { _ in
            // Refresh items and filter out any selections that no longer exist
            self.items = HistoryStore.shared.fetchAll()
            self.selection = self.selection.filter { id in items.contains(where: { $0.id == id }) }
        }
    }

    // MARK: - Actions for single items
    private func copy(_ item: OcrItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.outputText ?? "", forType: .string)
    }
    private func revealSource(_ item: OcrItem) {
        if let url = item.resolvedURL() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    private func revealOCR(_ item: OcrItem) {
        guard let p = item.outputPath else { return }
        let url = URL(fileURLWithPath: p)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    private func copyAsFile(_ item: OcrItem) {
        guard let p = item.outputPath else { return }
        let url = URL(fileURLWithPath: p)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
    private func delete(_ item: OcrItem) {
        HistoryStore.shared.delete(item.id)
        // Immediately refresh selection state on deletion of a single item
        self.items = HistoryStore.shared.fetchAll()
        self.selection.remove(item.id)
    }

    /// Handle a mouse click on a history row.  The semantics are:
    /// - plain click: select only the clicked item and update the anchor.
    /// - shift click: select all items between the anchor and the clicked row.
    /// - option+shift click: toggle the clicked item in the selection, leaving other selections unchanged.
    /// The NSEvent modifier flags are inspected to determine which branch to take.
    private func handleClick(itemID: UUID, index: Int, flags: NSEvent.ModifierFlags) {
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        // Command‑click is still handled by the system when using a native
        // List selection; since we manage selection manually here, we map
        // option+shift to toggling semantics.  If both shift and option are
        // pressed we toggle the clicked row’s membership in the selection.
        if shift && option {
            if selection.contains(itemID) {
                selection.remove(itemID)
            } else {
                selection.insert(itemID)
            }
            // Do not update anchor: subsequent shift clicks will use the
            // original anchor for contiguous range selection.
            return
        }
        // Shift‑click without option selects a contiguous range.  If no
        // anchor has been recorded yet (e.g. first click is shift), we
        // treat the clicked row as the anchor.
        if shift {
            let start = anchorIndex ?? index
            let lower = min(start, index)
            let upper = max(start, index)
            let ids = items[lower...upper].map { $0.id }
            selection = Set(ids)
            return
        }
        // Plain click: reset the selection to the clicked row and set
        // anchor for subsequent range selections.
        selection = [itemID]
        anchorIndex = index
    }

    // MARK: - Actions for multiple selection
    private func copySelected() {
        let selectedItems = items.filter { selection.contains($0.id) }
        guard selectedItems.isEmpty == false else { return }
        let combined = selectedItems.compactMap { $0.outputText }.joined(separator: "\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)
    }
    private func deleteSelected() {
        let ids = selection
        for id in ids {
            HistoryStore.shared.delete(id)
        }
        self.items = HistoryStore.shared.fetchAll()
        self.selection.removeAll()
    }
    private func selectAll() {
        self.selection = Set(items.map { $0.id })
    }
    private func clearHistory() {
        // Confirm deletion with an alert.  We run the alert on the main thread.
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("History.ClearConfirmTitle", comment: "")
        alert.informativeText = NSLocalizedString("History.ClearConfirmMessage", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Button.Delete", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Button.Cancel", comment: ""))
        alert.buttons.first?.hasDestructiveAction = true
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            HistoryStore.shared.wipeAll()
            self.items = HistoryStore.shared.fetchAll()
            self.selection.removeAll()
        }
    }
}
