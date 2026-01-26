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
        let systemPrompt = messages.first { $0.role == .system }?.content
        let conversationMessages = messages.filter { $0.role != .system }
        
        // Create the session with system prompt if available
        let session: LanguageModelSession
        if let systemPrompt = systemPrompt {
            session = LanguageModelSession(instructions: systemPrompt)
        } else {
            session = LanguageModelSession()
        }
        
        // Build the prompt from conversation history
        var prompt = ""
        for message in conversationMessages {
            switch message.role {
            case .user:
                prompt += "User: \(message.content)\n"
            case .assistant:
                prompt += "Assistant: \(message.content)\n"
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
