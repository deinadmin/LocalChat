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
    
    // Web search support for OpenRouter :online models
    var isSearchingWeb: Bool
    /// Whether this message used web search (persisted to show "Searched the web" chip after)
    var didSearchWeb: Bool
    
    // Citations/Sources support for Perplexity Sonar models
    // Stored as JSON array of citation URLs
    var citationsJSON: String?
    
    // Model info for AI messages - tracks which model generated this response
    var modelId: String?
    var modelName: String?
    var modelIconName: String?
    var modelProvider: String?
    var modelIsSystemIcon: Bool
    
    // Attachments - stored as JSON array of attachment metadata
    // Each attachment has: type (image/file), filename, mimeType, and base64 data
    var attachmentsJSON: String?
    
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
        isSearchingWeb: Bool = false,
        didSearchWeb: Bool = false,
        citations: [String]? = nil,
        modelId: String? = nil,
        modelName: String? = nil,
        modelIconName: String? = nil,
        modelProvider: String? = nil,
        modelIsSystemIcon: Bool = false,
        attachments: [MessageAttachment]? = nil
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
        self.isSearchingWeb = isSearchingWeb
        self.didSearchWeb = didSearchWeb
        self.citationsJSON = citations.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        self.modelId = modelId
        self.modelName = modelName
        self.modelIconName = modelIconName
        self.modelProvider = modelProvider
        self.modelIsSystemIcon = modelIsSystemIcon
        self.attachmentsJSON = attachments.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
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
    
    /// Get attachments as an array
    var attachments: [MessageAttachment] {
        get {
            guard let json = attachmentsJSON,
                  let data = json.data(using: .utf8),
                  let items = try? JSONDecoder().decode([MessageAttachment].self, from: data) else {
                return []
            }
            return items
        }
        set {
            attachmentsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
    
    /// Whether this message has attachments
    var hasAttachments: Bool {
        !attachments.isEmpty
    }
}

// MARK: - Message Attachment

/// Attachment metadata for storage in Message
struct MessageAttachment: Codable, Identifiable {
    let id: UUID
    let type: AttachmentType
    let filename: String
    let mimeType: String
    let base64Data: String
    
    enum AttachmentType: String, Codable {
        case image
        case file
    }
    
    init(id: UUID = UUID(), type: AttachmentType, filename: String, mimeType: String, base64Data: String) {
        self.id = id
        self.type = type
        self.filename = filename
        self.mimeType = mimeType
        self.base64Data = base64Data
    }
    
    /// Convert raw Data to a MessageAttachment
    static func fromData(_ data: Data, type: AttachmentType, filename: String, mimeType: String) -> MessageAttachment {
        MessageAttachment(
            type: type,
            filename: filename,
            mimeType: mimeType,
            base64Data: data.base64EncodedString()
        )
    }
    
    /// Get the data back from base64
    var data: Data? {
        Data(base64Encoded: base64Data)
    }
}
