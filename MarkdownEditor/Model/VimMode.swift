import Foundation

/// Represents the current Vim editing mode.
enum VimMode: Equatable, Sendable {
    case normal
    case insert
    case visual
    case visualLine
}
