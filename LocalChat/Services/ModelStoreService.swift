//
//  ModelStoreService.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation
import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

/// Service for fetching and managing AI models from Firestore
/// Falls back to bundled models when offline or Firestore unavailable
@Observable
@MainActor
final class ModelStoreService {
    static let shared = ModelStoreService()
    
    // MARK: - State
    
    private(set) var models: [StoreModel] = []
    private(set) var openRouterModels: [StoreModel] = []
    private(set) var featuredModels: [StoreModel] = []
    private(set) var isLoading = false
    private(set) var lastError: Error?
    private(set) var lastUpdated: Date?
    
    // Custom endpoints stored locally
    private(set) var customEndpoints: [CustomEndpointModel] = []
    
    // Firestore collection name
    private let collectionName = "models"
    
    // Library: user-selected models that appear in the model picker
    private(set) var libraryModelIds: Set<String> = []
    
    // UserDefaults keys
    private let cachedModelsKey = "cachedStoreModels"
    private let cachedOpenRouterModelsKey = "cachedOpenRouterModels"
    private let customEndpointsKey = "customEndpoints"
    private let lastUpdatedKey = "modelsLastUpdated"
    private let libraryModelIdsKey = "libraryModelIds"
    
    /// The Apple Intelligence model ID that is always in the library
    static let appleIntelligenceId = "apple-foundation-model"
    
    private init() {
        loadCachedModels()
        loadCachedOpenRouterModels()
        loadCustomEndpoints()
        loadLibrary()
    }
    
    // MARK: - Public Methods
    
    /// Fetch models from Firestore and OpenRouter
    func fetchModels() async {
        isLoading = true
        lastError = nil
        
        do {
            #if canImport(FirebaseFirestore)
            let fetchedModels = try await fetchFromFirestore()
            models = fetchedModels
            featuredModels = fetchedModels.filter { $0.isFeatured }
            lastUpdated = Date()
            cacheModels(fetchedModels)
            #else
            // Use sample models when Firebase is not available
            models = StoreModel.sampleModels
            featuredModels = models.filter { $0.isFeatured }
            lastUpdated = Date()
            #endif
            
            // Also fetch OpenRouter models if API key is available
            await fetchOpenRouterModels()
        } catch {
            lastError = error
            // Fall back to cached or sample models
            if models.isEmpty {
                models = StoreModel.sampleModels
                featuredModels = models.filter { $0.isFeatured }
            }
        }
        
        isLoading = false
    }
    
    /// Fetch models from OpenRouter API
    func fetchOpenRouterModels() async {
        guard await AIService.shared.hasAPIKey(for: .openRouter) else {
            openRouterModels = []
            return
        }
        
        do {
            guard let apiKey = try? await KeychainService.shared.getAPIKey(for: .openRouter) else {
                return
            }
            
            let provider = OpenRouterProvider(apiKey: apiKey)
            let orModels = try await provider.fetchModels()
            
            // Convert to StoreModels
            openRouterModels = orModels.map { $0.toStoreModel() }
            
            // Cache for offline use
            cacheOpenRouterModels(openRouterModels)
            
            print("Fetched \(openRouterModels.count) models from OpenRouter")
        } catch {
            print("Failed to fetch OpenRouter models: \(error)")
            // Keep cached models if fetch fails
        }
    }
    
    /// Get all available models (Firestore + OpenRouter + custom)
    /// When OpenRouter models are available, use those instead of pre-configured sample models
    var allModels: [StoreModel] {
        var combined: [StoreModel] = []
        
        // If we have OpenRouter models, use those as the primary source
        // (they are dynamically fetched and more up-to-date)
        if !openRouterModels.isEmpty {
            // Use OpenRouter models as the main source
            combined.append(contentsOf: openRouterModels)
        } else {
            // Fall back to curated sample models when OpenRouter is not available
            combined.append(contentsOf: models)
        }
        
        // Only include Apple Intelligence (on-device) model if it's fully available and enabled
        // since it's not fetched from OpenRouter
        if FoundationModelsProvider.isAppleIntelligenceAvailable {
            if let appleModel = models.first(where: { $0.providerType == .foundationModels }) {
                if !combined.contains(where: { $0.id == appleModel.id }) {
                    combined.append(appleModel)
                }
            }
        }
        
        // Always include Perplexity models from sample list if user has Perplexity configured
        // since those use direct Perplexity API, not OpenRouter
        let perplexityModels = models.filter { $0.providerType == .perplexity }
        for perplexityModel in perplexityModels {
            if !combined.contains(where: { $0.id == perplexityModel.id }) {
                combined.append(perplexityModel)
            }
        }
        
        // Add custom endpoints
        combined.append(contentsOf: customEndpoints.map { $0.toStoreModel() })
        
        return combined
    }
    
    /// Get models filtered by category
    func models(for category: StoreModel.ModelCategory) -> [StoreModel] {
        allModels.filter { $0.category == category }
    }
    
    /// Get models filtered by provider
    func models(for providerType: AIProviderType) -> [StoreModel] {
        allModels.filter { $0.providerType == providerType }
    }
    
    /// Search models by name or description
    func searchModels(_ query: String) -> [StoreModel] {
        guard !query.isEmpty else { return allModels }
        let lowercasedQuery = query.lowercased()
        return allModels.filter { model in
            model.name.lowercased().contains(lowercasedQuery) ||
            model.description.lowercased().contains(lowercasedQuery) ||
            model.provider.lowercased().contains(lowercasedQuery) ||
            model.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }
    
    /// Get a specific model by ID
    func model(byId id: String) -> StoreModel? {
        allModels.first { $0.id == id }
    }
    
    // MARK: - Custom Endpoint Management
    
    /// Add a custom endpoint
    func addCustomEndpoint(_ endpoint: CustomEndpointModel) {
        customEndpoints.append(endpoint)
        saveCustomEndpoints()
    }
    
    /// Update a custom endpoint
    func updateCustomEndpoint(_ endpoint: CustomEndpointModel) {
        if let index = customEndpoints.firstIndex(where: { $0.id == endpoint.id }) {
            customEndpoints[index] = endpoint
            saveCustomEndpoints()
        }
    }
    
    /// Remove a custom endpoint
    func removeCustomEndpoint(id: UUID) {
        customEndpoints.removeAll { $0.id == id }
        saveCustomEndpoints()
    }
    
    /// Get a custom endpoint by ID
    func customEndpoint(byId id: UUID) -> CustomEndpointModel? {
        customEndpoints.first { $0.id == id }
    }
    
    // MARK: - Library Management
    
    /// Whether a model is in the user's library
    func isInLibrary(_ modelId: String) -> Bool {
        modelId == Self.appleIntelligenceId || libraryModelIds.contains(modelId)
    }
    
    /// Add a model to the user's library
    func addToLibrary(_ modelId: String) {
        libraryModelIds.insert(modelId)
        saveLibrary()
    }
    
    /// Remove a model from the user's library (Apple Intelligence cannot be removed)
    func removeFromLibrary(_ modelId: String) {
        guard modelId != Self.appleIntelligenceId else { return }
        libraryModelIds.remove(modelId)
        saveLibrary()
    }
    
    /// Toggle a model's library membership
    func toggleLibrary(_ modelId: String) {
        if isInLibrary(modelId) {
            removeFromLibrary(modelId)
        } else {
            addToLibrary(modelId)
        }
    }
    
    /// Models currently in the user's library
    var libraryModels: [StoreModel] {
        allModels.filter { isInLibrary($0.id) }
    }
    
    private func saveLibrary() {
        let array = Array(libraryModelIds)
        UserDefaults.standard.set(array, forKey: libraryModelIdsKey)
    }
    
    private func loadLibrary() {
        if let array = UserDefaults.standard.stringArray(forKey: libraryModelIdsKey) {
            libraryModelIds = Set(array)
        }
        // Apple Intelligence is always in the library
        if FoundationModelsProvider.isAppleIntelligenceAvailable {
            libraryModelIds.insert(Self.appleIntelligenceId)
        }
    }
    
    // MARK: - Firestore Integration
    
    #if canImport(FirebaseFirestore)
    private func fetchFromFirestore() async throws -> [StoreModel] {
        let db = Firestore.firestore()
        let snapshot = try await db.collection(collectionName)
            .whereField("is_available", isEqualTo: true)
            .order(by: "is_featured", descending: true)
            .order(by: "name")
            .getDocuments()
        
        return try snapshot.documents.compactMap { document in
            try document.data(as: StoreModel.self)
        }
    }
    
    /// Listen for real-time updates
    func startListening() {
        let db = Firestore.firestore()
        db.collection(collectionName)
            .whereField("is_available", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    Task { @MainActor in
                        self.lastError = error
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                Task { @MainActor in
                    do {
                        let fetchedModels = try documents.compactMap { document in
                            try document.data(as: StoreModel.self)
                        }
                        self.models = fetchedModels
                        self.featuredModels = fetchedModels.filter { $0.isFeatured }
                        self.lastUpdated = Date()
                        self.cacheModels(fetchedModels)
                    } catch {
                        self.lastError = error
                    }
                }
            }
    }
    #endif
    
    // MARK: - Caching
    
    private func cacheModels(_ models: [StoreModel]) {
        do {
            let data = try JSONEncoder().encode(models)
            UserDefaults.standard.set(data, forKey: cachedModelsKey)
            UserDefaults.standard.set(Date(), forKey: lastUpdatedKey)
        } catch {
            print("Failed to cache models: \(error)")
        }
    }
    
    private func loadCachedModels() {
        guard let data = UserDefaults.standard.data(forKey: cachedModelsKey) else {
            // Load sample models as fallback
            models = StoreModel.sampleModels
            featuredModels = models.filter { $0.isFeatured }
            return
        }
        
        do {
            models = try JSONDecoder().decode([StoreModel].self, from: data)
            featuredModels = models.filter { $0.isFeatured }
            lastUpdated = UserDefaults.standard.object(forKey: lastUpdatedKey) as? Date
        } catch {
            // Load sample models as fallback
            models = StoreModel.sampleModels
            featuredModels = models.filter { $0.isFeatured }
        }
    }
    
    private func cacheOpenRouterModels(_ models: [StoreModel]) {
        do {
            let data = try JSONEncoder().encode(models)
            UserDefaults.standard.set(data, forKey: cachedOpenRouterModelsKey)
        } catch {
            print("Failed to cache OpenRouter models: \(error)")
        }
    }
    
    private func loadCachedOpenRouterModels() {
        guard let data = UserDefaults.standard.data(forKey: cachedOpenRouterModelsKey) else {
            return
        }
        
        do {
            openRouterModels = try JSONDecoder().decode([StoreModel].self, from: data)
        } catch {
            print("Failed to load cached OpenRouter models: \(error)")
        }
    }
    
    private func saveCustomEndpoints() {
        do {
            let data = try JSONEncoder().encode(customEndpoints)
            UserDefaults.standard.set(data, forKey: customEndpointsKey)
        } catch {
            print("Failed to save custom endpoints: \(error)")
        }
    }
    
    private func loadCustomEndpoints() {
        guard let data = UserDefaults.standard.data(forKey: customEndpointsKey) else {
            return
        }
        
        do {
            customEndpoints = try JSONDecoder().decode([CustomEndpointModel].self, from: data)
        } catch {
            print("Failed to load custom endpoints: \(error)")
        }
    }
}

// MARK: - Model Grouping Helpers

extension ModelStoreService {
    /// Group models by provider
    var modelsByProvider: [String: [StoreModel]] {
        Dictionary(grouping: allModels) { $0.provider }
    }
    
    /// Group models by category
    var modelsByCategory: [StoreModel.ModelCategory: [StoreModel]] {
        Dictionary(grouping: allModels) { $0.category }
    }
    
    /// Get unique categories with models
    var availableCategories: [StoreModel.ModelCategory] {
        Array(Set(allModels.map { $0.category })).sorted { $0.rawValue < $1.rawValue }
    }
    
    /// Get unique providers
    var availableProviders: [String] {
        Array(Set(allModels.map { $0.provider })).sorted()
    }
    
    /// Get new models (added in last 7 days)
    var newModels: [StoreModel] {
        allModels.filter { $0.isNew }
    }
}
