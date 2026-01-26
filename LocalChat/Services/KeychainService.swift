//
//  KeychainService.swift
//  LocalChat
//
//  Created by Carl Steen on 20.01.26.
//

import Foundation
import Security

/// Secure storage service for API keys using iOS Keychain
actor KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.localchat.apikeys"
    
    private init() {}
    
    // MARK: - API Key Management
    
    /// Save an API key for a provider
    func saveAPIKey(_ key: String, for provider: AIProviderType) throws {
        let account = provider.rawValue
        
        // Delete existing key first
        try? deleteAPIKey(for: provider)
        
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }
    
    /// Retrieve an API key for a provider
    func getAPIKey(for provider: AIProviderType) throws -> String? {
        let account = provider.rawValue
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }
            return key
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw KeychainError.readFailed(status: status)
        }
    }
    
    /// Delete an API key for a provider
    func deleteAPIKey(for provider: AIProviderType) throws {
        let account = provider.rawValue
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
    
    /// Check if an API key exists for a provider
    func hasAPIKey(for provider: AIProviderType) -> Bool {
        do {
            return try getAPIKey(for: provider) != nil
        } catch {
            return false
        }
    }
    
    // MARK: - Custom Endpoint Keys
    
    /// Save an API key for a custom endpoint
    func saveCustomAPIKey(_ key: String, identifier: String) throws {
        let account = "custom_\(identifier)"
        
        // Delete existing key first
        try? deleteCustomAPIKey(identifier: identifier)
        
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }
    
    /// Retrieve an API key for a custom endpoint
    func getCustomAPIKey(identifier: String) throws -> String? {
        let account = "custom_\(identifier)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }
            return key
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw KeychainError.readFailed(status: status)
        }
    }
    
    /// Delete an API key for a custom endpoint
    func deleteCustomAPIKey(identifier: String) throws {
        let account = "custom_\(identifier)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
    
    // MARK: - Bulk Operations
    
    /// Get all stored provider types that have API keys
    func getAllStoredProviders() -> [AIProviderType] {
        AIProviderType.allCases.filter { hasAPIKey(for: $0) }
    }
    
    /// Delete all stored API keys
    func deleteAllAPIKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode API key"
        case .decodingFailed:
            return "Failed to decode API key"
        case .saveFailed(let status):
            return "Failed to save API key (error: \(status))"
        case .readFailed(let status):
            return "Failed to read API key (error: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete API key (error: \(status))"
        }
    }
}

// MARK: - API Key Info (for UI display)

struct APIKeyInfo: Identifiable {
    let id: String
    let provider: AIProviderType
    let maskedKey: String
    let lastUpdated: Date?
    
    init(provider: AIProviderType, key: String, lastUpdated: Date? = nil) {
        self.id = provider.rawValue
        self.provider = provider
        self.maskedKey = Self.maskKey(key)
        self.lastUpdated = lastUpdated
    }
    
    private static func maskKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "*", count: key.count) }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        let middle = String(repeating: "*", count: min(key.count - 8, 16))
        return "\(prefix)\(middle)\(suffix)"
    }
}
