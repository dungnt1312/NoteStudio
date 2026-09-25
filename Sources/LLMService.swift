import Foundation
import Security

// MARK: - Nhiều LLM provider theo chuẩn OpenAI (endpoint /chat/completions)
// User cấu hình thoải mái: OpenAI, OpenRouter, Groq, Ollama local (http://localhost:11434/v1), vLLM…
// API key lưu file secrets.json (chmod 600) — KHÔNG dùng Keychain vì app build ad-hoc
// bị macOS hỏi password keychain mỗi lần rebuild.

enum LLMService {
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    struct Provider: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var baseURL: String
        var model: String

        init(name: String, baseURL: String, model: String) {
            self.id = UUID()
            self.name = name
            self.baseURL = baseURL
            self.model = model
        }
    }

    private static let providersKey = "llm.providers"
    private static let activeIDKey = "llm.activeProviderID"

    // MARK: Danh sách provider (phần cấu hình nằm UserDefaults, API key nằm Keychain)

    static var providers: [Provider] {
        get {
            guard let data = UserDefaults.standard.data(forKey: providersKey),
                  let list = try? JSONDecoder().decode([Provider].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: providersKey)
            }
        }
    }

    static var activeProviderID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: activeIDKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: activeIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeIDKey)
            }
        }
    }

    static var activeProvider: Provider {
        let list = providers
        if let id = activeProviderID, let match = list.first(where: { $0.id == id }) {
            return match
        }
        return list.first ?? Provider(name: "OpenAI", baseURL: defaultBaseURL, model: defaultModel)
    }

    static func key(for providerID: UUID) -> String {
        SecretStore.read(account: keyAccount(providerID)) ?? ""
    }

    static func setKey(_ key: String, for providerID: UUID) {
        if key.isEmpty {
            SecretStore.delete(account: keyAccount(providerID))
        } else {
            SecretStore.save(key, account: keyAccount(providerID))
        }
    }

    private static func keyAccount(_ id: UUID) -> String { "llm.key.\(id.uuidString)" }

    // MARK: Khởi động — migrate cấu hình bản cũ hoặc seed 2 provider mẫu

    static func bootstrap() {
        // Dọn item Keychain còn sót từ bản cũ — chỉ delete, không read nên không bao giờ hiện hộp thoại
        KeychainCleanup.removeLegacyItems()

        guard providers.isEmpty else { return }

        let legacyBase = UserDefaults.standard.string(forKey: "llm.baseURL") ?? ""
        let legacyModel = UserDefaults.standard.string(forKey: "llm.model") ?? ""
        let legacyUDKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""

        if !legacyBase.isEmpty || !legacyModel.isEmpty || !legacyUDKey.isEmpty {
            // v1.3: một provider duy nhất → đưa vào danh sách
            let provider = Provider(
                name: "Mặc định",
                baseURL: legacyBase.isEmpty ? defaultBaseURL : legacyBase,
                model: legacyModel.isEmpty ? defaultModel : legacyModel
            )
            providers = [provider]
            activeProviderID = provider.id
            if !legacyUDKey.isEmpty { setKey(legacyUDKey, for: provider.id) }
        } else {
            // lần đầu chạy: seed sẵn 2 lựa chọn mẫu
            let openai = Provider(name: "OpenAI", baseURL: defaultBaseURL, model: defaultModel)
            let ollama = Provider(name: "Ollama (local)", baseURL: "http://localhost:11434/v1", model: "llama3.2")
            providers = [openai, ollama]
            activeProviderID = openai.id
        }

        // dọn rác cấu hình cũ
        UserDefaults.standard.removeObject(forKey: "openai_api_key")
        UserDefaults.standard.removeObject(forKey: "llm.baseURL")
        UserDefaults.standard.removeObject(forKey: "llm.model")
    }

    // MARK: Chat completions qua provider chỉ định (mặc định: provider đang chọn)

    struct LLMToolCall {
        let id: String
        let name: String
        let argumentsJSON: String
    }

    struct LLMResponse {
        let content: String
        let toolCalls: [LLMToolCall]
    }

    static func chat(
        messages: [[String: String]],
        temperature: Double = 0.3,
        provider overrideProvider: Provider? = nil
    ) async throws -> String {
        let response = try await chatWithTools(messages: messages.map { $0 as [String: Any] }, tools: [], temperature: temperature, provider: overrideProvider)
        return response.content.isEmpty ? " " : response.content
    }

    static func chatWithTools(
        messages: [[String: Any]],
        tools: [[String: Any]],
        temperature: Double = 0.3,
        provider overrideProvider: Provider? = nil
    ) async throws -> LLMResponse {
        let provider = overrideProvider ?? activeProvider

        var base = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/chat/completions") else {
            throw LLMError.invalidBaseURL(base)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = key(for: provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "model": provider.model,
            "temperature": temperature,
            "messages": messages
        ]
        if !tools.isEmpty {
            payload["tools"] = tools.map { ["type": "function", "function": $0] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Auto-retry với lỗi tạm thời: rate limit (429), server quá tải (5xx), mạng chập chờn
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw LLMError.requestFailed("Không nhận được phản hồi từ provider")
                }
                guard http.statusCode == 200 else {
                    let apiMessage = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                        .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                        ?? String(data: data, encoding: .utf8)
                        ?? "Lỗi không xác định"
                    let error = LLMError.http(http.statusCode, apiMessage)
                    if [429, 500, 502, 503, 504].contains(http.statusCode), attempt < 3 {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                        continue
                    }
                    throw error
                }

                guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any] else {
                    throw LLMError.requestFailed("Không đọc được nội dung phản hồi")
                }

                let content = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var toolCalls: [LLMToolCall] = []
                if let calls = message["tool_calls"] as? [[String: Any]] {
                    for call in calls {
                        guard let id = call["id"] as? String,
                              let function = call["function"] as? [String: Any],
                              let name = function["name"] as? String else { continue }
                        let argsJSON: String
                        if let raw = function["arguments"] as? String {
                            argsJSON = raw
                        } else if let dict = function["arguments"] as? [String: Any],
                                  let data = try? JSONSerialization.data(withJSONObject: dict) {
                            argsJSON = String(data: data, encoding: .utf8) ?? "{}"
                        } else {
                            argsJSON = "{}"
                        }
                        toolCalls.append(LLMToolCall(id: id, name: name, argumentsJSON: argsJSON))
                    }
                }
                return LLMResponse(content: content, toolCalls: toolCalls)
            } catch let error as LLMError {
                throw error
            } catch {
                if attempt < 3, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
                    continue
                }
                throw error
            }
        }
    }

    // MARK: Streaming (SSE) — chữ hiện dần theo token, vẫn hỗ trợ tool_calls

    @MainActor
    static func chatStreaming(
        messages: [[String: Any]],
        tools: [[String: Any]],
        temperature: Double = 0.3,
        provider overrideProvider: Provider? = nil,
        onDelta: @escaping (String) -> Void
    ) async throws -> LLMResponse {
        let provider = overrideProvider ?? activeProvider

        var base = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/chat/completions") else {
            throw LLMError.invalidBaseURL(base)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = key(for: provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "model": provider.model,
            "temperature": temperature,
            "messages": messages,
            "stream": true
        ]
        if !tools.isEmpty {
            payload["tools"] = tools.map { ["type": "function", "function": $0] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.requestFailed("Không nhận được phản hồi từ provider")
        }
        guard http.statusCode == 200 else {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 400 { break }
            }
            throw LLMError.http(http.statusCode, body.isEmpty ? "Lỗi không xác định" : body)
        }

        var content = ""
        var callAccumulators: [Int: (id: String, name: String, args: String)] = [:]

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }

            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let fragment = delta["content"] as? String, !fragment.isEmpty {
                content += fragment
                onDelta(fragment)
            }
            if let toolDeltas = delta["tool_calls"] as? [[String: Any]] {
                for toolDelta in toolDeltas {
                    let index = toolDelta["index"] as? Int ?? 0
                    var acc = callAccumulators[index] ?? ("", "", "")
                    if let id = toolDelta["id"] as? String, !id.isEmpty { acc.id = id }
                    if let function = toolDelta["function"] as? [String: Any] {
                        if let name = function["name"] as? String, !name.isEmpty { acc.name += name }
                        if let args = function["arguments"] as? String { acc.args += args }
                    }
                    callAccumulators[index] = acc
                }
            }
        }

        let toolCalls = callAccumulators
            .sorted { $0.key < $1.key }
            .map { entry in
                LLMToolCall(
                    id: entry.value.id.isEmpty ? UUID().uuidString : entry.value.id,
                    name: entry.value.name,
                    argumentsJSON: entry.value.args.isEmpty ? "{}" : entry.value.args
                )
            }
        return LLMResponse(content: content, toolCalls: toolCalls)
    }

    // MARK: Các tác vụ cụ thể trong app

    static func suggestTitle(content: String) async throws -> String {
        let raw = try await chat(messages: [
            ["role": "system",
             "content": "Bạn đặt tiêu đề cho ghi chú. Chỉ trả về duy nhất tiêu đề, tối đa 8 từ, không dấu ngoặc kép, bằng tiếng Việt."],
            ["role": "user", "content": String(content.prefix(1200))]
        ], temperature: 0.4)
        return raw
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func suggestTags(content: String) async throws -> [String] {
        let raw = try await chat(messages: [
            ["role": "system",
             "content": "Bạn gắn thẻ cho ghi chú. Chỉ trả về 3-5 thẻ, mỗi thẻ 1-2 từ, chữ thường, phân tách bởi dấu phẩy, không giải thích gì thêm."],
            ["role": "user", "content": String(content.prefix(1200))]
        ], temperature: 0.3)
        return raw
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            }
            .filter { !$0.isEmpty }
    }
}

enum LLMError: LocalizedError {
    case invalidBaseURL(String)
    case http(Int, String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            return "Base URL không hợp lệ: \(url)"
        case .http(let code, let message):
            return "Lỗi LLM provider (\(code)): \(message)"
        case .requestFailed(let message):
            return message
        }
    }
}

// MARK: - Lưu API key vào file cục bộ secrets.json (quyền 0600)

enum SecretStore {
    private static var fileURL: URL {
        StudioPaths.dataDirectory.appendingPathComponent("secrets.json")
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private static func saveAll(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func read(account: String) -> String? {
        loadAll()[account]
    }

    static func save(_ value: String, account: String) {
        var all = loadAll()
        all[account] = value
        saveAll(all)
    }

    static func delete(account: String) {
        var all = loadAll()
        all.removeValue(forKey: account)
        saveAll(all)
    }
}

// MARK: - Dọn Keychain item cũ (thời còn dùng Keychain)
// Chỉ gọi SecItemDelete — delete không bao giờ làm macOS hiện hộp thoại password.

private enum KeychainCleanup {
    static func removeLegacyItems() {
        let service = "com.demo.notestudio"
        for account in ["llm.apiKey"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
