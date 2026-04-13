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
        // Default to no web search
        try await streamMessage(messages: messages, model: model, webSearchEnabled: false, onUpdate: onUpdate)
    }
    
    /// Stream a message with optional web search support
    func streamMessage(
        messages: [ChatMessage],
        model: StoreModel,
        webSearchEnabled: Bool,
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
        
        // Convert messages to OpenRouter format, handling multimodal content
        let openRouterMessages = messages.map { msg -> OpenRouterMessage in
            switch msg.content {
            case .text(let text):
                return OpenRouterMessage(role: msg.role.rawValue, content: .text(text))
            case .multipart(let parts):
                let openRouterParts: [OpenRouterContentPart] = parts.compactMap { part in
                    switch part {
                    case .text(let text):
                        return OpenRouterContentPart(type: "text", text: text)
                    case .imageURL(let url, _):
                        return OpenRouterContentPart(type: "image_url", image_url: OpenRouterImageURL(url: url))
                    case .imageData(let base64, let mimeType):
                        return OpenRouterContentPart(type: "image_url", image_url: OpenRouterImageURL(url: "data:\(mimeType);base64,\(base64)"))
                    case .file(let filename, let base64, let mimeType):
                        return OpenRouterContentPart(type: "file", file: OpenRouterFile(filename: filename, file_data: "data:\(mimeType);base64,\(base64)"))
                    }
                }
                return OpenRouterMessage(role: msg.role.rawValue, content: .parts(openRouterParts))
            }
        }
        
        // For web search, append :online to the model ID (simpler than plugins array)
        let effectiveModelId = webSearchEnabled ? "\(model.modelId):online" : model.modelId
        
        let body = OpenRouterRequest(
            model: effectiveModelId,
            messages: openRouterMessages,
            stream: true,
            temperature: configuration.temperature,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens,
            reasoning: supportsReasoning ? OpenRouterReasoningConfig(effort: "medium") : nil,
            plugins: nil
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
        var collectedCitations: [String] = [] // Collect unique citation URLs
        var isCurrentlySearchingWeb = webSearchEnabled // Start as true if web search is enabled
        var hasReceivedContent = false // Track if we've received any content
        
        // Send initial update to show "Searching the web..." indicator
        if webSearchEnabled {
            let initialUpdate = StreamingUpdate(
                content: "",
                reasoning: nil,
                isReasoning: false,
                reasoningComplete: false,
                citations: nil,
                isSearchingWeb: true
            )
            await onUpdate(initialUpdate)
        }
        
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
            
            // Collect citations from annotations (web search results)
            if let annotations = chunk.annotations {
                for annotation in annotations {
                    if let url = annotation.url, !url.isEmpty, !collectedCitations.contains(url) {
                        collectedCitations.append(url)
                    }
                    if let urlCitation = annotation.url_citation, let url = urlCitation.url, !url.isEmpty, !collectedCitations.contains(url) {
                        collectedCitations.append(url)
                    }
                }
            }
            
            // Also check for annotations in the delta
            if let deltaAnnotations = choice.delta?.annotations {
                for annotation in deltaAnnotations {
                    if let url = annotation.url, !url.isEmpty, !collectedCitations.contains(url) {
                        collectedCitations.append(url)
                    }
                    if let urlCitation = annotation.url_citation, let url = urlCitation.url, !url.isEmpty, !collectedCitations.contains(url) {
                        collectedCitations.append(url)
                    }
                }
            }
            
            // Handle reasoning - prefer reasoning_details over reasoning field
            // Only use one source to avoid duplication
            var gotReasoningFromDetails = false
            
            if let reasoningDetails = choice.delta?.reasoning_details {
                for detail in reasoningDetails {
                    // Extract text from reasoning details
                    if let text = detail.text, !text.isEmpty {
                        fullReasoning += text
                        isCurrentlyReasoning = true
                        gotReasoningFromDetails = true
                    }
                    // Handle summary type
                    if let summary = detail.summary, !summary.isEmpty {
                        fullReasoning += summary
                        isCurrentlyReasoning = true
                        gotReasoningFromDetails = true
                    }
                }
            }
            
            // Only use 'reasoning' field if we didn't get anything from reasoning_details
            // This prevents duplication when both fields contain the same content
            if !gotReasoningFromDetails, let reasoning = choice.delta?.reasoning, !reasoning.isEmpty {
                fullReasoning += reasoning
                isCurrentlyReasoning = true
            }
            
            // Handle regular content
            if let content = choice.delta?.content {
                // If we were reasoning and now have content, reasoning is complete
                if isCurrentlyReasoning && !content.isEmpty {
                    reasoningHasCompleted = true
                    isCurrentlyReasoning = false
                }
                // Once we receive content, we're no longer in web search phase
                if !content.isEmpty && isCurrentlySearchingWeb {
                    isCurrentlySearchingWeb = false
                    hasReceivedContent = true
                }
                fullContent += content
            }
            
            // Send update with citations and web search state
            let update = StreamingUpdate(
                content: fullContent,
                reasoning: fullReasoning.isEmpty ? nil : fullReasoning,
                isReasoning: isCurrentlyReasoning,
                reasoningComplete: reasoningHasCompleted,
                citations: collectedCitations.isEmpty ? nil : collectedCitations,
                isSearchingWeb: isCurrentlySearchingWeb
            )
            await onUpdate(update)
        }
        
        // Final update to ensure reasoning is marked complete if we had any
        if !fullReasoning.isEmpty && !reasoningHasCompleted {
            let update = StreamingUpdate(
                content: fullContent,
                reasoning: fullReasoning,
                isReasoning: false,
                reasoningComplete: true,
                citations: collectedCitations.isEmpty ? nil : collectedCitations,
                isSearchingWeb: false
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
        
        // Convert messages to OpenRouter format, handling multimodal content
        let openRouterMessages = messages.map { msg -> OpenRouterMessage in
            switch msg.content {
            case .text(let text):
                return OpenRouterMessage(role: msg.role.rawValue, content: .text(text))
            case .multipart(let parts):
                let openRouterParts: [OpenRouterContentPart] = parts.compactMap { part in
                    switch part {
                    case .text(let text):
                        return OpenRouterContentPart(type: "text", text: text)
                    case .imageURL(let url, _):
                        return OpenRouterContentPart(type: "image_url", image_url: OpenRouterImageURL(url: url))
                    case .imageData(let base64, let mimeType):
                        return OpenRouterContentPart(type: "image_url", image_url: OpenRouterImageURL(url: "data:\(mimeType);base64,\(base64)"))
                    case .file(let filename, let base64, let mimeType):
                        return OpenRouterContentPart(type: "file", file: OpenRouterFile(filename: filename, file_data: "data:\(mimeType);base64,\(base64)"))
                    }
                }
                return OpenRouterMessage(role: msg.role.rawValue, content: .parts(openRouterParts))
            }
        }
        
        let body = OpenRouterRequest(
            model: model.modelId,
            messages: openRouterMessages,
            stream: false,
            temperature: configuration.temperature,
            max_tokens: configuration.maxTokens ?? model.maxOutputTokens,
            reasoning: nil,
            plugins: nil
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
    let plugins: [OpenRouterPlugin]?
    
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, max_tokens, reasoning, plugins
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(max_tokens, forKey: .max_tokens)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(plugins, forKey: .plugins)
    }
}

/// Plugin configuration for OpenRouter requests (e.g., web search)
private struct OpenRouterPlugin: Encodable {
    let id: String
    let max_results: Int?
    let search_prompt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, max_results, search_prompt
    }
    
    init(id: String, max_results: Int? = nil, search_prompt: String? = nil) {
        self.id = id
        self.max_results = max_results
        self.search_prompt = search_prompt
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(max_results, forKey: .max_results)
        try container.encodeIfPresent(search_prompt, forKey: .search_prompt)
    }
    
    /// Create a web search plugin with default settings
    static func webSearch(maxResults: Int = 5) -> OpenRouterPlugin {
        OpenRouterPlugin(id: "web", max_results: maxResults)
    }
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

/// Message that supports both simple text and multimodal content
private struct OpenRouterMessage: Encodable {
    let role: String
    let content: OpenRouterMessageContent
    
    enum OpenRouterMessageContent: Encodable {
        case text(String)
        case parts([OpenRouterContentPart])
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }
}

/// Content part for multimodal messages (text, image, or file)
private struct OpenRouterContentPart: Encodable {
    let type: String
    let text: String?
    let image_url: OpenRouterImageURL?
    let file: OpenRouterFile?
    
    init(type: String, text: String? = nil, image_url: OpenRouterImageURL? = nil, file: OpenRouterFile? = nil) {
        self.type = type
        self.text = text
        self.image_url = image_url
        self.file = file
    }
}

/// Image URL structure for vision models
private struct OpenRouterImageURL: Encodable {
    let url: String
}

/// File structure for document attachments (PDFs, etc.)
private struct OpenRouterFile: Encodable {
    let filename: String
    let file_data: String // data:mime;base64,... or URL
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
    /// Web search annotations from the response
    let annotations: [OpenRouterAnnotation]?
}

private struct OpenRouterStreamChoice: Decodable {
    let delta: OpenRouterDelta?
}

private struct OpenRouterDelta: Decodable {
    let content: String?
    let reasoning: String?
    let reasoning_details: [OpenRouterReasoningDetail]?
    /// Annotations can also appear at the delta level
    let annotations: [OpenRouterAnnotation]?
}

/// Web search annotation containing citation sources
private struct OpenRouterAnnotation: Decodable {
    let type: String?
    let url: String?
    let title: String?
    /// For url_citation type
    let url_citation: OpenRouterURLCitation?
}

/// URL citation details from web search
private struct OpenRouterURLCitation: Decodable {
    let url: String?
    let title: String?
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
        let (category, iconName, accentColor, isSystemIcon) = categorizeModel(
            id: id, 
            name: name, 
            provider: provider,
            inputPrice: inputPrice,
            outputPrice: outputPrice
        )
        
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
        case "meta-llama", "meta": return "Meta"
        case "mistralai": return "Mistral"
        case "deepseek": return "DeepSeek"
        case "x-ai": return "xAI"
        case "cohere": return "Cohere"
        case "perplexity": return "Perplexity"
        case "nvidia": return "Nvidia"
        case "aion-labs": return "Aion Labs"
        case "minimax": return "Minimax"
        case "bytedance", "bytedance-seed": return "ByteDance"
        case "qwen": return "Qwen"
        case "openrouter": return "OpenRouter"
        case "z-ai": return "Z.ai"
        case "moonshotai": return "Moonshotai"
        case "liquid": return "Liquid"
        case "arcee": return "Arcee"
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
    private func categorizeModel(
        id: String, 
        name: String, 
        provider: String,
        inputPrice: Double?,
        outputPrice: Double?
    ) -> (StoreModel.ModelCategory, String, String, Bool) {
        let lowerId = id.lowercased()
        let lowerName = name.lowercased()
        
        // First, determine the category based on model characteristics
        let category: StoreModel.ModelCategory
        
        // Check for free models first - "(free)" in name or $0 pricing
        let isFree = lowerName.contains("(free)") || 
            ((inputPrice ?? 1) == 0 && (outputPrice ?? 1) == 0)
        
        if isFree {
            category = .free
        } else if isSpecificFlagshipModel(lowerName) {
            // Specific flagship models by name
            category = .flagship
        } else if lowerId.contains("flash") || lowerName.contains("flash") || lowerName.contains("mini") || lowerName.contains("instant") {
            category = .fast
        } else if lowerId.contains("reasoning") || lowerId.contains("-r1") || lowerName.contains("think") || lowerId.contains("deepseek-r") {
            category = .reasoning
        } else {
            // Default to flagship for premium models
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
            return (category, "aionlabs-icon", "#000000", false)
        case "minimax":
            return (category, "minimax-icon", "#000000", false)
        case "bytedance":
            return (category, "bytedance-icon", "#000000", false)
        case "qwen":
            return (category, "qwen-icon", "#000000", false)
        case "meta":
            return (category, "meta-icon", "#000000", false)
        case "arcee":
            return (category, "arcee-icon", "#000000", false)
            
        // Providers with black/white template icons (monochrome, use grok-color)
        case "openrouter":
            return (category, "openrouter-icon", "#000000", false)
        case "z.ai":
            return (category, "zai-icon", "#000000", false)
        case "moonshotai":
            return (category, "moonshot-icon", "#000000", false)
        case "liquid":
            return (category, "liquid-icon", "#000000", false)
            
        default:
            // For unknown providers, use cpu.fill SF Symbol and grok-color (monochrome)
            return (category, "cpu.fill", "#000000", true)
        }
    }
    
    /// Check if model name matches specific flagship models
    private func isSpecificFlagshipModel(_ lowerName: String) -> Bool {
        // Flagship model patterns
        let flagshipPatterns = [
            "claude opus 4.5",
            "claude sonnet 4.5", 
            "gemini 3 pro",
            "gemini 3 flash",
            "gpt-5.2",
            "gpt 5.2",
        ]
        
        for pattern in flagshipPatterns {
            if lowerName.contains(pattern) {
                return true
            }
        }
        return false
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
