import SwiftUI
import SwiftData
import Charts

/// Zeigt, wie viel gerettet und wie viel weggeworfen wurde. Nur Zahlen und
/// ein Satz Einordnung, keine Bewertung.
struct StatsView: View {
    @Query(sort: \ConsumptionRecord.recordedAt, order: .reverse)
    private var records: [ConsumptionRecord]

    @State private var period: StatsPeriod = .days30

    private static let consumedLabel = "Verbraucht"
    private static let discardedLabel = "Weggeworfen"

    private var report: ConsumptionReport {
        ConsumptionStats.report(for: records, period: period)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodPicker
                if report.isEmpty {
                    emptyState
                } else {
                    headerCard
                    chartCard
                    reasonsCard
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Statistik")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Zeitraum

    private var periodPicker: some View {
        Picker("Zeitraum", selection: $period) {
            ForEach(StatsPeriod.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Kopf

    private var headerCard: some View {
        VStack(spacing: 6) {
            Text(rateText)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(Color.freshGreen)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("gerettet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(countsText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            comparisonText
            if let averageText {
                Text(averageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var rateText: String {
        guard let rate = report.current.rescueRate else { return "–" }
        return "\(Int(rate.rounded())) %"
    }

    private var countsText: String {
        "\(report.current.consumed) verbraucht, \(report.current.discarded) weggeworfen \(period.sentenceSuffix)"
    }

    @ViewBuilder
    private var comparisonText: some View {
        if let change = report.rateChange {
            let points = Int(change.rounded())
            if points == 0 {
                Text("Gleich wie davor")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                let word = abs(points) == 1 ? "Punkt" : "Punkte"
                Text("\(abs(points)) \(word) \(points > 0 ? "besser" : "schlechter") als davor")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(points > 0 ? Color.freshGreen : .orange)
            }
        } else if period == .all {
            EmptyView()
        } else {
            Text("Kein Vergleich zum Zeitraum davor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var averageText: String? {
        guard let days = report.averageDaysBeforeExpiry else { return nil }
        let rounded = Int(days.rounded())
        if rounded > 0 {
            return "Im Schnitt \(rounded) \(rounded == 1 ? "Tag" : "Tage") vor Ablauf verbraucht"
        }
        if rounded == 0 {
            return "Im Schnitt am Tag des Ablaufs verbraucht"
        }
        let late = abs(rounded)
        return "Im Schnitt \(late) \(late == 1 ? "Tag" : "Tage") nach Ablauf verbraucht"
    }

    // MARK: - Diagramm

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Je Woche")
                .font(.headline)
            Chart {
                ForEach(report.weeks) { week in
                    BarMark(
                        x: .value("Woche", week.weekStart, unit: .weekOfYear),
                        y: .value("Anzahl", week.consumed)
                    )
                    .foregroundStyle(by: .value("Ausgang", Self.consumedLabel))
                    BarMark(
                        x: .value("Woche", week.weekStart, unit: .weekOfYear),
                        y: .value("Anzahl", week.discarded)
                    )
                    .foregroundStyle(by: .value("Ausgang", Self.discardedLabel))
                }
            }
            .chartForegroundStyleScale([
                Self.consumedLabel: Color.freshGreen,
                Self.discardedLabel: Color.orange
            ])
            .chartLegend(position: .bottom, spacing: 8)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: axisStride)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day(.twoDigits).month(.twoDigits))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Jede Woche beschriften wird bei langen Zeiträumen zu eng.
    private var axisStride: Int {
        switch report.weeks.count {
        case ...6:  return 1
        case ...14: return 2
        default:    return 4
        }
    }

    // MARK: - Woran es liegt

    private var reasonsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Woran es liegt")
                .font(.headline)

            if report.topLosses.isEmpty {
                Text("Nichts weggeworfen \(period.sentenceSuffix).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(report.topLosses.enumerated()), id: \.element.id) { index, loss in
                        if index > 0 { Divider() }
                        lossRow(
                            icon: "trash",
                            color: .orange,
                            title: loss.name,
                            count: loss.count
                        )
                    }
                    if let location = report.worstLocation {
                        Divider()
                        lossRow(
                            icon: "archivebox",
                            color: .secondary,
                            title: location.name,
                            count: location.count
                        )
                    }
                }
                if let location = report.worstLocation {
                    Text("\(location.name) ist der Ort mit den meisten Verlusten.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func lossRow(icon: String, color: Color, title: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(count)×")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Leer

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Noch keine Daten")
                .font(.title3.weight(.semibold))
            Text("Sobald du Produkte als verbraucht markierst, siehst du hier, wie viel du rettest.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}
