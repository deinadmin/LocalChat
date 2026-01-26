//
//  SourcesView.swift
//  LocalChat
//
//  Created by Carl Steen on 21.01.26.
//

import SwiftUI

// MARK: - Source Chips Horizontal Scroll View

/// Horizontal scroll view of source chips displayed below a message
struct SourceChipsView: View {
    let citations: [Citation]
    let accentColor: Color
    let horizontalPadding: CGFloat
    let onSourceTap: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(citations) { citation in
                    SourceChipView(citation: citation, accentColor: accentColor)
                        .onTapGesture {
                            onSourceTap()
                        }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
}

/// Individual source chip with favicon, title, and URL preview
struct SourceChipView: View {
    let citation: Citation
    let accentColor: Color
    
    private let chipHeight: CGFloat = 36
    
    var body: some View {
        HStack(spacing: 8) {
            // Favicon
            AsyncImage(url: citation.faviconURL) { phase in
                switch phase {
                case .empty:
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                @unknown default:
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            
            // Title and domain
            VStack(alignment: .leading, spacing: 1) {
                Text(citation.displayTitle.prefix(20) + (citation.displayTitle.count > 20 ? "…" : ""))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text(citation.domain)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: chipHeight)
        .background {
            Capsule()
                .fill(AppTheme.cardBackground)
        }
        .contentShape(Capsule())
    }
}

// MARK: - Citation Pill View (Inline in text)

/// Small circular pill for inline citation references like [1], [2]
struct CitationPillView: View {
    let number: Int
    let accentColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accentColor.contrastingTextColor)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accentColor.opacity(0.85)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sources Sheet View

/// Full sheet view displaying all sources in detailed card format
struct SourcesSheetView: View {
    let citations: [Citation]
    let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(citations) { citation in
                        SourceCardView(citation: citation, accentColor: accentColor) {
                            if let url = URL(string: citation.url) {
                                openURL(url)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppTheme.background)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Detailed source card for the sources sheet
struct SourceCardView: View {
    let citation: Citation
    let accentColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Citation number badge
                Text("\(citation.id)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentColor.contrastingTextColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(accentColor))
                
                // Favicon
                AsyncImage(url: citation.faviconURL) { phase in
                    switch phase {
                    case .empty:
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                    @unknown default:
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                
                // Title and URL
                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(citation.domain)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // External link indicator
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardBackground)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Source Chips") {
    let sampleCitations = Citation.fromURLs([
        "https://en.wikipedia.org/wiki/Swift_(programming_language)",
        "https://developer.apple.com/swift/",
        "https://www.hackingwithswift.com/quick-start/swiftui",
        "https://stackoverflow.com/questions/tagged/swift"
    ])
    
    return VStack(spacing: 20) {
        // Chips view
        SourceChipsView(
            citations: sampleCitations,
            accentColor: .blue,
            horizontalPadding: 16,
            onSourceTap: {}
        )
        
        Divider()
        
        // Individual chip
        SourceChipView(citation: sampleCitations[0], accentColor: .blue)
        
        // Citation pills
        HStack(spacing: 8) {
            CitationPillView(number: 1, accentColor: .blue, onTap: {})
            CitationPillView(number: 2, accentColor: .blue, onTap: {})
            CitationPillView(number: 3, accentColor: .blue, onTap: {})
        }
    }
    .padding()
    .background(AppTheme.background)
}

#Preview("Sources Sheet") {
    let sampleCitations = Citation.fromURLs([
        "https://en.wikipedia.org/wiki/Swift_(programming_language)",
        "https://developer.apple.com/documentation/swift",
        "https://www.hackingwithswift.com/quick-start/swiftui/what-is-swiftui",
        "https://stackoverflow.com/questions/24002369/how-do-i-call-objective-c-code-from-swift",
        "https://github.com/apple/swift"
    ])
    
    return SourcesSheetView(citations: sampleCitations, accentColor: .blue)
}
