import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit
import ImageIO

extension Notification.Name {
    static let readerProgressDidChange = Notification.Name("readerProgressDidChange")
}

enum ReaderPageFileType {
    case unknown, image, html, video, audio
}

enum ReaderBottomControlFocus {
    case bookProgress, fileControl
}

enum ReaderReadingDirection: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft
    case verticalPaged
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftToRight: return String(localized: "reader_dir_ltr")
        case .rightToLeft: return String(localized: "reader_dir_rtl")
        case .verticalPaged: return String(localized: "reader_dir_vertical_paged")
        case .vertical: return String(localized: "reader_dir_vertical")
        }
    }
}

enum ReaderTapGestureMode: String, CaseIterable, Identifiable {
    case leftRight
    case lShape
    case kindle
    case edges
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftRight: String(localized: "reader_tap_mode_left_right")
        case .lShape: String(localized: "reader_tap_mode_l_shape")
        case .kindle: "Kindle"
        case .edges: String(localized: "reader_tap_mode_edges")
        case .disabled: String(localized: "reader_tap_mode_disabled")
        }
    }
}



struct ReaderVerticalScrollRequest: Equatable {
    let token = UUID()
    let index: Int
    let animated: Bool
    let duration: TimeInterval?

    init(index: Int, animated: Bool, duration: TimeInterval? = nil) {
        self.index = index
        self.animated = animated
        self.duration = duration
    }
}

struct ReaderVerticalPageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(
        value: inout [Int: CGRect],
        nextValue: () -> [Int: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

struct ReaderAutoReadRefreshState: Equatable {
    let enabled: Bool
    let interval: Int
    let imagesOnly: Bool
    let controlsVisible: Bool
    let readerSettingsVisible: Bool
    let autoReadSettingsVisible: Bool
    let tableOfContentsVisible: Bool
    let appIsActive: Bool
}

struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase

    let arcid: String
    let files: [APIClient.PageFile]
    let startIndex: Int
    let server: Server
    let pageFileTypes: [ReaderPageFileType]

    @State var currentIndex: Int
    @State var showControls = false
    @State var images: [Int: UIImage] = [:]
    @State var isLoading: Set<Int> = []
    @State var dragOffset: CGFloat = 0
    @State var verticalDrag: CGFloat = 0
    @State var isDragging = false
    @State var isPageAnimating = false
    @State var pageWidth: CGFloat = 0
    @State var pageHeight: CGFloat = 0
    @State var textSafeAreaTop: CGFloat = 0
    @State var textSafeAreaBottom: CGFloat = 0
    @State var isZoomed = false
    @State var currentScale: CGFloat = 1.0
    @State var lastScale: CGFloat = 1.0
    @State var panOffset: CGSize = .zero
    @State var lastPanOffset: CGSize = .zero
    @State var loadTasks: [Int: Task<Void, Never>] = [:]
    @State var imageAspectRatios: [Int: CGFloat] = [:]
    @State var textDocuments: [Int: Data] = [:]
    @State var textDocumentHeights: [Int: CGFloat] = [:]
    @State var textLoadTasks: [Int: Task<Void, Never>] = [:]
    @State var textPageEnteringAtEnd: Set<Int> = []
    @State var textPageEntryRevision: [Int: Int] = [:]
    @State var verticalScrollRequest: ReaderVerticalScrollRequest?
    @State var isProgrammaticVerticalScroll = false
    @State var showReaderSettings = false
    @State var showAutoReadSettings = false
    @State var showTableOfContents = false
    @State var autoReadTask: Task<Void, Never>?
    @State var autoReadProgressStartDate: Date?
    @State var autoReadProgressDuration: TimeInterval = 0
    @State var autoReadFinishedMediaIndex: Int?
    @State var autoReadPausedPageIndex: Int?
    @State var thumbnailImages: [Int: UIImage] = [:]
    @State var thumbnailFailedPages: Set<Int> = []
    @State var thumbnailLoadTasks: [Int: Task<Void, Never>] = [:]
    @State var currentPageFileType: ReaderPageFileType = .unknown
    @State var bottomControlFocus: ReaderBottomControlFocus = .bookProgress
    @State var audioCover: UIImage?
    @State var audioCovers: [Int: UIImage] = [:]
    @State var audioPlayer: AVAudioPlayer?
    @State var isAudioPlaying = false
    @State var audioDuration: TimeInterval = 0
    @State var audioCurrentTime: TimeInterval = 0
    @State var audioTimer: Timer?
    @State var audioTitle: String?
    @State var audioArtist: String?
    @State var audioAlbum: String?
    @State var videoPlayer: AVPlayer?
    @State var videoPlayerIndex: Int?
    @State var videoCurrentTime: Double = 0
    @State var videoDuration: Double = 0
    @State var isVideoPlaying = false
    @State var isVideoLoading = false
    @State var videoAspectRatio: CGFloat = 16 / 9
    @State var videoTimeObserver: Any?
    @State var videoEndObserver: NSObjectProtocol?
    @State var videoLoadTask: Task<Void, Never>?
    @State var videoCacheTask: Task<Void, Never>?
    var mediaToolbarIcon: String? {
        switch currentPageFileType {
        case .audio:
            return "music.note"
        case .video:
            return "video"
        default:
            return nil
        }
    }
    @State var progressValue: Double
    @AppStorage("reader_double_tap_zoom") var doubleTapZoom = true
    @AppStorage("reader_tap_gesture_mode") var tapGestureModeRaw = ReaderTapGestureMode.leftRight.rawValue
    @AppStorage("reader_volume_button_mode") var volumeButtonModeRaw = ReaderVolumeButtonMode.off.rawValue
    @State var autoReadEnabled = false
    @AppStorage("reader_auto_read_interval") var autoReadInterval = 5
    @AppStorage("reader_auto_read_images_only") var autoReadImagesOnly = false
    @AppStorage("reader_audio_autoplay") var audioAutoplay = false
    @AppStorage("reader_video_autoplay") var videoAutoplay = false
    @AppStorage("reader_reading_direction") var readingDirectionRaw = ReaderReadingDirection.leftToRight.rawValue
    @AppStorage("reader_preload_page_count") var preloadPageCount = 2
    @AppStorage("reader_double_page") var doublePageEnabled = false
    @AppStorage("reader_first_page_single") var firstPageAlwaysSingle = false
    @AppStorage("reader_vertical_add_margin") var verticalAddMargin = false
    @AppStorage("reader_vertical_margin") var verticalMargin = 16
    @AppStorage("reader_text_font_size") var textFontSize = 18
    @AppStorage("reader_text_line_spacing") var textLineSpacing = 6
    @AppStorage("reader_text_paragraph_spacing") var textParagraphSpacing = 12
    @AppStorage("reader_text_page_margin") var textPageMargin = 20
    @State var horizontalPageUnits: [[Int]]
    @State var horizontalUnitIndexByPage: [Int: Int]

    var readingDirection: ReaderReadingDirection {
        ReaderReadingDirection(rawValue: readingDirectionRaw) ?? .leftToRight
    }

    var tapGestureMode: ReaderTapGestureMode {
        ReaderTapGestureMode(rawValue: tapGestureModeRaw) ?? .leftRight
    }

    var volumeButtonMode: ReaderVolumeButtonMode {
        ReaderVolumeButtonMode(rawValue: volumeButtonModeRaw) ?? .off
    }

    var maxIndex: Int { max(0, files.count - 1) }

    var currentFileIsImage: Bool {
        fileType(at: currentIndex) == .image
    }

    var usesVerticalPageControls: Bool {
        readingDirection == .verticalPaged || readingDirection == .vertical
    }

    var hasPreviousPage: Bool {
        readingDirection == .vertical
            ? currentIndex > 0
            : adjacentHorizontalTarget(from: currentIndex, offset: -1) != nil
    }

    var hasNextPage: Bool {
        readingDirection == .vertical
            ? currentIndex < maxIndex
            : adjacentHorizontalTarget(from: currentIndex, offset: 1) != nil
    }

    var autoReadRefreshState: ReaderAutoReadRefreshState {
        ReaderAutoReadRefreshState(
            enabled: autoReadEnabled,
            interval: autoReadInterval,
            imagesOnly: autoReadImagesOnly,
            controlsVisible: showControls,
            readerSettingsVisible: showReaderSettings,
            autoReadSettingsVisible: showAutoReadSettings,
            tableOfContentsVisible: showTableOfContents,
            appIsActive: scenePhase == .active
        )
    }

    func makeHorizontalPageUnits() -> [[Int]] {
        guard doublePageEnabled else { return files.indices.map { [$0] } }
        var units: [[Int]] = []
        var index = 0
        if firstPageAlwaysSingle, !files.isEmpty {
            units.append([0])
            index = 1
        }

        while index < files.count {
            let nextIndex = index + 1
            if nextIndex < files.count,
               pageFileTypes[index] == .image,
               pageFileTypes[nextIndex] == .image {
                units.append([index, nextIndex])
                index += 2
            } else {
                units.append([index])
                index += 1
            }
        }
        return units
    }

    func rebuildHorizontalPaginationCache() {
        let units = makeHorizontalPageUnits()
        var unitIndexByPage: [Int: Int] = [:]
        unitIndexByPage.reserveCapacity(files.count)
        for (unitIndex, pages) in units.enumerated() {
            for pageIndex in pages {
                unitIndexByPage[pageIndex] = unitIndex
            }
        }
        horizontalPageUnits = units
        horizontalUnitIndexByPage = unitIndexByPage
    }

    func horizontalUnit(containing index: Int) -> [Int] {
        guard let unitIndex = horizontalUnitIndexByPage[index],
              horizontalPageUnits.indices.contains(unitIndex) else { return [index] }
        return horizontalPageUnits[unitIndex]
    }

    func horizontalUnitIndex(containing index: Int) -> Int? {
        horizontalUnitIndexByPage[index]
    }

    func adjacentHorizontalTarget(from index: Int, offset: Int) -> Int? {
        guard let unitIndex = horizontalUnitIndex(containing: index) else { return nil }
        let targetUnitIndex = unitIndex + offset
        guard horizontalPageUnits.indices.contains(targetUnitIndex) else { return nil }
        return horizontalPageUnits[targetUnitIndex].first
    }

    func isInCurrentHorizontalUnit(_ index: Int) -> Bool {
        horizontalUnit(containing: currentIndex).contains(index)
    }

    func horizontalPreloadImageIndices(after unitIndex: Int) -> [Int] {
        let units = horizontalPageUnits
        guard units.indices.contains(unitIndex) else { return [] }

        let preloadLimit = min(max(preloadPageCount, 1), 5)
        var result: [Int] = []
        for nextUnitIndex in units.indices where nextUnitIndex > unitIndex {
            for pageIndex in units[nextUnitIndex] where fileType(at: pageIndex) == .image {
                result.append(pageIndex)
                if result.count == preloadLimit {
                    return result
                }
            }
        }
        return result
    }

    init(arcid: String, files: [APIClient.PageFile], startIndex: Int, server: Server) {
        let fileTypes = files.map { file in
            Self.detectFileType(
                file.defaultSource?.path ?? file.path ?? ""
            )
        }
        let initialUnits = files.indices.map { [$0] }
        self.arcid = arcid
        self.files = files
        self.startIndex = startIndex
        self.server = server
        self.pageFileTypes = fileTypes
        _currentIndex = State(initialValue: startIndex)
        _progressValue = State(initialValue: Double(startIndex))
        _horizontalPageUnits = State(initialValue: initialUnits)
        _horizontalUnitIndexByPage = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: files.indices.map { ($0, $0) }
            )
        )
    }

    private var readerPresentation: some View {
        GeometryReader { geo in
            readerCanvas(size: geo.size)
                .onAppear {
                    pageWidth = geo.size.width
                    pageHeight = geo.size.height
                    textSafeAreaTop = geo.safeAreaInsets.top
                    textSafeAreaBottom = geo.safeAreaInsets.bottom
                }
                .onChange(of: geo.size) { _, newValue in
                    pageWidth = newValue.width
                    pageHeight = newValue.height
                }
                .onChange(of: geo.safeAreaInsets) { _, newValue in
                    textSafeAreaTop = newValue.top
                    textSafeAreaBottom = newValue.bottom
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
                Text("\(currentIndex + 1) / \(files.count)")
                    .font(.subheadline)
                    .padding(8)
                    .glassEffect(.regular, in: Capsule())
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
                            Button { previousFile() } label: {
                                Image(
                                    systemName: usesVerticalPageControls
                                    ? "chevron.up"
                                    : "chevron.left"
                                )
                            }
                            .disabled(!hasPreviousPage)
                            .opacity(hasPreviousPage ? 1 : 0.5)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            Button { nextFile() } label: {
                                Image(
                                    systemName: usesVerticalPageControls
                                    ? "chevron.down"
                                    : "chevron.right"
                                )
                            }
                            .disabled(!hasNextPage)
                            .opacity(hasNextPage ? 1 : 0.5)
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
                                            currentIndex = horizontalUnit(containing: newIndex).first ?? newIndex
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
            readerBottomSafeAreaContent
        }
        .statusBarHidden(!showControls)
        .background {
            if volumeButtonMode != .off,
               scenePhase == .active,
               !showReaderSettings,
               !showTableOfContents {
                ReaderVolumeButtonControl(
                    mode: volumeButtonMode,
                    onVolumeUp: handleVolumeUpButton,
                    onVolumeDown: handleVolumeDownButton
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsView(
                doubleTapZoom: $doubleTapZoom,
                tapGestureMode: $tapGestureModeRaw,
                volumeButtonMode: $volumeButtonModeRaw,
                autoReadEnabled: $autoReadEnabled,
                autoReadInterval: $autoReadInterval,
                autoReadImagesOnly: $autoReadImagesOnly,
                audioAutoplay: $audioAutoplay,
                videoAutoplay: $videoAutoplay,
                readingDirection: $readingDirectionRaw,
                preloadPageCount: $preloadPageCount,
                doublePageEnabled: $doublePageEnabled,
                firstPageAlwaysSingle: $firstPageAlwaysSingle,
                verticalAddMargin: $verticalAddMargin,
                verticalMargin: $verticalMargin,
                textFontSize: $textFontSize,
                textLineSpacing: $textLineSpacing,
                textParagraphSpacing: $textParagraphSpacing,
                textPageMargin: $textPageMargin
            )
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAutoReadSettings) {
            ReaderAutoReadSettingsSheet(
                autoReadEnabled: $autoReadEnabled,
                autoReadInterval: $autoReadInterval,
                autoReadImagesOnly: $autoReadImagesOnly
            )
            .presentationDetents([.height(280)])
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
    }

    private var readerLifecyclePresentation: some View {
        readerPresentation
        .onAppear(perform: handleReaderAppear)
        .onDisappear(perform: handleReaderDisappear)
        .onChange(of: currentIndex) { oldIndex, newIndex in
            handleCurrentIndexChange(from: oldIndex, to: newIndex)
        }
        .onChange(of: readingDirectionRaw) { _, _ in
            handleReadingDirectionChange()
        }
        .onChange(of: preloadPageCount) { _, _ in
            handlePreloadPageCountChange()
        }
        .onChange(of: doublePageEnabled) { _, _ in
            handleDoublePageSettingChange()
        }
        .onChange(of: firstPageAlwaysSingle) { _, _ in
            handleFirstPageSettingChange()
        }
    }

    var body: some View {
        readerLifecyclePresentation
        .onChange(of: autoReadRefreshState) { oldState, newState in
            handleAutoReadRefreshChange(from: oldState, to: newState)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            handleReaderMemoryWarning()
        }
    }

    // MARK: - Reader Canvas

    @ViewBuilder
    func readerCanvas(size: CGSize) -> some View {
        switch readingDirection {
        case .vertical:
            verticalReaderCanvas(size: size)
        default:
            ZStack {
                pageStrip(size: size)
                if fileType(at: currentIndex) != .html {
                    interactionOverlay(pageSize: size)
                }
            }
        }
    }

    @ViewBuilder
    func verticalReaderCanvas(size: CGSize) -> some View {
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
                        withAnimation(
                            request.duration.map(Animation.linear(duration:))
                                ?? .easeInOut(duration: 0.3)
                        ) {
                            scrollProxy.scrollTo(request.index, anchor: .top)
                        }
                    } else {
                        withoutAnimation {
                            scrollProxy.scrollTo(request.index, anchor: .top)
                        }
                    }

                    DispatchQueue.main.asyncAfter(
                        deadline: .now()
                            + (request.animated ? (request.duration ?? 0.3) + 0.04 : 0.05)
                    ) {
                        isProgrammaticVerticalScroll = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    func verticalPageView(
        for index: Int,
        width: CGFloat,
        viewportHeight: CGFloat
    ) -> some View {
        let path = filePath(at: index)
        let pageFileType = fileType(at: index)
        let isImage = pageFileType == .image
        let horizontalMargin = isImage && verticalAddMargin
            ? CGFloat(verticalMargin)
            : 0
        let contentWidth = max(width - horizontalMargin * 2, 1)
        let height = verticalPageHeight(
            index: index,
            width: contentWidth,
            viewportHeight: viewportHeight
        )

        if isImage {
            if let image = images[index] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: contentWidth, height: height)
                    .frame(width: width, height: height)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("\(index + 1) / \(files.count)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .frame(width: contentWidth, height: height)
                .frame(width: width, height: height)
                .task(id: path) {
                    loadPage(index)
                }
            }
        } else if pageFileType == .html {
            textPageView(
                for: index,
                size: CGSize(width: width, height: height),
                paged: false
            )
            .frame(width: width, height: height)
        } else {
            pageView(
                for: index,
                size: CGSize(width: width, height: height)
            )
            .frame(width: width, height: height)
        }
    }

    func verticalPageHeight(
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

        if fileType(at: index) == .html {
            return max(textDocumentHeights[index] ?? viewportHeight, 1)
        }

        return viewportHeight
    }

    func updateVerticalCurrentPage(
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

    @ViewBuilder
    func pageStrip(size: CGSize) -> some View {
        let currentUnit = horizontalUnit(containing: currentIndex)
        let previousTarget = adjacentHorizontalTarget(from: currentIndex, offset: -1)
        let nextTarget = adjacentHorizontalTarget(from: currentIndex, offset: 1)

        if readingDirection == .verticalPaged {
            VStack(spacing: 0) {
                horizontalUnitView(target: previousTarget, size: size)

                horizontalUnitView(indices: currentUnit, size: size)
                    .frame(width: size.width, height: size.height)

                horizontalUnitView(target: nextTarget, size: size)
            }
            .offset(y: -size.height + dragOffset)
        } else {
            HStack(spacing: 0) {
                if readingDirection == .rightToLeft {
                    horizontalUnitView(target: nextTarget, size: size)
                } else {
                    horizontalUnitView(target: previousTarget, size: size)
                }

                horizontalUnitView(indices: currentUnit, size: size)
                    .frame(width: size.width, height: size.height)

                if readingDirection == .rightToLeft {
                    horizontalUnitView(target: previousTarget, size: size)
                } else {
                    horizontalUnitView(target: nextTarget, size: size)
                }
            }
            .offset(x: -size.width + dragOffset)
        }
    }

    @ViewBuilder
    func horizontalUnitView(target: Int?, size: CGSize) -> some View {
        if let target {
            horizontalUnitView(indices: horizontalUnit(containing: target), size: size)
        } else {
            Color.black
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    func horizontalUnitView(indices: [Int], size: CGSize) -> some View {
        if indices.count == 2,
           fileType(at: indices[0]) == .image,
           fileType(at: indices[1]) == .image {
            let displayedIndices = readingDirection == .rightToLeft
                ? Array(indices.reversed())
                : indices
            HStack(spacing: 0) {
                ForEach(Array(displayedIndices.enumerated()), id: \.element) { position, index in
                    pageView(
                        for: index,
                        size: CGSize(width: size.width / 2, height: size.height),
                        imageAlignment: position == 0 ? .trailing : .leading
                    )
                        .frame(width: size.width / 2, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
        } else if let index = indices.first {
            pageView(for: index, size: size)
                .frame(width: size.width, height: size.height)
        } else {
            Color.black
                .frame(width: size.width, height: size.height)
        }
    }

    func interactionOverlay(pageSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .highPriorityGesture(doubleTapGesture)
            .onTapGesture { location in
                handleSingleTap(at: location, pageSize: pageSize)
            }
            .gesture(pageDragGesture(pageSize: pageSize))
            .simultaneousGesture(zoomGesture)
    }

    var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                handleDoubleTap()
            }
    }

    func pageDragGesture(pageSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value, pageSize: pageSize)
            }
    }

    var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                handleMagnificationChanged(value)
            }
            .onEnded { value in
                handleMagnificationEnded(value)
            }
    }

    func handleDoubleTap() {
        guard !autoReadEnabled else { return }
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

    func handleSingleTap(at location: CGPoint, pageSize: CGSize) {
        let horizontal = location.x / max(pageSize.width, 1)
        let vertical = location.y / max(pageSize.height, 1)

        switch tapGestureMode {
        case .leftRight:
            if horizontal < 1 / 3 {
                previousPage()
            } else if horizontal > 2 / 3 {
                nextPage()
            } else {
                toggleReaderControls()
            }
        case .lShape:
            if vertical < 1 / 3 {
                previousPage()
            } else if vertical > 2 / 3 {
                nextPage()
            } else if horizontal < 1 / 3 {
                previousPage()
            } else if horizontal > 2 / 3 {
                nextPage()
            } else {
                toggleReaderControls()
            }
        case .kindle:
            if vertical < 1 / 3 {
                toggleReaderControls()
            } else if horizontal < 1 / 3 {
                previousPage()
            } else {
                nextPage()
            }
        case .edges:
            if horizontal < 1 / 3 || horizontal > 2 / 3 {
                nextPage()
            } else if vertical > 2 / 3 {
                previousPage()
            } else {
                toggleReaderControls()
            }
        case .disabled:
            toggleReaderControls()
        }
    }

    func toggleReaderControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
    }

    func refreshHorizontalPagination() {
        guard readingDirection != .vertical else { return }
        let normalizedIndex = horizontalUnit(containing: currentIndex).first ?? currentIndex
        withoutAnimation {
            currentIndex = normalizedIndex
            progressValue = Double(normalizedIndex)
            dragOffset = 0
        }
        preloadAdjacent()
        trimPageCache(around: normalizedIndex)
    }

    func handleDragChanged(_ value: DragGesture.Value) {
        guard !isPageAnimating else { return }
        if autoReadEnabled {
            stopAutoReadTask()
        }

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
            let translation = readingDirection == .verticalPaged
                ? value.translation.height
                : value.translation.width
            let needsDamping: Bool

            if readingDirection == .verticalPaged {
                needsDamping =
                    (adjacentHorizontalTarget(from: currentIndex, offset: -1) == nil && translation > 0) ||
                    (adjacentHorizontalTarget(from: currentIndex, offset: 1) == nil && translation < 0)
            } else if readingDirection == .rightToLeft {
                // 右滑进入更高页码；左滑进入更低页码。
                needsDamping =
                    (adjacentHorizontalTarget(from: currentIndex, offset: 1) == nil && translation > 0) ||
                    (adjacentHorizontalTarget(from: currentIndex, offset: -1) == nil && translation < 0)
            } else {
                needsDamping =
                    (adjacentHorizontalTarget(from: currentIndex, offset: -1) == nil && translation > 0) ||
                    (adjacentHorizontalTarget(from: currentIndex, offset: 1) == nil && translation < 0)
            }

            withoutAnimation {
                dragOffset = needsDamping ? translation * 0.2 : translation
            }
        }
    }

    func handleDragEnded(_ value: DragGesture.Value, pageSize: CGSize) {
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
            finishPageDrag(
                value,
                pageWidth: readingDirection == .verticalPaged
                    ? pageSize.height
                    : pageSize.width
            )
        }
    }

    func handleMagnificationChanged(_ value: CGFloat) {
        guard !autoReadEnabled else { return }
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

    func handleMagnificationEnded(_ value: CGFloat) {
        guard !autoReadEnabled else { return }
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

    func filePath(at index: Int) -> String {
        guard index >= 0, index < files.count else { return "" }
        return files[index].defaultSource?.path ?? files[index].path ?? ""
    }

    func isImageFile(_ path: String) -> Bool {
        Self.detectFileType(path) == .image
    }

    static func detectFileType(_ path: String) -> ReaderPageFileType {
        let clean = path.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? path
        let ext = (clean as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .unknown }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return .image
        }
        let fallback: Set<String> = ["jpg","jpeg","png","gif","webp","heic","heif","bmp","tif","tiff","avif"]
        if fallback.contains(ext) { return .image }

        let video: Set<String> = ["mp4","mov","avi","mkv","webm","wmv","m4v","3gp"]
        if video.contains(ext) { return .video }
        let audio: Set<String> = ["mp3","wav","flac","aac","ogg","wma","m4a","aiff"]
        if audio.contains(ext) { return .audio }
        if ext == "html" || ext == "htm" || ext == "xhtml" { return .html }
        return .unknown
    }

    func fileType(at index: Int) -> ReaderPageFileType {
        guard pageFileTypes.indices.contains(index) else { return .unknown }
        return pageFileTypes[index]
    }

    func iconForFile(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        let video: Set<String> = ["mp4","mov","avi","mkv","webm","wmv","m4v","3gp"]
        if video.contains(ext) { return "video.fill" }
        let audio: Set<String> = ["mp3","wav","flac","aac","ogg","wma","m4a","aiff"]
        if audio.contains(ext) { return "music.note" }
        let archive: Set<String> = ["zip","rar","7z","tar","gz","bz2","xz","cbz","cbr"]
        if archive.contains(ext) { return "archivebox.fill" }
        let doc: Set<String> = ["pdf","doc","docx","pages","rtf"]
        if doc.contains(ext) { return "doc.richtext.fill" }
        let text: Set<String> = ["txt","md","json","xml","yaml","yml","html","htm","xhtml"]
        if text.contains(ext) { return "doc.text.fill" }
        let ebook: Set<String> = ["epub","mobi","azw","azw3"]
        if ebook.contains(ext) { return "book.closed.fill" }
        return "doc.fill"
    }

    // MARK: - Table of Contents

    func hasThumbnailSource(at index: Int) -> Bool {
        guard index >= 0, index < files.count else { return false }
        let file = files[index]
        let thumbnailAssetId =
            file.defaultSource?.metadata?.thumbAssetId
            ?? file.metadata?.thumbAssetId
            ?? 0

        return thumbnailAssetId > 0 || fileType(at: index) == .image
    }

    func selectPageFromTableOfContents(_ index: Int) {
        guard index >= 0, index < files.count else { return }
        textPageEnteringAtEnd.remove(index)

        if readingDirection == .vertical {
            requestVerticalPage(index, animated: false)
            return
        }

        let normalizedIndex = horizontalUnit(containing: index).first ?? index
        guard normalizedIndex != currentIndex else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            progressValue = Double(normalizedIndex)
        }

        withoutAnimation {
            dragOffset = 0
            isDragging = false
            isPageAnimating = false
            currentIndex = normalizedIndex
        }
    }

    func loadThumbnail(_ index: Int, maxDimensionPoints: CGFloat) {
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

        guard thumbnailAssetId > 0 || fileType(at: index) == .image else { return }

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
                    trimThumbnailCache(around: index)
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

    func downsampleImage(
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

    func trimThumbnailCache(around index: Int) {
        let keepRange = max(0, index - 24)...min(maxIndex, index + 24)
        for pageIndex in thumbnailImages.keys where !keepRange.contains(pageIndex) {
            thumbnailImages.removeValue(forKey: pageIndex)
        }
    }

    // MARK: - Page View

    @ViewBuilder
    func pageView(
        for index: Int,
        size: CGSize,
        imageAlignment: Alignment = .center
    ) -> some View {
        let path = filePath(at: index)
        let pageFileType = fileType(at: index)

        if pageFileType == .audio {
            audioPageView(for: index, size: size)
        } else if pageFileType == .video {
            videoPageView(for: index, size: size)
        } else if pageFileType == .html {
            textPageView(for: index, size: size, paged: true)
        } else if pageFileType != .image {
            filePlaceholder(path: path, size: size)
        } else if let image = images[index] {
            ReaderPageView(
                image: image,
                scale: index == currentIndex ? currentScale : 1.0,
                panOffset: index == currentIndex ? panOffset : .zero,
                alignment: imageAlignment
            )
            .frame(width: size.width, height: size.height)
        } else {
            loadingPageView(index: index, size: size)
                .task(id: path) { loadPage(index) }
        }
    }

    @ViewBuilder
    func videoPageView(for index: Int, size: CGSize) -> some View {
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
                    prepareVideo(
                        at: index,
                        autoplay: videoAutoplay || shouldAutoPlayCurrentMedia
                    )
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    func loadingPageView(index: Int, size: CGSize) -> some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.5)
            Text("\(index + 1) / \(files.count)")
                .font(.caption)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    func filePlaceholder(path: String, size: CGSize) -> some View {
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
    func updateBottomToolbar(for index: Int) {
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

    func withoutAnimation(_ action: () -> Void) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { action() }
    }

    func clampedPanOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        guard let image = images[currentIndex],
              image.size.width > 0, image.size.height > 0 else { return .zero }
        let fitScale = min(UIScreen.main.bounds.width / image.size.width, UIScreen.main.bounds.height / image.size.height)
        let fw = image.size.width * fitScale * scale
        let fh = image.size.height * fitScale * scale
        let mx = max(0, (fw - UIScreen.main.bounds.width) / 2)
        let my = max(0, (fh - UIScreen.main.bounds.height) / 2)
        return CGSize(width: min(max(proposed.width, -mx), mx), height: min(max(proposed.height, -my), my))
    }

    func animatePageChange(to targetIndex: Int, pageWidth w: CGFloat) {
        guard w > 0,
              targetIndex >= 0,
              targetIndex <= maxIndex,
              targetIndex != currentIndex,
              !isPageAnimating else { return }

        let movesToHigherIndex = targetIndex > currentIndex
        let targetOffset: CGFloat

        if readingDirection == .verticalPaged {
            targetOffset = movesToHigherIndex ? -w : w
        } else if readingDirection == .rightToLeft {
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

    func finishPageDrag(_ value: DragGesture.Value, pageWidth w: CGFloat) {
        let isVertical = readingDirection == .verticalPaged
        let translation = isVertical
            ? value.translation.height
            : value.translation.width
        let predictedTranslation = isVertical
            ? value.predictedEndLocation.y - value.location.y
            : value.predictedEndLocation.x - value.location.x
        let swipedPositive =
            translation > w * 0.25 || predictedTranslation > 100
        let swipedNegative =
            translation < -w * 0.25 || predictedTranslation < -100

        let positiveSwipeTarget = readingDirection == .rightToLeft
            ? adjacentHorizontalTarget(from: currentIndex, offset: 1)
            : adjacentHorizontalTarget(from: currentIndex, offset: -1)
        let negativeSwipeTarget = readingDirection == .rightToLeft
            ? adjacentHorizontalTarget(from: currentIndex, offset: -1)
            : adjacentHorizontalTarget(from: currentIndex, offset: 1)

        if swipedPositive, let positiveSwipeTarget {
            animatePageChange(to: positiveSwipeTarget, pageWidth: w)
        } else if swipedNegative, let negativeSwipeTarget {
            animatePageChange(to: negativeSwipeTarget, pageWidth: w)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                dragOffset = 0
            }
            isDragging = false
            refreshAutoRead()
        }
    }

    func resetZoom(animated: Bool = true) {
        let action = {
            currentScale = 1.0; lastScale = 1.0
            panOffset = .zero; lastPanOffset = .zero; isZoomed = false
        }
        if animated { withAnimation(.smooth(duration: 0.25)) { action() } }
        else { withoutAnimation { action() } }
    }
}
