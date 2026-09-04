import SwiftUI
import WakaCore

/// What is actually inside one of WakaTime's unresolved language buckets.
///
/// Opened from the "Other" row. It answers the question that row raises and cannot
/// answer on its own — four hours of *what?* — and it is explicit that the figures
/// are WakaBoard's reconstruction rather than WakaTime's own, because they are.
struct FileTypeBreakdownView: View {
    @Environment(\.dismiss) private var dismiss

    let model: WakaUIModel
    /// The bucket being opened, carrying WakaTime's own total for it.
    let bucket: Usage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WakaDesign.Spacing.loose) {
                    header
                    content
                }
                .padding(WakaDesign.Spacing.regular)
            }
            .navigationTitle("Inside \(bucket.name)")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .frame(minHeight: WakaAccessibility.minimumTargetSize)
                }
            }
        }
        .task { await model.loadBreakdown(for: bucket) }
        .onDisappear { model.clearBreakdown() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.hairline) {
            Text(DurationFormatter().string(bucket.duration)).font(.wakaHeroNumeral)
            Text("WakaTime counted this much time as \"\(bucket.name)\" because it could not "
                 + "identify the file types involved.")
                .font(.wakaCaption)
                .foregroundStyle(.secondary)
        }
        .wakaHeroSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bucket.name), \(DurationFormatter().string(bucket.duration)) that WakaTime could not classify.")
    }

    @ViewBuilder private var content: some View {
        switch model.breakdown {
        case .loading, nil:
            ProgressView("Reading your coding activity…")
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityLabel("Loading the file types inside \(bucket.name).")
        case .failed(let message):
            WakaStateView(
                title: "No Breakdown Available",
                message: message,
                actionLabel: "Try Again",
                action: { Task { await model.loadBreakdown(for: bucket) } }
            )
        case .loaded(let result):
            ComparisonChart(title: "File Types", usage: Array(result.rows.prefix(8)))
            rows(result)
            caveat(result)
        }
    }

    private func rows(_ result: BreakdownResult) -> some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.snug) {
            Text("All File Types").font(.wakaSectionTitle)
            ForEach(Array(result.rows.enumerated()), id: \.element.id) { index, item in
                UsageRow(item: item, total: result.total, icon: "doc.text", rank: index)
                    .font(.wakaCode)
            }
        }
        .wakaCard()
    }

    /// The honesty note. Never optional, never smaller than the figures it qualifies.
    private func caveat(_ result: BreakdownResult) -> some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.tight) {
            Label("How This Is Calculated", systemImage: "info.circle").font(.wakaCardTitle)
            Text("WakaTime's API cannot report a file and its language together, so WakaBoard "
                 + "rebuilds these figures from your individual coding events, joining events "
                 + "less than 15 minutes apart. That is WakaTime's own default rule, but your "
                 + "account's settings are not published, so these totals are close to — and not "
                 + "identical to — WakaTime's own.")
                .font(.wakaCaption)
                .foregroundStyle(.secondary)
            if result.isPartial {
                Text("This covers the most recent \(result.daysCovered) days of the "
                     + "\(result.daysInPeriod) in the selected period. WakaBoard limits how many "
                     + "days one breakdown fetches so it stays well inside WakaTime's rate limit.")
                    .font(.wakaCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .wakaCard()
    }
}
