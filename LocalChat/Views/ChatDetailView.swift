//
//  ChatDetailView.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import SwiftUI
import SwiftData

struct ChatDetailView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var chat: Chat
    @Binding var navigationPath: NavigationPath
    
    @State private var messageText = ""
    @State private var showModelPicker = false
    @State private var showChatSettings = false
    @State private var aiService = AIService.shared
    @FocusState private var isInputFocused: Bool
    
    // Height of input bar for bottom padding calculation
    @State private var inputBarHeight: CGFloat = 120
    
    // Editing state
    @State private var editingMessage: Message?
    @State private var isEditing = false
    
    private var selectedModel: StoreModel {
        aiService.currentModel
    }
    
    @State private var isAtBottom = true
    @State private var showScrollToBottom = false
    @State private var scrolledMessageID: UUID?
    @State private var tempScrolledMessageID: UUID?
    @State private var isContentReady = false
    
    // State for "new chat" mode - shows empty state without creating a chat yet
    @State private var isNewChatMode = false
    // Temporary chat mode - chat won't be persisted
    @State private var isTemporaryChat = false
    // In-memory messages for temporary chat
    @State private var temporaryMessages: [Message] = []
    // Track if we're generating a response for temporary chat
    @State private var isGeneratingTemporary = false
    
    // Additional context sheet
    @State private var showAdditionalContextSheet = false
    @State private var pendingAttachments: [ChatAttachment] = []
    
    // Web search toggle state
    @State private var isWebSearchEnabled = false
    
    /// Check if this specific chat is currently generating
    private var isChatGenerating: Bool {
        chatStore.isGenerating(chatId: chat.id)
    }
    
    /// Whether we're in an empty state (no messages sent yet)
    private var isEmptyState: Bool {
        if isNewChatMode {
            return temporaryMessages.isEmpty
        }
        return chat.messages.isEmpty
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            AppTheme.background
                .ignoresSafeArea()
            
            // Messages or empty state
            if isEmptyState {
                emptyStateView
            } else if isNewChatMode && isTemporaryChat {
                temporaryMessagesScrollView
            } else {
                ZStack {
                    // Loading spinner - shown while content prepares
                    if !isContentReady {
                        ProgressView()
                            .scaleEffect(1.2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Messages - hidden until ready, then fades in
                    messagesScrollView
                        .opacity(isContentReady ? 1 : 0)
                }
            }
            
            // Floating scroll to bottom button
            if showScrollToBottom && !isEmptyState {
                scrollToBottomButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
            
            // Input bar overlaid on top
            inputBarView
                .zIndex(2)
                .background {
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            inputBarHeight = geo.size.height
                        }
                        .onChange(of: geo.size.height) { old, new in
                            inputBarHeight = new
                        }
                    }
                }
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Show temporary chat toggle when in empty state, otherwise show new chat button
                if isEmptyState {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTemporaryChat.toggle()
                        }
                    } label: {
                        Image(systemName: isTemporaryChat ? "clock.fill" : "clock")
                    }
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: isTemporaryChat)
                } else {
                    Button("New Chat", systemImage: "plus") {
                        // Enter new chat mode - clears the view but keeps current chat saved
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isNewChatMode = true
                            isTemporaryChat = false
                            temporaryMessages = []
                            messageText = ""
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .principal) {
                // Show "New Chat" or "Temporary Chat" when empty, otherwise show chat title
                if isEmptyState {
                    Text(isTemporaryChat ? "Temporary Chat" : "New Chat")
                        .font(.headline)
                } else if isNewChatMode && isTemporaryChat {
                    // Always show "Temporary Chat" for temporary chats even with messages
                    Text("Temporary Chat")
                        .font(.headline)
                } else {
                    // Tappable chat title that opens settings
                    Button {
                        showChatSettings = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(chat.title)
                                .font(.headline)
                                .lineLimit(1)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheetV2()
        }
        .sheet(isPresented: $showChatSettings) {
            ChatSettingsSheet(chat: chat)
        }
        .sheet(isPresented: $showAdditionalContextSheet) {
            AdditionalContextSheet(
                isWebSearchEnabled: $isWebSearchEnabled,
                onWebSearchToggled: { enabled in
                    isWebSearchEnabled = enabled
                },
                onAttachmentsSelected: { attachments in
                    pendingAttachments = attachments
                }
            )
        }
        .onAppear {
            // Switch to the chat's last used model if available
            if let lastModelId = chat.lastModelId {
                chatStore.switchToModel(withId: lastModelId)
            }
        }
        .onChange(of: chat.id) { oldId, newId in
            // Reset content ready state when switching chats
            isContentReady = false
        }
    }
    
    // MARK: - Empty State (Claude greeting style)
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            largeModelIconView
            
            Text(GreetingGenerator.greeting())
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.bottom, inputBarHeight)
    }
    
    // Large model icon for empty state
    @ViewBuilder
    private var largeModelIconView: some View {
        if selectedModel.isSystemIcon {
            Image(systemName: selectedModel.iconName)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(selectedModel.usesGradient ? 
                    AnyShapeStyle(selectedModel.appleIntelligenceGradient) : 
                    AnyShapeStyle(selectedModel.accentColor)
                )
        } else if selectedModel.isTemplateIcon {
            Image(selectedModel.iconName)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .foregroundStyle(selectedModel.usesGradient ? 
                    AnyShapeStyle(selectedModel.appleIntelligenceGradient) : 
                    AnyShapeStyle(selectedModel.accentColor)
                )
        } else {
            Image(selectedModel.iconName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
        }
    }
    
    // MARK: - Messages Scroll View
    
    private var messagesScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(chat.sortedMessages) { message in
                    MessageBubbleView(
                        message: message,
                        accentColor: selectedModel.accentColor,
                        onRegenerateWith: !message.isFromUser ? { model in
                            regenerateMessage(message, with: model)
                        } : nil,
                        onDelete: {
                            deleteMessage(message)
                        },
                        onEdit: message.isFromUser ? {
                            startEditing(message)
                        } : nil
                    )
                    .id(message.id)
                    .transition(message.isFromUser ? .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ) : .opacity)
                }
            }
            .scrollTargetLayout()
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: chat.messages.count)
            .padding(.top, 16)
            .padding(.bottom, inputBarHeight + 16)
        }
        .scrollPosition(id: $scrolledMessageID, anchor: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            let visibleBottom = geo.contentOffset.y + geo.containerSize.height
            let distanceFromBottom = geo.contentSize.height - visibleBottom
            return distanceFromBottom
        } action: { oldDistance, distanceFromBottom in
            let isAtBottomNow = distanceFromBottom < 120
            if isAtBottom != isAtBottomNow {
                isAtBottom = isAtBottomNow
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showScrollToBottom = !isAtBottomNow
                }
            }
        }
        .onAppear {
            // Set initial scroll position to the last message (while hidden)
            scrolledMessageID = chat.sortedMessages.last?.id
            
            // Wait for scroll to settle, then fade in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeOut(duration: 0.25)) {
                    isContentReady = true
                }
            }
        }
        .onChange(of: chat.messages.count) { oldCount, newCount in
            if isAtBottom {
                // Scroll to the newest message
                scrolledMessageID = chat.sortedMessages.last?.id
            }
        }
        .onChange(of: isChatGenerating) { old, new in
            if new && isAtBottom {
                scrolledMessageID = chat.sortedMessages.last?.id
            }
        }
    }
    
    // MARK: - Temporary Messages Scroll View (in-memory only)
    
    private var temporaryMessagesScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(temporaryMessages) { message in
                    MessageBubbleView(message: message, accentColor: selectedModel.accentColor)
                        .id(message.id)
                        .transition(message.isFromUser ? .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ) : .opacity)
                }
            }
            .scrollTargetLayout()
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: temporaryMessages.count)
            .padding(.top, 16)
            .padding(.bottom, inputBarHeight + 16)
        }
        .scrollPosition(id: $tempScrolledMessageID, anchor: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            let visibleBottom = geo.contentOffset.y + geo.containerSize.height
            let distanceFromBottom = geo.contentSize.height - visibleBottom
            return distanceFromBottom
        } action: { oldDistance, distanceFromBottom in
            let isAtBottomNow = distanceFromBottom < 120
            if isAtBottom != isAtBottomNow {
                isAtBottom = isAtBottomNow
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showScrollToBottom = !isAtBottomNow
                }
            }
        }
        .onChange(of: temporaryMessages.count) { oldCount, newCount in
            if isAtBottom {
                tempScrolledMessageID = temporaryMessages.last?.id
            }
        }
    }
    
    private var scrollToBottomButton: some View {
        Button {
            withAnimation {
                scrollToBottom()
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(width: 44, height: 44)
        .glassEffect(.regular.interactive(), in: Circle())
        
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.bottom, inputBarHeight + 20)
    }
    
    // MARK: - Input Bar with Liquid Glass
    
    // Button size for circular buttons - smaller
    private let buttonSize: CGFloat = 32
    
    private var inputBarView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Editing indicator
                if isEditing {
                    HStack(spacing: 8) {
                        Text("Editing message")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        
                        Spacer()
                        
                        Button {
                            cancelEditing()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.gray.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                
                // Pending attachments preview
                if !pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pendingAttachments) { attachment in
                                AttachmentPreviewChip(
                                    attachment: attachment,
                                    onRemove: {
                                        withAnimation {
                                            pendingAttachments.removeAll { $0.id == attachment.id }
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                
                TextField(isEditing ? "Edit your message" : (isEmptyState ? "Chat with AI" : "Reply to AI"), text: $messageText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textPrimary)
                    .tint(selectedModel.accentColor)
                    .focused($isInputFocused)
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isGeneratingTemporary || (isChatGenerating && !isNewChatMode))
                
                // Bottom row with circular buttons
                HStack(spacing: 10) {
                    // Plus button (attachments)
                    Button {
                        showAdditionalContextSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: buttonSize, height: buttonSize)
                            .background(Circle().fill(Color.gray.opacity(0.3)))
                    }
                    .buttonStyle(ScalableButtonStyle())
                    
                    // Model picker button - pill with icon and name
                    Button {
                        showModelPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            modelIconView
                            
                            Text(selectedModel.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: buttonSize)
                        .background(Capsule().fill(Color.gray.opacity(0.3)))
                    }
                    .buttonStyle(ScalableButtonStyle())
                    
                    // Web search indicator chip (shows when enabled)
                    if isWebSearchEnabled {
                        Button {
                            showAdditionalContextSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Web")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .frame(height: buttonSize)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                        .buttonStyle(ScalableButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Microphone button
                    Button {
                        // Voice input action
                    } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: buttonSize, height: buttonSize)
                            .background(Circle().fill(Color.gray.opacity(0.3)))
                    }
                    .buttonStyle(ScalableButtonStyle())
                    
                    // Send/Stop button
                    Button {
                        let isGenerating = isGeneratingTemporary || isChatGenerating
                        if isGenerating {
                            if isGeneratingTemporary {
                                // For temporary chats, we can't cancel mid-stream easily
                                // but we could add cancellation support later
                            } else {
                                chatStore.cancelGeneration(for: chat.id)
                            }
                        } else if canSend {
                            sendMessage()
                        }
                    } label: {
                        let isGenerating = isGeneratingTemporary || isChatGenerating
                        Image(systemName: isGenerating ? "stop.fill" : (canSend ? "arrow.up" : "waveform"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isGenerating ? Color.red.contrastingTextColor : selectedModel.buttonTextColor)
                            .frame(width: buttonSize, height: buttonSize)
                            .background {
                                if isGenerating {
                                    Circle().fill(Color.red)
                                } else if selectedModel.usesGradient {
                                    Circle().fill(selectedModel.appleIntelligenceGradient)
                                } else {
                                    Circle().fill(selectedModel.accentColor)
                                }
                            }
                    }
                    .buttonStyle(ScalableButtonStyle())
                    .sensoryFeedback(.impact(weight: .medium), trigger: isGeneratingTemporary || isChatGenerating)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 28)) // Block touches behind glass
            .onTapGesture {
                isInputFocused = true
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .contentShape(Rectangle()) // Block any touches in the entire input bar area
    }
    
    // Model icon view - handles both system and custom icons
    @ViewBuilder
    private var modelIconView: some View {
        if selectedModel.isSystemIcon {
            Image(systemName: selectedModel.iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selectedModel.usesGradient ? 
                    AnyShapeStyle(selectedModel.appleIntelligenceGradient) : 
                    AnyShapeStyle(selectedModel.accentColor)
                )
        } else if selectedModel.isTemplateIcon {
            Image(selectedModel.iconName)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(selectedModel.usesGradient ? 
                    AnyShapeStyle(selectedModel.appleIntelligenceGradient) : 
                    AnyShapeStyle(selectedModel.accentColor)
                )
        } else {
            Image(selectedModel.iconName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        }
    }
    
    // MARK: - Helpers
    
    private var canSend: Bool {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        let hasContent = hasText || hasAttachments
        
        if isNewChatMode && isTemporaryChat {
            return hasContent && !isGeneratingTemporary
        }
        return hasContent && !isChatGenerating
    }
    
    private func sendMessage() {
        // If we're in editing mode, submit the edit instead
        if isEditing {
            submitEdit()
            return
        }
        
        // Prevent sending while generating
        if isNewChatMode && isTemporaryChat {
            guard !isGeneratingTemporary else { return }
        } else {
            guard !isChatGenerating else { return }
        }
        
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        let webSearchEnabled = isWebSearchEnabled
        
        // Need either text or attachments
        guard !content.isEmpty || !attachments.isEmpty else { return }
        
        messageText = ""
        pendingAttachments = []
        isInputFocused = false
        // Reset web search after sending (one-shot per request)
        isWebSearchEnabled = false
        
        // Handle temporary chat - all in memory, no persistence
        if isNewChatMode && isTemporaryChat {
            sendTemporaryMessage(content: content, webSearchEnabled: webSearchEnabled)
            return
        }
        
        // If in new chat mode (but not temporary), create a new chat and navigate to it
        if isNewChatMode {
            let newChat = chatStore.createChat()
            
            // Exit new chat mode
            isNewChatMode = false
            isTemporaryChat = false
            
            // Navigate to the new chat (replace current view in stack)
            navigationPath.removeLast()
            navigationPath.append(newChat)
            
            // Send message to the new chat with attachments
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await chatStore.sendMessage(content: content, to: newChat, attachments: attachments, webSearchEnabled: webSearchEnabled)
            }
        } else {
            // Normal send to current chat with attachments
            Task {
                await chatStore.sendMessage(content: content, to: chat, attachments: attachments, webSearchEnabled: webSearchEnabled)
                await MainActor.run {
                    scrollToBottom()
                }
            }
        }
    }
    
    /// Send a message in temporary chat mode - everything stays in memory
    private func sendTemporaryMessage(content: String, webSearchEnabled: Bool = false) {
        // Create user message (in memory only)
        let userMessage = Message(content: content, isFromUser: true)
        temporaryMessages.append(userMessage)
        
        // Create AI response placeholder
        let aiMessage = Message(
            content: "",
            isFromUser: false,
            isStreaming: true,
            isSearchingWeb: webSearchEnabled,
            didSearchWeb: webSearchEnabled
        )
        temporaryMessages.append(aiMessage)
        
        isGeneratingTemporary = true
        
        // Build conversation for API
        var conversationMessages: [ChatMessage] = []
        
        // Use default system prompt for temporary chats
        let systemPrompt = DefaultChatSettings.shared.systemPrompt(for: selectedModel.name)
        if !systemPrompt.isEmpty {
            conversationMessages.append(ChatMessage(role: .system, content: systemPrompt))
        }
        
        for msg in temporaryMessages.dropLast() { // Exclude the empty AI placeholder
            conversationMessages.append(ChatMessage(
                role: msg.isFromUser ? .user : .assistant,
                content: msg.content
            ))
        }
        
        Task {
            do {
                var latestCitations: [String]?
                
                try await aiService.streamMessage(
                    messages: conversationMessages,
                    model: selectedModel,
                    webSearchEnabled: webSearchEnabled
                ) { [self] update in
                    // Find and update the AI message (callback is already on MainActor)
                    if let index = temporaryMessages.lastIndex(where: { !$0.isFromUser }) {
                        temporaryMessages[index].content = update.content
                        temporaryMessages[index].reasoningContent = update.reasoning
                        temporaryMessages[index].isThinking = update.isReasoning
                        temporaryMessages[index].isSearchingWeb = update.isSearchingWeb
                    }
                    // Track citations from web search or Perplexity
                    if let citations = update.citations {
                        latestCitations = citations
                    }
                }
                
                // Mark as done streaming and save citations
                if let index = temporaryMessages.lastIndex(where: { !$0.isFromUser }) {
                    temporaryMessages[index].isStreaming = false
                    temporaryMessages[index].isThinking = false
                    temporaryMessages[index].isSearchingWeb = false
                    // Store citations if present
                    if let citations = latestCitations, !citations.isEmpty {
                        if let jsonData = try? JSONEncoder().encode(citations),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            temporaryMessages[index].citationsJSON = jsonString
                        }
                    }
                }
                isGeneratingTemporary = false
                scrollToBottom()
            } catch {
                // Handle error
                if let index = temporaryMessages.lastIndex(where: { !$0.isFromUser }) {
                    temporaryMessages[index].content = "Error: \(error.localizedDescription)"
                    temporaryMessages[index].isStreaming = false
                }
                isGeneratingTemporary = false
            }
        }
        
        // Scroll to show the new messages
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            scrollToBottom()
        }
    }
    
    private func scrollToBottom(animate: Bool = true) {
        if animate {
            withAnimation(.easeOut(duration: 0.3)) {
                scrolledMessageID = chat.sortedMessages.last?.id
            }
        } else {
            scrolledMessageID = chat.sortedMessages.last?.id
        }
    }
    
    /// Regenerate an AI message using a specific model
    private func regenerateMessage(_ message: Message, with model: StoreModel) {
        Task {
            await chatStore.regenerateMessage(message, in: chat, withModel: model)
        }
    }
    
    /// Delete a message from the chat
    private func deleteMessage(_ message: Message) {
        chatStore.deleteMessage(message, from: chat)
    }
    
    /// Start editing a user message
    private func startEditing(_ message: Message) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            editingMessage = message
            isEditing = true
            messageText = message.content
        }
        isInputFocused = true
    }
    
    /// Cancel editing and clear the input
    private func cancelEditing() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            editingMessage = nil
            isEditing = false
            messageText = ""
        }
    }
    
    /// Submit the edited message
    private func submitEdit() {
        guard let message = editingMessage else { return }
        let newContent = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }
        
        // Clear editing state
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            editingMessage = nil
            isEditing = false
            messageText = ""
        }
        isInputFocused = false
        
        // Perform the edit
        Task {
            await chatStore.editMessage(message, in: chat, newContent: newContent)
        }
    }
}

// MARK: - Scalable Button Style

struct ScalableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Attachment Preview Chip

struct AttachmentPreviewChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if attachment.type == .image, let image = attachment.thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                // File attachment
                VStack(spacing: 4) {
                    Image(systemName: iconForFile(attachment.filename))
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.textSecondary)
                    
                    Text(attachment.filename)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.cardBackground)
                )
            }
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.7))
            }
            .offset(x: 8, y: -8)
        }
        .padding(.top, 8) // Prevent clipping of X button
        .padding(.trailing, 8) // Prevent clipping of X button
    }
    
    private func iconForFile(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "txt", "md":
            return "text.alignleft"
        case "zip", "rar", "7z":
            return "doc.zipper"
        case "mp3", "wav", "m4a":
            return "waveform"
        case "mp4", "mov", "avi":
            return "play.rectangle.fill"
        default:
            return "doc.fill"
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Chat.self, Message.self, configurations: config)
    let store = ChatStore(modelContext: container.mainContext)
    
    let chat = Chat(title: "Test Chat")
    container.mainContext.insert(chat)
    
    return NavigationStack {
        ChatDetailView(chat: chat, navigationPath: .constant(NavigationPath()))
            .environment(store)
            .modelContainer(container)
    }
}
