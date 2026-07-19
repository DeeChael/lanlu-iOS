import SwiftUI
import AVFoundation
import CryptoKit

extension ReaderView {
    func audioPageView(for index: Int, size: CGSize) -> some View {
        let file = index >= 0 && index < files.count ? files[index] : nil
        let filePath = file?.defaultSource?.path ?? file?.path ?? ""
        let fileName = (filePath as NSString).lastPathComponent
        let cover = audioCovers[index] ?? (index == currentIndex ? audioCover : nil)
        let title = index == currentIndex ? audioTitle : nil
        let artist = index == currentIndex ? audioArtist : nil
        let album = index == currentIndex ? audioAlbum : nil

        let coverView = ZStack(alignment: .center) {
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

        let informationView = VStack(alignment: .leading, spacing: 4) {
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

        return Group {
            if size.width > size.height {
                let coverSize = max(min(size.height - 64, size.width * 0.42), 160)
                HStack(spacing: 32) {
                    coverView
                        .frame(width: coverSize, height: coverSize)

                    informationView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .safeAreaPadding(.horizontal)
                .safeAreaPadding(.vertical)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    coverView
                        .frame(width: size.width - 64, height: size.width - 64)

                    informationView
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: index) {
            await loadAudioCover(at: index)
        }
    }

    func prepareAudio(autoplay: Bool = false) {
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
                if (autoplay || shouldAutoPlayCurrentMedia)
                    && !autoReadPausedOnCurrentPage {
                    startAudio()
                }
            }
        }
    }

    func startAudio() {
        audioPlayer?.play()
        isAudioPlaying = true
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        isAudioPlaying = false
        audioTimer?.invalidate()
        audioTimer = nil
    }

    func prepareVideo(at index: Int, autoplay: Bool) {
        guard index >= 0, index < files.count else { return }
        let path = filePath(at: index)
        guard !path.isEmpty else { return }

        if videoPlayerIndex == index, let videoPlayer {
            if autoplay && !autoReadPausedOnCurrentPage {
                videoPlayer.play()
                isVideoPlaying = true
            }
            return
        }

        stopVideo()
        isVideoLoading = true
        videoPlayerIndex = index
        LogManager.shared.log("[Reader] Video prepare index=\(index) autoplay=\(autoplay)")
        videoLoadTask = Task {
            do {
                let source = try videoSource(path: path)
                LogManager.shared.log("[Reader] Video source index=\(index) cached=\(source.isCached)")
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
                    if autoplay && !autoReadPausedOnCurrentPage {
                        player.play()
                        isVideoPlaying = true
                    }
                }
                LogManager.shared.log("[Reader] Video ready index=\(index)")

                if !source.isCached {
                    cacheVideoInBackground(path: path, destination: source.cacheURL)
                }
            } catch {
                LogManager.shared.log("[Reader] Video prepare failed index=\(index): \(error.localizedDescription)")
                await MainActor.run {
                    if currentIndex == index {
                        isVideoLoading = false
                        videoPlayerIndex = nil
                    }
                }
            }
        }
    }

    func videoSource(path: String) throws -> (
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

    func cacheVideoInBackground(path: String, destination: URL) {
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
                LogManager.shared.log("[Reader] Video cache completed")
            } catch {
                if !Task.isCancelled {
                    LogManager.shared.log("[Reader] video cache failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func installVideoObservers(on player: AVPlayer, item: AVPlayerItem) {
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
            handleAutoReadMediaFinished()
        }
    }

    func toggleVideoPlayback() {
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

    func seekVideo(to seconds: Double) {
        videoPlayer?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func stopVideo() {
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

    func startAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                let wasPlaying = isAudioPlaying
                audioCurrentTime = audioPlayer?.currentTime ?? 0
                if wasPlaying,
                   audioDuration > 0,
                   audioCurrentTime >= audioDuration - 0.1,
                   audioPlayer?.isPlaying == false {
                    isAudioPlaying = false
                    handleAutoReadMediaFinished()
                }
            }
        }
    }

    func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    func loadAudioCover(at index: Int) async {
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

}
