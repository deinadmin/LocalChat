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
    @State private var scrollProxy: ScrollViewProxy?
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
    
    // State for "new chat" mode - shows empty state without creating a chat yet
    @State private var isNewChatMode = false
    // Temporary chat mode - chat won't be persisted
    @State private var isTemporaryChat = false
    // In-memory messages for temporary chat
    @State private var temporaryMessages: [Message] = []
    // Track if we're generating a response for temporary chat
    @State private var isGeneratingTemporary = false
    
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
                messagesScrollView
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
        .onAppear {
            // Switch to the chat's last used model if available
            if let lastModelId = chat.lastModelId {
                chatStore.switchToModel(withId: lastModelId)
            }
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
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .foregroundStyle(selectedModel.usesGradient ? 
                    AnyShapeStyle(selectedModel.appleIntelligenceGradient) : 
                    AnyShapeStyle(selectedModel.accentColor)
                )
        } else {
            Image(selectedModel.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
        }
    }
    
    // MARK: - Messages Scroll View
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
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
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: chat.messages.count)
                .padding(.top, 16)
                .padding(.bottom, inputBarHeight + 16) // Extra padding for input bar overlay
                
                // Invisible bottom anchor - AFTER the padding so scrolling here reaches true bottom
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                // Calculate distance from bottom of content
                // contentOffset.y + containerSize.height = how far down we've scrolled + visible area
                // contentSize.height = total scrollable content
                let visibleBottom = geo.contentOffset.y + geo.containerSize.height
                let distanceFromBottom = geo.contentSize.height - visibleBottom
                return distanceFromBottom
            } action: { oldDistance, distanceFromBottom in
                // We're at bottom if within 100pt of the bottom
                let isAtBottomNow = distanceFromBottom < 120
                if isAtBottom != isAtBottomNow {
                    isAtBottom = isAtBottomNow
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showScrollToBottom = !isAtBottomNow
                    }
                }
            }
            .task {
                // Store proxy for later use
                scrollProxy = proxy
                // Wait for layout to fully complete, then scroll to bottom
                // Use multiple attempts to ensure scroll succeeds after layout
                try? await Task.sleep(for: .milliseconds(50))
                scrollToBottom(animate: false)
                try? await Task.sleep(for: .milliseconds(150))
                scrollToBottom(animate: false)
            }
            .onChange(of: chat.messages.count) { oldCount, newCount in
                // Auto-scroll if we're already at the bottom
                if isAtBottom {
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        scrollToBottom()
                    }
                }
            }
            .onChange(of: isChatGenerating) { old, new in
                // Scroll when generation starts if we're at bottom
                if new && isAtBottom {
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        scrollToBottom()
                    }
                }
            }
        }
    }
    
    // MARK: - Temporary Messages Scroll View (in-memory only)
    
    private var temporaryMessagesScrollView: some View {
        ScrollViewReader { proxy in
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
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: temporaryMessages.count)
                .padding(.top, 16)
                .padding(.bottom, inputBarHeight + 16)
                
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
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
            .task {
                scrollProxy = proxy
            }
            .onChange(of: temporaryMessages.count) { oldCount, newCount in
                if isAtBottom {
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        scrollToBottom()
                    }
                }
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
                        // Attachments action
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
                            .foregroundStyle(isGenerating ? Color.red.contrastingTextColor : selectedModel.accentColor.contrastingTextColor)
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
                    AnyShapeStyle(AppTheme.textPrimary)
                )
        } else if selectedModel.isTemplateIcon {
            Image(selectedModel.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(selectedModel.usesGradient ? 
                    AnyShapeStyle(selectedModel.appleIntelligenceGradient) : 
                    AnyShapeStyle(selectedModel.accentColor)
                )
        } else {
            Image(selectedModel.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        }
    }
    
    // MARK: - Helpers
    
    private var canSend: Bool {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isNewChatMode && isTemporaryChat {
            return hasText && !isGeneratingTemporary
        }
        return hasText && !isChatGenerating
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
        guard !content.isEmpty else { return }
        
        messageText = ""
        isInputFocused = false
        
        // Handle temporary chat - all in memory, no persistence
        if isNewChatMode && isTemporaryChat {
            sendTemporaryMessage(content: content)
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
            
            // Send message to the new chat
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await chatStore.sendMessage(content: content, to: newChat)
            }
        } else {
            // Normal send to current chat
            Task {
                await chatStore.sendMessage(content: content, to: chat)
                await MainActor.run {
                    scrollToBottom()
                }
            }
        }
    }
    
    /// Send a message in temporary chat mode - everything stays in memory
    private func sendTemporaryMessage(content: String) {
        // Create user message (in memory only)
        let userMessage = Message(content: content, isFromUser: true)
        temporaryMessages.append(userMessage)
        
        // Create AI response placeholder
        let aiMessage = Message(content: "", isFromUser: false, isStreaming: true)
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
                    model: selectedModel
                ) { [self] update in
                    // Find and update the AI message (callback is already on MainActor)
                    if let index = temporaryMessages.lastIndex(where: { !$0.isFromUser }) {
                        temporaryMessages[index].content = update.content
                        temporaryMessages[index].reasoningContent = update.reasoning
                        temporaryMessages[index].isThinking = update.isReasoning
                    }
                    // Track citations from Perplexity
                    if let citations = update.citations {
                        latestCitations = citations
                    }
                }
                
                // Mark as done streaming and save citations
                if let index = temporaryMessages.lastIndex(where: { !$0.isFromUser }) {
                    temporaryMessages[index].isStreaming = false
                    temporaryMessages[index].isThinking = false
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
                scrollProxy?.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            scrollProxy?.scrollTo("bottom", anchor: .bottom)
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
