//
//  Theme.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Appearance Manager

@Observable
final class AppearanceManager {
    static let shared = AppearanceManager()
    
    private let userDefaultsKey = "appearanceMode"
    
    var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsKey)
        }
    }
    
    var colorScheme: ColorScheme? {
        mode.colorScheme
    }
    
    private init() {
        if let savedMode = UserDefaults.standard.string(forKey: userDefaultsKey),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.mode = mode
        } else {
            self.mode = .system
        }
    }
}

// MARK: - App Theme Colors (Dynamic light/dark support)

enum AppTheme {
    // Light mode colors
    private enum Light {
        static let background = Color(red: 0.96, green: 0.94, blue: 0.90)
        static let cardBackground = Color(red: 0.94, green: 0.91, blue: 0.86)
        static let inputBackground = Color(red: 0.94, green: 0.92, blue: 0.87)
        static let accent = Color(red: 0.85, green: 0.45, blue: 0.35)
        static let accentLight = Color(red: 0.90, green: 0.55, blue: 0.45)
        static let textPrimary = Color(red: 0.15, green: 0.12, blue: 0.10)
        static let textSecondary = Color(red: 0.45, green: 0.42, blue: 0.38)
        static let textTertiary = Color(red: 0.60, green: 0.57, blue: 0.52)
        static let divider = Color(red: 0.88, green: 0.85, blue: 0.80)
        static let iconDefault = Color(red: 0.35, green: 0.32, blue: 0.28)
    }
    
    // Dark mode colors
    private enum Dark {
        static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
        static let cardBackground = Color(red: 0.17, green: 0.17, blue: 0.18)
        static let inputBackground = Color(red: 0.15, green: 0.15, blue: 0.16)
        static let accent = Color(red: 0.92, green: 0.52, blue: 0.42)
        static let accentLight = Color(red: 0.95, green: 0.60, blue: 0.50)
        static let textPrimary = Color(red: 0.93, green: 0.93, blue: 0.94)
        static let textSecondary = Color(red: 0.63, green: 0.63, blue: 0.65)
        static let textTertiary = Color(red: 0.45, green: 0.45, blue: 0.47)
        static let divider = Color(red: 0.25, green: 0.25, blue: 0.27)
        static let iconDefault = Color(red: 0.70, green: 0.70, blue: 0.72)
    }
    
    // Dynamic colors using adaptive Color assets
    static let background = Color("Background")
    static let cardBackground = Color("CardBackground")
    static let inputBackground = Color("InputBackground")
    static let accent = Color("Accent")
    static let accentLight = Color("AccentLight")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")
    static let divider = Color("Divider")
    static let iconDefault = Color("IconDefault")
    
    // Fallback static colors for previews or when assets aren't available
    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.background : Light.background
    }
    
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.cardBackground : Light.cardBackground
    }
    
    static func inputBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.inputBackground : Light.inputBackground
    }
    
    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.accent : Light.accent
    }
    
    static func accentLight(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.accentLight : Light.accentLight
    }
    
    static func textPrimary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.textPrimary : Light.textPrimary
    }
    
    static func textSecondary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.textSecondary : Light.textSecondary
    }
    
    static func textTertiary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.textTertiary : Light.textTertiary
    }
    
    static func divider(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.divider : Light.divider
    }
    
    static func iconDefault(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Dark.iconDefault : Light.iconDefault
    }
    
    /// Toggle tint color - black in light mode, nil for default iOS green in dark mode
    static func toggleTint(for colorScheme: ColorScheme) -> Color? {
        colorScheme == .dark ? nil : Color.black
    }
}

// MARK: - Greeting Generator

struct GreetingGenerator {
    static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 0..<5:
            return "How can I help you this\nlate night?"
        case 5..<12:
            return "How can I help you this\nmorning?"
        case 12..<17:
            return "How can I help you this\nafternoon?"
        case 17..<21:
            return "How can I help you this\nevening?"
        default:
            return "How can I help you this\nnight?"
        }
    }
}

// MARK: - Sparkle Icon View

struct SparkleIcon: View {
    var size: CGFloat = 40
    var color: Color = AppTheme.accent
    
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
    }
}

// MARK: - Custom Button Styles

struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(12)
            .background {
                Circle()
                    .fill(AppTheme.cardBackground)
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FABButtonStyle: ButtonStyle {
    var color: Color = AppTheme.accent
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(16)
            .background {
                Circle()
                    .fill(color)
            }
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
