import AgentBarCore
import SwiftUI

struct StatisticsTableView: View {
    let report: StatisticsReport
    let byModel: Bool

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text(byModel ? "Model" : "Account").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["Input", "Output", "Cache read", "Cache write", "Total"], id: \.self) { title in
                    Text(title).frame(width: 76, alignment: .trailing)
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(report.rows.enumerated()), id: \.element.id) { index, row in
                GridRow {
                    HStack(spacing: 6) {
                        Circle().fill(StatisticsPalette.color(at: index)).frame(width: 6, height: 6)
                        if let provider = row.provider { ProviderMark(kind: provider).scaleEffect(0.8).frame(width: 12) }
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    tokenCells(row.tokens)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text("Total").frame(maxWidth: .infinity, alignment: .leading)
                tokenCells(report.total)
            }
            .fontWeight(.medium)
        }
        .font(.system(size: 11)).monospacedDigit()
    }

    @ViewBuilder
    private func tokenCells(_ count: TokenCount) -> some View {
        ForEach(Array([count.input, count.output, count.cacheRead, count.cacheWrite, count.total].enumerated()), id: \.offset) { _, value in
            Text(DisplayFormat.tokens(value)).frame(width: 76, alignment: .trailing)
                .help(value.formatted(.number.locale(DisplayFormat.locale)))
        }
    }
}
