import Foundation

struct BoardManSnippetXMLItem: Equatable {
    let title: String
    let content: String
}

struct BoardManSnippetXMLFolder: Equatable {
    let title: String
    let snippets: [BoardManSnippetXMLItem]
}

enum BoardManSnippetXMLCodec {
    static func decode(_ data: Data) throws -> [BoardManSnippetXMLFolder] {
        let document = try XMLDocument(data: data, options: [.nodePreserveWhitespace])
        guard let root = document.rootElement(),
              root.name == Constants.Xml.rootElement else {
            return []
        }

        return elementChildren(of: root).map { folderElement in
            let title = firstElement(named: Constants.Xml.titleElement, in: folderElement)?.stringValue
                ?? "untitled folder"
            let snippetsElement = firstElement(named: Constants.Xml.snippetsElement, in: folderElement)
            let snippets = snippetsElement.map { element in
                elementChildren(of: element)
                    .filter { $0.name == Constants.Xml.snippetElement }
                    .map { snippetElement in
                        BoardManSnippetXMLItem(
                            title: firstElement(
                                named: Constants.Xml.titleElement,
                                in: snippetElement
                            )?.stringValue ?? "untitled snippet",
                            content: firstElement(
                                named: Constants.Xml.contentElement,
                                in: snippetElement
                            )?.stringValue ?? ""
                        )
                    }
            } ?? []

            return BoardManSnippetXMLFolder(title: title, snippets: snippets)
        }
    }

    static func encode(_ folders: [BoardManSnippetXMLFolder]) -> Data {
        Data(xmlString(for: folders).utf8)
    }

    static func xmlString(for folders: [BoardManSnippetXMLFolder]) -> String {
        let header = "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>"
        guard !folders.isEmpty else {
            return "\(header)\n<\(Constants.Xml.rootElement) />"
        }

        var lines = [header, "<\(Constants.Xml.rootElement)>"]
        for folder in folders {
            lines.append("\t<\(Constants.Xml.folderElement)>")
            lines.append(
                "\t\t<\(Constants.Xml.titleElement)>\(escaped(folder.title))</\(Constants.Xml.titleElement)>"
            )

            if folder.snippets.isEmpty {
                lines.append("\t\t<\(Constants.Xml.snippetsElement) />")
            } else {
                lines.append("\t\t<\(Constants.Xml.snippetsElement)>")
                for snippet in folder.snippets {
                    lines.append("\t\t\t<\(Constants.Xml.snippetElement)>")
                    lines.append(
                        "\t\t\t\t<\(Constants.Xml.titleElement)>\(escaped(snippet.title))</\(Constants.Xml.titleElement)>"
                    )
                    lines.append(
                        "\t\t\t\t<\(Constants.Xml.contentElement)>\(escaped(snippet.content))</\(Constants.Xml.contentElement)>"
                    )
                    lines.append("\t\t\t</\(Constants.Xml.snippetElement)>")
                }
                lines.append("\t\t</\(Constants.Xml.snippetsElement)>")
            }

            lines.append("\t</\(Constants.Xml.folderElement)>")
        }
        lines.append("</\(Constants.Xml.rootElement)>")
        return lines.joined(separator: "\n")
    }

    private static func elementChildren(of element: XMLElement) -> [XMLElement] {
        element.children?.compactMap { $0 as? XMLElement } ?? []
    }

    private static func firstElement(named name: String, in element: XMLElement) -> XMLElement? {
        elementChildren(of: element).first { $0.name == name }
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;", options: .literal)
            .replacingOccurrences(of: "<", with: "&lt;", options: .literal)
            .replacingOccurrences(of: ">", with: "&gt;", options: .literal)
            .replacingOccurrences(of: "'", with: "&apos;", options: .literal)
            .replacingOccurrences(of: "\"", with: "&quot;", options: .literal)
            .replacingOccurrences(of: "\n", with: "&#10;", options: .literal)
    }
}
