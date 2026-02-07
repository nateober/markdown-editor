import SwiftUI

/// Persisted editor settings using @AppStorage for automatic UserDefaults persistence.
@Observable
final class EditorSettings {
    /// The editor font size in points (range: 10-24).
    @ObservationIgnored
    @AppStorage("editorFontSize") var fontSize: Double = 14

    /// Whether Vim keybindings are enabled.
    @ObservationIgnored
    @AppStorage("vimModeEnabled") var vimModeEnabled: Bool = false

    /// The default view mode when opening a new document.
    @ObservationIgnored
    @AppStorage("defaultViewMode") var defaultViewModeRawValue: String = ViewMode.sideBySide.rawValue

    /// Computed property for type-safe access to the default view mode.
    var defaultViewMode: ViewMode {
        get { ViewMode(rawValue: defaultViewModeRawValue) ?? .sideBySide }
        set { defaultViewModeRawValue = newValue.rawValue }
    }
}
