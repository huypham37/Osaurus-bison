//
//  Attachment.swift
//  osaurus
//
//  Created for multimodal chat support with vision-capable models.
//

import Foundation
import AppKit

/// Represents a file attachment (image) for multimodal chat
struct Attachment: Identifiable, Equatable {
  let id: UUID
  let fileURL: URL
  let mimeType: String
  let base64Data: String
  let thumbnail: NSImage?
  let fileSize: Int
  
  init(
    id: UUID = UUID(),
    fileURL: URL,
    mimeType: String,
    base64Data: String,
    thumbnail: NSImage? = nil,
    fileSize: Int
  ) {
    self.id = id
    self.fileURL = fileURL
    self.mimeType = mimeType
    self.base64Data = base64Data
    self.thumbnail = thumbnail
    self.fileSize = fileSize
  }
  
  /// Check if two attachments are equal (by ID)
  static func == (lhs: Attachment, rhs: Attachment) -> Bool {
    lhs.id == rhs.id
  }
  
  /// Human-readable file size
  var formattedFileSize: String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(fileSize))
  }
  
  /// File extension
  var fileExtension: String {
    fileURL.pathExtension.lowercased()
  }
  
  /// Display name for the file
  var fileName: String {
    fileURL.lastPathComponent
  }
}

/// Supported image formats for attachments
enum AttachmentFormat: String, CaseIterable {
  case jpeg = "jpg"
  case png = "png"
  case webp = "webp"
  
  var mimeType: String {
    switch self {
    case .jpeg: return "image/jpeg"
    case .png: return "image/png"
    case .webp: return "image/webp"
    }
  }
  
  static func from(extension ext: String) -> AttachmentFormat? {
    // Handle both "jpg" and "jpeg"
    let normalized = ext.lowercased()
    if normalized == "jpeg" || normalized == "jpg" {
      return .jpeg
    }
    return AttachmentFormat.allCases.first { $0.rawValue == normalized }
  }
}

/// Errors that can occur during attachment processing
enum AttachmentError: LocalizedError {
  case unsupportedFormat(String)
  case fileTooLarge(Int, max: Int)
  case cannotReadFile
  case invalidImageData
  case compressionFailed
  
  var errorDescription: String? {
    switch self {
    case .unsupportedFormat(let ext):
      return "Unsupported file format: .\(ext). Supported formats: .jpg, .png, .webp"
    case .fileTooLarge(let size, let max):
      let formatter = ByteCountFormatter()
      formatter.allowedUnits = [.useMB]
      formatter.countStyle = .file
      let sizeStr = formatter.string(fromByteCount: Int64(size))
      let maxStr = formatter.string(fromByteCount: Int64(max))
      return "File size \(sizeStr) exceeds maximum allowed size of \(maxStr)"
    case .cannotReadFile:
      return "Cannot read file. Please check file permissions."
    case .invalidImageData:
      return "Invalid image data. The file may be corrupted."
    case .compressionFailed:
      return "Failed to compress image. Please try a different file."
    }
  }
}
