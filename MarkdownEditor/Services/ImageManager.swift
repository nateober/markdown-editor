import Foundation
import AppKit

/// Manages saving images alongside a Markdown document in a sibling `_images/` directory.
///
/// `ImageManager` is stateless with respect to any particular document; each method that touches the
/// filesystem receives the relevant document URL so the caller decides when a document has been saved.
struct ImageManager {

    // MARK: - Public API

    /// Save image data to the images directory that sits alongside the given document.
    ///
    /// - Parameters:
    ///   - imageData: The raw PNG or JPEG bytes.
    ///   - suggestedName: An optional human-readable stem. When `nil` a unique name is generated.
    ///   - documentURL: The file URL of the saved `.md` document.
    /// - Returns: The *relative* markdown-ready path (e.g. `my_doc_images/image-1706812345.png`),
    ///   or `nil` when saving fails.
    func saveImage(_ imageData: Data, suggestedName: String? = nil, relativeTo documentURL: URL) -> String? {
        let imagesDirectoryURL = Self.imagesDirectoryURL(for: documentURL)

        // Create the directory if it doesn't exist.
        do {
            try FileManager.default.createDirectory(
                at: imagesDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        // Determine image format and extension.
        let ext = imageExtension(for: imageData)
        let filename: String
        if let name = suggestedName {
            // Sanitise the suggested name and append the correct extension.
            let stem = sanitiseFilename(name)
            filename = "\(stem).\(ext)"
        } else {
            filename = generateImageFilename(extension: ext)
        }

        let fileURL = imagesDirectoryURL.appendingPathComponent(filename)

        // Avoid overwriting an existing file by appending a suffix when necessary.
        let uniqueURL = uniqueFileURL(for: fileURL)

        do {
            try imageData.write(to: uniqueURL)
        } catch {
            return nil
        }

        // Build the relative path: <directoryName>/<filename>
        let directoryName = imagesDirectoryURL.lastPathComponent
        let savedFilename = uniqueURL.lastPathComponent
        return "\(directoryName)/\(savedFilename)"
    }

    /// Copy an image file from an arbitrary location into the images directory.
    ///
    /// - Parameters:
    ///   - sourceURL: The file URL of the image to copy.
    ///   - documentURL: The file URL of the saved `.md` document.
    /// - Returns: The relative markdown-ready path, or `nil` on failure.
    func copyImage(from sourceURL: URL, relativeTo documentURL: URL) -> String? {
        guard let data = try? Data(contentsOf: sourceURL) else { return nil }
        let suggestedName = sourceURL.deletingPathExtension().lastPathComponent
        return saveImage(data, suggestedName: suggestedName, relativeTo: documentURL)
    }

    /// Generate a unique filename with the given extension.
    ///
    /// The format is `image-<unix-timestamp>-<random>.<ext>` to ensure uniqueness
    /// even when images are pasted in rapid succession.
    func generateImageFilename(extension ext: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = UInt32.random(in: 0..<100_000)
        return "image-\(timestamp)-\(random).\(ext)"
    }

    // MARK: - Directory Helpers

    /// Derive the images directory URL for a given document URL.
    ///
    /// For a document at `/path/to/notes.md` the result is `/path/to/notes_images/`.
    static func imagesDirectoryURL(for documentURL: URL) -> URL {
        let directory = documentURL.deletingLastPathComponent()
        let stem = documentURL.deletingPathExtension().lastPathComponent
        let imagesDirName = "\(stem)_images"
        return directory.appendingPathComponent(imagesDirName)
    }

    // MARK: - Private Helpers

    /// Return `"png"` or `"jpg"` based on the data's magic bytes.
    private func imageExtension(for data: Data) -> String {
        guard data.count >= 3 else { return "png" }
        let bytes = [UInt8](data.prefix(3))

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "jpg"
        }
        // PNG: 89 50 4E
        return "png"
    }

    /// Strip characters that are problematic in filenames.
    private func sanitiseFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
    }

    /// If a file already exists at `url`, append `-1`, `-2`, etc. until a free name is found.
    private func uniqueFileURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent

        var counter = 1
        while true {
            let candidate = directory.appendingPathComponent("\(stem)-\(counter).\(ext)")
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
