//
//  Message.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var content: String
    var isFromUser: Bool
    var timestamp: Date
    var isStreaming: Bool
    
    // Reasoning support for models that use <think> blocks
    var reasoningContent: String?
    var isThinking: Bool
    var thinkingStartTime: Date?
    var thinkingDuration: TimeInterval?
    
    // Citations/Sources support for Perplexity Sonar models
    // Stored as JSON array of citation URLs
    var citationsJSON: String?
    
    // Model info for AI messages - tracks which model generated this response
    var modelId: String?
    var modelName: String?
    var modelIconName: String?
    var modelProvider: String?
    var modelIsSystemIcon: Bool
    
    var chat: Chat?
    
    init(
        id: UUID = UUID(),
        content: String,
        isFromUser: Bool,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        reasoningContent: String? = nil,
        isThinking: Bool = false,
        thinkingStartTime: Date? = nil,
        thinkingDuration: TimeInterval? = nil,
        citations: [String]? = nil,
        modelId: String? = nil,
        modelName: String? = nil,
        modelIconName: String? = nil,
        modelProvider: String? = nil,
        modelIsSystemIcon: Bool = false
    ) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.reasoningContent = reasoningContent
        self.isThinking = isThinking
        self.thinkingStartTime = thinkingStartTime
        self.thinkingDuration = thinkingDuration
        self.citationsJSON = citations.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        self.modelId = modelId
        self.modelName = modelName
        self.modelIconName = modelIconName
        self.modelProvider = modelProvider
        self.modelIsSystemIcon = modelIsSystemIcon
    }
    
    /// Whether this message has reasoning content that can be viewed
    var hasReasoningContent: Bool {
        if let reasoning = reasoningContent {
            return !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
    
    /// Get citations as an array of URLs
    var citations: [String] {
        get {
            guard let json = citationsJSON,
                  let data = json.data(using: .utf8),
                  let urls = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return urls
        }
        set {
            citationsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
    
    /// Whether this message has citations/sources
    var hasCitations: Bool {
        !citations.isEmpty
    }
}
