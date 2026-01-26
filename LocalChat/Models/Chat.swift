//
//  Chat.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import Foundation
import SwiftData

@Model
final class Chat {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isStarred: Bool = false
    
    /// The model ID last used in this chat (e.g., "anthropic/claude-3.5-sonnet")
    /// Used to restore the model when reopening a chat
    var lastModelId: String?
    
    /// Whether to auto-generate titles based on conversation content
    var autoGenerateTitle: Bool = true
    
    /// Custom system prompt for this chat (nil means use default)
    var customSystemPrompt: String?
    
    /// Whether the system prompt is enabled for this chat
    var systemPromptEnabled: Bool = true
    
    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message]
    
    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isStarred: Bool = false,
        lastModelId: String? = nil,
        autoGenerateTitle: Bool = true,
        customSystemPrompt: String? = nil,
        systemPromptEnabled: Bool = true,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isStarred = isStarred
        self.lastModelId = lastModelId
        self.autoGenerateTitle = autoGenerateTitle
        self.customSystemPrompt = customSystemPrompt
        self.systemPromptEnabled = systemPromptEnabled
        self.messages = messages
    }
    
    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
    
    var lastMessage: Message? {
        sortedMessages.last
    }
    
    var previewText: String {
        lastMessage?.content ?? "No messages yet"
    }
}
