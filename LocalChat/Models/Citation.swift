//
//  Citation.swift
//  LocalChat
//
//  Created by Carl Steen on 21.01.26.
//

import Foundation

/// Represents a citation/source from a Perplexity Sonar response
/// Contains the URL and parsed metadata for display
struct Citation: Identifiable, Hashable {
    let id: Int // 1-indexed citation number (matches [1], [2], etc. in content)
    let url: String
    
    /// The domain/host of the URL (e.g., "wikipedia.org")
    var domain: String {
        guard let url = URL(string: url),
              let host = url.host else {
            return url
        }
        // Remove www. prefix if present
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    
    /// A shortened display title derived from the URL path
    var displayTitle: String {
        guard let url = URL(string: url) else {
            return domain
        }
        
        // Get the last path component, decode it, and clean it up
        var path = url.lastPathComponent
        
        // If it's empty or just a slash, use the domain
        if path.isEmpty || path == "/" {
            return domain
        }
        
        // Remove common file extensions
        if path.hasSuffix(".html") || path.hasSuffix(".htm") || path.hasSuffix(".php") {
            path = String(path.dropLast(path.hasSuffix(".html") ? 5 : 4))
        }
        
        // Decode URL encoding
        path = path.removingPercentEncoding ?? path
        
        // Replace hyphens and underscores with spaces
        path = path.replacingOccurrences(of: "-", with: " ")
        path = path.replacingOccurrences(of: "_", with: " ")
        
        // Capitalize first letter of each word
        let words = path.split(separator: " ").map { word -> String in
            guard let first = word.first else { return String(word) }
            return String(first).uppercased() + word.dropFirst().lowercased()
        }
        
        let title = words.joined(separator: " ")
        
        // Limit length
        if title.count > 50 {
            return String(title.prefix(47)) + "..."
        }
        
        return title.isEmpty ? domain : title
    }
    
    /// The favicon URL for the domain
    var faviconURL: URL? {
        guard let urlObj = URL(string: url),
              let scheme = urlObj.scheme,
              let host = urlObj.host else {
            return nil
        }
        // Use Google's favicon service for reliable favicons
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }
    
    /// Create citations array from a list of URLs
    static func fromURLs(_ urls: [String]) -> [Citation] {
        urls.enumerated().map { index, url in
            Citation(id: index + 1, url: url)
        }
    }
}

// MARK: - Citation Parsing Utilities

enum CitationParser {
    /// Regular expression pattern to match citation references like [1], [2], [1][2], etc.
    static let citationPattern = #"\[(\d+)\]"#
    
    /// Find all citation numbers referenced in a text
    static func findCitationNumbers(in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: citationPattern) else {
            return []
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        var numbers: [Int] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: text),
               let number = Int(text[range]) {
                numbers.append(number)
            }
        }
        
        return Array(Set(numbers)).sorted()
    }
    
    /// Check if a string contains citation references
    static func containsCitations(_ text: String) -> Bool {
        text.range(of: citationPattern, options: .regularExpression) != nil
    }
    
    /// Get ranges of citation references in text for styling
    static func citationRanges(in text: String) -> [(range: Range<String.Index>, number: Int)] {
        guard let regex = try? NSRegularExpression(pattern: citationPattern) else {
            return []
        }
        
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        
        var results: [(Range<String.Index>, Int)] = []
        for match in matches {
            if let range = Range(match.range, in: text),
               let numberRange = Range(match.range(at: 1), in: text),
               let number = Int(text[numberRange]) {
                results.append((range, number))
            }
        }
        
        return results
    }
}
