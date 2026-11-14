import SwiftUI
import SwiftData
import MessageUI

/// The weekly summary: built on the phone from Apple Health and the meal log,
/// then sent to the family as a PDF.
struct ReportView: View {
    @Query private var meals: [MealEntry]
    @AppStorage(Prefs.recipients) private var recipients = ""

    @State private var report: WeeklyReport?
    @State private var pdfURL: URL?
    @State private var jsonURL: URL?
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
            .task { if report == nil { await build() } }
            .refreshable { await build() }
            .sheet(isPresented: $showMail) {
                if let report {
                    MailComposer(recipients: Prefs.recipientList, subject: report.emailSubject,
                                 messageBody: report.emailBody, attachments: [pdfURL].compactMap { $0 }) { result in
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

    private func actions(_ report: WeeklyReport) -> some View {
        VStack(spacing: 10) {
            Button {
                if MailComposer.canSend {
                    showMail = true
                } else {
                    // Mail is not set up: hand the PDF and the text to the share sheet instead.
                    var items: [Any] = [report.emailSubject + "\n\n" + report.emailBody]
                    if let pdfURL { items.append(pdfURL) }
                    shareItems = items
                    showShare = true
                }
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

    @MainActor
    private func build() async {
        guard !isBuilding else { return }
        isBuilding = true
        defer { isBuilding = false }
        let snapshots = meals.map(\.snapshot)
        let built = await WeeklyReportBuilder.build(meals: snapshots, useAI: true)
        let pdf = ReportPDF.render(built)
        let files = ReportFiles.save(built, pdf: pdf)
        report = built
        pdfURL = files.pdf
        jsonURL = files.json
        status = "Saved in Files › On My iPhone › Health Agent › Weekly summaries."
    }
}
