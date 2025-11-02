//
//  ResponsiveTypography.swift
//  osaurus
//
//  Scales font sizes based on container width for comfortable reading
//

import SwiftUI

enum Typography {
  static func scale(for width: CGFloat) -> CGFloat {
    // Map 640→0.95, 1024→1.0, 1400→1.1 (reduced scaling for more compact UI)
    let clamped = max(640.0, min(1400.0, width))
    let s = (clamped - 640.0) / (1400.0 - 640.0)
    return 0.95 + s * 0.15
  }

  static func title(_ width: CGFloat) -> Font {
    .system(size: 16 * scale(for: width), weight: .semibold, design: .rounded)
  }

  static func body(_ width: CGFloat) -> Font { .system(size: 14 * scale(for: width)) }

  static func small(_ width: CGFloat) -> Font { .system(size: 12 * scale(for: width)) }

  static func code(_ width: CGFloat) -> Font {
    .system(size: 13 * scale(for: width), weight: .regular, design: .monospaced)
  }
}
