//
//  AIService.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation
import SwiftUI

/// Main AI service that orchestrates all providers
/// Acts as a facade for the application to interact with AI models
@Observable
@MainActor
final class AIService {
    static let shared = AIService()
    
    // MARK: - State
    
    private(set) var currentModel: StoreModel = StoreModel.defaultModel
    private(set) var isProcessing = false
    private(set) var lastError: AIProviderError?
    
    // MARK: - Providers
    
    private var openRouterProvider: OpenRouterProvider?
    private var perplexityProvider: PerplexityProvider?
    private var foundationModelsProvider: FoundationModelsProvider?
    private var customProviders: [String: CustomEndpointProvider] = [:]
    private var mockProvider: MockAIService?
    
    // MARK: - Dependencies
    
    private let keychainService = KeychainService.shared
    
    private init() {
        // Load the saved default model if available
        if let savedModelId = DefaultChatSettings.shared.defaultModelId,
           let savedModel = ModelStoreService.shared.allModels.first(where: { $0.modelId == savedModelId }) {
            currentModel = savedModel
        }
        
        Task {
            await loadProviders()
        }
    }
    
    // MARK: - Provider Management
    
    /// Load and configure providers based on stored API keys
    func loadProviders() async {
        // Load OpenRouter provider
        if let apiKey = try? await keychainService.getAPIKey(for: .openRouter) {
            openRouterProvider = OpenRouterProvider(apiKey: apiKey)
        }
        
        // Load Perplexity provider
        if let apiKey = try? await keychainService.getAPIKey(for: .perplexity) {
            perplexityProvider = PerplexityProvider(apiKey: apiKey)
        }
        
        // Foundation Models is always available on supported devices
        foundationModelsProvider = FoundationModelsProvider()
        
        // Mock provider for demo mode
        mockProvider = MockAIService()
    }
    
    /// Set API key for a provider type
    func setAPIKey(_ key: String, for providerType: AIProviderType) async throws {
        try await keychainService.saveAPIKey(key, for: providerType)
        
        switch providerType {
        case .openRouter:
            openRouterProvider = OpenRouterProvider(apiKey: key)
        case .perplexity:
            perplexityProvider = PerplexityProvider(apiKey: key)
        case .customEndpoint:
            // Custom endpoints are handled separately
            break
        case .foundationModels, .mock:
            // These don't need API keys
            break
        }
    }
    
    /// Remove API key for a provider type
    func removeAPIKey(for providerType: AIProviderType) async throws {
        try await keychainService.deleteAPIKey(for: providerType)
        
        switch providerType {
        case .openRouter:
            openRouterProvider = nil
        case .perplexity:
            perplexityProvider = nil
        case .customEndpoint, .foundationModels, .mock:
            break
        }
    }
    
    /// Check if a provider has an API key configured
    func hasAPIKey(for providerType: AIProviderType) async -> Bool {
        await keychainService.hasAPIKey(for: providerType)
    }
    
    /// Get the masked API key for display
    func getMaskedAPIKey(for providerType: AIProviderType) async -> String? {
        guard let key = try? await keychainService.getAPIKey(for: providerType) else {
            return nil
        }
        return APIKeyInfo(provider: providerType, key: key).maskedKey
    }
    
    // MARK: - Custom Endpoint Management
    
    /// Add a custom endpoint provider
    func addCustomEndpoint(_ endpoint: CustomEndpointModel) async throws {
        try await keychainService.saveCustomAPIKey(
            endpoint.apiKeyIdentifier,
            identifier: endpoint.id.uuidString
        )
        
        guard let apiKey = try? await keychainService.getCustomAPIKey(identifier: endpoint.apiKeyIdentifier) else {
            throw AIProviderError.missingAPIKey
        }
        
        let provider = CustomEndpointProvider(
            apiKey: apiKey,
            baseURL: endpoint.baseURL
        )
        customProviders[endpoint.id.uuidString] = provider
    }
    
    /// Remove a custom endpoint provider
    func removeCustomEndpoint(id: String) async throws {
        try await keychainService.deleteCustomAPIKey(identifier: id)
        customProviders.removeValue(forKey: id)
    }
    
    // MARK: - Model Selection
    
    /// Set the current model for chat
    func setCurrentModel(_ model: StoreModel) {
        currentModel = model
        lastError = nil
        
        // Persist as the default model
        DefaultChatSettings.shared.defaultModelId = model.modelId
    }
    
    /// Check if the current model is ready to use
    var isCurrentModelReady: Bool {
        get async {
            await isModelReady(currentModel)
        }
    }
    
    /// Check if a specific model is ready to use
    func isModelReady(_ model: StoreModel) async -> Bool {
        switch model.providerType {
        case .openRouter:
            guard let provider = openRouterProvider else { return false }
            return await provider.isConfigured
        case .perplexity:
            guard let provider = perplexityProvider else { return false }
            return await provider.isConfigured
        case .foundationModels:
            guard let provider = foundationModelsProvider else { return false }
            return await provider.isConfigured
        case .customEndpoint:
            guard let provider = customProviders[model.id] else { return false }
            return await provider.isConfigured
        case .mock:
            return true
        }
    }
    
    // MARK: - Chat Methods
    
    /// Send a message and stream the response
    func streamMessage(
        messages: [ChatMessage],
        model: StoreModel? = nil,
        onUpdate: @escaping (StreamingUpdate) -> Void
    ) async throws {
        let targetModel = model ?? currentModel
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        do {
            let provider = try await getProvider(for: targetModel)
            
            try await provider.streamMessage(
                messages: messages,
                model: targetModel,
                onUpdate: { update in
                    await MainActor.run {
                        onUpdate(update)
                    }
                }
            )
        } catch let error as AIProviderError {
            lastError = error
            throw error
        } catch {
            let providerError = AIProviderError.networkError(underlying: error)
            lastError = providerError
            throw providerError
        }
    }
    
    /// Send a message and get the complete response
    func sendMessage(
        messages: [ChatMessage],
        model: StoreModel? = nil
    ) async throws -> String {
        let targetModel = model ?? currentModel
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        do {
            let provider = try await getProvider(for: targetModel)
            return try await provider.sendMessage(messages: messages, model: targetModel)
        } catch let error as AIProviderError {
            lastError = error
            throw error
        } catch {
            let providerError = AIProviderError.networkError(underlying: error)
            lastError = providerError
            throw providerError
        }
    }
    
    /// Cancel any ongoing request
    func cancelCurrentRequest() async {
        switch currentModel.providerType {
        case .openRouter:
            await openRouterProvider?.cancelCurrentRequest()
        case .perplexity:
            await perplexityProvider?.cancelCurrentRequest()
        case .foundationModels:
            await foundationModelsProvider?.cancelCurrentRequest()
        case .customEndpoint:
            if let provider = customProviders[currentModel.id] {
                await provider.cancelCurrentRequest()
            }
        case .mock:
            break
        }
        isProcessing = false
    }
    
    // MARK: - Validation
    
    /// Validate an API key for a provider
    func validateAPIKey(_ key: String, for providerType: AIProviderType) async -> Bool {
        switch providerType {
        case .openRouter:
            let provider = OpenRouterProvider(apiKey: key)
            return (try? await provider.validateConfiguration()) ?? false
        case .perplexity:
            let provider = PerplexityProvider(apiKey: key)
            return (try? await provider.validateConfiguration()) ?? false
        case .customEndpoint:
            return !key.isEmpty
        case .foundationModels, .mock:
            return true
        }
    }
    
    // MARK: - Private Helpers
    
    private func getProvider(for model: StoreModel) async throws -> any AIProvider {
        switch model.providerType {
        case .openRouter:
            guard let provider = openRouterProvider else {
                throw AIProviderError.missingAPIKey
            }
            return provider
            
        case .perplexity:
            guard let provider = perplexityProvider else {
                throw AIProviderError.missingAPIKey
            }
            return provider
            
        case .foundationModels:
            guard let provider = foundationModelsProvider else {
                throw AIProviderError.unsupported(feature: "Foundation Models")
            }
            return provider
            
        case .customEndpoint:
            guard let provider = customProviders[model.id] else {
                throw AIProviderError.missingAPIKey
            }
            return provider
            
        case .mock:
            return MockAIProvider()
        }
    }
}

// MARK: - Mock AI Provider (for demo mode)

actor MockAIProvider: AIProvider {
    let providerType: AIProviderType = .mock
    let configuration = ProviderConfiguration(providerType: .mock)
    var isConfigured: Bool { true }
    
    private let mockResponses: [String] = [
        "That's a fascinating question! Let me think about this for a moment. In my experience, the key lies in understanding the underlying principles rather than just memorizing solutions. Would you like me to elaborate on any specific aspect?",
        "Great point! Here's what I think about this: The most effective approach combines both theoretical knowledge and practical application. The balance between these two often determines success in complex problem-solving scenarios.",
        "I appreciate you bringing this up. This is actually a topic I find quite interesting. There are multiple perspectives to consider here, and I'd be happy to walk you through the main ones if you're interested.",
        "Absolutely! Let me break this down into manageable parts. First, we need to understand the core concept. Then, we can explore how it applies to your specific situation. Finally, we can discuss potential solutions.",
        "That's an excellent observation. You've touched on something that many people overlook. The nuances here are important because they often determine the difference between a good solution and a great one."
    ]
    
    func streamMessage(
        messages: [ChatMessage],
        model: StoreModel,
        onUpdate: @escaping @Sendable (StreamingUpdate) async -> Void
    ) async throws {
        let response = mockResponses.randomElement() ?? mockResponses[0]
        var currentText = ""
        
        for character in response {
            try Task.checkCancellation()
            currentText.append(character)
            await onUpdate(StreamingUpdate(content: currentText))
            
            let delay: UInt64
            if character == "." || character == "!" || character == "?" {
                delay = UInt64.random(in: 150_000_000...300_000_000)
            } else if character == "," {
                delay = UInt64.random(in: 80_000_000...150_000_000)
            } else {
                delay = UInt64.random(in: 12_000_000...30_000_000)
            }
            
            try? await Task.sleep(nanoseconds: delay)
        }
    }
    
    func validateConfiguration() async throws -> Bool {
        return true
    }
    
    func cancelCurrentRequest() {}
}
