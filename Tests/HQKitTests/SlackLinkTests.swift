import Foundation
import Testing
@testable import HQKit

@Test func slackMessageLinks() {
    let message = SlackLink("https://example.slack.com/archives/C05ABC123/p1730971234000100")
    #expect(message?.host == "example.slack.com")
    #expect(message?.channel == "C05ABC123")
    #expect(message?.ts == "1730971234.000100")
    #expect(message?.threadTS == nil)
    #expect(message?.isReply == false)

    let reply = SlackLink("https://example.slack.com/archives/C05ABC123/p1730971299000200?thread_ts=1730971234.000100&cid=C05ABC123")
    #expect(reply?.ts == "1730971299.000200")
    #expect(reply?.threadTS == "1730971234.000100")
    #expect(reply?.isReply == true)

    let channel = SlackLink("https://example.slack.com/archives/C05ABC123")
    #expect(channel?.channel == "C05ABC123")
    #expect(channel?.ts == nil)

    #expect(SlackLink("https://example.slack.com/archives/D012/p1730971234000100")?.channel == "D012")
}

@Test func notSlackLinks() {
    #expect(SlackLink("https://github.com/co42/hq/pull/12") == nil)
    #expect(SlackLink("https://slack.com/help/articles/1") == nil)
    #expect(SlackLink("https://example.slack.com/archives/C05ABC123/abc") == nil)
    #expect(SlackLink("https://example.slack.com/client/T01/C05ABC123") == nil)
    #expect(SlackLink("http://example.slack.com/archives/C05ABC123/p1730971234000100") == nil)
    #expect(SlackLink("not a link") == nil)
}

@Test func slackLinkInText() {
    let text = "look at https://example.slack.com/archives/C05ABC123/p1730971234000100 please"
    let found = SlackLink.find(in: text)
    #expect(found?.url == "https://example.slack.com/archives/C05ABC123/p1730971234000100")
    #expect(found.map { String(text[$0.range]) } == found?.url)
    #expect(SlackLink.find(in: "see https://github.com/co42/hq") == nil)
}

@Test func slackMessageText() {
    let message = SlackMessage(channel: "infra", author: "Julien",
                               text: "\n<@U123> can you look at <https://x.dev/a|the dashboard> in <#C1|infra> &amp; <!here>?\nmore")
    #expect(message.firstLine == "@someone can you look at the dashboard in #infra & @here?")
    #expect(message.title == "Julien in #infra: @someone can you look at the dashboard in #infra & @here?")
    #expect(SlackMessage(channel: nil, author: "Julien", text: "hi").title == "Julien: hi")
    #expect(SlackMessage(channel: nil, author: nil, text: "").title == "Slack message")
    #expect(SlackMessage(channel: "infra", author: nil, text: "").title == "#infra")
    #expect(SlackMessage.plain("<@U1|noor> <!channel> <https://a.b>") == "@noor @channel https://a.b")
}
