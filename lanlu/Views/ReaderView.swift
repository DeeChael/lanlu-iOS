import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

enum ReaderPageFileType {
    case unknown, image, video, audio
}

enum ReaderBottomControlFocus {
    case bookProgress, fileControl
}

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
    @State fileprivate var showReaderSettings = false
    @State fileprivate var currentPageFileType: ReaderPageFileType = .unknown
    @State fileprivate var bottomControlFocus: ReaderBottomControlFocus = .bookProgress
    @State fileprivate var audioCover: UIImage?
    @State fileprivate var audioPlayer: AVAudioPlayer?
    @State fileprivate var isAudioPlaying = false
    @State fileprivate var audioDuration: TimeInterval = 0
    @State fileprivate var audioCurrentTime: TimeInterval = 0
    @State fileprivate var audioTimer: Timer?
    fileprivate var mediaToolbarIcon: String? {
        switch currentPageFileType {
        case .audio:
            return "music.note"
        case .video:
            return "video"
        default:
            return nil
        }
    }
    @State fileprivate var progressValue: Double
    @AppStorage("reader_double_tap_zoom") fileprivate var doubleTapZoom = true
    @AppStorage("reader_tap_turn_page") fileprivate var tapTurnPage = true
    @AppStorage("reader_audio_autoplay") fileprivate var audioAutoplay = false

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
        _progressValue = State(initialValue: Double(startIndex))
    }

    var body: some View {
        GeometryReader { geo in
            readerCanvas(size: geo.size)
                .onAppear { pageWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, newValue in
                    pageWidth = newValue
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
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("\(currentIndex + 1) / \(files.count)").font(.subheadline)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showReaderSettings = true } label: { Image(systemName: "gearshape.fill") }
            }
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbar {
            if (files.count > 1) {
                ToolbarItemGroup(placement: .bottomBar) {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                bottomControlFocus = .bookProgress
                            }
                        } label: {
                            Image(systemName: "book")
                                .foregroundStyle(
                                    bottomControlFocus == .bookProgress
                                    ? AnyShapeStyle(.tint)
                                    : AnyShapeStyle(.primary)
                                )
                        }
                        if (bottomControlFocus == .bookProgress) {
                            Button { previousPage() } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(currentIndex <= 0)
                            .opacity(currentIndex <= 0 ? 0.5 : 1)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            Button { nextPage() } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(currentIndex >= maxIndex)
                            .opacity(currentIndex >= maxIndex ? 0.5 : 1)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    
                    if (bottomControlFocus == .bookProgress) {
                        Slider(
                            value: .init(
                                get: { progressValue },
                                set: { newValue in
                                    progressValue = newValue
                                    let newIndex = min(
                                        max(Int(newValue.rounded()), 0),
                                        maxIndex
                                    )
                                    
                                    if newIndex != currentIndex {
                                        currentIndex = newIndex
                                    }
                                }
                            ),
                            in: 0...Double(maxIndex),
                            step: 1
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, 4)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            
            if let icon = mediaToolbarIcon {
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    if (bottomControlFocus == .fileControl) {
                        HStack(spacing: 4) {
                            if (currentPageFileType == .audio) {
                                Button {
                                    if isAudioPlaying { audioPlayer?.pause() } else { audioPlayer?.play() }
                                    isAudioPlaying.toggle()
                                } label: {
                                    Image(systemName: isAudioPlaying ? "pause.fill" : "play.fill")
                                        .font(.title2)
                                        .frame(width: 36)
                                }
                                
                                Slider(value: $audioCurrentTime, in: 0...max(audioDuration, 1)) { editing in
                                    if !editing { audioPlayer?.currentTime = audioCurrentTime }
                                }
                                .tint(.white)
                                
                                Text(timeString(audioCurrentTime) + " / " + timeString(audioDuration))
                                    .font(.caption).monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            bottomControlFocus = .fileControl
                        }
                    } label: {
                        Image(systemName: icon)
                            .foregroundStyle(
                                bottomControlFocus == .fileControl
                                ? AnyShapeStyle(.tint)
                                : AnyShapeStyle(.primary)
                            )
                    }
                    .id(icon)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsView(doubleTapZoom: $doubleTapZoom, tapTurnPage: $tapTurnPage, audioAutoplay: $audioAutoplay)
                .presentationDetents([.large])
        }
        .onAppear {
            currentPageFileType = fileType(at: currentIndex)
            audioCover = nil
            if currentPageFileType == .audio { prepareAudio(); if audioAutoplay { startAudio() } }
            loadPage(currentIndex)
            preloadAdjacent()
        }
        .onDisappear { cancelAllTasks(); stopAudio() }
        .onChange(of: currentIndex) { _, newIndex in
            updateBottomToolbar(for: newIndex)

            audioCover = nil
            stopAudio()
            if currentPageFileType == .audio { prepareAudio(); if audioAutoplay { startAudio() } }
            resetZoom(animated: false)
            loadPage(newIndex)
            preloadAdjacent()
        }
    }

    // MARK: - Reader Canvas

    @ViewBuilder
    fileprivate func readerCanvas(size: CGSize) -> some View {
        ZStack {
            pageStrip(size: size)
            interactionOverlay(pageWidth: size.width)
        }
    }

    fileprivate func audioPageView(size: CGSize) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                if let coverData = audioCover {
                    Image(uiImage: coverData)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: size.width - 64, height: size.width - 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "reader_audio_artist"))
                    .font(.body)
                    .foregroundColor(.primary)
                Text(String(localized: "reader_audio_album"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(width: size.width, height: size.height)
        .task { await loadAudioCover() }
    }

    fileprivate func prepareAudio() {
        guard audioPlayer == nil else { return }
        guard currentIndex >= 0, currentIndex < files.count else { return }
        let path = filePath(at: currentIndex)
        guard !path.isEmpty else { return }
        Task {
            let cacheKey = "page_\(arcid)_\(path)"
            let data: Data
            if let cached = CacheManager.shared.getCover(id: cacheKey) {
                data = cached
            } else {
                guard let d = try? await server.apiClient.fetchPageImage(arcid: arcid, path: path) else { return }
                CacheManager.shared.cacheCover(id: cacheKey, data: d)
                data = d
            }
            guard let player = try? AVAudioPlayer(data: data) else { return }
            await MainActor.run {
                audioPlayer = player
                audioDuration = player.duration
                audioCurrentTime = player.currentTime
                startAudioTimer()
            }
        }
    }

    fileprivate func startAudio() {
        audioPlayer?.play()
        isAudioPlaying = true
    }

    fileprivate func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isAudioPlaying = false
        audioTimer?.invalidate()
        audioTimer = nil
    }

    fileprivate func startAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                audioCurrentTime = audioPlayer?.currentTime ?? 0
            }
        }
    }

    fileprivate func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    fileprivate func loadAudioCover() async {
        guard currentIndex >= 0, currentIndex < files.count else { return }
        let file = files[currentIndex]
        let thumbId = file.defaultSource?.metadata?.thumbAssetId ?? file.metadata?.thumbAssetId ?? 0
        guard thumbId > 0 else { return }
        let cacheKey = "thumb_\(thumbId)"
        if let cached = CacheManager.shared.getCover(id: cacheKey), let img = UIImage(data: cached) {
            audioCover = img
            return
        }
        do {
            let data = try await server.apiClient.fetchAsset(assetId: thumbId)
            CacheManager.shared.cacheCover(id: cacheKey, data: data)
            if let img = UIImage(data: data) { audioCover = img }
        } catch {}
    }

    @ViewBuilder
    fileprivate func pageStrip(size: CGSize) -> some View {
        HStack(spacing: 0) {
            if currentIndex > 0 {
                pageView(for: currentIndex - 1, size: size)
                    .frame(width: size.width, height: size.height)
            } else {
                Color.black
                    .frame(width: size.width, height: size.height)
            }

            pageView(for: currentIndex, size: size)
                .frame(width: size.width, height: size.height)

            if currentIndex < maxIndex {
                pageView(for: currentIndex + 1, size: size)
                    .frame(width: size.width, height: size.height)
            } else {
                Color.black
                    .frame(width: size.width, height: size.height)
            }
        }
        .offset(x: -size.width + dragOffset)
    }

    fileprivate func interactionOverlay(pageWidth: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .highPriorityGesture(doubleTapGesture)
            .onTapGesture { location in
                handleSingleTap(at: location, pageWidth: pageWidth)
            }
            .gesture(pageDragGesture(pageWidth: pageWidth))
            .simultaneousGesture(zoomGesture)
    }

    fileprivate var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                handleDoubleTap()
            }
    }

    fileprivate func pageDragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value, pageWidth: pageWidth)
            }
    }

    fileprivate var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                handleMagnificationChanged(value)
            }
            .onEnded { value in
                handleMagnificationEnded(value)
            }
    }

    fileprivate func handleDoubleTap() {
        guard doubleTapZoom else { return }
        guard currentFileIsImage else { return }

        if currentScale > 1.001 {
            resetZoom()
        } else {
            withAnimation(.smooth(duration: 0.25)) {
                currentScale = 3.0
                lastScale = 3.0
                panOffset = .zero
                lastPanOffset = .zero
                isZoomed = true
            }
        }
    }

    fileprivate func handleSingleTap(at location: CGPoint, pageWidth: CGFloat) {
        let x = location.x

        if tapTurnPage, x < pageWidth * 0.3 {
            previousPage()
        } else if tapTurnPage, x > pageWidth * 0.7 {
            nextPage()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
    }

    fileprivate func handleDragChanged(_ value: DragGesture.Value) {
        guard !isPageAnimating else { return }

        if currentFileIsImage, currentScale > 1.001 {
            let proposed = CGSize(
                width: lastPanOffset.width + value.translation.width,
                height: lastPanOffset.height + value.translation.height
            )
            withoutAnimation {
                panOffset = clampedPanOffset(proposed, scale: currentScale)
            }
        } else {
            isDragging = true
            let translation = value.translation.width
            let needsDamping =
                (currentIndex == 0 && translation > 0) ||
                (currentIndex == maxIndex && translation < 0)

            withoutAnimation {
                dragOffset = needsDamping ? translation * 0.2 : translation
            }
        }
    }

    fileprivate func handleDragEnded(_ value: DragGesture.Value, pageWidth: CGFloat) {
        guard !isPageAnimating else { return }

        if currentFileIsImage, currentScale > 1.001 {
            let proposed = CGSize(
                width: lastPanOffset.width + value.translation.width,
                height: lastPanOffset.height + value.translation.height
            )
            let corrected = clampedPanOffset(proposed, scale: currentScale)
            panOffset = corrected
            lastPanOffset = corrected
        } else {
            finishPageDrag(value, pageWidth: pageWidth)
        }
    }

    fileprivate func handleMagnificationChanged(_ value: CGFloat) {
        guard currentFileIsImage else { return }

        let newScale = min(max(lastScale * value, 1.0), 3.0)
        withoutAnimation {
            currentScale = newScale
            isZoomed = newScale > 1.001
            if newScale <= 1.001 {
                panOffset = .zero
                lastPanOffset = .zero
            }
        }
    }

    fileprivate func handleMagnificationEnded(_ value: CGFloat) {
        guard currentFileIsImage else { return }

        let finalScale = min(max(lastScale * value, 1.0), 3.0)
        if finalScale <= 1.001 {
            resetZoom()
        } else {
            currentScale = finalScale
            lastScale = finalScale
            isZoomed = true

            let corrected = clampedPanOffset(panOffset, scale: finalScale)
            withAnimation(.snappy(duration: 0.18)) {
                panOffset = corrected
            }
            lastPanOffset = corrected
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

    fileprivate func fileType(at index: Int) -> ReaderPageFileType {
        let path = filePath(at: index)
        if isImageFile(path) { return .image }
        let ext = (path as NSString).pathExtension.lowercased()
        let video: Set<String> = ["mp4","mov","avi","mkv","webm","wmv","m4v","3gp"]
        if video.contains(ext) { return .video }
        let audio: Set<String> = ["mp3","wav","flac","aac","ogg","wma","m4a","aiff"]
        if audio.contains(ext) { return .audio }
        return .unknown
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

        if fileType(at: index) == .audio {
            audioPageView(size: size)
        } else if !isImage {
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
    fileprivate func updateBottomToolbar(for index: Int) {
        let newFileType = fileType(at: index)

        // 脱离 currentIndex 的 withoutAnimation 事务
        DispatchQueue.main.async {
            guard currentIndex == index else { return }

            withAnimation(.easeInOut(duration: 0.22)) {
                currentPageFileType = newFileType

                // 当前页面没有文件控制器时，自动回到阅读进度控制
                if newFileType != .audio && newFileType != .video {
                    bottomControlFocus = .bookProgress
                }
            }
        }
    }

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
            progressValue = Double(targetIndex)
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

struct ReaderSettingsView: View {
    @Binding var doubleTapZoom: Bool
    @Binding var tapTurnPage: Bool
    @Binding var audioAutoplay: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "reader_settings_gesture")) {
                    Toggle(String(localized: "reader_settings_double_tap"), isOn: $doubleTapZoom)
                    Toggle(String(localized: "reader_settings_tap_turn"), isOn: $tapTurnPage)
                }
                Section(String(localized: "reader_settings_playback")) {
                    Toggle(String(localized: "reader_settings_audio_autoplay"), isOn: $audioAutoplay)
                }
            }
            .navigationTitle(String(localized: "reader_settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.semibold) }
                }
            }
        }
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
