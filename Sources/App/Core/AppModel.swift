import Foundation
import SwiftUI

final class AppModel: ObservableObject {
    @Published var settings = SettingsStore.shared
    @Published var models: [String] = []
    
    init() {
        Task { await refreshModels() }
    }
    
    @MainActor
    func refreshModels() async {
        do {
            self.models = try await ModelCatalog.fetchModels()
        } catch {
            self.models = ["mistral-ocr-latest"]
        }
    }
}
