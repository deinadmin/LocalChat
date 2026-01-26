//
//  ChatTitleService.swift
//  LocalChat
//
//  Created by Carl Steen on 21.01.26.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for generating chat titles using Apple Intelligence (Foundation Models)
/// Falls back to simple word extraction when Apple Intelligence is not available
actor ChatTitleService {
    static let shared = ChatTitleService()
    
    private init() {}
    
    /// Check if Apple Intelligence is available for title generation
    var isAppleIntelligenceAvailable: Bool {
        FoundationModelsProvider.isAppleIntelligenceAvailable
    }
    
    /// Generate a title for a chat based on its messages
    /// - Parameters:
    ///   - messages: The chat messages to summarize
    /// - Returns: A 3-4 word title for the chat
    func generateTitle(for messages: [Message]) async -> String {
        // Filter to just user messages for context
        let userMessages = messages.filter { $0.isFromUser }
        guard !userMessages.isEmpty else { return "New Chat" }
        
        // Try Apple Intelligence first
        if isAppleIntelligenceAvailable {
            if let aiTitle = await generateTitleWithAppleIntelligence(messages: messages) {
                return aiTitle
            }
        }
        
        // Fallback: first 4 words of the last user message
        return generateFallbackTitle(from: userMessages)
    }
    
    /// Generate title using Foundation Models (Apple Intelligence)
    @available(iOS 26.0, macOS 26.0, *)
    private func generateTitleWithAppleIntelligence(messages: [Message]) async -> String? {
        #if canImport(FoundationModels)
        // Build a summary of the conversation
        var conversationSummary = ""
        for message in messages.suffix(10) { // Limit to last 10 messages
            let role = message.isFromUser ? "User" : "Assistant"
            // Truncate long messages
            let content = message.content.prefix(200)
            conversationSummary += "\(role): \(content)\n"
        }
        
        let systemPrompt = """
            You are a title generator. Given a conversation, generate a concise 3-4 word title that captures the main topic.
            Rules:
            - Output ONLY the title, nothing else
            - Use 3-4 words maximum
            - No punctuation at the end
            - Capitalize first letter of each word
            - Be specific and descriptive
            """
        
        let prompt = """
            Generate a 3-4 word title for this conversation:
            
            \(conversationSummary)
            
            Title:
            """
        
        do {
            let session = LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: prompt)
            
            // Clean up the response
            var title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "Title:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Ensure it's not too long (max 5 words as safety)
            let words = title.split(separator: " ")
            if words.count > 5 {
                title = words.prefix(4).joined(separator: " ")
            }
            
            // If empty or too short, return nil to trigger fallback
            guard title.count >= 3 else { return nil }
            
            return title
        } catch {
            print("ChatTitleService: Failed to generate title with Apple Intelligence: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }
    
    /// Fallback title generation: first 4 words of the last user message
    private func generateFallbackTitle(from userMessages: [Message]) -> String {
        guard let lastUserMessage = userMessages.last else { return "New Chat" }
        
        let words = lastUserMessage.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(4)
        
        var title = words.joined(separator: " ")
        
        // Add ellipsis if we truncated
        if lastUserMessage.content.split(separator: " ").count > 4 {
            title += "..."
        }
        
        // Ensure minimum length
        guard title.count >= 2 else { return "New Chat" }
        
        return title
    }
}
