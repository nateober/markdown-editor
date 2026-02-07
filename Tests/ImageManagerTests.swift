import Testing
import Foundation
import AppKit
@testable import MarkdownEditor

@Suite("ImageManager", .serialized)
struct ImageManagerTests {
    let manager = ImageManager()

    // MARK: - Filename Generation

    @Test("generateImageFilename produces valid unique names")
    func generateFilename() {
        let name1 = manager.generateImageFilename(extension: "png")
        let name2 = manager.generateImageFilename(extension: "png")

        #expect(name1.hasPrefix("image-"))
        #expect(name1.hasSuffix(".png"))
        #expect(name2.hasPrefix("image-"))
        // Two calls should not produce identical filenames (random component).
        #expect(name1 != name2)
    }

    @Test("generateImageFilename uses the provided extension")
    func generateFilenameExtension() {
        let jpg = manager.generateImageFilename(extension: "jpg")
        #expect(jpg.hasSuffix(".jpg"))

        let png = manager.generateImageFilename(extension: "png")
        #expect(png.hasSuffix(".png"))
    }

    // MARK: - Images Directory Derivation

    @Test("Images directory is correctly derived from document URL")
    func imageDirectoryPath() {
        let docURL = URL(fileURLWithPath: "/tmp/docs/my_notes.md")
        let imagesDir = ImageManager.imagesDirectoryURL(for: docURL)

        #expect(imagesDir.lastPathComponent == "my_notes_images")
        #expect(imagesDir.deletingLastPathComponent().path == "/tmp/docs")
    }

    @Test("Images directory handles document names with spaces")
    func imageDirectoryWithSpaces() {
        let docURL = URL(fileURLWithPath: "/tmp/docs/My Document.md")
        let imagesDir = ImageManager.imagesDirectoryURL(for: docURL)

        #expect(imagesDir.lastPathComponent == "My Document_images")
    }

    // MARK: - Save Image (filesystem)

    @Test("saveImage creates directory and writes file")
    func saveImageCreatesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let docURL = tempDir.appendingPathComponent("test.md")
        // Create a minimal valid PNG (1x1 pixel).
        let pngData = minimalPNGData()

        let relativePath = manager.saveImage(pngData, relativeTo: docURL)

        #expect(relativePath != nil)
        #expect(relativePath!.hasPrefix("test_images/"))
        #expect(relativePath!.hasSuffix(".png"))

        // Verify the file actually exists on disk.
        let imagesDir = ImageManager.imagesDirectoryURL(for: docURL)
        let filename = String(relativePath!.dropFirst("test_images/".count))
        let fileURL = imagesDir.appendingPathComponent(filename)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("saveImage with suggested name uses that name")
    func saveImageWithSuggestedName() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let docURL = tempDir.appendingPathComponent("notes.md")
        let pngData = minimalPNGData()

        let relativePath = manager.saveImage(pngData, suggestedName: "screenshot", relativeTo: docURL)

        #expect(relativePath != nil)
        #expect(relativePath! == "notes_images/screenshot.png")
    }

    @Test("saveImage avoids overwriting existing files")
    func saveImageUniqueness() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let docURL = tempDir.appendingPathComponent("doc.md")
        let pngData = minimalPNGData()

        let path1 = manager.saveImage(pngData, suggestedName: "photo", relativeTo: docURL)
        let path2 = manager.saveImage(pngData, suggestedName: "photo", relativeTo: docURL)

        #expect(path1 != nil)
        #expect(path2 != nil)
        #expect(path1 != path2)
        #expect(path2!.contains("photo-1.png"))
    }

    @Test("saveImage detects JPEG data")
    func saveJPEGImage() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let docURL = tempDir.appendingPathComponent("doc.md")
        // Minimal JPEG header bytes.
        var jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        jpegData.append(Data(repeating: 0x00, count: 20))

        let relativePath = manager.saveImage(jpegData, relativeTo: docURL)

        #expect(relativePath != nil)
        #expect(relativePath!.hasSuffix(".jpg"))
    }

    // MARK: - Helpers

    /// Produce a minimal 1x1 white PNG in memory.
    private func minimalPNGData() -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.white.set()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            // Return a minimal PNG header as a fallback.
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        return png
    }
}
