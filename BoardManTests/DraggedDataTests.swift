import Foundation
import Testing
@testable import Board_Man

@Suite
struct DragPayloadTests {
    @Test
    func archiveData() throws {
        let payload = BoardManDragPayload(
            type: .folder,
            folderIdentifier: UUID().uuidString,
            snippetIdentifier: nil,
            index: 10
        )
        let data = NSKeyedArchiver.archivedData(withRootObject: payload)

        let decoded = try #require(NSKeyedUnarchiver.unarchiveObject(with: data) as? BoardManDragPayload)
        #expect(decoded.type == payload.type)
        #expect(decoded.folderIdentifier == payload.folderIdentifier)
        #expect(decoded.snippetIdentifier == nil)
        #expect(decoded.index == payload.index)
    }
}
