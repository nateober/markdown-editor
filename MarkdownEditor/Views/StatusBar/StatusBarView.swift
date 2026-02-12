import SwiftUI

struct StatusBarView: View {
    let text: String
    let vimMode: VimMode
    let line: Int
    let column: Int
    var vimEnabled: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            // Vim mode badge (only shown when Vim mode is enabled)
            if vimEnabled {
                vimModeBadge
            }

            Spacer()

            // Line:Column
            Text("Ln \(line), Col \(column)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 12)

            // Word count
            Text("\(text.wordCount) words")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 12)

            // Character count
            Text("\(text.characterCount) chars")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 12)

            // Reading time
            let minutes = text.readingTimeMinutes
            Text("\(minutes) min read")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            colorScheme == .dark
                ? Color(nsColor: .controlBackgroundColor)
                : Color(nsColor: .windowBackgroundColor)
        )
    }

    private var vimModeBadge: some View {
        Text(vimModeLabel)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(vimModeColor)
            )
    }

    private var vimModeLabel: String {
        switch vimMode {
        case .normal:
            return "NORMAL"
        case .insert:
            return "INSERT"
        case .visual:
            return "VISUAL"
        case .visualLine:
            return "V-LINE"
        }
    }

    private var vimModeColor: Color {
        switch vimMode {
        case .normal:
            return .blue
        case .insert:
            return .green
        case .visual:
            return .orange
        case .visualLine:
            return .purple
        }
    }
}
