import SwiftUI
import SwiftData
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

@Observable
final class ReaderViewModel {
    var isPlaying = false
    var isLoading = true
    var currentUtteranceText = ""
    var speed: Float = 1.0
    var errorMessage: String?

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
    private var navigatorDelegate: NavigatorDelegateHandler?
    @ObservationIgnored
    private var isTTSNavigating = false  // Flag to ignore TTS-triggered navigation
    @ObservationIgnored
    private var modelContext: ModelContext?
    @ObservationIgnored
    private var currentBookId: UUID?

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
        // Ignore navigation triggered by TTS itself
        guard !isTTSNavigating else { return }
        // When user manually changes page, stop TTS
        guard let synthesizer = ttsSynthesizer else { return }
        if synthesizer.state != .stopped {
            synthesizer.stop()
            isPlaying = false
            currentUtteranceText = ""
        }
    }

    private func saveProgress(locator: Locator) {
        guard let context = modelContext, let bookId = currentBookId else { return }

        guard let json = locator.jsonString else { return }

        do {
            let descriptor = FetchDescriptor<ReadingProgress>(
                predicate: #Predicate { $0.bookId == bookId }
            )
            let progress = try context.fetch(descriptor).first ?? ReadingProgress(bookId: bookId)
            progress.locatorJSON = json
            progress.progress = locator.locations.totalProgression ?? 0
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
        NSLog("[ReaderViewModel] Setting up TTS for publication...")
        guard let synthesizer = PublicationSpeechSynthesizer(
            publication: publication,
            engineFactory: { SherpaOnnxTTSEngine() },
            tokenizerFactory: { defaultLanguage in
                makeJiebaContentTokenizer(defaultLanguage: defaultLanguage)
            },
            delegate: self
        ) else {
            NSLog("[ReaderViewModel] ERROR: TTS not available for this publication")
            return
        }
        NSLog("[ReaderViewModel] TTS synthesizer created successfully")
        self.ttsSynthesizer = synthesizer
    }

    // MARK: - TTS Controls

    func togglePlayback() {
        NSLog("[ReaderViewModel] togglePlayback called, synthesizer: \(ttsSynthesizer != nil ? "exists" : "nil")")
        guard let synthesizer = ttsSynthesizer else { return }
        NSLog("[ReaderViewModel] Current state: \(synthesizer.state)")
        switch synthesizer.state {
        case .stopped:
            NSLog("[ReaderViewModel] Starting from first visible element...")
            Task {
                let locator = await navigator?.firstVisibleElementLocator()
                NSLog("[ReaderViewModel] Locator: \(locator?.href.string ?? "nil")")
                synthesizer.start(from: locator)
            }
        case .paused:
            NSLog("[ReaderViewModel] Resuming...")
            synthesizer.resume()
        case .playing:
            NSLog("[ReaderViewModel] Pausing...")
            synthesizer.pause()
        }
    }

    func stop() {
        ttsSynthesizer?.stop()
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
        NSLog("[ReaderViewModel] State changed to: \(state)")
        switch state {
        case .playing(let utterance, _):
            NSLog("[ReaderViewModel] Playing: \(utterance.text.prefix(50))")
            isPlaying = true
            currentUtteranceText = utterance.text
            // 同步页面到朗读位置
            Task {
                isTTSNavigating = true
                await navigator?.go(to: utterance.locator)
                isTTSNavigating = false
            }
        case .paused(let utterance):
            NSLog("[ReaderViewModel] Paused: \(utterance.text.prefix(50))")
            isPlaying = false
            currentUtteranceText = utterance.text
        case .stopped:
            NSLog("[ReaderViewModel] Stopped")
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
}
