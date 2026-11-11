import Foundation
import HQKit

/// A task with every kind of link, for the links on a card (T-377) and a Slack message too long for a line (T-429).
extension SeedData {
    static let longSlackLink = "https://example.slack.com/archives/C0EXAMPLE2/p1762500000000200"
    static let longSlackMessage = SlackMessage(channel: "registry-incidents", author: "Julien",
        text: "Heads-up on the eu-west upload retries: the canary went red again overnight after the S3 client bump, every multipart complete above 5 GB retried three times before failing, the retry budget never kicked in because the parts were counted per layer instead of per upload, and the on-call had to restart the registry pods twice to clear the queue before the morning traffic peak\nCan you look before Monday's release? The dashboards are in the thread.")
    static let webLink = "https://status.example.com/incidents/2026-11-10/eu-west/registry-uploads/multipart-complete-retries/timeline"
    /// An issue GitHub hasn't brought: its kind's icon, gray (T-433).
    static let unfetchedIssue = "https://github.com/acme/registry/issues/9002"

    /// T-13: its PR, file, artifact and Slack message from the seed, plus a web page, a second, long Slack message and an issue not fetched.
    static func linkEveryKind(_ model: AppModel, task id: Int = 13) {
        model.slackMessages[longSlackLink] = longSlackMessage
        for link in [webLink, longSlackLink, unfetchedIssue] {
            if let url = URL(string: link) { model.link(task: id, url: url) }
        }
    }
}
