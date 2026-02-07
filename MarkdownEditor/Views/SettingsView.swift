import SwiftUI

/// The macOS Settings window, accessible via Cmd+,.
struct SettingsView: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("vimModeEnabled") private var vimModeEnabled: Bool = false
    @AppStorage("defaultViewMode") private var defaultViewModeRawValue: String = ViewMode.sideBySide.rawValue

    private var defaultViewMode: Binding<ViewMode> {
        Binding(
            get: { ViewMode(rawValue: defaultViewModeRawValue) ?? .sideBySide },
            set: { defaultViewModeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Editor") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Slider(value: $fontSize, in: 10...24, step: 1) {
                        Text("Font Size")
                    }
                    .frame(width: 160)
                    Stepper(value: $fontSize, in: 10...24, step: 1) {
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Toggle("Vim Mode", isOn: $vimModeEnabled)
            }

            Section("Display") {
                Picker("Default View Mode", selection: defaultViewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 250)
    }
}
