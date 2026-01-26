//
//  ThinkingIndicatorView.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI

/// Animated "Thinking..." indicator with shimmer effect
/// Similar to ChatGPT's reasoning indicator
struct ThinkingIndicatorView: View {
    let isThinking: Bool
    let thinkingStartTime: Date?
    let thinkingDuration: TimeInterval?
    let onTap: () -> Void
    
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    
    private let shimmerWidth: CGFloat = 0.3 // Width of the shimmer highlight
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Brain/thinking icon
                Image(systemName: isThinking ? "brain" : "brain.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(shimmerGradient)
                    .symbolEffect(.pulse, options: .repeating, isActive: isThinking)
                
                // Text with shimmer effect
                Group {
                    if isThinking {
                        thinkingText
                    } else {
                        completedText
                    }
                }
                .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(AppTheme.cardBackground)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            startAnimations()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: isThinking) { _, newValue in
            if newValue {
                startAnimations()
            } else {
                stopTimer()
            }
        }
    }
    
    // MARK: - Thinking Text (with shimmer)
    
    private var thinkingText: some View {
        Text("Thinking...")
            .foregroundStyle(shimmerGradient)
    }
    
    // MARK: - Completed Text
    
    private var completedText: some View {
        Text(formattedDuration)
            .foregroundStyle(AppTheme.textSecondary)
    }
    
    // MARK: - Shimmer Gradient
    
    private var shimmerGradient: LinearGradient {
        let baseColor = AppTheme.textSecondary
        let highlightColor = AppTheme.accent
        
        // Create a moving gradient that gives the shimmer effect
        return LinearGradient(
            stops: [
                .init(color: baseColor, location: max(0, shimmerOffset - shimmerWidth)),
                .init(color: highlightColor, location: shimmerOffset),
                .init(color: baseColor, location: min(1, shimmerOffset + shimmerWidth))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Duration Formatting
    
    private var formattedDuration: String {
        let duration = thinkingDuration ?? elapsedTime
        
        if duration < 1 {
            return "Thought for a moment"
        }
        
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes > 0 {
            return "Thought for \(minutes)m \(seconds)s"
        } else {
            return "Thought for \(seconds)s"
        }
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Start shimmer animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 2.0 // Go past 1.0 to ensure full travel
        }
        
        // Start elapsed time timer if thinking
        if isThinking, let startTime = thinkingStartTime {
            elapsedTime = Date().timeIntervalSince(startTime)
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                elapsedTime = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Alternative Shimmer Implementation

/// A view modifier that applies a shimmer effect to any view
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let isAnimating: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isAnimating {
                    GeometryReader { geometry in
                        shimmerOverlay(width: geometry.size.width)
                    }
                    .mask(content)
                }
            }
    }
    
    private func shimmerOverlay(width: CGFloat) -> some View {
        LinearGradient(
            colors: [
                .clear,
                AppTheme.accent.opacity(0.6),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width * 0.4)
        .offset(x: width * (phase - 0.2))
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

extension View {
    func shimmer(isActive: Bool) -> some View {
        modifier(ShimmerModifier(isAnimating: isActive))
    }
}

// MARK: - Preview

#Preview("Thinking States") {
    VStack(spacing: 24) {
        // Currently thinking
        ThinkingIndicatorView(
            isThinking: true,
            thinkingStartTime: Date().addingTimeInterval(-5),
            thinkingDuration: nil,
            onTap: {}
        )
        
        // Finished thinking (short duration)
        ThinkingIndicatorView(
            isThinking: false,
            thinkingStartTime: nil,
            thinkingDuration: 12,
            onTap: {}
        )
        
        // Finished thinking (longer duration)
        ThinkingIndicatorView(
            isThinking: false,
            thinkingStartTime: nil,
            thinkingDuration: 95,
            onTap: {}
        )
    }
    .padding()
    .background(AppTheme.background)
}
