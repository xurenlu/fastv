//
//  MonitorChartView.swift
//  fastv
//
//  内存监控图表视图
//

import SwiftUI
import Combine

/// 图表时间范围
enum ChartTimeRange: String, CaseIterable, Identifiable {
    case hour = "1小时"
    case day = "24小时"
    case week = "7天"
    case month = "30天"

    var id: String { rawValue }
}

/// 内存监控图表视图
struct MonitorChartView: View {
    @StateObject private var monitor = MemoryMonitor.shared
    @State private var selectedRange: ChartTimeRange = .hour

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summarySection
            Divider()
            chartSection
            Divider()
            actionButtons
        }
        .frame(minHeight: 400)
        .onAppear {
            updateChart()
        }
        .onChange(of: selectedRange) { _, _ in
            updateChart()
        }
    }

    private var header: some View {
        HStack {
            Text("内存使用监控")
                .font(.headline)
            Spacer()
            Picker("", selection: $selectedRange) {
                ForEach(ChartTimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
        .padding()
    }

    private var summarySection: some View {
        SummaryView(monitor: monitor)
            .padding(.horizontal)
            .padding(.vertical, 12)
    }

    private var chartSection: some View {
        Group {
            if chartData.isEmpty {
                emptyStateView
            } else {
                MemoryLineChart(data: chartData, range: selectedRange)
                    .frame(height: 250)
                    .padding()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("暂无数据")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("立即记录") {
                monitor.recordNow()
                updateChart()
            }
            .keyboardShortcut(.defaultAction)

            Spacer()

            Button("清除历史") {
                monitor.clearAllRecords()
                updateChart()
            }
            .foregroundColor(.red)
        }
        .padding()
    }

    @State private var chartData: [MemoryRecord] = []

    private func updateChart() {
        let now = Date()
        let startDate: Date

        switch selectedRange {
        case .hour:
            startDate = now.addingTimeInterval(-60 * 60)
        case .day:
            startDate = now.addingTimeInterval(-24 * 60 * 60)
        case .week:
            startDate = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month:
            startDate = now.addingTimeInterval(-30 * 24 * 60 * 60)
        }

        chartData = monitor.getRecords(from: startDate, to: now)
    }
}

// MARK: - Summary View

struct SummaryView: View {
    @ObservedObject var monitor: MemoryMonitor

    var body: some View {
        let summary = monitor.getMemorySummary()

        return HStack(spacing: 30) {
            currentValueView(summary: summary)
            trendView(summary: summary)
            hourAvgView(summary: summary)
            hourMaxView(summary: summary)

            Spacer()

            recordCountView(summary: summary)
        }
    }

    private func currentValueView(summary: MemorySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前内存")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(summary.currentFormatted)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(colorForMemory(summary.currentMB))
        }
    }

    private func trendView(summary: MemorySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("趋势")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(summary.trendDescription)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(trendColor(summary.trend))
        }
    }

    private func hourAvgView(summary: MemorySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("1小时平均")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(summary.hourAvgFormatted)
                .font(.system(size: 16, weight: .medium))
        }
    }

    private func hourMaxView(summary: MemorySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("1小时峰值")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(summary.hourMaxFormatted)
                .font(.system(size: 16, weight: .medium))
        }
    }

    private func recordCountView(summary: MemorySummary) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("记录数")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(summary.recordCount)")
                .font(.system(size: 16, weight: .medium))
        }
    }

    private func colorForMemory(_ memoryMB: Double) -> Color {
        switch memoryMB {
        case 0..<2048: return .green
        case 2048..<4096: return .orange
        case 4096..<6144: return .red
        default: return .purple
        }
    }

    private func trendColor(_ trend: MemoryTrend) -> Color {
        switch trend {
        case .stable: return .secondary
        case .rising: return .red
        case .falling: return .green
        }
    }
}

// MARK: - Memory Line Chart

struct MemoryLineChart: View {
    let data: [MemoryRecord]
    let range: ChartTimeRange

    var body: some View {
        GeometryReader { geometry in
            if data.isEmpty {
                EmptyView()
            } else {
                ZStack {
                    GridLines(width: geometry.size.width, height: geometry.size.height)
                    LinePath(data: data, width: geometry.size.width, height: geometry.size.height)
                    FillPath(data: data, width: geometry.size.width, height: geometry.size.height)
                    DataPoints(data: data, width: geometry.size.width, height: geometry.size.height)
                    YAxisLabels(minMemory: minMemory, maxMemory: maxMemory, height: geometry.size.height)
                    XAxisLabels(data: data, width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }

    private var minMemory: Double {
        data.map { $0.memoryMB }.min() ?? 0
    }

    private var maxMemory: Double {
        max(data.map { $0.memoryMB }.max() ?? 100, minMemory + 100)
    }
}

// MARK: - Chart Components

struct GridLines: View {
    let width: CGFloat
    let height: CGFloat

    private let padding: CGFloat = 20

    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                let y = height - padding - CGFloat(i) * (height - 2 * padding) / 4
                Path { path in
                    path.move(to: CGPoint(x: padding, y: y))
                    path.addLine(to: CGPoint(x: width - padding, y: y))
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
    }
}

struct LinePath: View {
    let data: [MemoryRecord]
    let width: CGFloat
    let height: CGFloat

    private let padding: CGFloat = 20

    var body: some View {
        if data.count >= 2 {
            Path { path in
                let firstPoint = pointForRecord(data[0])
                path.move(to: firstPoint)

                for record in data.dropFirst() {
                    let point = pointForRecord(record)
                    path.addLine(to: point)
                }
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private var minMemory: Double {
        data.map { $0.memoryMB }.min() ?? 0
    }

    private var maxMemory: Double {
        max(data.map { $0.memoryMB }.max() ?? 100, minMemory + 100)
    }

    private var lineColor: Color {
        let avg = data.reduce(0) { $0 + $1.memoryMB } / Double(data.count)
        switch avg {
        case 0..<2048: return .green
        case 2048..<4096: return .orange
        default: return .red
        }
    }

    private func pointForRecord(_ record: MemoryRecord) -> CGPoint {
        guard let firstTime = data.first?.timestamp,
              let lastTime = data.last?.timestamp,
              lastTime != firstTime else {
            return CGPoint(x: padding, y: height - padding)
        }

        let timeRange = lastTime.timeIntervalSince(firstTime)
        let offset = record.timestamp.timeIntervalSince(firstTime)
        let x = padding + CGFloat(offset / timeRange) * (width - 2 * padding)

        let memoryRange = maxMemory - minMemory
        let normalized = (record.memoryMB - minMemory) / max(memoryRange, 1)
        let y = height - padding - CGFloat(normalized) * (height - 2 * padding)

        return CGPoint(x: x, y: y)
    }
}

struct FillPath: View {
    let data: [MemoryRecord]
    let width: CGFloat
    let height: CGFloat

    private let padding: CGFloat = 20

    var body: some View {
        if data.count >= 2 {
            Path { path in
                let firstPoint = pointForRecord(data[0])
                path.move(to: CGPoint(x: firstPoint.x, y: height - padding))

                for record in data {
                    let point = pointForRecord(record)
                    path.addLine(to: point)
                }

                if let lastRecord = data.last {
                    let lastPoint = pointForRecord(lastRecord)
                    path.addLine(to: CGPoint(x: lastPoint.x, y: height - padding))
                }

                path.closeSubpath()
            }
            .fill(lineColor.opacity(0.1))
        }
    }

    private var minMemory: Double {
        data.map { $0.memoryMB }.min() ?? 0
    }

    private var maxMemory: Double {
        max(data.map { $0.memoryMB }.max() ?? 100, minMemory + 100)
    }

    private var lineColor: Color {
        let avg = data.reduce(0) { $0 + $1.memoryMB } / Double(data.count)
        switch avg {
        case 0..<2048: return .green
        case 2048..<4096: return .orange
        default: return .red
        }
    }

    private func pointForRecord(_ record: MemoryRecord) -> CGPoint {
        guard let firstTime = data.first?.timestamp,
              let lastTime = data.last?.timestamp,
              lastTime != firstTime else {
            return CGPoint(x: padding, y: height - padding)
        }

        let timeRange = lastTime.timeIntervalSince(firstTime)
        let offset = record.timestamp.timeIntervalSince(firstTime)
        let x = padding + CGFloat(offset / timeRange) * (width - 2 * padding)

        let memoryRange = maxMemory - minMemory
        let normalized = (record.memoryMB - minMemory) / max(memoryRange, 1)
        let y = height - padding - CGFloat(normalized) * (height - 2 * padding)

        return CGPoint(x: x, y: y)
    }
}

struct DataPoints: View {
    let data: [MemoryRecord]
    let width: CGFloat
    let height: CGFloat

    private let padding: CGFloat = 20

    var body: some View {
        ForEach(Array(data.enumerated()), id: \.element.id) { _, record in
            let point = pointForRecord(record)
            Circle()
                .fill(colorForMemory(record.memoryMB))
                .frame(width: 6, height: 6)
                .position(point)
        }
    }

    private var minMemory: Double {
        data.map { $0.memoryMB }.min() ?? 0
    }

    private var maxMemory: Double {
        max(data.map { $0.memoryMB }.max() ?? 100, minMemory + 100)
    }

    private func pointForRecord(_ record: MemoryRecord) -> CGPoint {
        guard let firstTime = data.first?.timestamp,
              let lastTime = data.last?.timestamp,
              lastTime != firstTime else {
            return CGPoint(x: padding, y: height - padding)
        }

        let timeRange = lastTime.timeIntervalSince(firstTime)
        let offset = record.timestamp.timeIntervalSince(firstTime)
        let x = padding + CGFloat(offset / timeRange) * (width - 2 * padding)

        let memoryRange = maxMemory - minMemory
        let normalized = (record.memoryMB - minMemory) / max(memoryRange, 1)
        let y = height - padding - CGFloat(normalized) * (height - 2 * padding)

        return CGPoint(x: x, y: y)
    }

    private func colorForMemory(_ memoryMB: Double) -> Color {
        switch memoryMB {
        case 0..<2048: return .green
        case 2048..<4096: return .orange
        case 4096..<6144: return .red
        default: return .purple
        }
    }
}

struct YAxisLabels: View {
    let minMemory: Double
    let maxMemory: Double
    let height: CGFloat

    private let padding: CGFloat = 20

    var body: some View {
        ForEach(0..<5, id: \.self) { i in
            let y = height - padding - CGFloat(i) * (height - 2 * padding) / 4
            let value = minMemory + CGFloat(i) * (maxMemory - minMemory) / 4

            Text("\(Int(value))")
                .font(.caption2)
                .foregroundColor(.secondary)
                .position(x: padding - 10, y: y)
        }
    }
}

struct XAxisLabels: View {
    let data: [MemoryRecord]
    let width: CGFloat
    let height: CGFloat

    private let padding: CGFloat = 20

    var body: some View {
        ForEach(Array(timeLabels.enumerated()), id: \.offset) { _, label in
            Text(label.text)
                .font(.caption2)
                .foregroundColor(.secondary)
                .position(x: label.x, y: height - padding + 15)
        }
    }

    private var timeLabels: [(text: String, x: CGFloat)] {
        let count = min(5, data.count)
        let step = max(1, data.count / count)

        return stride(from: 0, to: data.count, by: step).prefix(count).compactMap { index -> (text: String, x: CGFloat)? in
            guard index < data.count else { return nil }
            let record = data[index]
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return (formatter.string(from: record.timestamp), xPositionForRecord(record))
        }
    }

    private func xPositionForRecord(_ record: MemoryRecord) -> CGFloat {
        guard let firstTime = data.first?.timestamp,
              let lastTime = data.last?.timestamp,
              lastTime != firstTime else {
            return padding
        }

        let timeRange = lastTime.timeIntervalSince(firstTime)
        let offset = record.timestamp.timeIntervalSince(firstTime)
        return padding + CGFloat(offset / timeRange) * (width - 2 * padding)
    }
}

// MARK: - Preview

struct MonitorChartView_Previews: PreviewProvider {
    static var previews: some View {
        MonitorChartView()
            .frame(width: 600, height: 500)
    }
}
