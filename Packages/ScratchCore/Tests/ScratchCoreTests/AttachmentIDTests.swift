import Foundation
import Testing

@testable import ScratchCore

// Plan 5, Task 1: an attachment's identity is a lowercase UUID string, like a note's (spec §6.4).

@Test func attachmentIDsAreUniqueLowercaseUUIDs() {
    let a = AttachmentID.make()
    let b = AttachmentID.make()
    #expect(a != b)
    #expect(a.rawValue == a.rawValue.lowercased())
    #expect(UUID(uuidString: a.rawValue) != nil)
}

@Test func attachmentIDIsABareJSONString() throws {
    let id = AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff")
    let data = try JSONEncoder().encode([id])
    #expect(String(decoding: data, as: UTF8.self) == "[\"6f9619ff-8b86-4d11-b42d-00c04fc964ff\"]")
    #expect(try JSONDecoder().decode([AttachmentID].self, from: data) == [id])
}
