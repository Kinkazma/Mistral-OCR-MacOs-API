import Foundation

enum ModelCatalog {
    static func fetchModels() async throws -> [String] {
        guard let key = SettingsStore.shared.apiKey.nonEmpty else { return ["mistral-ocr-latest"] }
        var req = URLRequest(url: URL(string: "https://api.mistral.ai/v1/models")!)
        req.httpMethod = "GET"
        req.addValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let ids = decoded.data.map { $0.id }.filter { $0.hasPrefix("mistral-ocr") }
        let uniq = Array(Set(ids)).sorted()
        var list = uniq
        if list.contains("mistral-ocr-latest") == false { list.insert("mistral-ocr-latest", at: 0) }
        return list
    }
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

fileprivate extension String {
    var nonEmpty: String? { self.isEmpty ? nil : self }
}
