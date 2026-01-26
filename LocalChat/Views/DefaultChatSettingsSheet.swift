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
    @State private var aiService = AIService.shared
    
    @State private var systemPrompt: String
    @State private var systemPromptEnabled: Bool
    @State private var autoGenerateTitle: Bool
    @State private var showModelPicker = false
    
    init() {
        let settings = DefaultChatSettings.shared
        _systemPrompt = State(initialValue: settings.defaultSystemPrompt)
        _systemPromptEnabled = State(initialValue: settings.systemPromptEnabled)
        _autoGenerateTitle = State(initialValue: settings.autoGenerateTitle)
    }
    
    /// Toggle tint - black in light mode, default iOS green in dark mode
    private var toggleTint: Color? {
        AppTheme.toggleTint(for: colorScheme)
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
            ModelPickerSheetV2()
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
                            .fill(aiService.currentModel.usesGradient ?
                                AnyShapeStyle(aiService.currentModel.appleIntelligenceGradient.opacity(0.15)) :
                                AnyShapeStyle(aiService.currentModel.accentColor.opacity(0.15))
                            )
                            .frame(width: 48, height: 48)
                        
                        if aiService.currentModel.isSystemIcon {
                            Image(systemName: aiService.currentModel.iconName)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(aiService.currentModel.usesGradient ?
                                    AnyShapeStyle(aiService.currentModel.appleIntelligenceGradient) :
                                    AnyShapeStyle(aiService.currentModel.accentColor)
                                )
                        } else if aiService.currentModel.isTemplateIcon {
                            Image(aiService.currentModel.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(aiService.currentModel.usesGradient ?
                                    AnyShapeStyle(aiService.currentModel.appleIntelligenceGradient) :
                                    AnyShapeStyle(aiService.currentModel.accentColor)
                                )
                        } else {
                            Image(aiService.currentModel.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(aiService.currentModel.name)
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
        defaultSettings.defaultModelId = aiService.currentModel.modelId
    }
}

#Preview {
    DefaultChatSettingsSheet()
}
