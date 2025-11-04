//
//  AttachmentChipView.swift
//  osaurus
//
//  View component for displaying attachment chips with thumbnails and remove button.
//

import SwiftUI
import AppKit

/// Displays an attachment as a chip with thumbnail and remove button
struct AttachmentChipView: View {
  let attachment: Attachment
  let onRemove: () -> Void
  
  @Environment(\.theme) private var theme
  @State private var isHovering = false
  
  var body: some View {
    HStack(spacing: 8) {
      // Thumbnail
      if let thumbnail = attachment.thumbnail {
        Image(nsImage: thumbnail)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 44, height: 44)
          .clipShape(RoundedRectangle(cornerRadius: 6))
      } else {
        // Fallback icon
        Image(systemName: "photo")
          .font(.system(size: 20))
          .foregroundColor(theme.secondaryText)
          .frame(width: 44, height: 44)
          .background(theme.secondaryBackground)
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      
      // File info
      VStack(alignment: .leading, spacing: 2) {
        Text(attachment.fileName)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(theme.primaryText)
          .lineLimit(1)
        
        Text(attachment.formattedFileSize)
          .font(.system(size: 10))
          .foregroundColor(theme.secondaryText)
      }
      
      Spacer()
      
      // Remove button
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 16))
          .foregroundColor(isHovering ? theme.primaryText : theme.secondaryText)
      }
      .buttonStyle(.plain)
      .help("Remove attachment")
      .onHover { hovering in
        isHovering = hovering
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(theme.secondaryBackground.opacity(0.5))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(theme.primaryBorder.opacity(0.3), lineWidth: 1)
    )
  }
}

/// Container view for displaying multiple attachment chips
struct AttachmentsContainer: View {
  let attachments: [Attachment]
  let onRemove: (Attachment) -> Void
  
  @Environment(\.theme) private var theme
  
  var body: some View {
    if !attachments.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(attachments) { attachment in
            AttachmentChipView(
              attachment: attachment,
              onRemove: { onRemove(attachment) }
            )
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }
      .frame(height: 70)
      .background(theme.primaryBackground.opacity(0.5))
    }
  }
}

// MARK: - Preview

#Preview {
  let sampleAttachment = Attachment(
    fileURL: URL(fileURLWithPath: "/tmp/sample.jpg"),
    mimeType: "image/jpeg",
    base64Data: "sample_base64_data",
    thumbnail: NSImage(systemSymbolName: "photo", accessibilityDescription: nil),
    fileSize: 1_234_567
  )
  
  return VStack(spacing: 20) {
    AttachmentChipView(
      attachment: sampleAttachment,
      onRemove: { print("Remove tapped") }
    )
    .frame(width: 280)
    
    AttachmentsContainer(
      attachments: [sampleAttachment, sampleAttachment],
      onRemove: { _ in print("Remove from container") }
    )
    .frame(width: 600)
  }
  .padding()
  .background(Color.black)
}
