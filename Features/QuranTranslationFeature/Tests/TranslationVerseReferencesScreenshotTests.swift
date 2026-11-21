//
//  TranslationVerseReferencesScreenshotTests.swift
//
//  Renders the pull request screenshots for #1136, verse references in footnotes. Not a regression
//  test: it writes the images to $SCREENSHOTS_DIR (xcodebuild passes TEST_RUNNER_SCREENSHOTS_DIR to
//  the test process) and fails only when a screen doesn't render.
//

import AnnotationsService
import NoorFont
import QuranKit
import QuranResources
import QuranText
@testable import QuranTextKit
import ReadingService
import SwiftUI
import TranslationService
import UIKit
import UIx
import VerseTextPersistence
import XCTest
@testable import NoorUI
@testable import QuranTranslationFeature

@MainActor
final class TranslationVerseReferencesScreenshotTests: XCTestCase {
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
        savedShowFootnotes = QuranContentStatePreferences.shared.showFootnotesInTranslation
        savedTranslationFontSize = FontSizePreferences.shared.translationFontSize
        savedArabicFontSize = FontSizePreferences.shared.arabicFontSize
        // The app's defaults, with footnotes shown under the translation.
        ReadingPreferences.shared.reading = .hafs_1405
        QuranContentStatePreferences.shared.showArabicInTranslation = true
        QuranContentStatePreferences.shared.showFootnotesInTranslation = true
        FontSizePreferences.shared.translationFontSize = .large
        FontSizePreferences.shared.arabicFontSize = .large
    }

    override func tearDown() {
        ReadingPreferences.shared.reading = savedReading
        QuranContentStatePreferences.shared.showArabicInTranslation = savedShowArabicText
        QuranContentStatePreferences.shared.showFootnotesInTranslation = savedShowFootnotes
        FontSizePreferences.shared.translationFontSize = savedTranslationFontSize
        FontSizePreferences.shared.arabicFontSize = savedArabicFontSize
        UIView.setAnimationsEnabled(animationsWereEnabled)
        super.tearDown()
    }

    /// (a) The Clear Quran's 21:105, its footnote shown under the translation.
    func test_a_inlineFootnote() async throws {
        let verse = Self.verse(21, 105)
        let screen = try await Screen.translationPage(
            of: verse,
            scrollToRow: .translationFootnoteChunk(verse, translationId: ScreenshotTranslation.clearQuran.id, footnoteIndex: 0, chunkIndex: 0)
        )
        try save(await screen.png(), as: "a-inline-footnote")
        screen.close()
    }

    /// (b) The same footnote in the footnote sheet, opened from its marker.
    func test_b_footnoteSheet() async throws {
        let page = try await Screen.translationPage(of: Self.verse(21, 105))
        page.viewModel?.openURL(.footnote(translationId: ScreenshotTranslation.clearQuran.id, sura: 21, ayah: 105, footnoteIndex: 0))
        let footnote = try XCTUnwrap(page.viewModel?.footnote, "The footnote didn't open")
        page.close()

        let sheet = Screen.view(footnote)
        try save(await sheet.png(), as: "b-footnote-sheet")
        sheet.close()
    }

    /// (c) After tapping {39:47}: the reader at 39:47, highlighted, with the toast to go back.
    func test_c_followedReference() async throws {
        let target = Self.verse(39, 47)
        let screen = try await Screen.translationPage(of: target, navigatedTo: target, toast: .verseReference(target) {})
        try save(await screen.png(), as: "c-followed-reference")
        screen.close()
    }

    // MARK: Private

    private var animationsWereEnabled = true
    private var savedReading: Reading = .hafs_1405
    private var savedShowArabicText = true
    private var savedShowFootnotes = false
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

// MARK: - Screen

/// An iPhone-sized window showing a translation page as the reader does, or any view.
@MainActor
private final class Screen {
    // MARK: Lifecycle

    private init(window: UIWindow, viewModel: ContentTranslationViewModel?) {
        self.window = window
        self.viewModel = viewModel
    }

    // MARK: Internal

    let viewModel: ContentTranslationViewModel?

    /// The Clear Quran on `verse`'s page, opened at `target` the way navigating to a verse opens it,
    /// or scrolled to `row`, with `toast` showing where the toast presenter shows it.
    static func translationPage(
        of verse: AyahNumber,
        navigatedTo target: AyahNumber? = nil,
        scrollToRow row: TranslationItemId? = nil,
        toast: Toast? = nil
    ) async throws -> Screen {
        let overlayService = VerseOverlayService()
        overlayService.overlays.navigationTarget = target
        overlayService.overlays.navigationHighlight = target
        // Its own data services find no files, so the content committed here stays.
        let viewModel = makeContentTranslationViewModel(overlayService: overlayService)
        // The reader follows verse references, so they show as links.
        viewModel.onVerseReferenceTapped = { _, _ in }
        let verses = verse.page.verses
        viewModel.verses = verses
        let translations = [ScreenshotTranslation.clearQuran]
        let texts = try await verseTexts(verses, translations: translations)
        viewModel.commitLoadedContent(verses: verses, translations: translations, verseTexts: texts)

        #if QURAN_SYNC
        let content = ContentTranslationView(viewModel: viewModel, onAyahNumberTapped: nil)
        #else
        let content = ContentTranslationView(viewModel: viewModel)
        #endif
        // As QuranPaginationView themes the pages, with the default Paper theme.
        let root = content
            .themedBackground()
            .themedForeground()
            .environment(\.themeStyle, themeStyle)
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast, dismiss: {}, userDismiss: {})
                        .padding(.bottom, toast.bottomOffset)
                }
            }
            .ignoresSafeArea()
        let screen = Screen(window: makeWindow(UIHostingController(rootView: root)), viewModel: viewModel)

        if let row {
            viewModel.scrollToItem = row
        }
        if target != nil || row != nil {
            let list = try XCTUnwrap(screen.list, "Found no translation list")
            // The list centers the row it scrolls to.
            await waitUntil("the list scrolls") {
                list.contentOffset.y > -list.adjustedContentInset.top + 1
            }
        }
        return screen
    }

    /// `view` filling the window, like a sheet at its large detent.
    static func view(_ view: some View) -> Screen {
        let root = view.environment(\.themeStyle, themeStyle)
        return Screen(window: makeWindow(UIHostingController(rootView: root)), viewModel: nil)
    }

    /// The screen once its content stops changing.
    func png() async throws -> Data {
        var previous: Data?
        for _ in 0 ..< 24 {
            try await Task.sleep(nanoseconds: 250_000_000)
            let png = renderPNG()
            if png == previous {
                return png
            }
            previous = png
        }
        XCTFail("The screen kept changing; keeping its last frame")
        return previous ?? renderPNG()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: Private

    private static let themeStyle = ThemeStyle.paper

    private let window: UIWindow

    private static var screenSize: CGSize {
        let size = UIScreen.main.bounds.size
        return size.width > 0 && size.height > size.width ? size : CGSize(width: 390, height: 844)
    }

    private var list: UIScrollView? {
        let collectionView: UIScrollView? = window.findSubview(ofType: UICollectionView.self)
        let tableView: UIScrollView? = window.findSubview(ofType: UITableView.self)
        return collectionView ?? tableView
    }

    private static func makeWindow(_ controller: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: screenSize))
        window.backgroundColor = themeStyle.backgroundColor
        // The accent the app tints its windows with, which SwiftUI reads as accentColor for links.
        window.tintColor = AppIconAccent.current.color
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        print("[screenshots] screen \(screenSize) @\(UIScreen.main.scale)x")
        return window
    }

    /// Each verse's Arabic text from the bundled Quran database, and each translation's text as
    /// `QuranTextDataService` builds it from the translation database's rows, footnotes included.
    private static func verseTexts(_ verses: [AyahNumber], translations: [Translation]) async throws -> [AyahNumber: VerseText] {
        let unavailableURL = URL(fileURLWithPath: "/tmp/unavailable-quran-translation-test")
        let dataService = QuranTextDataService(
            localTranslationRetriever: LocalTranslationsRetriever(databasesURL: unavailableURL),
            arabicPersistence: GRDBQuranVerseTextPersistence(fileURL: QuranResources.quranUthmaniV2Database),
            translationsPersistenceBuilder: { _ in RawTranslationRows(rows: TranslationVerseReferencesScreenshotTexts.clearQuran) }
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

    private func renderPNG() -> Data {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.pngData { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}

/// The number of colors in a 64×128 thumbnail of the image; a blank screen has one.
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
        colors.insert(UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2]))
    }
    return colors.count
}

// MARK: - Translations

/// The Clear Quran, as the translations list describes it.
private enum ScreenshotTranslation {
    static let clearQuran = Translation(
        id: 106,
        displayName: "English Translation (The Clear Quran)",
        translator: "Dr. Mustafa Khattab",
        translatorForeign: nil,
        fileURL: URL(string: "https://android.quran.com/data/getTranslation.php?id=106&ext=zip")!,
        fileName: "quran.en.clearquran.db",
        languageCode: "en",
        version: 11,
        installedVersion: 11
    )
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
