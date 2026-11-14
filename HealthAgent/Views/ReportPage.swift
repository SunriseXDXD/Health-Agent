import SwiftUI
import Charts

/// The report laid out as a page. Shown on screen and also rendered into the PDF.
struct ReportPage: View {
    let report: WeeklyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Text(report.takeaway)
                .font(.system(size: 12))
            headlineTable
            if !report.current.dailySteps.isEmpty { stepsChart }
            if !report.current.dailyRestingHR.isEmpty { heartChart }
            if report.current.sleepHours != nil { sleepSection }
            if !report.current.dailyKcal.isEmpty { foodChart }
            observations
            Text("Readings come from an iPhone, an Apple Watch and photo-based meal estimates. This is not a medical assessment.")
                .font(.system(size: 9))
                .foregroundStyle(.gray)
        }
        .padding(32)
        .frame(width: 595, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weekly health summary")
                .font(.system(size: 22, weight: .bold))
            Text("\(report.name) · \(report.weekLabel)")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
    }

    private var headlineTable: some View {
        VStack(spacing: 0) {
            tableRow("Measure", "This week", "Change", bold: true)
            Divider()
            ForEach(report.headlineRows) { row in
                tableRow(row.label, row.value, row.change, bold: false)
                Divider()
            }
        }
    }

    private func tableRow(_ a: String, _ b: String, _ c: String, bold: Bool) -> some View {
        HStack {
            Text(a).frame(maxWidth: .infinity, alignment: .leading)
            Text(b).frame(width: 120, alignment: .trailing)
            Text(c).frame(width: 120, alignment: .trailing)
        }
        .font(.system(size: 11, weight: bold ? .semibold : .regular))
        .padding(.vertical, 5)
    }

    private var stepsChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Daily steps")
            Chart(report.current.dailySteps) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.value))
                    .foregroundStyle(Color(red: 0.11, green: 0.62, blue: 0.48))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .frame(height: 120)
        }
    }

    private var heartChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Resting heart rate (bpm)")
            Chart(report.current.dailyRestingHR) { day in
                LineMark(x: .value("Day", day.date, unit: .day), y: .value("bpm", day.value))
                    .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.3))
                PointMark(x: .value("Day", day.date, unit: .day), y: .value("bpm", day.value))
                    .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.3))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .frame(height: 110)
        }
    }

    private var sleepSection: some View {
        let c = report.current
        var parts: [String] = []
        if let hours = c.sleepHours { parts.append(String(format: "%.1f h asleep on average over %d night%@", hours, c.sleepNights, c.sleepNights == 1 ? "" : "s")) }
        if let deep = c.deepHours, let core = c.coreHours, let rem = c.remHours {
            parts.append(String(format: "deep %.1f h, core %.1f h, REM %.1f h", deep, core, rem))
        }
        if let bed = c.bedtime, let wake = c.wakeTime { parts.append("typically \(bed) to \(wake)") }
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Sleep")
            Text(parts.joined(separator: "; ") + ".")
                .font(.system(size: 11))
        }
    }

    private var foodChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Food logged (kcal per day)")
            Chart(report.current.dailyKcal) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.value))
                    .foregroundStyle(Color(red: 0.95, green: 0.6, blue: 0.2))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .frame(height: 110)
            if let trend = report.weightTrendKgPerWeek, let future = report.weightInFourWeeksKg {
                Text(String(format: "Weight trend: %+.2f kg a week; about %.1f kg in four weeks if it continues.", trend, future))
                    .font(.system(size: 11))
            }
        }
    }

    private var observations: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Observations")
            ForEach(Array(report.observations.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(line)
                }
                .font(.system(size: 11))
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold))
    }
}

enum ReportPDF {
    /// Draws the report page into a single-page vector PDF.
    @MainActor
    static func render(_ report: WeeklyReport) -> Data? {
        let renderer = ImageRenderer(content: ReportPage(report: report))
        let data = NSMutableData()
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data.length > 0 ? data as Data : nil
    }
}
