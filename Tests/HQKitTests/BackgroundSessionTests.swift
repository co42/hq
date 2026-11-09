import Foundation
import Testing
@testable import HQKit

@Test func backgroundSessionHandles() {
    let agents = Data("""
    [{"id":"84acac78","sessionId":"84acac78-ccc3-4ff9-b761-c737c7acd763","kind":"background","state":"done"},
     {"id":null,"sessionId":"9fde7d51-4f20-4f72-9a6b-df70031044a3","kind":"interactive","state":null}]
    """.utf8)
    #expect(BackgroundSession.handle(of: "84acac78-ccc3-4ff9-b761-c737c7acd763", agents: agents) == "84acac78")
    #expect(BackgroundSession.handle(of: "9fde7d51-4f20-4f72-9a6b-df70031044a3", agents: agents) == nil)
    #expect(BackgroundSession.handle(of: "unknown", agents: agents) == nil)
    #expect(BackgroundSession.handle(of: "84acac78-ccc3-4ff9-b761-c737c7acd763", agents: Data("not json".utf8)) == nil)
}

@Test func backgroundSessionTerminal() {
    typealias Terminal = BackgroundSession.Terminal
    let titled = Terminal(tty: "/dev/ttys006", title: "✳ HQ - Slack")
    let other = Terminal(tty: "/dev/ttys001", title: "◐ HQ - Dev")
    let claude: (String) -> Bool = { _ in true }
    // The only tab titled with its name, Claude's status glyph aside, whichever session owns the tab.
    #expect(BackgroundSession.terminal(showing: "HQ - Slack", among: [other, titled], runsClaude: claude) == titled.tty)
    // Not when that tab runs no Claude, nor when two tabs have the title.
    #expect(BackgroundSession.terminal(showing: "HQ - Slack", among: [titled], runsClaude: { _ in false }) == nil)
    let twin = Terminal(tty: "/dev/ttys010", title: "⠂ HQ - Slack")
    #expect(BackgroundSession.terminal(showing: "HQ - Slack", among: [titled, twin], runsClaude: claude) == nil)
    #expect(BackgroundSession.terminal(showing: "HQ - Slack", among: [other], runsClaude: claude) == nil)
    #expect(BackgroundSession.title("✳ HQ - Slack") == "HQ - Slack")
    #expect(BackgroundSession.title("HQ - Slack") == "HQ - Slack")
}
