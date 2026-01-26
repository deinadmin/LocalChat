//
//  CustomEndpointProvider.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation

/// Custom OpenAI-compatible endpoint provider
/// Supports any API that follows the OpenAI chat completions format
actor CustomEndpointProvider: AIProvider {
    let providerType: AIProviderType = .customEndpoint
    private(set) var configuration: ProviderConfiguration
    
    private var currentTask: Task<Void, Never>?
    
    var isConfigured: Bool {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty,
              let baseURL = configuration.baseURL, !baseURL.isEmpty else {
            return false
        }
        return true
    }
    
    init(configuration: ProviderConfiguration) {
        self.configuration = configuration
    }
    
    init(apiKey: String, baseURL: String, additionalHeaders: [String: String]? = nil) {
        self.configuration = ProviderConfiguration(
            providerType: .customEndpoint,
            apiKey: apiKey,
            baseURL: baseURL,
            additionalHeaders: additionalHeaders
        )
    }
    
    // MARK: - Configuration
    
    func updateConfiguration(apiKey: String? = nil, baseURL: String? = nil) {
        configuration = ProviderConfiguration(
            providerType: .customEndpoint,
            apiKey: apiKey ?? configuration.apiKey,
            baseURL: baseURL ?? configuration.baseURL,
            additionalHeaders: configuration.additionalHeaders,
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
        
        guard let baseURLString = configuration.baseURL,
              let baseURL = URL(string: baseURLString) else {
            throw AIProviderError.invalidEndpoint
        }
        
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add any custom headers
        if let headers = configuration.additionalHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        let body = OpenAIRequest(
            model: model.modelId,
            messages: messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            temperature: configuration.temperature,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        try handleHTTPStatus(httpResponse)
        
        var fullContent = ""
        
        for try await line in bytes.lines {
            try Task.checkCancellation()
            
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            
            if data == "[DONE]" { break }
            
            guard let jsonData = data.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: jsonData),
                  let delta = chunk.choices.first?.delta,
                  let content = delta.content else {
                continue
            }
            
            fullContent += content
            await onUpdate(StreamingUpdate(content: fullContent))
        }
    }
    
    func sendMessage(
        messages: [ChatMessage],
        model: StoreModel
    ) async throws -> String {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        
        guard let baseURLString = configuration.baseURL,
              let baseURL = URL(string: baseURLString) else {
            throw AIProviderError.invalidEndpoint
        }
        
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let headers = configuration.additionalHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        let body = OpenAIRequest(
            model: model.modelId,
            messages: messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) },
            stream: false,
            temperature: configuration.temperature,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        try handleHTTPStatus(httpResponse)
        
        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw AIProviderError.invalidResponse
        }
        
        return content
    }
    
    func validateConfiguration() async throws -> Bool {
        guard isConfigured else { return false }
        
        guard let baseURLString = configuration.baseURL,
              let baseURL = URL(string: baseURLString) else {
            return false
        }
        
        // Try to reach the models endpoint
        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.setValue("Bearer \(configuration.apiKey ?? "")", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
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

// MARK: - OpenAI-Compatible Request/Response Types

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool
    let temperature: Double?
    let max_tokens: Int?
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIMessage
}

private struct OpenAIStreamChunk: Decodable {
    let choices: [OpenAIStreamChoice]
}

private struct OpenAIStreamChoice: Decodable {
    let delta: OpenAIDelta?
}

private struct OpenAIDelta: Decodable {
    let content: String?
}
