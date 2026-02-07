import AppKit

/// Facade that coordinates export operations.
/// Presents NSSavePanel dialogs and writes exported data to the chosen location.
@MainActor
final class ExportService {

    private let pdfExporter = PDFExporter()
    private let htmlExporter = HTMLExporter()
    private let docxExporter = DOCXExporter()

    /// Exports the given markdown as a PDF file.
    /// Presents a save panel for the user to choose the destination.
    func exportPDF(markdown: String, darkMode: Bool) {
        Task { @MainActor in
            guard let url = presentSavePanel(
                title: "Export as PDF",
                fileType: "pdf",
                defaultName: "export.pdf"
            ) else { return }

            do {
                let data = try await pdfExporter.exportPDF(from: markdown, darkMode: darkMode)
                try data.write(to: url, options: .atomic)
            } catch {
                showError(error)
            }
        }
    }

    /// Exports the given markdown as a standalone HTML file.
    /// Presents a save panel for the user to choose the destination.
    func exportHTML(markdown: String, darkMode: Bool) {
        guard let url = presentSavePanel(
            title: "Export as HTML",
            fileType: "html",
            defaultName: "export.html"
        ) else { return }

        let data = htmlExporter.exportHTML(from: markdown, darkMode: darkMode)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showError(error)
        }
    }

    /// Exports the given markdown as a Word (.docx) document.
    /// Presents a save panel for the user to choose the destination.
    func exportDOCX(markdown: String) {
        guard let url = presentSavePanel(
            title: "Export as Word",
            fileType: "docx",
            defaultName: "export.docx"
        ) else { return }

        do {
            let data = try docxExporter.exportDOCX(from: markdown)
            try data.write(to: url, options: .atomic)
        } catch {
            showError(error)
        }
    }

    // MARK: - Private Helpers

    private func presentSavePanel(title: String, fileType: String, defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [
            .init(filenameExtension: fileType) ?? .data
        ]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
