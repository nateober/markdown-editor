import AppKit
import Compression
import Foundation

/// Exports markdown content to DOCX format.
/// Uses NSAttributedString for most content, then post-processes the OOXML
/// to inject native Word tables that NSAttributedString cannot produce.
final class DOCXExporter {

    enum ExportError: LocalizedError {
        case htmlConversionFailed
        case docxCreationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .htmlConversionFailed:
                return "Failed to convert markdown to attributed string for DOCX export."
            case .docxCreationFailed(let underlying):
                return "DOCX creation failed: \(underlying.localizedDescription)"
            }
        }
    }

    private let parser = MarkdownParser()

    func exportDOCX(from markdown: String) throws -> Data {
        let html = parser.parse(markdown)

        // Pre-process lists into styled paragraphs (NSAttributedString drops list formatting)
        let listProcessedHTML = convertListsToStyledParagraphs(html)

        // Extract tables from HTML and replace with placeholders
        let (processedHTML, tables) = extractTables(from: listProcessedHTML)

        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            color: #24292e;
        }
        h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
        h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
        h3 { font-size: 1.25em; }
        p { margin-top: 0; margin-bottom: 16px; }
        code {
            font-family: "SF Mono", Menlo, monospace;
            font-size: 12px;
            background-color: #f5f5f5;
            padding: 2px 4px;
            border-radius: 3px;
        }
        pre { background-color: #f6f8fa; border-radius: 6px; padding: 16px; overflow: auto; }
        pre code { display: block; padding: 0; background: none; }
        blockquote {
            border-left: 4px solid #ddd;
            padding-left: 16px;
            color: #555;
        }
        img { max-width: 100%; height: auto; }
        hr { border: none; border-top: 2px solid #eaecef; margin: 24px 0; }
        ul, ol { padding-left: 2em; margin-bottom: 16px; }
        del { color: #6a737d; }
        </style>
        </head>
        <body>\(processedHTML)</body>
        </html>
        """

        guard let htmlData = fullHTML.data(using: .utf8),
              let attributedString = NSAttributedString(
                html: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            throw ExportError.htmlConversionFailed
        }

        let range = NSRange(location: 0, length: attributedString.length)

        do {
            var docxData = try attributedString.data(
                from: range,
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.officeOpenXML
                ]
            )

            // If we extracted tables, inject them as native Word tables
            if !tables.isEmpty {
                docxData = try injectWordTables(into: docxData, tables: tables)
            }

            return docxData
        } catch {
            throw ExportError.docxCreationFailed(error)
        }
    }

    // MARK: - Table Extraction

    /// Represents a parsed HTML table.
    private struct HTMLTable {
        let headers: [String]
        let rows: [[String]]
        let placeholderID: String
    }

    /// Extracts `<table>` elements from HTML, replaces them with placeholder
    /// paragraphs, and returns the parsed table data.
    private func extractTables(from html: String) -> (String, [HTMLTable]) {
        var result = html
        var tables: [HTMLTable] = []

        // Find each <table>...</table> block
        while let tableRange = result.range(of: "<table>", options: .caseInsensitive) {
            guard let endRange = result.range(of: "</table>", options: .caseInsensitive, range: tableRange.upperBound..<result.endIndex) else {
                break
            }

            let fullRange = tableRange.lowerBound..<endRange.upperBound
            let tableHTML = String(result[fullRange])

            let id = "DOCX_TABLE_\(tables.count)"
            if let parsed = parseHTMLTable(tableHTML, id: id) {
                tables.append(parsed)
                result.replaceSubrange(fullRange, with: "<p>\(id)</p>")
            } else {
                // If we can't parse it, leave it (NSAttributedString will do its best)
                break
            }
        }

        return (result, tables)
    }

    /// Parses a single HTML table string into headers and rows.
    private func parseHTMLTable(_ html: String, id: String) -> HTMLTable? {
        let headers = extractCells(from: html, tag: "th")
        let allTDs = extractRows(from: html)

        // If no headers found, use first row as headers
        if headers.isEmpty && !allTDs.isEmpty {
            return HTMLTable(headers: allTDs[0], rows: Array(allTDs.dropFirst()), placeholderID: id)
        }

        return HTMLTable(headers: headers, rows: allTDs, placeholderID: id)
    }

    /// Extracts cell text for a given tag (th or td) from the first matching row.
    private func extractCells(from html: String, tag: String) -> [String] {
        var cells: [String] = []
        var searchRange = html.startIndex..<html.endIndex

        while let openRange = html.range(of: "<\(tag)", options: .caseInsensitive, range: searchRange) {
            // Find the end of the opening tag (handle attributes)
            guard let tagClose = html.range(of: ">", range: openRange.upperBound..<html.endIndex) else { break }
            guard let closeRange = html.range(of: "</\(tag)>", options: .caseInsensitive, range: tagClose.upperBound..<html.endIndex) else { break }

            let content = String(html[tagClose.upperBound..<closeRange.lowerBound])
            cells.append(stripHTML(content).trimmingCharacters(in: .whitespacesAndNewlines))
            searchRange = closeRange.upperBound..<html.endIndex
        }

        return cells
    }

    /// Extracts all `<tr>` rows that contain `<td>` cells (skips header rows).
    private func extractRows(from html: String) -> [[String]] {
        var rows: [[String]] = []
        var searchRange = html.startIndex..<html.endIndex

        while let trOpen = html.range(of: "<tr", options: .caseInsensitive, range: searchRange) {
            guard let trClose = html.range(of: "</tr>", options: .caseInsensitive, range: trOpen.upperBound..<html.endIndex) else { break }

            let rowHTML = String(html[trOpen.lowerBound..<trClose.upperBound])

            // Only process rows with <td> cells (skip header rows with only <th>)
            if rowHTML.range(of: "<td", options: .caseInsensitive) != nil {
                let cells = extractCells(from: rowHTML, tag: "td")
                if !cells.isEmpty {
                    rows.append(cells)
                }
            }

            searchRange = trClose.upperBound..<html.endIndex
        }

        return rows
    }

    /// Strips HTML tags from a string.
    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    // MARK: - List Conversion

    /// Converts HTML `<ul>` and `<ol>` lists into styled paragraphs with
    /// bullet/number characters. NSAttributedString's OOXML export doesn't
    /// produce native Word lists, so we render them as indented text.
    private func convertListsToStyledParagraphs(_ html: String) -> String {
        var result = html

        // Process ordered lists first (to avoid nested list issues)
        result = convertOrderedLists(result)
        result = convertUnorderedLists(result)

        return result
    }

    private func convertUnorderedLists(_ html: String) -> String {
        var result = html

        while let ulStart = result.range(of: "<ul>", options: .caseInsensitive) {
            guard let ulEnd = findMatchingClose(tag: "ul", in: result, after: ulStart.upperBound) else { break }

            let fullRange = ulStart.lowerBound..<ulEnd.upperBound
            let listHTML = String(result[fullRange])

            let items = extractListItems(from: listHTML)
            var replacement = ""
            for item in items {
                let text = stripHTML(item).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    replacement += "<p style=\"margin-left:36pt;text-indent:-18pt;\">\u{2022}  \(text)</p>\n"
                }
            }

            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    private func convertOrderedLists(_ html: String) -> String {
        var result = html

        while let olStart = result.range(of: "<ol>", options: .caseInsensitive) {
            guard let olEnd = findMatchingClose(tag: "ol", in: result, after: olStart.upperBound) else { break }

            let fullRange = olStart.lowerBound..<olEnd.upperBound
            let listHTML = String(result[fullRange])

            let items = extractListItems(from: listHTML)
            var replacement = ""
            for (index, item) in items.enumerated() {
                let text = stripHTML(item).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    replacement += "<p style=\"margin-left:36pt;text-indent:-18pt;\">\(index + 1).  \(text)</p>\n"
                }
            }

            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    /// Finds the matching closing tag, handling nesting.
    private func findMatchingClose(tag: String, in html: String, after start: String.Index) -> Range<String.Index>? {
        var depth = 1
        var searchFrom = start

        while depth > 0 && searchFrom < html.endIndex {
            let openTag = html.range(of: "<\(tag)", options: .caseInsensitive, range: searchFrom..<html.endIndex)
            let closeTag = html.range(of: "</\(tag)>", options: .caseInsensitive, range: searchFrom..<html.endIndex)

            guard let close = closeTag else { return nil }

            if let open = openTag, open.lowerBound < close.lowerBound {
                depth += 1
                searchFrom = open.upperBound
            } else {
                depth -= 1
                if depth == 0 {
                    return close
                }
                searchFrom = close.upperBound
            }
        }

        return nil
    }

    /// Extracts the content of each `<li>...</li>` in the given HTML.
    private func extractListItems(from html: String) -> [String] {
        var items: [String] = []
        var searchRange = html.startIndex..<html.endIndex

        while let liOpen = html.range(of: "<li", options: .caseInsensitive, range: searchRange) {
            guard let tagClose = html.range(of: ">", range: liOpen.upperBound..<html.endIndex) else { break }
            guard let liClose = html.range(of: "</li>", options: .caseInsensitive, range: tagClose.upperBound..<html.endIndex) else { break }

            let content = String(html[tagClose.upperBound..<liClose.lowerBound])
            items.append(content)
            searchRange = liClose.upperBound..<html.endIndex
        }

        return items
    }

    // MARK: - Word Table XML Injection

    /// Modifies document.xml inside the DOCX ZIP to inject native Word tables.
    /// Pure Swift implementation — no shell commands.
    private func injectWordTables(into docxData: Data, tables: [HTMLTable]) throws -> Data {
        // Parse all ZIP entries
        var entries = readZIPEntries(from: docxData)

        // Find and modify word/document.xml
        guard let docIndex = entries.firstIndex(where: { $0.name == "word/document.xml" }),
              var xmlString = String(data: entries[docIndex].uncompressedData, encoding: .utf8) else {
            return docxData
        }

        // Replace each placeholder with a Word table
        for table in tables {
            let wordTableXML = generateWordTableXML(for: table)
            if let placeholderRange = findParagraphContaining(table.placeholderID, in: xmlString) {
                xmlString.replaceSubrange(placeholderRange, with: wordTableXML)
            }
        }

        // Update the entry with modified XML
        guard let newData = xmlString.data(using: .utf8) else { return docxData }
        entries[docIndex].uncompressedData = newData

        // Rebuild the ZIP
        return buildZIP(from: entries)
    }

    // MARK: - ZIP Handling

    private struct ZIPEntry {
        var name: String
        var uncompressedData: Data
        var compressionMethod: UInt16  // 0 = stored, 8 = deflated
        var externalAttributes: UInt32
        var lastModTime: UInt16
        var lastModDate: UInt16
    }

    /// Reads all entries from a ZIP archive.
    private func readZIPEntries(from data: Data) -> [ZIPEntry] {
        var entries: [ZIPEntry] = []

        // Find end of central directory record (search backward for signature PK\x05\x06)
        guard let eocdOffset = findEOCD(in: data) else { return entries }

        let centralDirOffset = readUInt32(data, at: eocdOffset + 16)
        let entryCount = readUInt16(data, at: eocdOffset + 10)

        var offset = Int(centralDirOffset)
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count else { break }

            // Verify central directory signature (PK\x01\x02)
            guard data[offset] == 0x50, data[offset + 1] == 0x4B,
                  data[offset + 2] == 0x01, data[offset + 3] == 0x02 else { break }

            let compressionMethod = readUInt16(data, at: offset + 10)
            let lastModTime = readUInt16(data, at: offset + 12)
            let lastModDate = readUInt16(data, at: offset + 14)
            let compressedSize = readUInt32(data, at: offset + 20)
            let uncompressedSize = readUInt32(data, at: offset + 24)
            let nameLength = Int(readUInt16(data, at: offset + 28))
            let extraLength = Int(readUInt16(data, at: offset + 30))
            let commentLength = Int(readUInt16(data, at: offset + 32))
            let externalAttributes = readUInt32(data, at: offset + 38)
            let localHeaderOffset = Int(readUInt32(data, at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else { break }
            let nameData = data[nameStart..<(nameStart + nameLength)]
            let name = String(data: nameData, encoding: .utf8) ?? ""

            // Read from local file header to get actual data
            let localData = readLocalFileData(from: data, at: localHeaderOffset,
                                               compressedSize: Int(compressedSize),
                                               uncompressedSize: Int(uncompressedSize),
                                               compressionMethod: compressionMethod)

            entries.append(ZIPEntry(
                name: name,
                uncompressedData: localData,
                compressionMethod: compressionMethod,
                externalAttributes: externalAttributes,
                lastModTime: lastModTime,
                lastModDate: lastModDate
            ))

            offset = nameStart + nameLength + extraLength + commentLength
        }

        return entries
    }

    private func readLocalFileData(from data: Data, at offset: Int,
                                    compressedSize: Int, uncompressedSize: Int,
                                    compressionMethod: UInt16) -> Data {
        guard offset + 30 <= data.count else { return Data() }

        // Verify local file header signature (PK\x03\x04)
        guard data[offset] == 0x50, data[offset + 1] == 0x4B,
              data[offset + 2] == 0x03, data[offset + 3] == 0x04 else { return Data() }

        let localNameLength = Int(readUInt16(data, at: offset + 26))
        let localExtraLength = Int(readUInt16(data, at: offset + 28))
        let dataStart = offset + 30 + localNameLength + localExtraLength

        guard dataStart + compressedSize <= data.count else { return Data() }
        let compressedData = data[dataStart..<(dataStart + compressedSize)]

        if compressionMethod == 0 {
            // Stored (no compression)
            return Data(compressedData)
        } else if compressionMethod == 8 {
            // Deflated — use Compression framework (raw deflate)
            return decompressDeflate(Data(compressedData), expectedSize: uncompressedSize)
        }

        return Data(compressedData)
    }

    private func decompressDeflate(_ data: Data, expectedSize: Int) -> Data {
        guard !data.isEmpty else { return Data() }
        let bufferSize = max(expectedSize * 2, 65536)
        var result = Data(count: bufferSize)

        let decompressedSize = data.withUnsafeBytes { srcPtr -> Int in
            result.withUnsafeMutableBytes { dstPtr -> Int in
                guard let src = srcPtr.baseAddress,
                      let dst = dstPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(
                    dst, bufferSize,
                    src.assumingMemoryBound(to: UInt8.self), data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        if decompressedSize > 0 {
            result.count = decompressedSize
            return result
        }
        return Data()
    }

    private func compressDeflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        let bufferSize = max(data.count * 2, 65536)
        var result = Data(count: bufferSize)

        let compressedSize = data.withUnsafeBytes { srcPtr -> Int in
            result.withUnsafeMutableBytes { dstPtr -> Int in
                guard let src = srcPtr.baseAddress,
                      let dst = dstPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_encode_buffer(
                    dst, bufferSize,
                    src.assumingMemoryBound(to: UInt8.self), data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        if compressedSize > 0 {
            result.count = compressedSize
            return result
        }
        return Data()
    }

    /// Builds a new ZIP archive from entries.
    private func buildZIP(from entries: [ZIPEntry]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offsets: [Int] = []

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let uncompressedData = entry.uncompressedData
            let crc = crc32(uncompressedData)

            let compressedData: Data
            let method: UInt16
            if entry.compressionMethod == 8 && !uncompressedData.isEmpty {
                let compressed = compressDeflate(uncompressedData)
                if !compressed.isEmpty && compressed.count < uncompressedData.count {
                    compressedData = compressed
                    method = 8
                } else {
                    compressedData = uncompressedData
                    method = 0
                }
            } else {
                compressedData = uncompressedData
                method = 0
            }

            offsets.append(output.count)

            // Local file header
            writeUInt32(&output, 0x04034B50)  // signature
            writeUInt16(&output, 20)           // version needed
            writeUInt16(&output, 0)            // flags
            writeUInt16(&output, method)       // compression method
            writeUInt16(&output, entry.lastModTime)
            writeUInt16(&output, entry.lastModDate)
            writeUInt32(&output, crc)
            writeUInt32(&output, UInt32(compressedData.count))
            writeUInt32(&output, UInt32(uncompressedData.count))
            writeUInt16(&output, UInt16(nameData.count))
            writeUInt16(&output, 0)            // extra field length
            output.append(nameData)
            output.append(compressedData)

            // Central directory entry
            writeUInt32(&centralDirectory, 0x02014B50)  // signature
            writeUInt16(&centralDirectory, 20)           // version made by
            writeUInt16(&centralDirectory, 20)           // version needed
            writeUInt16(&centralDirectory, 0)            // flags
            writeUInt16(&centralDirectory, method)
            writeUInt16(&centralDirectory, entry.lastModTime)
            writeUInt16(&centralDirectory, entry.lastModDate)
            writeUInt32(&centralDirectory, crc)
            writeUInt32(&centralDirectory, UInt32(compressedData.count))
            writeUInt32(&centralDirectory, UInt32(uncompressedData.count))
            writeUInt16(&centralDirectory, UInt16(nameData.count))
            writeUInt16(&centralDirectory, 0)    // extra field length
            writeUInt16(&centralDirectory, 0)    // comment length
            writeUInt16(&centralDirectory, 0)    // disk number start
            writeUInt16(&centralDirectory, 0)    // internal attributes
            writeUInt32(&centralDirectory, entry.externalAttributes)
            writeUInt32(&centralDirectory, UInt32(offsets.last!))
        }

        let centralDirOffset = output.count
        output.append(centralDirectory)

        // End of central directory record
        writeUInt32(&output, 0x06054B50)  // signature
        writeUInt16(&output, 0)            // disk number
        writeUInt16(&output, 0)            // disk with central dir
        writeUInt16(&output, UInt16(entries.count))
        writeUInt16(&output, UInt16(entries.count))
        writeUInt32(&output, UInt32(centralDirectory.count))
        writeUInt32(&output, UInt32(centralDirOffset))
        writeUInt16(&output, 0)            // comment length

        return output
    }

    // MARK: - ZIP Utility Helpers

    private func findEOCD(in data: Data) -> Int? {
        // Search backward for EOCD signature (PK\x05\x06)
        let minOffset = max(0, data.count - 65557) // max comment size is 65535
        for i in stride(from: data.count - 22, through: minOffset, by: -1) {
            if data[i] == 0x50, data[i + 1] == 0x4B,
               data[i + 2] == 0x05, data[i + 3] == 0x06 {
                return i
            }
        }
        return nil
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private func writeUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func writeUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func crc32(_ data: Data) -> UInt32 {
        // CRC-32 lookup table
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }

        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Finds the range of the `<w:p>...</w:p>` element containing the given placeholder text.
    private func findParagraphContaining(_ text: String, in xml: String) -> Range<String.Index>? {
        guard let textRange = xml.range(of: text) else { return nil }

        // Search backward for <w:p> or <w:p
        var pStart = textRange.lowerBound
        while pStart > xml.startIndex {
            let checkStart = xml.index(before: pStart)
            // Look for <w:p> or <w:p followed by space
            if xml[checkStart..<pStart].contains("<") {
                // Check if this is a <w:p> tag
                let remaining = xml[checkStart...]
                if remaining.hasPrefix("<w:p>") || remaining.hasPrefix("<w:p ") {
                    pStart = checkStart
                    break
                }
            }
            pStart = checkStart
        }

        // Search forward for </w:p>
        guard let pEndRange = xml.range(of: "</w:p>", range: textRange.upperBound..<xml.endIndex) else {
            return nil
        }

        return pStart..<pEndRange.upperBound
    }

    /// Generates Word Open XML markup for a table.
    private func generateWordTableXML(for table: HTMLTable) -> String {
        // Calculate column count and even width distribution
        // Word uses twips: US Letter = 12240 twips wide, minus 1800 margins = ~9360 usable
        let colCount = max(table.headers.count, table.rows.first?.count ?? 1)
        let colWidthTwips = 9360 / max(colCount, 1)

        var xml = """
        <w:tbl>
          <w:tblPr>
            <w:tblStyle w:val="TableGrid"/>
            <w:tblW w:w="5000" w:type="pct"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
              <w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
              <w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>
            </w:tblBorders>
            <w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>
          </w:tblPr>
          <w:tblGrid>
        """

        // Define equal column widths
        for _ in 0..<colCount {
            xml += "<w:gridCol w:w=\"\(colWidthTwips)\"/>"
        }
        xml += "</w:tblGrid>"

        // Header row
        if !table.headers.isEmpty {
            xml += "<w:tr>"
            for header in table.headers {
                xml += """
                <w:tc>
                  <w:tcPr>
                    <w:tcW w:w="\(colWidthTwips)" w:type="dxa"/>
                    <w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>
                  </w:tcPr>
                  <w:p><w:pPr><w:jc w:val="left"/></w:pPr>
                    <w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t xml:space="preserve">\(escapeXML(header))</w:t></w:r>
                  </w:p>
                </w:tc>
                """
            }
            xml += "</w:tr>"
        }

        // Data rows
        for row in table.rows {
            xml += "<w:tr>"
            for cell in row {
                xml += """
                <w:tc>
                  <w:tcPr>
                    <w:tcW w:w="\(colWidthTwips)" w:type="dxa"/>
                  </w:tcPr>
                  <w:p><w:pPr><w:jc w:val="left"/></w:pPr>
                    <w:r><w:rPr><w:sz w:val="22"/></w:rPr><w:t xml:space="preserve">\(escapeXML(cell))</w:t></w:r>
                  </w:p>
                </w:tc>
                """
            }
            xml += "</w:tr>"
        }

        xml += "</w:tbl>"
        return xml
    }

    /// Escapes special XML characters.
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
