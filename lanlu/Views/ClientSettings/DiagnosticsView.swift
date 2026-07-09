import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logFileURL: URL?

    private var logContent: String { LogManager.shared.logText }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(logContent.isEmpty
                     ? String(localized: "diag_empty")
                     : logContent)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
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
        .task {
            prepareLogFile()
        }
    }

    private func prepareLogFile() {
        guard !logContent.isEmpty else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lanlu-diag.log")
        try? logContent.write(to: url, atomically: true, encoding: .utf8)
        logFileURL = url
    }
}
