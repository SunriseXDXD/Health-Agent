import SwiftUI
import UIKit
import MessageUI

/// Takes a photo with the camera.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// The system mail composer, filled in with recipients, text and attachments.
struct MailComposer: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let recipients: [String]
    let subject: String
    let messageBody: String
    let attachments: [URL]
    var onFinish: (MFMailComposeResult) -> Void = { _ in }

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(messageBody, isHTML: false)
        for url in attachments {
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime: String
            switch url.pathExtension.lowercased() {
            case "pdf": mime = "application/pdf"
            case "json": mime = "application/json"
            case "png": mime = "image/png"
            default: mime = "text/plain"
            }
            controller.addAttachmentData(data, mimeType: mime, fileName: url.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposer
        init(_ parent: MailComposer) { self.parent = parent }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.onFinish(result)
            parent.dismiss()
        }
    }
}

/// The system share sheet, used when Mail is not set up on the phone.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A small tile showing one number on the Today screen.
struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

extension Double {
    /// "1,234" style whole-number text.
    var wholeText: String {
        self.formatted(.number.precision(.fractionLength(0)))
    }

    func text(_ decimals: Int) -> String {
        self.formatted(.number.precision(.fractionLength(decimals)))
    }
}

extension Binding where Value == Int {
    /// Presents minutes-after-midnight as a Date for a time picker.
    var asTimeOfDay: Binding<Date> {
        Binding<Date>(
            get: {
                let start = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: wrappedValue, to: start) ?? start
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
