//
//  WebSearchIndicatorView.swift
//  LocalChat
//
//  Created by Carl Steen on 28.01.26.
//

import SwiftUI

/// Animated "Searching the web..." indicator with shimmer effect
/// Similar to ThinkingIndicatorView but for web search
struct WebSearchIndicatorView: View {
    let isSearching: Bool
    
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var hasAppeared = false
    
    private let shimmerWidth: CGFloat = 0.3 // Width of the shimmer highlight
    
    var body: some View {
        HStack(spacing: 6) {
            // Globe/web search icon
            Image(systemName: isSearching ? "globe" : "globe")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSearching ? shimmerGradient : AnyShapeStyle(AppTheme.textSecondary))
                .symbolEffect(.pulse, options: .repeating, isActive: isSearching)
            
            // Text with shimmer effect when searching, static when done
            if isSearching {
                Text("Searching the web...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(shimmerGradient)
            } else {
                Text("Searched the web")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(AppTheme.cardBackground)
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hasAppeared)
        .onAppear {
            startAnimation()
            // Trigger haptic on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
    }
    
    // MARK: - Shimmer Gradient
    
    private var shimmerGradient: AnyShapeStyle {
        let baseColor = AppTheme.textSecondary
        let highlightColor = Color.accentColor
        
        // Create a moving gradient that gives the shimmer effect
        return AnyShapeStyle(LinearGradient(
            stops: [
                .init(color: baseColor, location: max(0, shimmerOffset - shimmerWidth)),
                .init(color: highlightColor, location: shimmerOffset),
                .init(color: baseColor, location: min(1, shimmerOffset + shimmerWidth))
            ],
            startPoint: .leading,
            endPoint: .trailing
        ))
    }
    
    // MARK: - Animation
    
    private func startAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 2.0 // Go past 1.0 to ensure full travel
        }
    }
}

// MARK: - Preview

#Preview("Web Search States") {
    VStack(spacing: 24) {
        // Currently searching
        WebSearchIndicatorView(isSearching: true)
        
        // Finished searching
        WebSearchIndicatorView(isSearching: false)
    }
    .padding()
    .background(AppTheme.background)
}
