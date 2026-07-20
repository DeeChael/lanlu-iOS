import SwiftUI
import WebKit

struct ReaderTextPageView: UIViewRepresentable {
    let data: Data
    let paged: Bool
    let readingDirection: ReaderReadingDirection
    let tapGestureMode: ReaderTapGestureMode
    let fontSize: Int
    let lineSpacing: Int
    let paragraphSpacing: Int
    let pageMargin: Int
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let startsAtLastPage: Bool
    let entryRevision: Int
    let autoReadAdvanceRevision: Int
    let arcid: String
    let documentPath: String
    let apiClient: APIClient
    let onPreviousFile: () -> Void
    let onNextFile: () -> Void
    let onToggleControls: () -> Void
    let onAutoReadStepCompleted: (Bool) -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            context.coordinator,
            forURLScheme: Coordinator.resourceScheme
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.installGestures(on: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateGestureDirections()
        context.coordinator.applySafeArea(to: webView)

        let signature = [
            String(data.hashValue),
            String(paged),
            readingDirection.rawValue,
            String(fontSize),
            String(lineSpacing),
            String(paragraphSpacing),
            String(pageMargin),
            String(describing: safeAreaTop),
            String(describing: safeAreaBottom)
        ].joined(separator: ":")

        if context.coordinator.loadedSignature != signature {
            context.coordinator.loadedSignature = signature
            context.coordinator.isDocumentReady = false
            webView.loadHTMLString(
                styledHTML,
                baseURL: context.coordinator.documentBaseURL
            )
        }
        context.coordinator.applyEntryIfNeeded(to: webView)
        context.coordinator.applyAutoReadAdvanceIfNeeded(to: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        coordinator.cancelResourceTasks()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "readerText"
        )
    }

    private var styledHTML: String {
        let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? String(decoding: data, as: UTF8.self)
        let style = """
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
        <style id="lanlu-reader-style">
        :root { color-scheme: light dark; }
        html, body { background: transparent !important; }
        *, *::before, *::after { box-sizing: border-box !important; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif !important;
          font-size: \(fontSize)px !important;
          line-height: calc(1em + \(lineSpacing)px) !important;
          margin: 0 !important;
          padding: 0 !important;
          overflow-wrap: anywhere;
          visibility: hidden;
        }
        p { margin-top: 0 !important; margin-bottom: \(paragraphSpacing)px !important; }
        img, video, svg {
          display: block !important;
          max-width: 100% !important;
          max-height: var(--reader-content-height, none) !important;
          width: auto !important;
          height: auto !important;
          object-fit: contain !important;
          break-inside: avoid-column !important;
          -webkit-column-break-inside: avoid !important;
        }
        .lanlu-reader-media-page {
          display: flex !important;
          align-items: center !important;
          justify-content: center !important;
          width: 100% !important;
          height: var(--reader-content-height, auto) !important;
          overflow: hidden !important;
          break-before: column !important;
          break-after: column !important;
          break-inside: avoid-column !important;
          -webkit-column-break-before: always !important;
          -webkit-column-break-after: always !important;
          -webkit-column-break-inside: avoid !important;
        }
        .lanlu-reader-media-page > img,
        .lanlu-reader-media-page > video,
        .lanlu-reader-media-page > svg {
          max-width: 100% !important;
          max-height: 100% !important;
        }
        </style>
        """
        let script = """
        <script>
        (() => {
          const paged = \(paged ? "true" : "false");
          let currentPage = 0;
          let pageCount = 1;
          let entryAtEnd = false;
          function layout() {
            const body = document.body;
            if (!body) return;
            const rootStyle = getComputedStyle(document.documentElement);
            const safeTop = parseFloat(rootStyle.getPropertyValue('--reader-safe-top')) || 0;
            const safeBottom = parseFloat(rootStyle.getPropertyValue('--reader-safe-bottom')) || 0;
            if (paged) {
              document.documentElement.style.overflow = 'hidden';
              const contentWidth = Math.max(window.innerWidth - \(pageMargin * 2), 1);
              const contentHeight = Math.max(window.innerHeight - safeTop - safeBottom, 1);
              body.style.position = 'absolute';
              body.style.top = safeTop + 'px';
              body.style.left = '\(pageMargin)px';
              body.style.width = contentWidth + 'px';
              body.style.height = contentHeight + 'px';
              body.style.margin = '0px';
              body.style.columnWidth = contentWidth + 'px';
              body.style.columnGap = '\(pageMargin * 2)px';
              body.style.columnFill = 'auto';
              body.style.overflow = 'visible';
              body.style.padding = '0px';
              body.style.transition = 'none';
              document.documentElement.style.setProperty('--reader-content-height', contentHeight + 'px');
              pageCount = Math.max(1, Math.ceil((body.scrollWidth + \(pageMargin * 2)) / window.innerWidth));
              currentPage = entryAtEnd
                ? Math.max(pageCount - 1, 0)
                : Math.min(currentPage, pageCount - 1);
              body.style.transform = `translateX(${-currentPage * window.innerWidth}px)`;
              body.style.visibility = 'visible';
            } else {
              document.documentElement.style.overflow = 'hidden';
              body.style.position = 'static';
              body.style.transform = 'none';
              body.style.width = '100%';
              body.style.height = 'auto';
              body.style.columnWidth = 'auto';
              body.style.setProperty('margin-top', safeTop + 'px', 'important');
              body.style.setProperty('margin-right', '0px', 'important');
              body.style.setProperty('margin-bottom', safeBottom + 'px', 'important');
              body.style.setProperty('margin-left', '0px', 'important');
              body.style.setProperty('padding-top', '0px', 'important');
              body.style.setProperty('padding-right', '\(pageMargin)px', 'important');
              body.style.setProperty('padding-bottom', '0px', 'important');
              body.style.setProperty('padding-left', '\(pageMargin)px', 'important');
              body.style.overflow = 'visible';
              body.style.visibility = 'visible';
              const height = Math.max(body.scrollHeight, document.documentElement.scrollHeight);
              window.webkit.messageHandlers.readerText.postMessage({ action: 'height', value: height });
            }
          }
          window.readerMove = delta => {
            const body = document.body;
            if (!body) return false;
            const target = currentPage + delta;
            if (target < 0 || target >= pageCount) return false;
            entryAtEnd = false;
            currentPage = target;
            body.style.transition = 'transform 220ms ease-out';
            body.style.transform = `translateX(${-currentPage * window.innerWidth}px)`;
            return true;
          };
          window.readerSetEntry = atEnd => {
            entryAtEnd = atEnd;
            layout();
            currentPage = atEnd ? Math.max(pageCount - 1, 0) : 0;
            const body = document.body;
            if (!body) return;
            body.style.transition = 'none';
            body.style.transform = `translateX(${-currentPage * window.innerWidth}px)`;
          };
          window.readerLayout = layout;
          addEventListener('load', () => {
            if (paged) {
              document.querySelectorAll('img, video, svg').forEach(element => {
                if (element.parentElement?.classList.contains('lanlu-reader-media-page')) return;
                const wrapper = document.createElement('div');
                wrapper.className = 'lanlu-reader-media-page';
                element.parentNode.insertBefore(wrapper, element);
                wrapper.appendChild(element);
              });
            }
            setTimeout(layout, 0);
            document.querySelectorAll('img, video, svg').forEach(element => {
              element.addEventListener('load', layout, { once: true });
              element.addEventListener('loadedmetadata', layout, { once: true });
            });
            new ResizeObserver(() => {
              if (!paged) requestAnimationFrame(layout);
            }).observe(document.body);
          });
          addEventListener('resize', layout);
        })();
        </script>
        """

        if let headRange = source.range(
            of: "</head>",
            options: [.caseInsensitive]
        ) {
            var result = source
            result.insert(contentsOf: style + script, at: headRange.lowerBound)
            return result
        }
        return "<html><head>\(style)</head><body>\(source)</body>\(script)</html>"
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler,
        WKURLSchemeHandler {
        static let resourceScheme = "lanlu-reader-resource"

        var parent: ReaderTextPageView
        var loadedSignature: String?
        var isDocumentReady = false
        private var appliedEntryRevision: Int?
        private var appliedAutoReadAdvanceRevision = 0
        private weak var webView: WKWebView?
        private var swipeRecognizers: [UISwipeGestureRecognizer] = []
        private var resourceTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

        func cancelResourceTasks() {
            for task in resourceTasks.values { task.cancel() }
            resourceTasks.removeAll()
        }

        var documentBaseURL: URL? {
            let directory = (parent.documentPath as NSString).deletingLastPathComponent
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var components = URLComponents()
            components.scheme = Self.resourceScheme
            components.host = "archive"
            components.path = directory.isEmpty ? "/" : "/\(directory)/"
            return components.url
        }

        init(parent: ReaderTextPageView) {
            self.parent = parent
        }

        func installGestures(on webView: WKWebView) {
            self.webView = webView
            webView.configuration.userContentController.add(self, name: "readerText")

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            webView.addGestureRecognizer(tap)

            for direction in [
                UISwipeGestureRecognizer.Direction.left,
                .right,
                .up,
                .down
            ] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
                swipe.direction = direction
                swipe.delegate = self
                webView.addGestureRecognizer(swipe)
                swipeRecognizers.append(swipe)
            }
            updateGestureDirections()
        }

        func updateGestureDirections() {
            for recognizer in swipeRecognizers {
                let vertical = recognizer.direction == .up || recognizer.direction == .down
                recognizer.isEnabled = parent.paged && (
                    parent.readingDirection == .verticalPaged ? vertical : !vertical
                )
            }
            webView?.scrollView.isScrollEnabled = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isDocumentReady = true
            webView.evaluateJavaScript("document.documentElement.style.webkitUserSelect='none'")
            applySafeArea(to: webView)
            applyEntryIfNeeded(to: webView)
            applyAutoReadAdvanceIfNeeded(to: webView)
        }

        func applyEntryIfNeeded(to webView: WKWebView) {
            guard isDocumentReady,
                  appliedEntryRevision != parent.entryRevision else { return }
            appliedEntryRevision = parent.entryRevision
            webView.evaluateJavaScript(
                "window.readerSetEntry && window.readerSetEntry("
                + (parent.startsAtLastPage ? "true" : "false")
                + ");"
            )
        }

        func applyAutoReadAdvanceIfNeeded(to webView: WKWebView) {
            guard isDocumentReady,
                  parent.autoReadAdvanceRevision > 0,
                  appliedAutoReadAdvanceRevision != parent.autoReadAdvanceRevision else { return }
            appliedAutoReadAdvanceRevision = parent.autoReadAdvanceRevision
            webView.evaluateJavaScript("window.readerMove && window.readerMove(1)") { [weak self] result, _ in
                guard let self else { return }
                self.parent.onAutoReadStepCompleted((result as? Bool) == true)
            }
        }

        func applySafeArea(to webView: WKWebView) {
            let windowInsets = webView.window?.safeAreaInsets ?? .zero
            let applicationInsets = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .safeAreaInsets ?? .zero
            let top = max(
                parent.safeAreaTop,
                webView.safeAreaInsets.top,
                windowInsets.top,
                applicationInsets.top
            )
            let bottom = max(
                parent.safeAreaBottom,
                webView.safeAreaInsets.bottom,
                windowInsets.bottom,
                applicationInsets.bottom
            )
            webView.evaluateJavaScript(
                "document.documentElement.style.setProperty('--reader-safe-top','\(top)px');"
                + "document.documentElement.style.setProperty('--reader-safe-bottom','\(bottom)px');"
                + "window.readerLayout && window.readerLayout();"
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  body["action"] as? String == "height",
                  let value = body["value"] as? Double else { return }
            parent.onHeightChange(CGFloat(value))
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            let identifier = ObjectIdentifier(urlSchemeTask)
            guard let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            resourceTasks[identifier] = Task {
                do {
                    let path = url.path.removingPercentEncoding?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        ?? ""
                    guard !path.isEmpty else { throw URLError(.badURL) }
                    let data = try await parent.apiClient.fetchPageImage(
                        arcid: parent.arcid,
                        path: path
                    )
                    guard !Task.isCancelled else { return }
                    let response = URLResponse(
                        url: url,
                        mimeType: Self.mimeType(for: path),
                        expectedContentLength: data.count,
                        textEncodingName: nil
                    )
                    await MainActor.run {
                        urlSchemeTask.didReceive(response)
                        urlSchemeTask.didReceive(data)
                        urlSchemeTask.didFinish()
                        resourceTasks.removeValue(forKey: identifier)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        urlSchemeTask.didFailWithError(error)
                        resourceTasks.removeValue(forKey: identifier)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
            let identifier = ObjectIdentifier(urlSchemeTask)
            resourceTasks[identifier]?.cancel()
            resourceTasks.removeValue(forKey: identifier)
        }

        private static func mimeType(for path: String) -> String? {
            let ext = (path as NSString).pathExtension.lowercased()
            switch ext {
            case "jpg", "jpeg": return "image/jpeg"
            case "png": return "image/png"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            case "svg": return "image/svg+xml"
            case "css": return "text/css"
            case "woff": return "font/woff"
            case "woff2": return "font/woff2"
            default: return nil
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let horizontal = location.x / max(view.bounds.width, 1)
            let vertical = location.y / max(view.bounds.height, 1)

            switch parent.tapGestureMode {
            case .leftRight:
                if horizontal < 1 / 3 { move(-1) }
                else if horizontal > 2 / 3 { move(1) }
                else { parent.onToggleControls() }
            case .lShape:
                if vertical < 1 / 3 { move(-1) }
                else if vertical > 2 / 3 { move(1) }
                else if horizontal < 1 / 3 { move(-1) }
                else if horizontal > 2 / 3 { move(1) }
                else { parent.onToggleControls() }
            case .kindle:
                if vertical < 1 / 3 { parent.onToggleControls() }
                else if horizontal < 1 / 3 { move(-1) }
                else { move(1) }
            case .edges:
                if horizontal < 1 / 3 || horizontal > 2 / 3 { move(1) }
                else if vertical > 2 / 3 { move(-1) }
                else { parent.onToggleControls() }
            case .disabled:
                parent.onToggleControls()
            }
        }

        @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
            let advances: Bool
            switch parent.readingDirection {
            case .rightToLeft:
                advances = recognizer.direction == .right
            case .verticalPaged:
                advances = recognizer.direction == .up
            default:
                advances = recognizer.direction == .left
            }
            move(advances ? 1 : -1)
        }

        private func move(_ delta: Int) {
            guard parent.paged, let webView else { return }
            webView.evaluateJavaScript("window.readerMove && window.readerMove(\(delta))") { [weak self] result, _ in
                guard let self, (result as? Bool) != true else { return }
                if delta < 0 { self.parent.onPreviousFile() }
                else { self.parent.onNextFile() }
            }
        }
    }
}

extension ReaderTextPageView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

extension ReaderView {
    @ViewBuilder
    func textPageView(for index: Int, size: CGSize, paged: Bool) -> some View {
        if let data = textDocuments[index] {
            let effectiveMargin = !paged && verticalAddMargin
                ? verticalMargin
                : textPageMargin
            ReaderTextPageView(
                data: data,
                paged: paged,
                readingDirection: readingDirection,
                tapGestureMode: tapGestureMode,
                fontSize: textFontSize,
                lineSpacing: textLineSpacing,
                paragraphSpacing: textParagraphSpacing,
                pageMargin: effectiveMargin,
                safeAreaTop: textSafeAreaTop,
                safeAreaBottom: textSafeAreaBottom,
                startsAtLastPage: textPageEnteringAtEnd.contains(index),
                entryRevision: textPageEntryRevision[index] ?? 0,
                autoReadAdvanceRevision: index == currentIndex
                    && textAutoReadAdvanceIndex == index
                    ? textAutoReadAdvanceRevision
                    : 0,
                arcid: arcid,
                documentPath: filePath(at: index),
                apiClient: server.apiClient,
                onPreviousFile: previousFile,
                onNextFile: nextFile,
                onToggleControls: toggleReaderControls,
                onAutoReadStepCompleted: { advancedInsideDocument in
                    handleTextAutoReadStepCompleted(
                        at: index,
                        advancedInsideDocument: advancedInsideDocument
                    )
                },
                onHeightChange: { height in
                    guard !paged, abs((textDocumentHeights[index] ?? 0) - height) > 1 else { return }
                    textDocumentHeights[index] = height
                }
            )
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(paged && index == currentIndex)
        } else {
            loadingPageView(index: index, size: size)
                .task(id: filePath(at: index)) { loadTextDocument(index) }
        }
    }

    func loadTextDocument(_ index: Int) {
        guard files.indices.contains(index), fileType(at: index) == .html else { return }
        guard textDocuments[index] == nil, textLoadTasks[index] == nil else { return }
        let path = filePath(at: index)
        guard !path.isEmpty else { return }

        textLoadTasks[index] = Task {
            do {
                let data = try await server.apiClient.fetchPageImage(arcid: arcid, path: path)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    textDocuments[index] = data
                    textLoadTasks[index] = nil
                }
            } catch {
                await MainActor.run { textLoadTasks[index] = nil }
                LogManager.shared.log(
                    "[Reader] HTML load failed index=\(index) path=\(path): \(error.localizedDescription)"
                )
            }
        }
    }
}
