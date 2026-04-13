//
//  ModelStoreView.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI

// MARK: - Unified Filter Type

/// Represents a filter option in the Model Store (category or provider)
enum ModelStoreFilter: Hashable {
    case all
    case library
    case category(StoreModel.ModelCategory)
    case provider(String)
    
    var title: String {
        switch self {
        case .all:
            return "All"
        case .library:
            return "Library"
        case .category(let category):
            return category.rawValue
        case .provider(let provider):
            return provider
        }
    }
    
    var iconName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .library:
            return "books.vertical"
        case .category(let category):
            return category.iconName
        case .provider(let provider):
            switch provider {
            case "Google": return "gemini-icon"
            case "OpenAI": return "openai-icon"
            case "Anthropic": return "claude-icon"
            case "Perplexity": return "perplexity-icon"
            default: return "cpu"
            }
        }
    }
    
    var isSystemIcon: Bool {
        switch self {
        case .all, .library, .category:
            return true
        case .provider:
            return false
        }
    }
    
    var isTemplateIcon: Bool {
        switch self {
        case .provider(let provider):
            return provider == "OpenAI"
        default:
            return false
        }
    }
    
    /// All filters in the desired order
    static var allFilters: [ModelStoreFilter] {
        [
            .all,
            .library,
            .category(.flagship),
            .category(.fast),
            .category(.reasoning),
            .provider("Google"),
            .provider("OpenAI"),
            .provider("Anthropic"),
            .provider("Perplexity"),
            .category(.local),
            .category(.free)
        ]
    }
}

struct ModelStoreView: View {
    @Binding var showSidebar: Bool
    var onStartChat: ((Chat) -> Void)?
    
    @State private var modelStore = ModelStoreService.shared
    @State private var searchText = ""
    @State private var selectedFilter: ModelStoreFilter = .all
    @State private var showModelDetail: StoreModel?
    @State private var showAddCustomEndpoint = false
    
    @Namespace private var namespace
    
    var filteredModels: [StoreModel] {
        var result = modelStore.allModels
        
        switch selectedFilter {
        case .all:
            break // No filtering
            
        case .library:
            result = modelStore.libraryModels
            
        case .category(let category):
            if category == .free {
                // Free category: Apple Intelligence + models with "(free)" in name or $0 pricing
                result = result.filter { model in
                    model.provider.lowercased() == "apple" ||
                    model.name.lowercased().contains("(free)") ||
                    ((model.inputPricePerMillion ?? 1) == 0 && (model.outputPricePerMillion ?? 1) == 0)
                }
            } else {
                result = result.filter { $0.category == category }
            }
            
        case .provider(let provider):
            result = result.filter { $0.provider == provider }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let searchQuery = searchText.lowercased()
            result = result.filter { model in
                model.name.lowercased().contains(searchQuery) ||
                model.description.lowercased().contains(searchQuery) ||
                model.provider.lowercased().contains(searchQuery) ||
                model.tags.contains { $0.lowercased().contains(searchQuery) }
            }
        }
        
        return result
    }
    
    /// Title for the current filter
    private var filterTitle: String {
        switch selectedFilter {
        case .all:
            return "All Models"
        case .library:
            return "Library"
        case .category(let category):
            return category.rawValue
        case .provider(let provider):
            return provider
        }
    }
    
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Featured models section
                    if searchText.isEmpty && selectedFilter == .all && !modelStore.featuredModels.isEmpty {
                        featuredSection
                    }
                    
                    // Filter pills (categories + providers)
                    filterPills
                    
                    // Models grid
                    modelsGrid
                }
                .padding(.bottom, 100)
            }
            .refreshable {
                await modelStore.fetchModels()
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
                Text("Model Store")
                    .font(.system(size: 17, weight: .semibold))
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddCustomEndpoint = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search models")
        .sheet(item: $showModelDetail) { model in
            ModelDetailSheet(model: model) { newChat in
                onStartChat?(newChat)
            }
        }
        .sheet(isPresented: $showAddCustomEndpoint) {
            AddModelSheet()
        }
        .task {
            // Always fetch models when the view appears to ensure OpenRouter models are loaded
            await modelStore.fetchModels()
        }
    }
    
    // MARK: - Featured Section
    
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Featured")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(modelStore.featuredModels) { model in
                        FeaturedModelCard(model: model, namespace: namespace)
                            .onTapGesture {
                                showModelDetail = model
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .scrollClipDisabled()
    }
    
    // MARK: - Filter Pills
    
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(ModelStoreFilter.allFilters, id: \.self) { filter in
                        FilterPill(
                            filter: filter,
                            isSelected: selectedFilter == filter,
                            namespace: namespace
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .scrollClipDisabled()
    }
    
    // MARK: - Models Grid
    
    private var modelsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(filterTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Text("(\(filteredModels.count))")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            LazyVStack(spacing: 12) {
                ForEach(filteredModels) { model in
                    ModelCardView(model: model)
                        .onTapGesture {
                            showModelDetail = model
                        }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showSidebar.toggle()
        }
    }
}

// MARK: - Featured Model Card

struct FeaturedModelCard: View {
    let model: StoreModel
    var namespace: Namespace.ID
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // Icon
                ZStack {
                    Circle()
                        .fill(model.usesGradient ? 
                            AnyShapeStyle(model.appleIntelligenceGradient.opacity(0.15)) : 
                            AnyShapeStyle(model.accentColor.opacity(0.15))
                        )
                        .frame(width: 48, height: 48)
                    
                    if model.isSystemIcon {
                        Image(systemName: model.iconName)
                            .font(.system(size: 20, weight: .medium))
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
                            .frame(width: 28, height: 28)
                            .foregroundStyle(model.usesGradient ? 
                                AnyShapeStyle(model.appleIntelligenceGradient) : 
                                AnyShapeStyle(model.accentColor)
                            )
                    } else {
                        Image(model.iconName)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                    }
                }
                
                Spacer()
                
                if model.isNew {
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(model.accentColor))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Text(model.provider)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            Text(model.description)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
            
            Spacer()
            
            HStack(spacing: 12) {
                Label(model.formattedContextLength, systemImage: "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
                
                if let pricing = model.formattedPricing {
                    Label(pricing, systemImage: "dollarsign.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
        .glassEffectID(model.id, in: namespace)
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let filter: ModelStoreFilter
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if filter.isSystemIcon {
                    Image(systemName: filter.iconName)
                        .font(.system(size: 12, weight: .medium))
                } else if filter.isTemplateIcon {
                    Image(filter.iconName)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                } else {
                    Image(filter.iconName)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                }
                
                Text(filter.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? AppTheme.accent.contrastingTextColor : AppTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .glassEffect(
            isSelected ? .regular.tint(AppTheme.accent) : .regular,
            in: Capsule()
        )
        .glassEffectID("filter_\(filter.title)", in: namespace)
    }
}

// MARK: - Model Card View

struct ModelCardView: View {
    let model: StoreModel
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(model.usesGradient ? 
                        AnyShapeStyle(model.appleIntelligenceGradient.opacity(0.15)) : 
                        AnyShapeStyle(model.accentColor.opacity(0.15))
                    )
                    .frame(width: 48, height: 48)
                
                if model.isSystemIcon {
                    Image(systemName: model.iconName)
                        .font(.system(size: 20, weight: .medium))
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
                        .frame(width: 28, height: 28)
                        .foregroundStyle(model.usesGradient ? 
                            AnyShapeStyle(model.appleIntelligenceGradient) : 
                            AnyShapeStyle(model.accentColor)
                        )
                } else {
                    Image(model.iconName)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    if model.isNew {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(model.provider)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                    
                    Text("•")
                        .foregroundStyle(AppTheme.textTertiary)
                    
                    Text(model.formattedContextLength + " context")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
            
            Spacer()
            
            // Provider indicator
            VStack(spacing: 4) {
                if model.providerType.isSystemIcon {
                    Image(systemName: model.providerType.iconName)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Image(model.providerType.iconName)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                if !model.requiresAPIKey {
                    Text("Free")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
            }
            
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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ModelStoreView(showSidebar: .constant(false))
    }
}
