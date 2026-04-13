//
//  PhotoLibraryService.swift
//  LocalChat
//
//  Created by Carl Steen on 27.01.26.
//

import Photos
import UIKit
import SwiftUI

/// Service for managing photo library access and fetching recent photos
@Observable
@MainActor
final class PhotoLibraryService {
    static let shared = PhotoLibraryService()
    
    private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    private(set) var recentPhotos: [PHAsset] = []
    private(set) var isLoading = false
    
    /// Whether we have full access to the photo library
    var hasFullAccess: Bool {
        authorizationStatus == .authorized
    }
    
    /// Whether we have limited access to the photo library
    var hasLimitedAccess: Bool {
        authorizationStatus == .limited
    }
    
    /// Whether we have any access (full or limited)
    var hasAnyAccess: Bool {
        hasFullAccess || hasLimitedAccess
    }
    
    private init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    /// Request full photo library access
    /// Returns true if access was granted (full or limited)
    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        
        if hasAnyAccess {
            await fetchRecentPhotos()
        }
        
        return hasAnyAccess
    }
    
    /// Check current authorization status without prompting
    func checkStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    /// Fetch the most recent photos from the library
    func fetchRecentPhotos(count: Int = 10) async {
        guard hasAnyAccess else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = count
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        recentPhotos = assets
    }
    
    /// Load a UIImage from a PHAsset
    func loadImage(for asset: PHAsset, targetSize: CGSize = CGSize(width: 200, height: 200)) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    /// Load full resolution UIImage from a PHAsset
    func loadFullResolutionImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            let targetSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    /// Load image data from a PHAsset
    func loadImageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - Camera Permission Service

@Observable
@MainActor
final class CameraService {
    static let shared = CameraService()
    
    private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    
    var hasAccess: Bool {
        authorizationStatus == .authorized
    }
    
    private init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    /// Request camera access
    func requestAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        return granted
    }
    
    /// Check current authorization status
    func checkStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
}
