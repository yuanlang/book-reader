import SwiftUI
import SwiftData
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator
import UIKit
import WebKit

@Observable
final class ReaderViewModel {
    var isPlaying = false
    var isLoading = true
    var currentUtteranceText = ""
    var speed: Float = 1.0
    var errorMessage: String?
    var ttsPanelHeight: CGFloat = 0

    /// Table of contents entries for the current publication.
    var tableOfContents: [TOCItem] = []

    // Readium components — ignored from observation
    @ObservationIgnored
    private var publication: Publication?
    @ObservationIgnored
    private var navigator: EPUBNavigatorViewController?
    @ObservationIgnored
    private var ttsSynthesizer: PublicationSpeechSynthesizer?
    @ObservationIgnored
    private let storage = BookStorageService.shared
    @ObservationIgnored
    fileprivate var navigatorDelegate: NavigatorDelegateHandler?
    @ObservationIgnored
    private var modelContext: ModelContext?
    @ObservationIgnored
    private var currentBookId: UUID?
    @ObservationIgnored
    private var ttsEngine: SherpaOnnxTTSEngine?
    @ObservationIgnored
    private lazy var hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    @ObservationIgnored
    private lazy var httpClient = DefaultHTTPClient()
    @ObservationIgnored
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    @ObservationIgnored
    private lazy var publicationOpener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        )
    )

    /// Returns the EPUB navigator as a SwiftUI view.
    var navigatorView: AnyView {
        if let navigator {
            return AnyView(NavigatorWrapper(navigator))
        }
        return AnyView(ProgressView("加载中..."))
    }

    func open(book: Book, context: ModelContext) async {
        isLoading = true
        defer { isLoading = false }

        self.modelContext = context
        self.currentBookId = book.id

        // 查询上次阅读位置
        let savedLocator = loadSavedLocator(for: book.id, context: context)

        do {
            let url = await storage.bookURL(for: book.filePath)

            guard let fileURL = FileURL(url: url) else {
                errorMessage = "无效的文件路径"
                return
            }

            let asset = try await assetRetriever.retrieve(url: fileURL).get()
            let pub = try await publicationOpener.open(
                asset: asset,
                allowUserInteraction: false
            ).get()

            self.publication = pub

            await MainActor.run {
                parseTOC(from: pub)
                setupNavigator(with: pub, initialLocation: savedLocator)
            }
        } catch {
            errorMessage = "打开书籍失败: \(error.localizedDescription)"
        }
    }

    private func loadSavedLocator(for bookId: UUID, context: ModelContext) -> Locator? {
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate { $0.bookId == bookId }
        )
        guard let progress = try? context.fetch(descriptor).first,
              !progress.locatorJSON.isEmpty,
              let locator = try? Locator(jsonString: progress.locatorJSON) else {
            return nil
        }
        return locator
    }

    @MainActor
    private func setupNavigator(with publication: Publication, initialLocation: Locator? = nil) {
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation
            )
            self.navigator = navigator
            // Set up navigator delegate to handle page changes
            let delegate = NavigatorDelegateHandler { [weak self] locator in
                self?.handlePageChange()
                self?.saveProgress(locator: locator)
            }
            navigator.delegate = delegate
            self.navigatorDelegate = delegate
            setupTTS(for: publication)
        } catch {
            self.errorMessage = "初始化阅读器失败: \(error.localizedDescription)"
        }
    }

    private func handlePageChange() {
        // When TTS is playing, all navigation is TTS-driven — don't stop it.
        // Only stop TTS when the user manually swipes to a new page.
        guard let synthesizer = ttsSynthesizer else { return }
        if case .playing = synthesizer.state {
            return
        }
        if case .stopped = synthesizer.state {
            return
        }
        synthesizer.stop()
        isPlaying = false
        currentUtteranceText = ""
    }

    @MainActor
    func updateTTSPanelHeight(_ height: CGFloat) {
        navigatorDelegate?.ttsPanelHeight = height
        // Force content inset update by finding spread views through the view hierarchy
        forceContentInsetUpdate()
    }

    @MainActor
    private func forceContentInsetUpdate() {
        guard let navView = navigator?.view else { return }
        let inset = computeContentInset()
        applyInset(inset, to: navView)
    }

    @MainActor
    private func computeContentInset() -> UIEdgeInsets {
        guard let navView = navigator?.view else { return .zero }
        // SwiftUI 已处理安全区域，只需为 TTS 面板添加底部边距
        let panelHeight = navigatorDelegate?.ttsPanelHeight ?? 0
        return UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: panelHeight,
            right: 0
        )
    }

    private func findNavBarHeight(in view: UIView?) -> CGFloat {
        guard let view else { return 44 }
        if let navBar = view as? UINavigationBar {
            return navBar.frame.height
        }
        for subview in view.subviews {
            let found = findNavBarHeight(in: subview)
            if found > 0 { return found }
        }
        return 0
    }

    private func applyInset(_ inset: UIEdgeInsets, to view: UIView) {
        for subview in view.subviews {
            if let webView = subview as? WKWebView {
                webView.scrollView.contentInset = inset
                webView.scrollView.scrollIndicatorInsets = inset
                for constraint in webView.constraints {
                    if constraint.firstAttribute == .top {
                        constraint.constant = inset.top
                    }
                    if constraint.firstAttribute == .bottom {
                        constraint.constant = -inset.bottom
                    }
                }
            }
            applyInset(inset, to: subview)
        }
    }

    private func saveProgress(locator: Locator) {
        guard let context = modelContext, let bookId = currentBookId else { return }

        guard let json = locator.jsonString else { return }

        let progression = locator.locations.totalProgression ?? 0

        do {
            let descriptor = FetchDescriptor<ReadingProgress>(
                predicate: #Predicate { $0.bookId == bookId }
            )
            let progress = try context.fetch(descriptor).first ?? ReadingProgress(bookId: bookId)
            progress.locatorJSON = json
            progress.progress = progression
            progress.lastUpdated = Date()

            if progress.modelContext == nil {
                context.insert(progress)
            }
            try context.save()
        } catch {
            NSLog("[ReaderViewModel] 保存进度失败: \(error)")
        }
    }

    private func setupTTS(for publication: Publication) {
        let engine = SherpaOnnxTTSEngine()
        self.ttsEngine = engine
        guard let synthesizer = PublicationSpeechSynthesizer(
            publication: publication,
            engineFactory: { engine },
            tokenizerFactory: { defaultLanguage in
                makeJiebaContentTokenizer(defaultLanguage: defaultLanguage)
            },
            delegate: self
        ) else {
            return
        }
        self.ttsSynthesizer = synthesizer
    }

    // MARK: - TTS Controls

    func togglePlayback() {
        guard let synthesizer = ttsSynthesizer else { return }
        triggerHaptic()
        switch synthesizer.state {
        case .stopped:
            Task {
                let locator = await navigator?.firstVisibleElementLocator()
                synthesizer.start(from: locator)
            }
        case .paused:
            synthesizer.resume()
        case .playing:
            synthesizer.pause()
            ttsEngine?.stopSpeaking()
        }
    }

    func stop() {
        ttsSynthesizer?.stop()
        ttsEngine?.stopSpeaking()
        isPlaying = false
        currentUtteranceText = ""
    }

    func skipNext() {
        ttsSynthesizer?.next()
    }

    func skipPrevious() {
        ttsSynthesizer?.previous()
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        ttsEngine?.playbackSpeed = newSpeed
    }

    /// All available voice options grouped by language.
    var voiceOptions: (chinese: [SherpaOnnxTTSEngine.VoiceOption], english: [SherpaOnnxTTSEngine.VoiceOption]) {
        SherpaOnnxTTSEngine.availableVoiceOptions
    }

    /// Currently selected voice identifier.
    var selectedVoiceId: String? {
        ttsEngine?.selectedVoiceIdentifier
    }

    func setVoice(_ identifier: String) {
        ttsEngine?.selectedVoiceIdentifier = identifier
    }

    // MARK: - TOC

    /// Navigate to a TOC item.
    func navigateToTOCItem(_ item: TOCItem) {
        guard !item.href.isEmpty else { return }
        guard let url = AnyURL(string: item.href) else { return }
        let locator = Locator(href: url, mediaType: .html, title: item.title)
        Task {
            await navigator?.go(to: locator)
        }
    }

    private func parseTOC(from publication: Publication) {
        Task {
            let result = await publication.tableOfContents()
            switch result {
            case .success(let links):
                tableOfContents = links.map { TOCItem(from: $0) }
            case .failure:
                tableOfContents = []
            }
        }
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        hapticGenerator.impactOccurred()
    }
}

// MARK: - UIViewControllerRepresentable Wrapper

private struct NavigatorWrapper: UIViewControllerRepresentable {
    let viewController: UIViewController

    init(_ viewController: UIViewController) {
        self.viewController = viewController
    }

    func makeUIViewController(context: Context) -> UIViewController {
        viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - PublicationSpeechSynthesizerDelegate

extension ReaderViewModel: PublicationSpeechSynthesizerDelegate {
    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        stateDidChange state: PublicationSpeechSynthesizer.State
    ) {
        switch state {
        case .playing(let utterance, _):
            isPlaying = true
            currentUtteranceText = utterance.text
            // 同步页面到朗读位置
            Task {
                await navigator?.go(to: utterance.locator)
            }
        case .paused(let utterance):
            isPlaying = false
            currentUtteranceText = utterance.text
        case .stopped:
            isPlaying = false
            currentUtteranceText = ""
        }
    }

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance,
        didFailWithError error: PublicationSpeechSynthesizer.Error
    ) {
        NSLog("[ReaderViewModel] TTS Error: \(error)")
        errorMessage = "朗读出错: \(error)"
    }
}

// MARK: - Navigator Delegate Handler

@MainActor
private class NavigatorDelegateHandler: NSObject, EPUBNavigatorDelegate {
    private let onPageChange: @MainActor (Locator) -> Void
    var ttsPanelHeight: CGFloat = 0

    @MainActor
    init(onPageChange: @escaping @MainActor (Locator) -> Void) {
        self.onPageChange = onPageChange
        super.init()
    }

    nonisolated func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        Task { @MainActor in
            onPageChange(locator)
        }
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        // Handle errors silently for now
    }

    func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        // SwiftUI 已处理安全区域，只需为 TTS 面板添加底部边距
        return UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: ttsPanelHeight,
            right: 0
        )
    }
}

// MARK: - TOC Item

struct TOCItem: Identifiable {
    let id = UUID()
    let title: String
    let href: String
    let children: [TOCItem]

    init(from link: ReadiumShared.Link) {
        self.title = link.title ?? ""
        self.href = link.href
        self.children = link.children.map { TOCItem(from: $0) }
    }
}
