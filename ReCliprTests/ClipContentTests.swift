//
//  ClipContentTests.swift
//  ReCliprTests
//
//  The v1 → v2 history migration. This is the highest-consequence code in the app:
//  a regression here silently destroys a user's clipboard history, and the only
//  route back is the one-time backup file.
//

import XCTest
import UniformTypeIdentifiers
@testable import ReClipr

final class ClipContentTests: XCTestCase {

    /// Mirrors Persistence.load()'s per-element decode.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(T.self)
        }
    }

    private func decode(_ json: String) throws -> [ClipItem] {
        try JSONDecoder()
            .decode([Lenient<ClipItem>].self, from: Data(json.utf8))
            .compactMap(\.value)
    }

    func testV1TextDecodes() throws {
        let items = try decode("""
        [{"id":"11111111-1111-1111-1111-111111111111","date":1000,
          "content":{"type":"text","text":"hello from v1"}}]
        """)
        XCTAssertEqual(items.count, 1)
        guard case .text(let text) = items[0].content else { return XCTFail("not text") }
        XCTAssertEqual(text, "hello from v1")
    }

    func testV1FileBecomesAReferenceNotAnInlineCopy() throws {
        let items = try decode("""
        [{"id":"44444444-4444-4444-4444-444444444444","date":1000,
          "content":{"type":"file","fileURL":"file:///etc/hosts"}}]
        """)
        guard case .files(let attachments) = items[0].content else { return XCTFail("not files") }
        XCTAssertEqual(attachments.count, 1)
        guard case .reference(let ref) = attachments[0] else {
            return XCTFail("a v1 file must never be inlined at decode time")
        }
        XCTAssertEqual(ref.path, "/etc/hosts")
        XCTAssertEqual(ref.filename, "hosts")
    }

    func testV1ImageHashKeepsItsHash() throws {
        let items = try decode("""
        [{"id":"22222222-2222-2222-2222-222222222222","date":1000,
          "content":{"type":"image","imageHash":"abc123"}}]
        """)
        guard case .image(let ref) = items[0].content else { return XCTFail("not image") }
        XCTAssertEqual(ref.hash, "abc123")
        XCTAssertEqual(ref.ext, "png")
    }

    func testOneCorruptRowDoesNotTakeTheWholeFile() throws {
        let items = try decode("""
        [{"id":"11111111-1111-1111-1111-111111111111","date":1000,
          "content":{"type":"text","text":"first"}},
         {"id":"55555555-5555-5555-5555-555555555555","date":1001,
          "content":{"type":"wingdings"}},
         {"id":"66666666-6666-6666-6666-666666666666","date":1002,
          "content":{"type":"text","text":"last"}}]
        """)
        XCTAssertEqual(items.count, 2, "the unreadable row should be dropped, not the file")
        XCTAssertEqual(items.last?.content.searchableText, "last")
    }

    func testEncodingAlwaysWritesV2AndRoundTrips() throws {
        let original = ClipItem(content: .text("round trip"), sourceAppName: "Finder")
        let data = try JSONEncoder().encode([original])
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let content = try XCTUnwrap(raw[0]["content"] as? [String: Any])
        XCTAssertEqual(content["v"] as? Int, 2)

        let restored = try JSONDecoder().decode([ClipItem].self, from: data)
        XCTAssertEqual(restored[0].id, original.id)
        XCTAssertEqual(restored[0].content, original.content)
        XCTAssertEqual(restored[0].sourceAppName, "Finder")
    }

    func testPinnedFlagSurvivesEncoding() throws {
        let pinned = ClipItem(content: .text("keep me"), isPinned: true)
        let data = try JSONEncoder().encode([pinned])
        let restored = try JSONDecoder().decode([ClipItem].self, from: data)
        XCTAssertTrue(restored[0].isPinned)
    }

    func testDerivedPropertiesForGarbageCollection() {
        let ref = BlobRef(hash: "deadbeef", uti: UTType.png.identifier, ext: "png", byteCount: 42)
        XCTAssertEqual(ClipContent.image(ref).blobHashes, ["deadbeef"])
        XCTAssertEqual(ClipContent.image(ref).storedByteCount, 42)
        XCTAssertTrue(ClipContent.text("x").blobHashes.isEmpty)
        XCTAssertEqual(ClipContent.text("x").storedByteCount, 0,
                       "text costs no disk and must never be evicted for space")

        let file = FileRef(path: "/etc/hosts", filename: "hosts", uti: "public.data", byteCount: 999)
        let referenced = ClipContent.files([.reference(file)])
        XCTAssertEqual(referenced.storedByteCount, 0, "a reference stores nothing of its own")
        XCTAssertTrue(referenced.hasLinkedFiles)
        XCTAssertEqual(referenced.referencedPaths, ["/etc/hosts"])
    }

    func testPlainTextExtraction() {
        XCTAssertEqual(ClipItem(content: .text("plain")).plainText, "plain")
        let rich = ClipItem(
            content: .blob(BlobRef(hash: "h", uti: UTType.rtf.identifier, ext: "rtf", byteCount: 1)),
            sidecarText: "the words")
        XCTAssertEqual(rich.plainText, "the words")
        let image = ClipItem(content: .image(BlobRef(hash: "h", uti: "public.png", ext: "png", byteCount: 1)))
        XCTAssertNil(image.plainText)
        XCTAssertFalse(image.canCopyAsPlainText)
    }
}
