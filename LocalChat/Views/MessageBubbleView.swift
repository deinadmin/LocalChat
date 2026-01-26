//
//  MessageBubbleView.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let accentColor: Color
    var onRegenerateWith: ((StoreModel) -> Void)?
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    
    @State private var showCursor = true
    @State private var showActions = false
    @State private var copied = false
    @State private var showReasoningSheet = false
    @State private var showSourcesSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showUserDeleteConfirmation = false
    @State private var availableModels: [StoreModel] = []
    @State private var regenerateTrigger = false
    @State private var deleteTrigger = false
    
    /// The display name for this message's model (AI messages only)
    private var messageModelName: String {
        message.modelName ?? "AI"
    }
    
    init(message: Message, accentColor: Color = AppTheme.accent, onRegenerateWith: ((StoreModel) -> Void)? = nil, onDelete: (() -> Void)? = nil, onEdit: (() -> Void)? = nil) {
        self.message = message
        self.accentColor = accentColor
        self.onRegenerateWith = onRegenerateWith
        self.onDelete = onDelete
        self.onEdit = onEdit
    }
    
    // Standard horizontal padding for content
    private let horizontalPadding: CGFloat = 16
    
    private var isUser: Bool { message.isFromUser }
    
    /// Get citations from the message
    private var citations: [Citation] {
        Citation.fromURLs(message.citations)
    }
    
    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
            if isUser {
                userMessageView
            } else {
                aiMessageView
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .textSelection(.enabled)
        .sheet(isPresented: $showReasoningSheet) {
            if let reasoning = message.reasoningContent {
                ReasoningSheetView(
                    reasoningContent: reasoning,
                    thinkingDuration: message.thinkingDuration
                )
            }
        }
        .sheet(isPresented: $showSourcesSheet) {
            SourcesSheetView(citations: citations, accentColor: accentColor)
        }
    }
    
    // MARK: - User Message (Cream bubble on right)
    
    private var userMessageView: some View {
        HStack {
            Spacer(minLength: 60) // Push to right, leave at least 60pt on left
            
            Text(message.content)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.cardBackground)
                }
                .contextMenu {
                    if onEdit != nil {
                        Button {
                            onEdit?()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    
                    if onDelete != nil {
                        Button(role: .destructive) {
                            showUserDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        }
        .padding(.horizontal, horizontalPadding)
        .alert("Delete Message", isPresented: $showUserDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteTrigger.toggle()
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete this message?")
        }
        .sensoryFeedback(.warning, trigger: deleteTrigger)
    }
    
// MARK: - AI Message (Full-width markdown)

private var aiMessageView: some View {
    VStack(alignment: .leading, spacing: 8) {
        // Show thinking indicator if model is reasoning or has reasoning content
        if message.isThinking || message.hasReasoningContent {
            ThinkingIndicatorView(
                isThinking: message.isThinking,
                thinkingStartTime: message.thinkingStartTime,
                thinkingDuration: message.thinkingDuration,
                onTap: {
                    if message.hasReasoningContent {
                        showReasoningSheet = true
                    }
                }
            )
            .padding(.horizontal, horizontalPadding)
        }
        
        if message.isStreaming && message.content.isEmpty && !message.isThinking {
            // Only show typing indicator if not in thinking mode
            typingIndicator
                .padding(.horizontal, horizontalPadding)
        } else if !message.content.isEmpty {
            // Full-width markdown content - padding handled per-block
            // Pass citations for inline pill rendering
            MarkdownView(
                message.content,
                isStreaming: message.isStreaming,
                horizontalPadding: horizontalPadding,
                accentColor: accentColor,
                citations: citations,
                onCitationTap: { showSourcesSheet = true }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Sources chips (above action buttons)
            if !message.isStreaming && message.hasCitations {
                SourceChipsView(
                    citations: citations,
                    accentColor: accentColor,
                    horizontalPadding: horizontalPadding,
                    onSourceTap: { showSourcesSheet = true }
                )
                .padding(.top, 0)
            }
            
            // Action buttons always visible
            if !message.isStreaming {
                actionButtons
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
    
    // MARK: - Action Buttons
    
    private let chipHeight: CGFloat = 28
    
    private var actionButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Copy button - fixed width to prevent layout shift when text changes
                Button {
                    copyMessage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 14) // Fixed icon width
                        Text(copied ? "" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(copied ? .green : AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(width: 72, height: chipHeight) // Fixed size to prevent layout shift
                    .background {
                        Capsule()
                            .fill(AppTheme.cardBackground)
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: copied) { _, newValue in
                    newValue
                }
                
                // Regenerate with model menu - between Copy and Share
                if onRegenerateWith != nil && !availableModels.isEmpty {
                    Menu {
                        ForEach(availableModels) { model in
                            Button(model.name) {
                                regenerateTrigger.toggle()
                                onRegenerateWith?(model)
                            }
                        }
                    } label: {
                        Text(messageModelName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: chipHeight)
                            .background {
                                Capsule()
                                    .fill(AppTheme.cardBackground)
                            }
                    } primaryAction: {
                        // Primary tap action - regenerate with the message's original model if available
                        regenerateTrigger.toggle()
                        if let modelId = message.modelId,
                           let originalModel = availableModels.first(where: { $0.modelId == modelId }) {
                            onRegenerateWith?(originalModel)
                        } else if let firstModel = availableModels.first {
                            onRegenerateWith?(firstModel)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: regenerateTrigger)
                }
                
                // Share button
                ShareLink(item: message.content) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 14) // Fixed icon width
                        Text("Share")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: chipHeight) // Fixed height
                    .background {
                        Capsule()
                            .fill(AppTheme.cardBackground)
                    }
                }
                .buttonStyle(.plain)
                
                // Delete button
                if onDelete != nil {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 14)
                            Text("Delete")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: chipHeight)
                        .background {
                            Capsule()
                                .fill(AppTheme.cardBackground)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .alert("Delete Message", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteTrigger.toggle()
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete this message?")
        }
        .sensoryFeedback(.warning, trigger: deleteTrigger)
        .task {
            await loadAvailableModels()
        }
    }
    
    private func loadAvailableModels() async {
        let modelStore = ModelStoreService.shared
        let aiService = AIService.shared
        var ready: [StoreModel] = []
        for model in modelStore.allModels {
            let isReady = await aiService.isModelReady(model)
            if isReady {
                ready.append(model)
            }
        }
        await MainActor.run {
            availableModels = ready
        }
    }
    
    // MARK: - Typing Indicator
    
    private var typingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(AppTheme.textSecondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(showCursor ? 1 : 0.5)
                    .opacity(showCursor ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: showCursor
                    )
            }
        }
        .padding(.vertical, 8)
        .onAppear { showCursor.toggle() }
    }
    
    // MARK: - Actions
    
    private func copyMessage() {
        #if os(iOS)
        UIPasteboard.general.string = message.content
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #endif
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copied = true
        }
        
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    copied = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Chat Messages") {
    ScrollView {
        VStack(spacing: 20) {
            MessageBubbleView(
                message: Message(
                    content: "Can you explain how async/await works in Swift?",
                    isFromUser: true
                )
            )
            
            // Message that's currently thinking
            MessageBubbleView(
                message: Message(
                    content: "",
                    isFromUser: false,
                    isStreaming: true,
                    isThinking: true,
                    thinkingStartTime: Date().addingTimeInterval(-8)
                )
            )
            
            // Message with completed reasoning
            MessageBubbleView(
                message: Message(
                    content: """
                    # Async/Await in Swift
                    
                    Swift's `async/await` is a powerful concurrency model introduced in Swift 5.5. Here's a quick overview:
                    
                    ## Key Concepts
                    
                    - **async** marks a function as asynchronous
                    - **await** suspends execution until the result is ready
                    - Tasks run on a cooperative thread pool
                    
                    ## Example
                    
                    ```swift
                    func fetchData() async throws -> Data {
                        let url = URL(string: "https://api.example.com/data")!
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return data
                    }
                    
                    // Calling an async function
                    Task {
                        do {
                            let data = try await fetchData()
                            print("Received \\(data.count) bytes")
                        } catch {
                            print("Error: \\(error)")
                        }
                    }
                    ```
                    
                    ## Benefits
                    
                    1. Cleaner code compared to completion handlers
                    2. Better error handling with `try/catch`
                    3. Structured concurrency with `Task` and `TaskGroup`
                    
                    > **Note:** Always use `@MainActor` when updating UI from async contexts.
                    
                    For more details, check out [Apple's documentation](https://developer.apple.com/documentation/swift/concurrency).
                    """,
                    isFromUser: false,
                    reasoningContent: """
                    Let me think through how to explain async/await clearly.
                    
                    ## Key Points to Cover
                    
                    1. What async/await is and why it was introduced
                    2. The basic syntax and keywords
                    3. A practical example
                    4. The benefits over completion handlers
                    
                    I should keep the explanation concise but include code examples since the user is asking about a specific Swift feature.
                    """,
                    thinkingDuration: 12
                )
            )
            
            MessageBubbleView(
                message: Message(
                    content: "",
                    isFromUser: false,
                    isStreaming: true
                )
            )
        }
        .padding()
    }
    .background(AppTheme.background)
}
