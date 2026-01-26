//
//  ChatSettingsSheet.swift
//  LocalChat
//
//  Created by Carl Steen on 21.01.26.
//

import SwiftUI

/// Sheet for editing individual chat settings
struct ChatSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var chat: Chat
    
    @State private var title: String
    @State private var autoGenerateTitle: Bool
    @State private var systemPrompt: String
    @State private var systemPromptEnabled: Bool
    
    private let defaultSettings = DefaultChatSettings.shared
    
    /// Toggle tint - black in light mode, default iOS green in dark mode
    private var toggleTint: Color? {
        AppTheme.toggleTint(for: colorScheme)
    }
    
    init(chat: Chat) {
        self.chat = chat
        _title = State(initialValue: chat.title)
        _autoGenerateTitle = State(initialValue: chat.autoGenerateTitle)
        _systemPrompt = State(initialValue: chat.customSystemPrompt ?? DefaultChatSettings.shared.defaultSystemPrompt)
        _systemPromptEnabled = State(initialValue: chat.systemPromptEnabled)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
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
            .navigationTitle("Chat Settings")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Title")
            
            VStack(spacing: 0) {
                // Title text field
                HStack(spacing: 12) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 24)
                    
                    TextField("Chat title", text: $title)
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textPrimary)
                        .disabled(autoGenerateTitle)
                        .opacity(autoGenerateTitle ? 0.5 : 1)
                }
                .padding(14)
                
                Divider()
                    .padding(.horizontal, 14)
                
                // Auto-generate toggle
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
                            
                            Text("Automatically create a title based on conversation")
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
            sectionHeader("System Instructions")
            
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
                            
                            Text("Provide context and guidelines to the AI")
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
                            .frame(minHeight: 150, maxHeight: 250)
                        
                        HStack {
                            Text("Available placeholders: {MODEL_NAME} {DATE_AND_TIME}")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textTertiary)
                            
                            Spacer()
                            
                            if systemPrompt != DefaultChatSettings.builtInSystemPrompt {
                                Button("Reset to Default") {
                                    systemPrompt = DefaultChatSettings.builtInSystemPrompt
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                            }
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
            sectionHeader("Tools")
            
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
        chat.title = title
        chat.autoGenerateTitle = autoGenerateTitle
        chat.systemPromptEnabled = systemPromptEnabled
        
        // Only save custom prompt if it differs from default
        if systemPrompt != DefaultChatSettings.shared.defaultSystemPrompt {
            chat.customSystemPrompt = systemPrompt
        } else {
            chat.customSystemPrompt = nil
        }
    }
}

#Preview {
    ChatSettingsSheet(chat: Chat(title: "Test Chat"))
}
