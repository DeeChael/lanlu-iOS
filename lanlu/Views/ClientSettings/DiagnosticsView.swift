import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logFileURL: URL?
    @State private var logContent = ""

    var body: some View {
        NavigationStack {
            SelectableLogTextView(
                text: logContent.isEmpty
                    ? String(localized: "diag_empty")
                    : logContent
            )
            .navigationTitle(String(localized: "diag_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !logContent.isEmpty, let url = logFileURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            refreshLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .diagnosticsLogDidChange)) { _ in
            refreshLogs()
        }
    }

    private func refreshLogs() {
        logContent = LogManager.shared.logText
        guard !logContent.isEmpty else {
            logFileURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lanlu-diag.log")
        try? logContent.write(to: url, atomically: true, encoding: .utf8)
        logFileURL = url
    }
}

private struct SelectableLogTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textColor = .secondaryLabel
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text else { return }

        let selectedRange = textView.selectedRange
        let contentOffset = textView.contentOffset
        textView.text = text

        if selectedRange.location != NSNotFound,
           NSMaxRange(selectedRange) <= (text as NSString).length {
            textView.selectedRange = selectedRange
        }
        textView.setContentOffset(contentOffset, animated: false)
    }
}
