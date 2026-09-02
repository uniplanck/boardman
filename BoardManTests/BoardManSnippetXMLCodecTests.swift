import Foundation
import Testing
@testable import Board_Man

@Suite
struct BoardManSnippetXMLCodecTests {
    @Test
    func encodingPreservesLegacyAEXMLShapeAndEscaping() {
        let folders = [
            BoardManSnippetXMLFolder(
                title: "Folder & <One>",
                snippets: [
                    BoardManSnippetXMLItem(
                        title: "Quote \"'",
                        content: "line1\nline2 & <tag>"
                    )
                ]
            ),
            BoardManSnippetXMLFolder(title: "Empty", snippets: [])
        ]

        let xml = BoardManSnippetXMLCodec.xmlString(for: folders)

        #expect(xml == """
        <?xml version="1.0" encoding="utf-8" standalone="no"?>
        <folders>
        \t<folder>
        \t\t<title>Folder &amp; &lt;One&gt;</title>
        \t\t<snippets>
        \t\t\t<snippet>
        \t\t\t\t<title>Quote &quot;&apos;</title>
        \t\t\t\t<content>line1&#10;line2 &amp; &lt;tag&gt;</content>
        \t\t\t</snippet>
        \t\t</snippets>
        \t</folder>
        \t<folder>
        \t\t<title>Empty</title>
        \t\t<snippets />
        \t</folder>
        </folders>
        """)
    }

    @Test
    func decodingPreservesWhitespaceAndLegacyEntities() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8" standalone="no"?>
        <folders>
        \t<folder>
        \t\t<title>  Folder  </title>
        \t\t<snippets>
        \t\t\t<snippet>
        \t\t\t\t<title>Snippet &amp; More</title>
        \t\t\t\t<content>line1&#10;  line2 &lt;x&gt;</content>
        \t\t\t</snippet>
        \t\t</snippets>
        \t</folder>
        </folders>
        """

        let folders = try BoardManSnippetXMLCodec.decode(Data(xml.utf8))

        #expect(folders == [
            BoardManSnippetXMLFolder(
                title: "  Folder  ",
                snippets: [
                    BoardManSnippetXMLItem(
                        title: "Snippet & More",
                        content: "line1\n  line2 <x>"
                    )
                ]
            )
        ])
    }

    @Test
    func roundTripKeepsFolderAndSnippetOrdering() throws {
        let original = [
            BoardManSnippetXMLFolder(
                title: "First",
                snippets: [
                    BoardManSnippetXMLItem(title: "A", content: "one"),
                    BoardManSnippetXMLItem(title: "B", content: "two")
                ]
            ),
            BoardManSnippetXMLFolder(title: "Second", snippets: [])
        ]

        let decoded = try BoardManSnippetXMLCodec.decode(BoardManSnippetXMLCodec.encode(original))
        #expect(decoded == original)
    }
}
