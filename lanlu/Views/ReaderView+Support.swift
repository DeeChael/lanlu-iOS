import SwiftUI

private enum ReaderImageLoadError: LocalizedError {
    case decodeFailed

    var errorDescription: String? {
        "Image decode failed"
    }
}

struct ReaderTableOfContentsOverlay: View {
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
                    .ignoresSafeArea(.container, edges: [.vertical, .horizontal])
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
    let alignment: Alignment

    var body: some View {
        GeometryReader { proxy in
            let imageAspectRatio = image.size.width / max(image.size.height, 1)
            let containerAspectRatio = proxy.size.width / max(proxy.size.height, 1)
            let fittedSize = imageAspectRatio > containerAspectRatio
                ? CGSize(
                    width: proxy.size.width,
                    height: proxy.size.width / imageAspectRatio
                )
                : CGSize(
                    width: proxy.size.height * imageAspectRatio,
                    height: proxy.size.height
                )

            Image(uiImage: image)
                .resizable()
                .frame(width: fittedSize.width, height: fittedSize.height)
                .scaleEffect(scale)
                .offset(panOffset)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: alignment
                )
                .clipped()
        }
    }
}

struct ReaderSettingsView: View {
    @Binding var doubleTapZoom: Bool
    @Binding var tapGestureMode: String
    @Binding var volumeButtonMode: String
    @Binding var audioAutoplay: Bool
    @Binding var videoAutoplay: Bool
    @Binding var readingDirection: String
    @Binding var preloadPageCount: Int
    @Binding var doublePageEnabled: Bool
    @Binding var firstPageAlwaysSingle: Bool
    @Binding var verticalAddMargin: Bool
    @Binding var verticalMargin: Int
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
                    NavigationLink {
                        ReaderTapGestureSettingsView(selection: $tapGestureMode)
                    } label: {
                        HStack {
                            Text(String(localized: "reader_tap_gesture"))
                            Spacer()
                            Text(
                                ReaderTapGestureMode(rawValue: tapGestureMode)?.title
                                    ?? ReaderTapGestureMode.leftRight.title
                            )
                            .foregroundStyle(.secondary)
                        }
                    }

                    Picker(
                        String(localized: "reader_volume_button_page_turn"),
                        selection: $volumeButtonMode
                    ) {
                        ForEach(ReaderVolumeButtonMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                }
                Section(String(localized: "reader_settings_pagination")) {
                    Stepper(value: $preloadPageCount, in: 1...5) {
                        HStack {
                            Text(String(localized: "reader_preload_pages"))
                            Spacer()
                            Text("\(preloadPageCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Toggle(String(localized: "reader_double_page"), isOn: $doublePageEnabled)
                    Toggle(
                        String(localized: "reader_first_page_single"),
                        isOn: $firstPageAlwaysSingle
                    )
                    .disabled(!doublePageEnabled)
                }
                Section(String(localized: "reader_settings_vertical_comic")) {
                    Toggle(
                        String(localized: "reader_vertical_add_margin"),
                        isOn: $verticalAddMargin
                    )
                    Stepper(value: $verticalMargin, in: 4...128, step: 4) {
                        HStack {
                            Text(String(localized: "reader_vertical_margin"))
                            Spacer()
                            Text("\(verticalMargin)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(verticalAddMargin ? .primary : .secondary)
                    .disabled(!verticalAddMargin)
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

private struct ReaderTapGestureSettingsView: View {
    @Binding var selection: String

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ReaderTapGestureMode.allCases) { mode in
                    Button {
                        selection = mode.rawValue
                    } label: {
                        ReaderTapGestureCard(
                            mode: mode,
                            isSelected: selection == mode.rawValue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle(String(localized: "reader_tap_gesture"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReaderTapGestureCard: View {
    let mode: ReaderTapGestureMode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(uiColor: .systemBackground))

                ReaderTapGestureDiagram(mode: mode)
                    .padding(12)
            }
            .aspectRatio(0.72, contentMode: .fit)

            Text(mode.title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.08)
                : Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected ? Color.accentColor : Color(uiColor: .separator),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
                .padding(8)
        }
    }
}

private struct ReaderTapGestureDiagram: View {
    let mode: ReaderTapGestureMode

    private let previousColor = Color.blue.opacity(0.38)
    private let nextColor = Color.green.opacity(0.38)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .topLeading) {
                Color.clear
                switch mode {
                case .leftRight:
                    region(x: 0, y: 0, width: width / 3, height: height, color: previousColor)
                    region(x: width * 2 / 3, y: 0, width: width / 3, height: height, color: nextColor)
                case .lShape:
                    region(x: 0, y: 0, width: width, height: height / 3, color: previousColor)
                    region(x: 0, y: height * 2 / 3, width: width, height: height / 3, color: nextColor)
                    region(x: 0, y: height / 3, width: width / 3, height: height / 3, color: previousColor)
                    region(x: width * 2 / 3, y: height / 3, width: width / 3, height: height / 3, color: nextColor)
                case .kindle:
                    region(x: 0, y: height / 3, width: width / 3, height: height * 2 / 3, color: previousColor)
                    region(x: width / 3, y: height / 3, width: width * 2 / 3, height: height * 2 / 3, color: nextColor)
                case .edges:
                    region(x: 0, y: 0, width: width / 3, height: height, color: nextColor)
                    region(x: width * 2 / 3, y: 0, width: width / 3, height: height, color: nextColor)
                    region(x: width / 3, y: height * 2 / 3, width: width / 3, height: height / 3, color: previousColor)
                case .disabled:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
            }
        }
    }

    private func region(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: Color
    ) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }
}

extension ReaderView {
    /// 禁用 fullScreenCover 自带的底部呈现动画，只保留目录面板内部的左侧滑入动画。
    func presentTableOfContents() {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            showTableOfContents = true
        }
    }

    /// 面板自身完成左滑退出后，立即移除透明的 fullScreenCover 容器。
    func dismissTableOfContents() {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            showTableOfContents = false
        }
    }

    func handleVolumeUpButton() {
        switch volumeButtonMode {
        case .off:
            break
        case .volumeUpNext:
            nextPage()
        case .volumeDownNext:
            previousPage()
        }
    }

    func handleVolumeDownButton() {
        switch volumeButtonMode {
        case .off:
            break
        case .volumeUpNext:
            previousPage()
        case .volumeDownNext:
            nextPage()
        }
    }

    func previousPage() {
        if readingDirection == .vertical {
            let targetIndex = currentIndex - 1
            guard targetIndex >= 0 else { return }
            requestVerticalPage(targetIndex, animated: true)
        } else if let targetIndex = adjacentHorizontalTarget(from: currentIndex, offset: -1) {
            animatePageChange(
                to: targetIndex,
                pageWidth: readingDirection == .verticalPaged ? pageHeight : pageWidth
            )
        }
    }

    func nextPage() {
        if readingDirection == .vertical {
            let targetIndex = currentIndex + 1
            guard targetIndex <= maxIndex else { return }
            requestVerticalPage(targetIndex, animated: true)
        } else if let targetIndex = adjacentHorizontalTarget(from: currentIndex, offset: 1) {
            animatePageChange(
                to: targetIndex,
                pageWidth: readingDirection == .verticalPaged ? pageHeight : pageWidth
            )
        }
    }

    func requestVerticalPage(
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

    func loadPage(_ index: Int) {
        guard index >= 0, index < files.count else { return }
        guard images[index] == nil else { return }
        guard !isLoading.contains(index) else { return }

        let path = filePath(at: index)
        guard !path.isEmpty else { return }
        guard fileType(at: index) == .image else { return }

        isLoading.insert(index)
        loadTasks[index]?.cancel()

        loadTasks[index] = Task {
            let cacheKey = "page_\(arcid)_\(path)"

            var attempt = 0
            while !Task.isCancelled {
                attempt += 1
                do {
                    let data: Data
                    let loadedFromCache: Bool
                    if attempt == 1,
                       let cached = CacheManager.shared.getCover(id: cacheKey) {
                        data = cached
                        loadedFromCache = true
                    } else {
                        data = try await server.apiClient.fetchPageImage(arcid: arcid, path: path)
                        loadedFromCache = false
                    }

                    guard !Task.isCancelled else { break }
                    guard let image = readerImage(from: data) else {
                        throw ReaderImageLoadError.decodeFailed
                    }

                    if !loadedFromCache {
                        CacheManager.shared.cacheCover(id: cacheKey, data: data)
                    }
                    await MainActor.run {
                        images[index] = image
                        if image.size.width > 0, image.size.height > 0 {
                            imageAspectRatios[index] = image.size.height / image.size.width
                        }
                        isLoading.remove(index)
                        loadTasks[index] = nil
                    }
                    return
                } catch {
                    guard !Task.isCancelled else { break }
                    let shouldRetry = await MainActor.run {
                        readingDirection == .vertical
                            ? currentIndex == index
                            : isInCurrentHorizontalUnit(index)
                    }
                    if !shouldRetry {
                        break
                    }
                    LogManager.shared.log(
                        "[Reader] Current image retry index=\(index) attempt=\(attempt): \(error.localizedDescription)"
                    )
                    try? await Task.sleep(for: .milliseconds(800))
                }
            }

            await MainActor.run {
                isLoading.remove(index)
                loadTasks[index] = nil
            }
        }
    }

    func preloadAdjacent() {
        guard readingDirection != .vertical,
              let currentUnitIndex = horizontalUnitIndex(containing: currentIndex) else { return }

        let units = horizontalPageUnits
        for pageIndex in units[currentUnitIndex] where fileType(at: pageIndex) == .image {
            loadPage(pageIndex)
        }
        for pageIndex in horizontalPreloadImageIndices(after: currentUnitIndex) {
            loadPage(pageIndex)
        }
    }

    func preloadVerticalPages(around index: Int) {
        guard readingDirection == .vertical,
              !files.isEmpty else { return }

        let preloadRange = max(0, index - 1)...min(maxIndex, index + 2)
        for pageIndex in preloadRange where fileType(at: pageIndex) == .image {
            loadPage(pageIndex)
        }

        trimPageCache(around: index)
    }

    func trimPageCache(around index: Int) {
        let keepIndices: Set<Int>
        if readingDirection == .vertical {
            keepIndices = Set(max(0, index - 2)...min(maxIndex, index + 2))
        } else if let currentUnitIndex = horizontalUnitIndex(containing: index) {
            let units = horizontalPageUnits
            var horizontalKeepIndices = Set(units[currentUnitIndex])
            if currentUnitIndex > 0 {
                horizontalKeepIndices.formUnion(units[currentUnitIndex - 1])
            }
            horizontalKeepIndices.formUnion(
                horizontalPreloadImageIndices(after: currentUnitIndex)
            )
            keepIndices = horizontalKeepIndices
        } else {
            keepIndices = [index]
        }
        let imageIndexesToRemove = images.keys.filter {
            !keepIndices.contains($0)
        }
        for pageIndex in imageIndexesToRemove {
            images.removeValue(forKey: pageIndex)
        }

        let taskIndexesToCancel = loadTasks.keys.filter {
            !keepIndices.contains($0)
        }
        for pageIndex in taskIndexesToCancel {
            // 只发出取消信号，由任务自身统一清理状态，避免快速跳页时
            // 旧任务覆盖同一页的新任务状态。
            loadTasks[pageIndex]?.cancel()
        }
    }

    func readerImage(from data: Data) -> UIImage? {
        let screen = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let longestScreenEdge = max(screen.width, screen.height) * scale
        let maxPixelSize = min(max(longestScreenEdge, 1_536), 2_048)
        return downsampleImage(data: data, maxPixelSize: maxPixelSize)
    }

    func saveProgress() {
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

    func cancelAllTasks() {
        for task in loadTasks.values { task.cancel() }
        loadTasks.removeAll()

        for task in thumbnailLoadTasks.values { task.cancel() }
        thumbnailLoadTasks.removeAll()
    }
}
