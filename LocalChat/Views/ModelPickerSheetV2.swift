//
//  ModelPickerSheetV2.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI

/// Updated model picker sheet that uses the new StoreModel and AIService
struct ModelPickerSheetV2: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var aiService = AIService.shared
    @State private var modelStore = ModelStoreService.shared
    @State private var searchText = ""
    @State private var availableModels: [StoreModel] = []
    
    @Namespace private var namespace
    
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
                        modelsListSection
                        
                        // Get more models
                        getMoreModelsButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Choose Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(aiService.currentModel.accentColor)
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
            .task {
                await loadAvailableModels()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Load Available Models
    
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
    
    // MARK: - Models List Section
    
    private var modelsListSection: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 0) {
                ForEach(filteredModels) { model in
                    ModelPickerRow(
                        model: model,
                        isSelected: aiService.currentModel.id == model.id,
                        namespace: namespace
                    ) {
                        selectModel(model)
                    }
                    
                    if model.id != filteredModels.last?.id {
                        Divider()
                            .padding(.horizontal, 14)
                    }
                }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Get More Models Button
    
    private var getMoreModelsButton: some View {
        Button {
            // Dismiss sheet first
            dismiss()
            // Wait for sheet dismiss animation to complete, then navigate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: NSNotification.Name("NavigateToModelStore"), object: nil)
            }
        } label: {
            HStack {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18))
                
                Text("Get More Models")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(aiService.currentModel.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    
    private func selectModel(_ model: StoreModel) {
        aiService.setCurrentModel(model, updateDefault: false)
        dismiss()
    }
}

// MARK: - Model Picker Row

struct ModelPickerRow: View {
    let model: StoreModel
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    @State private var aiService = AIService.shared
    
    var body: some View {
        Button(action: action) {
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
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(aiService.currentModel.accentColor)
                }
            }
            .padding(14)
            .glassEffectID("model_\(model.id)", in: namespace)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModelPickerSheetV2()
}
