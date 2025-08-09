import SwiftUI
import AppKit

struct PreferencesView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var apiKey: String = SettingsStore.shared.apiKey
    @State private var exportFolder: URL = SettingsStore.shared.exportFolder
    @State private var showingOpen = false
    @State private var hotkeyListening = false
    @State private var hotkeyDisplay = "⌘⇧O"
    // Whether to automatically send jobs upon drop
    @State private var autoSend = SettingsStore.shared.autoSendOnDrop
    // Result of API key validity test: nil = unknown, true = ok, false = failed
    @State private var apiKeyStatus: Bool? = SettingsStore.shared.apiKeyValid

    // Deposit settings local state
    @State private var depositEnabled: Bool = SettingsStore.shared.depositFolder != nil
    @State private var depositFolder: URL? = SettingsStore.shared.depositFolder
    @State private var depositExport: URL? = SettingsStore.shared.depositExportFolder
    @State private var depositTrash: URL? = SettingsStore.shared.depositTrashFolder
    @State private var useSystemTrash: Bool = SettingsStore.shared.useSystemTrashForSource

    var body: some View {
        Form {
            // API key field with inline test button and status indicator
            HStack {
                TextField("MISTRAL_API_KEY", text: $apiKey)
                    .textContentType(.password)
                    .onChange(of: apiKey) { _, newValue in
                        SettingsStore.shared.apiKey = newValue
                        // Reset validation when the key changes
                        self.apiKeyStatus = nil
                    }
                Button(LocalizedStringKey("Settings.TestKey")) {
                    Task { await testApiKey() }
                }
                if let ok = apiKeyStatus {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundColor(ok ? .green : .red)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.gray)
                }
            }

            Picker(LocalizedStringKey("Settings.Model"), selection: $appModel.settings.selectedModel) {
                ForEach(appModel.models, id: \.self) { m in Text(m).tag(m) }
            }
            Button("Rafraîchir la liste des modèles") {
                Task { await appModel.refreshModels() }
            }

            Divider().padding(.vertical, 6)

            HStack {
                Text("Dossier d’export")
                Spacer()
                Text(exportFolder.path).lineLimit(1).truncationMode(.middle)
                Button("Changer…") { pickFolder() }
            }

            // Option to immediately send dropped files
            Toggle(LocalizedStringKey("Settings.AutoSend"), isOn: $autoSend)
                .onChange(of: autoSend) { _, newValue in
                    SettingsStore.shared.autoSendOnDrop = newValue
                }

            HStack {
                Text("Raccourci global")
                Spacer()
                Button(hotkeyDisplay) {
                    hotkeyListening = true
                }
                .keyboardShortcut(.defaultAction)
                .onChange(of: hotkeyListening) { _, newValue in
                    if newValue { startListeningHotkey() }
                }
            }
            Text("Appuyez sur la combinaison désirée. Les conflits seront détectés lors de l’enregistrement.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 6)

            // Deposit folder configuration
            Toggle(LocalizedStringKey("Settings.Deposit.Enable"), isOn: $depositEnabled)
                .onChange(of: depositEnabled) { _, newValue in
                    if newValue == false {
                        // Disable deposit: clear settings
                        depositFolder = nil
                        depositExport = nil
                        depositTrash = nil
                        SettingsStore.shared.depositFolder = nil
                        SettingsStore.shared.depositExportFolder = nil
                        SettingsStore.shared.depositTrashFolder = nil
                    }
                }

            if depositEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Dossier de dépôt")
                        Spacer()
                        Text(depositFolder?.path ?? "—").lineLimit(1).truncationMode(.middle)
                        Button("Choisir…") { pickDepositFolder() }
                    }
                    HStack {
                        Text("Dossier OCR (export)")
                        Spacer()
                        // Show default if nil
                        let defaultExport = depositFolder?.appendingPathComponent("Mistral_OCR_Export", isDirectory: true)
                        Text((depositExport ?? defaultExport)?.path ?? "—").lineLimit(1).truncationMode(.middle)
                        Button("Définir…") { pickDepositExportFolder() }
                            .disabled(depositFolder == nil)
                    }
                    HStack {
                        Text("Dossier des originaux")
                        Spacer()
                        let defaultTrash = depositFolder?.appendingPathComponent("Mistral_OCR_Corbeille", isDirectory: true)
                        Text((depositTrash ?? defaultTrash)?.path ?? "—").lineLimit(1).truncationMode(.middle)
                        Button("Définir…") { pickDepositTrashFolder() }
                            .disabled(depositFolder == nil || useSystemTrash)
                    }
                    Toggle("Envoyer les originaux à la corbeille du système", isOn: $useSystemTrash)
                        .onChange(of: useSystemTrash) { _, newValue in
                            SettingsStore.shared.useSystemTrashForSource = newValue
                        }
                    Text("[Attention ! C’est bien le nom dans l’application qui compte. Si l’utilisateur renomme son dossier, l’application le recréera. Si l’utilisateur veut en changer le nom, il doit aussi l’indiquer dans les réglages.]")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 16)
                .onAppear {
                    // Sync local state with store values on appear
                    depositFolder = SettingsStore.shared.depositFolder
                    depositExport = SettingsStore.shared.depositExportFolder
                    depositTrash = SettingsStore.shared.depositTrashFolder
                    useSystemTrash = SettingsStore.shared.useSystemTrashForSource
                }
                .onChange(of: depositFolder) { _, newValue in
                    SettingsStore.shared.depositFolder = newValue
                    // Update defaults when folder changes
                    if newValue != nil {
                        if SettingsStore.shared.depositExportFolder == nil {
                            depositExport = nil
                        }
                        if SettingsStore.shared.depositTrashFolder == nil {
                            depositTrash = nil
                        }
                    }
                }
                .onChange(of: depositExport) { _, newValue in
                    SettingsStore.shared.depositExportFolder = newValue
                }
                .onChange(of: depositTrash) { _, newValue in
                    SettingsStore.shared.depositTrashFolder = newValue
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            apiKey = SettingsStore.shared.apiKey
            exportFolder = SettingsStore.shared.exportFolder
            autoSend = SettingsStore.shared.autoSendOnDrop
            apiKeyStatus = SettingsStore.shared.apiKeyValid
        }
    }

    private func pickFolder() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.begin { resp in
            if resp == .OK, let url = p.url {
                // Test write permissions: attempt to write and remove a dummy file
                let tmp = url.appendingPathComponent(".mocr_write_test")
                do {
                    try Data().write(to: tmp)
                    try FileManager.default.removeItem(at: tmp)
                    exportFolder = url
                    SettingsStore.shared.exportFolder = url
                } catch {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Alert.CannotWrite", comment: "Cannot write")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    // MARK: Deposit folder pickers
    private func pickDepositFolder() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.begin { resp in
            if resp == .OK, let url = p.url {
                // Validate write access by writing a tiny file then removing it
                let testFile = url.appendingPathComponent(".mocr_write_test")
                do {
                    try Data().write(to: testFile)
                    try FileManager.default.removeItem(at: testFile)
                    depositFolder = url
                    SettingsStore.shared.depositFolder = url
                } catch {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Alert.CannotWrite", comment: "Cannot write")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func pickDepositExportFolder() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.begin { resp in
            if resp == .OK, let url = p.url {
                let testFile = url.appendingPathComponent(".mocr_write_test")
                do {
                    try Data().write(to: testFile)
                    try FileManager.default.removeItem(at: testFile)
                    depositExport = url
                    SettingsStore.shared.depositExportFolder = url
                } catch {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Alert.CannotWrite", comment: "Cannot write")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func pickDepositTrashFolder() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.begin { resp in
            if resp == .OK, let url = p.url {
                let testFile = url.appendingPathComponent(".mocr_write_test")
                do {
                    try Data().write(to: testFile)
                    try FileManager.default.removeItem(at: testFile)
                    depositTrash = url
                    SettingsStore.shared.depositTrashFolder = url
                } catch {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Alert.CannotWrite", comment: "Cannot write")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func startListeningHotkey() {
        // Simplified capture: next keyDown in window
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            self.hotkeyListening = false
            let kc = UInt32(ev.keyCode)
            var mods: UInt32 = 0
            if ev.modifierFlags.contains(.command) { mods |= (1 << 8) }
            if ev.modifierFlags.contains(.shift)   { mods |= (1 << 17) }
            if ev.modifierFlags.contains(.option)  { mods |= (1 << 11) }
            if ev.modifierFlags.contains(.control) { mods |= (1 << 12) }
            SettingsStore.shared.hotkeyKeyCode = kc
            SettingsStore.shared.hotkeyModifiers = mods
            self.hotkeyDisplay = describe(kc, mods)
            GlobalHotkeyManager.shared.register(defaultKey: kc, modifiers: mods) // re-register; returns no error if ok
            return nil
        }
    }

    private func describe(_ key: UInt32, _ mods: UInt32) -> String {
        var parts: [String] = []
        if (mods & (1 << 8)) != 0 { parts.append("⌘") }
        if (mods & (1 << 17)) != 0 { parts.append("⇧") }
        if (mods & (1 << 11)) != 0 { parts.append("⌥") }
        if (mods & (1 << 12)) != 0 { parts.append("^") }
        // naive mapping for 'O' (31); in prod, map keycodes fully
        let keyName = (key == 31 ? "O" : String(format: "#%d", key))
        parts.append(keyName)
        return parts.joined()
    }

    /// Validate the current API key by requesting the list of available models.  On success this
    /// will set `apiKeyStatus` to true and update `SettingsStore.shared.apiKeyValid`.  On error
    /// `apiKeyStatus` is set to false.  The network call is asynchronous.
    private func testApiKey() async {
        do {
            _ = try await ModelCatalog.fetchModels()
            await MainActor.run {
                self.apiKeyStatus = true
                SettingsStore.shared.apiKeyValid = true
            }
        } catch {
            await MainActor.run {
                self.apiKeyStatus = false
                SettingsStore.shared.apiKeyValid = false
            }
        }
    }
}
