import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit
import CryptoKit
import ImageIO

extension Notification.Name {
    static let readerProgressDidChange = Notification.Name("readerProgressDidChange")
}

enum ReaderPageFileType {
    case unknown, image, video, audio
}

enum ReaderBottomControlFocus {
    case bookProgress, fileControl
}

enum ReaderReadingDirection: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftToRight: return String(localized: "reader_dir_ltr")
        case .rightToLeft: return String(localized: "reader_dir_rtl")
        case .vertical: return String(localized: "reader_dir_vertical")
        }
    }
}


fileprivate struct ReaderVerticalScrollRequest: Equatable {
    let token = UUID()
    let index: Int
    let animated: Bool
}

fileprivate struct ReaderVerticalPageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(
        value: inout [Int: CGRect],
        nextValue: () -> [Int: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
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
    @State fileprivate var imageAspectRatios: [Int: CGFloat] = [:]
    @State fileprivate var verticalScrollRequest: ReaderVerticalScrollRequest?
    @State fileprivate var isProgrammaticVerticalScroll = false
    @State fileprivate var showReaderSettings = false
    @State fileprivate var showTableOfContents = false
    @State fileprivate var thumbnailImages: [Int: UIImage] = [:]
    @State fileprivate var thumbnailFailedPages: Set<Int> = []
    @State fileprivate var thumbnailLoadTasks: [Int: Task<Void, Never>] = [:]
    @State fileprivate var currentPageFileType: ReaderPageFileType = .unknown
    @State fileprivate var bottomControlFocus: ReaderBottomControlFocus = .bookProgress
    @State fileprivate var audioCover: UIImage?
    @State fileprivate var audioCovers: [Int: UIImage] = [:]
    @State fileprivate var audioPlayer: AVAudioPlayer?
    @State fileprivate var isAudioPlaying = false
    @State fileprivate var audioDuration: TimeInterval = 0
    @State fileprivate var audioCurrentTime: TimeInterval = 0
    @State fileprivate var audioTimer: Timer?
    @State fileprivate var audioTitle: String?
    @State fileprivate var audioArtist: String?
    @State fileprivate var audioAlbum: String?
    @State fileprivate var videoPlayer: AVPlayer?
    @State fileprivate var videoPlayerIndex: Int?
    @State fileprivate var videoCurrentTime: Double = 0
    @State fileprivate var videoDuration: Double = 0
    @State fileprivate var isVideoPlaying = false
    @State fileprivate var isVideoLoading = false
    @State fileprivate var videoAspectRatio: CGFloat = 16 / 9
    @State fileprivate var videoTimeObserver: Any?
    @State fileprivate var videoEndObserver: NSObjectProtocol?
    @State fileprivate var videoLoadTask: Task<Void, Never>?
    @State fileprivate var videoCacheTask: Task<Void, Never>?
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
    @AppStorage("reader_video_autoplay") fileprivate var videoAutoplay = false
    @AppStorage("reader_reading_direction") fileprivate var readingDirectionRaw = ReaderReadingDirection.leftToRight.rawValue

    fileprivate var readingDirection: ReaderReadingDirection {
        ReaderReadingDirection(rawValue: readingDirectionRaw) ?? .leftToRight
    }

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
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    presentTableOfContents()
                } label: { Image(systemName: "list.bullet") }
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
                            Image(
                                systemName: bottomControlFocus == .bookProgress
                                ? "book.fill"
                                : "book"
                            )
                                .foregroundStyle(
                                    bottomControlFocus == .bookProgress
                                    ? AnyShapeStyle(.tint)
                                    : AnyShapeStyle(.primary)
                                )
                        }
                        if (bottomControlFocus == .bookProgress) {
                            Button { previousPage() } label: {
                                Image(
                                    systemName: readingDirection == .vertical
                                    ? "chevron.up"
                                    : "chevron.left"
                                )
                            }
                            .disabled(currentIndex <= 0)
                            .opacity(currentIndex <= 0 ? 0.5 : 1)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            Button { nextPage() } label: {
                                Image(
                                    systemName: readingDirection == .vertical
                                    ? "chevron.down"
                                    : "chevron.right"
                                )
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
                                        if readingDirection == .vertical {
                                            requestVerticalPage(
                                                newIndex,
                                                animated: false
                                            )
                                        } else {
                                            currentIndex = newIndex
                                        }
                                    }
                                }
                            ),
                            in: 0...Double(maxIndex),
                            step: 1
                        )
                        .frame(width: .infinity)
                        .padding(.trailing, 4)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
            }
            
            if let icon = mediaToolbarIcon {
                if (files.count > 1) {
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                }
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
                                .disabled(audioPlayer == nil)

                                Slider(
                                    value: $audioCurrentTime,
                                    in: 0...max(audioDuration, 1)
                                ) { editing in
                                    if !editing {
                                        audioPlayer?.currentTime = audioCurrentTime
                                    }
                                }
                                .frame(width: .infinity)
                                .disabled(audioPlayer == nil)

                                Text(
                                    timeString(audioCurrentTime)
                                    + " / "
                                    + timeString(audioDuration)
                                )
                                .font(.caption)
                                .monospacedDigit()
                            } else if (currentPageFileType == .video) {
                                Button {
                                    toggleVideoPlayback()
                                } label: {
                                    Image(systemName: isVideoPlaying ? "pause.fill" : "play.fill")
                                        .font(.title2)
                                        .frame(width: 36)
                                }
                                .disabled(videoPlayer == nil)

                                Slider(
                                    value: $videoCurrentTime,
                                    in: 0...max(videoDuration, 1)
                                ) { editing in
                                    if !editing {
                                        seekVideo(to: videoCurrentTime)
                                    }
                                }
                                .frame(width: .infinity)
                                .disabled(videoPlayer == nil)

                                Text(
                                    timeString(videoCurrentTime)
                                    + " / "
                                    + timeString(videoDuration)
                                )
                                .font(.caption)
                                .monospacedDigit()
                            }
                        }
                        .transition(
                            .move(edge: .trailing)
                                .combined(with: .opacity)
                        )
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            bottomControlFocus = .fileControl
                        }
                    } label: {
                        Image(systemName: icon)
                            .symbolVariant(
                                currentPageFileType == .video
                                && bottomControlFocus == .fileControl
                                ? .fill
                                : .none
                            )
                            .foregroundStyle(
                                bottomControlFocus == .fileControl
                                ? AnyShapeStyle(.tint)
                                : AnyShapeStyle(.primary)
                            )
                    }
                    .id(icon)
                    .transition(
                        .move(edge: .trailing)
                            .combined(with: .opacity)
                    )
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
                        .padding(.vertical, 6)
                    }
                    .padding(.horizontal, 16).buttonStyle(.glass)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: isZoomed)
            }
        }
        .statusBarHidden(!showControls)
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsView(
                doubleTapZoom: $doubleTapZoom,
                tapTurnPage: $tapTurnPage,
                audioAutoplay: $audioAutoplay,
                videoAutoplay: $videoAutoplay,
                readingDirection: $readingDirectionRaw
            )
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showTableOfContents) {
            ReaderTableOfContentsOverlay(
                pageCount: files.count,
                currentIndex: currentIndex,
                thumbnailImages: thumbnailImages,
                thumbnailFailedPages: thumbnailFailedPages,
                pathAt: { index in
                    filePath(at: index)
                },
                hasThumbnailSource: { index in
                    hasThumbnailSource(at: index)
                },
                iconForPath: { path in
                    iconForFile(path)
                },
                loadThumbnail: { index, maxDimension in
                    loadThumbnail(index, maxDimensionPoints: maxDimension)
                },
                selectPage: { index in
                    selectPageFromTableOfContents(index)
                    dismissTableOfContents()
                },
                dismiss: {
                    dismissTableOfContents()
                }
            )
            .presentationBackground(.clear)
            .interactiveDismissDisabled()
        }
        .onAppear {
            currentPageFileType = fileType(at: currentIndex)
            if files.count <= 1 && mediaToolbarIcon != nil  {
                bottomControlFocus = .fileControl
            }
            audioCover = nil
            if currentPageFileType == .audio {
                prepareAudio()
                if audioAutoplay { startAudio() }
            } else if currentPageFileType == .video {
                prepareVideo(at: currentIndex, autoplay: videoAutoplay)
            }

            if readingDirection == .vertical {
                preloadVerticalPages(around: currentIndex)
            } else {
                loadPage(currentIndex)
                preloadAdjacent()
            }
        }
        .onDisappear { cancelAllTasks(); stopAudio(); stopVideo(); saveProgress() }
        .onChange(of: currentIndex) { _, newIndex in
            updateBottomToolbar(for: newIndex)

            audioCover = nil
            audioTitle = nil
            audioArtist = nil
            audioAlbum = nil
            stopAudio()
            stopVideo()
            if fileType(at: newIndex) == .audio {
                prepareAudio()
                if audioAutoplay { startAudio() }
            } else if fileType(at: newIndex) == .video {
                prepareVideo(at: newIndex, autoplay: videoAutoplay)
            }
            resetZoom(animated: false)

            if readingDirection == .vertical {
                preloadVerticalPages(around: newIndex)
            } else {
                loadPage(newIndex)
                preloadAdjacent()
            }
        }
        .onChange(of: readingDirectionRaw) { _, _ in
            resetZoom(animated: false)
            withAnimation(.easeOut(duration: 0.25)) {
                progressValue = Double(currentIndex)
            }
            withoutAnimation {
                dragOffset = 0
                isDragging = false
                isPageAnimating = false
            }

            if readingDirection == .vertical {
                preloadVerticalPages(around: currentIndex)
                requestVerticalPage(currentIndex, animated: false)
            } else {
                loadPage(currentIndex)
                preloadAdjacent()
            }
        }
    }

    // MARK: - Reader Canvas

    @ViewBuilder
    fileprivate func readerCanvas(size: CGSize) -> some View {
        switch readingDirection {
        case .vertical:
            verticalReaderCanvas(size: size)
        default:
            ZStack {
                pageStrip(size: size)
                interactionOverlay(pageSize: size)
            }
        }
    }

    @ViewBuilder
    fileprivate func verticalReaderCanvas(size: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(files.indices, id: \.self) { index in
                        verticalPageView(
                            for: index,
                            width: size.width,
                            viewportHeight: size.height
                        )
                        .id(index)
                        .background {
                            GeometryReader { pageGeometry in
                                Color.clear.preference(
                                    key: ReaderVerticalPageFramePreferenceKey.self,
                                    value: [
                                        index: pageGeometry.frame(
                                            in: .named("reader_vertical_scroll")
                                        )
                                    ]
                                )
                            }
                        }
                        .onAppear {
                            preloadVerticalPages(around: index)
                        }
                    }
                }
            }
            .coordinateSpace(name: "reader_vertical_scroll")
            .scrollIndicators(.hidden)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
            }
            .onPreferenceChange(
                ReaderVerticalPageFramePreferenceKey.self
            ) { frames in
                updateVerticalCurrentPage(
                    from: frames,
                    viewportHeight: size.height
                )
            }
            .onAppear {
                preloadVerticalPages(around: currentIndex)
                DispatchQueue.main.async {
                    withoutAnimation {
                        scrollProxy.scrollTo(currentIndex, anchor: .top)
                    }
                    isProgrammaticVerticalScroll = false
                }
            }
            .onChange(of: verticalScrollRequest) { _, request in
                guard let request else { return }

                DispatchQueue.main.async {
                    if request.animated {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(request.index, anchor: .top)
                        }
                    } else {
                        withoutAnimation {
                            scrollProxy.scrollTo(request.index, anchor: .top)
                        }
                    }

                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + (request.animated ? 0.34 : 0.05)
                    ) {
                        isProgrammaticVerticalScroll = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    fileprivate func verticalPageView(
        for index: Int,
        width: CGFloat,
        viewportHeight: CGFloat
    ) -> some View {
        let path = filePath(at: index)
        let height = verticalPageHeight(
            index: index,
            width: width,
            viewportHeight: viewportHeight
        )

        if isImageFile(path) {
            if let image = images[index] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
            } else if failedPages.contains(index) {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(String(localized: "reader_tap_reload"))
                        .font(.subheadline)
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .onTapGesture {
                    retryPage(index)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("\(index + 1) / \(files.count)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .frame(width: width, height: height)
                .task(id: path) {
                    loadPage(index)
                }
            }
        } else {
            pageView(
                for: index,
                size: CGSize(width: width, height: height)
            )
            .frame(width: width, height: height)
        }
    }

    fileprivate func verticalPageHeight(
        index: Int,
        width: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        if fileType(at: index) == .image {
            if let aspectRatio = imageAspectRatios[index],
               aspectRatio.isFinite,
               aspectRatio > 0 {
                return width * aspectRatio
            }

            if let image = images[index],
               image.size.width > 0,
               image.size.height > 0 {
                return width * image.size.height / image.size.width
            }

            if let thumbnail = thumbnailImages[index],
               thumbnail.size.width > 0,
               thumbnail.size.height > 0 {
                return width * thumbnail.size.height / thumbnail.size.width
            }

            return width * 4 / 3
        }

        return viewportHeight
    }

    fileprivate func updateVerticalCurrentPage(
        from frames: [Int: CGRect],
        viewportHeight: CGFloat
    ) {
        guard readingDirection == .vertical,
              !isProgrammaticVerticalScroll,
              viewportHeight > 0 else { return }

        let viewportCenter = viewportHeight / 2
        let visibleFrames = frames.filter { _, frame in
            frame.maxY > 0 && frame.minY < viewportHeight
        }

        guard let nearestPage = visibleFrames.min(by: { lhs, rhs in
            abs(lhs.value.midY - viewportCenter)
                < abs(rhs.value.midY - viewportCenter)
        })?.key,
              nearestPage != currentIndex else {
            return
        }
        
        withAnimation(.easeOut(duration: 0.25)) {
            progressValue = Double(nearestPage)
        }
        withoutAnimation {
            currentIndex = nearestPage
        }
    }

    fileprivate func audioPageView(for index: Int, size: CGSize) -> some View {
        let file = index >= 0 && index < files.count ? files[index] : nil
        let filePath = file?.defaultSource?.path ?? file?.path ?? ""
        let fileName = (filePath as NSString).lastPathComponent
        let cover = audioCovers[index] ?? (index == currentIndex ? audioCover : nil)
        let title = index == currentIndex ? audioTitle : nil
        let artist = index == currentIndex ? audioArtist : nil
        let album = index == currentIndex ? audioAlbum : nil

        return VStack(spacing: 16) {
            Spacer()
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
                if let cover {
                    Image(uiImage: cover)
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
                Text(title ?? fileName)
                    .font(.title2)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(artist ?? String(localized: "reader_audio_artist"))
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(album ?? String(localized: "reader_audio_album"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(width: size.width, height: size.height)
        .task(id: index) {
            await loadAudioCover(at: index)
        }
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

            // Cache audio data and read metadata
            if CacheManager.shared.getCover(id: cacheKey) == nil {
                CacheManager.shared.cacheCover(id: cacheKey, data: data)
            }
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("image_cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let fileURL = cacheDir.appendingPathComponent(cacheKey)
            try? data.write(to: fileURL)

            let metaKey = "audio_meta_\(arcid)_\(path)"
            var title: String?
            var artist: String?
            var album: String?
            if let saved = UserDefaults.standard.dictionary(forKey: metaKey) as? [String: String] {
                title = saved["title"]; artist = saved["artist"]; album = saved["album"]
            } else {
                let asset = AVURLAsset(url: fileURL)
                let metadata = try? await asset.load(.commonMetadata)
                for item in metadata ?? [] {
                    if item.commonKey == .commonKeyTitle { title = try? await item.load(.value) as? String }
                    if item.commonKey == .commonKeyArtist { artist = try? await item.load(.value) as? String }
                    if item.commonKey == .commonKeyAlbumName { album = try? await item.load(.value) as? String }
                }
                var dict: [String: String] = [:]
                if let t = title { dict["title"] = t }
                if let a = artist { dict["artist"] = a }
                if let a = album { dict["album"] = a }
                UserDefaults.standard.set(dict, forKey: metaKey)
            }

            await MainActor.run {
                audioPlayer = player
                audioDuration = player.duration
                audioCurrentTime = player.currentTime
                audioTitle = title
                audioArtist = artist
                audioAlbum = album
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

    fileprivate func prepareVideo(at index: Int, autoplay: Bool) {
        guard index >= 0, index < files.count else { return }
        let path = filePath(at: index)
        guard !path.isEmpty else { return }

        if videoPlayerIndex == index, let videoPlayer {
            if autoplay {
                videoPlayer.play()
                isVideoPlaying = true
            }
            return
        }

        stopVideo()
        isVideoLoading = true
        videoPlayerIndex = index
        videoLoadTask = Task {
            do {
                let source = try videoSource(path: path)
                guard !Task.isCancelled, currentIndex == index else { return }

                let asset = AVURLAsset(
                    url: source.url,
                    options: source.headers.map {
                        ["AVURLAssetHTTPHeaderFieldsKey": $0]
                    }
                )
                let tracks = try await asset.loadTracks(withMediaType: .video)
                var aspectRatio: CGFloat = 16 / 9
                if let track = tracks.first {
                    let naturalSize = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let transformedSize = naturalSize.applying(transform)
                    let width = abs(transformedSize.width)
                    let height = abs(transformedSize.height)
                    if width > 0, height > 0 { aspectRatio = width / height }
                }

                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                await MainActor.run {
                    guard currentIndex == index else { return }
                    videoPlayer = player
                    videoAspectRatio = aspectRatio
                    isVideoLoading = false
                    installVideoObservers(on: player, item: item)
                    if autoplay {
                        player.play()
                        isVideoPlaying = true
                    }
                }

                if !source.isCached {
                    cacheVideoInBackground(path: path, destination: source.cacheURL)
                }
            } catch {
                await MainActor.run {
                    if currentIndex == index {
                        isVideoLoading = false
                        videoPlayerIndex = nil
                    }
                }
            }
        }
    }

    fileprivate func videoSource(path: String) throws -> (
        url: URL,
        headers: [String: String]?,
        cacheURL: URL,
        isCached: Bool
    ) {
        let digest = SHA256.hash(data: Data("\(arcid)|\(path)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let ext = (path as NSString).pathExtension
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reader_media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cacheURL = directory.appendingPathComponent(digest).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return (cacheURL, nil, cacheURL, true)
        }

        let request = try server.apiClient.pageRequest(arcid: arcid, path: path)
        guard let url = request.url else {
            throw AuthError.networkError(String(localized: "invalid_url"))
        }
        let headers = request.allHTTPHeaderFields?.isEmpty == false
            ? request.allHTTPHeaderFields
            : nil
        return (url, headers, cacheURL, false)
    }

    fileprivate func cacheVideoInBackground(path: String, destination: URL) {
        videoCacheTask?.cancel()
        videoCacheTask = Task {
            do {
                let request = try server.apiClient.pageRequest(arcid: arcid, path: path)
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                guard !Task.isCancelled,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { return }

                let stagedURL = destination.appendingPathExtension("download")
                try? FileManager.default.removeItem(at: stagedURL)
                try FileManager.default.moveItem(at: temporaryURL, to: stagedURL)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: stagedURL, to: destination)
            } catch {
                if !Task.isCancelled {
                    LogManager.shared.log("[Reader] video cache failed: \(error.localizedDescription)")
                }
            }
        }
    }

    fileprivate func installVideoObservers(on player: AVPlayer, item: AVPlayerItem) {
        videoTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            videoCurrentTime = time.seconds.isFinite ? time.seconds : 0
            let seconds = item.duration.seconds
            if seconds.isFinite { videoDuration = seconds }
            isVideoPlaying = player.timeControlStatus == .playing
        }
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isVideoPlaying = false
            videoCurrentTime = videoDuration
        }
    }

    fileprivate func toggleVideoPlayback() {
        guard let videoPlayer else { return }
        if isVideoPlaying {
            videoPlayer.pause()
            isVideoPlaying = false
        } else {
            if videoDuration > 0, videoCurrentTime >= videoDuration - 0.1 {
                videoPlayer.seek(to: .zero)
            }
            videoPlayer.play()
            isVideoPlaying = true
        }
    }

    fileprivate func seekVideo(to seconds: Double) {
        videoPlayer?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    fileprivate func stopVideo() {
        videoLoadTask?.cancel()
        videoLoadTask = nil
        videoCacheTask?.cancel()
        videoCacheTask = nil
        videoPlayer?.pause()
        if let observer = videoTimeObserver, let videoPlayer {
            videoPlayer.removeTimeObserver(observer)
        }
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        videoTimeObserver = nil
        videoEndObserver = nil
        videoPlayer = nil
        videoPlayerIndex = nil
        videoCurrentTime = 0
        videoDuration = 0
        isVideoPlaying = false
        isVideoLoading = false
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

    fileprivate func loadAudioCover(at index: Int) async {
        guard index >= 0, index < files.count else { return }
        guard audioCovers[index] == nil else { return }

        let file = files[index]
        let thumbId = file.defaultSource?.metadata?.thumbAssetId
            ?? file.metadata?.thumbAssetId
            ?? 0
        guard thumbId > 0 else { return }

        let cacheKey = "thumb_\(thumbId)"

        if let cached = CacheManager.shared.getCover(id: cacheKey),
           let image = UIImage(data: cached) {
            await MainActor.run {
                audioCovers[index] = image
                if index == currentIndex {
                    audioCover = image
                }
            }
            return
        }

        do {
            let data = try await server.apiClient.fetchAsset(assetId: thumbId)
            guard !Task.isCancelled else { return }
            CacheManager.shared.cacheCover(id: cacheKey, data: data)

            guard let image = UIImage(data: data) else { return }
            await MainActor.run {
                audioCovers[index] = image
                if index == currentIndex {
                    audioCover = image
                }
            }
        } catch {}
    }

    @ViewBuilder
    fileprivate func pageStrip(size: CGSize) -> some View {
        HStack(spacing: 0) {
            if readingDirection == .rightToLeft {
                // 右到左时，高页码位于当前页左侧，低页码位于右侧。
                if currentIndex < maxIndex {
                    pageView(for: currentIndex + 1, size: size)
                        .frame(width: size.width, height: size.height)
                } else {
                    Color.black
                        .frame(width: size.width, height: size.height)
                }
            } else {
                if currentIndex > 0 {
                    pageView(for: currentIndex - 1, size: size)
                        .frame(width: size.width, height: size.height)
                } else {
                    Color.black
                        .frame(width: size.width, height: size.height)
                }
            }

            pageView(for: currentIndex, size: size)
                .frame(width: size.width, height: size.height)

            if readingDirection == .rightToLeft {
                if currentIndex > 0 {
                    pageView(for: currentIndex - 1, size: size)
                        .frame(width: size.width, height: size.height)
                } else {
                    Color.black
                        .frame(width: size.width, height: size.height)
                }
            } else {
                if currentIndex < maxIndex {
                    pageView(for: currentIndex + 1, size: size)
                        .frame(width: size.width, height: size.height)
                } else {
                    Color.black
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        // 无论阅读方向如何，当前页都始终位于三页容器的中间。
        .offset(x: -size.width + dragOffset)
    }

    fileprivate func interactionOverlay(pageSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .highPriorityGesture(doubleTapGesture)
            .onTapGesture { location in
                handleSingleTap(at: location, pageSize: pageSize)
            }
            .gesture(pageDragGesture(pageWidth: pageSize.width))
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

    fileprivate func handleSingleTap(at location: CGPoint, pageSize: CGSize) {
        let x = location.x
        let y = location.y
        let isCenterColumn = x >= pageSize.width * 0.3
            && x <= pageSize.width * 0.7
        let isCenterReloadBand = y >= pageSize.height * 0.4
            && y <= pageSize.height * 0.6

        if failedPages.contains(currentIndex),
           isImageFile(filePath(at: currentIndex)),
           isCenterColumn,
           isCenterReloadBand {
            retryPage(currentIndex)
            return
        }

        if tapTurnPage, x < pageSize.width * 0.3 {
            if readingDirection == .rightToLeft {
                nextPage()
            } else {
                previousPage()
            }
        } else if tapTurnPage, x > pageSize.width * 0.7 {
            if readingDirection == .rightToLeft {
                previousPage()
            } else {
                nextPage()
            }
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
            let needsDamping: Bool

            if readingDirection == .rightToLeft {
                // 右滑进入更高页码；左滑进入更低页码。
                needsDamping =
                    (currentIndex == maxIndex && translation > 0) ||
                    (currentIndex == 0 && translation < 0)
            } else {
                needsDamping =
                    (currentIndex == 0 && translation > 0) ||
                    (currentIndex == maxIndex && translation < 0)
            }

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
        guard !isPageAnimating else { return }
        guard !isDragging else { return }
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
        guard !isPageAnimating else { return }
        guard !isDragging else { return }
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

    // MARK: - Table of Contents

    fileprivate func hasThumbnailSource(at index: Int) -> Bool {
        guard index >= 0, index < files.count else { return false }
        let file = files[index]
        let thumbnailAssetId =
            file.defaultSource?.metadata?.thumbAssetId
            ?? file.metadata?.thumbAssetId
            ?? 0

        return thumbnailAssetId > 0 || isImageFile(filePath(at: index))
    }

    fileprivate func selectPageFromTableOfContents(_ index: Int) {
        guard index >= 0, index < files.count else { return }

        if readingDirection == .vertical {
            requestVerticalPage(index, animated: false)
            return
        }

        guard index != currentIndex else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            progressValue = Double(index)
        }

        withoutAnimation {
            dragOffset = 0
            isDragging = false
            isPageAnimating = false
            currentIndex = index
        }
    }

    fileprivate func loadThumbnail(_ index: Int, maxDimensionPoints: CGFloat) {
        guard index >= 0, index < files.count else { return }
        guard thumbnailImages[index] == nil else { return }
        guard !thumbnailFailedPages.contains(index) else { return }
        guard thumbnailLoadTasks[index] == nil else { return }

        let file = files[index]
        let path = filePath(at: index)
        let thumbnailAssetId =
            file.defaultSource?.metadata?.thumbAssetId
            ?? file.metadata?.thumbAssetId
            ?? 0

        guard thumbnailAssetId > 0 || isImageFile(path) else { return }

        let requestedPixels = maxDimensionPoints * UIScreen.main.scale
        let maxPixelSize = min(max(requestedPixels, 384), 1024)
        let sizeBucket = Int(ceil(maxPixelSize / 128) * 128)
        let sourceIdentity = thumbnailAssetId > 0
            ? "asset_\(thumbnailAssetId)"
            : "page_\(arcid)_\(path)"
        let thumbnailCacheKey = "reader_toc_\(sizeBucket)_\(sourceIdentity)"

        thumbnailLoadTasks[index] = Task {
            if let cachedData = CacheManager.shared.getCover(id: thumbnailCacheKey),
               let cachedImage = UIImage(data: cachedData) {
                await MainActor.run {
                    thumbnailImages[index] = cachedImage
                    thumbnailFailedPages.remove(index)
                    thumbnailLoadTasks[index] = nil
                }
                return
            }

            do {
                let sourceData: Data

                if thumbnailAssetId > 0 {
                    let sourceCacheKey = "thumb_\(thumbnailAssetId)"
                    if let cachedData = CacheManager.shared.getCover(id: sourceCacheKey) {
                        sourceData = cachedData
                    } else {
                        let data = try await server.apiClient.fetchAsset(assetId: thumbnailAssetId)
                        CacheManager.shared.cacheCover(id: sourceCacheKey, data: data)
                        sourceData = data
                    }
                } else {
                    let sourceCacheKey = "page_\(arcid)_\(path)"
                    if let cachedData = CacheManager.shared.getCover(id: sourceCacheKey) {
                        sourceData = cachedData
                    } else {
                        let data = try await server.apiClient.fetchPageImage(arcid: arcid, path: path)
                        CacheManager.shared.cacheCover(id: sourceCacheKey, data: data)
                        sourceData = data
                    }
                }

                guard !Task.isCancelled else {
                    await MainActor.run {
                        thumbnailLoadTasks[index] = nil
                    }
                    return
                }

                guard let thumbnail = downsampleImage(
                    data: sourceData,
                    maxPixelSize: maxPixelSize
                ) else {
                    await MainActor.run {
                        thumbnailFailedPages.insert(index)
                        thumbnailLoadTasks[index] = nil
                    }
                    return
                }

                if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.84) {
                    CacheManager.shared.cacheCover(
                        id: thumbnailCacheKey,
                        data: thumbnailData
                    )
                }

                await MainActor.run {
                    thumbnailImages[index] = thumbnail
                    thumbnailFailedPages.remove(index)
                    thumbnailLoadTasks[index] = nil
                }
            } catch {
                await MainActor.run {
                    thumbnailLoadTasks[index] = nil
                    if !Task.isCancelled {
                        thumbnailFailedPages.insert(index)
                    }
                }
            }
        }
    }

    fileprivate func downsampleImage(
        data: Data,
        maxPixelSize: CGFloat
    ) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            sourceOptions
        ) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else {
            return nil
        }

        return UIImage(cgImage: image)
    }

    // MARK: - Page View

    @ViewBuilder
    fileprivate func pageView(for index: Int, size: CGSize) -> some View {
        let path = filePath(at: index)
        let isImage = isImageFile(path)

        if fileType(at: index) == .audio {
            audioPageView(for: index, size: size)
        } else if fileType(at: index) == .video {
            videoPageView(for: index, size: size)
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
    fileprivate func videoPageView(for index: Int, size: CGSize) -> some View {
        ZStack {
            Color.black
            if videoPlayerIndex == index, let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .aspectRatio(videoAspectRatio, contentMode: .fit)
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text((filePath(at: index) as NSString).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .task(id: index) {
                    guard index == currentIndex else { return }
                    prepareVideo(at: index, autoplay: videoAutoplay)
                }
            }
        }
        .frame(width: size.width, height: size.height)
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
        .onTapGesture { retryPage(index) }
    }

    fileprivate func retryPage(_ index: Int) {
        failedPages.remove(index)
        loadPage(index)
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
        guard w > 0,
              targetIndex >= 0,
              targetIndex <= maxIndex,
              targetIndex != currentIndex,
              !isPageAnimating else { return }

        let movesToHigherIndex = targetIndex > currentIndex
        let targetOffset: CGFloat

        if readingDirection == .rightToLeft {
            // 右到左：更高页码在左侧，因此容器向右移动。
            targetOffset = movesToHigherIndex ? w : -w
        } else {
            targetOffset = movesToHigherIndex ? -w : w
        }

        isPageAnimating = true
        isDragging = true
        withAnimation(.easeOut(duration: 0.25), completionCriteria: .logicallyComplete) {
            dragOffset = targetOffset
            progressValue = Double(targetIndex)
        } completion: {
            withoutAnimation {
                currentIndex = targetIndex
                dragOffset = 0
            }
            isDragging = false
            isPageAnimating = false
        }
    }

    fileprivate func finishPageDrag(_ value: DragGesture.Value, pageWidth w: CGFloat) {
        let translation = value.translation.width
        let predictedTranslation =
            value.predictedEndLocation.x - value.location.x
        let swipedRight =
            translation > w * 0.25 || predictedTranslation > 100
        let swipedLeft =
            translation < -w * 0.25 || predictedTranslation < -100

        let rightSwipeTarget = readingDirection == .rightToLeft
            ? currentIndex + 1
            : currentIndex - 1
        let leftSwipeTarget = readingDirection == .rightToLeft
            ? currentIndex - 1
            : currentIndex + 1

        if swipedRight,
           rightSwipeTarget >= 0,
           rightSwipeTarget <= maxIndex {
            animatePageChange(to: rightSwipeTarget, pageWidth: w)
        } else if swipedLeft,
                  leftSwipeTarget >= 0,
                  leftSwipeTarget <= maxIndex {
            animatePageChange(to: leftSwipeTarget, pageWidth: w)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffset = 0
            }
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

private struct ReaderTableOfContentsOverlay: View {
    let pageCount: Int
    let currentIndex: Int
    let thumbnailImages: [Int: UIImage]
    let thumbnailFailedPages: Set<Int>
    let pathAt: (Int) -> String
    let hasThumbnailSource: (Int) -> Bool
    let iconForPath: (String) -> String
    let loadThumbnail: (Int, CGFloat) -> Void
    let selectPage: (Int) -> Void
    let dismiss: () -> Void

    @State private var isPanelVisible = false
    @State private var isClosing = false

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = min(
                max(geometry.size.width * 0.48, 180),
                420
            )
            let thumbnailWidth = max(
                72,
                min(
                    geometry.size.width / 3,
                    panelWidth - 32
                )
            )
            let thumbnailHeight = thumbnailWidth * 4 / 3

            ZStack(alignment: .leading) {
                Color.black
                    .ignoresSafeArea(.container, edges: .vertical)
                    .opacity(isPanelVisible ? 0.32 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closePanel(completion: dismiss)
                    }

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "reader_toc_title"))
                                .font(.headline)
                            Text("\(currentIndex + 1) / \(pageCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Spacer(minLength: 0)

                        Button {
                            closePanel(completion: dismiss)
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                    Divider()

                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 16) {
                                ForEach(0..<pageCount, id: \.self) { index in
                                    Button {
                                        closePanel {
                                            selectPage(index)
                                        }
                                    } label: {
                                        thumbnailCell(
                                            for: index,
                                            width: thumbnailWidth,
                                            height: thumbnailHeight
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 18)
                        }
                        .scrollIndicators(.hidden)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                scrollProxy.scrollTo(currentIndex, anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                }
                .shadow(radius: 24, y: 8)
                .padding(.leading, 12)
                .offset(x: isPanelVisible ? 0 : -(panelWidth + 32))
            }
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.24)) {
                        isPanelVisible = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(
        for index: Int,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let path = pathAt(index)
        let canLoadThumbnail = hasThumbnailSource(index)
        let isCurrentPage = index == currentIndex

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)

            if let image = thumbnailImages[index] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .padding(4)
            } else if canLoadThumbnail {
                if thumbnailFailedPages.contains(index) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: iconForPath(path))
                        .font(.system(size: 30))
                    Text((path as NSString).lastPathComponent)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text("\(index + 1)")
                .font(.caption2)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                // .background(.regularMaterial, in: Capsule())
                .glassEffect(.regular, in: Capsule())
                .padding(7)
        }
        .padding(4)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isCurrentPage ? Color.accentColor : Color.clear,
                    lineWidth: 3
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if canLoadThumbnail,
               thumbnailImages[index] == nil,
               !thumbnailFailedPages.contains(index) {
                loadThumbnail(index, max(width, height))
            }
        }
    }

    private func closePanel(completion: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true

        withAnimation(.easeIn(duration: 0.2)) {
            isPanelVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            completion()
        }
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
    @Binding var videoAutoplay: Bool
    @Binding var readingDirection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "reader_dir_section")) {
                    Picker(String(localized: "reader_dir_picker"), selection: $readingDirection) {
                        ForEach(ReaderReadingDirection.allCases) { direction in
                            Text(direction.title)
                                .tag(direction.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section(String(localized: "reader_settings_gesture")) {
                    Toggle(String(localized: "reader_settings_double_tap"), isOn: $doubleTapZoom)
                    Toggle(String(localized: "reader_settings_tap_turn"), isOn: $tapTurnPage)
                }
                Section(String(localized: "reader_settings_playback")) {
                    Toggle(String(localized: "reader_settings_audio_autoplay"), isOn: $audioAutoplay)
                    Toggle(String(localized: "reader_settings_video_autoplay"), isOn: $videoAutoplay)
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
    /// 禁用 fullScreenCover 自带的底部呈现动画，只保留目录面板内部的左侧滑入动画。
    fileprivate func presentTableOfContents() {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            showTableOfContents = true
        }
    }

    /// 面板自身完成左滑退出后，立即移除透明的 fullScreenCover 容器。
    fileprivate func dismissTableOfContents() {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            showTableOfContents = false
        }
    }

    fileprivate func previousPage() {
        let targetIndex = currentIndex - 1
        guard targetIndex >= 0 else { return }

        if readingDirection == .vertical {
            requestVerticalPage(targetIndex, animated: true)
        } else {
            animatePageChange(to: targetIndex, pageWidth: pageWidth)
        }
    }

    fileprivate func nextPage() {
        let targetIndex = currentIndex + 1
        guard targetIndex <= maxIndex else { return }

        if readingDirection == .vertical {
            requestVerticalPage(targetIndex, animated: true)
        } else {
            animatePageChange(to: targetIndex, pageWidth: pageWidth)
        }
    }

    fileprivate func requestVerticalPage(
        _ index: Int,
        animated: Bool
    ) {
        guard index >= 0, index <= maxIndex else { return }

        isProgrammaticVerticalScroll = true
        withAnimation(.easeOut(duration: 0.25)) {
            progressValue = Double(index)
        }
        withoutAnimation {
            currentIndex = index
        }
        preloadVerticalPages(around: index)
        verticalScrollRequest = ReaderVerticalScrollRequest(
            index: index,
            animated: animated
        )
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
                    images[index] = img
                    if img.size.width > 0, img.size.height > 0 {
                        imageAspectRatios[index] = img.size.height / img.size.width
                    }
                    failedPages.remove(index)
                    isLoading.remove(index)
                    loadTasks[index] = nil
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
                    images[index] = img
                    if img.size.width > 0, img.size.height > 0 {
                        imageAspectRatios[index] = img.size.height / img.size.width
                    }
                    failedPages.remove(index)
                    isLoading.remove(index)
                    loadTasks[index] = nil
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                loadPage(nextIndex)
            }
        }
    }

    fileprivate func preloadVerticalPages(around index: Int) {
        guard readingDirection == .vertical,
              !files.isEmpty else { return }

        let preloadRange = max(0, index - 2)...min(maxIndex, index + 3)
        for pageIndex in preloadRange where fileType(at: pageIndex) == .image {
            loadPage(pageIndex)
        }

        trimVerticalPageCache(around: index)
    }

    fileprivate func trimVerticalPageCache(around index: Int) {
        let keepRange = max(0, index - 5)...min(maxIndex, index + 6)
        let imageIndexesToRemove = images.keys.filter {
            !keepRange.contains($0)
        }
        for pageIndex in imageIndexesToRemove {
            images.removeValue(forKey: pageIndex)
        }

        let taskIndexesToCancel = loadTasks.keys.filter {
            !keepRange.contains($0)
        }
        for pageIndex in taskIndexesToCancel {
            // 只发出取消信号，由任务自身统一清理状态，避免快速跳页时
            // 旧任务覆盖同一页的新任务状态。
            loadTasks[pageIndex]?.cancel()
        }
    }

    fileprivate func saveProgress() {
        let page = currentIndex + 1
        Task { try? await server.apiClient.updateProgress(arcid: arcid, page: page) }
        // Update cached metadata progress
        if var data = CacheManager.shared.getArchiveMetadata(arcid: arcid),
           var meta = try? JSONDecoder().decode(APIClient.ArchiveMetadata.self, from: data) {
            meta.progress = page
            if let encoded = try? JSONEncoder().encode(meta) {
                CacheManager.shared.cacheArchiveMetadata(arcid: arcid, data: encoded)
            }
        }

        NotificationCenter.default.post(
            name: .readerProgressDidChange,
            object: nil,
            userInfo: [
                "serverId": server.baseURL,
                "arcid": arcid,
                "page": page
            ]
        )
    }

    fileprivate func cancelAllTasks() {
        for task in loadTasks.values { task.cancel() }
        loadTasks.removeAll()

        for task in thumbnailLoadTasks.values { task.cancel() }
        thumbnailLoadTasks.removeAll()
    }
}
