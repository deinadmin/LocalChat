//
//  MarkdownView.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Main Markdown View

struct MarkdownView: View {
    let content: String
    let isStreaming: Bool
    let horizontalPadding: CGFloat
    let accentColor: Color
    let citations: [Citation]
    let onCitationTap: (() -> Void)?
    
    @State private var blocks: [MarkdownBlock] = []
    @State private var lastParsedContent: String = ""
    @State private var parseTask: Task<Void, Never>?
    
    init(
        _ content: String,
        isStreaming: Bool = false,
        horizontalPadding: CGFloat = 0,
        accentColor: Color = AppTheme.accent,
        citations: [Citation] = [],
        onCitationTap: (() -> Void)? = nil
    ) {
        self.content = content
        self.isStreaming = isStreaming
        self.horizontalPadding = horizontalPadding
        self.accentColor = accentColor
        self.citations = citations
        self.onCitationTap = onCitationTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<blocks.count, id: \.self) { index in
                MarkdownBlockView(
                    block: blocks[index],
                    horizontalPadding: horizontalPadding,
                    accentColor: accentColor,
                    citations: citations,
                    onCitationTap: onCitationTap
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: blocks.count)
            }
        }
        .textSelection(.enabled)
        .onAppear {
            parseContent()
        }
        .onChange(of: content) {
            // Debounce during streaming to avoid parsing every character
            if isStreaming {
                parseTask?.cancel()
                parseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    if !Task.isCancelled {
                        parseContent()
                    }
                }
            } else {
                parseContent()
            }
        }
        .onChange(of: isStreaming) {
            // When streaming stops, do a final parse
            if !isStreaming {
                parseTask?.cancel()
                parseContent()
            }
        }
    }
    
    private func parseContent() {
        // Only reparse if content actually changed
        guard content != lastParsedContent else { return }
        lastParsedContent = content
        blocks = MarkdownParser.parse(content)
    }
}

// MARK: - Markdown Block Types

enum MarkdownBlock {
    case paragraph(text: String)
    case heading(level: Int, text: String)
    case codeBlock(language: String?, code: String)
    case bulletList(items: [String])
    case numberedList(items: [String])
    case blockquote(text: String)
    case horizontalRule
    case table(headers: [String], rows: [[String]])
}

// MARK: - Block View

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let horizontalPadding: CGFloat
    let accentColor: Color
    let citations: [Citation]
    let onCitationTap: (() -> Void)?
    
    var body: some View {
        switch block {
        case .paragraph(let text):
            MarkdownTextView(text: text, accentColor: accentColor, citations: citations, onCitationTap: onCitationTap)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 12)
            
        case .heading(let level, let text):
            headingView(level: level, text: text)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 8)
                .padding(.top, level == 1 ? 8 : 4)
            
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)
            
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<items.count, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        MarkdownTextView(text: items[index], accentColor: accentColor, citations: citations, onCitationTap: onCitationTap)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 12)
            
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<items.count, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 24, alignment: .trailing)
                        MarkdownTextView(text: items[index], accentColor: accentColor, citations: citations, onCitationTap: onCitationTap)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 12)
            
        case .blockquote(let text):
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor.opacity(0.6))
                    .frame(width: 3)
                
                MarkdownTextView(text: text, accentColor: accentColor, citations: citations, onCitationTap: onCitationTap)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            
        case .horizontalRule:
            Divider()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            
        case .table(let headers, let rows):
            // Tables get special treatment - padding inside the ScrollView
            TableBlockView(headers: headers, rows: rows, horizontalPadding: horizontalPadding, accentColor: accentColor)
                .padding(.vertical, 8)
        }
    }
    
    private func headingView(level: Int, text: String) -> some View {
        let fontSize: CGFloat = switch level {
        case 1: 28
        case 2: 24
        case 3: 20
        default: 18
        }
        
        let weight: Font.Weight = level <= 2 ? .bold : .semibold
        
        return Text(text)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(AppTheme.textPrimary)
    }
}

// MARK: - Markdown Parser (Pure functions, no SwiftUI)

enum MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Code block
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }
            
            // Heading
            if let (level, headingText) = parseHeading(trimmed) {
                blocks.append(.heading(level: level, text: headingText))
                i += 1
                continue
            }
            
            // Horizontal rule
            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }
            
            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let quoteLine = lines[i].trimmingCharacters(in: .whitespaces)
                    quoteLines.append(String(quoteLine.dropFirst().trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: " ")))
                continue
            }
            
            // Bullet list
            if isBulletListItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBulletListItem(listLine) {
                        items.append(String(listLine.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }
            
            // Numbered list
            if let item = parseNumberedListItem(trimmed) {
                var items: [String] = [item]
                i += 1
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if let nextItem = parseNumberedListItem(listLine) {
                        items.append(nextItem)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numberedList(items: items))
                continue
            }
            
            // Table
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var tableLines: [String] = []
                while i < lines.count {
                    let tableLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if tableLine.hasPrefix("|") {
                        tableLines.append(tableLine)
                        i += 1
                    } else {
                        break
                    }
                }
                
                if tableLines.count >= 2 {
                    let headers = parseTableRow(tableLines[0])
                    // Only create table if we have valid headers
                    if !headers.isEmpty {
                        var rows: [[String]] = []
                        for j in 2..<tableLines.count {
                            if !tableLines[j].contains("---") {
                                rows.append(parseTableRow(tableLines[j]))
                            }
                        }
                        blocks.append(.table(headers: headers, rows: rows))
                    }
                }
                continue
            }
            
            // Regular paragraph
            if !trimmed.isEmpty {
                var paragraphLines: [String] = []
                while i < lines.count {
                    let pLine = lines[i]
                    let pTrimmed = pLine.trimmingCharacters(in: .whitespaces)
                    
                    if pTrimmed.isEmpty ||
                       pTrimmed.hasPrefix("```") ||
                       pTrimmed.hasPrefix("#") ||
                       pTrimmed.hasPrefix(">") ||
                       isBulletListItem(pTrimmed) ||
                       pTrimmed.hasPrefix("|") ||
                       parseNumberedListItem(pTrimmed) != nil {
                        break
                    }
                    
                    paragraphLines.append(pTrimmed)
                    i += 1
                }
                
                if !paragraphLines.isEmpty {
                    blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
                }
                continue
            }
            
            i += 1
        }
        
        return blocks
    }
    
    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        var remaining = line[...]
        
        while remaining.first == "#" && level < 6 {
            level += 1
            remaining = remaining.dropFirst()
        }
        
        guard level > 0, remaining.first == " " else { return nil }
        
        let text = String(remaining.dropFirst()).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }
    
    private static func isHorizontalRule(_ line: String) -> Bool {
        // Fast path: check length first
        guard line.count >= 3 else { return false }
        
        // Find first non-whitespace character
        var ruleChar: Character? = nil
        var count = 0
        
        for char in line {
            if char.isWhitespace {
                continue
            }
            if char == "-" || char == "*" || char == "_" {
                if ruleChar == nil {
                    ruleChar = char
                } else if ruleChar != char {
                    return false // Mixed characters
                }
                count += 1
            } else {
                return false // Invalid character
            }
        }
        
        return count >= 3
    }
    
    private static func isBulletListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
    }
    
    private static func parseNumberedListItem(_ line: String) -> String? {
        // Match patterns like "1. ", "2. ", "10. "
        var idx = line.startIndex
        
        while idx < line.endIndex && line[idx].isNumber {
            idx = line.index(after: idx)
        }
        
        guard idx > line.startIndex,
              idx < line.endIndex,
              line[idx] == ".",
              line.index(after: idx) < line.endIndex,
              line[line.index(after: idx)] == " " else {
            return nil
        }
        
        let afterDotSpace = line.index(idx, offsetBy: 2)
        return String(line[afterDotSpace...])
    }
    
    private static func parseTableRow(_ row: String) -> [String] {
        row.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Inline Markdown Text View

struct MarkdownTextView: View {
    let text: String
    let accentColor: Color
    let citations: [Citation]
    let onCitationTap: (() -> Void)?
    
    init(text: String, accentColor: Color = AppTheme.accent, citations: [Citation] = [], onCitationTap: (() -> Void)? = nil) {
        self.text = text
        self.accentColor = accentColor
        self.citations = citations
        self.onCitationTap = onCitationTap
    }
    
    var body: some View {
        // Use UITextView wrapper for proper text selection and SF Symbol citations
        SelectableTextView(
            attributedString: buildNSAttributedString(),
            accentColor: accentColor,
            onCitationTap: onCitationTap
        )
    }
    
    /// Build NSAttributedString with SF Symbol citation images
    private func buildNSAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor(AppTheme.textPrimary)
        ]
        
        // If no citations, build simple attributed string
        if citations.isEmpty || !CitationParser.containsCitations(text) {
            result.append(buildNSAttributedSegment(for: text, defaultAttributes: defaultAttributes))
            return result
        }
        
        // Build with citations
        var currentIndex = text.startIndex
        let citationRanges = CitationParser.citationRanges(in: text)
        
        for (range, number) in citationRanges {
            // Add text before the citation
            if currentIndex < range.lowerBound {
                let textBefore = String(text[currentIndex..<range.lowerBound])
                result.append(buildNSAttributedSegment(for: textBefore, defaultAttributes: defaultAttributes))
            }
            
            // Add SF Symbol citation (1.circle.fill, etc.)
            let symbolName = "\(number).circle.fill"
            if let symbolImage = UIImage(systemName: symbolName)?.withTintColor(UIColor(accentColor), renderingMode: .alwaysOriginal) {
                let attachment = NSTextAttachment()
                // Scale the symbol to match text
                let symbolSize: CGFloat = 15
                attachment.image = symbolImage
                attachment.bounds = CGRect(x: 0, y: -2, width: symbolSize, height: symbolSize)
                
                let attachmentString = NSMutableAttributedString(attachment: attachment)
                // Add a custom attribute to identify this as a citation for tap handling
                attachmentString.addAttribute(.link, value: URL(string: "citation://\(number)")!, range: NSRange(location: 0, length: attachmentString.length))
                result.append(attachmentString)
            }
            
            currentIndex = range.upperBound
        }
        
        // Add remaining text after last citation
        if currentIndex < text.endIndex {
            let remainingText = String(text[currentIndex...])
            result.append(buildNSAttributedSegment(for: remainingText, defaultAttributes: defaultAttributes))
        }
        
        return result
    }
    
    /// Build NSAttributedString segment with markdown formatting
    private func buildNSAttributedSegment(for segment: String, defaultAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(segment)
        var i = 0
        
        while i < chars.count {
            // Bold + Italic (***text***)
            if i + 2 < chars.count && chars[i] == "*" && chars[i+1] == "*" && chars[i+2] == "*" {
                if let endIdx = findClosing(in: chars, from: i + 3, pattern: "***") {
                    let content = String(chars[(i+3)..<endIdx])
                    var attrs = defaultAttributes
                    if let font = attrs[.font] as? UIFont {
                        attrs[.font] = UIFont.systemFont(ofSize: font.pointSize, weight: .bold).withTraits(.traitItalic)
                    }
                    result.append(NSAttributedString(string: content, attributes: attrs))
                    i = endIdx + 3
                    continue
                }
            }
            
            // Bold (**text**)
            if i + 1 < chars.count && chars[i] == "*" && chars[i+1] == "*" {
                if let endIdx = findClosing(in: chars, from: i + 2, pattern: "**") {
                    let content = String(chars[(i+2)..<endIdx])
                    var attrs = defaultAttributes
                    attrs[.font] = UIFont.systemFont(ofSize: 16, weight: .bold)
                    result.append(NSAttributedString(string: content, attributes: attrs))
                    i = endIdx + 2
                    continue
                }
            }
            
            // Italic (*text*)
            if chars[i] == "*" && (i == 0 || chars[i-1] != "*") {
                if let endIdx = findClosingSingle(in: chars, from: i + 1, char: "*") {
                    let content = String(chars[(i+1)..<endIdx])
                    var attrs = defaultAttributes
                    attrs[.font] = UIFont.italicSystemFont(ofSize: 16)
                    result.append(NSAttributedString(string: content, attributes: attrs))
                    i = endIdx + 1
                    continue
                }
            }
            
            // Inline code (`code`)
            if chars[i] == "`" {
                if let endIdx = findClosingSingle(in: chars, from: i + 1, char: "`") {
                    let content = String(chars[(i+1)..<endIdx])
                    var attrs = defaultAttributes
                    attrs[.font] = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                    attrs[.backgroundColor] = UIColor(AppTheme.cardBackground)
                    result.append(NSAttributedString(string: content, attributes: attrs))
                    i = endIdx + 1
                    continue
                }
            }
            
            // Link [text](url)
            if chars[i] == "[" {
                if let (linkText, url, endIdx) = parseLink(in: chars, from: i) {
                    var attrs = defaultAttributes
                    attrs[.foregroundColor] = UIColor(accentColor)
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if let linkURL = URL(string: url) {
                        attrs[.link] = linkURL
                    }
                    result.append(NSAttributedString(string: linkText, attributes: attrs))
                    i = endIdx
                    continue
                }
            }
            
            // Regular character
            result.append(NSAttributedString(string: String(chars[i]), attributes: defaultAttributes))
            i += 1
        }
        
        return result
    }
    
    private func findClosing(in chars: [Character], from start: Int, pattern: String) -> Int? {
        let patternChars = Array(pattern)
        var j = start
        
        while j <= chars.count - patternChars.count {
            var matches = true
            for k in 0..<patternChars.count {
                if chars[j + k] != patternChars[k] {
                    matches = false
                    break
                }
            }
            if matches { return j }
            j += 1
        }
        
        return nil
    }
    
    private func findClosingSingle(in chars: [Character], from start: Int, char: Character) -> Int? {
        for j in start..<chars.count {
            if chars[j] == char {
                return j
            }
        }
        return nil
    }
    
    private func parseLink(in chars: [Character], from start: Int) -> (String, String, Int)? {
        guard chars[start] == "[" else { return nil }
        
        // Find ]
        var bracketEnd: Int?
        for j in (start + 1)..<chars.count {
            if chars[j] == "]" {
                bracketEnd = j
                break
            }
        }
        
        guard let be = bracketEnd,
              be + 1 < chars.count,
              chars[be + 1] == "(" else { return nil }
        
        // Find )
        var parenEnd: Int?
        for j in (be + 2)..<chars.count {
            if chars[j] == ")" {
                parenEnd = j
                break
            }
        }
        
        guard let pe = parenEnd else { return nil }
        
        let linkText = String(chars[(start + 1)..<be])
        let url = String(chars[(be + 2)..<pe])
        
        return (linkText, url, pe + 1)
    }
}

// MARK: - Selectable Text View (UIViewRepresentable)

/// UITextView wrapper that provides proper text selection like a webpage
private struct SelectableTextView: UIViewRepresentable {
    let attributedString: NSAttributedString
    let accentColor: Color
    let onCitationTap: (() -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(accentColor)
        ]
        // Remove any default padding/margin
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = attributedString
        context.coordinator.onCitationTap = onCitationTap
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCitationTap: onCitationTap)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var onCitationTap: (() -> Void)?
        
        init(onCitationTap: (() -> Void)?) {
            self.onCitationTap = onCitationTap
        }
        
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if URL.scheme == "citation" {
                onCitationTap?()
                return false
            }
            // Allow other links to open normally
            return true
        }
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}

// MARK: - UIFont Extension for Traits

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

// MARK: - Code Block View with Liquid Glass

struct CodeBlockView: View {
    let language: String?
    let code: String
    
    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme
    
    private let chipHeight: CGFloat = 28
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(languageDisplayName(lang))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                Spacer()
                
                // Fixed width to prevent layout shift when text changes
                Button {
                    copyCode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 14) // Fixed icon width
                        Text(copied ? "" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(copied ? .green : AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(width: 72, height: chipHeight) // Fixed size to prevent layout shift
                    .background {
                        Capsule()
                            .fill(AppTheme.cardBackground.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: copied) { _, newValue in
                    newValue
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedCode)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(codeBackgroundTint), in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var highlightedCode: AttributedString {
        // Apply syntax highlighting based on language
        guard let lang = language?.lowercased() else {
            var result = AttributedString(code)
            result.foregroundColor = codeTextColor
            return result
        }
        
        return SyntaxHighlighter.highlight(code, language: lang, colorScheme: colorScheme)
    }
    
    private var codeTextColor: Color {
        colorScheme == .dark ? Color(white: 0.9) : Color(white: 0.15)
    }
    
    private var codeBackgroundTint: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.92)
    }
    
    private func languageDisplayName(_ lang: String) -> String {
        switch lang.lowercased() {
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "py": return "Python"
        case "rb": return "Ruby"
        case "sh", "bash", "zsh": return "Shell"
        case "yml": return "YAML"
        case "md": return "Markdown"
        default: return lang.capitalized
        }
    }
    
    private func copyCode() {
        #if os(iOS)
        UIPasteboard.general.string = code
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copied = true
        }
        
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    copied = false
                }
            }
        }
    }
}

// MARK: - Syntax Highlighter

enum SyntaxHighlighter {
    
    // MARK: - Color Palette
    
    private struct SyntaxColors {
        let keyword: Color
        let type: Color
        let string: Color
        let number: Color
        let comment: Color
        let function: Color
        let property: Color
        let `operator`: Color
        let attribute: Color
        let plain: Color
        
        static func forScheme(_ colorScheme: ColorScheme) -> SyntaxColors {
            if colorScheme == .dark {
                return SyntaxColors(
                    keyword: Color(red: 0.99, green: 0.42, blue: 0.56),    // Pink - keywords
                    type: Color(red: 0.55, green: 0.82, blue: 0.94),       // Cyan - types
                    string: Color(red: 0.99, green: 0.82, blue: 0.55),     // Orange - strings
                    number: Color(red: 0.82, green: 0.68, blue: 0.99),     // Purple - numbers
                    comment: Color(red: 0.48, green: 0.54, blue: 0.59),    // Gray - comments
                    function: Color(red: 0.67, green: 0.85, blue: 0.60),   // Green - functions
                    property: Color(red: 0.55, green: 0.82, blue: 0.94),   // Cyan - properties
                    operator: Color(white: 0.85),                          // Light gray - operators
                    attribute: Color(red: 0.99, green: 0.55, blue: 0.42),  // Orange-red - attributes
                    plain: Color(white: 0.9)                               // Light - plain text
                )
            } else {
                return SyntaxColors(
                    keyword: Color(red: 0.69, green: 0.13, blue: 0.47),    // Magenta - keywords
                    type: Color(red: 0.07, green: 0.45, blue: 0.60),       // Teal - types
                    string: Color(red: 0.77, green: 0.25, blue: 0.17),     // Red-orange - strings
                    number: Color(red: 0.47, green: 0.25, blue: 0.68),     // Purple - numbers
                    comment: Color(red: 0.45, green: 0.50, blue: 0.55),    // Gray - comments
                    function: Color(red: 0.20, green: 0.50, blue: 0.30),   // Green - functions
                    property: Color(red: 0.07, green: 0.45, blue: 0.60),   // Teal - properties
                    operator: Color(white: 0.25),                          // Dark gray - operators
                    attribute: Color(red: 0.60, green: 0.33, blue: 0.17),  // Brown - attributes
                    plain: Color(white: 0.15)                              // Dark - plain text
                )
            }
        }
    }
    
    // MARK: - Language Definitions
    
    private struct LanguageDefinition {
        let keywords: Set<String>
        let types: Set<String>
        let builtins: Set<String>
        let singleLineComment: String?
        let multiLineCommentStart: String?
        let multiLineCommentEnd: String?
        let stringDelimiters: [Character]
        let attributePrefix: Character?
    }
    
    private static let swift = LanguageDefinition(
        keywords: ["func", "var", "let", "if", "else", "for", "while", "return", "import", "struct", "class", "enum", "protocol", "extension", "private", "public", "internal", "fileprivate", "open", "static", "self", "Self", "guard", "switch", "case", "default", "break", "continue", "async", "await", "throws", "throw", "try", "catch", "rethrows", "some", "any", "init", "deinit", "where", "in", "true", "false", "nil", "as", "is", "super", "override", "mutating", "nonmutating", "lazy", "weak", "unowned", "willSet", "didSet", "get", "set", "subscript", "typealias", "associatedtype", "inout", "defer", "repeat", "fallthrough", "#if", "#else", "#endif", "#available", "do"],
        types: ["View", "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "URL", "Data", "Date", "UUID", "Color", "Font", "Image", "Text", "Button", "VStack", "HStack", "ZStack", "List", "ForEach", "NavigationStack", "NavigationLink", "ScrollView", "LazyVStack", "LazyHStack", "Spacer", "Divider", "EmptyView", "AnyView", "Group", "Section", "Form", "TextField", "SecureField", "TextEditor", "Toggle", "Picker", "Slider", "Stepper", "DatePicker", "ColorPicker", "ProgressView", "Label", "Link", "Menu", "ContextMenu", "Alert", "Sheet", "Popover", "FullScreenCover", "TabView", "NavigationView", "GeometryReader", "Path", "Shape", "Circle", "Rectangle", "RoundedRectangle", "Ellipse", "Capsule", "CGFloat", "CGPoint", "CGSize", "CGRect", "UIColor", "NSColor", "AttributedString", "Binding", "State", "ObservedObject", "StateObject", "EnvironmentObject", "Environment", "Published", "ObservableObject", "Identifiable", "Hashable", "Equatable", "Codable", "Encodable", "Decodable", "Sendable", "Actor", "MainActor", "Task", "AsyncSequence", "Void", "Never", "Any", "AnyObject"],
        builtins: ["print", "debugPrint", "fatalError", "precondition", "assert", "min", "max", "abs", "stride", "zip", "map", "filter", "reduce", "compactMap", "flatMap", "forEach", "sorted", "reversed", "first", "last", "contains", "isEmpty", "count", "append", "insert", "remove", "removeAll"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\""],
        attributePrefix: "@"
    )
    
    private static let python = LanguageDefinition(
        keywords: ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "async", "await", "True", "False", "None", "and", "or", "not", "in", "is", "pass", "break", "continue", "raise", "global", "nonlocal", "del", "assert"],
        types: ["str", "int", "float", "bool", "list", "dict", "set", "tuple", "bytes", "bytearray", "object", "type", "Exception", "BaseException", "TypeError", "ValueError", "KeyError", "IndexError", "AttributeError", "RuntimeError", "StopIteration", "Generator", "Callable", "Optional", "Union", "Any", "List", "Dict", "Set", "Tuple", "Sequence", "Mapping", "Iterable"],
        builtins: ["print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed", "sum", "min", "max", "abs", "round", "open", "input", "isinstance", "issubclass", "hasattr", "getattr", "setattr", "delattr", "callable", "iter", "next", "super", "property", "staticmethod", "classmethod", "all", "any", "bin", "hex", "oct", "ord", "chr", "format", "repr", "hash", "id", "dir", "vars", "globals", "locals", "eval", "exec", "compile"],
        singleLineComment: "#",
        multiLineCommentStart: "\"\"\"",
        multiLineCommentEnd: "\"\"\"",
        stringDelimiters: ["\"", "'"],
        attributePrefix: "@"
    )
    
    private static let javascript = LanguageDefinition(
        keywords: ["function", "const", "let", "var", "if", "else", "for", "while", "do", "return", "import", "export", "from", "class", "extends", "new", "this", "super", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "true", "false", "null", "undefined", "default", "switch", "case", "break", "continue", "yield", "of", "in", "delete", "void", "with", "debugger", "static", "get", "set"],
        types: ["String", "Number", "Boolean", "Object", "Array", "Function", "Promise", "Map", "Set", "WeakMap", "WeakSet", "Date", "Error", "TypeError", "ReferenceError", "SyntaxError", "RangeError", "RegExp", "Symbol", "BigInt", "Proxy", "Reflect", "JSON", "Math", "console", "window", "document", "navigator", "localStorage", "sessionStorage", "fetch", "Request", "Response", "Headers", "URL", "URLSearchParams", "FormData", "Blob", "File", "FileReader", "ArrayBuffer", "DataView", "Int8Array", "Uint8Array", "Float32Array", "Float64Array"],
        builtins: ["parseInt", "parseFloat", "isNaN", "isFinite", "encodeURI", "decodeURI", "encodeURIComponent", "decodeURIComponent", "setTimeout", "setInterval", "clearTimeout", "clearInterval", "requestAnimationFrame", "cancelAnimationFrame", "alert", "confirm", "prompt", "require", "module", "exports", "process", "Buffer", "__dirname", "__filename"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'", "`"],
        attributePrefix: nil
    )
    
    private static let rust = LanguageDefinition(
        keywords: ["fn", "let", "mut", "const", "static", "if", "else", "match", "for", "while", "loop", "return", "break", "continue", "use", "mod", "pub", "crate", "self", "Self", "super", "struct", "enum", "trait", "impl", "type", "where", "as", "in", "ref", "move", "async", "await", "dyn", "unsafe", "extern", "true", "false"],
        types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc", "Cell", "RefCell", "Mutex", "RwLock", "HashMap", "HashSet", "BTreeMap", "BTreeSet", "VecDeque", "LinkedList", "BinaryHeap", "Cow", "Pin", "Future", "Stream", "Iterator", "IntoIterator", "Clone", "Copy", "Debug", "Display", "Default", "Eq", "PartialEq", "Ord", "PartialOrd", "Hash", "Send", "Sync", "Sized", "Drop", "Fn", "FnMut", "FnOnce", "From", "Into", "TryFrom", "TryInto", "AsRef", "AsMut", "Deref", "DerefMut"],
        builtins: ["println", "print", "eprintln", "eprint", "format", "panic", "assert", "assert_eq", "assert_ne", "debug_assert", "vec", "todo", "unimplemented", "unreachable", "cfg", "include", "include_str", "include_bytes", "concat", "stringify", "env", "option_env", "compile_error", "file", "line", "column", "module_path"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\""],
        attributePrefix: "#"
    )
    
    private static let go = LanguageDefinition(
        keywords: ["func", "var", "const", "type", "struct", "interface", "map", "chan", "if", "else", "for", "range", "switch", "case", "default", "select", "break", "continue", "return", "go", "defer", "fallthrough", "goto", "package", "import", "true", "false", "nil", "iota"],
        types: ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "float32", "float64", "complex64", "complex128", "bool", "byte", "rune", "string", "error", "any", "comparable"],
        builtins: ["append", "cap", "clear", "close", "complex", "copy", "delete", "imag", "len", "make", "max", "min", "new", "panic", "print", "println", "real", "recover"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'", "`"],
        attributePrefix: nil
    )
    
    private static let html = LanguageDefinition(
        keywords: [],
        types: [],
        builtins: ["html", "head", "body", "div", "span", "p", "a", "img", "ul", "ol", "li", "table", "tr", "td", "th", "thead", "tbody", "form", "input", "button", "select", "option", "textarea", "label", "h1", "h2", "h3", "h4", "h5", "h6", "header", "footer", "nav", "main", "section", "article", "aside", "figure", "figcaption", "video", "audio", "source", "canvas", "svg", "path", "script", "style", "link", "meta", "title", "br", "hr", "pre", "code", "blockquote", "em", "strong", "i", "b", "u", "s", "small", "sub", "sup", "mark", "del", "ins", "iframe", "embed", "object", "param"],
        singleLineComment: nil,
        multiLineCommentStart: "<!--",
        multiLineCommentEnd: "-->",
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let css = LanguageDefinition(
        keywords: ["important", "inherit", "initial", "unset", "revert", "auto", "none", "block", "inline", "flex", "grid", "absolute", "relative", "fixed", "sticky", "static"],
        types: [],
        builtins: ["color", "background", "background-color", "background-image", "border", "border-radius", "margin", "padding", "width", "height", "max-width", "max-height", "min-width", "min-height", "display", "position", "top", "right", "bottom", "left", "z-index", "overflow", "opacity", "visibility", "font", "font-size", "font-weight", "font-family", "font-style", "text-align", "text-decoration", "text-transform", "line-height", "letter-spacing", "word-spacing", "white-space", "flex-direction", "flex-wrap", "justify-content", "align-items", "align-content", "gap", "grid-template-columns", "grid-template-rows", "transition", "transform", "animation", "box-shadow", "text-shadow", "cursor", "pointer-events", "user-select"],
        singleLineComment: nil,
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let json = LanguageDefinition(
        keywords: ["true", "false", "null"],
        types: [],
        builtins: [],
        singleLineComment: nil,
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil,
        stringDelimiters: ["\""],
        attributePrefix: nil
    )
    
    private static let shell = LanguageDefinition(
        keywords: ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "in", "function", "return", "exit", "break", "continue", "export", "local", "readonly", "unset", "shift", "set", "true", "false"],
        types: [],
        builtins: ["echo", "printf", "read", "cd", "pwd", "ls", "cp", "mv", "rm", "mkdir", "rmdir", "touch", "cat", "head", "tail", "grep", "sed", "awk", "find", "xargs", "sort", "uniq", "wc", "cut", "tr", "chmod", "chown", "chgrp", "ln", "tar", "gzip", "gunzip", "zip", "unzip", "curl", "wget", "ssh", "scp", "rsync", "git", "docker", "kubectl", "npm", "yarn", "pip", "python", "node", "ruby", "go", "cargo", "make", "cmake", "gcc", "clang", "java", "javac", "mvn", "gradle", "apt", "yum", "brew", "pacman", "sudo", "su", "whoami", "which", "where", "whereis", "man", "help", "alias", "source", "eval", "exec", "nohup", "kill", "pkill", "ps", "top", "htop", "df", "du", "free", "uname", "hostname", "date", "time", "sleep", "wait", "test", "[", "[["],
        singleLineComment: "#",
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil,
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let sql = LanguageDefinition(
        keywords: ["select", "from", "where", "and", "or", "not", "in", "like", "between", "is", "null", "order", "by", "asc", "desc", "limit", "offset", "group", "having", "join", "inner", "left", "right", "outer", "full", "cross", "on", "as", "distinct", "all", "union", "intersect", "except", "insert", "into", "values", "update", "set", "delete", "create", "table", "index", "view", "database", "schema", "drop", "alter", "add", "column", "constraint", "primary", "key", "foreign", "references", "unique", "check", "default", "auto_increment", "not", "null", "cascade", "restrict", "truncate", "grant", "revoke", "commit", "rollback", "transaction", "begin", "end", "if", "else", "case", "when", "then", "end", "exists", "any", "some", "true", "false"],
        types: ["int", "integer", "smallint", "bigint", "decimal", "numeric", "float", "real", "double", "precision", "char", "varchar", "text", "blob", "clob", "date", "time", "timestamp", "datetime", "boolean", "bool", "binary", "varbinary", "json", "xml", "uuid", "serial", "money", "interval", "array"],
        builtins: ["count", "sum", "avg", "min", "max", "abs", "round", "floor", "ceil", "ceiling", "mod", "power", "sqrt", "length", "char_length", "upper", "lower", "trim", "ltrim", "rtrim", "substring", "substr", "replace", "concat", "coalesce", "nullif", "cast", "convert", "now", "current_date", "current_time", "current_timestamp", "date_add", "date_sub", "datediff", "year", "month", "day", "hour", "minute", "second", "extract", "row_number", "rank", "dense_rank", "ntile", "lead", "lag", "first_value", "last_value"],
        singleLineComment: "--",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["'"],
        attributePrefix: nil
    )
    
    private static let java = LanguageDefinition(
        keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "default", "do", "double", "else", "enum", "extends", "final", "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int", "interface", "long", "native", "new", "package", "private", "protected", "public", "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "void", "volatile", "while", "true", "false", "null", "var", "yield", "record", "sealed", "permits", "non-sealed"],
        types: ["String", "Integer", "Long", "Double", "Float", "Boolean", "Character", "Byte", "Short", "Object", "Class", "System", "Math", "StringBuilder", "StringBuffer", "ArrayList", "LinkedList", "HashMap", "HashSet", "TreeMap", "TreeSet", "List", "Map", "Set", "Collection", "Iterator", "Comparable", "Comparator", "Optional", "Stream", "Consumer", "Supplier", "Function", "Predicate", "BiFunction", "BiConsumer", "Runnable", "Callable", "Future", "CompletableFuture", "Thread", "Exception", "RuntimeException", "Error", "Throwable", "IOException", "NullPointerException", "IllegalArgumentException", "IllegalStateException", "IndexOutOfBoundsException", "Arrays", "Collections", "Objects", "Files", "Path", "Paths", "Pattern", "Matcher", "Scanner", "PrintStream", "InputStream", "OutputStream", "Reader", "Writer", "BufferedReader", "BufferedWriter", "FileReader", "FileWriter"],
        builtins: ["println", "print", "printf", "format", "toString", "equals", "hashCode", "compareTo", "length", "size", "isEmpty", "contains", "add", "remove", "get", "set", "put", "clear", "toArray", "stream", "forEach", "map", "filter", "reduce", "collect", "sorted", "distinct", "limit", "skip", "findFirst", "findAny", "anyMatch", "allMatch", "noneMatch", "count", "min", "max", "sum", "average", "parseInt", "parseDouble", "valueOf", "getClass", "notify", "notifyAll", "wait", "clone", "finalize"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: "@"
    )
    
    private static let c = LanguageDefinition(
        keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Alignas", "_Alignof", "_Atomic", "_Bool", "_Complex", "_Generic", "_Imaginary", "_Noreturn", "_Static_assert", "_Thread_local", "true", "false", "NULL"],
        types: ["int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t", "FILE", "DIR", "time_t", "clock_t", "pid_t", "off_t", "bool", "wchar_t", "char16_t", "char32_t"],
        builtins: ["printf", "scanf", "fprintf", "fscanf", "sprintf", "snprintf", "sscanf", "puts", "gets", "fgets", "fputs", "getchar", "putchar", "fopen", "fclose", "fread", "fwrite", "fseek", "ftell", "rewind", "feof", "ferror", "malloc", "calloc", "realloc", "free", "memset", "memcpy", "memmove", "memcmp", "strlen", "strcpy", "strncpy", "strcat", "strncat", "strcmp", "strncmp", "strchr", "strrchr", "strstr", "strtok", "atoi", "atol", "atof", "strtol", "strtoul", "strtod", "abs", "labs", "fabs", "ceil", "floor", "round", "sqrt", "pow", "exp", "log", "sin", "cos", "tan", "rand", "srand", "time", "clock", "exit", "abort", "assert", "isalpha", "isdigit", "isalnum", "isspace", "isupper", "islower", "toupper", "tolower"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let cpp = LanguageDefinition(
        keywords: ["alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "bool", "break", "case", "catch", "char", "char8_t", "char16_t", "char32_t", "class", "compl", "concept", "const", "consteval", "constexpr", "constinit", "const_cast", "continue", "co_await", "co_return", "co_yield", "decltype", "default", "delete", "do", "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false", "float", "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected", "public", "register", "reinterpret_cast", "requires", "return", "short", "signed", "sizeof", "static", "static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local", "throw", "true", "try", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq", "override", "final"],
        types: ["string", "wstring", "vector", "list", "deque", "array", "forward_list", "set", "multiset", "map", "multimap", "unordered_set", "unordered_multiset", "unordered_map", "unordered_multimap", "stack", "queue", "priority_queue", "pair", "tuple", "optional", "variant", "any", "span", "string_view", "unique_ptr", "shared_ptr", "weak_ptr", "function", "bind", "thread", "mutex", "lock_guard", "unique_lock", "condition_variable", "future", "promise", "async", "atomic", "chrono", "regex", "exception", "runtime_error", "logic_error", "invalid_argument", "out_of_range", "bad_alloc", "iostream", "istream", "ostream", "fstream", "ifstream", "ofstream", "stringstream", "istringstream", "ostringstream", "cin", "cout", "cerr", "clog", "endl", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "size_t", "ptrdiff_t", "nullptr_t", "initializer_list", "iterator", "const_iterator", "reverse_iterator"],
        builtins: ["std", "begin", "end", "cbegin", "cend", "rbegin", "rend", "size", "empty", "front", "back", "push_back", "pop_back", "push_front", "pop_front", "insert", "erase", "clear", "find", "count", "lower_bound", "upper_bound", "equal_range", "swap", "sort", "stable_sort", "partial_sort", "nth_element", "binary_search", "merge", "reverse", "rotate", "shuffle", "unique", "remove", "remove_if", "replace", "replace_if", "fill", "generate", "transform", "accumulate", "inner_product", "partial_sum", "adjacent_difference", "min", "max", "minmax", "min_element", "max_element", "clamp", "copy", "copy_if", "copy_n", "move", "forward", "make_pair", "make_tuple", "make_unique", "make_shared", "get", "tie", "ignore", "ref", "cref", "invoke", "apply", "visit", "holds_alternative", "get_if", "emplace", "emplace_back", "emplace_front", "emplace_hint", "try_emplace"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let php = LanguageDefinition(
        keywords: ["abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "die", "do", "echo", "else", "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "eval", "exit", "extends", "final", "finally", "fn", "for", "foreach", "function", "global", "goto", "if", "implements", "include", "include_once", "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace", "new", "or", "print", "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch", "throw", "trait", "try", "unset", "use", "var", "while", "xor", "yield", "yield from", "true", "false", "null", "self", "parent"],
        types: ["int", "float", "bool", "string", "array", "object", "callable", "iterable", "void", "mixed", "never", "null", "false", "true", "static", "self", "parent", "stdClass", "Exception", "Error", "TypeError", "ArgumentCountError", "ArithmeticError", "DivisionByZeroError", "ParseError", "Throwable", "Iterator", "Generator", "Closure", "DateTime", "DateTimeImmutable", "DateInterval", "DatePeriod", "ArrayObject", "ArrayIterator", "SplFileInfo", "SplFileObject", "PDO", "PDOStatement", "PDOException", "mysqli", "mysqli_result", "mysqli_stmt", "ReflectionClass", "ReflectionMethod", "ReflectionProperty", "ReflectionFunction"],
        builtins: ["echo", "print", "var_dump", "print_r", "var_export", "debug_backtrace", "strlen", "substr", "strpos", "str_replace", "str_contains", "str_starts_with", "str_ends_with", "strtolower", "strtoupper", "trim", "ltrim", "rtrim", "explode", "implode", "join", "sprintf", "printf", "sscanf", "number_format", "count", "sizeof", "array_push", "array_pop", "array_shift", "array_unshift", "array_merge", "array_map", "array_filter", "array_reduce", "array_keys", "array_values", "array_search", "in_array", "array_unique", "array_reverse", "array_slice", "array_splice", "sort", "rsort", "asort", "arsort", "ksort", "krsort", "usort", "uasort", "uksort", "array_multisort", "json_encode", "json_decode", "serialize", "unserialize", "file_get_contents", "file_put_contents", "file_exists", "is_file", "is_dir", "mkdir", "rmdir", "unlink", "copy", "rename", "fopen", "fclose", "fread", "fwrite", "fgets", "fgetcsv", "fputcsv", "preg_match", "preg_match_all", "preg_replace", "preg_split", "date", "time", "strtotime", "mktime", "checkdate", "date_create", "date_format", "date_diff", "header", "setcookie", "session_start", "session_destroy", "password_hash", "password_verify", "md5", "sha1", "hash", "base64_encode", "base64_decode", "urlencode", "urldecode", "htmlspecialchars", "htmlentities", "strip_tags", "nl2br", "is_null", "is_array", "is_string", "is_int", "is_float", "is_bool", "is_object", "is_numeric", "is_callable", "gettype", "settype", "intval", "floatval", "strval", "boolval", "class_exists", "method_exists", "property_exists", "get_class", "get_parent_class", "is_a", "instanceof"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: "#"
    )
    
    private static let kotlin = LanguageDefinition(
        keywords: ["abstract", "actual", "annotation", "as", "break", "by", "catch", "class", "companion", "const", "constructor", "continue", "crossinline", "data", "delegate", "do", "dynamic", "else", "enum", "expect", "external", "false", "final", "finally", "for", "fun", "get", "if", "import", "in", "infix", "init", "inline", "inner", "interface", "internal", "is", "lateinit", "noinline", "null", "object", "open", "operator", "out", "override", "package", "private", "protected", "public", "reified", "return", "sealed", "set", "super", "suspend", "tailrec", "this", "throw", "true", "try", "typealias", "typeof", "val", "var", "vararg", "when", "where", "while"],
        types: ["Any", "Unit", "Nothing", "Boolean", "Byte", "Short", "Int", "Long", "Float", "Double", "Char", "String", "Array", "List", "MutableList", "ArrayList", "Set", "MutableSet", "HashSet", "LinkedHashSet", "Map", "MutableMap", "HashMap", "LinkedHashMap", "Pair", "Triple", "Sequence", "Iterable", "Iterator", "Collection", "Comparable", "Comparator", "Lazy", "Result", "Throwable", "Exception", "Error", "RuntimeException", "IllegalArgumentException", "IllegalStateException", "NullPointerException", "IndexOutOfBoundsException", "UnsupportedOperationException", "NumberFormatException", "Regex", "MatchResult", "StringBuilder", "Appendable", "CharSequence", "Number", "Enum", "Annotation", "Function", "KClass", "KProperty", "KFunction"],
        builtins: ["println", "print", "readLine", "readln", "require", "requireNotNull", "check", "checkNotNull", "error", "assert", "TODO", "run", "with", "let", "also", "apply", "takeIf", "takeUnless", "repeat", "lazy", "synchronized", "listOf", "mutableListOf", "arrayListOf", "setOf", "mutableSetOf", "hashSetOf", "linkedSetOf", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf", "arrayOf", "intArrayOf", "longArrayOf", "doubleArrayOf", "booleanArrayOf", "charArrayOf", "emptyList", "emptySet", "emptyMap", "emptyArray", "sequenceOf", "generateSequence", "buildList", "buildSet", "buildMap", "to", "component1", "component2", "plus", "minus", "times", "div", "rem", "rangeTo", "contains", "iterator", "compareTo", "equals", "hashCode", "toString", "copy", "first", "last", "single", "firstOrNull", "lastOrNull", "singleOrNull", "find", "findLast", "filter", "filterNot", "filterNotNull", "map", "mapNotNull", "flatMap", "flatten", "associate", "associateBy", "associateWith", "groupBy", "partition", "fold", "reduce", "forEach", "forEachIndexed", "onEach", "zip", "zipWithNext", "chunked", "windowed", "take", "takeLast", "takeWhile", "drop", "dropLast", "dropWhile", "distinct", "distinctBy", "sorted", "sortedBy", "sortedByDescending", "sortedWith", "reversed", "shuffled", "count", "sum", "sumOf", "average", "min", "max", "minBy", "maxBy", "minOf", "maxOf", "any", "all", "none", "contains", "indexOf", "lastIndexOf", "joinToString", "toList", "toMutableList", "toSet", "toMutableSet", "toMap", "toMutableMap", "toTypedArray", "toIntArray", "toLongArray", "toDoubleArray"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: "@"
    )
    
    private static let csharp = LanguageDefinition(
        keywords: ["abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char", "checked", "class", "const", "continue", "decimal", "default", "delegate", "do", "double", "else", "enum", "event", "explicit", "extern", "false", "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in", "int", "interface", "internal", "is", "lock", "long", "namespace", "new", "null", "object", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sbyte", "sealed", "short", "sizeof", "stackalloc", "static", "string", "struct", "switch", "this", "throw", "true", "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using", "var", "virtual", "void", "volatile", "while", "add", "alias", "ascending", "async", "await", "by", "descending", "dynamic", "equals", "from", "get", "global", "group", "init", "into", "join", "let", "nameof", "nint", "not", "notnull", "nuint", "on", "or", "orderby", "partial", "record", "remove", "required", "select", "set", "unmanaged", "value", "when", "where", "with", "yield"],
        types: ["String", "Int32", "Int64", "Double", "Single", "Boolean", "Char", "Byte", "Object", "Type", "Array", "List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList", "SortedList", "SortedSet", "SortedDictionary", "ArrayList", "Hashtable", "StringBuilder", "Guid", "DateTime", "DateTimeOffset", "TimeSpan", "Nullable", "Tuple", "ValueTuple", "Task", "ValueTask", "Action", "Func", "Predicate", "Comparison", "EventHandler", "IEnumerable", "IEnumerator", "ICollection", "IList", "IDictionary", "ISet", "IComparable", "IEquatable", "IDisposable", "IAsyncDisposable", "ICloneable", "IFormattable", "IConvertible", "Exception", "ArgumentException", "ArgumentNullException", "ArgumentOutOfRangeException", "InvalidOperationException", "NotImplementedException", "NotSupportedException", "NullReferenceException", "IndexOutOfRangeException", "KeyNotFoundException", "FormatException", "OverflowException", "IOException", "FileNotFoundException", "DirectoryNotFoundException", "Stream", "MemoryStream", "FileStream", "StreamReader", "StreamWriter", "BinaryReader", "BinaryWriter", "TextReader", "TextWriter", "Console", "Math", "Convert", "BitConverter", "Encoding", "Regex", "Match", "Group", "Capture", "Thread", "ThreadPool", "Timer", "Mutex", "Semaphore", "Monitor", "Interlocked", "CancellationToken", "CancellationTokenSource", "HttpClient", "HttpResponseMessage", "HttpRequestMessage", "JsonSerializer", "XmlSerializer"],
        builtins: ["Console.WriteLine", "Console.ReadLine", "Console.Write", "ToString", "Equals", "GetHashCode", "GetType", "CompareTo", "Clone", "Format", "Parse", "TryParse", "Add", "Remove", "Contains", "Clear", "Count", "ToArray", "ToList", "ToDictionary", "Where", "Select", "SelectMany", "OrderBy", "OrderByDescending", "ThenBy", "ThenByDescending", "GroupBy", "Join", "GroupJoin", "Distinct", "Union", "Intersect", "Except", "Concat", "Zip", "Skip", "SkipWhile", "Take", "TakeWhile", "First", "FirstOrDefault", "Last", "LastOrDefault", "Single", "SingleOrDefault", "ElementAt", "ElementAtOrDefault", "DefaultIfEmpty", "Reverse", "Any", "All", "Count", "Sum", "Min", "Max", "Average", "Aggregate", "SequenceEqual", "Cast", "OfType", "AsEnumerable", "AsQueryable", "ToLookup", "Append", "Prepend", "Range", "Repeat", "Empty"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: "["
    )
    
    private static let ruby = LanguageDefinition(
        keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "__FILE__", "__LINE__", "__ENCODING__", "BEGIN", "END", "attr_reader", "attr_writer", "attr_accessor", "private", "protected", "public", "require", "require_relative", "include", "extend", "prepend", "raise", "fail", "catch", "throw", "lambda", "proc", "loop"],
        types: ["Object", "Class", "Module", "String", "Integer", "Float", "Rational", "Complex", "Array", "Hash", "Set", "Range", "Regexp", "MatchData", "Symbol", "Proc", "Lambda", "Method", "UnboundMethod", "Binding", "NilClass", "TrueClass", "FalseClass", "Numeric", "Comparable", "Enumerable", "Enumerator", "Struct", "OpenStruct", "Exception", "StandardError", "RuntimeError", "TypeError", "ArgumentError", "NameError", "NoMethodError", "IndexError", "KeyError", "RangeError", "IOError", "EOFError", "SystemCallError", "Errno", "File", "Dir", "IO", "StringIO", "Tempfile", "FileUtils", "Pathname", "URI", "Net", "HTTP", "JSON", "YAML", "CSV", "Time", "Date", "DateTime", "BigDecimal", "Thread", "Mutex", "Queue", "ConditionVariable", "Fiber", "BasicObject", "Kernel"],
        builtins: ["puts", "print", "p", "pp", "gets", "chomp", "to_s", "to_i", "to_f", "to_a", "to_h", "to_sym", "inspect", "class", "is_a?", "kind_of?", "instance_of?", "respond_to?", "send", "public_send", "method", "methods", "instance_methods", "class_methods", "ancestors", "superclass", "included_modules", "constants", "instance_variables", "class_variables", "global_variables", "local_variables", "binding", "eval", "instance_eval", "class_eval", "module_eval", "define_method", "define_singleton_method", "method_missing", "respond_to_missing?", "const_get", "const_set", "const_defined?", "remove_const", "autoload", "autoload?", "new", "allocate", "initialize", "dup", "clone", "freeze", "frozen?", "taint", "tainted?", "untaint", "trust", "untrust", "untrusted?", "nil?", "empty?", "blank?", "present?", "length", "size", "count", "first", "last", "take", "drop", "each", "each_with_index", "each_with_object", "map", "collect", "select", "reject", "find", "detect", "find_all", "grep", "grep_v", "include?", "member?", "any?", "all?", "none?", "one?", "reduce", "inject", "sum", "min", "max", "minmax", "min_by", "max_by", "minmax_by", "sort", "sort_by", "reverse", "shuffle", "sample", "uniq", "compact", "flatten", "zip", "transpose", "partition", "group_by", "chunk", "slice", "split", "join", "concat", "push", "pop", "shift", "unshift", "insert", "delete", "delete_at", "delete_if", "keep_if", "clear", "replace", "fill", "index", "rindex", "assoc", "rassoc", "values_at", "fetch", "dig", "slice!", "compact!", "flatten!", "uniq!", "reverse!", "sort!", "sort_by!", "shuffle!", "rotate", "rotate!", "combination", "permutation", "repeated_combination", "repeated_permutation", "product"],
        singleLineComment: "#",
        multiLineCommentStart: "=begin",
        multiLineCommentEnd: "=end",
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let yaml = LanguageDefinition(
        keywords: ["true", "false", "yes", "no", "on", "off", "null", "~"],
        types: [],
        builtins: [],
        singleLineComment: "#",
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil,
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let markdown = LanguageDefinition(
        keywords: [],
        types: [],
        builtins: [],
        singleLineComment: nil,
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil,
        stringDelimiters: [],
        attributePrefix: nil
    )
    
    private static let dart = LanguageDefinition(
        keywords: ["abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue", "covariant", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external", "factory", "false", "final", "finally", "for", "Function", "get", "hide", "if", "implements", "import", "in", "interface", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required", "rethrow", "return", "set", "show", "static", "super", "switch", "sync", "this", "throw", "true", "try", "typedef", "var", "void", "while", "with", "yield"],
        types: ["int", "double", "num", "bool", "String", "List", "Set", "Map", "Iterable", "Iterator", "Object", "dynamic", "void", "Never", "Null", "Future", "Stream", "FutureOr", "Function", "Symbol", "Type", "Runes", "Duration", "DateTime", "Uri", "Pattern", "Match", "RegExp", "StringBuffer", "Exception", "Error", "StateError", "ArgumentError", "RangeError", "TypeError", "FormatException", "UnsupportedError", "UnimplementedError", "ConcurrentModificationError", "StackOverflowError", "OutOfMemoryError", "NoSuchMethodError", "Comparable", "Comparator", "Completer", "Zone", "Timer", "Stopwatch", "BigInt", "Expando", "WeakReference", "Finalizer"],
        builtins: ["print", "main", "runApp", "setState", "initState", "dispose", "build", "createState", "didChangeDependencies", "didUpdateWidget", "deactivate", "toString", "toList", "toSet", "toMap", "map", "where", "fold", "reduce", "forEach", "any", "every", "contains", "indexOf", "lastIndexOf", "add", "addAll", "remove", "removeAt", "removeLast", "removeWhere", "clear", "insert", "insertAll", "sort", "shuffle", "reversed", "first", "last", "single", "isEmpty", "isNotEmpty", "length", "join", "split", "trim", "substring", "replaceAll", "startsWith", "endsWith", "contains", "toLowerCase", "toUpperCase", "compareTo", "parse", "tryParse", "then", "catchError", "whenComplete", "timeout", "asStream", "listen", "cancel", "pause", "resume"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: "@"
    )
    
    private static let scala = LanguageDefinition(
        keywords: ["abstract", "case", "catch", "class", "def", "do", "else", "enum", "export", "extends", "extension", "false", "final", "finally", "for", "forSome", "given", "if", "implicit", "import", "infix", "inline", "lazy", "macro", "match", "new", "null", "object", "opaque", "open", "override", "package", "private", "protected", "return", "sealed", "super", "then", "this", "throw", "trait", "transparent", "true", "try", "type", "using", "val", "var", "while", "with", "yield"],
        types: ["Any", "AnyRef", "AnyVal", "Boolean", "Byte", "Char", "Double", "Float", "Int", "Long", "Nothing", "Null", "Short", "String", "Unit", "Array", "List", "Vector", "Set", "Map", "Seq", "IndexedSeq", "LinearSeq", "Iterable", "Iterator", "Option", "Some", "None", "Either", "Left", "Right", "Try", "Success", "Failure", "Future", "Promise", "Tuple", "Function", "PartialFunction", "Product", "Serializable", "Comparable", "Ordered", "Ordering", "Numeric", "Integral", "Fractional", "Equiv", "Range", "BigInt", "BigDecimal", "StringBuilder", "StringContext", "Symbol", "Char", "ClassTag", "TypeTag", "WeakTypeTag"],
        builtins: ["println", "print", "printf", "readLine", "require", "assert", "assume", "ensuring", "identity", "implicitly", "locally", "summon", "valueOf", "classOf", "isInstanceOf", "asInstanceOf", "eq", "ne", "synchronized", "wait", "notify", "notifyAll", "getClass", "hashCode", "equals", "toString", "clone", "finalize", "map", "flatMap", "filter", "filterNot", "withFilter", "foreach", "foldLeft", "foldRight", "reduceLeft", "reduceRight", "fold", "reduce", "collect", "collectFirst", "find", "exists", "forall", "contains", "count", "isEmpty", "nonEmpty", "size", "length", "head", "headOption", "tail", "init", "last", "lastOption", "take", "takeWhile", "takeRight", "drop", "dropWhile", "dropRight", "slice", "splitAt", "span", "partition", "groupBy", "grouped", "sliding", "zip", "zipWithIndex", "unzip", "flatten", "transpose", "distinct", "sorted", "sortBy", "sortWith", "reverse", "mkString", "addString", "toList", "toVector", "toSet", "toMap", "toArray", "toSeq", "toIndexedSeq", "toIterable", "toIterator", "toStream", "toBuffer", "copyToArray", "copyToBuffer", "corresponds", "diff", "intersect", "union", "patch", "updated", "padTo", "combinations", "permutations", "product", "sum", "min", "max", "minBy", "maxBy"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\""],
        attributePrefix: "@"
    )
    
    private static let r = LanguageDefinition(
        keywords: ["if", "else", "repeat", "while", "function", "for", "in", "next", "break", "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_", "NA_complex_", "NA_character_", "return", "invisible", "local", "on.exit", "stop", "warning", "message", "tryCatch", "withCallingHandlers", "withRestarts", "library", "require", "attach", "detach", "source", "sys.source"],
        types: ["numeric", "integer", "double", "complex", "character", "logical", "raw", "list", "vector", "matrix", "array", "data.frame", "factor", "ordered", "ts", "Date", "POSIXct", "POSIXlt", "difftime", "formula", "expression", "call", "name", "symbol", "language", "pairlist", "environment", "closure", "promise", "externalptr", "weakref", "bytecode", "S4", "function"],
        builtins: ["print", "cat", "paste", "paste0", "sprintf", "format", "nchar", "substr", "substring", "strsplit", "grep", "grepl", "sub", "gsub", "regexpr", "gregexpr", "regmatches", "toupper", "tolower", "chartr", "nchar", "length", "dim", "nrow", "ncol", "names", "colnames", "rownames", "class", "typeof", "mode", "storage.mode", "attributes", "attr", "structure", "c", "list", "vector", "matrix", "array", "data.frame", "cbind", "rbind", "merge", "split", "cut", "table", "xtabs", "ftable", "addmargins", "prop.table", "sum", "prod", "mean", "median", "var", "sd", "min", "max", "range", "quantile", "IQR", "fivenum", "summary", "cumsum", "cumprod", "cummax", "cummin", "diff", "sort", "order", "rank", "unique", "duplicated", "rev", "rep", "seq", "seq_along", "seq_len", "head", "tail", "which", "which.min", "which.max", "any", "all", "match", "pmatch", "charmatch", "is.na", "is.null", "is.finite", "is.infinite", "is.nan", "is.numeric", "is.character", "is.logical", "is.factor", "is.list", "is.vector", "is.matrix", "is.array", "is.data.frame", "as.numeric", "as.integer", "as.double", "as.character", "as.logical", "as.factor", "as.list", "as.vector", "as.matrix", "as.array", "as.data.frame", "lapply", "sapply", "vapply", "mapply", "tapply", "apply", "by", "aggregate", "transform", "within", "subset", "with", "eval", "parse", "deparse", "substitute", "bquote", "quote", "get", "assign", "exists", "rm", "ls", "objects", "search", "attach", "detach", "new.env", "environment", "globalenv", "baseenv", "emptyenv", "parent.frame", "sys.call", "sys.function", "sys.frame", "sys.nframe", "sys.calls", "sys.frames", "sys.parents", "sys.on.exit", "sys.status", "options", "getOption", "setOption", "Sys.time", "Sys.Date", "Sys.timezone", "Sys.getenv", "Sys.setenv", "Sys.sleep", "Sys.info", "file.exists", "file.create", "file.remove", "file.rename", "file.copy", "file.info", "file.path", "dir.create", "dir.exists", "list.files", "list.dirs", "getwd", "setwd", "read.table", "read.csv", "read.csv2", "read.delim", "read.delim2", "write.table", "write.csv", "write.csv2", "readLines", "writeLines", "scan", "readRDS", "saveRDS", "load", "save", "save.image", "serialize", "unserialize", "dput", "dump", "sink", "capture.output", "connection", "open", "close", "readBin", "writeBin", "readChar", "writeChar", "url", "file", "gzfile", "bzfile", "xzfile", "unz", "pipe", "fifo", "socketConnection", "rawConnection", "textConnection", "seek", "truncate", "isOpen", "isIncomplete", "flush", "showConnections", "getAllConnections", "closeAllConnections", "pushBack", "pushBackLength", "plot", "hist", "barplot", "boxplot", "pie", "dotchart", "stripchart", "stem", "qqnorm", "qqline", "qqplot", "pairs", "coplot", "matplot", "image", "contour", "persp", "heatmap", "points", "lines", "abline", "segments", "arrows", "rect", "polygon", "text", "mtext", "title", "axis", "box", "grid", "legend", "locator", "identify", "par", "layout", "split.screen", "screen", "erase.screen", "close.screen", "dev.new", "dev.off", "dev.cur", "dev.set", "dev.next", "dev.prev", "dev.list", "dev.copy", "dev.print", "dev.copy2pdf", "dev.copy2eps", "png", "jpeg", "bmp", "tiff", "pdf", "postscript", "svg", "cairo_pdf", "cairo_ps", "setEPS", "setPS", "embedFonts", "lm", "glm", "aov", "anova", "TukeyHSD", "t.test", "chisq.test", "fisher.test", "wilcox.test", "kruskal.test", "cor", "cor.test", "cov", "var.test", "bartlett.test", "leveneTest", "shapiro.test", "ks.test", "prop.test", "binom.test", "mcnemar.test", "pairwise.t.test", "pairwise.wilcox.test", "p.adjust", "power.t.test", "power.prop.test", "power.anova.test"],
        singleLineComment: "#",
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil,
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let lua = LanguageDefinition(
        keywords: ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"],
        types: ["nil", "boolean", "number", "string", "function", "userdata", "thread", "table"],
        builtins: ["assert", "collectgarbage", "dofile", "error", "getmetatable", "ipairs", "load", "loadfile", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen", "rawset", "require", "select", "setmetatable", "tonumber", "tostring", "type", "xpcall", "_G", "_VERSION", "coroutine", "debug", "io", "math", "os", "package", "string", "table", "utf8", "bit32", "math.abs", "math.acos", "math.asin", "math.atan", "math.ceil", "math.cos", "math.deg", "math.exp", "math.floor", "math.fmod", "math.huge", "math.log", "math.max", "math.maxinteger", "math.min", "math.mininteger", "math.modf", "math.pi", "math.rad", "math.random", "math.randomseed", "math.sin", "math.sqrt", "math.tan", "math.tointeger", "math.type", "math.ult", "string.byte", "string.char", "string.dump", "string.find", "string.format", "string.gmatch", "string.gsub", "string.len", "string.lower", "string.match", "string.pack", "string.packsize", "string.rep", "string.reverse", "string.sub", "string.unpack", "string.upper", "table.concat", "table.insert", "table.move", "table.pack", "table.remove", "table.sort", "table.unpack", "io.close", "io.flush", "io.input", "io.lines", "io.open", "io.output", "io.popen", "io.read", "io.stderr", "io.stdin", "io.stdout", "io.tmpfile", "io.type", "io.write", "os.clock", "os.date", "os.difftime", "os.execute", "os.exit", "os.getenv", "os.remove", "os.rename", "os.setlocale", "os.time", "os.tmpname"],
        singleLineComment: "--",
        multiLineCommentStart: "--[[",
        multiLineCommentEnd: "]]",
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let elixir = LanguageDefinition(
        keywords: ["after", "alias", "and", "case", "catch", "cond", "def", "defcallback", "defdelegate", "defexception", "defguard", "defguardp", "defimpl", "defmacro", "defmacrop", "defmodule", "defn", "defnp", "defoverridable", "defp", "defprotocol", "defstruct", "do", "else", "end", "false", "fn", "for", "if", "import", "in", "nil", "not", "or", "quote", "raise", "receive", "require", "rescue", "reraise", "super", "throw", "true", "try", "unless", "unquote", "unquote_splicing", "use", "when", "with"],
        types: ["Atom", "BitString", "Float", "Function", "Integer", "List", "Map", "PID", "Port", "Reference", "Tuple", "String", "Regex", "Range", "MapSet", "Keyword", "Struct", "Protocol", "Behaviour", "GenServer", "Supervisor", "Application", "Agent", "Task", "GenStage", "Flow", "Enum", "Stream", "IO", "File", "Path", "System", "Process", "Node", "Registry", "ETS", "DETS", "Mnesia", "Calendar", "Date", "DateTime", "NaiveDateTime", "Time", "URI", "Version", "Exception", "RuntimeError", "ArgumentError", "ArithmeticError", "SystemLimitError", "Collectable", "Enumerable", "Inspect", "Access", "Macro", "Code", "Module", "Kernel"],
        builtins: ["abs", "apply", "binary_part", "bit_size", "byte_size", "ceil", "div", "elem", "exit", "floor", "function_exported?", "get_and_update_in", "get_in", "hd", "inspect", "is_atom", "is_binary", "is_bitstring", "is_boolean", "is_exception", "is_float", "is_function", "is_integer", "is_list", "is_map", "is_map_key", "is_nil", "is_number", "is_pid", "is_port", "is_reference", "is_struct", "is_tuple", "length", "macro_exported?", "make_ref", "map_size", "max", "min", "node", "not", "pop_in", "put_elem", "put_in", "raise", "rem", "reraise", "round", "self", "send", "spawn", "spawn_link", "spawn_monitor", "struct", "struct!", "throw", "tl", "to_charlist", "to_string", "trunc", "tuple_size", "update_in", "dbg", "tap", "then", "sigil_C", "sigil_D", "sigil_N", "sigil_R", "sigil_S", "sigil_T", "sigil_U", "sigil_W", "sigil_c", "sigil_r", "sigil_s", "sigil_w"],
        singleLineComment: "#",
        multiLineCommentStart: nil,
        multiLineCommentEnd: nil,
        stringDelimiters: ["\"", "'"],
        attributePrefix: "@"
    )
    
    private static let haskell = LanguageDefinition(
        keywords: ["as", "case", "class", "data", "default", "deriving", "do", "else", "family", "forall", "foreign", "hiding", "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "mdo", "module", "newtype", "of", "proc", "qualified", "rec", "then", "type", "where", "True", "False", "Nothing", "Just", "Left", "Right", "LT", "EQ", "GT"],
        types: ["Bool", "Char", "Double", "Float", "Int", "Integer", "String", "IO", "Maybe", "Either", "Ordering", "Read", "Show", "Num", "Eq", "Ord", "Enum", "Bounded", "Real", "Integral", "Fractional", "Floating", "RealFrac", "RealFloat", "Monad", "MonadPlus", "Functor", "Applicative", "Foldable", "Traversable", "Semigroup", "Monoid", "Alternative", "MonadIO", "MonadReader", "MonadWriter", "MonadState", "MonadError", "MonadTrans", "MaybeT", "EitherT", "ReaderT", "WriterT", "StateT", "ExceptT", "Identity", "Const", "Proxy", "Void", "All", "Any", "Sum", "Product", "First", "Last", "Dual", "Endo", "Kleisli", "Arrow", "ArrowChoice", "ArrowApply", "ArrowLoop", "Category", "Comonad", "Bifunctor", "Profunctor", "Contravariant", "Generic", "Typeable", "Data", "Storable", "Ptr", "ForeignPtr", "IORef", "MVar", "STRef", "TVar", "Chan", "QSem", "QSemN", "Async", "Concurrent", "STM", "Map", "Set", "IntMap", "IntSet", "Seq", "Vector", "Array", "Text", "ByteString", "Builder", "Parser", "Parsec", "Attoparsec", "Aeson", "Lens", "Prism", "Iso", "Traversal", "Fold", "Getter", "Setter", "Review"],
        builtins: ["abs", "acos", "acosh", "all", "and", "any", "appendFile", "asin", "asinh", "atan", "atan2", "atanh", "break", "ceiling", "compare", "concat", "concatMap", "const", "cos", "cosh", "curry", "cycle", "decodeFloat", "div", "divMod", "drop", "dropWhile", "either", "elem", "encodeFloat", "enumFrom", "enumFromThen", "enumFromThenTo", "enumFromTo", "error", "even", "exp", "exponent", "fail", "filter", "flip", "floatDigits", "floatRadix", "floatRange", "floor", "fmap", "foldl", "foldl1", "foldr", "foldr1", "fromEnum", "fromInteger", "fromIntegral", "fromRational", "fst", "gcd", "getChar", "getContents", "getLine", "head", "id", "init", "interact", "ioError", "isDenormalized", "isIEEE", "isInfinite", "isNaN", "isNegativeZero", "iterate", "last", "lcm", "length", "lex", "lines", "log", "logBase", "lookup", "map", "mapM", "mapM_", "max", "maxBound", "maximum", "maybe", "min", "minBound", "minimum", "mod", "negate", "not", "notElem", "null", "odd", "or", "otherwise", "pi", "pred", "print", "product", "properFraction", "pure", "putChar", "putStr", "putStrLn", "quot", "quotRem", "read", "readFile", "readIO", "readList", "readLn", "readParen", "reads", "readsPrec", "realToFrac", "recip", "rem", "repeat", "replicate", "return", "reverse", "round", "scaleFloat", "scanl", "scanl1", "scanr", "scanr1", "seq", "sequence", "sequence_", "show", "showChar", "showList", "showParen", "showString", "shows", "showsPrec", "significand", "signum", "sin", "sinh", "snd", "span", "splitAt", "sqrt", "subtract", "succ", "sum", "tail", "take", "takeWhile", "tan", "tanh", "toEnum", "toInteger", "toRational", "traverse", "truncate", "uncurry", "undefined", "unlines", "until", "unwords", "unzip", "unzip3", "userError", "words", "writeFile", "zip", "zip3", "zipWith", "zipWith3"],
        singleLineComment: "--",
        multiLineCommentStart: "{-",
        multiLineCommentEnd: "-}",
        stringDelimiters: ["\"", "'"],
        attributePrefix: nil
    )
    
    private static let objectivec = LanguageDefinition(
        keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Bool", "_Complex", "_Imaginary", "YES", "NO", "nil", "Nil", "NULL", "true", "false", "self", "super", "@interface", "@implementation", "@end", "@protocol", "@optional", "@required", "@property", "@synthesize", "@dynamic", "@class", "@public", "@private", "@protected", "@package", "@try", "@catch", "@finally", "@throw", "@selector", "@encode", "@synchronized", "@autoreleasepool", "@compatibility_alias", "@defs", "in", "out", "inout", "bycopy", "byref", "oneway", "__strong", "__weak", "__unsafe_unretained", "__autoreleasing", "__block", "__bridge", "__bridge_retained", "__bridge_transfer", "atomic", "nonatomic", "retain", "assign", "copy", "readonly", "readwrite", "getter", "setter", "strong", "weak", "unsafe_unretained", "nonnull", "nullable", "null_resettable", "null_unspecified", "_Nonnull", "_Nullable", "_Null_unspecified", "IBOutlet", "IBAction", "IBInspectable", "IB_DESIGNABLE"],
        types: ["id", "Class", "SEL", "IMP", "BOOL", "instancetype", "NSObject", "NSString", "NSMutableString", "NSNumber", "NSInteger", "NSUInteger", "CGFloat", "NSArray", "NSMutableArray", "NSDictionary", "NSMutableDictionary", "NSSet", "NSMutableSet", "NSData", "NSMutableData", "NSDate", "NSURL", "NSError", "NSException", "NSNotification", "NSNotificationCenter", "NSUserDefaults", "NSBundle", "NSFileManager", "NSProcessInfo", "NSThread", "NSRunLoop", "NSTimer", "NSOperation", "NSOperationQueue", "NSLock", "NSCondition", "NSConditionLock", "NSRecursiveLock", "dispatch_queue_t", "dispatch_group_t", "dispatch_semaphore_t", "dispatch_source_t", "dispatch_block_t", "UIView", "UIViewController", "UITableView", "UITableViewCell", "UICollectionView", "UICollectionViewCell", "UILabel", "UIButton", "UITextField", "UITextView", "UIImageView", "UIScrollView", "UIStackView", "UINavigationController", "UITabBarController", "UIAlertController", "UIApplication", "UIWindow", "UIScreen", "UIColor", "UIFont", "UIImage", "CGRect", "CGPoint", "CGSize", "CGAffineTransform", "CALayer", "CAAnimation", "NSLayoutConstraint", "NSAttributedString", "NSMutableAttributedString", "NSParagraphStyle", "NSMutableParagraphStyle", "NSRange", "NSValue", "NSNull", "NSIndexPath", "NSIndexSet", "NSMutableIndexSet", "NSPredicate", "NSSortDescriptor", "NSComparisonResult", "NSEnumerator", "NSFastEnumeration", "NSCoding", "NSSecureCoding", "NSCopying", "NSMutableCopying"],
        builtins: ["alloc", "init", "new", "copy", "mutableCopy", "dealloc", "retain", "release", "autorelease", "retainCount", "description", "debugDescription", "class", "superclass", "isKindOfClass", "isMemberOfClass", "respondsToSelector", "conformsToProtocol", "performSelector", "performSelectorOnMainThread", "performSelectorInBackground", "NSLog", "NSAssert", "NSCAssert", "NSParameterAssert", "NSCParameterAssert", "dispatch_async", "dispatch_sync", "dispatch_after", "dispatch_once", "dispatch_get_main_queue", "dispatch_get_global_queue", "dispatch_queue_create", "dispatch_group_create", "dispatch_group_enter", "dispatch_group_leave", "dispatch_group_wait", "dispatch_group_notify", "dispatch_semaphore_create", "dispatch_semaphore_wait", "dispatch_semaphore_signal", "dispatch_apply", "dispatch_barrier_async", "dispatch_barrier_sync", "@synchronized", "@autoreleasepool", "objc_msgSend", "objc_getClass", "objc_getProtocol", "class_getName", "class_getSuperclass", "class_getInstanceMethod", "class_getClassMethod", "method_getImplementation", "method_setImplementation", "sel_getName", "sel_registerName", "object_getClass", "object_setClass", "objc_allocateClassPair", "objc_registerClassPair", "objc_disposeClassPair", "class_addMethod", "class_addIvar", "class_addProtocol", "class_replaceMethod"],
        singleLineComment: "//",
        multiLineCommentStart: "/*",
        multiLineCommentEnd: "*/",
        stringDelimiters: ["\"", "'"],
        attributePrefix: "@"
    )
    
    private static func getLanguage(_ lang: String) -> LanguageDefinition? {
        switch lang {
        case "swift": return swift
        case "python", "py": return python
        case "javascript", "js", "jsx", "typescript", "ts", "tsx": return javascript
        case "rust", "rs": return rust
        case "go", "golang": return go
        case "html", "htm", "xml": return html
        case "css", "scss", "sass", "less": return css
        case "json": return json
        case "bash", "sh", "zsh", "shell", "fish": return shell
        case "sql", "mysql", "postgresql", "postgres", "sqlite": return sql
        case "java": return java
        case "c", "h": return c
        case "cpp", "c++", "cxx", "cc", "hpp", "hxx", "hh": return cpp
        case "php": return php
        case "kotlin", "kt", "kts": return kotlin
        case "csharp", "c#", "cs": return csharp
        case "ruby", "rb": return ruby
        case "yaml", "yml": return yaml
        case "markdown", "md": return markdown
        case "dart": return dart
        case "scala": return scala
        case "r", "R": return r
        case "lua": return lua
        case "elixir", "ex", "exs": return elixir
        case "haskell", "hs": return haskell
        case "objectivec", "objective-c", "objc", "m", "mm": return objectivec
        default: return nil
        }
    }
    
    // MARK: - Highlighting
    
    static func highlight(_ code: String, language: String, colorScheme: ColorScheme) -> AttributedString {
        let colors = SyntaxColors.forScheme(colorScheme)
        
        guard let lang = getLanguage(language) else {
            var result = AttributedString(code)
            result.foregroundColor = colors.plain
            return result
        }
        
        var result = AttributedString()
        var index = code.startIndex
        
        while index < code.endIndex {
            // Check for comments first
            if let singleComment = lang.singleLineComment, code[index...].hasPrefix(singleComment) {
                let commentStart = index
                // Find end of line
                var commentEnd = index
                while commentEnd < code.endIndex && code[commentEnd] != "\n" {
                    commentEnd = code.index(after: commentEnd)
                }
                var comment = AttributedString(String(code[commentStart..<commentEnd]))
                comment.foregroundColor = colors.comment
                result += comment
                index = commentEnd
                continue
            }
            
            // Check for multi-line comments
            if let multiStart = lang.multiLineCommentStart, let multiEnd = lang.multiLineCommentEnd,
               code[index...].hasPrefix(multiStart) {
                let commentStart = index
                var commentEnd = code.index(index, offsetBy: multiStart.count, limitedBy: code.endIndex) ?? code.endIndex
                while commentEnd < code.endIndex {
                    if code[commentEnd...].hasPrefix(multiEnd) {
                        commentEnd = code.index(commentEnd, offsetBy: multiEnd.count, limitedBy: code.endIndex) ?? code.endIndex
                        break
                    }
                    commentEnd = code.index(after: commentEnd)
                }
                var comment = AttributedString(String(code[commentStart..<commentEnd]))
                comment.foregroundColor = colors.comment
                result += comment
                index = commentEnd
                continue
            }
            
            // Check for strings
            let currentChar = code[index]
            if lang.stringDelimiters.contains(currentChar) {
                let stringStart = index
                var stringEnd = code.index(after: index)
                let delimiter = currentChar
                
                while stringEnd < code.endIndex {
                    if code[stringEnd] == "\\" && code.index(after: stringEnd) < code.endIndex {
                        // Skip escaped character
                        stringEnd = code.index(stringEnd, offsetBy: 2, limitedBy: code.endIndex) ?? code.endIndex
                        continue
                    }
                    if code[stringEnd] == delimiter {
                        stringEnd = code.index(after: stringEnd)
                        break
                    }
                    if code[stringEnd] == "\n" && delimiter != "`" {
                        // End string at newline for non-template strings
                        break
                    }
                    stringEnd = code.index(after: stringEnd)
                }
                
                var str = AttributedString(String(code[stringStart..<stringEnd]))
                str.foregroundColor = colors.string
                result += str
                index = stringEnd
                continue
            }
            
            // Check for attributes (like @State in Swift)
            if let attrPrefix = lang.attributePrefix, currentChar == attrPrefix {
                let attrStart = index
                var attrEnd = code.index(after: index)
                
                while attrEnd < code.endIndex && (code[attrEnd].isLetter || code[attrEnd].isNumber || code[attrEnd] == "_") {
                    attrEnd = code.index(after: attrEnd)
                }
                
                if attrEnd > code.index(after: attrStart) {
                    var attr = AttributedString(String(code[attrStart..<attrEnd]))
                    attr.foregroundColor = colors.attribute
                    result += attr
                    index = attrEnd
                    continue
                }
            }
            
            // Check for numbers
            if currentChar.isNumber || (currentChar == "." && index < code.endIndex && code[code.index(after: index)].isNumber) {
                let numStart = index
                var numEnd = index
                var hasDecimal = currentChar == "."
                var hasExponent = false
                
                while numEnd < code.endIndex {
                    let c = code[numEnd]
                    if c.isNumber {
                        numEnd = code.index(after: numEnd)
                    } else if c == "." && !hasDecimal {
                        hasDecimal = true
                        numEnd = code.index(after: numEnd)
                    } else if (c == "e" || c == "E") && !hasExponent {
                        hasExponent = true
                        numEnd = code.index(after: numEnd)
                        if numEnd < code.endIndex && (code[numEnd] == "+" || code[numEnd] == "-") {
                            numEnd = code.index(after: numEnd)
                        }
                    } else if c == "x" || c == "X" || c == "b" || c == "B" || c == "o" || c == "O" {
                        // Hex, binary, octal prefix
                        numEnd = code.index(after: numEnd)
                    } else if c.isHexDigit && hasExponent == false {
                        numEnd = code.index(after: numEnd)
                    } else if c == "_" {
                        // Numeric separator (Swift, Python, etc.)
                        numEnd = code.index(after: numEnd)
                    } else {
                        break
                    }
                }
                
                if numEnd > numStart {
                    var num = AttributedString(String(code[numStart..<numEnd]))
                    num.foregroundColor = colors.number
                    result += num
                    index = numEnd
                    continue
                }
            }
            
            // Check for identifiers (keywords, types, functions)
            if currentChar.isLetter || currentChar == "_" {
                let wordStart = index
                var wordEnd = index
                
                while wordEnd < code.endIndex && (code[wordEnd].isLetter || code[wordEnd].isNumber || code[wordEnd] == "_") {
                    wordEnd = code.index(after: wordEnd)
                }
                
                let word = String(code[wordStart..<wordEnd])
                var attributed = AttributedString(word)
                
                // Check if followed by ( for function call detection
                var isFunction = false
                var lookAhead = wordEnd
                while lookAhead < code.endIndex && code[lookAhead].isWhitespace {
                    lookAhead = code.index(after: lookAhead)
                }
                if lookAhead < code.endIndex && code[lookAhead] == "(" {
                    isFunction = true
                }
                
                if lang.keywords.contains(word) || lang.keywords.contains(word.lowercased()) {
                    attributed.foregroundColor = colors.keyword
                } else if lang.types.contains(word) {
                    attributed.foregroundColor = colors.type
                } else if lang.builtins.contains(word) || isFunction {
                    attributed.foregroundColor = colors.function
                } else {
                    attributed.foregroundColor = colors.plain
                }
                
                result += attributed
                index = wordEnd
                continue
            }
            
            // Operators and punctuation
            var char = AttributedString(String(currentChar))
            if "+-*/%=<>!&|^~?:".contains(currentChar) {
                char.foregroundColor = colors.operator
            } else {
                char.foregroundColor = colors.plain
            }
            result += char
            index = code.index(after: index)
        }
        
        return result
    }
}

// MARK: - Preview

struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    let horizontalPadding: CGFloat
    var accentColor: Color = AppTheme.accent
    
    private let cellPadding: CGFloat = 12
    private let minColumnWidth: CGFloat = 80
    
    var body: some View {
        if headers.isEmpty {
            EmptyView()
        } else {
            tableContent
        }
    }
    
    // Calculate column widths based on content
    private var columnWidths: [CGFloat] {
        var widths = Array(repeating: minColumnWidth, count: headers.count)
        
        // Measure headers
        for (index, header) in headers.enumerated() {
            let width = measureText(header, weight: .semibold)
            widths[index] = max(widths[index], width)
        }
        
        // Measure all row cells
        for row in rows {
            for (index, cell) in row.enumerated() where index < headers.count {
                let width = measureText(cell, weight: .regular)
                widths[index] = max(widths[index], width)
            }
        }
        
        return widths
    }
    
    private func measureText(_ text: String, weight: Font.Weight) -> CGFloat {
        // Approximate width calculation: ~8pt per character for size 14 font
        let charWidth: CGFloat = weight == .semibold ? 8.5 : 8.0
        return CGFloat(text.count) * charWidth + cellPadding * 2
    }
    
    private var totalTableWidth: CGFloat {
        columnWidths.reduce(0, +)
    }
    
    private var tableContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Left padding spacer
                Color.clear.frame(width: horizontalPadding)
                
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        ForEach(0..<headers.count, id: \.self) { index in
                            MarkdownTextView(text: headers[index], accentColor: accentColor)
                                .fontWeight(.semibold)
                                .frame(width: columnWidths[index], alignment: .leading)
                                .padding(.horizontal, cellPadding)
                                .padding(.vertical, 10)
                        }
                    }
                    .background(AppTheme.cardBackground.opacity(0.6))
                    
                    // Header separator
                    Divider()
                        .background(AppTheme.textSecondary.opacity(0.3))
                    
                    // Data rows
                    ForEach(0..<rows.count, id: \.self) { rowIndex in
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(0..<headers.count, id: \.self) { colIndex in
                                    MarkdownTextView(text: colIndex < rows[rowIndex].count ? rows[rowIndex][colIndex] : "", accentColor: accentColor)
                                        .frame(width: columnWidths[colIndex], alignment: .leading)
                                        .padding(.horizontal, cellPadding)
                                        .padding(.vertical, 8)
                                }
                            }
                            
                            // Row separator (except for last row)
                            if rowIndex < rows.count - 1 {
                                Divider()
                                    .background(AppTheme.textSecondary.opacity(0.15))
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardBackground.opacity(0.3))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.textSecondary.opacity(0.2), lineWidth: 1)
                )
                
                // Right padding spacer
                Color.clear.frame(width: horizontalPadding)
            }
        }
    }
}

// MARK: - Preview

#Preview("Markdown Content") {
    ScrollView {
        MarkdownView("""
        # Welcome to LocalChat
        
        This is a **bold** statement and this is *italic* text. You can also use `inline code` for technical terms.
        
        ## Features
        
        Here's what we support:
        
        - Full markdown rendering
        - **Bold** and *italic* text
        - Code blocks with syntax highlighting
        - Tables and lists
        
        ### Code Example
        
        ```swift
        struct ContentView: View {
            @State private var message = ""
            
            var body: some View {
                Text("Hello, World!")
                    .font(.largeTitle)
                    .foregroundStyle(.primary)
            }
        }
        ```
        
        ### Numbered List
        
        1. First item with explanation
        2. Second item with more details
        3. Third item wrapping up
        
        > This is a blockquote that contains important information that should stand out from the rest of the text.
        
        ---
        
        | Model | Context | Price |
        |-------|---------|-------|
        | **GPT-4** | 128K | *$10/1M* |
        | **Claude** | 200K | *$15/1M* |
        | **Sonar** | `128K` | ~~$5/1M~~ *$1/1M* |
        
        Check out [OpenAI](https://openai.com) for more information.
        """)
        .padding()
    }
    .background(AppTheme.background)
}
