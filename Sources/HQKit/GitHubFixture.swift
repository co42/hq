import Foundation

/// One poll's answer from GitHub, for the unit tests and for test runs (`HQ_GITHUB=fixtures`),
/// which never reach the network. Its dates are relative to `reference`.
public enum GitHubFixture {
    public static let reference = ISO8601DateFormatter().date(from: "2026-11-04T16:00:00Z")!
    public static let linked = ["https://github.com/acme/image-sync/issues/77", "https://github.com/acme/registry/pull/405"]

    public static let poll = Data(#"""
    {"data": {
      "viewer": {"login": "alex"},
      "rateLimit": {"remaining": 4990, "resetAt": "2026-11-04T17:00:00Z"},
      "review": {"nodes": [
        {"__typename": "PullRequest", "url": "https://github.com/acme/static-cdn/pull/512", "number": 512,
         "title": "Coalesce adjacent chunk ranges", "isDraft": false, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T14:00:00Z", "body": "Merges adjacent range requests before they reach the chunk bridge.\n\nGoes with the prefetch window work.",
         "author": {"login": "noor"}, "repository": {"nameWithOwner": "acme/static-cdn"}, "headRefName": "noor/coalesce-ranges",
         "reviewDecision": "REVIEW_REQUIRED", "latestReviews": {"nodes": []},
         "timelineItems": {"nodes": [{"createdAt": "2026-11-04T13:58:00Z", "requestedReviewer": {"__typename": "User", "login": "alex"}},
                                    {"createdAt": "2026-11-04T14:30:00Z", "requestedReviewer": {"__typename": "User", "login": "theo"}}]},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-04T13:55:00Z", "statusCheckRollup": {"state": "SUCCESS",
           "contexts": {"nodes": [{"__typename": "CheckRun", "name": "ci / test", "conclusion": "SUCCESS", "status": "COMPLETED"},
                                  {"__typename": "CheckRun", "name": "ci / lint", "conclusion": "SUCCESS", "status": "COMPLETED"}]}}}}]}},
        {"__typename": "PullRequest", "url": "https://github.com/acme/registry/pull/430", "number": 430,
         "title": "Bump tokio to 1.48", "isDraft": false, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T15:35:00Z", "body": "Routine bump, no API changes.",
         "author": {"login": "theo"}, "repository": {"nameWithOwner": "acme/registry"}, "headRefName": "theo/tokio-1.48",
         "reviewDecision": "REVIEW_REQUIRED", "latestReviews": {"nodes": []},
         "timelineItems": {"nodes": [{"createdAt": "2026-11-04T15:32:00Z", "requestedReviewer": {"__typename": "Team"}}]},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-04T15:30:00Z", "statusCheckRollup": {"state": "PENDING",
           "contexts": {"nodes": [{"__typename": "CheckRun", "name": "ci / test", "conclusion": null, "status": "IN_PROGRESS"}]}}}}]}},
        {"__typename": "PullRequest", "url": "https://github.com/acme/storage-core/pull/233", "number": 233,
         "title": "Shard compaction metrics", "isDraft": false, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T12:10:00Z", "body": "Counts compactions per shard.",
         "author": {"login": "ines"}, "repository": {"nameWithOwner": "acme/storage-core"}, "headRefName": "ines/compaction-metrics",
         "reviewDecision": "REVIEW_REQUIRED",
         "latestReviews": {"nodes": [{"author": {"login": "alex"}, "state": "COMMENTED", "submittedAt": "2026-11-04T12:00:00Z"}]},
         "timelineItems": {"nodes": [{"createdAt": "2026-11-04T10:30:00Z", "requestedReviewer": {"__typename": "User", "login": "alex"}}]},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-04T11:00:00Z", "statusCheckRollup": {"state": "SUCCESS", "contexts": {"nodes": []}}}}]}}
      ]},
      "reviewed": {"nodes": [
        {"__typename": "PullRequest", "url": "https://github.com/acme/registry/pull/433", "number": 433,
         "title": "Cache manifest lookups", "isDraft": false, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T09:40:00Z", "body": "Caches manifest lookups for a minute.",
         "author": {"login": "noor"}, "repository": {"nameWithOwner": "acme/registry"}, "headRefName": "noor/manifest-cache",
         "reviewDecision": "REVIEW_REQUIRED",
         "latestReviews": {"nodes": [{"author": {"login": "alex"}, "state": "APPROVED", "submittedAt": "2026-11-04T09:30:00Z"}]},
         "timelineItems": {"nodes": [{"createdAt": "2026-11-04T09:00:00Z", "requestedReviewer": {"__typename": "User", "login": "alex"}}]},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-04T08:50:00Z", "statusCheckRollup": {"state": "SUCCESS", "contexts": {"nodes": []}}}}]}}
      ]},
      "mine": {"nodes": [
        {"__typename": "PullRequest", "url": "https://github.com/acme/registry/pull/418", "number": 418,
         "title": "Retry budget for blob uploads", "isDraft": false, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T15:40:00Z", "body": "Adds a per-upload retry budget to blob uploads.\n\n- `RetryBudget` in `upload::retry`, shared by the parts of one upload\n- A `503` on multipart complete retries once\n- `registry_upload_retries_total`, by reason",
         "author": {"login": "alex"}, "repository": {"nameWithOwner": "acme/registry"}, "headRefName": "retry-budget",
         "reviewDecision": "APPROVED",
         "latestReviews": {"nodes": [{"author": {"login": "noor"}, "state": "APPROVED", "submittedAt": "2026-11-04T15:40:00Z"}]},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-04T14:20:00Z", "statusCheckRollup": {"state": "SUCCESS",
           "contexts": {"nodes": [{"__typename": "CheckRun", "name": "ci / test", "conclusion": "SUCCESS", "status": "COMPLETED"},
                                  {"__typename": "CheckRun", "name": "ci / clippy", "conclusion": "SUCCESS", "status": "COMPLETED"},
                                  {"__typename": "StatusContext", "context": "canary / registry-staging", "state": "SUCCESS"}]}}}}]}},
        {"__typename": "PullRequest", "url": "https://github.com/acme/image-sync/pull/80", "number": 80,
         "title": "Pull-speed bench", "isDraft": false, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T15:00:00Z", "body": "A reproducible pull-speed bench for image-sync, with dated result folders.",
         "author": {"login": "alex"}, "repository": {"nameWithOwner": "acme/image-sync"}, "headRefName": "pull-bench",
         "reviewDecision": "CHANGES_REQUESTED",
         "latestReviews": {"nodes": [{"author": {"login": "theo"}, "state": "CHANGES_REQUESTED", "submittedAt": "2026-11-04T15:00:00Z"}]},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-03T18:00:00Z", "statusCheckRollup": {"state": "SUCCESS", "contexts": {"nodes": []}}}}]}},
        {"__typename": "PullRequest", "url": "https://github.com/acme/infra-secrets/pull/44", "number": 44,
         "title": "Machine identities in Terraform", "isDraft": true, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T15:25:00Z", "body": "Draft: one machine identity per CDN worker pool.\n\n- [x] Identity module\n- [ ] Wire the worker init container",
         "author": {"login": "alex"}, "repository": {"nameWithOwner": "acme/infra-secrets"}, "headRefName": "machine-identities",
         "reviewDecision": null, "latestReviews": {"nodes": []},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-04T15:20:00Z", "statusCheckRollup": {"state": "PENDING",
           "contexts": {"nodes": [{"__typename": "CheckRun", "name": "terraform / plan", "conclusion": null, "status": "IN_PROGRESS"}]}}}}]}},
        {"__typename": "PullRequest", "url": "https://github.com/acme/static-cdn/pull/520", "number": 520,
         "title": "Prefetch window for the CDN chunk bridge", "isDraft": false, "state": "OPEN", "merged": false,
         "updatedAt": "2026-11-04T15:50:00Z", "body": "Prefetches the next window while serving the current one.",
         "author": {"login": "alex"}, "repository": {"nameWithOwner": "acme/static-cdn"}, "headRefName": "chunk-bridge-prefetch",
         "reviewDecision": "REVIEW_REQUIRED", "latestReviews": {"nodes": []},
         "commits": {"nodes": [{"commit": {"committedDate": "2026-11-04T15:45:00Z", "statusCheckRollup": {"state": "FAILURE",
           "contexts": {"nodes": [{"__typename": "CheckRun", "name": "ci / test", "conclusion": "FAILURE", "status": "COMPLETED"},
                                  {"__typename": "CheckRun", "name": "ci / lint", "conclusion": "SUCCESS", "status": "COMPLETED"}]}}}}]}}
      ]},
      "r0": {"__typename": "Issue", "url": "https://github.com/acme/image-sync/issues/77", "number": 77,
             "title": "Push progress stalls at 99%", "state": "OPEN", "updatedAt": "2026-11-04T15:00:00Z",
             "body": "On large pushes the bar sits at **99%** while the last chunks upload.\n\nSeen with a 12 GB model on image-sync 0.9.",
             "author": {"login": "theo"}, "repository": {"nameWithOwner": "acme/image-sync"}},
      "r1": {"__typename": "PullRequest", "url": "https://github.com/acme/registry/pull/405", "number": 405,
             "title": "Registry GC dry run", "isDraft": false, "state": "MERGED", "merged": true,
             "updatedAt": "2026-11-02T10:00:00Z", "body": "Dry run of the blob GC on staging.",
             "author": {"login": "alex"}, "repository": {"nameWithOwner": "acme/registry"}, "headRefName": "gc-dry-run",
             "reviewDecision": "APPROVED", "latestReviews": {"nodes": [{"author": {"login": "noor"}, "state": "APPROVED", "submittedAt": "2026-11-01T10:00:00Z"}]},
             "commits": {"nodes": [{"commit": {"committedDate": "2026-11-01T09:00:00Z", "statusCheckRollup": {"state": "SUCCESS", "contexts": {"nodes": []}}}}]}}
    }}
    """#.utf8)
}
