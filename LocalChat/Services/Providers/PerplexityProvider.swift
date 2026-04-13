//
//  PerplexityProvider.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation

/// Perplexity API provider implementation
/// Supports Perplexity's search-enhanced AI models with real-time web access
actor PerplexityProvider: AIProvider {
    let providerType: AIProviderType = .perplexity
    private(set) var configuration: ProviderConfiguration
    
    private let baseURL = "https://api.perplexity.ai"
    private var currentTask: Task<Void, Never>?
    
    var isConfigured: Bool {
        configuration.apiKey != nil && !(configuration.apiKey?.isEmpty ?? true)
    }
    
    init(configuration: ProviderConfiguration) {
        self.configuration = configuration
    }
    
    convenience init(apiKey: String?) {
        self.init(configuration: ProviderConfiguration(
            providerType: .perplexity,
            apiKey: apiKey
        ))
    }
    
    // MARK: - Configuration
    
    func updateAPIKey(_ apiKey: String?) {
        configuration = ProviderConfiguration(
            providerType: .perplexity,
            apiKey: apiKey,
            temperature: configuration.temperature,
            maxTokens: configuration.maxTokens
        )
    }
    
    // MARK: - API Methods
    
    func streamMessage(
        messages: [ChatMessage],
        model: StoreModel,
        onUpdate: @escaping @Sendable (StreamingUpdate) async -> Void
    ) async throws {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body = PerplexityRequest(
            model: model.modelId,
            messages: messages.map { PerplexityMessage(role: $0.role.rawValue, content: $0.content.textContent) },
            stream: true,
            temperature: configuration.temperature ?? 0.2,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        try handleHTTPStatus(httpResponse)
        
        var fullContent = ""
        var citations: [String]? = nil
        
        for try await line in bytes.lines {
            // Check for cancellation
            try Task.checkCancellation()
            
            // Parse SSE data
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            
            if data == "[DONE]" { break }
            
            guard let jsonData = data.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(PerplexityStreamChunk.self, from: jsonData) else {
                continue
            }
            
            // Extract citations from the chunk if present (usually in the final chunk)
            if let chunkCitations = chunk.citations, !chunkCitations.isEmpty {
                citations = chunkCitations
            }
            
            if let delta = chunk.choices.first?.delta,
               let content = delta.content {
                fullContent += content
                await onUpdate(StreamingUpdate(content: fullContent, citations: citations))
            }
        }
        
        // Send final update with citations if we have them
        if citations != nil {
            await onUpdate(StreamingUpdate(content: fullContent, citations: citations))
        }
    }
    
    func sendMessage(
        messages: [ChatMessage],
        model: StoreModel
    ) async throws -> String {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body = PerplexityRequest(
            model: model.modelId,
            messages: messages.map { PerplexityMessage(role: $0.role.rawValue, content: $0.content.textContent) },
            stream: false,
            temperature: configuration.temperature ?? 0.2,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        try handleHTTPStatus(httpResponse)
        
        let result = try JSONDecoder().decode(PerplexityResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw AIProviderError.invalidResponse
        }
        
        return content
    }
    
    func validateConfiguration() async throws -> Bool {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            return false
        }
        
        // Validate by making a minimal chat request
        // Perplexity API documentation: https://docs.perplexity.ai/getting-started/quickstart
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept") // Required by Perplexity API
        request.timeoutInterval = 30
        
        // Use minimal request with current model name (sonar-pro per docs)
        let body: [String: Any] = [
            "model": "sonar",
            "messages": [["role": "user", "content": "test"]]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            // Debug logging
            if httpResponse.statusCode != 200 {
                if let responseStr = String(data: data, encoding: .utf8) {
                    print("Perplexity validation failed (\(httpResponse.statusCode)): \(responseStr)")
                }
            }
            
            // 200 = success, 401 = invalid key
            return httpResponse.statusCode == 200
        } catch {
            print("Perplexity validation network error: \(error.localizedDescription)")
            return false
        }
    }
    
    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - Helpers
    
    private func handleHTTPStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw AIProviderError.invalidAPIKey
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw AIProviderError.rateLimited(retryAfter: retryAfter)
        case 400...499:
            throw AIProviderError.serverError(statusCode: response.statusCode, message: "Client error")
        case 500...599:
            throw AIProviderError.serverError(statusCode: response.statusCode, message: "Server error")
        default:
            throw AIProviderError.serverError(statusCode: response.statusCode, message: nil)
        }
    }
}

// MARK: - Request/Response Types

private struct PerplexityRequest: Encodable, Sendable {
    let model: String
    let messages: [PerplexityMessage]
    let stream: Bool
    let temperature: Double?
    let max_tokens: Int?
}

private struct PerplexityMessage: Codable, Sendable {
    let role: String
    let content: String
}

private struct PerplexityResponse: Decodable, Sendable {
    let choices: [PerplexityChoice]
    let citations: [String]?
}

private struct PerplexityChoice: Decodable, Sendable {
    let message: PerplexityMessage
}

private struct PerplexityStreamChunk: Decodable, Sendable {
    let choices: [PerplexityStreamChoice]
    let citations: [String]?
}

private struct PerplexityStreamChoice: Decodable, Sendable {
    let delta: PerplexityDelta?
}

private struct PerplexityDelta: Decodable, Sendable {
    let content: String?
}
