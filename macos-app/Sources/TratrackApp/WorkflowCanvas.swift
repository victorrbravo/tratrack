import SwiftUI

/// The workflow drawn as a route of taped sticky notes.
struct WorkflowCanvas: View {
    let kicker: String
    let title: String
    let steps: [Step]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker.uppercased())
                    .font(.system(size: 13, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(Paper.muted)
                Text(title)
                    .font(.system(size: 56, weight: .bold))
                    .tracking(-1.5)
                    .foregroundStyle(Paper.ink)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Paper.ink)
                    .frame(width: 48, height: 3)
                    .padding(.top, 14)

                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 22, weight: .ultraLight))
                                .foregroundStyle(Paper.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                        }
                        let layout = NoteLayout(index: index)
                        StepCard(step: step, layout: layout)
                            .frame(maxWidth: 560)
                            .padding(.leading, layout.inset)
                            .frame(maxWidth: .infinity, alignment: layout.alignment)
                        if let total = step.dayTotal {
                            DayTotalView(total: total)
                                .padding(.top, 34)
                                .padding(.bottom, index == steps.count - 1 ? 0 : 6)
                        }
                    }
                }
                .padding(.top, 48)

                Text(footer)
                    .font(.system(size: 15))
                    .foregroundStyle(Paper.muted)
                    .padding(.top, 48)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 56)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(Paper.background)
    }

    /// e.g. "Jun 28 – Jul 1 · 12 steps"
    private var footer: String {
        var parts: [String] = []
        let times = steps.compactMap(\.time)
        if let first = times.min(), let last = times.max() {
            let day = Date.FormatStyle().month(.abbreviated).day()
            let start = first.formatted(day), end = last.formatted(day)
            parts.append(start == end ? start : "\(start) – \(end)")
        }
        parts.append(steps.count == 1 ? "1 step" : "\(steps.count) steps")
        return parts.joined(separator: " · ")
    }
}

struct StepCard: View {
    let step: Step
    let layout: NoteLayout

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Paper.ink)
                .frame(width: 44)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "STEP %02d", step.number))
                    .font(.system(size: 13, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(Paper.ink.opacity(0.75))
                Text(step.name)
                    .font(.custom("Bradley Hand", size: 38).bold())
                    .foregroundStyle(Paper.ink)
                let summary = step.summary.flatMap { $0.isEmpty ? nil : $0 } ?? step.nextDescription
                Text(summary)
                    .font(.custom("Noteworthy", size: 17))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .foregroundStyle(Paper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(summary)
                if let time = step.time {
                    Label(
                        time.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year().hour().minute()),
                        systemImage: "clock"
                    )
                    .font(.custom("Noteworthy", size: 16).bold())
                    .foregroundStyle(Paper.ink.opacity(0.85))
                    .padding(.top, 4)
                }
                if !details.isEmpty {
                    Text(details)
                        .font(.custom("Noteworthy", size: 15))
                        .foregroundStyle(Paper.ink.opacity(0.7))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 34)
        .background(layout.color)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.55))
                .frame(width: 100, height: 28)
                .offset(y: -14)
        }
        .shadow(color: .black.opacity(0.14), radius: 1.5, y: -1)
        .rotationEffect(.degrees(layout.tilt))
    }

    /// Amount and attached videos, e.g. "$14,950.00 · 1 video".
    private var details: String {
        var parts: [String] = []
        if let amount = step.amount {
            parts.append(amount)
        }
        if step.videoCount > 0 {
            parts.append(step.videoCount == 1 ? "1 video" : "\(step.videoCount) videos")
        }
        return parts.joined(separator: " · ")
    }

    /// Picks an icon from the first keyword group the step mentions.
    private var icon: String {
        let groups: [(String, Set<String>)] = [
            ("cup.and.saucer", ["coffee", "café", "cafés", "cafe", "capuchino", "frapuchino", "juice"]),
            ("fork.knife", ["restaurant", "lunch", "dinner", "breakfast", "eatery", "dining"]),
            ("basket", ["groceries", "market", "bakery", "bread"]),
            ("fuelpump", ["gas", "fuel"]),
            ("play.tv", ["streaming", "music"]),
            ("paperplane", ["sent", "transfer"]),
            ("doc.text", ["bill"]),
        ]
        let words = step.keywords
        return groups.first { !$0.1.isDisjoint(with: words) }?.0 ?? "mappin.and.ellipse"
    }
}

/// The end-of-day marker from `transition.wrapped`.
struct DayTotalView: View {
    let total: WorkflowTask.DayTotal

    var body: some View {
        HStack(spacing: 14) {
            line
            VStack(spacing: 2) {
                Text((total.label ?? "Day total").uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(Paper.muted)
                if let amount = total.amount {
                    Text(amount)
                        .font(.custom("Bradley Hand", size: 24).bold())
                        .foregroundStyle(Paper.ink)
                }
            }
            .fixedSize()
            line
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private var line: some View {
        Rectangle()
            .fill(Paper.muted.opacity(0.35))
            .frame(height: 1)
    }
}

/// Position, tilt and color of a note, cycling so the route zigzags.
struct NoteLayout {
    let alignment: Alignment
    let inset: CGFloat
    let tilt: Double
    let color: Color

    init(index: Int) {
        let positions: [(Alignment, CGFloat, Double)] = [
            (.leading, 0, -1.2),
            (.trailing, 0, 0.9),
            (.leading, 56, -0.8),
        ]
        (alignment, inset, tilt) = positions[index % positions.count]
        color = Paper.notes[index % Paper.notes.count]
    }
}

/// Fixed paper palette: the canvas looks the same in light and dark mode.
enum Paper {
    static let background = Color(hex: 0xF3F3EF)
    static let ink = Color(hex: 0x1E1E1E)
    static let muted = Color(hex: 0x5C5C58)
    static let notes = [
        Color(hex: 0xFBE48C), // yellow
        Color(hex: 0xBFE6D3), // mint
        Color(hex: 0xF8C0A8), // peach
        Color(hex: 0xD9D0F2), // lavender
        Color(hex: 0xC6DDF5), // sky
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
