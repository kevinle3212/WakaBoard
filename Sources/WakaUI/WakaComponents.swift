import SwiftUI
import WakaCore

/// A single headline number on a card.
public struct MetricCard: View {
    let title: String
    let value: String
    let detail: String

    public init(title: String, value: String, detail: String) {
        self.title = title
        self.value = value
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.tight) {
            Text(title).font(.wakaCardTitle).foregroundStyle(.secondary)
            // `value` is sometimes a project or language name, not a number, and those
            // run long. Let it wrap to two lines and shrink before it truncates.
            Text(value)
                .font(.wakaMetricNumeral)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(detail).font(.wakaCaption).foregroundStyle(.secondary).lineLimit(2)
        }
        .wakaCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WakaAccessibility.metricLabel(title: title, value: value, detail: detail))
    }
}

/// One row of a ranked list: name, duration, share bar, and share percentage.
///
/// Extracted so the ranked list and the file-type breakdown sheet render rows
/// identically. Two lists of the same shape that drift apart visually is how an app
/// starts feeling assembled rather than designed.
struct UsageRow: View {
    @Environment(\.colorScheme) private var scheme

    let item: Usage
    let total: TimeInterval
    let icon: String
    /// The palette slot this row's bar is drawn in, matching the charts above it.
    let rank: Int
    /// Set when the row opens something, so it can show that it is actionable.
    var isDrillable = false

    /// The compact share shown beneath this row.
    private var percentage: String {
        WakaAccessibility.sharePercentage(duration: item.duration, total: total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.tight) {
            HStack(spacing: WakaDesign.Spacing.tight) {
                Label(item.name, systemImage: icon).lineLimit(2)
                Spacer(minLength: WakaDesign.Spacing.tight)
                // Keep the duration whole against any name length.
                Text(DurationFormatter().string(item.duration))
                    .font(.wakaInlineNumeral)
                    .lineLimit(1)
                    .layoutPriority(1)
                if isDrillable {
                    Image(systemName: "chevron.right")
                        .font(.wakaCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            // A rank-coloured bar rather than a tinted `ProgressView`: it is the same
            // hue this row carries in the charts above, so the eye can follow one
            // series between the two without re-reading the legend.
            ShareBar(fraction: total > 0 ? item.duration / total : 0, colour: WakaDesign.Palette.series(rank, scheme: scheme))
            Text("\(percentage) of the selected period.")
                .font(.wakaCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, WakaDesign.Spacing.hairline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WakaAccessibility.usageLabel(name: item.name, duration: item.duration, total: total))
    }
}

/// The proportion bar inside a ranked row.
private struct ShareBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary.opacity(0.5))
                Capsule()
                    .fill(colour)
                    .frame(width: max(2, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A segmented control that looks and behaves the same on all six platforms.
///
/// SwiftUI's `.segmented` picker style does not exist on watchOS, is wrong under the
/// tvOS focus engine, and is an AppKit control on the Mac — which means it is also
/// the one thing in the app the snapshot renderer cannot draw, so every committed
/// screenshot carried a yellow "unsupported view" box where the period picker should
/// be. Built from buttons, it is one control everywhere, it honours the token system,
/// and it keeps a 44-point target at every Dynamic Type size.
struct WakaSegmentedPicker<Value: Hashable & Identifiable>: View {
    @Environment(\.colorScheme) private var scheme

    /// Spoken as the control's name; not shown, because each option is labelled.
    let label: String
    let hint: String
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Ask for every label at its natural width. When the row cannot fit, the
            // next candidate preserves the words rather than squeezing them into an
            // ellipsis. The compact Breakdown render exposed this with “Operating
            // Systems”, which left one of the app's five dimensions unreadable.
            HStack(spacing: WakaDesign.Spacing.hairline) {
                ForEach(options) { option in
                    optionButton(option, wrapsTitle: false)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            // Two equal columns keep long labels readable and every option visible
            // on a compact phone or at an accessibility text size. It is a fallback,
            // so wider screens retain the familiar single-row segmented control.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: WakaDesign.Spacing.hairline),
                    GridItem(.flexible())
                ],
                spacing: WakaDesign.Spacing.hairline
            ) {
                ForEach(options) { option in
                    optionButton(option, wrapsTitle: true)
                }
            }
        }
        .padding(WakaDesign.Spacing.hairline)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: WakaDesign.Radius.control))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    /// Produces one option with a readable visual title and complete VoiceOver name.
    @ViewBuilder private func optionButton(_ option: Value, wrapsTitle: Bool) -> some View {
        let isSelected = option == selection
        Button {
            selection = option
        } label: {
            Text(title(option))
                .font(.wakaCardTitle)
                .lineLimit(wrapsTitle ? 2 : 1)
                .minimumScaleFactor(wrapsTitle ? 0.8 : 1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: !wrapsTitle, vertical: false)
                // The label owns the button's accessibility frame. A short title such
                // as “Editors” otherwise exposes a narrow 38-point target on macOS.
                .frame(
                    minWidth: WakaAccessibility.minimumTargetSize,
                    maxWidth: wrapsTitle ? .infinity : nil,
                    minHeight: WakaAccessibility.minimumTargetSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? WakaDesign.Palette.accent(scheme) : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: WakaDesign.Radius.control)
                .fill(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
                .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 2, y: 1)
        )
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// An explanatory state with a single recovery action.
public struct WakaStateView: View {
    let title: String
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    public init(title: String, message: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "chart.bar.xaxis")
        } description: {
            Text(message)
        } actions: {
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: WakaAccessibility.minimumTargetSize, minHeight: WakaAccessibility.minimumTargetSize)
            }
        }
    }
}

/// A banner shown above real data whenever that data is not current.
struct WakaBanner: View {
    let message: String
    let icon: String
    let spokenLabel: String

    var body: some View {
        Label(message, systemImage: icon)
            .font(.footnote)
            .padding(WakaDesign.Spacing.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: WakaDesign.Radius.control))
            .accessibilityLabel(spokenLabel)
    }
}

/// The credit line that appears wherever WakaBoard shows WakaTime's data.
///
/// Not decoration and not a footer to be trimmed for space. Every number on every
/// screen was measured by WakaTime, and a reader who lands on one screen should be
/// able to tell that without opening Settings.
struct WakaTimeCredit: View {
    /// Shows the link as well as the sentence. Off inside dense list footers.
    var showsLink = true

    var body: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.hairline) {
            Text("Coding data is measured and provided by WakaTime. WakaBoard is an "
                 + "independent client and is not affiliated with or endorsed by WakaTime.")
                .font(.wakaCaption)
                .foregroundStyle(.secondary)
            if showsLink {
                WakaExternalLink(
                    title: "Open wakatime.com",
                    url: URL(string: "https://wakatime.com"),
                    hint: "Opens WakaTime, the service that measures this data, in your browser"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A form row button with a hit target that actually meets the 44-point minimum.
///
/// `Button(...) { }.frame(minHeight: 44)` does not work: the frame wraps the button
/// rather than sizing it, and the accessibility tree reported 24-point targets for
/// every Settings action. Padding the *label* is what moves the control's own frame.
struct WakaFormButton: View {
    let title: String
    var role: ButtonRole?
    var hint: String?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 14, not 12: a 16-point line plus 24 points of padding measured 40 in
                // the live accessibility tree, four short of the 44-point target.
                .padding(.vertical, 14) // design-exempt: measured against the live accessibility tree
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
        .accessibilityHint(hint ?? "")
    }
}

/// An external link with a hit target that actually meets the 44-point minimum.
///
/// SwiftUI's `Link` lays out at its text height and ignores `.frame(minHeight:)`, so
/// every link in this app previously presented a 16-point target. The live
/// accessibility tree is what revealed it; `scripts/ax-audit.swift` now guards it.
struct WakaExternalLink: View {
    @Environment(\.openURL) private var openURL

    let title: String
    let url: URL?
    var hint: String?

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14) // design-exempt: measured against the live accessibility tree
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .disabled(url == nil)
        .accessibilityHint(hint ?? "Opens \(title) in your browser")
    }
}

/// Opens a bundled legal document, falling back to the public repository copy.
struct LegalLink: View {
    let title: String
    let file: String

    var body: some View {
        WakaExternalLink(title: title, url: url, hint: "Opens the \(title) document")
    }

    /// The published copy of the document.
    ///
    /// Documents are linked rather than bundled: a symlinked copy inside a
    /// code-signed bundle is fragile, and the repository is the authoritative
    /// version users should read.
    private var url: URL? {
        URL(string: "https://github.com/kevinle3212/WakaBoard/blob/main/\(file).md")
            ?? URL(string: "https://github.com/kevinle3212/WakaBoard")
    }
}
