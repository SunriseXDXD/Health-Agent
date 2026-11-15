import SwiftUI
import SwiftData
import MessageUI

/// The weekly summary: built on the phone from Apple Health and the meal log,
/// then sent to the family as a PDF.
struct ReportView: View {
    @EnvironmentObject private var router: AppRouter
    @Query private var meals: [MealEntry]
    @Query private var waters: [WaterEntry]
    @AppStorage(Prefs.recipients) private var recipients = ""

    @State private var report: WeeklyReport?
    @State private var pdfURL: URL?
    @State private var jsonURL: URL?
    @State private var foodImageURL: URL?
    @State private var isBuilding = false
    @State private var showMail = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var status: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let report {
                        actions(report)
                        if let status {
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                        summaryCard(report)
                    } else if isBuilding {
                        ProgressView("Building last week's summary…").padding(.top, 80)
                    } else {
                        ContentUnavailableView("No report yet", systemImage: "doc.text",
                                               description: Text("Pull down to build the summary for the last full week."))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weekly summary")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await build() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isBuilding)
                }
            }
            .task { if report == nil || router.autoEmail { await build() } }
            .onChange(of: router.autoEmail) { _, requested in
                if requested { Task { await build() } }
            }
            .refreshable { await build() }
            .sheet(isPresented: $showMail) {
                if let report {
                    MailComposer(recipients: Prefs.recipientList, subject: report.emailSubject,
                                 messageBody: report.emailBody, attachments: [pdfURL, foodImageURL].compactMap { $0 }) { result in
                        if result == .sent { status = "Sent to \(Prefs.recipientList.joined(separator: ", "))." }
                    }
                    .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: shareItems)
            }
        }
    }

    /// The same content as the PDF, laid out for the phone screen.
    private func summaryCard(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.weekLabel).font(.headline)
            Text(report.takeaway).font(.subheadline)
            Divider()
            ForEach(report.headlineRows) { row in
                HStack {
                    Text(row.label)
                    Spacer()
                    Text(row.value).fontWeight(.semibold)
                    Text(row.change)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }
                .font(.subheadline)
            }
            Divider()
            detail("Nutrition", report.nutritionLine)
            detail("Water", report.waterLine)
            detail("Weight forecast", report.forecastLine)
            detail("Monthly goal", report.goalLine)
            Text("Observations").font(.headline)
            ForEach(Array(report.observations.enumerated()), id: \.offset) { _, line in
                Text("• " + line).font(.subheadline)
            }
            Text("Readings come from consumer devices and meal estimates. This is not a medical assessment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func detail(_ title: String, _ line: String?) -> some View {
        if let line {
            Text(title).font(.headline)
            Text(line).font(.subheadline)
        }
    }

    private func actions(_ report: WeeklyReport) -> some View {
        VStack(spacing: 10) {
            Button {
                openEmail(report)
            } label: {
                Label("Email report to family", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(pdfURL == nil)

            HStack(spacing: 10) {
                Button {
                    if let pdfURL {
                        shareItems = [pdfURL]
                        showShare = true
                    }
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .disabled(pdfURL == nil)
                Button {
                    if let jsonURL {
                        shareItems = [jsonURL]
                        showShare = true
                    }
                } label: {
                    Label("Export data", systemImage: "curlybraces").frame(maxWidth: .infinity)
                }
                .disabled(jsonURL == nil)
            }
            .buttonStyle(.bordered)

            Text("To: \(Prefs.recipientList.isEmpty ? "no recipients set" : Prefs.recipientList.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Opens a ready-to-send email with the PDF attached.
    private func openEmail(_ report: WeeklyReport) {
        if MailComposer.canSend {
            showMail = true
        } else {
            // Mail is not set up: hand the PDF and the text to the share sheet instead.
            var items: [Any] = [report.emailSubject + "\n\n" + report.emailBody]
            if let pdfURL { items.append(pdfURL) }
            if let foodImageURL { items.append(foodImageURL) }
            shareItems = items
            showShare = true
        }
    }

    @MainActor
    private func build() async {
        guard !isBuilding else { return }
        isBuilding = true
        defer { isBuilding = false }
        let snapshots = meals.map(\.snapshot)
        let waterSnapshots = waters.map(\.snapshot)
        let built = await WeeklyReportBuilder.build(meals: snapshots, water: waterSnapshots, useAI: true)
        let pdf = ReportPDF.render(built)
        let files = ReportFiles.save(built, pdf: pdf, foodImage: FoodImage.render(built))
        report = built
        pdfURL = files.pdf
        jsonURL = files.json
        foodImageURL = files.foodImage
        status = "Saved in Files › On My iPhone › Health Agent › Weekly summaries."
        // Opened from the Sunday notification: go straight to the email.
        if router.autoEmail {
            router.autoEmail = false
            if files.pdf != nil { openEmail(built) }
        }
    }
}
