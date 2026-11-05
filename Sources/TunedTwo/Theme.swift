//
//  Theme.swift
//  TunedTwo
//
//  Centralized layout metrics + type system.
//

import SwiftUI

/// Centralized layout metrics and type system for the TunedTwo UI.
///
/// Two rules keep this honest (see `SWIFTUI-RULES.md` §2.4, §5.1):
/// - **Scale** comes from semantic SwiftUI text styles only, never hardcoded
///   point sizes, so Dynamic Type and OS metric updates keep working.
/// - **Emphasis is weight; de-emphasis is color** (`.secondary` / `.tertiary`),
///   never a lighter font weight.
///
/// When you find yourself typing the same number a third time, it belongs here
/// as a named metric.
enum Theme {
    // MARK: Window
    static let windowMinWidth: CGFloat = 480
    static let windowMinHeight: CGFloat = 440

    // MARK: Spacing
    static let sectionSpacing: CGFloat = 16
    static let groupSpacing: CGFloat = 12
    static let itemSpacing: CGFloat = 10
    static let tightSpacing: CGFloat = 8
    static let labelSpacing: CGFloat = 4

    // MARK: Padding
    static let defaultPadding: CGFloat = 16
    static let cardPaddingHorizontal: CGFloat = 12
    static let cardPaddingVertical: CGFloat = 6
    static let cardHeaderPaddingVertical: CGFloat = 8
    static let chipPaddingHorizontal: CGFloat = 6
    static let chipPaddingVertical: CGFloat = 2

    // MARK: Corner radii
    static let imageCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 8

    // MARK: Frames
    static let metadataLabelWidth: CGFloat = 80
    static let frequencyFieldWidth: CGFloat = 120
    static let logIconSize: CGFloat = 24
    static let lotImageSize: CGFloat = 100
    static let sidePanelMinWidth: CGFloat = 240

    // MARK: Type scale
    enum Fonts {
        /// The app header's hero icon.
        static let appIcon = Font.largeTitle.weight(.bold)
        /// The app header title.
        static let appTitle = Font.title2.weight(.bold)
        /// Section/row headings.
        static let sectionTitle = Font.headline
        /// Body copy.
        static let body = Font.body
        /// Secondary body text (descriptions, subtitles).
        static let bodySecondary = Font.subheadline
        /// Metadata, timestamps, status lines, and table footers.
        static let meta = Font.caption
        /// Emphasized metadata (counts, badges).
        static let metaBold = Font.caption.weight(.bold)
        /// The icon glyph inside a log-event row.
        static let logIcon = Font.subheadline.weight(.semibold)
    }
}
