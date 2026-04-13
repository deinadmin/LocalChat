//
//  AdditionalContextSheet.swift
//  LocalChat
//
//  Created by Carl Steen on 27.01.26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Attachment type that can be added to a chat message
struct ChatAttachment: Identifiable, Equatable {
    let id = UUID()
    let type: AttachmentType
    let data: Data
    let filename: String
    let mimeType: String
    
    enum AttachmentType: Equatable {
        case image
        case file
    }
    
    /// Create a thumbnail image for display
    var thumbnailImage: UIImage? {
        guard type == .image else { return nil }
        return UIImage(data: data)
    }
}

/// Sheet for adding additional context to chat (photos, files, etc.)
struct AdditionalContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var photoLibraryService = PhotoLibraryService.shared
    @State private var cameraService = CameraService.shared
    
    // Photo picker
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    
    // Camera
    @State private var showCamera = false
    
    // File picker
    @State private var showFilePicker = false
    
    // Selected attachments to return
    let onAttachmentsSelected: ([ChatAttachment]) -> Void
    
    // Web search toggle callback
    let onWebSearchToggled: ((Bool) -> Void)?
    
    // Current web search state (passed in from parent)
    @Binding var isWebSearchEnabled: Bool
    
    // Track loaded thumbnails for recent photos
    @State private var recentPhotoThumbnails: [String: UIImage] = [:]
    @State private var selectedPhotoAssets: Set<String> = []
    
    /// Initialize with attachments callback only (web search disabled)
    init(onAttachmentsSelected: @escaping ([ChatAttachment]) -> Void) {
        self.onAttachmentsSelected = onAttachmentsSelected
        self.onWebSearchToggled = nil
        self._isWebSearchEnabled = .constant(false)
    }
    
    /// Initialize with both attachments and web search toggle support
    init(
        isWebSearchEnabled: Binding<Bool>,
        onWebSearchToggled: @escaping (Bool) -> Void,
        onAttachmentsSelected: @escaping ([ChatAttachment]) -> Void
    ) {
        self.onAttachmentsSelected = onAttachmentsSelected
        self.onWebSearchToggled = onWebSearchToggled
        self._isWebSearchEnabled = isWebSearchEnabled
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Main action buttons section
                        mainActionsSection
                        
                        // Divider
                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                        
                        // Additional options
                        additionalOptionsSection
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Add Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                }
                
                // Show Done button when photos are selected
                if !selectedPhotoAssets.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add (\(selectedPhotoAssets.count))") {
                            addSelectedPhotos()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .task {
                photoLibraryService.checkStatus()
                cameraService.checkStatus()
                if photoLibraryService.hasAnyAccess {
                    await photoLibraryService.fetchRecentPhotos()
                    await loadThumbnails()
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, items in
                Task {
                    await processSelectedPhotos(items)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileSelection(result)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { image in
                    handleCapturedImage(image)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Main Actions Section
    
    @ViewBuilder
    private var mainActionsSection: some View {
        if photoLibraryService.hasAnyAccess {
            // Show recent photos with inline buttons
            VStack(alignment: .leading, spacing: 12) {
                // Header with title
                HStack {
                    Text("Photos")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Button("All Photos") {
                        showPhotoPicker = true
                    }
                    .font(.system(size: 15))
                }
                .padding(.horizontal, 20)
                
                // Horizontal scroll with camera button and recent photos
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Camera button
                        Button {
                            handleCameraAction()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .frame(width: 80, height: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.cardBackground)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Recent photos
                        ForEach(photoLibraryService.recentPhotos, id: \.localIdentifier) { asset in
                            RecentPhotoButton(
                                asset: asset,
                                thumbnail: recentPhotoThumbnails[asset.localIdentifier],
                                isSelected: selectedPhotoAssets.contains(asset.localIdentifier)
                            ) {
                                togglePhotoSelection(asset)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // Files button below photos
            HStack(spacing: 12) {
                actionButton(
                    icon: "folder.fill",
                    title: "Files",
                    action: { showFilePicker = true }
                )
            }
            .padding(.horizontal, 20)
        } else {
            // No permission - show three big buttons
            HStack(spacing: 12) {
                bigActionButton(
                    icon: "camera.fill",
                    title: "Camera",
                    action: handleCameraAction
                )
                
                bigActionButton(
                    icon: "photo.on.rectangle",
                    title: "Photos",
                    action: handlePhotosAction
                )
                
                bigActionButton(
                    icon: "folder.fill",
                    title: "Files",
                    action: { showFilePicker = true }
                )
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Additional Options Section
    
    private var additionalOptionsSection: some View {
        VStack(spacing: 0) {
            // Web Search toggle row
            webSearchToggleRow
            
            Divider()
                .padding(.leading, 56)
            
            additionalOptionRow(
                icon: "brain.head.profile",
                title: "Quiz",
                description: "Test your knowledge on a topic",
                action: { /* Placeholder */ }
            )
            
            Divider()
                .padding(.leading, 56)
            
            additionalOptionRow(
                icon: "doc.text.magnifyingglass",
                title: "Deep Research",
                description: "In-depth analysis and research",
                action: { /* Placeholder */ }
            )
            
            Divider()
                .padding(.leading, 56)
            
            additionalOptionRow(
                icon: "text.page.badge.magnifyingglass",
                title: "Summarize",
                description: "Summarize long documents",
                action: { /* Placeholder */ }
            )
            
            Divider()
                .padding(.leading, 56)
            
            additionalOptionRow(
                icon: "translate",
                title: "Translate",
                description: "Translate text between languages",
                action: { /* Placeholder */ }
            )
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Component Views
    
    /// Web Search toggle row with switch instead of button
    private var webSearchToggleRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundStyle(isWebSearchEnabled ? Color.accentColor : AppTheme.textSecondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Web Search")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Text("Search the web for up-to-date answers")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isWebSearchEnabled)
                .labelsHidden()
                .onChange(of: isWebSearchEnabled) { _, newValue in
                    onWebSearchToggled?(newValue)
                }
        }
        .padding(.vertical, 12)
    }
    
    private func bigActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
        }
        .buttonStyle(ScalableButtonStyle())
    }
    
    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 32)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardBackground)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func additionalOptionRow(icon: String, title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func handleCameraAction() {
        Task {
            if cameraService.hasAccess {
                showCamera = true
            } else {
                let granted = await cameraService.requestAccess()
                if granted {
                    showCamera = true
                }
            }
        }
    }
    
    private func handlePhotosAction() {
        Task {
            if photoLibraryService.hasAnyAccess {
                showPhotoPicker = true
            } else {
                // Try to request full access
                let granted = await photoLibraryService.requestAccess()
                if granted {
                    // Reload the view to show recent photos
                    await photoLibraryService.fetchRecentPhotos()
                    await loadThumbnails()
                } else {
                    // Even without permission, show the system picker which works with limited/no access
                    showPhotoPicker = true
                }
            }
        }
    }
    
    private func togglePhotoSelection(_ asset: PHAsset) {
        if selectedPhotoAssets.contains(asset.localIdentifier) {
            selectedPhotoAssets.remove(asset.localIdentifier)
        } else {
            selectedPhotoAssets.insert(asset.localIdentifier)
        }
    }
    
    private func addSelectedPhotos() {
        Task {
            var attachments: [ChatAttachment] = []
            
            for assetId in selectedPhotoAssets {
                if let asset = photoLibraryService.recentPhotos.first(where: { $0.localIdentifier == assetId }),
                   let data = await photoLibraryService.loadImageData(for: asset) {
                    let attachment = ChatAttachment(
                        type: .image,
                        data: data,
                        filename: "photo_\(UUID().uuidString.prefix(8)).jpg",
                        mimeType: "image/jpeg"
                    )
                    attachments.append(attachment)
                }
            }
            
            if !attachments.isEmpty {
                onAttachmentsSelected(attachments)
                dismiss()
            }
        }
    }
    
    private func loadThumbnails() async {
        for asset in photoLibraryService.recentPhotos {
            if let image = await photoLibraryService.loadImage(for: asset, targetSize: CGSize(width: 160, height: 160)) {
                recentPhotoThumbnails[asset.localIdentifier] = image
            }
        }
    }
    
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var attachments: [ChatAttachment] = []
        
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let attachment = ChatAttachment(
                    type: .image,
                    data: data,
                    filename: "photo_\(UUID().uuidString.prefix(8)).jpg",
                    mimeType: "image/jpeg"
                )
                attachments.append(attachment)
            }
        }
        
        if !attachments.isEmpty {
            onAttachmentsSelected(attachments)
            dismiss()
        }
    }
    
    private func handleCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let attachment = ChatAttachment(
            type: .image,
            data: data,
            filename: "camera_\(UUID().uuidString.prefix(8)).jpg",
            mimeType: "image/jpeg"
        )
        
        onAttachmentsSelected([attachment])
        dismiss()
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var attachments: [ChatAttachment] = []
            
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                if let data = try? Data(contentsOf: url) {
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let attachment = ChatAttachment(
                        type: .file,
                        data: data,
                        filename: url.lastPathComponent,
                        mimeType: mimeType
                    )
                    attachments.append(attachment)
                }
            }
            
            if !attachments.isEmpty {
                onAttachmentsSelected(attachments)
                dismiss()
            }
            
        case .failure:
            break
        }
    }
}

// MARK: - Recent Photo Button

struct RecentPhotoButton: View {
    let asset: PHAsset
    let thumbnail: UIImage?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardBackground)
                        .frame(width: 80, height: 80)
                        .overlay {
                            ProgressView()
                        }
                }
                
                // Selection indicator
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.8), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .frame(width: 24, height: 24)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera Capture View

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        
        init(_ parent: CameraCaptureView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    AdditionalContextSheet { attachments in
        print("Selected \(attachments.count) attachments")
    }
}
