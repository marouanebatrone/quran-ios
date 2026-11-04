//
//  TranslationFootnotesScreenshotTests.swift
//
//  Renders the translation page into PNG files for pull request screenshots. It isn't a
//  regression test: it writes the images to $SCREENSHOTS_DIR (xcodebuild passes
//  TEST_RUNNER_SCREENSHOTS_DIR to the test process) and fails only when a page doesn't render.
//

import AnnotationsService
import NoorFont
import QuranKit
import QuranResources
import QuranText
import ReadingService
import SwiftUI
import TranslationService
import UIKit
import UIx
import VerseTextPersistence
import XCTest
@testable import NoorUI
@testable import QuranTextKit
@testable import QuranTranslationFeature

@MainActor
final class TranslationFootnotesScreenshotTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        if UIFont(name: "icomoon", size: 20) == nil {
            FontName.registerFonts()
        }
        // Scrolls and list updates apply at once, without waiting for animations.
        animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)

        savedReading = ReadingPreferences.shared.reading
        savedShowArabicText = QuranContentStatePreferences.shared.showArabicInTranslation
        savedTranslationFontSize = FontSizePreferences.shared.translationFontSize
        savedArabicFontSize = FontSizePreferences.shared.arabicFontSize
        // The app's defaults.
        ReadingPreferences.shared.reading = .hafs_1405
        QuranContentStatePreferences.shared.showArabicInTranslation = true
        FontSizePreferences.shared.translationFontSize = .large
        FontSizePreferences.shared.arabicFontSize = .large
    }

    override func tearDown() {
        ReadingPreferences.shared.reading = savedReading
        QuranContentStatePreferences.shared.showArabicInTranslation = savedShowArabicText
        FontSizePreferences.shared.translationFontSize = savedTranslationFontSize
        FontSizePreferences.shared.arabicFontSize = savedArabicFontSize
        UIView.setAnimationsEnabled(animationsWereEnabled)
        super.tearDown()
    }

    /// (a) Khan & Hilali on page 2, opened at 2:3, whose translation has three footnotes.
    func test_a_khanHilali() async throws {
        let page = try await TranslationPageHost.show(
            verses: Self.page2,
            translations: [ScreenshotTranslation.khanHilali],
            scrollTo: Self.verse(2, 3)
        )
        defer { page.close() }
        try save(try await page.screen(), as: "a-khan-hilali")
        try save(try await page.fullPage(), as: "a-khan-hilali-fullpage")
    }

    /// (b) Khan & Hilali with Sahih International, from the top of page 2.
    func test_b_khanHilaliAndSahihInternational() async throws {
        let page = try await TranslationPageHost.show(
            verses: Self.page2,
            translations: [ScreenshotTranslation.khanHilali, ScreenshotTranslation.sahihInternational]
        )
        defer { page.close() }
        try save(try await page.screen(), as: "b-khan-hilali-sahih")
        try save(try await page.fullPage(), as: "b-khan-hilali-sahih-fullpage")
    }

    /// (c) A right-to-left translation with footnotes, from the top of page 2.
    func test_c_urduJunagarhi() async throws {
        let page = try await TranslationPageHost.show(
            verses: Self.page2,
            translations: [ScreenshotTranslation.junagarhi]
        )
        defer { page.close() }
        try save(try await page.screen(), as: "c-urdu-junagarhi")
        try save(try await page.fullPage(), as: "c-urdu-junagarhi-fullpage")
    }

    /// (d) 7:157, whose Khan & Hilali translation is truncated by Read more, before and after expanding it.
    /// It's shown alone so the end of its translation and its footnotes fit on the screen.
    func test_d_readMore() async throws {
        let verse = Self.verse(7, 157)
        let page = try await TranslationPageHost.show(
            verses: [verse],
            translations: [ScreenshotTranslation.khanHilali]
        )
        defer { page.close() }
        try save(try await page.screen(scrolledToBottom: true), as: "d1-read-more-collapsed")
        try save(try await page.fullPage(), as: "d1-read-more-collapsed-fullpage")

        page.viewModel.openURL(.readMore(
            translationId: ScreenshotTranslation.khanHilali.id,
            sura: verse.sura.suraNumber,
            ayah: verse.ayah
        ))
        page.logRows("after Read more")
        try save(try await page.screen(scrolledToBottom: true), as: "d2-read-more-expanded")
        try save(try await page.fullPage(), as: "d2-read-more-expanded-fullpage")
    }

    /// (e) (a) in the dark theme.
    func test_e1_khanHilaliDark() async throws {
        let page = try await TranslationPageHost.show(
            verses: Self.page2,
            translations: [ScreenshotTranslation.khanHilali],
            scrollTo: Self.verse(2, 3),
            style: .dark
        )
        defer { page.close() }
        try save(try await page.screen(), as: "e1-khan-hilali-dark")
    }

    /// (e) (b) in the dark theme.
    func test_e2_khanHilaliAndSahihInternationalDark() async throws {
        let page = try await TranslationPageHost.show(
            verses: Self.page2,
            translations: [ScreenshotTranslation.khanHilali, ScreenshotTranslation.sahihInternational],
            style: .dark
        )
        defer { page.close() }
        try save(try await page.screen(), as: "e2-khan-hilali-sahih-dark")
    }

    /// (f) (a) with the largest standard translation font size, scrolled to 2:3's translation
    /// so its footnotes show under it.
    func test_f_khanHilaliLargeTranslationFont() async throws {
        FontSizePreferences.shared.translationFontSize = .xxxLarge
        let page = try await TranslationPageHost.show(
            verses: Self.page2,
            translations: [ScreenshotTranslation.khanHilali],
            scrollToRow: .translationTextChunk(Self.verse(2, 3), translationId: ScreenshotTranslation.khanHilali.id, chunkIndex: 0)
        )
        defer { page.close() }
        try save(try await page.screen(), as: "f-khan-hilali-large-font")
    }

    // MARK: Private

    /// Al-Baqarah 2:1–5.
    private static let page2 = Quran.hafsMadani1405.pages[1].verses

    private var animationsWereEnabled = true
    private var savedReading: Reading = .hafs_1405
    private var savedShowArabicText = true
    private var savedTranslationFontSize: FontSize = .large
    private var savedArabicFontSize: FontSize = .large

    private static func verse(_ sura: Int, _ ayah: Int) -> AyahNumber {
        AyahNumber(quran: .hafsMadani1405, sura: sura, ayah: ayah)!
    }

    private static var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("screenshots", isDirectory: true)
    }

    private func save(_ png: Data, as name: String) throws {
        let colors = distinctColorCount(png)
        XCTAssertGreaterThan(colors, 8, "\(name) looks blank")

        let directory = Self.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("[screenshots] wrote \(url.path): \(png.count) bytes, \(colors) sampled colors")

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Page host

/// Shows a page's translation as the reader does, in an iPhone-sized window.
@MainActor
private final class TranslationPageHost {
    // MARK: Lifecycle

    private init(window: UIWindow, list: UIScrollView, viewModel: ContentTranslationViewModel) {
        self.window = window
        self.list = list
        self.viewModel = viewModel
    }

    // MARK: Internal

    let viewModel: ContentTranslationViewModel

    /// Shows `translations` of `verses`, opened at `target` the way navigating to a verse opens it,
    /// or scrolled to `row` as the reader could scroll it.
    static func show(
        verses: [AyahNumber],
        translations: [Translation],
        scrollTo target: AyahNumber? = nil,
        scrollToRow row: TranslationItemId? = nil,
        style: UIUserInterfaceStyle = .light
    ) async throws -> TranslationPageHost {
        let overlayService = VerseOverlayService()
        overlayService.overlays.navigationTarget = target
        // Its own data services find no files, so the content committed here stays.
        let viewModel = makeContentTranslationViewModel(overlayService: overlayService)
        viewModel.verses = verses
        let texts = try await Self.verseTexts(verses, translations: translations)
        viewModel.commitLoadedContent(verses: verses, translations: translations, verseTexts: texts)

        #if QURAN_SYNC
        let content = ContentTranslationView(viewModel: viewModel, onAyahNumberTapped: nil)
        #else
        let content = ContentTranslationView(viewModel: viewModel)
        #endif
        // As QuranPaginationView themes the pages, with the default Paper theme.
        let controller = UIHostingController(
            rootView: content
                .themedBackground()
                .themedForeground()
                .environment(\.themeStyle, themeStyle)
                .ignoresSafeArea()
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: screenSize))
        window.overrideUserInterfaceStyle = style
        window.backgroundColor = themeStyle.backgroundColor
        // The accent the app tints its windows with, which SwiftUI reads as accentColor for links.
        window.tintColor = AppIconAccent.current.color
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        let collectionView: UIScrollView? = window.findSubview(ofType: UICollectionView.self)
        let tableView: UIScrollView? = window.findSubview(ofType: UITableView.self)
        let list = try XCTUnwrap(collectionView ?? tableView, "Found no translation list")
        let page = TranslationPageHost(window: window, list: list, viewModel: viewModel)
        print("[screenshots] screen \(screenSize) @\(UIScreen.main.scale)x, \(style == .dark ? "dark" : "light")")
        page.logRows("shown")

        if let row {
            viewModel.scrollToItem = row
        }
        if target != nil || row != nil {
            // The list centers the row it scrolls to.
            await waitUntil("the list scrolls") {
                list.contentOffset.y > -list.adjustedContentInset.top + 1
            }
            print("[screenshots] scrolled to \(String(describing: viewModel.scrollToItem)): offset \(list.contentOffset.y)")
        }
        return page
    }

    /// The page as the iPhone screen shows it.
    func screen(scrolledToBottom: Bool = false) async throws -> Data {
        resize(to: Self.screenSize)
        if scrolledToBottom {
            try await scrollToBottom()
        }
        return try await settledPNG()
    }

    /// The whole page in one image as tall as the list's content.
    func fullPage() async throws -> Data {
        for _ in 0 ..< 10 {
            let height = ceil(list.contentSize.height + list.adjustedContentInset.top + list.adjustedContentInset.bottom)
            if abs(height - window.bounds.height) < 1 {
                break
            }
            resize(to: CGSize(width: window.bounds.width, height: height))
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: -list.adjustedContentInset.top), animated: false)
        return try await settledPNG()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    func logRows(_ reason: String) {
        let rows = viewModel.items(quranFont: .uthmanicHafs).map { "\($0.id)" }
        print("[screenshots] \(reason): \(rows.count) rows: \(rows.joined(separator: " | "))")
    }

    // MARK: Private

    private static let themeStyle = ThemeStyle.paper

    private let window: UIWindow
    private let list: UIScrollView

    private static var screenSize: CGSize {
        let size = UIScreen.main.bounds.size
        return size.width > 0 && size.height > size.width ? size : CGSize(width: 390, height: 844)
    }

    /// Each verse's Arabic text from the bundled Quran database, and each translation's text as
    /// `QuranTextDataService` builds it from the translation database's rows, footnotes included.
    private static func verseTexts(_ verses: [AyahNumber], translations: [Translation]) async throws -> [AyahNumber: VerseText] {
        let unavailableURL = URL(fileURLWithPath: "/tmp/unavailable-quran-translation-test")
        let dataService = QuranTextDataService(
            localTranslationRetriever: LocalTranslationsRetriever(databasesURL: unavailableURL),
            arabicPersistence: GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database),
            translationsPersistenceBuilder: rawTranslationRows
        )
        return try await dataService.textForVerses(verses, translations: translations)
    }

    private static func waitUntil(_ description: String, _ condition: @escaping @MainActor () -> Bool) async {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { condition() }
            },
            object: nil
        )
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        if result != .completed {
            XCTFail("Timed out waiting until \(description)")
        }
    }

    private func resize(to size: CGSize) {
        guard window.bounds.size != size else {
            return
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded()
    }

    private func scrollToBottom() async throws {
        var lastBottom = CGFloat.nan
        for _ in 0 ..< 12 {
            let bottom = max(
                -list.adjustedContentInset.top,
                list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height
            )
            if bottom == lastBottom, abs(list.contentOffset.y - bottom) < 0.5 {
                return
            }
            lastBottom = bottom
            list.setContentOffset(CGPoint(x: list.contentOffset.x, y: bottom), animated: false)
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// Renders until two frames match, so the list has laid out its rows.
    private func settledPNG() async throws -> Data {
        var settled: Data?
        var previous: Data?
        for _ in 0 ..< 24 {
            try await Task.sleep(nanoseconds: 250_000_000)
            let png = renderPNG(drawingHierarchy: false)
            if png == previous {
                settled = png
                break
            }
            previous = png
        }
        if settled == nil {
            XCTFail("The page kept changing; keeping its last frame")
        }
        let png = settled ?? previous ?? renderPNG(drawingHierarchy: false)
        if distinctColorCount(png) <= 8 {
            print("[screenshots] the layer rendering looks blank; drawing the view hierarchy instead")
            let drawn = renderPNG(drawingHierarchy: true)
            if distinctColorCount(drawn) > distinctColorCount(png) {
                return drawn
            }
        }
        return png
    }

    private func renderPNG(drawingHierarchy: Bool) -> Data {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.pngData { context in
            if drawingHierarchy {
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            } else {
                window.layer.render(in: context.cgContext)
            }
        }
    }
}

/// The number of colors in a 64×128 thumbnail of the image; a blank page has one.
private func distinctColorCount(_ png: Data) -> Int {
    guard let image = UIImage(data: png)?.cgImage else {
        return 0
    }
    let width = 64
    let height = 128
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else {
        return 0
    }
    var colors = Set<UInt32>()
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let red = UInt32(pixels[index]) << 16
        let green = UInt32(pixels[index + 1]) << 8
        let blue = UInt32(pixels[index + 2])
        colors.insert(red | green | blue)
    }
    return colors.count
}

// MARK: - Translations

/// The translations as the translations list describes them.
private enum ScreenshotTranslation {
    static let khanHilali = Translation(
        id: 107,
        displayName: "English Translation (Khan/Hilali)",
        translator: "Muhsin Khan and Taqi-ud-Din al-Hilali",
        translatorForeign: nil,
        fileURL: URL(string: "https://android.quran.com/data/getTranslation.php?id=107&ext=zip")!,
        fileName: "quran.en.khanhilali.db",
        languageCode: "en",
        version: 10,
        installedVersion: 10
    )

    static let sahihInternational = Translation(
        id: 98,
        displayName: "English Translation (Sahih International)",
        translator: "Sahih International",
        translatorForeign: nil,
        fileURL: URL(string: "https://android.quran.com/data/getTranslation.php?id=98&ext=zip")!,
        fileName: "quran.ensi.db",
        languageCode: "en",
        version: 20,
        installedVersion: 20
    )

    static let junagarhi = Translation(
        id: 90,
        displayName: "Urdu Translation",
        translator: "Muhammad Junagarhi",
        translatorForeign: nil,
        fileURL: URL(string: "https://android.quran.com/data/getTranslation.php?id=90&ext=zip")!,
        fileName: "quran.urdu.junagarhi.db",
        languageCode: "ur",
        version: 16,
        installedVersion: 16
    )
}

/// A translation database holding `translation`'s rows from `TranslationFootnotesScreenshotTexts`.
private func rawTranslationRows(_ translation: Translation) -> any TranslationVerseTextPersistence {
    switch translation.id {
    case ScreenshotTranslation.khanHilali.id:
        RawTranslationRows(rows: TranslationFootnotesScreenshotTexts.khanHilali)
    case ScreenshotTranslation.sahihInternational.id:
        RawTranslationRows(rows: TranslationFootnotesScreenshotTexts.sahihInternational)
    case ScreenshotTranslation.junagarhi.id:
        RawTranslationRows(rows: TranslationFootnotesScreenshotTexts.junagarhi)
    default:
        RawTranslationRows(rows: [:])
    }
}

/// Serves `verses.text` rows, keyed by "sura:ayah", as `GRDBTranslationVerseTextPersistence` reads them.
private struct RawTranslationRows: TranslationVerseTextPersistence {
    let rows: [String: String]

    func textForVerse(_ verse: AyahNumber) async throws -> TranslationTextPersistenceModel {
        .string(rows[key(verse)] ?? "")
    }

    func textForVerses(_ verses: [AyahNumber]) async throws -> [AyahNumber: TranslationTextPersistenceModel] {
        var texts: [AyahNumber: TranslationTextPersistenceModel] = [:]
        for verse in verses {
            if let text = rows[key(verse)] {
                texts[verse] = .string(text)
            }
        }
        return texts
    }

    func autocomplete(term: String) async throws -> [String] {
        []
    }

    func search(for term: String, quran: Quran) async throws -> [(verse: AyahNumber, text: String)] {
        []
    }

    private func key(_ verse: AyahNumber) -> String {
        "\(verse.sura.suraNumber):\(verse.ayah)"
    }
}
