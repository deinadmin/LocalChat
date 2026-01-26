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
        case .openRouter: return "network"
        case .perplexity: return "magnifyingglass.circle.fill"
        case .foundationModels: return "apple.intelligence"
        case .customEndpoint: return "server.rack"
        case .mock: return "sparkles"
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

/// A message in a conversation for API calls
struct ChatMessage: Codable, Sendable {
    let role: Role
    let content: String
    
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
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
    /// Citations/sources from Perplexity Sonar models (array of URLs)
    let citations: [String]?
    
    init(content: String, reasoning: String? = nil, isReasoning: Bool = false, reasoningComplete: Bool = false, citations: [String]? = nil) {
        self.content = content
        self.reasoning = reasoning
        self.isReasoning = isReasoning
        self.reasoningComplete = reasoningComplete
        self.citations = citations
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
