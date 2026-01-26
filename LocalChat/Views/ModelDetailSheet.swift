//
//  ModelDetailSheet.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI
import SwiftData

struct ModelDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let model: StoreModel
    var onStartChat: ((Chat) -> Void)?
    
    @State private var aiService = AIService.shared
    @State private var isModelReady = false
    @State private var showAPIKeyEntry = false
    @State private var apiKeyInput = ""
    @State private var isValidatingKey = false
    @State private var validationError: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Quick stats
                        statsSection
                        
                        // Use button (only shown if ready)
                        if isModelReady {
                            useButton
                        }
                        
                        // Description
                        descriptionSection
                        
                        // Capabilities
                        capabilitiesSection
                        
                        // API Key section (if needed)
                        if model.requiresAPIKey {
                            apiKeySection
                        }
                        
                        // Technical details
                        technicalDetailsSection
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
            .task {
                isModelReady = await aiService.isModelReady(model)
            }
        }
        .presentationDetents([.large])
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(model.usesGradient ? 
                        AnyShapeStyle(model.appleIntelligenceGradient.opacity(0.15)) : 
                        AnyShapeStyle(model.accentColor.opacity(0.15))
                    )
                    .frame(width: 80, height: 80)
                
                if model.isSystemIcon {
                    Image(systemName: model.iconName)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(model.usesGradient ? 
                            AnyShapeStyle(model.appleIntelligenceGradient) : 
                            AnyShapeStyle(model.accentColor)
                        )
                } else if model.isTemplateIcon {
                    Image(model.iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(model.usesGradient ? 
                            AnyShapeStyle(model.appleIntelligenceGradient) : 
                            AnyShapeStyle(model.accentColor)
                        )
                } else {
                    Image(model.iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                }
            }
            
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    if model.isNew {
                        Text("NEW")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(model.accentColor))
                    }
                }
                
                HStack(spacing: 4) {
                    Image(systemName: model.providerType.iconName)
                        .font(.system(size: 12))
                    
                    Text(model.provider)
                        .font(.system(size: 15))
                }
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        HStack(spacing: 0) {
            statItem(
                title: "Context",
                value: model.formattedContextLength,
                icon: "text.alignleft"
            )
            
            Divider()
                .frame(height: 40)
            
            if let inputPrice = model.inputPricePerMillion {
                statItem(
                    title: "Input",
                    value: "$\(String(format: "%.2f", inputPrice))/M",
                    icon: "arrow.up.circle"
                )
                
                Divider()
                    .frame(height: 40)
            }
            
            if let outputPrice = model.outputPricePerMillion {
                statItem(
                    title: "Output",
                    value: "$\(String(format: "%.2f", outputPrice))/M",
                    icon: "arrow.down.circle"
                )
            } else {
                statItem(
                    title: "Price",
                    value: "Free",
                    icon: "gift"
                )
            }
        }
        .padding(.vertical, 16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func statItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.textSecondary)
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Description Section
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text(model.description)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Capabilities Section
    
    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capabilities")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            FlowLayout(spacing: 8) {
                ForEach(model.capabilities, id: \.self) { capability in
                    Text(capability.rawValue.capitalized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(AppTheme.cardBackground)
                        }
                }
                
                // Input modalities
                ForEach(model.inputModalities, id: \.self) { modality in
                    HStack(spacing: 4) {
                        Image(systemName: modalityIcon(modality))
                            .font(.system(size: 11))
                        Text(modality.rawValue.capitalized)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .stroke(AppTheme.divider, lineWidth: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func modalityIcon(_ modality: StoreModel.Modality) -> String {
        switch modality {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "video"
        case .file: return "doc"
        }
    }
    
    // MARK: - API Key Section
    
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("API Key")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Spacer()
                
                if isModelReady {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Configured")
                            .foregroundStyle(.green)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
            
            if !isModelReady || showAPIKeyEntry {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                        
                        SecureField("Enter \(model.providerType.displayName) API Key", text: $apiKeyInput)
                            .font(.system(size: 16))
                    }
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.cardBackground)
                    }
                    
                    if let error = validationError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                    
                    Button {
                        Task {
                            await saveAPIKey()
                        }
                    } label: {
                        HStack {
                            if isValidatingKey {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isValidatingKey ? "Validating..." : "Save API Key")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(apiKeyInput.isEmpty ? AppTheme.textTertiary : AppTheme.accent)
                        }
                    }
                    .disabled(apiKeyInput.isEmpty || isValidatingKey)
                }
            } else {
                Button {
                    showAPIKeyEntry = true
                } label: {
                    Text("Update API Key")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.cardBackground)
        }
    }
    
    // MARK: - Use Button
    
    private var useButton: some View {
        Button {
            startNewChat()
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text("Start Chat")
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .glassEffect(.regular.tint(model.accentColor), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Technical Details
    
    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technical Details")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            VStack(spacing: 0) {
                detailRow("Model ID", value: model.modelId)
                Divider()
                detailRow("Context Length", value: "\(model.contextLength.formatted()) tokens")
                if let maxOutput = model.maxOutputTokens {
                    Divider()
                    detailRow("Max Output", value: "\(maxOutput.formatted()) tokens")
                }
                Divider()
                detailRow("Streaming", value: model.supportsStreaming ? "Supported" : "Not supported")
                Divider()
                detailRow("Function Calling", value: model.supportsFunctionCalling ? "Supported" : "Not supported")
                if let minVersion = model.minimumIOSVersion {
                    Divider()
                    detailRow("Minimum iOS", value: minVersion)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Actions
    
    private func saveAPIKey() async {
        isValidatingKey = true
        validationError = nil
        
        let isValid = await aiService.validateAPIKey(apiKeyInput, for: model.providerType)
        
        if isValid {
            do {
                try await aiService.setAPIKey(apiKeyInput, for: model.providerType)
                isModelReady = true
                showAPIKeyEntry = false
                apiKeyInput = ""
            } catch {
                validationError = error.localizedDescription
            }
        } else {
            validationError = "Invalid API key. Please check and try again."
        }
        
        isValidatingKey = false
    }
    
    private func startNewChat() {
        // Set the model as current (but don't change the default for new chats)
        aiService.setCurrentModel(model, updateDefault: false)
        
        // Create a new chat
        let newChat = Chat(title: "Chat with \(model.name)")
        modelContext.insert(newChat)
        
        // Dismiss and notify parent to navigate
        dismiss()
        onStartChat?(newChat)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        return (CGSize(width: maxWidth, height: currentY + lineHeight), frames)
    }
}

// MARK: - Preview

#Preview {
    ModelDetailSheet(model: StoreModel.sampleModels[0])
}
