import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) fileprivate var dismiss

    let arcid: String
    let files: [APIClient.PageFile]
    let startIndex: Int
    let server: Server

    @State fileprivate var currentIndex: Int
    @State fileprivate var showControls = false
    @State fileprivate var images: [Int: UIImage] = [:]
    @State fileprivate var failedPages: Set<Int> = []
    @State fileprivate var isLoading: Set<Int> = []
    @State fileprivate var dragOffset: CGFloat = 0
    @State fileprivate var isDragging = false
    @State fileprivate var loadTasks: [Int: Task<Void, Never>] = [:]

    var maxIndex: Int { max(0, files.count - 1) }

    init(arcid: String, files: [APIClient.PageFile], startIndex: Int, server: Server) {
        self.arcid = arcid
        self.files = files
        self.startIndex = startIndex
        self.server = server
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        GeometryReader { geo in
            let pageW = geo.size.width
            let pageH = geo.size.height

            ZStack {
                HStack(spacing: 0) {
                    if currentIndex > 0 {
                        pageView(for: currentIndex - 1, size: geo.size)
                            .frame(width: pageW, height: pageH)
                    } else {
                        Color.black.frame(width: pageW, height: pageH)
                    }

                    pageView(for: currentIndex, size: geo.size)
                        .frame(width: pageW, height: pageH)

                    if currentIndex < maxIndex {
                        pageView(for: currentIndex + 1, size: geo.size)
                            .frame(width: pageW, height: pageH)
                    } else {
                        Color.black.frame(width: pageW, height: pageH)
                    }
                }
                .offset(x: -pageW + dragOffset)

                // Tap zones
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let x = location.x
                        if !isDragging {
                            if x < pageW * 0.3 {
                                previousPage()
                            } else if x > pageW * 0.7 {
                                nextPage()
                            } else {
                                withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                            }
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                isDragging = true
                                dragOffset = v.translation.width
                            }
                            .onEnded { v in
                                let threshold = pageW * 0.25
                                let velocity = v.predictedEndLocation.x - v.location.x

                                if v.translation.width > threshold || velocity > 100 {
                                    withAnimation(.easeOut(duration: 0.25)) { dragOffset = pageW }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        if currentIndex > 0 { currentIndex -= 1 }
                                        dragOffset = 0; isDragging = false
                                    }
                                } else if v.translation.width < -threshold || velocity < -100 {
                                    withAnimation(.easeOut(duration: 0.25)) { dragOffset = -pageW }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        if currentIndex < maxIndex { currentIndex += 1 }
                                        dragOffset = 0; isDragging = false
                                    }
                                } else {
                                    withAnimation(.easeOut(duration: 0.25)) { dragOffset = 0 }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { isDragging = false }
                                }
                            }
                    )
            }
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbar(showControls ? .visible : .hidden, for: .bottomBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .principal) {
                Text("\(currentIndex + 1) / \(files.count)")
                    .font(.subheadline)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {} label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { previousPage() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(currentIndex <= 0).opacity(currentIndex <= 0 ? 0.5 : 1)

                Slider(
                    value: Binding(get: { Double(currentIndex) }, set: { currentIndex = Int($0) }),
                    in: 0...Double(maxIndex), step: 1
                ).tint(.white)

                Button { nextPage() } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(currentIndex >= maxIndex).opacity(currentIndex >= maxIndex ? 0.5 : 1)
            }
        }
        .statusBarHidden(!showControls)
        .onAppear { loadPage(currentIndex) }
        .onDisappear { cancelAllTasks() }
        .onChange(of: currentIndex) { _, _ in
            loadPage(currentIndex)
            preloadAdjacent()
        }
    }

    @ViewBuilder
    fileprivate func pageView(for index: Int, size: CGSize) -> some View {
        if let image = images[index] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading.contains(index) {
            VStack(spacing: 12) {
                ProgressView().tint(.white).scaleEffect(1.5)
                Text("\(index + 1) / \(files.count)")
                    .font(.caption).foregroundColor(.white.opacity(0.6))
            }
        } else if failedPages.contains(index) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                Text(String(localized: "reader_tap_reload")).font(.subheadline).foregroundColor(.white)
            }
            .onTapGesture { failedPages.remove(index); loadPage(index) }
        } else {
            Image(systemName: "photo").font(.largeTitle).foregroundColor(.white.opacity(0.3))
        }
    }
}

extension ReaderView {
    fileprivate func previousPage() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.15)) { currentIndex -= 1 }
    }

    fileprivate func nextPage() {
        guard currentIndex < maxIndex else { return }
        withAnimation(.easeInOut(duration: 0.15)) { currentIndex += 1 }
    }

    fileprivate func loadPage(_ index: Int) {
        guard index >= 0, index < files.count, images[index] == nil, !failedPages.contains(index) else { return }
        let file = files[index]
        let path = file.defaultSource?.path ?? file.path ?? ""
        guard !path.isEmpty else { return }

        loadTasks[index]?.cancel()
        isLoading.insert(index)

        loadTasks[index] = Task {
            let cacheKey = "page_\(arcid)_\(path)"
            if let cached = CacheManager.shared.getCover(id: cacheKey), let img = UIImage(data: cached) {
                await MainActor.run { images[index] = img; isLoading.remove(index); failedPages.remove(index) }
                return
            }
            do {
                let data = try await server.apiClient.fetchPageImage(arcid: arcid, path: path)
                guard !Task.isCancelled else { return }
                CacheManager.shared.cacheCover(id: cacheKey, data: data)
                if let img = UIImage(data: data) {
                    await MainActor.run { images[index] = img; isLoading.remove(index); failedPages.remove(index) }
                } else {
                    await MainActor.run { isLoading.remove(index); failedPages.insert(index) }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { isLoading.remove(index); failedPages.insert(index) }
            }
        }
    }

    fileprivate func preloadAdjacent() {
        let nextIndex = currentIndex + 1
        if nextIndex < files.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { loadPage(nextIndex) }
        }
    }

    fileprivate func cancelAllTasks() {
        for task in loadTasks.values { task.cancel() }
        loadTasks.removeAll()
    }
}
