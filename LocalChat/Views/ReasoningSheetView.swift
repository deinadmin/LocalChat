//
//  ReasoningSheetView.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI

/// Sheet view to display the model's reasoning/thinking content
struct ReasoningSheetView: View {
    let reasoningContent: String
    let thinkingDuration: TimeInterval?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Duration badge
                    if let duration = thinkingDuration {
                        durationBadge(duration: duration)
                    }
                    
                    // Reasoning content rendered as markdown
                    MarkdownView(reasoningContent, isStreaming: false, horizontalPadding: 0, accentColor: AppTheme.accent)
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Reasoning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Duration Badge
    
    private func durationBadge(duration: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
            
            Text(formattedDuration(duration))
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(AppTheme.cardBackground)
        }
    }
    
    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes > 0 {
            return "Thought for \(minutes) min \(seconds) sec"
        } else {
            return "Thought for \(seconds) seconds"
        }
    }
}

// MARK: - Preview

#Preview("Reasoning Sheet") {
    ReasoningSheetView(
        reasoningContent: """
        Let me think through this step by step.
        
        ## Understanding the Problem
        
        The user is asking about async/await in Swift. I need to:
        
        1. Explain what async/await is
        2. Show how it compares to completion handlers
        3. Provide a practical example
        
        ## Key Points to Cover
        
        - The `async` keyword marks a function as asynchronous
        - The `await` keyword suspends execution until the result is ready
        - Swift uses structured concurrency with `Task` and `TaskGroup`
        
        ## Example Considerations
        
        I should provide a simple network request example that demonstrates:
        - How to declare an async function
        - How to call it with await
        - Error handling with try/catch
        
        This will give the user a complete understanding of the basics.
        """,
        thinkingDuration: 45
    )
}
