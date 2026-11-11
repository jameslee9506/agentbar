import AgentBarCore
import Charts
import SwiftUI

struct StatisticsView: View {
    let store: AccountStore
    @State var selectedAccount: AccountID?
    @State var days = 7

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let report = StatisticsReport(accounts: store.accounts, selectedAccount: selectedAccount, days: days, now: context.date)
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    Picker("Account", selection: $selectedAccount) {
                        Text("All accounts").tag(nil as AccountID?)
                        ForEach(store.accounts) { state in
                            Text("\(state.account.name) · \(state.id.provider.displayName)")
                                .tag(Optional(state.id))
                        }
                    }
                    .labelsHidden().frame(width: 250)
                    Spacer()
                    Picker("Range", selection: $days) {
                        ForEach([7, 30, 90], id: \.self) { Text("\($0) days").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 220)
                }
                chart(report)
                    .frame(minHeight: 190, idealHeight: 220, maxHeight: .infinity)
                ScrollView {
                    StatisticsTableView(report: report, byModel: selectedAccount != nil)
                }
                .frame(height: min(200, CGFloat(report.rows.count + 2) * 30))
            }
            .padding(24)
        }
        .frame(
            minWidth: StatisticsLayout.minimumSize.width, idealWidth: StatisticsLayout.preferredSize.width,
            minHeight: StatisticsLayout.minimumSize.height, idealHeight: StatisticsLayout.preferredSize.height
        )
        .background(.background)
        .onChange(of: store.accounts.map(\.id)) { _, ids in
            if let selectedAccount, !ids.contains(selectedAccount) { self.selectedAccount = nil }
        }
    }

    private func chart(_ report: StatisticsReport) -> some View {
        Chart(report.segments) { segment in
            BarMark(
                x: .value("Day", segment.day, unit: .day),
                y: .value("Tokens", segment.tokens),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Series", segment.series))
            .accessibilityLabel("\(segment.day.formatted(.dateTime.month(.abbreviated).day().locale(DisplayFormat.locale))), \(report.rows.first { $0.id == segment.series }?.name ?? segment.series)")
            .accessibilityValue("\(segment.tokens) tokens")
        }
        .chartForegroundStyleScale(
            domain: report.rows.map(\.id),
            range: report.rows.indices.map { StatisticsPalette.color(at: $0) }
        )
        .chartLegend(.hidden)
        .chartXScale(domain: report.start...report.end)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: days == 7 ? 7 : 6)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(DisplayFormat.locale), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let count = value.as(Int.self) { Text(DisplayFormat.tokens(count)).monospacedDigit() }
                }
            }
        }
        .overlay {
            if report.segments.isEmpty {
                Text("No token history").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
