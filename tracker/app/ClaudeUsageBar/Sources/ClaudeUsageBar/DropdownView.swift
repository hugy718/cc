import SwiftUI
import ClaudeUsageBarCore

func color(for pct: Double) -> Color {
    switch UsageLevel(percentage: pct) {
    case .low: return .green
    case .medium: return .yellow
    case .high: return .red
    }
}

struct WindowRow: View {
    let title: String
    let window: DisplayWindow
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(window.usedPercentage.rounded()))%")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundColor(color(for: window.usedPercentage))
            }
            ProgressView(value: min(window.usedPercentage, 100), total: 100)
                .tint(color(for: window.usedPercentage))
            HStack(spacing: 6) {
                Text("resets \(resetText)").font(.system(size: 11.5)).foregroundColor(.secondary)
                if window.didReset { Circle().fill(Color.yellow).frame(width: 6, height: 6) }
                if window.isStale { Text("· stale").font(.system(size: 10.5)).foregroundColor(.secondary) }
            }
        }
    }
}

struct DropdownView: View {
    @ObservedObject var viewModel: UsageViewModel
    let resetText: (Date) -> String
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let e = viewModel.evaluated {
                if let fh = e.fiveHour { WindowRow(title: "5-hour", window: fh, resetText: resetText(fh.resetsAt)) }
                if let sd = e.sevenDay { WindowRow(title: "Weekly", window: sd, resetText: resetText(sd.resetsAt)) }
            } else {
                Text("No data yet — use Claude Code once to populate.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Divider()
            HStack {
                Text(viewModel.updatedAgoText).font(.system(size: 11.5)).foregroundColor(.secondary)
                Spacer()
                Button("Refresh", action: onRefresh).font(.system(size: 11.5))
                Button("Quit", action: onQuit).font(.system(size: 11.5))
            }
            if let note = viewModel.noteText {
                Text(note).font(.system(size: 11)).foregroundColor(.orange)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
