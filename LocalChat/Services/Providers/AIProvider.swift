//
//  AIProvider.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation

// MARK: - Provider Types

/// Supported AI provider types
enum AIProviderType: String, Codable, CaseIterable, Identifiable {
    case openRouter = "openrouter"
    case perplexity = "perplexity"
    case foundationModels = "foundation_models"
    case customEndpoint = "custom_endpoint"
    case mock = "mock"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .perplexity: return "Perplexity"
        case .foundationModels: return "Apple Intelligence"
        case .customEndpoint: return "Custom Endpoint"
        case .mock: return "Demo Mode"
        }
    }
    
    var iconName: String {
        switch self {
        case .openRouter: return "openrouter-icon"
        case .perplexity: return "perplexity-icon"
        case .foundationModels: return "apple.intelligence"
        case .customEndpoint: return "server.rack"
        case .mock: return "sparkles"
        }
    }
    
    /// Whether the icon is an SF Symbol (true) or asset catalog image (false)
    var isSystemIcon: Bool {
        switch self {
        case .openRouter, .perplexity: return false
        case .foundationModels, .customEndpoint, .mock: return true
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .openRouter, .perplexity, .customEndpoint: return true
        case .foundationModels, .mock: return false
        }
    }
    
    var supportsStreaming: Bool {
        switch self {
        case .openRouter, .perplexity, .customEndpoint, .foundationModels: return true
        case .mock: return true
        }
    }
}

// MARK: - Chat Message Types

/// Content part for multimodal messages
enum MessageContentPart: Codable, Sendable {
    case text(String)
    case imageURL(url: String, detail: String?) // For URL-based images
    case imageData(base64: String, mimeType: String) // For base64 encoded images
    case file(filename: String, base64: String, mimeType: String) // For files (PDFs, docs, etc.)
    
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
        case file
    }
    
    enum ImageURLKeys: String, CodingKey {
        case url
        case detail
    }
    
    enum FileKeys: String, CodingKey {
        case filename
        case fileData = "file_data"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url, let detail):
            try container.encode("image_url", forKey: .type)
            var imageContainer = container.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .imageUrl)
            try imageContainer.encode(url, forKey: .url)
            if let detail = detail {
                try imageContainer.encode(detail, forKey: .detail)
            }
        case .imageData(let base64, let mimeType):
            try container.encode("image_url", forKey: .type)
            var imageContainer = container.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .imageUrl)
            try imageContainer.encode("data:\(mimeType);base64,\(base64)", forKey: .url)
        case .file(let filename, let base64, let mimeType):
            try container.encode("file", forKey: .type)
            var fileContainer = container.nestedContainer(keyedBy: FileKeys.self, forKey: .file)
            try fileContainer.encode(filename, forKey: .filename)
            try fileContainer.encode("data:\(mimeType);base64,\(base64)", forKey: .fileData)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image_url":
            let imageContainer = try container.nestedContainer(keyedBy: ImageURLKeys.self, forKey: .imageUrl)
            let url = try imageContainer.decode(String.self, forKey: .url)
            let detail = try imageContainer.decodeIfPresent(String.self, forKey: .detail)
            self = .imageURL(url: url, detail: detail)
        case "file":
            let fileContainer = try container.nestedContainer(keyedBy: FileKeys.self, forKey: .file)
            let filename = try fileContainer.decode(String.self, forKey: .filename)
            let fileData = try fileContainer.decode(String.self, forKey: .fileData)
            // Parse the data URL
            if fileData.hasPrefix("data:") {
                let parts = fileData.dropFirst(5).split(separator: ";", maxSplits: 1)
                let mimeType = String(parts.first ?? "application/octet-stream")
                let base64Part = parts.last.flatMap { $0.hasPrefix("base64,") ? String($0.dropFirst(7)) : nil } ?? ""
                self = .file(filename: filename, base64: base64Part, mimeType: mimeType)
            } else {
                self = .file(filename: filename, base64: fileData, mimeType: "application/octet-stream")
            }
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }
}

/// A message in a conversation for API calls
struct ChatMessage: Codable, Sendable {
    let role: Role
    let content: MessageContent
    
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }
    
    /// Content can be either a simple string or an array of content parts (for multimodal)
    enum MessageContent: Codable, Sendable {
        case text(String)
        case multipart([MessageContentPart])
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .multipart(let parts):
                try container.encode(parts)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else if let parts = try? container.decode([MessageContentPart].self) {
                self = .multipart(parts)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Content must be string or array")
            }
        }
        
        /// Get the text content (for display or simple APIs)
        var textContent: String {
            switch self {
            case .text(let string):
                return string
            case .multipart(let parts):
                return parts.compactMap { part in
                    if case .text(let text) = part {
                        return text
                    }
                    return nil
                }.joined(separator: " ")
            }
        }
    }
    
    /// Initialize with simple text content
    init(role: Role, content: String) {
        self.role = role
        self.content = .text(content)
    }
    
    /// Initialize with multipart content (for images + text)
    init(role: Role, parts: [MessageContentPart]) {
        self.role = role
        self.content = .multipart(parts)
    }
}

// MARK: - Provider Errors

enum AIProviderError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case invalidEndpoint
    case networkError(underlying: Error)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String?)
    case invalidResponse
    case modelNotAvailable(modelId: String)
    case contextLengthExceeded(limit: Int, requested: Int)
    case cancelled
    case unsupported(feature: String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is required for this provider"
        case .invalidAPIKey:
            return "The API key is invalid or has expired"
        case .invalidEndpoint:
            return "The endpoint URL is invalid"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Rate limited. Try again in \(Int(retry)) seconds"
            }
            return "Rate limited. Please try again later"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .invalidResponse:
            return "Received an invalid response from the server"
        case .modelNotAvailable(let modelId):
            return "Model '\(modelId)' is not available"
        case .contextLengthExceeded(let limit, let requested):
            return "Context length exceeded (limit: \(limit), requested: \(requested))"
        case .cancelled:
            return "Request was cancelled"
        case .unsupported(let feature):
            return "Feature not supported: \(feature)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .missingAPIKey:
            return "Add your API key in Settings > API Keys"
        case .invalidAPIKey:
            return "Check your API key in Settings or generate a new one"
        case .invalidEndpoint:
            return "Verify the endpoint URL in your custom model configuration"
        case .networkError:
            return "Check your internet connection and try again"
        case .rateLimited:
            return "Wait a moment before sending another message"
        case .serverError:
            return "The service may be experiencing issues. Try again later"
        case .invalidResponse:
            return "Try sending your message again"
        case .modelNotAvailable:
            return "Select a different model from the Model Store"
        case .contextLengthExceeded:
            return "Try starting a new chat or use a model with larger context"
        case .cancelled:
            return nil
        case .unsupported:
            return "Try a different provider or model"
        }
    }
}

// MARK: - Provider Configuration

/// Configuration for a provider instance
struct ProviderConfiguration: Codable, Sendable {
    let providerType: AIProviderType
    var apiKey: String?
    var baseURL: String?
    var organizationId: String?
    var additionalHeaders: [String: String]?
    
    // Model-specific settings
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var frequencyPenalty: Double?
    var presencePenalty: Double?
    
    init(
        providerType: AIProviderType,
        apiKey: String? = nil,
        baseURL: String? = nil,
        organizationId: String? = nil,
        additionalHeaders: [String: String]? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil
    ) {
        self.providerType = providerType
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.organizationId = organizationId
        self.additionalHeaders = additionalHeaders
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
    }
}

// MARK: - Provider Protocol

/// Protocol that all AI providers must conform to
protocol AIProvider: Actor {
    /// The type of this provider
    var providerType: AIProviderType { get }
    
    /// Current configuration
    var configuration: ProviderConfiguration { get }
    
    /// Check if the provider is properly configured and ready to use
    var isConfigured: Bool { get }
    
    /// Send a message and receive a complete response
    func sendMessage(
        messages: [ChatMessage],
        model: StoreModel
    ) async throws -> String
    
    /// Send a message and receive a streaming response
    /// - Parameters:
    ///   - messages: The conversation messages
    ///   - model: The model to use
    ///   - onUpdate: Callback with streaming update containing content and optional reasoning
    func streamMessage(
        messages: [ChatMessage],
        model: StoreModel,
        onUpdate: @escaping @Sendable (StreamingUpdate) async -> Void
    ) async throws
    
    /// Validate the current configuration (e.g., test API key)
    func validateConfiguration() async throws -> Bool
    
    /// Cancel any ongoing requests
    func cancelCurrentRequest()
}

/// Represents a streaming update from an AI provider
struct StreamingUpdate: Sendable {
    /// The accumulated content (visible response)
    let content: String
    /// The accumulated reasoning content (from reasoning_details or <think> tags)
    let reasoning: String?
    /// Whether the model is currently in the reasoning phase
    let isReasoning: Bool
    /// Whether reasoning has completed
    let reasoningComplete: Bool
    /// Citations/sources from Perplexity Sonar models or web search (array of URLs)
    let citations: [String]?
    /// Whether the model is currently searching the web
    let isSearchingWeb: Bool
    
    init(content: String, reasoning: String? = nil, isReasoning: Bool = false, reasoningComplete: Bool = false, citations: [String]? = nil, isSearchingWeb: Bool = false) {
        self.content = content
        self.reasoning = reasoning
        self.isReasoning = isReasoning
        self.reasoningComplete = reasoningComplete
        self.citations = citations
        self.isSearchingWeb = isSearchingWeb
    }
}

// MARK: - Default Implementations

extension AIProvider {
    /// Default implementation that streams and collects the full response
    func sendMessage(
        messages: [ChatMessage],
        model: StoreModel
    ) async throws -> String {
        var fullResponse = ""
        try await streamMessage(messages: messages, model: model) { update in
            fullResponse = update.content
        }
        return fullResponse
    }
    
    /// Default validation just checks if configured
    func validateConfiguration() async throws -> Bool {
        return isConfigured
    }
}
