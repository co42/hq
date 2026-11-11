import HQKit
import Testing

@Test func quickOpenFindsTheWordBeforeScatteredLetters() {
    let whole = Fuzzy.match("retry", in: "registry: retry budget")
    #expect(whole?.offsets == Array(10..<15))
    let scattered = Fuzzy.match("retry", in: "registry rollout")
    #expect((whole?.score ?? 0) > (scattered?.score ?? 0))
    #expect(Fuzzy.match("rb", in: "retry budget")?.offsets == [0, 6])
}
