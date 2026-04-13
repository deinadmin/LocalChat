//
//  ChatStore.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import Foundation
import SwiftData
import SwiftUI

/// Tracks the state of an ongoing generation for a specific chat
private struct GenerationState {
    let task: Task<Void, Never>
    let messageId: UUID
}

@Observable
final class ChatStore {
    private let modelContext: ModelContext
    private let aiService: AIService
    
    var chats: [Chat] = []
    var isLoading: Bool = false
    var error: String?
    
    // Per-chat generation tracking - keyed by chat ID
    // Using a dictionary allows multiple chats to generate simultaneously
    private var activeGenerations: [UUID: GenerationState] = [:]
    
    // Set of chat IDs currently generating (for efficient observation)
    private(set) var generatingChatIds: Set<UUID> = []
    
    // Current model tracking
    var currentModel: StoreModel {
        aiService.currentModel
    }
    
    init(modelContext: ModelContext, aiService: AIService = .shared) {
        self.modelContext = modelContext
        self.aiService = aiService
        fetchChats()
    }
    
    // MARK: - Generation State Queries
    
    /// Check if a specific chat is currently generating a response
    func isGenerating(chatId: UUID) -> Bool {
        generatingChatIds.contains(chatId)
    }
    
    /// Check if any chat is currently generating
    var hasActiveGeneration: Bool {
        !generatingChatIds.isEmpty
    }
    
    // MARK: - CRUD Operations
    
    func fetchChats() {
        let descriptor = FetchDescriptor<Chat>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        do {
            chats = try modelContext.fetch(descriptor)
        } catch {
            self.error = "Failed to fetch chats: \(error.localizedDescription)"
        }
    }
    
    @discardableResult
    func createChat(title: String = "New Chat") -> Chat {
        let defaults = DefaultChatSettings.shared
        
        // Use the persisted default model ID, or fall back to the first available model
        // We intentionally don't use aiService.currentModel here to keep new chats
        // independent from whatever model is currently active in other chats
        let modelId = defaults.defaultModelId 
            ?? ModelStoreService.shared.allModels.first?.modelId 
            ?? aiService.currentModel.modelId
        
        let chat = Chat(
            title: title,
            lastModelId: modelId,
            autoGenerateTitle: defaults.autoGenerateTitle,
            customSystemPrompt: nil, // Will use default
            systemPromptEnabled: defaults.systemPromptEnabled
        )
        
        modelContext.insert(chat)
        saveContext()
        fetchChats()
        return chat
    }
    
    func deleteChat(_ chat: Chat) {
        // Cancel any ongoing generation for this chat
        cancelGeneration(for: chat.id)
        
        modelContext.delete(chat)
        saveContext()
        fetchChats()
    }
    
    func renameChat(_ chat: Chat, to newTitle: String) {
        chat.title = newTitle
        chat.updatedAt = Date()
        saveContext()
        fetchChats()
    }
    
    // MARK: - Message Operations
    
    func sendMessage(content: String, to chat: Chat, attachments: [ChatAttachment] = [], webSearchEnabled: Bool = false) async {
        // Prevent sending while this chat is already generating
        guard !isGenerating(chatId: chat.id) else { return }
        
        let chatId = chat.id
        let isFirstMessage = chat.messages.isEmpty
        
        // Convert ChatAttachment to MessageAttachment for storage
        let messageAttachments: [MessageAttachment] = attachments.map { attachment in
            MessageAttachment.fromData(
                attachment.data,
                type: attachment.type == .image ? .image : .file,
                filename: attachment.filename,
                mimeType: attachment.mimeType
            )
        }
        
        // Create user message with attachments
        let userMessage = Message(content: content, isFromUser: true, attachments: messageAttachments.isEmpty ? nil : messageAttachments)
        userMessage.chat = chat
        chat.messages.append(userMessage)
        chat.updatedAt = Date()
        
        // Save the current model ID to the chat
        chat.lastModelId = currentModel.modelId
        
        // For the first message, lock in the system prompt so future changes
        // to the default won't affect this chat
        if isFirstMessage && chat.customSystemPrompt == nil {
            chat.customSystemPrompt = DefaultChatSettings.shared.defaultSystemPrompt
        }
        
        // For the first message, use simple fallback title immediately
        if chat.title == "New Chat" && chat.messages.count == 1 {
            chat.title = generateFallbackTitle(from: content)
        }
        
        saveContext()
        fetchChats()
        
        // Create placeholder AI response with model info
        let aiMessage = Message(
            content: "",
            isFromUser: false,
            isStreaming: true,
            isSearchingWeb: webSearchEnabled,
            didSearchWeb: webSearchEnabled,
            modelId: currentModel.modelId,
            modelName: currentModel.name,
            modelIconName: currentModel.iconName,
            modelProvider: currentModel.provider,
            modelIsSystemIcon: currentModel.isSystemIcon
        )
        aiMessage.chat = chat
        chat.messages.append(aiMessage)
        let aiMessageId = aiMessage.id
        
        saveContext()
        fetchChats()
        
        // Build conversation history for context
        let conversationMessages = buildConversationMessages(for: chat)
        let modelToUse = currentModel
        
        // Mark as generating
        generatingChatIds.insert(chatId)
        
        // Create background task that continues even when navigating away
        let generationTask = Task { [weak self] in
            guard let self = self else { return }
            
            var rawContent = ""
            var hasStartedThinking = false
            var latestCitations: [String]? = nil
            
            do {
                try await aiService.streamMessage(
                    messages: conversationMessages,
                    model: modelToUse,
                    webSearchEnabled: webSearchEnabled
                ) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if Task.isCancelled { return }
                        
                        // Find the message by ID (it may have been refetched)
                        guard let currentChat = self.chats.first(where: { $0.id == chatId }),
                              let message = currentChat.messages.first(where: { $0.id == aiMessageId }) else {
                            return
                        }
                        
                        rawContent = update.content
                        
                        // Update web search state
                        message.isSearchingWeb = update.isSearchingWeb
                        
                        // Store citations if provided (web search or Perplexity sends these)
                        if let citations = update.citations, !citations.isEmpty {
                            latestCitations = citations
                            message.citations = citations
                        }
                        
                        if let reasoning = update.reasoning {
                            message.reasoningContent = reasoning
                            
                            if update.isReasoning && !hasStartedThinking {
                                hasStartedThinking = true
                                message.isThinking = true
                                message.thinkingStartTime = Date()
                            }
                            
                            if update.reasoningComplete && message.isThinking {
                                message.isThinking = false
                                if let startTime = message.thinkingStartTime {
                                    message.thinkingDuration = Date().timeIntervalSince(startTime)
                                }
                            }
                            
                            message.content = update.content
                        } else {
                            let parseResult = ReasoningParser.parse(rawContent)
                            
                            if parseResult.isInsideThinkingBlock && !hasStartedThinking {
                                hasStartedThinking = true
                                message.isThinking = true
                                message.thinkingStartTime = Date()
                            }
                            
                            if parseResult.isInsideThinkingBlock || parseResult.isThinkingComplete {
                                message.reasoningContent = parseResult.reasoningContent
                            }
                            
                            if parseResult.isThinkingComplete && message.isThinking {
                                message.isThinking = false
                                if let startTime = message.thinkingStartTime {
                                    message.thinkingDuration = Date().timeIntervalSince(startTime)
                                }
                            }
                            
                            message.content = parseResult.displayContent
                        }
                        
                        // Throttle saves during streaming for performance
                        // Save every update but without fetching (reduces UI churn)
                        self.saveContextQuietly()
                    }
                }
                
                // Mark as complete
                await MainActor.run { [weak self] in
                    guard let self = self, !Task.isCancelled else { return }
                    
                    guard let currentChat = self.chats.first(where: { $0.id == chatId }),
                          let message = currentChat.messages.first(where: { $0.id == aiMessageId }) else {
                        return
                    }
                    
                    if message.reasoningContent == nil {
                        let finalResult = ReasoningParser.parse(rawContent)
                        message.content = finalResult.displayContent
                        message.reasoningContent = finalResult.reasoningContent
                    }
                    
                    // Ensure citations are saved on completion
                    if let citations = latestCitations {
                        message.citations = citations
                    }
                    
                    message.isThinking = false
                    message.isSearchingWeb = false
                    
                    if message.reasoningContent != nil,
                       let startTime = message.thinkingStartTime,
                       message.thinkingDuration == nil {
                        message.thinkingDuration = Date().timeIntervalSince(startTime)
                    }
                    
                    message.isStreaming = false
                    currentChat.updatedAt = Date()
                    
                    self.saveContext()
                    self.fetchChats()
                    
                    // Generate title after AI response completes (if auto-generate is enabled)
                    if currentChat.autoGenerateTitle {
                        let messageCount = currentChat.messages.count
                        let shouldGenerateTitle = messageCount == 2 || (messageCount > 2 && (messageCount - 2) % 6 == 0)
                        if shouldGenerateTitle {
                            Task {
                                await self.generateAndUpdateTitle(for: currentChat)
                            }
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        
                        if let currentChat = self.chats.first(where: { $0.id == chatId }),
                           let message = currentChat.messages.first(where: { $0.id == aiMessageId }) {
                            message.content = "Error: \(error.localizedDescription)"
                            message.isStreaming = false
                            message.isThinking = false
                        }
                        
                        self.error = error.localizedDescription
                        self.saveContext()
                        self.fetchChats()
                    }
                }
            }
            
            // Clean up generation state
            await MainActor.run { [weak self] in
                self?.cleanupGeneration(for: chatId)
            }
        }
        
        // Store the generation state
        activeGenerations[chatId] = GenerationState(task: generationTask, messageId: aiMessageId)
    }
    
    /// Cancel generation for a specific chat
    func cancelGeneration(for chatId: UUID) {
        guard let state = activeGenerations[chatId] else { return }
        
        // Cancel the task
        state.task.cancel()
        
        // Find and update the message
        if let chat = chats.first(where: { $0.id == chatId }),
           let message = chat.messages.first(where: { $0.id == state.messageId }) {
            message.isStreaming = false
            message.isThinking = false
            message.isSearchingWeb = false
            
            if let startTime = message.thinkingStartTime, message.thinkingDuration == nil {
                message.thinkingDuration = Date().timeIntervalSince(startTime)
            }
            
            if message.content.isEmpty {
                message.content = "[Generation cancelled]"
            }
            
            saveContext()
            fetchChats()
        }
        
        cleanupGeneration(for: chatId)
    }
    
    /// Legacy method for compatibility - cancels generation for the "current" chat
    /// Prefer using cancelGeneration(for:) with a specific chat ID
    func cancelGeneration() {
        // Cancel all active generations
        for chatId in generatingChatIds {
            cancelGeneration(for: chatId)
        }
    }
    
    private func cleanupGeneration(for chatId: UUID) {
        activeGenerations.removeValue(forKey: chatId)
        generatingChatIds.remove(chatId)
    }
    
    /// Retry the last AI response
    func retryLastMessage(in chat: Chat) async {
        // Cancel any existing generation first
        cancelGeneration(for: chat.id)
        
        // Find and remove the last AI message
        guard let lastAIMessage = chat.sortedMessages.last(where: { !$0.isFromUser }) else {
            return
        }
        
        // Find the user message before it
        let messages = chat.sortedMessages
        guard let aiIndex = messages.firstIndex(where: { $0.id == lastAIMessage.id }),
              aiIndex > 0 else {
            return
        }
        
        let userMessage = messages[aiIndex - 1]
        guard userMessage.isFromUser else { return }
        
        // Remove the AI message
        modelContext.delete(lastAIMessage)
        chat.messages.removeAll { $0.id == lastAIMessage.id }
        saveContext()
        fetchChats()
        
        // Resend the user message
        await sendMessage(content: userMessage.content, to: chat)
    }
    
    /// Regenerate a specific AI message in place (keeps messages before and after it)
    func regenerateMessage(_ aiMessage: Message, in chat: Chat, withModel model: StoreModel? = nil) async {
        // Cancel any existing generation first
        cancelGeneration(for: chat.id)
        
        // Switch to the specified model if provided
        if let model = model {
            aiService.setCurrentModel(model, updateDefault: false)
        }
        
        let chatId = chat.id
        let messages = chat.sortedMessages
        
        // Find the user message that preceded this AI message
        guard let aiIndex = messages.firstIndex(where: { $0.id == aiMessage.id }),
              aiIndex > 0 else {
            return
        }
        
        let userMessage = messages[aiIndex - 1]
        guard userMessage.isFromUser else { return }
        
        // Reset the AI message for regeneration
        aiMessage.content = ""
        aiMessage.isStreaming = true
        aiMessage.isThinking = false
        aiMessage.reasoningContent = nil
        aiMessage.thinkingStartTime = nil
        aiMessage.thinkingDuration = nil
        aiMessage.citationsJSON = nil
        
        // Update model info for the regenerated message
        aiMessage.modelId = currentModel.modelId
        aiMessage.modelName = currentModel.name
        aiMessage.modelIconName = currentModel.iconName
        aiMessage.modelProvider = currentModel.provider
        aiMessage.modelIsSystemIcon = currentModel.isSystemIcon
        
        // Save the current model ID to the chat
        chat.lastModelId = currentModel.modelId
        chat.updatedAt = Date()
        saveContext()
        fetchChats()
        
        // Build conversation history up to and including the user message
        // We need to exclude messages AFTER the AI message we're regenerating
        var conversationMessages: [ChatMessage] = []
        
        // Build system prompt from chat settings or defaults
        let systemPrompt = DefaultChatSettings.shared.systemPrompt(for: chat, modelName: currentModel.name)
        if !systemPrompt.isEmpty {
            conversationMessages.append(ChatMessage(
                role: .system,
                content: systemPrompt
            ))
        }
        
        // Only include messages up to and including the user message before this AI response
        let relevantMessages = messages.prefix(through: aiIndex - 1).suffix(20)
        for msg in relevantMessages {
            if msg.isFromUser {
                // Use helper to properly include attachments
                conversationMessages.append(convertToChatMessage(msg))
            } else if !msg.content.isEmpty && !msg.isStreaming {
                conversationMessages.append(ChatMessage(role: .assistant, content: msg.content))
            }
        }
        
        let modelToUse = currentModel
        let aiMessageId = aiMessage.id
        
        // Mark as generating
        generatingChatIds.insert(chatId)
        
        // Create background task for streaming
        let generationTask = Task { [weak self] in
            guard let self = self else { return }
            
            var rawContent = ""
            var hasStartedThinking = false
            var latestCitations: [String]? = nil
            
            do {
                try await aiService.streamMessage(
                    messages: conversationMessages,
                    model: modelToUse
                ) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if Task.isCancelled { return }
                        
                        guard let currentChat = self.chats.first(where: { $0.id == chatId }),
                              let message = currentChat.messages.first(where: { $0.id == aiMessageId }) else {
                            return
                        }
                        
                        rawContent = update.content
                        
                        if let citations = update.citations, !citations.isEmpty {
                            latestCitations = citations
                            message.citations = citations
                        }
                        
                        if let reasoning = update.reasoning {
                            message.reasoningContent = reasoning
                            
                            if update.isReasoning && !hasStartedThinking {
                                hasStartedThinking = true
                                message.isThinking = true
                                message.thinkingStartTime = Date()
                            }
                            
                            if update.reasoningComplete && message.isThinking {
                                message.isThinking = false
                                if let startTime = message.thinkingStartTime {
                                    message.thinkingDuration = Date().timeIntervalSince(startTime)
                                }
                            }
                            
                            message.content = update.content
                        } else {
                            let parseResult = ReasoningParser.parse(rawContent)
                            
                            if parseResult.isInsideThinkingBlock && !hasStartedThinking {
                                hasStartedThinking = true
                                message.isThinking = true
                                message.thinkingStartTime = Date()
                            }
                            
                            if parseResult.isInsideThinkingBlock || parseResult.isThinkingComplete {
                                message.reasoningContent = parseResult.reasoningContent
                            }
                            
                            if parseResult.isThinkingComplete && message.isThinking {
                                message.isThinking = false
                                if let startTime = message.thinkingStartTime {
                                    message.thinkingDuration = Date().timeIntervalSince(startTime)
                                }
                            }
                            
                            message.content = parseResult.displayContent
                        }
                        
                        self.saveContextQuietly()
                    }
                }
                
                // Mark as complete
                await MainActor.run { [weak self] in
                    guard let self = self, !Task.isCancelled else { return }
                    
                    guard let currentChat = self.chats.first(where: { $0.id == chatId }),
                          let message = currentChat.messages.first(where: { $0.id == aiMessageId }) else {
                        return
                    }
                    
                    if message.reasoningContent == nil {
                        let finalResult = ReasoningParser.parse(rawContent)
                        message.content = finalResult.displayContent
                        message.reasoningContent = finalResult.reasoningContent
                    }
                    
                    if let citations = latestCitations {
                        message.citations = citations
                    }
                    
                    message.isThinking = false
                    
                    if message.reasoningContent != nil,
                       let startTime = message.thinkingStartTime,
                       message.thinkingDuration == nil {
                        message.thinkingDuration = Date().timeIntervalSince(startTime)
                    }
                    
                    message.isStreaming = false
                    currentChat.updatedAt = Date()
                    
                    self.saveContext()
                    self.fetchChats()
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        
                        if let currentChat = self.chats.first(where: { $0.id == chatId }),
                           let message = currentChat.messages.first(where: { $0.id == aiMessageId }) {
                            message.content = "Error: \(error.localizedDescription)"
                            message.isStreaming = false
                            message.isThinking = false
                        }
                        
                        self.error = error.localizedDescription
                        self.saveContext()
                        self.fetchChats()
                    }
                }
            }
            
            // Clean up generation state
            await MainActor.run { [weak self] in
                self?.cleanupGeneration(for: chatId)
            }
        }
        
        // Store the generation state
        activeGenerations[chatId] = GenerationState(task: generationTask, messageId: aiMessageId)
    }
    
    /// Delete a specific message
    func deleteMessage(_ message: Message, from chat: Chat) {
        modelContext.delete(message)
        chat.messages.removeAll { $0.id == message.id }
        saveContext()
        fetchChats()
    }
    
    /// Edit a user message: updates content, removes the following AI response, and regenerates
    func editMessage(_ message: Message, in chat: Chat, newContent: String) async {
        // Cancel any existing generation first
        cancelGeneration(for: chat.id)
        
        let chatId = chat.id
        let messages = chat.sortedMessages
        
        // Find the index of the message being edited
        guard let messageIndex = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        
        // Update the user message content
        message.content = newContent
        message.timestamp = Date()
        
        // Find and delete the AI response that followed this user message (if any)
        let nextIndex = messageIndex + 1
        if nextIndex < messages.count {
            let nextMessage = messages[nextIndex]
            if !nextMessage.isFromUser {
                modelContext.delete(nextMessage)
                chat.messages.removeAll { $0.id == nextMessage.id }
            }
        }
        
        chat.updatedAt = Date()
        saveContext()
        fetchChats()
        
        // Create new AI response placeholder with model info
        let aiMessage = Message(
            content: "",
            isFromUser: false,
            isStreaming: true,
            modelId: currentModel.modelId,
            modelName: currentModel.name,
            modelIconName: currentModel.iconName,
            modelProvider: currentModel.provider,
            modelIsSystemIcon: currentModel.isSystemIcon
        )
        aiMessage.chat = chat
        
        // Insert the AI message at the correct position (after the edited user message)
        // Find the correct position in the array
        if let editedIndex = chat.messages.firstIndex(where: { $0.id == message.id }) {
            chat.messages.insert(aiMessage, at: editedIndex + 1)
        } else {
            chat.messages.append(aiMessage)
        }
        
        let aiMessageId = aiMessage.id
        saveContext()
        fetchChats()
        
        // Build conversation history up to the edited message
        var conversationMessages: [ChatMessage] = []
        
        // Build system prompt from chat settings or defaults
        let systemPrompt = DefaultChatSettings.shared.systemPrompt(for: chat, modelName: currentModel.name)
        if !systemPrompt.isEmpty {
            conversationMessages.append(ChatMessage(
                role: .system,
                content: systemPrompt
            ))
        }
        
        // Get refreshed sorted messages and include only up to and including the edited message
        let updatedMessages = chat.sortedMessages
        if let editedIndex = updatedMessages.firstIndex(where: { $0.id == message.id }) {
            let relevantMessages = updatedMessages.prefix(through: editedIndex).suffix(20)
            for msg in relevantMessages {
                if msg.isFromUser {
                    // Use helper to properly include attachments
                    conversationMessages.append(convertToChatMessage(msg))
                } else if !msg.content.isEmpty && !msg.isStreaming {
                    conversationMessages.append(ChatMessage(role: .assistant, content: msg.content))
                }
            }
        }
        
        let modelToUse = currentModel
        
        // Mark as generating
        generatingChatIds.insert(chatId)
        
        // Create background task for streaming
        let generationTask = Task { [weak self] in
            guard let self = self else { return }
            
            var rawContent = ""
            var hasStartedThinking = false
            var latestCitations: [String]? = nil
            
            do {
                try await aiService.streamMessage(
                    messages: conversationMessages,
                    model: modelToUse
                ) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if Task.isCancelled { return }
                        
                        guard let currentChat = self.chats.first(where: { $0.id == chatId }),
                              let aiMsg = currentChat.messages.first(where: { $0.id == aiMessageId }) else {
                            return
                        }
                        
                        rawContent = update.content
                        
                        if let citations = update.citations, !citations.isEmpty {
                            latestCitations = citations
                            aiMsg.citations = citations
                        }
                        
                        if let reasoning = update.reasoning {
                            aiMsg.reasoningContent = reasoning
                            
                            if update.isReasoning && !hasStartedThinking {
                                hasStartedThinking = true
                                aiMsg.isThinking = true
                                aiMsg.thinkingStartTime = Date()
                            }
                            
                            if update.reasoningComplete && aiMsg.isThinking {
                                aiMsg.isThinking = false
                                if let startTime = aiMsg.thinkingStartTime {
                                    aiMsg.thinkingDuration = Date().timeIntervalSince(startTime)
                                }
                            }
                            
                            aiMsg.content = update.content
                        } else {
                            let parseResult = ReasoningParser.parse(rawContent)
                            
                            if parseResult.isInsideThinkingBlock && !hasStartedThinking {
                                hasStartedThinking = true
                                aiMsg.isThinking = true
                                aiMsg.thinkingStartTime = Date()
                            }
                            
                            if parseResult.isInsideThinkingBlock || parseResult.isThinkingComplete {
                                aiMsg.reasoningContent = parseResult.reasoningContent
                            }
                            
                            if parseResult.isThinkingComplete && aiMsg.isThinking {
                                aiMsg.isThinking = false
                                if let startTime = aiMsg.thinkingStartTime {
                                    aiMsg.thinkingDuration = Date().timeIntervalSince(startTime)
                                }
                            }
                            
                            aiMsg.content = parseResult.displayContent
                        }
                        
                        self.saveContextQuietly()
                    }
                }
                
                // Mark as complete
                await MainActor.run { [weak self] in
                    guard let self = self, !Task.isCancelled else { return }
                    
                    guard let currentChat = self.chats.first(where: { $0.id == chatId }),
                          let aiMsg = currentChat.messages.first(where: { $0.id == aiMessageId }) else {
                        return
                    }
                    
                    if aiMsg.reasoningContent == nil {
                        let finalResult = ReasoningParser.parse(rawContent)
                        aiMsg.content = finalResult.displayContent
                        aiMsg.reasoningContent = finalResult.reasoningContent
                    }
                    
                    if let citations = latestCitations {
                        aiMsg.citations = citations
                    }
                    
                    aiMsg.isThinking = false
                    
                    if aiMsg.reasoningContent != nil,
                       let startTime = aiMsg.thinkingStartTime,
                       aiMsg.thinkingDuration == nil {
                        aiMsg.thinkingDuration = Date().timeIntervalSince(startTime)
                    }
                    
                    aiMsg.isStreaming = false
                    currentChat.updatedAt = Date()
                    
                    self.saveContext()
                    self.fetchChats()
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        
                        if let currentChat = self.chats.first(where: { $0.id == chatId }),
                           let aiMsg = currentChat.messages.first(where: { $0.id == aiMessageId }) {
                            aiMsg.content = "Error: \(error.localizedDescription)"
                            aiMsg.isStreaming = false
                            aiMsg.isThinking = false
                        }
                        
                        self.error = error.localizedDescription
                        self.saveContext()
                        self.fetchChats()
                    }
                }
            }
            
            // Clean up generation state
            await MainActor.run { [weak self] in
                self?.cleanupGeneration(for: chatId)
            }
        }
        
        // Store the generation state
        activeGenerations[chatId] = GenerationState(task: generationTask, messageId: aiMessageId)
    }
    
    // MARK: - Model Selection
    
    func setModel(_ model: StoreModel) {
        aiService.setCurrentModel(model, updateDefault: false)
    }
    
    /// Switch to a model by its model ID (e.g., "anthropic/claude-3.5-sonnet")
    /// Returns true if the model was found and switched to
    /// Note: This does NOT update the default model for new chats
    @discardableResult
    func switchToModel(withId modelId: String) -> Bool {
        let modelStore = ModelStoreService.shared
        if let model = modelStore.allModels.first(where: { $0.modelId == modelId }) {
            aiService.setCurrentModel(model, updateDefault: false)
            return true
        }
        return false
    }
    
    var isModelConfigured: Bool {
        get async {
            await aiService.isCurrentModelReady
        }
    }
    
    // MARK: - Helpers
    
    private func buildConversationMessages(for chat: Chat) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        
        // Build system prompt from chat settings or defaults
        let systemPrompt = DefaultChatSettings.shared.systemPrompt(for: chat, modelName: currentModel.name)
        if !systemPrompt.isEmpty {
            messages.append(ChatMessage(
                role: .system,
                content: systemPrompt
            ))
        }
        
        let recentMessages = chat.sortedMessages.suffix(20)
        for message in recentMessages {
            if message.isFromUser {
                // Use helper to properly include attachments
                messages.append(convertToChatMessage(message))
            } else if !message.content.isEmpty && !message.isStreaming {
                messages.append(ChatMessage(role: .assistant, content: message.content))
            }
        }
        
        return messages
    }
    
    /// Convert a single Message to ChatMessage, properly handling attachments
    private func convertToChatMessage(_ message: Message) -> ChatMessage {
        if message.isFromUser {
            if message.hasAttachments {
                var parts: [MessageContentPart] = []
                
                // Add user's text content first if not empty
                if !message.content.isEmpty {
                    parts.append(.text(message.content))
                }
                
                // Add attachments
                for attachment in message.attachments {
                    switch attachment.type {
                    case .image:
                        parts.append(.imageData(base64: attachment.base64Data, mimeType: attachment.mimeType))
                        
                    case .file:
                        let mimeType = attachment.mimeType.lowercased()
                        let filename = attachment.filename.lowercased()
                        
                        if mimeType.contains("pdf") || filename.hasSuffix(".pdf") {
                            parts.append(.file(filename: attachment.filename, base64: attachment.base64Data, mimeType: attachment.mimeType))
                        } else if let textContent = extractTextFromFile(attachment) {
                            parts.append(.text("--- File: \(attachment.filename) ---\n\(textContent)\n--- End of \(attachment.filename) ---"))
                        } else {
                            parts.append(.file(filename: attachment.filename, base64: attachment.base64Data, mimeType: attachment.mimeType))
                        }
                    }
                }
                
                return ChatMessage(role: .user, parts: parts)
            } else {
                return ChatMessage(role: .user, content: message.content)
            }
        } else {
            return ChatMessage(role: .assistant, content: message.content)
        }
    }
    
    /// Extract text content from file attachment
    private func extractTextFromFile(_ attachment: MessageAttachment) -> String? {
        guard let data = attachment.data else { return nil }
        
        let mimeType = attachment.mimeType.lowercased()
        
        // Text-based files
        if mimeType.hasPrefix("text/") ||
           mimeType.contains("json") ||
           mimeType.contains("xml") ||
           mimeType.contains("javascript") ||
           mimeType.contains("css") ||
           mimeType.contains("html") ||
           mimeType.contains("markdown") ||
           mimeType.contains("yaml") ||
           mimeType.contains("csv") {
            return String(data: data, encoding: .utf8)
        }
        
        // Common code/config file extensions (check by filename if mime type doesn't help)
        let filename = attachment.filename.lowercased()
        let textExtensions = [".txt", ".md", ".json", ".xml", ".html", ".css", ".js", ".ts",
                              ".swift", ".py", ".rb", ".java", ".c", ".cpp", ".h", ".m",
                              ".sh", ".bash", ".zsh", ".yaml", ".yml", ".toml", ".ini",
                              ".csv", ".log", ".sql", ".graphql", ".env", ".gitignore"]
        
        for ext in textExtensions {
            if filename.hasSuffix(ext) {
                return String(data: data, encoding: .utf8)
            }
        }
        
        // For application/octet-stream, try to read as text
        if mimeType == "application/octet-stream" {
            if let text = String(data: data, encoding: .utf8),
               text.allSatisfy({ $0.isASCII || $0.isLetter || $0.isNumber || $0.isWhitespace || $0.isPunctuation }) {
                return text
            }
        }
        
        return nil
    }
    
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    /// Save without triggering a full refresh - used during streaming for performance
    private func saveContextQuietly() {
        do {
            try modelContext.save()
        } catch {
            // Silently handle during streaming
        }
    }
    
    private func generateFallbackTitle(from content: String) -> String {
        let words = content.split(separator: " ").prefix(4)
        var title = words.joined(separator: " ")
        if content.split(separator: " ").count > 4 {
            title += "..."
        }
        return title.isEmpty ? "New Chat" : title
    }
    
    private func generateAndUpdateTitle(for chat: Chat) async {
        let messages = chat.sortedMessages
        let newTitle = await ChatTitleService.shared.generateTitle(for: messages)
        
        await MainActor.run {
            chat.title = newTitle
            saveContext()
            fetchChats()
        }
    }
}
