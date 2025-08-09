import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // Defaults
    static let exportDefault: URL = {
        let d = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        return d.appendingPathComponent("MistralOCR_Desktop", isDirectory: true)
    }()

    // Stored properties
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
    }
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }
    @Published var availableModels: [String] = ["mistral-ocr-latest"]

    // Export folder
    @Published var exportFolder: URL {
        didSet { UserDefaults.standard.set(exportFolder.path, forKey: "exportFolder") }
    }

    // Include images (base64) in OCR responses.  When true the client will
    // request that the API embeds images as base64 in the returned Markdown.  This
    // value is persisted using the key "includeImages".  For backwards
    // compatibility we also read the value stored under "includeImageBase64" on
    // initialization.  When neither is present the default is false.
    @Published var includeImages: Bool {
        didSet { UserDefaults.standard.set(includeImages, forKey: "includeImages") }
    }

    /// Backwards‑compatible alias for includeImages.  Some parts of the code or
    /// external consumers may still reference includeImageBase64; exposing it
    /// here prevents compile errors and simply forwards to includeImages.
    var includeImageBase64: Bool { includeImages }
    

    // Hotkey: modifiers mask + keyCode (Carbon)
    @Published var hotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }
    @Published var hotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }

    /// When enabled the application will immediately process any file dropped into the main window.
    /// The resulting OCR will be added to the history and exported to the selected export folder.
    @Published var autoSendOnDrop: Bool {
        didSet { UserDefaults.standard.set(autoSendOnDrop, forKey: "autoSendOnDrop") }
    }

    /// When true the application will attempt to preserve the directory structure of dropped
    /// files when exporting OCR results.  In manual sending, the results will be written
    /// into a subdirectory of the export folder that mirrors the relative path of the
    /// source files.  This setting does not affect processing via the deposit folder.
    @Published var preserveStructure: Bool {
        didSet { UserDefaults.standard.set(preserveStructure, forKey: "preserveStructure") }
    }

    /// An optional flag indicating whether the provided API key appears to be valid.  This value is
    /// updated by the preferences view when the user explicitly tests the key.  It is not persisted
    /// to disk and serves only to drive UI state.
    @Published var apiKeyValid: Bool?

    // MARK: Deposit processing settings
    /// Optional folder to watch for incoming documents.  When non‑nil the application will
    /// monitor this directory and automatically process new files using the selected OCR
    /// parameters.  Results will be exported to `depositExportFolder` or, if unset,
    /// to a default subdirectory beneath the deposit folder.  Originals are moved into
    /// `depositTrashFolder` unless `useSystemTrashForSource` is enabled.
    @Published var depositFolder: URL? {
        didSet {
            if let url = depositFolder {
                UserDefaults.standard.set(url.path, forKey: "depositFolder")
            } else {
                UserDefaults.standard.removeObject(forKey: "depositFolder")
            }
            if initialized { DepositWatcher.shared.updatePaths() }
        }
    }
    /// Folder where the OCR output files will be stored for documents processed via the
    /// deposit folder.  If nil and a deposit folder is configured, a subdirectory named
    /// `Mistral_OCR_Export` within the deposit folder will be used.  When set by the user
    /// the directory will be used directly and no automatic subdirectory will be created.
    @Published var depositExportFolder: URL? {
        didSet {
            if let url = depositExportFolder {
                UserDefaults.standard.set(url.path, forKey: "depositExportFolder")
            } else {
                UserDefaults.standard.removeObject(forKey: "depositExportFolder")
            }
            if initialized { DepositWatcher.shared.updatePaths() }
        }
    }
    /// Folder where originals will be moved after OCR processing when using the deposit
    /// watcher.  If nil and a deposit folder is configured, a subdirectory named
    /// `Mistral_OCR_Corbeille` within the deposit folder will be used.  When set by the user
    /// the directory will be used directly.  Ignored when `useSystemTrashForSource` is true.
    @Published var depositTrashFolder: URL? {
        didSet {
            if let url = depositTrashFolder {
                UserDefaults.standard.set(url.path, forKey: "depositTrashFolder")
            } else {
                UserDefaults.standard.removeObject(forKey: "depositTrashFolder")
            }
            if initialized { DepositWatcher.shared.updatePaths() }
        }
    }
    /// When true the deposit watcher will place processed source files into the system
    /// Trash rather than moving them to `depositTrashFolder`.  When enabled the picker
    /// for choosing a trash folder is disabled in the UI.  Defaults to false.
    @Published var useSystemTrashForSource: Bool {
        didSet {
            UserDefaults.standard.set(useSystemTrashForSource, forKey: "useSystemTrashForSource")
            // Avoid starting the watcher during initialization.  The watcher
            // will be started explicitly from AppDelegate once the store is
            // fully constructed.
            if initialized { DepositWatcher.shared.updatePaths() }
        }
    }

    /// Indicates whether the store has completed initialization.  Some
    /// property observers use this flag to avoid triggering side effects
    /// (such as starting the deposit watcher) while the singleton is still
    /// being constructed.  It is set to true at the end of the initializer.
    private var initialized: Bool = false

    init() {
        let ud = UserDefaults.standard
        // API key
        self.apiKey = ud.string(forKey: "apiKey") ?? ""
        // Selected model
        self.selectedModel = ud.string(forKey: "selectedModel") ?? "mistral-ocr-latest"
        // Export folder (fall back to default)
        if let ef = ud.string(forKey: "exportFolder") {
            self.exportFolder = URL(fileURLWithPath: ef)
        } else {
            self.exportFolder = SettingsStore.exportDefault
        }
        // Hotkey defaults – avoid using `self` before full initialization by using local variables
        var keyCode: UInt32 = UInt32(ud.integer(forKey: "hotkeyKeyCode"))
        if keyCode == 0 { keyCode = 31 } // 'O'
        var mods: UInt32 = UInt32(ud.integer(forKey: "hotkeyModifiers"))
        if mods == 0 { mods = (1 << 8) | (1 << 17) } // cmd + shift
        self.hotkeyKeyCode = keyCode
        self.hotkeyModifiers = mods
        // Auto‑send on drop: default false
        self.autoSendOnDrop = ud.bool(forKey: "autoSendOnDrop")
        // Preserve folder structure during manual send
        self.preserveStructure = ud.bool(forKey: "preserveStructure")
        // apiKeyValid starts undefined until tested
        self.apiKeyValid = nil

        // Include images option: check both legacy and new keys.  We must
        // initialize this property before deposit settings because some
        // watchers may read includeImages.  If neither key exists the
        // default is false (do not embed images by default).  This
        // initializer assigns directly to the stored property to avoid
        // triggering the didSet observer during initialization.
        if let stored = ud.object(forKey: "includeImages") as? Bool {
            self.includeImages = stored
        } else if let legacy = ud.object(forKey: "includeImageBase64") as? Bool {
            self.includeImages = legacy
        } else {
            self.includeImages = false
        }

        // Deposit settings
        if let depositPath = ud.string(forKey: "depositFolder") {
            self.depositFolder = URL(fileURLWithPath: depositPath)
        } else {
            self.depositFolder = nil
        }
        if let exportPath = ud.string(forKey: "depositExportFolder") {
            self.depositExportFolder = URL(fileURLWithPath: exportPath)
        } else {
            self.depositExportFolder = nil
        }
        if let trashPath = ud.string(forKey: "depositTrashFolder") {
            self.depositTrashFolder = URL(fileURLWithPath: trashPath)
        } else {
            self.depositTrashFolder = nil
        }
        self.useSystemTrashForSource = ud.bool(forKey: "useSystemTrashForSource")
        // Mark the store as fully initialized.  Property observers will use
        // this flag to determine whether to call updatePaths()
        self.initialized = true
    }
}
