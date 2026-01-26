//
//  StoreModel.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation
import SwiftUI

// MARK: - Store Model (from Firestore/Local catalog)

/// A model available in the Model Store
/// This represents an AI model that can be fetched from Firestore or bundled locally
struct StoreModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let provider: String
    let providerType: AIProviderType
    let description: String
    let modelId: String // The actual model ID to send to the API (e.g., "anthropic/claude-3.5-sonnet")
    
    // Technical specs
    let contextLength: Int
    let maxOutputTokens: Int?
    let inputModalities: [Modality]
    let outputModalities: [Modality]
    
    // Capabilities
    let capabilities: [Capability]
    let supportsStreaming: Bool
    let supportsSystemMessage: Bool
    let supportsFunctionCalling: Bool
    
    // Pricing (per million tokens)
    let inputPricePerMillion: Double?
    let outputPricePerMillion: Double?
    
    // UI/Display
    let iconName: String
    let isSystemIcon: Bool
    let accentColorHex: String
    let category: ModelCategory
    let tags: [String]
    
    // Availability
    let isAvailable: Bool
    let isFeatured: Bool
    let isNew: Bool
    let releaseDate: Date?
    let lastUpdated: Date
    
    // Requirements
    let requiresAPIKey: Bool
    let minimumIOSVersion: String?
    
    // Computed properties
    var accentColor: Color {
        // Use asset catalog colors for known providers
        switch provider.lowercased() {
        case "anthropic":
            return Color("claude-color")
        case "google":
            return Color("gemini-color")
        case "perplexity":
            return Color("perplexity-color")
        case "apple":
            // Apple Intelligence uses rainbow gradient color
            return Color("apple-intelligence-color")
        case "openai":
            // OpenAI uses green color #16B28B
            return Color("openai-color")
        case "xai":
            return Color("grok-color")
        default:
            return Color(hex: accentColorHex) ?? .blue
        }
    }
    
    /// Rainbow gradient for Apple Intelligence
    var appleIntelligenceGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.4, blue: 0.6),   // Pink
                Color(red: 0.9, green: 0.3, blue: 0.9),   // Purple
                Color(red: 0.4, green: 0.5, blue: 1.0),   // Blue
                Color(red: 0.3, green: 0.8, blue: 0.9),   // Cyan
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Check if this model should use gradient (Apple Intelligence)
    var usesGradient: Bool {
        provider.lowercased() == "apple"
    }
    
    /// Icons that are template images (monochrome) and should use .primary foreground
    var isTemplateIcon: Bool {
        switch iconName {
        case "openai-icon", "grok-icon":
            return true
        default:
            return false
        }
    }
    
    var formattedContextLength: String {
        if contextLength >= 1_000_000 {
            return "\(contextLength / 1_000_000)M"
        } else if contextLength >= 1_000 {
            return "\(contextLength / 1_000)K"
        }
        return "\(contextLength)"
    }
    
    var formattedPricing: String? {
        guard let input = inputPricePerMillion, let output = outputPricePerMillion else {
            return nil
        }
        return "$\(String(format: "%.2f", input))/$\(String(format: "%.2f", output)) per 1M"
    }
    
    // MARK: - Nested Types
    
    enum Modality: String, Codable, Sendable {
        case text
        case image
        case audio
        case video
        case file
    }
    
    enum Capability: String, Codable, Sendable {
        case chat
        case completion
        case embedding
        case imageGeneration
        case codeGeneration
        case reasoning
        case webSearch
        case longContext
        case multimodal
        case functionCalling
        case jsonMode
    }
    
    enum ModelCategory: String, Codable, CaseIterable, Sendable {
        case flagship = "Flagship"
        case fast = "Fast"
        case reasoning = "Reasoning"
        case vision = "Vision"
        case coding = "Coding"
        case creative = "Creative"
        case local = "On-Device"
        case free = "Free"
        
        var iconName: String {
            switch self {
            case .flagship: return "star.fill"
            case .fast: return "bolt.fill"
            case .reasoning: return "brain.head.profile"
            case .vision: return "eye.fill"
            case .coding: return "chevron.left.forwardslash.chevron.right"
            case .creative: return "paintbrush.fill"
            case .local: return "iphone"
            case .free: return "gift.fill"
            }
        }
    }
    
    // MARK: - Coding Keys for Firestore compatibility
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case providerType = "provider_type"
        case description
        case modelId = "model_id"
        case contextLength = "context_length"
        case maxOutputTokens = "max_output_tokens"
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
        case capabilities
        case supportsStreaming = "supports_streaming"
        case supportsSystemMessage = "supports_system_message"
        case supportsFunctionCalling = "supports_function_calling"
        case inputPricePerMillion = "input_price_per_million"
        case outputPricePerMillion = "output_price_per_million"
        case iconName = "icon_name"
        case isSystemIcon = "is_system_icon"
        case accentColorHex = "accent_color_hex"
        case category
        case tags
        case isAvailable = "is_available"
        case isFeatured = "is_featured"
        case isNew = "is_new"
        case releaseDate = "release_date"
        case lastUpdated = "last_updated"
        case requiresAPIKey = "requires_api_key"
        case minimumIOSVersion = "minimum_ios_version"
    }
}

// MARK: - Custom Endpoint Model

/// A user-configured custom endpoint
struct CustomEndpointModel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var baseURL: String
    var modelId: String
    var apiKeyIdentifier: String // Reference to Keychain
    var provider: String
    var contextLength: Int
    var supportsStreaming: Bool
    var additionalHeaders: [String: String]?
    var createdAt: Date
    var lastUsed: Date?
    
    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        modelId: String,
        apiKeyIdentifier: String,
        provider: String = "Custom",
        contextLength: Int = 8192,
        supportsStreaming: Bool = true,
        additionalHeaders: [String: String]? = nil,
        createdAt: Date = Date(),
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.modelId = modelId
        self.apiKeyIdentifier = apiKeyIdentifier
        self.provider = provider
        self.contextLength = contextLength
        self.supportsStreaming = supportsStreaming
        self.additionalHeaders = additionalHeaders
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }
    
    /// Convert to StoreModel for unified handling
    func toStoreModel() -> StoreModel {
        StoreModel(
            id: id.uuidString,
            name: name,
            provider: provider,
            providerType: .customEndpoint,
            description: "Custom endpoint: \(baseURL)",
            modelId: modelId,
            contextLength: contextLength,
            maxOutputTokens: nil,
            inputModalities: [.text],
            outputModalities: [.text],
            capabilities: [.chat],
            supportsStreaming: supportsStreaming,
            supportsSystemMessage: true,
            supportsFunctionCalling: false,
            inputPricePerMillion: nil,
            outputPricePerMillion: nil,
            iconName: "server.rack",
            isSystemIcon: true,
            accentColorHex: "#8E8E93",
            category: .flagship,
            tags: ["custom"],
            isAvailable: true,
            isFeatured: false,
            isNew: false,
            releaseDate: createdAt,
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        )
    }
}

// MARK: - Sample Models for Development

extension StoreModel {
    /// A fallback model used when no default is set and no models are available
    static let fallbackModel = StoreModel(
        id: "fallback",
        name: "No Model Selected",
        provider: "Select a model",
        providerType: .openRouter,
        description: "Please select a model from the Model Store",
        modelId: "fallback",
        contextLength: 0,
        maxOutputTokens: 0,
        inputModalities: [.text],
        outputModalities: [.text],
        capabilities: [.chat],
        supportsStreaming: false,
        supportsSystemMessage: false,
        supportsFunctionCalling: false,
        inputPricePerMillion: nil,
        outputPricePerMillion: nil,
        iconName: "questionmark.circle",
        isSystemIcon: true,
        accentColorHex: "#8E8E93",
        category: .flagship,
        tags: [],
        isAvailable: false,
        isFeatured: false,
        isNew: false,
        releaseDate: Date(),
        lastUpdated: Date(),
        requiresAPIKey: false,
        minimumIOSVersion: nil
    )
    
    static let sampleModels: [StoreModel] = [
        // OpenRouter Models
        StoreModel(
            id: "gpt-5-2",
            name: "GPT-5.2",
            provider: "OpenAI",
            providerType: .openRouter,
            description: "OpenAI's most advanced model. Unprecedented reasoning and creative capabilities.",
            modelId: "openai/gpt-5.2",
            contextLength: 256_000,
            maxOutputTokens: 32768,
            inputModalities: [.text, .image, .audio],
            outputModalities: [.text],
            capabilities: [.chat, .reasoning, .codeGeneration, .multimodal, .functionCalling, .longContext],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 5.0,
            outputPricePerMillion: 15.0,
            iconName: "openai-icon",
            isSystemIcon: false,
            accentColorHex: "#000000",
            category: .flagship,
            tags: ["flagship", "reasoning", "multimodal"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "gpt-5-2-instant",
            name: "GPT-5.2 Instant",
            provider: "OpenAI",
            providerType: .openRouter,
            description: "OpenAI's fastest GPT-5.2 variant. Optimized for low-latency responses.",
            modelId: "openai/gpt-5.2-chat",
            contextLength: 256_000,
            maxOutputTokens: 16384,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            capabilities: [.chat, .codeGeneration, .multimodal, .functionCalling, .longContext],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 2.0,
            outputPricePerMillion: 8.0,
            iconName: "openai-icon",
            isSystemIcon: false,
            accentColorHex: "#000000",
            category: .fast,
            tags: ["fast", "multimodal"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "gemini-3-flash-preview",
            name: "Gemini 3 Flash Preview",
            provider: "Google",
            providerType: .openRouter,
            description: "Ultra-fast model from Google. Best-in-class speed with strong capabilities.",
            modelId: "google/gemini-3-flash-preview",
            contextLength: 2_000_000,
            maxOutputTokens: 16384,
            inputModalities: [.text, .image, .audio, .video],
            outputModalities: [.text],
            capabilities: [.chat, .multimodal, .longContext, .codeGeneration],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 0.15,
            outputPricePerMillion: 0.6,
            iconName: "gemini-icon",
            isSystemIcon: false,
            accentColorHex: "#000000",
            category: .fast,
            tags: ["fast", "multimodal", "long-context"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "gemini-3-pro-preview",
            name: "Gemini 3 Pro Preview",
            provider: "Google",
            providerType: .openRouter,
            description: "Google's flagship model. Advanced reasoning with massive context window.",
            modelId: "google/gemini-3-pro-preview",
            contextLength: 2_000_000,
            maxOutputTokens: 32768,
            inputModalities: [.text, .image, .audio, .video],
            outputModalities: [.text],
            capabilities: [.chat, .reasoning, .multimodal, .longContext, .codeGeneration, .functionCalling],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 2.5,
            outputPricePerMillion: 10.0,
            iconName: "gemini-icon",
            isSystemIcon: false,
            accentColorHex: "#000000",
            category: .flagship,
            tags: ["flagship", "reasoning", "multimodal"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "claude-sonnet-4-5",
            name: "Claude Sonnet 4.5",
            provider: "Anthropic",
            providerType: .openRouter,
            description: "Anthropic's balanced model. Excellent reasoning with fast responses.",
            modelId: "anthropic/claude-sonnet-4.5",
            contextLength: 400_000,
            maxOutputTokens: 16384,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            capabilities: [.chat, .reasoning, .codeGeneration, .multimodal, .longContext],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 3.0,
            outputPricePerMillion: 15.0,
            iconName: "claude-icon",
            isSystemIcon: false,
            accentColorHex: "#D97757",
            category: .flagship,
            tags: ["flagship", "reasoning", "coding"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "claude-opus-4-5",
            name: "Claude Opus 4.5",
            provider: "Anthropic",
            providerType: .openRouter,
            description: "Anthropic's most capable model. State-of-the-art reasoning and analysis.",
            modelId: "anthropic/claude-opus-4.5",
            contextLength: 400_000,
            maxOutputTokens: 32768,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            capabilities: [.chat, .reasoning, .codeGeneration, .multimodal, .longContext],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 15.0,
            outputPricePerMillion: 75.0,
            iconName: "claude-icon",
            isSystemIcon: false,
            accentColorHex: "#D97757",
            category: .flagship,
            tags: ["flagship", "reasoning", "premium"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "grok-4",
            name: "Grok 4",
            provider: "xAI",
            providerType: .openRouter,
            description: "xAI's flagship model. Real-time knowledge with witty personality.",
            modelId: "x-ai/grok-4",
            contextLength: 256_000,
            maxOutputTokens: 16384,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            capabilities: [.chat, .reasoning, .codeGeneration, .multimodal],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 5.0,
            outputPricePerMillion: 15.0,
            iconName: "grok-icon",
            isSystemIcon: false,
            accentColorHex: "#000000",
            category: .flagship,
            tags: ["flagship", "real-time", "witty"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "grok-4-fast",
            name: "Grok 4 Fast",
            provider: "xAI",
            providerType: .openRouter,
            description: "xAI's fastest model. Optimized for speed with witty personality.",
            modelId: "x-ai/grok-4-fast",
            contextLength: 256_000,
            maxOutputTokens: 16384,
            inputModalities: [.text, .image],
            outputModalities: [.text],
            capabilities: [.chat, .codeGeneration, .multimodal],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: true,
            inputPricePerMillion: 2.0,
            outputPricePerMillion: 8.0,
            iconName: "grok-icon",
            isSystemIcon: false,
            accentColorHex: "#000000",
            category: .fast,
            tags: ["fast", "real-time", "witty"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        
        // Apple Intelligence (On-device)
        StoreModel(
            id: "apple-foundation-model",
            name: "Apple Intelligence",
            provider: "Apple",
            providerType: .foundationModels,
            description: "On-device AI powered by Apple Silicon. Private and fast.",
            modelId: "apple/foundation-model",
            contextLength: 4096,
            maxOutputTokens: 2048,
            inputModalities: [.text],
            outputModalities: [.text],
            capabilities: [.chat],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: false,
            inputPricePerMillion: nil,
            outputPricePerMillion: nil,
            iconName: "apple.intelligence",
            isSystemIcon: true,
            accentColorHex: "#000000",
            category: .local,
            tags: ["on-device", "private", "free"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: false,
            minimumIOSVersion: "26.0"
        ),
        
        // Perplexity Models
        StoreModel(
            id: "sonar-pro",
            name: "Sonar Pro",
            provider: "Perplexity",
            providerType: .perplexity,
            description: "Advanced search-augmented model. Best for research and fact-finding with real-time web access.",
            modelId: "sonar-pro",
            contextLength: 200_000,
            maxOutputTokens: 8192,
            inputModalities: [.text],
            outputModalities: [.text],
            capabilities: [.chat, .webSearch, .reasoning, .longContext],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: false,
            inputPricePerMillion: 3.0,
            outputPricePerMillion: 15.0,
            iconName: "perplexity-icon",
            isSystemIcon: false,
            accentColorHex: "#22B8CD",
            category: .flagship,
            tags: ["search", "research", "real-time"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "sonar",
            name: "Sonar",
            provider: "Perplexity",
            providerType: .perplexity,
            description: "Fast search-augmented model. Quick answers with web access at lower cost.",
            modelId: "sonar",
            contextLength: 128_000,
            maxOutputTokens: 4096,
            inputModalities: [.text],
            outputModalities: [.text],
            capabilities: [.chat, .webSearch],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: false,
            inputPricePerMillion: 1.0,
            outputPricePerMillion: 1.0,
            iconName: "perplexity-icon",
            isSystemIcon: false,
            accentColorHex: "#22B8CD",
            category: .fast,
            tags: ["search", "fast", "affordable"],
            isAvailable: true,
            isFeatured: false,
            isNew: false,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        ),
        StoreModel(
            id: "sonar-reasoning-pro",
            name: "Sonar Reasoning Pro",
            provider: "Perplexity",
            providerType: .perplexity,
            description: "Advanced reasoning with web search. Extended thinking for complex research tasks.",
            modelId: "sonar-reasoning-pro",
            contextLength: 128_000,
            maxOutputTokens: 8192,
            inputModalities: [.text],
            outputModalities: [.text],
            capabilities: [.chat, .webSearch, .reasoning],
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: false,
            inputPricePerMillion: 2.0,
            outputPricePerMillion: 8.0,
            iconName: "perplexity-icon",
            isSystemIcon: false,
            accentColorHex: "#22B8CD",
            category: .reasoning,
            tags: ["reasoning", "search", "research"],
            isAvailable: true,
            isFeatured: true,
            isNew: true,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        )
    ]
    
    static let defaultModel = sampleModels[0]
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    /// Returns the appropriate contrasting text color (black or white) for this color
    var contrastingTextColor: Color {
        // Get UIColor to access RGB components
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate relative luminance using the WCAG formula
        // https://www.w3.org/TR/WCAG20/#relativeluminancedef
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        
        // Return white for dark colors, black for light colors
        // Threshold of 0.5 works well for most cases
        return luminance > 0.5 ? .black : .white
        #else
        return .white
        #endif
    }
}
