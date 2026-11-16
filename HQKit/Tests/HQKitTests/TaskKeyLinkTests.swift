import Foundation
import Testing
@testable import HQKit

/// Task keys in text are links (T-368): as words, never in code, addresses or links.
struct TaskKeyLinkTests {
    private func taskLinks(_ text: String) -> [Int] {
        guard case .paragraph(let parsed)? = Markdown.blocks(text).first else { return [] }
        return parsed.runs.compactMap { $0.link.flatMap(Markdown.taskID) }
    }

    @Test func aKeyAsAWordLinks() {
        #expect(taskLinks("Split into T-47 and (T-48).") == [47, 48])
    }

    @Test func notInCodeAddressesOrLinks() {
        #expect(taskLinks("Code `T-1`, https://x.y/T-2, [T-3](https://x.y), [[T-4 plan]], AT-5, T-6x") == [])
    }
}
