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
    @State private var selectedImageAttachment: MessageAttachment?
    @State private var selectedFileAttachment: MessageAttachment?
    
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
        .fullScreenCover(item: $selectedImageAttachment) { attachment in
            FullscreenImageView(attachment: attachment)
        }
        .sheet(item: $selectedFileAttachment) { attachment in
            FilePreviewSheet(attachment: attachment)
        }
    }
    
    // MARK: - User Message (Cream bubble on right)
    
    private var userMessageView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Show attachments if any (right-aligned, no context menu)
            if message.hasAttachments {
                userAttachmentsView
            }
            
            // Only show text bubble if there's content (with context menu)
            if !message.content.isEmpty {
                HStack {
                    Spacer(minLength: 60)
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
                            // Only show edit if message has no attachments
                            if onEdit != nil && !message.hasAttachments {
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
            } else if message.hasAttachments {
                // If only attachments (no text), show a minimal delete context menu on the attachment area
                Color.clear
                    .frame(height: 1)
                    .contextMenu {
                        if onDelete != nil {
                            Button(role: .destructive) {
                                showUserDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
    
    // MARK: - User Attachments View
    
    private var userAttachmentsView: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(message.attachments) { attachment in
                    attachmentThumbnail(for: attachment)
                        .onTapGesture {
                            if attachment.type == .image {
                                selectedImageAttachment = attachment
                            } else {
                                selectedFileAttachment = attachment
                            }
                        }
                }
            }
        }
    }
    
    @ViewBuilder
    private func attachmentThumbnail(for attachment: MessageAttachment) -> some View {
        if attachment.type == .image, let imageData = Data(base64Encoded: attachment.base64Data) {
            #if os(iOS)
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            #else
            if let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            #endif
        } else {
            // File attachment chip
            HStack(spacing: 6) {
                Image(systemName: iconForMimeType(attachment.mimeType))
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(attachment.filename)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.cardBackground)
            }
        }
    }
    
    private func iconForMimeType(_ mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.contains("pdf") { return "doc.fill" }
        if mimeType.contains("text") { return "doc.text" }
        return "doc"
    }
    
// MARK: - AI Message (Full-width markdown)

private var aiMessageView: some View {
    VStack(alignment: .leading, spacing: 8) {
        // Show web search indicator if searching or has searched
        if message.isSearchingWeb || message.didSearchWeb {
            WebSearchIndicatorView(isSearching: message.isSearchingWeb)
                .padding(.horizontal, horizontalPadding)
        }
        
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
        
        if message.isStreaming && message.content.isEmpty && !message.isThinking && !message.isSearchingWeb {
            // Only show typing indicator if not in thinking mode or web search mode
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
        for model in modelStore.libraryModels {
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

// MARK: - Fullscreen Image View

struct FullscreenImageView: View {
    let attachment: MessageAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let imageData = Data(base64Encoded: attachment.base64Data) {
                #if os(iOS)
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = lastScale * value.magnification
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation(.spring(response: 0.3)) {
                                            scale = 1.0
                                            lastScale = 1.0
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                }
                #else
                if let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                #endif
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}

// MARK: - File Preview Sheet

struct FilePreviewSheet: View {
    let attachment: MessageAttachment
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if let data = attachment.data {
                    FilePreviewContent(data: data, filename: attachment.filename, mimeType: attachment.mimeType)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Unable to Preview",
                        systemImage: "doc.questionmark",
                        description: Text("The file data could not be loaded.")
                    )
                }
            }
            .navigationTitle(attachment.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - File Preview Content

struct FilePreviewContent: View {
    let data: Data
    let filename: String
    let mimeType: String
    
    var body: some View {
        let lowercaseMime = mimeType.lowercased()
        let lowercaseFilename = filename.lowercased()
        
        if lowercaseMime.contains("pdf") || lowercaseFilename.hasSuffix(".pdf") {
            // PDF preview using PDFKit
            PDFPreviewView(data: data)
                .ignoresSafeArea(edges: .bottom)
        } else if isTextFile {
            // Text file preview
            TextFilePreview(data: data, filename: filename)
        } else {
            // Generic file - show info
            GenericFilePreview(filename: filename, mimeType: mimeType, dataSize: data.count)
        }
    }
    
    private var isTextFile: Bool {
        let lowercaseMime = mimeType.lowercased()
        let lowercaseFilename = filename.lowercased()
        
        if lowercaseMime.hasPrefix("text/") { return true }
        if lowercaseMime.contains("json") || lowercaseMime.contains("xml") { return true }
        
        let textExtensions = [".txt", ".md", ".json", ".xml", ".html", ".css", ".js", ".ts",
                              ".swift", ".py", ".rb", ".java", ".c", ".cpp", ".h", ".m",
                              ".sh", ".yaml", ".yml", ".toml", ".ini", ".csv", ".log", ".sql"]
        return textExtensions.contains { lowercaseFilename.hasSuffix($0) }
    }
}

// MARK: - PDF Preview

#if canImport(PDFKit)
import PDFKit

struct PDFPreviewView: View {
    let data: Data
    
    var body: some View {
        PDFKitView(data: data)
    }
}

#if os(iOS)
struct PDFKitView: UIViewRepresentable {
    let data: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#else
struct PDFKitView: NSViewRepresentable {
    let data: Data
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {}
}
#endif
#else
struct PDFPreviewView: View {
    let data: Data
    
    var body: some View {
        ContentUnavailableView(
            "PDF Preview Unavailable",
            systemImage: "doc.fill",
            description: Text("PDFKit is not available on this platform.")
        )
    }
}
#endif

// MARK: - Text File Preview

struct TextFilePreview: View {
    let data: Data
    let filename: String
    
    private var textContent: String? {
        String(data: data, encoding: .utf8)
    }
    
    var body: some View {
        if let content = textContent {
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Unable to Read File",
                systemImage: "doc.text",
                description: Text("The file could not be decoded as text.")
            )
        }
    }
}

// MARK: - Generic File Preview

struct GenericFilePreview: View {
    let filename: String
    let mimeType: String
    let dataSize: Int
    
    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(dataSize))
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: iconForMimeType)
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text(filename)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text(mimeType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(formattedSize)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private var iconForMimeType: String {
        let mime = mimeType.lowercased()
        if mime.contains("pdf") { return "doc.fill" }
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "video" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.hasPrefix("text/") { return "doc.text" }
        if mime.contains("zip") || mime.contains("archive") { return "archivebox" }
        return "doc"
    }
}
