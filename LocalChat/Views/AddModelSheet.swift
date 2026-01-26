//
//  AddModelSheet.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import SwiftUI

struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var modelName = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var selectedProvider = "OpenAI Compatible"
    @State private var showComingSoon = false
    
    private let providers = [
        "OpenAI Compatible",
        "Anthropic",
        "Google AI",
        "Ollama (Local)",
        "LM Studio",
        "Custom"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Form
                        formSection
                        
                        // Submit
                        submitButton
                        
                        // Info
                        infoNote
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
            .alert("Coming Soon!", isPresented: $showComingSoon) {
                Button("Got it", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Custom model integration will be available in v2.")
            }
        }
        .presentationDetents([.large])
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.cardBackground)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.accent)
            }
            
            Text("Connect Your Model")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text("Add a custom AI model configuration")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.top, 8)
    }
    
    private var formSection: some View {
        VStack(spacing: 16) {
            // Provider picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                
                Menu {
                    ForEach(providers, id: \.self) { provider in
                        Button(provider) {
                            selectedProvider = provider
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedProvider)
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.cardBackground)
                    }
                }
            }
            
            // Model name
            formField(
                title: "Model Name",
                placeholder: "e.g., My Custom GPT",
                text: $modelName,
                icon: "textformat"
            )
            
            // API Endpoint
            formField(
                title: "API Endpoint",
                placeholder: "https://api.example.com/v1",
                text: $apiEndpoint,
                icon: "link"
            )
            
            // API Key
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textSecondary)
                    
                    SecureField("sk-...", text: $apiKey)
                        .font(.system(size: 16))
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardBackground)
                }
            }
        }
    }
    
    private func formField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textSecondary)
                
                TextField(placeholder, text: text)
                    .font(.system(size: 16))
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardBackground)
            }
        }
    }
    
    private var submitButton: some View {
        Button {
            showComingSoon = true
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                
                Text("Add Model")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.accent)
            }
        }
    }
    
    private var infoNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
            
            Text("API keys are stored securely on-device")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardBackground)
        }
    }
}

#Preview {
    AddModelSheet()
}
