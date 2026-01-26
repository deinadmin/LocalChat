//
//  OpenRouterProvider.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation

/// OpenRouter API provider implementation
/// Supports 200+ models from various providers through a unified API
actor OpenRouterProvider: AIProvider {
    let providerType: AIProviderType = .openRouter
    private(set) var configuration: ProviderConfiguration
    
    private let baseURL = "https://openrouter.ai/api/v1"
    private var currentTask: Task<Void, Never>?
    
    var isConfigured: Bool {
        configuration.apiKey != nil && !(configuration.apiKey?.isEmpty ?? true)
    }
    
    init(configuration: ProviderConfiguration) {
        self.configuration = configuration
    }
    
    convenience init(apiKey: String?) {
        self.init(configuration: ProviderConfiguration(
            providerType: .openRouter,
            apiKey: apiKey
        ))
    }
    
    // MARK: - Configuration
    
    func updateAPIKey(_ apiKey: String?) {
        configuration = ProviderConfiguration(
            providerType: .openRouter,
            apiKey: apiKey,
            temperature: configuration.temperature,
            maxTokens: configuration.maxTokens
        )
    }
    
    // MARK: - API Methods
    
    func streamMessage(
        messages: [ChatMessage],
        model: StoreModel,
        onUpdate: @escaping @Sendable (StreamingUpdate) async -> Void
    ) async throws {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LocalChat/2.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("LocalChat", forHTTPHeaderField: "X-Title")
        
        // Check if model supports reasoning (Gemini, Claude, GPT-5, Grok reasoning models)
        let supportsReasoning = model.capabilities.contains(.reasoning)
        
        let body = OpenRouterRequest(
            model: model.modelId,
            messages: messages.map { OpenRouterMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            temperature: configuration.temperature,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens,
            reasoning: supportsReasoning ? OpenRouterReasoningConfig(effort: "medium") : nil
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        try handleHTTPStatus(httpResponse)
        
        var fullContent = ""
        var fullReasoning = ""
        var isCurrentlyReasoning = false
        var reasoningHasCompleted = false
        
        for try await line in bytes.lines {
            // Check for cancellation
            try Task.checkCancellation()
            
            // Parse SSE data
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            
            if data == "[DONE]" { break }
            
            guard let jsonData = data.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: jsonData),
                  let choice = chunk.choices.first else {
                continue
            }
            
            // Handle reasoning_details from the streaming response
            if let reasoningDetails = choice.delta?.reasoning_details {
                for detail in reasoningDetails {
                    // Extract text from reasoning details
                    if let text = detail.text {
                        fullReasoning += text
                        isCurrentlyReasoning = true
                    }
                    // Handle summary type
                    if let summary = detail.summary {
                        fullReasoning += summary
                        isCurrentlyReasoning = true
                    }
                }
            }
            
            // Handle regular content
            if let content = choice.delta?.content {
                // If we were reasoning and now have content, reasoning is complete
                if isCurrentlyReasoning && !content.isEmpty {
                    reasoningHasCompleted = true
                    isCurrentlyReasoning = false
                }
                fullContent += content
            }
            
            // Also check for 'reasoning' field directly (non-streaming format sometimes appears in stream)
            if let reasoning = choice.delta?.reasoning {
                fullReasoning += reasoning
                isCurrentlyReasoning = true
            }
            
            // Send update
            let update = StreamingUpdate(
                content: fullContent,
                reasoning: fullReasoning.isEmpty ? nil : fullReasoning,
                isReasoning: isCurrentlyReasoning,
                reasoningComplete: reasoningHasCompleted
            )
            await onUpdate(update)
        }
        
        // Final update to ensure reasoning is marked complete if we had any
        if !fullReasoning.isEmpty && !reasoningHasCompleted {
            let update = StreamingUpdate(
                content: fullContent,
                reasoning: fullReasoning,
                isReasoning: false,
                reasoningComplete: true
            )
            await onUpdate(update)
        }
    }
    
    func sendMessage(
        messages: [ChatMessage],
        model: StoreModel
    ) async throws -> String {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LocalChat/2.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("LocalChat", forHTTPHeaderField: "X-Title")
        
        let body = OpenRouterRequest(
            model: model.modelId,
            messages: messages.map { OpenRouterMessage(role: $0.role.rawValue, content: $0.content) },
            stream: false,
            temperature: configuration.temperature,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens,
            reasoning: nil
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        try handleHTTPStatus(httpResponse)
        
        let result = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        
        guard let content = result.choices.first?.message.content else {
            throw AIProviderError.invalidResponse
        }
        
        return content
    }
    
    func validateConfiguration() async throws -> Bool {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            return false
        }
        
        // Use the dedicated /key endpoint for API key validation
        // This endpoint returns 401 for invalid keys and 200 with key data for valid keys
        let url = URL(string: "\(baseURL)/key")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            
            // 401 = invalid/expired key
            if httpResponse.statusCode == 401 {
                return false
            }
            
            // For other non-2xx codes, consider it invalid
            guard (200...299).contains(httpResponse.statusCode) else {
                return false
            }
            
            // Verify we get valid key data back (has a "data" field with "label")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let keyData = json["data"] as? [String: Any],
               keyData["label"] != nil {
                return true
            }
            
            return false
        } catch {
            // Network error or other failure
            return false
        }
    }
    
    /// Fetch all available models from OpenRouter
    func fetchModels() async throws -> [OpenRouterModel] {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        
        let url = URL(string: "\(baseURL)/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        
        try handleHTTPStatus(httpResponse)
        
        let modelsResponse = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return modelsResponse.data
    }
    
    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - Helpers
    
    private func handleHTTPStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw AIProviderError.invalidAPIKey
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
            throw AIProviderError.rateLimited(retryAfter: retryAfter)
        case 400...499:
            throw AIProviderError.serverError(statusCode: response.statusCode, message: "Client error")
        case 500...599:
            throw AIProviderError.serverError(statusCode: response.statusCode, message: "Server error")
        default:
            throw AIProviderError.serverError(statusCode: response.statusCode, message: nil)
        }
    }
}

// MARK: - Request/Response Types

private struct OpenRouterRequest: Encodable {
    let model: String
    let messages: [OpenRouterMessage]
    let stream: Bool
    let temperature: Double?
    let max_tokens: Int?
    let reasoning: OpenRouterReasoningConfig?
}

/// Configuration for reasoning tokens in OpenRouter requests
private struct OpenRouterReasoningConfig: Encodable {
    /// Reasoning effort level: "xhigh", "high", "medium", "low", "minimal", "none"
    let effort: String?
    /// Maximum tokens for reasoning (alternative to effort)
    let max_tokens: Int?
    /// Whether to exclude reasoning from response
    let exclude: Bool?
    
    init(effort: String? = nil, max_tokens: Int? = nil, exclude: Bool? = nil) {
        self.effort = effort
        self.max_tokens = max_tokens
        self.exclude = exclude
    }
}

private struct OpenRouterMessage: Codable {
    let role: String
    let content: String
}

private struct OpenRouterResponse: Decodable {
    let choices: [OpenRouterChoice]
}

private struct OpenRouterChoice: Decodable {
    let message: OpenRouterResponseMessage
}

private struct OpenRouterResponseMessage: Decodable {
    let role: String?
    let content: String?
    let reasoning: String?
    let reasoning_details: [OpenRouterReasoningDetail]?
}

private struct OpenRouterStreamChunk: Decodable {
    let choices: [OpenRouterStreamChoice]
}

private struct OpenRouterStreamChoice: Decodable {
    let delta: OpenRouterDelta?
}

private struct OpenRouterDelta: Decodable {
    let content: String?
    let reasoning: String?
    let reasoning_details: [OpenRouterReasoningDetail]?
}

/// Represents a reasoning detail in OpenRouter responses
/// Supports multiple types: reasoning.text, reasoning.summary, reasoning.encrypted
private struct OpenRouterReasoningDetail: Decodable {
    let type: String?
    let text: String?
    let summary: String?
    let data: String? // For encrypted reasoning
    let id: String?
    let format: String?
    let index: Int?
}

// MARK: - Models API Response Types

struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

struct OpenRouterModel: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let context_length: Int?
    let pricing: OpenRouterPricing?
    let architecture: OpenRouterArchitecture?
    let top_provider: OpenRouterTopProvider?
    
    struct OpenRouterPricing: Decodable {
        let prompt: String?
        let completion: String?
    }
    
    struct OpenRouterArchitecture: Decodable {
        let input_modalities: [String]?
        let output_modalities: [String]?
    }
    
    struct OpenRouterTopProvider: Decodable {
        let context_length: Int?
        let max_completion_tokens: Int?
    }
    
    /// Convert to StoreModel for unified handling
    func toStoreModel() -> StoreModel {
        // Parse pricing (comes as string like "0.000001" per token)
        let inputPrice = pricing?.prompt.flatMap { Double($0) }.map { $0 * 1_000_000 }
        let outputPrice = pricing?.completion.flatMap { Double($0) }.map { $0 * 1_000_000 }
        
        // Determine context length
        let contextLen = context_length ?? top_provider?.context_length ?? 8192
        let maxOutput = top_provider?.max_completion_tokens ?? 4096
        
        // Determine input modalities
        var inputMods: [StoreModel.Modality] = [.text]
        if let mods = architecture?.input_modalities {
            if mods.contains("image") { inputMods.append(.image) }
            if mods.contains("audio") { inputMods.append(.audio) }
            if mods.contains("video") { inputMods.append(.video) }
            if mods.contains("file") { inputMods.append(.file) }
        }
        
        // Extract provider from model ID (e.g., "anthropic/claude-3" -> "Anthropic")
        let provider = extractProvider(from: id)
        
        // Extract clean model title (remove publisher prefix like "OpenAI: " from name)
        let modelTitle = extractModelTitle(from: name)
        
        // Determine category, icon, and color based on provider and model name
        let (category, iconName, accentColor, isSystemIcon) = categorizeModel(id: id, name: name, provider: provider)
        
        return StoreModel(
            id: id,
            name: modelTitle,
            provider: provider,
            providerType: .openRouter,
            description: description ?? "Model available via OpenRouter",
            modelId: id,
            contextLength: contextLen,
            maxOutputTokens: maxOutput,
            inputModalities: inputMods,
            outputModalities: [.text],
            capabilities: determineCapabilities(name: name),
            supportsStreaming: true,
            supportsSystemMessage: true,
            supportsFunctionCalling: name.lowercased().contains("gpt") || name.lowercased().contains("claude"),
            inputPricePerMillion: inputPrice,
            outputPricePerMillion: outputPrice,
            iconName: iconName,
            isSystemIcon: isSystemIcon,
            accentColorHex: accentColor,
            category: category,
            tags: generateTags(name: name, id: id),
            isAvailable: true,
            isFeatured: isFeaturedModel(id: id),
            isNew: false,
            releaseDate: Date(),
            lastUpdated: Date(),
            requiresAPIKey: true,
            minimumIOSVersion: nil
        )
    }
    
    private func extractProvider(from modelId: String) -> String {
        let parts = modelId.split(separator: "/")
        guard let providerSlug = parts.first else { return "Unknown" }
        
        switch providerSlug {
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "google": return "Google"
        case "meta-llama": return "Meta"
        case "mistralai": return "Mistral"
        case "deepseek": return "DeepSeek"
        case "x-ai": return "xAI"
        case "cohere": return "Cohere"
        case "perplexity": return "Perplexity"
        case "nvidia": return "Nvidia"
        case "aion-labs": return "Aion Labs"
        case "minimax": return "Minimax"
        case "bytedance": return "ByteDance"
        case "qwen": return "Qwen"
        case "openrouter": return "OpenRouter"
        case "z-ai": return "Z.ai"
        default: return String(providerSlug).capitalized
        }
    }
    
    /// Extract clean model title by removing publisher prefix from name
    /// e.g., "OpenAI: GPT-5.2" -> "GPT-5.2"
    private func extractModelTitle(from name: String) -> String {
        // Common patterns: "Publisher: Model Name" or "Publisher/Model Name"
        if let colonRange = name.range(of: ": ") {
            return String(name[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return name
    }
    
    /// Categorize model and determine icon/color based on provider and model characteristics
    /// Returns (category, iconName, accentColorHex, isSystemIcon)
    private func categorizeModel(id: String, name: String, provider: String) -> (StoreModel.ModelCategory, String, String, Bool) {
        let lowerId = id.lowercased()
        let lowerName = name.lowercased()
        
        // First, determine the category based on model characteristics
        let category: StoreModel.ModelCategory
        if lowerId.contains("flash") || lowerName.contains("flash") || lowerName.contains("mini") || lowerName.contains("instant") {
            category = .fast
        } else if lowerId.contains("vision") || lowerName.contains("vision") {
            category = .vision
        } else if lowerId.contains("code") || lowerName.contains("code") || lowerName.contains("codex") {
            category = .coding
        } else if lowerId.contains("reasoning") || lowerId.contains("-r1") || lowerName.contains("think") || lowerId.contains("deepseek") {
            category = .reasoning
        } else {
            category = .flagship
        }
        
        // Determine icon and color based on provider (use asset catalog for known publishers)
        switch provider.lowercased() {
        // Providers with colored icons
        case "openai":
            return (category, "openai-icon", "#000000", false)
        case "anthropic":
            return (category, "claude-icon", "#D97757", false)
        case "google":
            return (category, "gemini-icon", "#000000", false)
        case "xai":
            return (category, "grok-icon", "#000000", false)
        case "perplexity":
            return (category, "perplexity-icon", "#22B8CD", false)
        case "deepseek":
            return (category, "deepseek-icon", "#000000", false)
        case "mistral":
            return (category, "mistral-icon", "#000000", false)
        case "nvidia":
            return (category, "nvidia-icon", "#000000", false)
        case "aion labs":
            return (category, "aion-labs-icon", "#000000", false)
        case "minimax":
            return (category, "minimax-icon", "#000000", false)
        case "bytedance":
            return (category, "bytedance-icon", "#000000", false)
        case "qwen":
            return (category, "qwen-icon", "#000000", false)
            
        // Providers with black/white template icons (like grok)
        case "openrouter":
            return (category, "openrouter-icon", "#000000", false)
        case "z.ai":
            return (category, "zai-icon", "#000000", false)
            
        default:
            // For other providers, use SF Symbols and determine color based on model family
            let (icon, color) = determineIconAndColorForUnknownProvider(id: lowerId, name: lowerName)
            return (category, icon, color, true)
        }
    }
    
    /// Determine icon and color for providers not in our known list
    private func determineIconAndColorForUnknownProvider(id: String, name: String) -> (String, String) {
        if id.contains("llama") || id.contains("meta") {
            return ("flame.fill", "#0467DF")
        } else if id.contains("cohere") {
            return ("waveform", "#D18EE2")
        } else if name.contains("vision") || id.contains("vision") {
            return ("eye.fill", "#8E44AD")
        } else if name.contains("code") || id.contains("code") {
            return ("chevron.left.forwardslash.chevron.right", "#27AE60")
        } else if name.contains("flash") || id.contains("flash") {
            return ("bolt.fill", "#4285F4")
        }
        return ("cpu", "#6C757D")
    }
    
    private func determineCapabilities(name: String) -> [StoreModel.Capability] {
        var caps: [StoreModel.Capability] = [.chat]
        let lower = name.lowercased()
        
        if lower.contains("code") || lower.contains("gpt") || lower.contains("claude") {
            caps.append(.codeGeneration)
        }
        if lower.contains("vision") || architecture?.input_modalities?.contains("image") == true {
            caps.append(.multimodal)
        }
        if lower.contains("reason") || lower.contains("think") || lower.contains("-r1") {
            caps.append(.reasoning)
        }
        if (context_length ?? 0) > 100_000 {
            caps.append(.longContext)
        }
        
        return caps
    }
    
    private func generateTags(name: String, id: String) -> [String] {
        var tags: [String] = []
        let lower = (name + id).lowercased()
        
        if lower.contains("free") { tags.append("free") }
        if lower.contains("preview") || lower.contains("beta") { tags.append("preview") }
        if lower.contains("turbo") || lower.contains("flash") { tags.append("fast") }
        if lower.contains("pro") || lower.contains("opus") { tags.append("premium") }
        
        return tags
    }
    
    private func isFeaturedModel(id: String) -> Bool {
        let featured = [
            "openai/gpt-5", "openai/gpt-4",
            "anthropic/claude-sonnet", "anthropic/claude-opus",
            "google/gemini-3", "google/gemini-2",
            "x-ai/grok-4", "x-ai/grok-3"
        ]
        return featured.contains { id.lowercased().contains($0) }
    }
}
