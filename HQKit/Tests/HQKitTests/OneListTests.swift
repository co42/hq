import Foundation
import Testing
@testable import HQKit

// MARK: The backlog status

@Test func backlogIsAStatus() {
    #expect(TaskStatus(parsing: "Backlog") == .backlog)
    #expect(TaskStatus(parsing: "review") == .doing)
    #expect(TaskStatus.allCases.first == .backlog)
    #expect([TaskStatus.backlog, .todo, .doing, .done].map(\.next) == [.todo, .doing, .done, .todo])
    #expect(TaskStatus.todo.isOpen && TaskStatus.doing.isOpen && !TaskStatus.backlog.isOpen && !TaskStatus.done.isOpen)
}

@Test func doingTakesBacklogParentsToTodo() {
    let parents: [Int: Int] = [3: 2, 2: 1]
    let statuses: [Int: TaskStatus] = [1: .backlog, 2: .todo, 3: .todo]
    #expect(TaskStatus.backlogAncestors(of: 3, parent: { parents[$0] }, status: { statuses[$0] }) == [1])
    #expect(TaskStatus.backlogAncestors(of: 1, parent: { parents[$0] }, status: { statuses[$0] }).isEmpty)
    // A loop in the parents ends.
    #expect(TaskStatus.backlogAncestors(of: 1, parent: { $0 == 1 ? 2 : 1 }, status: { _ in .backlog }) == [2])
}

@Test func togglesHideBacklogAndDone() {
    let rest = TaskShow()
    #expect(rest.hides(.backlog, openBelow: false) && rest.hides(.backlog, openBelow: true))
    #expect(rest.hides(.done, openBelow: false) && !rest.hides(.done, openBelow: true))
    #expect(!rest.hides(.todo, openBelow: false) && !rest.hides(.doing, openBelow: false))
    let all = TaskShow(backlog: true, done: true)
    #expect(TaskStatus.allCases.allSatisfy { !all.hides($0, openBelow: false) })
}

@Test func backlogIsLaterNeverReady() {
    let flow = TaskFlow([
        .init(id: 1, later: true),
        .init(id: 2, parent: 1),
        .init(id: 3, parent: 1, done: true),
        .init(id: 4, parent: 1, blocked: true),
        .init(id: 5),
        .init(id: 6, parent: 5, later: true),
    ])
    #expect(flow.state(1) == .later && flow.state(2) == .later)
    #expect(flow.state(3) == .done && flow.state(4) == .blocked)
    #expect(flow.state(5) == .ready && flow.state(6) == .later)
    let tally = flow.tally(of: 1)
    #expect(tally.later == 1 && tally.done == 1 && tally.blocked == 1 && tally.ready == 0 && tally.total == 3)
}

// MARK: The one-list move

@Test func oneListMergesTheLists() {
    let notes: [TaskMigration.ListedNote] = [
        .init(id: 1, topLevel: true, list: "overview", status: "doing", order: 2),
        .init(id: 2, topLevel: true, list: "overview", status: "todo", order: 1),
        .init(id: 3, topLevel: true, list: "backlog", status: "todo", order: 0.5),
        .init(id: 4, topLevel: true, list: "backlog", status: "done", order: 3),
        .init(id: 5, topLevel: true, list: "backlog", status: nil, order: 4),
        .init(id: 6, topLevel: false, list: nil, status: "todo", order: 1),
        .init(id: 7, topLevel: false, list: "backlog", status: "todo", order: 2),
    ]
    let plan = TaskMigration.oneList(notes)
    #expect(plan[2] == .init(status: nil, order: 1) && plan[1] == .init(status: nil, order: 2))
    #expect(plan[3] == .init(status: .backlog, order: 3) && plan[4] == .init(status: nil, order: 4))
    #expect(plan[5] == .init(status: .backlog, order: 5))
    // A subtask keeps its status and order; one with a stray list key only loses it.
    #expect(plan[6] == nil && plan[7] == .init(status: nil, order: nil))
}

@Test func oneListRunsOnceAndPlacesStraysLast() {
    let moved: [TaskMigration.ListedNote] = [
        .init(id: 1, topLevel: true, list: nil, status: "doing", order: 1),
        .init(id: 2, topLevel: true, list: nil, status: "backlog", order: 2),
    ]
    #expect(TaskMigration.oneList(moved).isEmpty)
    let stray = moved + [.init(id: 9, topLevel: true, list: "overview", status: "todo", order: 0)]
    #expect(TaskMigration.oneList(stray) == [9: .init(status: nil, order: 3)])
}

// MARK: The Archive

private let day: TimeInterval = 86_400
private let now = NoteDate.parse("2026-11-16T12:00")!

@Test func archiveTakesDoneStoriesAfterTheDelay() {
    let children: [Int: [Int]] = [1: [2], 3: [4], 5: [], 6: [], 7: []]
    let statuses: [Int: TaskStatus] = [1: .done, 2: .done, 3: .done, 4: .todo, 5: .done, 6: .done, 7: .todo]
    let done: [Int: Date] = [1: now - 8 * day, 3: now - 30 * day, 5: now - 2 * day, 6: now - 7 * day]
    func subtree(_ id: Int) -> [Int] { [id] + (children[id] ?? []).flatMap(subtree) }
    let due = TaskArchive.due(roots: [1, 3, 5, 6, 7], subtree: subtree, status: { statuses[$0] }, done: { done[$0] }, now: now, delayDays: 7)
    // 3 still holds an open task, 5 is too recent, 7 is open.
    #expect(due == [1, 6])
    let sooner = TaskArchive.due(roots: [1, 3, 5, 6, 7], subtree: subtree, status: { statuses[$0] }, done: { done[$0] }, now: now, delayDays: 1)
    #expect(sooner == [1, 5, 6])
    #expect(TaskArchive.delayChoices.contains(TaskArchive.defaultDelay))
}

private func sampleIndex() -> ArchiveIndex {
    ArchiveIndex(entries: [
        .init(id: 342, root: 342, title: "HQ v12", status: .done, project: "HQ", archived: now - 1 * day, modified: now),
        .init(id: 348, root: 342, parent: 342, title: "Drag-drop anything into the terminal", status: .done, archived: now - 1 * day, modified: now),
        .init(id: 359, root: 342, parent: 342, title: "Drop a task onto a task", status: .done, archived: now - 1 * day, modified: now),
        .init(id: 46, root: 46, title: "Build the HQ cockpit", status: .done, project: "HQ", tags: ["perf"], archived: now - 9 * day, modified: now),
        .init(id: 51, root: 46, parent: 46, title: "Drag and drop tasks between the lists", status: .done, archived: now - 9 * day, modified: now),
        .init(id: 244, root: 244, title: "Release hf-image 0.5.0", status: .done, project: "Registry", archived: now - 2 * day, modified: now),
        .init(id: 315, root: 315, title: "Slack safety net, déjà vu", status: .backlog, project: "HQ", archived: now, modified: now),
    ])
}

@Test func archiveSearchFindsStoriesAndTasksUnder() {
    let index = sampleIndex()
    #expect(index.highestKey == 359)
    #expect(index.stories.map(\.id) == [315, 342, 244, 46])
    let searcher = ArchiveIndex.Searcher(index)
    #expect(searcher.search("").map(\.story.id) == [315, 342, 244, 46])
    #expect(searcher.search("").first { $0.story.id == 342 }?.count == 2)
    let drag = searcher.search("DRAG")
    #expect(drag.map(\.story.id) == [342, 46])
    #expect(drag[0].under.map(\.id) == [348] && drag[1].under.map(\.id) == [51])
    // Every word, in the title, key, project or #tag; a task under a story takes the story's project.
    #expect(searcher.search("registry 0.5").map(\.story.id) == [244])
    #expect(searcher.search("t-46").map(\.story.id) == [46])
    #expect(searcher.search("#perf").map(\.story.id) == [46])
    #expect(searcher.search("hq terminal").first?.under.map(\.id) == [348])
    #expect(searcher.search("deja").map(\.story.id) == [315])
    #expect(searcher.search("nothing here").isEmpty)
}

@Test func archiveIndexAddsAndRemovesStories() throws {
    var index = sampleIndex()
    index.remove(story: 342)
    #expect(index.entry(348) == nil && index.stories.map(\.id) == [315, 244, 46])
    index.add([.init(id: 46, root: 46, title: "Renamed", status: .done, archived: now, modified: now)])
    #expect(index.entries.filter { $0.id == 46 }.count == 1 && index.entry(46)?.title == "Renamed")
    #expect(index.tasks(under: 46).map(\.id) == [51])
    let data = try JSONEncoder().encode(index)
    #expect(try JSONDecoder().decode(ArchiveIndex.self, from: data) == index)
}

@Test func archiveSearchOverTenThousandIsQuick() {
    var entries: [ArchiveIndex.Entry] = []
    for story in 0..<2_000 {
        let root = story * 5 + 1
        entries.append(.init(id: root, root: root, title: "Story \(story) about registries and pushes", status: .done, project: "P\(story % 7)",
                             archived: now - Double(story) * 3_600, modified: now))
        for kid in 1...4 {
            entries.append(.init(id: root + kid, root: root, parent: root, title: "Step \(kid) of story \(story): measure the pulls",
                                 status: .done, archived: now, modified: now))
        }
    }
    let searcher = ArchiveIndex.Searcher(ArchiveIndex(entries: entries))
    #expect(searcher.count == 2_000)
    let clock = ContinuousClock()
    var found = 0
    let took = clock.measure { found = searcher.search("story 1999: pulls").count }
    #expect(found == 1)
    // Debug builds run several times slower than the app; the app's own budget is 16 ms a keystroke.
    #expect(took < .milliseconds(150))
}

@Test func archiveGroupsByWeekThenMonth() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    calendar.firstWeekday = 2
    let monday = NoteDate.parse("2026-11-16T12:00")!
    #expect(ArchiveIndex.group(monday, now: monday, calendar: calendar) == .thisWeek)
    #expect(ArchiveIndex.group(monday - 2 * day, now: monday, calendar: calendar) == .lastWeek)
    #expect(ArchiveIndex.group(monday - 20 * day, now: monday, calendar: calendar) == .month(year: 2026, month: 10))
}
