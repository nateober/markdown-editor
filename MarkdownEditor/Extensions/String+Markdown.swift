import Foundation

extension String {
    var wordCount: Int {
        self.split { $0.isWhitespace || $0.isNewline }.count
    }

    var characterCount: Int {
        self.count
    }

    var readingTimeMinutes: Int {
        max(0, Int((Double(wordCount) / 200.0).rounded(.up)))
    }

    func lineAndColumn(at offset: Int) -> (line: Int, column: Int) {
        let target = self.index(startIndex, offsetBy: min(offset, count))
        var line = 1
        var column = 1
        for idx in self.indices {
            if idx == target { break }
            if self[idx] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }
}
