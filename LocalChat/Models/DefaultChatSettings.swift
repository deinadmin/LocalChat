//
//  DefaultChatSettings.swift
//  LocalChat
//
//  Created by Carl Steen on 21.01.26.
//

import Foundation
import SwiftData

/// Manages default settings for new chats, persisted to UserDefaults
@Observable
final class DefaultChatSettings {
    static let shared = DefaultChatSettings()
    
    // MARK: - UserDefaults Keys
    
    private let defaultModelIdKey = "defaultChatModelId"
    private let defaultSystemPromptKey = "defaultChatSystemPrompt"
    private let systemPromptEnabledKey = "defaultChatSystemPromptEnabled"
    private let autoGenerateTitleKey = "defaultChatAutoGenerateTitle"
    private let enabledToolsKey = "defaultChatEnabledTools"
    
    // MARK: - Default System Prompt
    
    /// The default system prompt that provides context to AI models
    static let builtInSystemPrompt = """
You are a helpful AI assistant in LocalChat. You are currently running as {MODEL_NAME}.
The current date and time is {DATE_AND_TIME}.

Core Guidelines:
- Be concise, clear, and directly helpful
- Provide accurate information and acknowledge uncertainty when appropriate
- Format responses with markdown when it improves readability (code blocks, lists, headers)
- Respect the user's time - get to the point without unnecessary preamble
- If asked to do something you cannot do, explain why clearly

You can help with:
- Answering questions and explaining concepts
- Writing, editing, and reviewing text
- Coding assistance and debugging
- Analysis and problem-solving
- Creative tasks and brainstorming
"""

    // MARK: - Properties

    
    /// The default model ID for new chats
    var defaultModelId: String? {
        didSet {
            UserDefaults.standard.set(defaultModelId, forKey: defaultModelIdKey)
        }
    }
    
    /// The default system prompt for new chats
    var defaultSystemPrompt: String {
        didSet {
            UserDefaults.standard.set(defaultSystemPrompt, forKey: defaultSystemPromptKey)
        }
    }
    
    /// Whether the system prompt is enabled by default
    var systemPromptEnabled: Bool {
        didSet {
            UserDefaults.standard.set(systemPromptEnabled, forKey: systemPromptEnabledKey)
        }
    }
    
    /// Whether to auto-generate titles by default
    var autoGenerateTitle: Bool {
        didSet {
            UserDefaults.standard.set(autoGenerateTitle, forKey: autoGenerateTitleKey)
        }
    }
    
    /// List of enabled tool IDs for new chats
    var enabledTools: [String] {
        didSet {
            UserDefaults.standard.set(enabledTools, forKey: enabledToolsKey)
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted values or use defaults
        self.defaultModelId = UserDefaults.standard.string(forKey: defaultModelIdKey)
        
        if let savedPrompt = UserDefaults.standard.string(forKey: defaultSystemPromptKey) {
            self.defaultSystemPrompt = savedPrompt
        } else {
            self.defaultSystemPrompt = Self.builtInSystemPrompt
        }
        
        // Default to enabled if not set
        if UserDefaults.standard.object(forKey: systemPromptEnabledKey) != nil {
            self.systemPromptEnabled = UserDefaults.standard.bool(forKey: systemPromptEnabledKey)
        } else {
            self.systemPromptEnabled = true
        }
        
        // Default to enabled if not set
        if UserDefaults.standard.object(forKey: autoGenerateTitleKey) != nil {
            self.autoGenerateTitle = UserDefaults.standard.bool(forKey: autoGenerateTitleKey)
        } else {
            self.autoGenerateTitle = true
        }
        
        self.enabledTools = UserDefaults.standard.stringArray(forKey: enabledToolsKey) ?? []
    }
    
    // MARK: - Helpers
    
    /// Get current date and time formatted
    private var currentDateTimeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: Date())
    }
    
    /// Reset the system prompt to the built-in default
    func resetSystemPromptToDefault() {
        defaultSystemPrompt = Self.builtInSystemPrompt
    }
    
    /// Get the system prompt with model name and date/time substituted
    func systemPrompt(for modelName: String) -> String {
        guard systemPromptEnabled else { return "" }
        return defaultSystemPrompt
            .replacingOccurrences(of: "{MODEL_NAME}", with: modelName)
            .replacingOccurrences(of: "{DATE_AND_TIME}", with: currentDateTimeString)
    }
    
    /// Get the system prompt for a specific chat, falling back to defaults
    func systemPrompt(for chat: Chat, modelName: String) -> String {
        guard chat.systemPromptEnabled else { return "" }
        
        let prompt = chat.customSystemPrompt ?? defaultSystemPrompt
        return prompt
            .replacingOccurrences(of: "{MODEL_NAME}", with: modelName)
            .replacingOccurrences(of: "{DATE_AND_TIME}", with: currentDateTimeString)
    }
}
