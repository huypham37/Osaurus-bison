//
//  AttachmentService.swift
//  osaurus
//
//  Service for handling file attachments (images) for multimodal chat.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Service for managing file attachments in chat
@MainActor
final class AttachmentService {
  
  // MARK: - Configuration
  
  /// Maximum file size in bytes (5MB)
  static let maxFileSize = 5 * 1024 * 1024
  
  /// Maximum image dimension for compression
  static let maxImageDimension: CGFloat = 2048
  
  /// Thumbnail size
  static let thumbnailSize = NSSize(width: 80, height: 80)
  
  // MARK: - Public Methods
  
  /// Present file picker and process selected image
  /// - Returns: Processed attachment or nil if cancelled
  static func pickImage() async throws -> Attachment? {
    return try await withCheckedThrowingContinuation { continuation in
      let panel = NSOpenPanel()
      panel.title = "Select an Image"
      panel.message = "Choose an image to attach to your message"
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      
      // Configure allowed file types
      panel.allowedContentTypes = [
        .jpeg,
        .png,
        UTType(filenameExtension: "webp") ?? .image
      ]
      
      panel.begin { response in
        if response == .OK, let url = panel.url {
          Task {
            do {
              let attachment = try await self.processImage(url: url)
              continuation.resume(returning: attachment)
            } catch {
              continuation.resume(throwing: error)
            }
          }
        } else {
          // User cancelled
          continuation.resume(returning: nil)
        }
      }
    }
  }
  
  // MARK: - Image Processing
  
  /// Process an image file into an Attachment
  /// - Parameter url: File URL of the image
  /// - Returns: Processed attachment
  static func processImage(url: URL) async throws -> Attachment {
    // Validate file format
    let fileExtension = url.pathExtension.lowercased()
    guard let format = AttachmentFormat.from(extension: fileExtension) else {
      throw AttachmentError.unsupportedFormat(fileExtension)
    }
    
    // Check file size
    let fileSize = try getFileSize(url: url)
    guard fileSize <= maxFileSize else {
      throw AttachmentError.fileTooLarge(fileSize, max: maxFileSize)
    }
    
    // Load image data
    guard let imageData = try? Data(contentsOf: url) else {
      throw AttachmentError.cannotReadFile
    }
    
    guard let image = NSImage(data: imageData) else {
      throw AttachmentError.invalidImageData
    }
    
    // Compress if needed
    let processedData: Data
    if fileSize > maxFileSize / 2 || needsResizing(image: image) {
      processedData = try compressImage(image: image, format: format)
    } else {
      processedData = imageData
    }
    
    // Encode to base64
    let base64String = processedData.base64EncodedString()
    
    // Generate thumbnail
    let thumbnail = generateThumbnail(image: image)
    
    return Attachment(
      fileURL: url,
      mimeType: format.mimeType,
      base64Data: base64String,
      thumbnail: thumbnail,
      fileSize: processedData.count
    )
  }
  
  // MARK: - Private Helpers
  
  /// Get file size in bytes
  private static func getFileSize(url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let fileSize = attributes[.size] as? Int else {
      throw AttachmentError.cannotReadFile
    }
    return fileSize
  }
  
  /// Check if image needs resizing
  private static func needsResizing(image: NSImage) -> Bool {
    return image.size.width > maxImageDimension || image.size.height > maxImageDimension
  }
  
  /// Compress and resize image if needed
  private static func compressImage(image: NSImage, format: AttachmentFormat) throws -> Data {
    let targetSize = calculateTargetSize(original: image.size, max: maxImageDimension)
    
    guard let resized = resizeImage(image: image, to: targetSize) else {
      throw AttachmentError.compressionFailed
    }
    
    // Convert to appropriate format
    guard let tiffData = resized.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData) else {
      throw AttachmentError.compressionFailed
    }
    
    let compressionFactor: CGFloat = 0.8
    var imageData: Data?
    
    switch format {
    case .jpeg:
      imageData = bitmapImage.representation(
        using: .jpeg,
        properties: [.compressionFactor: compressionFactor]
      )
    case .png:
      imageData = bitmapImage.representation(using: .png, properties: [:])
    case .webp:
      // WebP not natively supported, convert to JPEG
      imageData = bitmapImage.representation(
        using: .jpeg,
        properties: [.compressionFactor: compressionFactor]
      )
    }
    
    guard let data = imageData else {
      throw AttachmentError.compressionFailed
    }
    
    return data
  }
  
  /// Resize image maintaining aspect ratio
  private static func resizeImage(image: NSImage, to targetSize: NSSize) -> NSImage? {
    let newImage = NSImage(size: targetSize)
    newImage.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: targetSize),
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1.0
    )
    newImage.unlockFocus()
    return newImage
  }
  
  /// Calculate target size maintaining aspect ratio
  private static func calculateTargetSize(original: NSSize, max: CGFloat) -> NSSize {
    let aspectRatio = original.width / original.height
    
    if original.width > original.height {
      // Landscape
      if original.width > max {
        return NSSize(width: max, height: max / aspectRatio)
      }
    } else {
      // Portrait or square
      if original.height > max {
        return NSSize(width: max * aspectRatio, height: max)
      }
    }
    
    return original
  }
  
  /// Generate thumbnail from image
  private static func generateThumbnail(image: NSImage) -> NSImage? {
    let targetSize = thumbnailSize
    let aspectRatio = image.size.width / image.size.height
    
    // Calculate thumbnail size maintaining aspect ratio
    var thumbSize = targetSize
    if aspectRatio > 1 {
      thumbSize.height = targetSize.width / aspectRatio
    } else {
      thumbSize.width = targetSize.height * aspectRatio
    }
    
    return resizeImage(image: image, to: thumbSize)
  }
  
  /// Create data URI for base64 image
  static func createDataURI(base64: String, mimeType: String) -> String {
    return "data:\(mimeType);base64,\(base64)"
  }
}
