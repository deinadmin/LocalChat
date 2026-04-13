//
//  ContentView.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import SwiftUI
import SwiftData

enum SidebarPage {
    case chats
    case modelStore
    case settings
}

/// Navigation destination for new chat (before it's persisted)
struct NewChatDestination: Hashable {}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var chatStore: ChatStore?
    @State private var showSidebar = false
    @State private var selectedPage: SidebarPage = .chats
    
    var body: some View {
        Group {
            if let store = chatStore {
                MainContentView(showSidebar: $showSidebar, selectedPage: $selectedPage)
                    .environment(store)
            } else {
                ProgressView("Loading...")
                    .onAppear {
                        chatStore = ChatStore(modelContext: modelContext)
                    }
            }
        }
    }
}

// MARK: - Main Content View with Custom Sidebar

struct MainContentView: View {
    @Environment(ChatStore.self) private var chatStore
    @Binding var showSidebar: Bool
    @Binding var selectedPage: SidebarPage
    
    // Navigation path for programmatic navigation
    @State private var navigationPath = NavigationPath()
    
    // Sidebar takes 80% of the screen, main content shows 20% when sidebar is open
    private let sidebarWidthRatio: CGFloat = 0.80
    
    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = geometry.size.width * sidebarWidthRatio
            let currentOffset: CGFloat = showSidebar ? sidebarWidth : 0
            
            ZStack(alignment: .leading) {
                // Main content (chat list or chat detail) with overlay
                ZStack {
                    mainContent
                    
                    // Dim overlay - opacity based on current offset
                    Color.black
                        .opacity(Double(currentOffset / sidebarWidth) * 0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeSidebar()
                        }
                        .allowsHitTesting(currentOffset > 0)
                }
                .frame(width: geometry.size.width)
                .offset(x: currentOffset)
                
                // Sidebar
                SidebarView(showSidebar: $showSidebar, selectedPage: $selectedPage, navigationPath: $navigationPath)
                    .frame(width: sidebarWidth)
                    .offset(x: currentOffset - sidebarWidth)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSidebar)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: showSidebar)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToModelStore"))) { _ in
            selectedPage = .modelStore
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        switch selectedPage {
        case .chats:
            NavigationStack(path: $navigationPath) {
                ChatListView(showSidebar: $showSidebar, navigationPath: $navigationPath)
                    .navigationDestination(for: Chat.self) { chat in
                        ChatDetailView(chat: chat, navigationPath: $navigationPath)
                    }
                    .navigationDestination(for: NewChatDestination.self) { _ in
                        NewChatView(navigationPath: $navigationPath)
                    }
            }
        case .modelStore:
            NavigationStack {
                ModelStoreView(showSidebar: $showSidebar) { newChat in
                    // Switch to chats page and navigate to the new chat
                    selectedPage = .chats
                    // Small delay to allow page switch animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        navigationPath.append(newChat)
                    }
                }
            }
        case .settings:
            NavigationStack {
                SettingsView(showSidebar: $showSidebar)
            }
        }
    }
    
    private func closeSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showSidebar = false
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Environment(ChatStore.self) private var chatStore
    @Binding var showSidebar: Bool
    @Binding var selectedPage: SidebarPage
    @Binding var navigationPath: NavigationPath
    
    var starredChats: [Chat] {
        chatStore.chats.filter { $0.isStarred }
    }
    
    var recentChats: [Chat] {
        Array(chatStore.chats.prefix(5))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("LocalChat")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 24)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Main navigation
                    sidebarButton(title: "Chats", icon: "bubble.left.and.bubble.right", isSelected: selectedPage == .chats) {
                        selectedPage = .chats
                        navigationPath = NavigationPath() // Clear navigation to go to root
                        closeSidebar()
                    }
                    
                    sidebarButton(title: "Model Store", icon: "square.grid.2x2", isSelected: selectedPage == .modelStore) {
                        selectedPage = .modelStore
                        closeSidebar()
                    }
                    
                    sidebarButton(title: "Settings", icon: "gearshape", isSelected: selectedPage == .settings) {
                        selectedPage = .settings
                        closeSidebar()
                    }
                    
                    // Starred section
                    if !starredChats.isEmpty {
                        sectionHeader("Starred")
                        
                        ForEach(starredChats) { chat in
                            sidebarChatRow(chat: chat)
                        }
                    }
                    
                    // Recents section
                    if !recentChats.isEmpty {
                        sectionHeader("Recents")
                        
                        ForEach(recentChats) { chat in
                            sidebarChatRow(chat: chat)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(AppTheme.background)
    }
    
    private func sidebarButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.iconDefault)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardBackground)
                        .padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
    
    private func sidebarChatRow(chat: Chat) -> some View {
        Button {
            // Switch to chats page and navigate to the chat
            selectedPage = .chats
            // Clear the navigation path and navigate to this chat
            navigationPath = NavigationPath()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                navigationPath.append(chat)
            }
            closeSidebar()
        } label: {
            Text(chat.title)
                .font(.system(size: 17))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
    
    private func closeSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showSidebar = false
        }
    }
}

// MARK: - Chat List View

struct ChatListView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showSidebar: Bool
    @Binding var navigationPath: NavigationPath
    
    @State private var searchText = ""
    @State private var chatToDelete: Chat?
    @State private var showDeleteConfirmation = false
    
    // Height for floating bottom bar
    private let bottomBarHeight: CGFloat = 48
    private let bottomBarPadding: CGFloat = 16
    
    var filteredChats: [Chat] {
        if searchText.isEmpty {
            return chatStore.chats
        }
        return chatStore.chats.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.background
                .ignoresSafeArea()
            
            // Content
            if chatStore.chats.isEmpty {
                emptyStateView
            } else {
                chatListContent
            }
            
            // Floating bottom bar
            floatingBottomBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .medium))
                }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: showSidebar)
            }
            
            ToolbarItem(placement: .principal) {
                Text("Chats")
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .alert("Delete Chat", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                chatToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let chat = chatToDelete {
                    chatStore.deleteChat(chat)
                }
                chatToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this chat?")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            SparkleIcon(size: 50)
            
            Text("Start a new chat")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
            
            Text("Tap the + button below to begin")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
            
            Spacer()
            
            // Space for floating bar
            Color.clear.frame(height: bottomBarHeight + bottomBarPadding * 2)
        }
    }
    
    private var chatListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredChats) { chat in
                    NavigationLink(value: chat) {
                        ChatRowView(chat: chat)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            chatToDelete = chat
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 8)
            // Extra bottom padding for floating bar
            .padding(.bottom, bottomBarHeight + bottomBarPadding * 2 + 8)
        }
    }
    
    private var floatingBottomBar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textSecondary)
                
                TextField("Search", text: $searchText)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 16)
            .frame(height: bottomBarHeight)
            .glassEffect(.regular.interactive(), in: Capsule())
            
            // New chat FAB - same height as search field, circular with accent tint
            Button {
                navigationPath.append(NewChatDestination())
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.accent.contrastingTextColor)
                    .frame(width: bottomBarHeight, height: bottomBarHeight)
            }
            .glassEffect(.regular.tint(AppTheme.accent).interactive(), in: .circle)
        }
        .padding(.horizontal, bottomBarPadding)
        .padding(.bottom, bottomBarPadding)
    }
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showSidebar.toggle()
        }
    }
}

// MARK: - Chat Row View

struct ChatRowView: View {
    @Environment(ChatStore.self) private var chatStore
    let chat: Chat
    
    private var isGenerating: Bool {
        chatStore.isGenerating(chatId: chat.id)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text(timeAgoText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            Spacer()
            
            // Show progress indicator when generating
            if isGenerating {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.trailing, 8)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
    
    private var timeAgoText: String {
        let secondsAgo = Date().timeIntervalSince(chat.updatedAt)
        
        // Show "Just now" for very recent updates (less than 30 seconds)
        if secondsAgo < 30 {
            return "Just now"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: chat.updatedAt, relativeTo: Date())
    }
}

// MARK: - Empty Chat View

struct EmptyChatView: View {
    @Environment(ChatStore.self) private var chatStore
    
    var body: some View {
        VStack(spacing: 24) {
            SparkleIcon(size: 60)
            
            Text(GreetingGenerator.greeting())
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Text("Select a chat or start a new one")
                .font(.system(size: 17))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Chat.self, Message.self, configurations: config)
    
    return ContentView()
        .modelContainer(container)
}
