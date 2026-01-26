//
//  LocalChatApp.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import SwiftUI
import SwiftData

@main
struct LocalChatApp: App {
    @State private var appearanceManager = AppearanceManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Chat.self,
            Message.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration fails, try to delete the store and recreate
            print("Failed to load model container: \(error)")
            print("Attempting to delete existing store and recreate...")
            
            // Get the default store URL
            let url = URL.applicationSupportDirectory
                .appending(path: "default.store")
            
            // Try to delete existing store files
            let fileManager = FileManager.default
            let storeURLs = [
                url,
                url.appendingPathExtension("shm"),
                url.appendingPathExtension("wal")
            ]
            
            for storeURL in storeURLs {
                try? fileManager.removeItem(at: storeURL)
            }
            
            // Try again with fresh store
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after cleanup: \(error)")
            }
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceManager.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
