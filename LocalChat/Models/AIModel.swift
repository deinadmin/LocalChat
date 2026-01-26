//
//  AIModel.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import Foundation
import SwiftUI

struct AIModel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let provider: String
    let description: String
    let iconName: String
    let isSystemIcon: Bool // true for SF Symbols, false for asset images
    let accentColor: Color
    let isAvailable: Bool
    
    /// Icons that are template images (monochrome) and should use accent color
    var isTemplateIcon: Bool {
        switch iconName {
        case "openai-icon", "grok-icon":
            return true
        default:
            return false
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
    
    init(
        id: UUID = UUID(),
        name: String,
        provider: String,
        description: String,
        iconName: String = "cpu",
        isSystemIcon: Bool = true,
        accentColor: Color = .blue,
        isAvailable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.description = description
        self.iconName = iconName
        self.isSystemIcon = isSystemIcon
        self.accentColor = accentColor
        self.isAvailable = isAvailable
    }
}

// MARK: - Mock Models for v1
extension AIModel {
    static let mockModels: [AIModel] = [
        AIModel(
            name: "Claude 3.5 Sonnet",
            provider: "Anthropic",
            description: "Balanced performance and speed",
            iconName: "claude-icon",
            isSystemIcon: false,
            accentColor: Color(red: 0.85, green: 0.55, blue: 0.35), // Claude orange/tan
            isAvailable: false
        ),
        AIModel(
            name: "GPT-4o",
            provider: "OpenAI",
            description: "Most capable model for complex tasks",
            iconName: "openai-icon",
            isSystemIcon: false,
            accentColor: Color(red: 0.0, green: 0.65, blue: 0.55), // OpenAI teal
            isAvailable: false
        ),
        AIModel(
            name: "Gemini Pro",
            provider: "Google",
            description: "Multimodal understanding",
            iconName: "gemini-icon",
            isSystemIcon: false,
            accentColor: Color(red: 0.4, green: 0.5, blue: 0.95), // Gemini blue
            isAvailable: false
        ),
        AIModel(
            name: "Grok",
            provider: "xAI",
            description: "Real-time knowledge",
            iconName: "grok-icon",
            isSystemIcon: false,
            accentColor: .white, // Grok white on dark
            isAvailable: false
        ),
        AIModel(
            name: "Llama 3.1",
            provider: "Meta",
            description: "Open-source powerhouse",
            iconName: "flame",
            isSystemIcon: true,
            accentColor: .purple,
            isAvailable: false
        ),
        AIModel(
            name: "Local Model",
            provider: "On-Device",
            description: "Private, offline inference",
            iconName: "iphone",
            isSystemIcon: true,
            accentColor: .gray,
            isAvailable: false
        )
    ]
    
    static let defaultModel = mockModels[0]
}
