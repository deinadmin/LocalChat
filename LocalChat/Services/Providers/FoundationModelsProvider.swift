//
//  FoundationModelsProvider.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Foundation Models provider for on-device AI inference
/// Uses Apple Intelligence for private, fast, local processing
actor FoundationModelsProvider: AIProvider {
    let providerType: AIProviderType = .foundationModels
    private(set) var configuration: ProviderConfiguration
    
    private var currentTask: Task<Void, Never>?
    
    var isConfigured: Bool {
        // Foundation Models doesn't require API key, check device capability
        return isSupported
    }
    
    var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }
    
    /// Check if Apple Intelligence is fully available and enabled on this device
    /// This checks the actual runtime availability, not just OS version support
    nonisolated static var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            return availability == .available
        }
        #endif
        return false
    }
    
    /// Get the reason why Apple Intelligence is unavailable, if any
    nonisolated static var unavailabilityReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                return nil
            case .unavailable(let reason):
                // Return a user-friendly description of the unavailability reason
                return String(describing: reason)
            @unknown default:
                return "Unknown availability status"
            }
        }
        #endif
        return "Requires iOS 26 or later"
    }
    
    init(configuration: ProviderConfiguration = ProviderConfiguration(providerType: .foundationModels)) {
        self.configuration = configuration
    }
    
    // MARK: - API Methods
    
    func streamMessage(
        messages: [ChatMessage],
        model: StoreModel,
        onUpdate: @escaping @Sendable (StreamingUpdate) async -> Void
    ) async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            try await streamWithFoundationModels(messages: messages, onUpdate: onUpdate)
        } else {
            throw AIProviderError.unsupported(feature: "Foundation Models requires iOS 26+")
        }
        #else
        throw AIProviderError.unsupported(feature: "Foundation Models not available on this platform")
        #endif
    }
    
    @available(iOS 26.0, macOS 26.0, *)
    private func streamWithFoundationModels(
        messages: [ChatMessage],
        onUpdate: @escaping @Sendable (StreamingUpdate) async -> Void
    ) async throws {
        #if canImport(FoundationModels)
        // Build the conversation prompt
        let systemPrompt = messages.first { $0.role == .system }?.content.textContent
        let conversationMessages = messages.filter { $0.role != .system }
        
        // Create the session with system prompt if available
        let session: LanguageModelSession
        if let systemPrompt = systemPrompt {
            session = LanguageModelSession(instructions: systemPrompt)
        } else {
            session = LanguageModelSession()
        }
        
        // Build the prompt from conversation history
        // Note: Foundation Models doesn't support images, so we extract text only
        var prompt = ""
        for message in conversationMessages {
            switch message.role {
            case .user:
                prompt += "User: \(message.content.textContent)\n"
            case .assistant:
                prompt += "Assistant: \(message.content.textContent)\n"
            case .system:
                break
            }
        }
        
        // Stream the response
        var fullContent = ""
        let stream = session.streamResponse(to: prompt)
        
        for try await partialResponse in stream {
            try Task.checkCancellation()
            fullContent = partialResponse.content
            await onUpdate(StreamingUpdate(content: fullContent))
        }
        #endif
    }
    
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
    
    func validateConfiguration() async throws -> Bool {
        return isSupported
    }
    
    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
}
