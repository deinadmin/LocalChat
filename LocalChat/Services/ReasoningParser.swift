//
//  ReasoningParser.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation

/// Parses reasoning/thinking blocks from AI model responses
/// Supports multiple formats used by different models:
/// - <think>...</think> (DeepSeek, Qwen)
/// - <thinking>...</thinking> (Claude)
/// - <Thought>...</Thought> (some models)
enum ReasoningParser {
    
    /// Result of parsing content for reasoning blocks
    struct ParseResult {
        /// The visible content (with thinking blocks removed)
        let displayContent: String
        /// The extracted reasoning content (if any)
        let reasoningContent: String?
        /// Whether we're currently inside a thinking block (for streaming)
        let isInsideThinkingBlock: Bool
        /// Whether the thinking block is complete
        let isThinkingComplete: Bool
    }
    
    /// All supported opening tags (case-insensitive matching)
    private static let openingTags = ["<think>", "<thinking>", "<thought>"]
    private static let closingTags = ["</think>", "</thinking>", "</thought>"]
    
    /// Parse content and extract reasoning blocks
    /// - Parameter content: The raw content from the AI model
    /// - Returns: ParseResult with separated display and reasoning content
    static func parse(_ content: String) -> ParseResult {
        let lowercased = content.lowercased()
        
        // Find all thinking block boundaries
        var openingIndex: String.Index?
        var openingTagLength = 0
        var closingIndex: String.Index?
        var closingTagLength = 0
        
        // Find the first opening tag
        for tag in openingTags {
            if let range = lowercased.range(of: tag) {
                if openingIndex == nil || range.lowerBound < openingIndex! {
                    openingIndex = range.lowerBound
                    openingTagLength = tag.count
                }
            }
        }
        
        // Find the corresponding closing tag
        for tag in closingTags {
            if let range = lowercased.range(of: tag) {
                if closingIndex == nil || range.lowerBound < closingIndex! {
                    closingIndex = range.lowerBound
                    closingTagLength = tag.count
                }
            }
        }
        
        // Case 1: No thinking block found
        guard let openIdx = openingIndex else {
            return ParseResult(
                displayContent: content,
                reasoningContent: nil,
                isInsideThinkingBlock: false,
                isThinkingComplete: false
            )
        }
        
        // Case 2: Opening tag found but no closing tag (still streaming thinking)
        guard let closeIdx = closingIndex, closeIdx > openIdx else {
            // Extract what we have so far as reasoning
            let afterOpenTag = content.index(openIdx, offsetBy: openingTagLength)
            let reasoningSoFar = String(content[afterOpenTag...])
            
            // Content before the thinking block is display content
            let displayBefore = String(content[..<openIdx])
            
            return ParseResult(
                displayContent: displayBefore.trimmingCharacters(in: .whitespacesAndNewlines),
                reasoningContent: reasoningSoFar.trimmingCharacters(in: .whitespacesAndNewlines),
                isInsideThinkingBlock: true,
                isThinkingComplete: false
            )
        }
        
        // Case 3: Complete thinking block found
        let afterOpenTag = content.index(openIdx, offsetBy: openingTagLength)
        let reasoningContent = String(content[afterOpenTag..<closeIdx])
        
        // Build display content (before + after thinking block)
        let displayBefore = String(content[..<openIdx])
        let afterCloseTag = content.index(closeIdx, offsetBy: closingTagLength)
        let displayAfter = String(content[afterCloseTag...])
        
        let displayContent = (displayBefore + displayAfter).trimmingCharacters(in: .whitespacesAndNewlines)
        
        return ParseResult(
            displayContent: displayContent,
            reasoningContent: reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines),
            isInsideThinkingBlock: false,
            isThinkingComplete: true
        )
    }
    
    /// Check if content starts with a thinking block (for detecting reasoning models)
    static func startsWithThinkingBlock(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return openingTags.contains { trimmed.hasPrefix($0) }
    }
    
    /// Check if we're currently inside an unclosed thinking block
    static func isInsideThinkingBlock(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        
        var openCount = 0
        var closeCount = 0
        
        for tag in openingTags {
            openCount += lowercased.components(separatedBy: tag).count - 1
        }
        
        for tag in closingTags {
            closeCount += lowercased.components(separatedBy: tag).count - 1
        }
        
        return openCount > closeCount
    }
}
