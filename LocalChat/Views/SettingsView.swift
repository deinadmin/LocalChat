//
//  SettingsView.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI

struct SettingsView: View {
    @Binding var showSidebar: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var aiService = AIService.shared
    @State private var appearanceManager = AppearanceManager.shared
    @State private var showAPIKeySheet = false
    @State private var selectedProvider: AIProviderType?
    @State private var showDefaultChatSettings = false
    
    // API Key states
    @State private var openRouterKeyConfigured = false
    @State private var perplexityKeyConfigured = false
    @State private var customEndpointsCount = 0
    
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Current Model Section
                    currentModelSection
                    
                    // API Keys Section
                    apiKeysSection
                    
                    // Custom Endpoints Section
                    customEndpointsSection
                    
                    // Appearance Section
                    appearanceSection
                    
                    // About Section
                    aboutSection
                }
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .medium))
                }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: showSidebar)
            }
            
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .sheet(item: $selectedProvider) { provider in
            APIKeyEntrySheet(provider: provider) {
                Task {
                    await refreshAPIKeyStatus()
                }
            }
        }
        .sheet(isPresented: $showDefaultChatSettings) {
            DefaultChatSettingsSheet()
        }
        .task {
            await refreshAPIKeyStatus()
        }
    }
    
    // MARK: - Default Chat Settings Section
    
    private var currentModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Default Chat Settings")
            
            Button {
                showDefaultChatSettings = true
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
                        Text("New Chat Defaults")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text("\(aiService.currentModel.name) · System instructions")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
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
    
    // MARK: - API Keys Section
    
    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("API Keys")
            
            VStack(spacing: 0) {
                // OpenRouter
                apiKeyRow(
                    provider: .openRouter,
                    isConfigured: openRouterKeyConfigured
                )
                
                Divider()
                    .padding(.horizontal, 14)
                
                // Perplexity
                apiKeyRow(
                    provider: .perplexity,
                    isConfigured: perplexityKeyConfigured
                )
                
                Divider()
                    .padding(.horizontal, 14)
                
                // Foundation Models (Apple)
                HStack {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text("On-device, no API key needed")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Available")
                            .foregroundStyle(.green)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .padding(14)
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
    }
    
    private func apiKeyRow(provider: AIProviderType, isConfigured: Bool) -> some View {
        Button {
            selectedProvider = provider
        } label: {
            HStack {
                Image(systemName: provider.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text(isConfigured ? "API key configured" : "Tap to add API key")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                Spacer()
                
                if isConfigured {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Active")
                            .foregroundStyle(.green)
                    }
                    .font(.system(size: 12, weight: .medium))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Custom Endpoints Section
    
    private var customEndpointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Custom Endpoints")
            
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenAI-Compatible APIs")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text(customEndpointsCount > 0 ? "\(customEndpointsCount) endpoint(s) configured" : "Add your own API endpoints")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(14)
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
    }
    
    // MARK: - Appearance Section
    
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Appearance")
            
            VStack(spacing: 0) {
                HStack {
                    Label("Theme", systemImage: "paintbrush")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    // Theme picker with segmented-style buttons
                    HStack(spacing: 8) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appearanceManager.mode = mode
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: mode.iconName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(mode.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(appearanceManager.mode == mode ? AppTheme.accent.contrastingTextColor : AppTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background {
                                    if appearanceManager.mode == mode {
                                        Capsule()
                                            .fill(AppTheme.accent)
                                    } else {
                                        Capsule()
                                            .fill(AppTheme.background)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("About")
            
            VStack(spacing: 0) {
                HStack {
                    Label("Version", systemImage: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Text("2.0.0")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(14)
                
                Divider()
                    .padding(.horizontal, 14)
                
                HStack {
                    Label("Privacy", systemImage: "lock.shield")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Text("All data stored locally")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
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
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showSidebar.toggle()
        }
    }
    
    private func refreshAPIKeyStatus() async {
        openRouterKeyConfigured = await aiService.hasAPIKey(for: .openRouter)
        perplexityKeyConfigured = await aiService.hasAPIKey(for: .perplexity)
        customEndpointsCount = ModelStoreService.shared.customEndpoints.count
    }
}

// MARK: - API Key Entry Sheet

struct APIKeyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let provider: AIProviderType
    let onSave: () -> Void
    
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var aiService = AIService.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.cardBackground)
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: provider.iconName)
                                .font(.system(size: 36))
                                .foregroundStyle(AppTheme.accent)
                        }
                        
                        Text(provider.displayName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text("Enter your API key to use \(provider.displayName) models")
                            .font(.system(size: 15))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // API Key Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.textSecondary)
                            
                            SecureField("sk-or-...", text: $apiKey)
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
                    }
                    .padding(.horizontal, 20)
                    
                    // Help text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to get an API key:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Text(helpText(for: provider))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.cardBackground)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Save button
                    Button {
                        Task {
                            await saveAPIKey()
                        }
                    } label: {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(AppTheme.accent.contrastingTextColor)
                            }
                            Text(isValidating ? "Validating..." : "Save API Key")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent.contrastingTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .glassEffect(
                        apiKey.isEmpty ? .regular.tint(.gray) : .regular.tint(AppTheme.accent),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .disabled(apiKey.isEmpty || isValidating)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func helpText(for provider: AIProviderType) -> String {
        switch provider {
        case .openRouter:
            return "1. Visit openrouter.ai\n2. Sign in or create an account\n3. Go to Keys in your dashboard\n4. Create a new API key and paste it here"
        case .perplexity:
            return "1. Visit perplexity.ai/settings/api\n2. Sign in or create an account\n3. Generate a new API key\n4. Paste your key here"
        case .customEndpoint:
            return "Enter the API key provided by your custom endpoint provider."
        case .foundationModels:
            return "Apple Intelligence doesn't require an API key."
        case .mock:
            return "Demo mode doesn't require an API key."
        }
    }
    
    private func saveAPIKey() async {
        isValidating = true
        validationError = nil
        
        let isValid = await aiService.validateAPIKey(apiKey, for: provider)
        
        if isValid {
            do {
                try await aiService.setAPIKey(apiKey, for: provider)
                onSave()
                dismiss()
            } catch {
                validationError = error.localizedDescription
            }
        } else {
            validationError = "Invalid API key. Please check and try again."
        }
        
        isValidating = false
    }
}

#Preview {
    NavigationStack {
        SettingsView(showSidebar: .constant(false))
    }
}
