//
//  DefaultChatSettingsSheet.swift
//  LocalChat
//
//  Created by Carl Steen on 21.01.26.
//

import SwiftUI

/// Sheet for editing default settings for new chats
struct DefaultChatSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var defaultSettings = DefaultChatSettings.shared
    @State private var modelStore = ModelStoreService.shared
    
    @State private var systemPrompt: String
    @State private var systemPromptEnabled: Bool
    @State private var autoGenerateTitle: Bool
    @State private var selectedDefaultModel: StoreModel?
    @State private var showModelPicker = false
    
    init() {
        let settings = DefaultChatSettings.shared
        _systemPrompt = State(initialValue: settings.defaultSystemPrompt)
        _systemPromptEnabled = State(initialValue: settings.systemPromptEnabled)
        _autoGenerateTitle = State(initialValue: settings.autoGenerateTitle)
        _selectedDefaultModel = State(initialValue: settings.defaultModel)
    }
    
    /// Toggle tint - black in light mode, default iOS green in dark mode
    private var toggleTint: Color? {
        AppTheme.toggleTint(for: colorScheme)
    }
    
    /// The model to display (selected or fallback to first available)
    private var displayModel: StoreModel {
        selectedDefaultModel ?? modelStore.allModels.first ?? StoreModel.fallbackModel
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Default Model Section
                        defaultModelSection
                        
                        // Title Section
                        titleSection
                        
                        // System Prompt Section
                        systemPromptSection
                        
                        // Tools Section
                        toolsSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Default Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            DefaultModelPickerSheet(selectedModel: $selectedDefaultModel)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Default Model Section
    
    private var defaultModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Default Model")
            
            Button {
                showModelPicker = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(displayModel.usesGradient ?
                                AnyShapeStyle(displayModel.appleIntelligenceGradient.opacity(0.15)) :
                                AnyShapeStyle(displayModel.accentColor.opacity(0.15))
                            )
                            .frame(width: 48, height: 48)
                        
                        if displayModel.isSystemIcon {
                            Image(systemName: displayModel.iconName)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(displayModel.usesGradient ?
                                    AnyShapeStyle(displayModel.appleIntelligenceGradient) :
                                    AnyShapeStyle(displayModel.accentColor)
                                )
                        } else if displayModel.isTemplateIcon {
                            Image(displayModel.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(displayModel.usesGradient ?
                                    AnyShapeStyle(displayModel.appleIntelligenceGradient) :
                                    AnyShapeStyle(displayModel.accentColor)
                                )
                        } else {
                            Image(displayModel.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayModel.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text("Used for new chats")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.cardBackground)
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Title")
            
            VStack(spacing: 0) {
                Toggle(isOn: $autoGenerateTitle) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-generate Title")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            Text("Automatically create titles based on conversation")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .tint(toggleTint)
                .padding(14)
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
    }
    
    // MARK: - System Prompt Section
    
    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Default System Instructions")
            
            VStack(spacing: 0) {
                // Enable/disable toggle
                Toggle(isOn: $systemPromptEnabled) {
                    HStack(spacing: 12) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable System Instructions")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            
                            Text("Applied to all new chats by default")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .tint(toggleTint)
                .padding(14)
                
                if systemPromptEnabled {
                    Divider()
                        .padding(.horizontal, 14)
                    
                    // System prompt text editor
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 200, maxHeight: 300)
                        
                        HStack {
                            Text("Use {MODEL_NAME} to insert the current model name")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textTertiary)
                            
                            Spacer()
                            
                            Button("Reset to Default") {
                                systemPrompt = DefaultChatSettings.builtInSystemPrompt
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(14)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
            .animation(.easeInOut(duration: 0.2), value: systemPromptEnabled)
        }
    }
    
    // MARK: - Tools Section
    
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Default Tools")
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Tools")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text("Tools coming soon")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    
                    Spacer()
                }
                .padding(14)
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
    }
    
    private func saveSettings() {
        defaultSettings.defaultSystemPrompt = systemPrompt
        defaultSettings.systemPromptEnabled = systemPromptEnabled
        defaultSettings.autoGenerateTitle = autoGenerateTitle
        if let model = selectedDefaultModel {
            defaultSettings.defaultModelId = model.modelId
        }
    }
}

// MARK: - Default Model Picker Sheet

/// A separate model picker specifically for choosing the default model
/// This does NOT affect aiService.currentModel
struct DefaultModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedModel: StoreModel?
    
    @State private var modelStore = ModelStoreService.shared
    @State private var aiService = AIService.shared
    @State private var searchText = ""
    @State private var availableModels: [StoreModel] = []
    
    var filteredModels: [StoreModel] {
        let models = searchText.isEmpty ? availableModels : availableModels.filter { model in
            model.name.localizedCaseInsensitiveContains(searchText) ||
            model.provider.localizedCaseInsensitiveContains(searchText)
        }
        return models
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Models list
                        VStack(spacing: 0) {
                            ForEach(filteredModels) { model in
                                Button {
                                    selectedModel = model
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        // Icon
                                        ZStack {
                                            Circle()
                                                .fill(model.usesGradient ?
                                                    AnyShapeStyle(model.appleIntelligenceGradient.opacity(0.15)) :
                                                    AnyShapeStyle(model.accentColor.opacity(0.15))
                                                )
                                                .frame(width: 44, height: 44)
                                            
                                            if model.isSystemIcon {
                                                Image(systemName: model.iconName)
                                                    .font(.system(size: 18, weight: .medium))
                                                    .foregroundStyle(model.usesGradient ?
                                                        AnyShapeStyle(model.appleIntelligenceGradient) :
                                                        AnyShapeStyle(model.accentColor)
                                                    )
                                            } else if model.isTemplateIcon {
                                                Image(model.iconName)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 24, height: 24)
                                                    .foregroundStyle(model.usesGradient ?
                                                        AnyShapeStyle(model.appleIntelligenceGradient) :
                                                        AnyShapeStyle(model.accentColor)
                                                    )
                                            } else {
                                                Image(model.iconName)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 24, height: 24)
                                            }
                                        }
                                        
                                        // Info
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(model.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppTheme.textPrimary)
                                            
                                            Text(model.provider)
                                                .font(.system(size: 14))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        // Selection indicator
                                        if selectedModel?.id == model.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                    }
                                    .padding(14)
                                }
                                .buttonStyle(.plain)
                                
                                if model.id != filteredModels.last?.id {
                                    Divider()
                                        .padding(.horizontal, 14)
                                }
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(AppTheme.cardBackground)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Default Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
            .task {
                await loadAvailableModels()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func loadAvailableModels() async {
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
}

#Preview {
    DefaultChatSettingsSheet()
}
