import HQKit
import SwiftUI

/// The one place a time is picked (DESIGN.md §11): Later on a row, a reminder's time. Type a time ("tomorrow 9am",
/// "in 2h", "next friday at 3pm") or take a choice; ↑ ↓ move, Return picks. Pick Date & Time… shows a calendar.
struct WhenPicker: View {
    let now: Date
    let pick: (Date) -> Void
    @State private var text = ""
    @State private var index = 0
    @State private var calendar = false
    @State private var custom: Date
    @FocusState private var typing: Bool

    init(now: Date, current: Date? = nil, pick: @escaping (Date) -> Void) {
        self.now = now
        self.pick = pick
        _custom = State(initialValue: current ?? ReminderTime.date(.tomorrow, now: now))
    }

    private struct Choice: Identifiable {
        let id: String
        let title: String
        let detail: String
        let date: Date?
    }

    private var choices: [Choice] {
        var rows: [Choice] = []
        let typed = text.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty {
            let date = ReminderTime.parse(typed, now: now)
            rows.append(Choice(id: "typed", title: date.map(ReminderTime.full) ?? "Type a time: 16:00, tomorrow 9am, in 2h, fri",
                               detail: "", date: date))
        }
        rows += ReminderTime.Preset.available(now: now).map {
            let date = ReminderTime.date($0, now: now)
            return Choice(id: $0.rawValue, title: $0.title, detail: ReminderTime.brief(date, now: now), date: date)
        }
        return rows
    }

    var body: some View {
        let rows = choices
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Tomorrow 9am, in 2h, fri…", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($typing)
                .onChange(of: text) { index = 0 }
                .onKeyPress(.downArrow) { index = min(index + 1, rows.count); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .onSubmit { choose(rows) }
                .uiTestAnchor("when-field")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { position, choice in
                    Button { if let date = choice.date { pick(date) } } label: {
                        line(choice.title, detail: choice.detail, highlighted: position == index, dim: choice.date == nil)
                    }
                    .buttonStyle(.plain)
                    .clickable()
                    .disabled(choice.date == nil)
                    .accessibilityAddTraits(position == index ? .isSelected : [])
                    .onHover { if $0 { index = position } }
                    .uiTestAnchor("when:\(choice.id)")
                }
                Button { calendar.toggle() } label: {
                    line("Pick Date & Time…", detail: "", icon: .pickDate, highlighted: index == rows.count)
                }
                .buttonStyle(.plain)
                .clickable()
                .onHover { if $0 { index = rows.count } }
                .uiTestAnchor("when-calendar")
            }
            if calendar {
                Divider()
                DatePicker("Day", selection: $custom, in: now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                HStack(spacing: Space.sm) {
                    DatePicker("Time", selection: $custom, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                    Spacer(minLength: Space.sm)
                    Button("Set") { pick(custom) }
                        .buttonStyle(.glassProminent)
                        .clickable()
                        .disabled(custom <= now)
                        .uiTestAnchor("when-set")
                }
            }
        }
        .padding(Space.md)
        .frame(width: Metric.whenPicker)
        .onAppear { typing = true }
    }

    /// Return: the highlighted choice, or the calendar.
    private func choose(_ rows: [Choice]) {
        if rows.indices.contains(index) {
            if let date = rows[index].date { pick(date) }
        } else {
            calendar.toggle()
        }
    }

    private func line(_ title: String, detail: String, icon: KitIcon? = nil, highlighted: Bool, dim: Bool = false) -> some View {
        HStack(spacing: Space.sm) {
            if let icon { icon.image.foregroundStyle(.secondary) }
            Text(title).kitType(.title).lineLimit(1).foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Spacer(minLength: Space.sm)
            Text(detail).kitType(.meta).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: Metric.boxRow)
        .background(highlighted ? Ink.rowSelection : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .contentShape(Rectangle())
    }
}
