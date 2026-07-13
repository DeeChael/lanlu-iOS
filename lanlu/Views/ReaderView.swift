import SwiftUI
import UniformTypeIdentifiers

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
    @State fileprivate var verticalDrag: CGFloat = 0
    @State fileprivate var isDragging = false
    @State fileprivate var isPageAnimating = false
    @State fileprivate var pageWidth: CGFloat = 0
    @State fileprivate var isZoomed = false
    @State fileprivate var currentScale: CGFloat = 1.0
    @State fileprivate var lastScale: CGFloat = 1.0
    @State fileprivate var panOffset: CGSize = .zero
    @State fileprivate var lastPanOffset: CGSize = .zero
    @State fileprivate var loadTasks: [Int: Task<Void, Never>] = [:]

    var maxIndex: Int { max(0, files.count - 1) }

    fileprivate var currentFileIsImage: Bool {
        isImageFile(filePath(at: currentIndex))
    }

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

                Color.clear
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                guard currentFileIsImage else { return }
                                if currentScale > 1.001 { resetZoom() }
                                else {
                                    withAnimation(.smooth(duration: 0.25)) {
                                        currentScale = 3.0; lastScale = 3.0
                                        panOffset = .zero; lastPanOffset = .zero; isZoomed = true
                                    }
                                }
                            }
                    )
                    .onTapGesture { location in
                        let x = location.x
                        if x < pageW * 0.3 { previousPage() }
                        else if x > pageW * 0.7 { nextPage() }
                        else { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                guard !isPageAnimating else { return }
                                if currentFileIsImage, currentScale > 1.001 {
                                    let proposed = CGSize(
                                        width: lastPanOffset.width + v.translation.width,
                                        height: lastPanOffset.height + v.translation.height
                                    )
                                    withoutAnimation { panOffset = clampedPanOffset(proposed, scale: currentScale) }
                                } else {
                                    isDragging = true
                                    let t = v.translation.width
                                    let damping = (currentIndex == 0 && t > 0) || (currentIndex == maxIndex && t < 0)
                                    withoutAnimation { dragOffset = damping ? t * 0.2 : t }
                                }
                            }
                            .onEnded { v in
                                guard !isPageAnimating else { return }
                                if currentFileIsImage, currentScale > 1.001 {
                                    let proposed = CGSize(
                                        width: lastPanOffset.width + v.translation.width,
                                        height: lastPanOffset.height + v.translation.height
                                    )
                                    let corrected = clampedPanOffset(proposed, scale: currentScale)
                                    panOffset = corrected; lastPanOffset = corrected
                                } else {
                                    finishPageDrag(v, pageWidth: pageW)
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard currentFileIsImage else { return }
                                let newScale = min(max(lastScale * value, 1.0), 3.0)
                                withoutAnimation {
                                    currentScale = newScale
                                    isZoomed = newScale > 1.001
                                    if newScale <= 1.001 { panOffset = .zero; lastPanOffset = .zero }
                                }
                            }
                            .onEnded { value in
                                guard currentFileIsImage else { return }
                                let finalScale = min(max(lastScale * value, 1.0), 3.0)
                                if finalScale <= 1.001 { resetZoom() }
                                else {
                                    currentScale = finalScale; lastScale = finalScale; isZoomed = true
                                    let corrected = clampedPanOffset(panOffset, scale: finalScale)
                                    withAnimation(.snappy(duration: 0.18)) { panOffset = corrected }
                                    lastPanOffset = corrected
                                }
                            }
                    )
            }
            .onAppear { pageWidth = pageW }
            .onChange(of: pageW) { _, nv in pageWidth = nv }
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbar(showControls ? .visible : .hidden, for: .bottomBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("\(currentIndex + 1) / \(files.count)").font(.subheadline)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {} label: { Image(systemName: "gearshape.fill") }
            }
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbar {
            if (files.count > 1) {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { previousPage() } label: {
                        Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44)
                    }
                    .disabled(currentIndex <= 0).opacity(currentIndex <= 0 ? 0.5 : 1)

                    Slider(
                        value: .init(
                            get: { Double(currentIndex) },
                            set: { currentIndex = Int($0) }
                        ),
                        in: 0...Double(maxIndex),
                        step: 1
                    )
                    .frame(width: .infinity)

                    Button { nextPage() } label: {
                        Image(systemName: "chevron.right").font(.title3).frame(width: 44, height: 44)
                    }
                    .disabled(currentIndex >= maxIndex).opacity(currentIndex >= maxIndex ? 0.5 : 1)
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if isZoomed {
                Section {
                    Button { resetZoom() } label: {
                        HStack {
                            Label(String(localized: "reader_reset_zoom"), systemImage: "arrow.counterclockwise")
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 20).buttonStyle(.glass)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: isZoomed)
            }
        }
        .statusBarHidden(!showControls)
        .onAppear {
            loadPage(currentIndex)
            preloadAdjacent()
        }
        .onDisappear { cancelAllTasks() }
        .onChange(of: currentIndex) { _, _ in
            resetZoom(animated: false)
            loadPage(currentIndex)
            preloadAdjacent()
        }
    }

    // MARK: - File Helpers

    fileprivate func filePath(at index: Int) -> String {
        guard index >= 0, index < files.count else { return "" }
        return files[index].defaultSource?.path ?? files[index].path ?? ""
    }

    fileprivate func isImageFile(_ path: String) -> Bool {
        let clean = path.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? path
        let ext = (clean as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        if let type = UTType(filenameExtension: ext) { return type.conforms(to: .image) }
        let fallback: Set<String> = ["jpg","jpeg","png","gif","webp","heic","heif","bmp","tif","tiff","avif"]
        return fallback.contains(ext)
    }

    fileprivate func iconForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        let video: Set<String> = ["mp4","mov","avi","mkv","webm","wmv","m4v","3gp"]
        if video.contains(ext) { return "video.fill" }
        let audio: Set<String> = ["mp3","wav","flac","aac","ogg","wma","m4a","aiff"]
        if audio.contains(ext) { return "music.note" }
        let archive: Set<String> = ["zip","rar","7z","tar","gz","bz2","xz","cbz","cbr"]
        if archive.contains(ext) { return "archivebox.fill" }
        let doc: Set<String> = ["pdf","doc","docx","pages","rtf"]
        if doc.contains(ext) { return "doc.richtext.fill" }
        let text: Set<String> = ["txt","md","json","xml","yaml","yml"]
        if text.contains(ext) { return "doc.text.fill" }
        let ebook: Set<String> = ["epub","mobi","azw","azw3"]
        if ebook.contains(ext) { return "book.closed.fill" }
        return "doc.fill"
    }

    // MARK: - Page View

    @ViewBuilder
    fileprivate func pageView(for index: Int, size: CGSize) -> some View {
        let path = filePath(at: index)
        let isImage = isImageFile(path)

        if !isImage {
            filePlaceholder(path: path, size: size)
        } else if let image = images[index] {
            ReaderPageView(
                image: image,
                scale: index == currentIndex ? currentScale : 1.0,
                panOffset: index == currentIndex ? panOffset : .zero
            )
            .frame(width: size.width, height: size.height)
        } else if failedPages.contains(index) {
            failedPageView(index: index, size: size)
        } else {
            loadingPageView(index: index, size: size)
                .task(id: path) { loadPage(index) }
        }
    }

    @ViewBuilder
    fileprivate func loadingPageView(index: Int, size: CGSize) -> some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.5)
            Text("\(index + 1) / \(files.count)")
                .font(.caption)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    fileprivate func failedPageView(index: Int, size: CGSize) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
            Text(String(localized: "reader_tap_reload")).font(.subheadline)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { failedPages.remove(index); loadPage(index) }
    }

    @ViewBuilder
    fileprivate func filePlaceholder(path: String, size: CGSize) -> some View {
        VStack(spacing: 12) {
            Image(systemName: iconForFile(path))
                .font(.system(size: 48))
            let name = (path as NSString).lastPathComponent
            if !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .lineLimit(1).truncationMode(.middle).padding(.horizontal, 32)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Animation Helpers

    fileprivate func withoutAnimation(_ action: () -> Void) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { action() }
    }

    fileprivate func clampedPanOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        guard let image = images[currentIndex],
              image.size.width > 0, image.size.height > 0 else { return .zero }
        let fitScale = min(UIScreen.main.bounds.width / image.size.width, UIScreen.main.bounds.height / image.size.height)
        let fw = image.size.width * fitScale * scale
        let fh = image.size.height * fitScale * scale
        let mx = max(0, (fw - UIScreen.main.bounds.width) / 2)
        let my = max(0, (fh - UIScreen.main.bounds.height) / 2)
        return CGSize(width: min(max(proposed.width, -mx), mx), height: min(max(proposed.height, -my), my))
    }

    fileprivate func animatePageChange(to targetIndex: Int, pageWidth w: CGFloat) {
        guard w > 0, targetIndex >= 0, targetIndex <= maxIndex, targetIndex != currentIndex, !isPageAnimating else { return }
        let targetOffset: CGFloat = targetIndex < currentIndex ? w : -w
        isPageAnimating = true; isDragging = true
        withAnimation(.easeOut(duration: 0.25), completionCriteria: .logicallyComplete) {
            dragOffset = targetOffset
        } completion: {
            withoutAnimation { currentIndex = targetIndex; dragOffset = 0 }
            isDragging = false; isPageAnimating = false
        }
    }

    fileprivate func finishPageDrag(_ value: DragGesture.Value, pageWidth w: CGFloat) {
        let t = value.translation.width
        let pred = value.predictedEndLocation.x - value.location.x
        if (t > w * 0.25 || pred > 100), currentIndex > 0 {
            animatePageChange(to: currentIndex - 1, pageWidth: w)
        } else if (t < -w * 0.25 || pred < -100), currentIndex < maxIndex {
            animatePageChange(to: currentIndex + 1, pageWidth: w)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
            isDragging = false
        }
    }

    fileprivate func resetZoom(animated: Bool = true) {
        let action = {
            currentScale = 1.0; lastScale = 1.0
            panOffset = .zero; lastPanOffset = .zero; isZoomed = false
        }
        if animated { withAnimation(.smooth(duration: 0.25)) { action() } }
        else { withoutAnimation { action() } }
    }
}

struct ReaderPageView: View {
    let image: UIImage
    let scale: CGFloat
    let panOffset: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable().scaledToFit()
            .scaleEffect(scale).offset(panOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

extension ReaderView {
    fileprivate func previousPage() {
        animatePageChange(to: currentIndex - 1, pageWidth: pageWidth)
    }

    fileprivate func nextPage() {
        animatePageChange(to: currentIndex + 1, pageWidth: pageWidth)
    }

    fileprivate func loadPage(_ index: Int) {
        guard index >= 0, index < files.count else { return }
        guard images[index] == nil else { return }
        guard !failedPages.contains(index) else { return }
        guard !isLoading.contains(index) else { return }

        let path = filePath(at: index)
        guard !path.isEmpty else { return }
        guard isImageFile(path) else { return }

        isLoading.insert(index)
        loadTasks[index]?.cancel()

        loadTasks[index] = Task {
            let cacheKey = "page_\(arcid)_\(path)"

            if let cached = CacheManager.shared.getCover(id: cacheKey),
               let img = UIImage(data: cached) {
                await MainActor.run {
                    images[index] = img; failedPages.remove(index); isLoading.remove(index); loadTasks[index] = nil
                }
                return
            }

            do {
                let data = try await server.apiClient.fetchPageImage(arcid: arcid, path: path)
                guard !Task.isCancelled else {
                    await MainActor.run { isLoading.remove(index); loadTasks[index] = nil }
                    return
                }
                guard let img = UIImage(data: data) else {
                    await MainActor.run { isLoading.remove(index); failedPages.insert(index); loadTasks[index] = nil }
                    return
                }
                CacheManager.shared.cacheCover(id: cacheKey, data: data)
                await MainActor.run {
                    images[index] = img; failedPages.remove(index); isLoading.remove(index); loadTasks[index] = nil
                }
            } catch {
                await MainActor.run {
                    isLoading.remove(index); loadTasks[index] = nil
                    if !Task.isCancelled { failedPages.insert(index) }
                }
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
