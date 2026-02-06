import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType("net.daringfireball.markdown") ?? UTType(
        exportedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}
