import AppKit
import SwiftUI

enum ItemKind: String, Codable, CaseIterable {
    case text, link, image, file, color

    var displayName: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        case .color: "Color"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }
}

struct ClipItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ItemKind
    var createdAt = Date()
    var modifiedAt = Date()

    // Content
    var text: String?            // plain text, url string, hex color
    var rtfFile: String?         // file name in the data dir
    var htmlFile: String?
    var imageFile: String?       // png in data dir
    var imageSize: CGSize?
    var fileURLs: [String]?      // absolute paths

    // Link preview
    var linkTitle: String?
    var linkImageFile: String?
    var linkPreviewFetched = false

    // Source
    var appBundleID: String?
    var appName: String?

    // Organisation
    var title: String?
    var inHistory = true
    var pinboardID: UUID?
    var pinnedAt: Date?

    var contentHash: String

    var displayTitle: String { (title?.isEmpty == false ? title! : kind.displayName) }

    var searchableText: String {
        var parts: [String] = [kind.displayName]
        if let t = text { parts.append(t) }
        if let t = title { parts.append(t) }
        if let t = linkTitle { parts.append(t) }
        if let f = fileURLs { parts.append(contentsOf: f) }
        if let a = appName { parts.append(a) }
        return parts.joined(separator: " ")
    }
}

enum PinboardColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var color: Color {
        switch self {
        case .red: Color(red: 0.95, green: 0.27, blue: 0.27)
        case .orange: Color(red: 0.98, green: 0.58, blue: 0.20)
        case .yellow: Color(red: 0.98, green: 0.78, blue: 0.20)
        case .green: Color(red: 0.25, green: 0.78, blue: 0.40)
        case .blue: Color(red: 0.22, green: 0.52, blue: 0.98)
        case .purple: Color(red: 0.72, green: 0.36, blue: 0.95)
        case .pink: Color(red: 0.96, green: 0.30, blue: 0.48)
        case .gray: Color(white: 0.6)
        }
    }
}

struct Pinboard: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: PinboardColor
    var sortIndex: Double = 0
    var modifiedAt = Date()
    /// Folder of a shared pinboard (`<Name>.pastepinboard`) that collaborators also read and write.
    var sharedFolderPath: String?

    var isShared: Bool { sharedFolderPath != nil }
}

/// Which list the panel is showing.
enum ListSelection: Hashable {
    case history
    case pinboard(UUID)
}
