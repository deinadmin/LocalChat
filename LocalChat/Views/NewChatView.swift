//
//  NewChatView.swift
//  LocalChat
//
//  Created by Carl Steen on 21.01.26.
//

import SwiftUI
import SwiftData

/// View for starting a new chat - creates the chat only when the first message is sent
struct NewChatView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Binding var navigationPath: NavigationPath
    
    @State private var messageText = ""
    @State private var showModelPicker = false
    @State private var aiService = AIService.shared
    @FocusState private var isInputFocused: Bool
    
    // Height of input bar for bottom padding calculation
    @State private var inputBarHeight: CGFloat = 120
    
    // Temporary chat mode
    @State private var isTemporaryChat = false
    @State private var temporaryMessages: [Message] = []
    @State private var isGeneratingTemporary = false
    
    private var selectedModel: StoreModel {
        aiService.currentModel
    }
    
    /// Whether we're in empty state (no messages yet)
    private var isEmptyState: Bool {
        temporaryMessages.isEmpty
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            AppTheme.background
                .ignoresSafeArea()
            
            // Empty state or temporary messages
            if isEmptyState {
                emptyStateView
            } else {
                temporaryMessagesScrollView
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
        .navigationTitle(isTemporaryChat ? "Temporary Chat" : "New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Show temporary chat toggle when in empty state, otherwise show nothing
                if isEmptyState {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTemporaryChat.toggle()
                        }
                    } label: {
                        Image(systemName: isTemporaryChat ? "clock.fill" : "clock")
                    }
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: isTemporaryChat)
                }
            }
            
            ToolbarItem(placement: .principal) {
                // Show "New Chat" or "Temporary Chat" based on mode
                Text(isTemporaryChat ? "Temporary Chat" : "New Chat")
                    .font(.headline)
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheetV2()
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
    
    // MARK: - Temporary Messages Scroll View
    
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isAtBottom = true
    
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
    
    private func scrollToBottom(animate: Bool = true) {
        if animate {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy?.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            scrollProxy?.scrollTo("bottom", anchor: .bottom)
        }
    }
    
    // MARK: - Input Bar with Liquid Glass
    
    // Button size for circular buttons - smaller
    private let buttonSize: CGFloat = 32
    
    private var inputBarView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(isEmptyState ? "Chat with AI" : "Reply to AI", text: $messageText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textPrimary)
                    .focused($isInputFocused)
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isGeneratingTemporary)
                
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
                        if isGeneratingTemporary {
                            // Cancel not implemented for temporary chats
                        } else if canSend {
                            sendMessage()
                        }
                    } label: {
                        Image(systemName: isGeneratingTemporary ? "stop.fill" : (canSend ? "arrow.up" : "waveform"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isGeneratingTemporary ? Color.red.contrastingTextColor : selectedModel.accentColor.contrastingTextColor)
                            .frame(width: buttonSize, height: buttonSize)
                            .background {
                                if isGeneratingTemporary {
                                    Circle().fill(Color.red)
                                } else if selectedModel.usesGradient {
                                    Circle().fill(selectedModel.appleIntelligenceGradient)
                                } else {
                                    Circle().fill(selectedModel.accentColor)
                                }
                            }
                    }
                    .buttonStyle(ScalableButtonStyle())
                    .sensoryFeedback(.impact(weight: .medium), trigger: isGeneratingTemporary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: 28)) // Block touches behind glass
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
        return hasText && !isGeneratingTemporary
    }
    
    private func sendMessage() {
        guard !isGeneratingTemporary else { return }
        
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        messageText = ""
        isInputFocused = false
        
        // If temporary chat mode, handle in-memory
        if isTemporaryChat {
            sendTemporaryMessage(content: content)
            return
        }
        
        // Create the chat now (permanent)
        let chat = chatStore.createChat()
        
        // Replace current navigation (NewChatDestination) with the actual chat
        navigationPath.removeLast()
        navigationPath.append(chat)
        
        // Send the message after navigation
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await chatStore.sendMessage(content: content, to: chat)
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
                try await aiService.streamMessage(
                    messages: conversationMessages,
                    model: selectedModel
                ) { [self] update in
                    // Find and update the AI message (already on MainActor)
                    if let index = temporaryMessages.lastIndex(where: { !$0.isFromUser }) {
                        temporaryMessages[index].content = update.content
                        temporaryMessages[index].reasoningContent = update.reasoning
                        temporaryMessages[index].isThinking = update.isReasoning
                    }
                }
                
                // Mark as done streaming
                if let index = temporaryMessages.lastIndex(where: { !$0.isFromUser }) {
                    temporaryMessages[index].isStreaming = false
                    temporaryMessages[index].isThinking = false
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
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            scrollToBottom()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Chat.self, Message.self, configurations: config)
    let store = ChatStore(modelContext: container.mainContext)
    
    return NavigationStack {
        NewChatView(navigationPath: .constant(NavigationPath()))
            .environment(store)
            .modelContainer(container)
    }
}
