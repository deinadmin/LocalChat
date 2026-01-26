//
//  ModelPickerSheet.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import SwiftUI

struct ModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedModel: AIModel
    @State private var showAddModel = false
    @State private var showComingSoon = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Warm cream background
                AppTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Models list
                        modelsSection
                        
                        // Add model button
                        addModelButton
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
            .sheet(isPresented: $showAddModel) {
                AddModelSheet()
            }
            .alert("Coming Soon", isPresented: $showComingSoon) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("AI model integration is coming in v2! Stay tuned for exciting updates.")
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            SparkleIcon(size: 44)
            
            Text("Select AI Model")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text("Choose from available AI models")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.top, 8)
    }
    
    private var modelsSection: some View {
        VStack(spacing: 12) {
            ForEach(AIModel.mockModels) { model in
                ModelRowView(
                    model: model,
                    isSelected: selectedModel.id == model.id
                ) {
                    selectedModel = model
                    showComingSoon = true
                }
            }
        }
    }
    
    private var addModelButton: some View {
        Button {
            showAddModel = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                
                Text("Add Custom Model")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Model Row View

struct ModelRowView: View {
    let model: AIModel
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(model.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    modelIcon
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
                
                // Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isAvailable ? .green : .orange)
                        .frame(width: 6, height: 6)
                    
                    Text(model.isAvailable ? "Ready" : "Soon")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.accent, lineWidth: 2)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var modelIcon: some View {
        if model.isSystemIcon {
            Image(systemName: model.iconName)
                .font(.system(size: 18))
                .foregroundStyle(model.accentColor)
        } else if model.isTemplateIcon {
            Image(model.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(model.accentColor)
        } else {
            Image(model.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
}

#Preview {
    @Previewable @State var selectedModel = AIModel.defaultModel
    
    ModelPickerSheet(selectedModel: $selectedModel)
}
