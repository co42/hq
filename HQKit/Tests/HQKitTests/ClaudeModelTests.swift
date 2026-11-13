import Foundation
import Testing
@testable import HQKit

@Test func modelFamilyAndEffortShort() {
    #expect(ClaudeModel.family("claude-opus-5-5") == "Opus")
    #expect(ClaudeModel.family("claude-opus-5-5[1m]") == "Opus")
    #expect(ClaudeModel.family("sonnet") == "Sonnet")
    #expect(ClaudeModel.family("claude-fable-5-2") == "Fable")
    #expect(ClaudeModel.family("gpt-x") == "gpt-x")
    #expect(ClaudeModel.shortEffort("xhigh") == "VH")
    #expect(ClaudeModel.shortEffort("medium") == "M")
    #expect(ClaudeModel.effortTitle("xhigh") == "Very High")
    #expect(ClaudeModel.shortTokens(441_898) == "442k")
    #expect(ClaudeModel.shortTokens(800) == "800")
}

@Test func claudeCodesOwnDefaults() throws {
    let path = NSTemporaryDirectory() + "settings-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: path) }
    try #"{"model":"opus","effortLevel":"high","theme":"dark"}"#.write(toFile: path, atomically: true, encoding: .utf8)
    #expect(ClaudeModel.defaults(settings: path) == ("opus", "high"))
    try #"{"effortLevel":"huge"}"#.write(toFile: path, atomically: true, encoding: .utf8)
    #expect(ClaudeModel.defaults(settings: path) == (nil, nil))
    #expect(ClaudeModel.defaults(settings: path + ".none") == (nil, nil))
}

@Test func usageFromTheLastMainReply() {
    let lines = [
        #"{"type":"assistant","effort":"high","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":10,"output_tokens":5}}}"#,
        #"{"type":"assistant","effort":"xhigh","message":{"model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":1032,"cache_read_input_tokens":440864,"output_tokens":143}}}"#,
        #"{"type":"assistant","isSidechain":true,"effort":"low","message":{"model":"claude-haiku-5-5","usage":{"input_tokens":9}}}"#,
        #"{"type":"assistant","message":{"model":"<synthetic>","usage":{"input_tokens":0}}}"#,
        #"{"type":"user","message":{"content":"hi"}}"#,
    ]
    let usage = ClaudeModel.usage(in: lines.joined(separator: "\n"))
    #expect(usage == ClaudeModel.Usage(model: "claude-opus-5-5", effort: "xhigh", contextTokens: 442_041))
    #expect(ClaudeModel.usage(in: lines[4]) == nil)
    let dated = #"{"type":"assistant","timestamp":"2026-11-13T12:34:56.789Z","message":{"model":"claude-opus-5-5"}}"#
    #expect(ClaudeModel.usage(in: dated)?.at == (try? Date("2026-11-13T12:34:56.789Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))))
}
