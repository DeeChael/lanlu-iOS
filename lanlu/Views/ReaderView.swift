import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss

    let arcid: String
    let files: [APIClient.PageFile]
    let startIndex: Int
    let server: Server

    @State private var currentIndex: Int
    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var showControls = false

    init(arcid: String, files: [APIClient.PageFile], startIndex: Int, server: Server) {
        self.arcid = arcid
        self.files = files
        self.startIndex = startIndex
        self.server = server
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    ProgressView().tint(.white)
                } else if loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                        Text(String(localized: "reader_tap_reload"))
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await loadCurrentPage() } }
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }

                // Tap zones: left=prev, center=toggle controls, right=next
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { previousPage() }
                    Color.clear.contentShape(Rectangle()).onTapGesture { toggleControls() }
                    Color.clear.contentShape(Rectangle()).onTapGesture { nextPage() }
                }

                if showControls {
                    VStack {
                        topBar
                        Spacer()
                        bottomBar
                    }
                }
            }
            .statusBarHidden(!showControls)
        }
        .ignoresSafeArea()
        .task { await loadCurrentPage() }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()

            Button {

            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button { previousPage() } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            Text("\(currentIndex + 1) / \(files.count)")
                .font(.caption)
                .foregroundColor(.white)

            Button { nextPage() } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .padding(.bottom, 16)
    }

    private func loadCurrentPage() async {
        guard currentIndex >= 0, currentIndex < files.count else { return }
        loadError = false
        isLoading = true
        imageData = nil

        let file = files[currentIndex]
        let path = file.defaultSource?.path ?? file.path ?? ""
        let cacheKey = "page_\(arcid)_\(path)"

        if let cached = CacheManager.shared.getCover(id: cacheKey) {
            imageData = cached
            isLoading = false
            return
        }

        do {
            let data = try await server.apiClient.fetchPageImage(arcid: arcid, path: path)
            CacheManager.shared.cacheCover(id: cacheKey, data: data)
            imageData = data
        } catch {
            loadError = true
        }
        isLoading = false
    }

    private func previousPage() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        Task { await loadCurrentPage() }
    }

    private func nextPage() {
        guard currentIndex < files.count - 1 else { return }
        currentIndex += 1
        Task { await loadCurrentPage() }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
    }
}
