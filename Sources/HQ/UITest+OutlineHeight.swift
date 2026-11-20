import AppKit
import HQKit

/// The page's outline holds its rows at every zoom (T-689): a step of 1.15 makes row heights fractions of a point,
/// which SwiftUI rounds to the screen's pixels; that rounding is no defect, a row cut off is.
extension UITest {
    static func outlineHeight(_ model: AppModel, _ ui: Driver) async {
        guard let story = model.addTask(status: .todo, title: "Zoomed story") else { return await check("a story to grow", false) }
        let logged = AppLog.written["outline.log", default: 0]
        var gaps: [String] = []
        var widest: CGFloat = 0
        for zoom in [1.15, 0.85, 1.3] as [CGFloat] {
            model.zoom = zoom
            await ui.settle(0.4)
            for step in 0..<4 {
                if step % 2 == 0 { _ = model.addSubtask(to: story.id, title: "Step \(step) at \(zoom)") }
                else { _ = model.addTask(status: .todo, title: "Beside \(step) at \(zoom)") }
                // Past the 0.3 s the outline waits before it judges its container.
                try? await Task.sleep(for: .seconds(0.45))
                if let container = ui.find(OutlineContainer.self), container.window != nil {
                    let rows = container.contentHeight
                    widest = max(widest, abs(container.frame.height - rows))
                    gaps.append(String(format: "%.2f: container %.2f, rows %.2f", zoom, container.frame.height, rows))
                }
            }
        }
        model.zoom = 1
        await ui.settle(0.4)
        await check("at zooms 0.85, 1.15 and 1.3 the outline's container holds its rows to the pixel, and logs no defect while they grow",
                    widest <= 0.5 && AppLog.written["outline.log", default: 0] == logged,
                    "\(AppLog.written["outline.log", default: 0] - logged) lines; \(gaps.joined(separator: "; "))")
    }
}
