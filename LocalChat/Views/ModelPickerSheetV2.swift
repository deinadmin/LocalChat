//
//  ModelPickerSheetV2.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI

/// Updated model picker sheet that uses the new StoreModel and AIService
struct ModelPickerSheetV2: View {
    /// Matches half of the 44pt model icon circles.
    private let rowCornerRadius: CGFloat = 22
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var aiService = AIService.shared
    @State private var modelStore = ModelStoreService.shared
    @State private var searchText = ""
    @State private var availableModels: [StoreModel] = []
    @State private var modelSelectionHapticTick = 0
    
    /// Ready library models, plus the active model first when it isn’t in the library list.
    private var pickerModels: [StoreModel] {
        let current = aiService.currentModel
        if availableModels.contains(where: { $0.id == current.id }) {
            return availableModels
        }
        return [current] + availableModels
    }
    
    private var filteredModels: [StoreModel] {
        let matchesSearch: (StoreModel) -> Bool = { model in
            model.name.localizedCaseInsensitiveContains(searchText) ||
                model.provider.localizedCaseInsensitiveContains(searchText)
        }
        
        if searchText.isEmpty {
            return pickerModels
        }
        
        let current = aiService.currentModel
        let orphanNotInLibrary = !availableModels.contains(where: { $0.id == current.id })
        let filtered = pickerModels.filter(matchesSearch)
        
        if orphanNotInLibrary, !filtered.contains(where: { $0.id == current.id }) {
            return [current] + pickerModels.filter { $0.id != current.id }.filter(matchesSearch)
        }
        return filtered
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 4) {
                        modelsListSection
                        getMoreModelsButton
                    }
                    .padding(.horizontal, 12)
                }
            }
            .tint(.primary)
            .navigationTitle("Choose Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .searchable(text: $searchText, prompt: "Search models")
            .task {
                await loadAvailableModels()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: modelSelectionHapticTick)
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Load Available Models
    
    private func loadAvailableModels() async {
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
    
    // MARK: - Models List Section
    
    private var modelsListSection: some View {
        VStack(spacing: 4) {
            ForEach(filteredModels) { model in
                ModelPickerRow(
                    model: model,
                    isSelected: aiService.currentModel.id == model.id,
                    rowCornerRadius: rowCornerRadius
                ) {
                    selectModel(model)
                }
            }
        }
    }
    
    // MARK: - Get More Models Button
    
    private var getMoreModelsButton: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: NSNotification.Name("NavigateToModelStore"), object: nil)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.cardBackground.opacity(0.65))
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.iconDefault)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Get More Models")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Browse the model store")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func selectModel(_ model: StoreModel) {
        modelSelectionHapticTick += 1
        aiService.setCurrentModel(model, updateDefault: false)
        dismiss()
    }
}

// MARK: - Model Picker Row

struct ModelPickerRow: View {
    let model: StoreModel
    let isSelected: Bool
    var rowCornerRadius: CGFloat = 22
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
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
                            .renderingMode(.template)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(model.usesGradient ?
                                AnyShapeStyle(model.appleIntelligenceGradient) :
                                AnyShapeStyle(model.accentColor)
                            )
                    } else {
                        Image(model.iconName)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text(model.provider)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.trailing, 6)
                }
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(AppTheme.cardBackground.opacity(0.65))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ModelPickerSheetV2()
}
