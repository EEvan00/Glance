import SwiftUI
import XCTest
@testable import GlanceCore

final class AppLanguageTests: XCTestCase {
    func testSupportsThirteenLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 13)
    }

    func testResolvesChineseScriptAndRegionVariants() {
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["zh-Hant-HK"]), .traditionalChinese)
    }

    func testResolvesBaseLanguageVariants() {
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["ja-JP"]), .japanese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["pt-BR"]), .brazilianPortuguese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["pt"]), .brazilianPortuguese)
    }

    func testUsesFirstSupportedSystemPreferenceThenEnglishFallback() {
        XCTAssertEqual(
            AppLanguage.resolved(preferredLanguages: ["fr-CA", "de-DE"]),
            .french
        )
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["yue-Hant"]), .english)
    }

    func testResolvesVietnameseLanguageVariants() {
        for identifier in ["vi", "vi-VN", "vi_VN"] {
            XCTAssertEqual(AppLanguage.resolved(preferredLanguages: [identifier, "en"]), .vietnamese)
        }
        XCTAssertEqual(AppLanguage.vietnamese.nativeName, "Tiếng Việt")
        XCTAssertEqual(AppLanguage.vietnamese.layoutDirection, .leftToRight)
    }

    func testArabicUsesRightToLeftLayout() {
        XCTAssertEqual(AppLanguage.arabic.layoutDirection, .rightToLeft)
        XCTAssertEqual(AppLanguage.english.layoutDirection, .leftToRight)
    }
}
