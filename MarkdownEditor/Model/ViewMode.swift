import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side by Side"
    case editorOnly = "Editor Only"
    case previewOnly = "Preview Only"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .editorOnly: return "doc.text"
        case .previewOnly: return "eye"
        }
    }
}
