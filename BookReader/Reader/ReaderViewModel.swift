import SwiftUI
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

    func open(book: Book) async {
        isLoading = true
        defer { isLoading = false }

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
                setupNavigator(with: pub)
            }
        } catch {
            errorMessage = "打开书籍失败: \(error.localizedDescription)"
        }
    }

    private func setupNavigator(with publication: Publication) {
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: nil
            )
            self.navigator = navigator
            setupTTS(for: publication)
        } catch {
            self.errorMessage = "初始化阅读器失败: \(error.localizedDescription)"
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
            NSLog("[ReaderViewModel] Starting from nil position...")
            synthesizer.start(from: nil)
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
                await navigator?.go(to: utterance.locator)
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
