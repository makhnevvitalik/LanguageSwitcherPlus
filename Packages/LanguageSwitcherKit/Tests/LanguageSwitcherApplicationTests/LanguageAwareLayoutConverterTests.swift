// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import Foundation
import LanguageSwitcherApplication
import LanguageSwitcherDomain
import XCTest

final class LanguageAwareLayoutConverterTests: XCTestCase {
    func testWrongLayoutWordCyclesFromDetectedEnglishToRussian() {
        let fixture = makeFixture()

        let result = fixture.converter.convert(
            "ghbdtn",
            current: source("en", locale: "en_US"),
            availableInputSources: [source("en", locale: "en_US"), source("ru", locale: "ru_RU")]
        )

        XCTAssertEqual(result, LanguageAwareLayoutConversion(text: "привет", targetInputSourceID: "ru"))
    }

    func testKnownRussianWordStillCyclesToEnglish() {
        let fixture = makeFixture()
        fixture.frequencies.values["ru:папа"] = 0.9
        fixture.spelling.correct.insert("ru:папа")

        let result = fixture.converter.convert(
            "папа",
            current: source("ru", locale: "ru_RU"),
            availableInputSources: [source("en", locale: "en_US"), source("ru", locale: "ru_RU")]
        )

        XCTAssertEqual(result, LanguageAwareLayoutConversion(text: "gfgf", targetInputSourceID: "en"))
    }

    func testDetectedRussianCyclesToFollowingLayoutWhenThreeLayoutsAreSelected() {
        let layouts = KeyboardLayoutProviderFake()
        layouts.characters = [
            "en": ["g", "f"],
            "ru": ["п", "а"],
            "de": ["p", "a"]
        ]
        layouts.maps["en->ru"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "g", target: "п"),
            KeyboardLayoutPair(source: "f", target: "а")
        ]])
        layouts.maps["ru->de"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "п", target: "p"),
            KeyboardLayoutPair(source: "а", target: "a")
        ]])
        layouts.maps["de->en"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "p", target: "p"),
            KeyboardLayoutPair(source: "a", target: "a")
        ]])
        let converter = LanguageAwareLayoutConverter(
            keyboardLayoutProvider: layouts,
            frequencyProvider: WordFrequencyProviderFake(supported: ["en", "ru", "de"]),
            spellingChecker: WordSpellingCheckerFake()
        )

        let result = converter.convert(
            "папа",
            current: source("en", locale: "en"),
            availableInputSources: [
                source("en", locale: "en"),
                source("ru", locale: "ru"),
                source("de", locale: "de")
            ]
        )

        XCTAssertEqual(result, LanguageAwareLayoutConversion(text: "papa", targetInputSourceID: "de"))
    }

    func testSourceLayoutDetectionDoesNotDependOnActiveLayout() {
        let fixture = makeFixture()

        let result = fixture.converter.convert(
            "папа",
            current: source("en", locale: "en_US"),
            availableInputSources: [source("en", locale: "en_US"), source("ru", locale: "ru_RU")]
        )

        XCTAssertEqual(result, LanguageAwareLayoutConversion(text: "gfgf", targetInputSourceID: "en"))
    }

    func testWhitespaceSeparatedFragmentsAreEvaluatedIndependently() {
        let fixture = makeFixture()
        let result = fixture.converter.convert(
            "ghbdtn  привет\n",
            current: source("en", locale: "en_US"),
            availableInputSources: [source("en", locale: "en_US"), source("ru", locale: "ru_RU")]
        )

        XCTAssertEqual(
            result,
            LanguageAwareLayoutConversion(text: "привет  ghbdtn\n", targetInputSourceID: "en")
        )
    }

    func testPhysicalPunctuationIsConvertedButExcludedFromLookup() {
        let fixture = makeFixture()
        fixture.layouts.maps["en->ru"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "g", target: "п"),
            KeyboardLayoutPair(source: "h", target: "р"),
            KeyboardLayoutPair(source: "b", target: "и"),
            KeyboardLayoutPair(source: "d", target: "в"),
            KeyboardLayoutPair(source: "t", target: "е"),
            KeyboardLayoutPair(source: "n", target: "т"),
            KeyboardLayoutPair(source: "/", target: ".")
        ]])
        fixture.frequencies.values["ru:привет"] = 0.9

        let result = fixture.converter.convert(
            "ghbdtn/",
            current: source("en", locale: "en"),
            availableInputSources: [source("en", locale: "en"), source("ru", locale: "ru")]
        )

        XCTAssertEqual(result?.text, "привет.")
    }

    func testLookupKeepsInternalApostrophesAndDigitsButDropsAttachedPunctuation() {
        let fixture = makeFixture()

        _ = fixture.converter.convert(
            "(CAN’T123!)",
            current: source("en", locale: "en"),
            availableInputSources: [source("en", locale: "en"), source("ru", locale: "ru")]
        )

        XCTAssertTrue(fixture.frequencies.queries.contains("en:can’t123"))
    }

    func testLastChangedFragmentDeterminesTargetInputSource() {
        let layouts = KeyboardLayoutProviderFake()
        layouts.characters = ["en": ["q"], "ru": ["ж"], "de": ["z"]]
        layouts.maps["en->ru"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "q", target: "й")
        ]])
        layouts.maps["ru->de"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "ж", target: "ü")
        ]])
        layouts.maps["de->en"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "z", target: "y")
        ]])
        let frequencies = WordFrequencyProviderFake(supported: ["en", "ru", "de"])
        let converter = LanguageAwareLayoutConverter(
            keyboardLayoutProvider: layouts,
            frequencyProvider: frequencies,
            spellingChecker: WordSpellingCheckerFake()
        )

        let result = converter.convert(
            "q ж",
            current: source("en", locale: "en"),
            availableInputSources: [
                source("en", locale: "en"),
                source("ru", locale: "ru"),
                source("de", locale: "de")
            ]
        )

        XCTAssertEqual(result, LanguageAwareLayoutConversion(text: "й ü", targetInputSourceID: "de"))
    }

    func testLanguageScoresBreakEqualCharacterCoverage() {
        let layouts = KeyboardLayoutProviderFake()
        layouts.characters = ["en": Set("wort"), "de": Set("wort"), "ru": ["я"]]
        layouts.maps["en->de"] = KeyboardLayoutMap(pairTiers: [Array("wort").map {
            KeyboardLayoutPair(source: String($0), target: String($0))
        }])
        layouts.maps["de->ru"] = KeyboardLayoutMap(pairTiers: [zip(
            Array("wort"),
            Array("цщке")
        ).map {
            KeyboardLayoutPair(source: String($0), target: String($1))
        }])
        layouts.maps["ru->en"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "я", target: "z")
        ]])
        let frequencies = WordFrequencyProviderFake(supported: ["en", "de", "ru"])
        frequencies.values["de:wort"] = 0.9
        let converter = LanguageAwareLayoutConverter(
            keyboardLayoutProvider: layouts,
            frequencyProvider: frequencies,
            spellingChecker: WordSpellingCheckerFake()
        )

        let result = converter.convert(
            "wort",
            current: source("en", locale: "en"),
            availableInputSources: [
                source("en", locale: "en"),
                source("de", locale: "de"),
                source("ru", locale: "ru")
            ]
        )

        XCTAssertEqual(result, LanguageAwareLayoutConversion(text: "цщке", targetInputSourceID: "ru"))
    }

    func testSourceDetectionDoesNotDependOnAmbiguityInTargetMap() {
        let layouts = KeyboardLayoutProviderFake()
        layouts.characters["en"] = ["x"]
        layouts.characters["ru"] = ["x", "y"]
        layouts.characters["de"] = ["z"]
        layouts.maps["en->ru"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "x", target: "X")
        ]])
        layouts.maps["ru->de"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "x", target: "A"),
            KeyboardLayoutPair(source: "x", target: "B"),
            KeyboardLayoutPair(source: "y", target: "Y")
        ]])
        layouts.maps["de->en"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "z", target: "Z")
        ]])
        let converter = LanguageAwareLayoutConverter(
            keyboardLayoutProvider: layouts,
            frequencyProvider: WordFrequencyProviderFake(supported: ["en", "ru", "de"]),
            spellingChecker: WordSpellingCheckerFake()
        )

        let result = converter.convert(
            "xy",
            current: source("en", locale: "en"),
            availableInputSources: [
                source("en", locale: "en"),
                source("ru", locale: "ru"),
                source("de", locale: "de")
            ]
        )

        XCTAssertEqual(result, LanguageAwareLayoutConversion(text: "xY", targetInputSourceID: "de"))
    }

    func testUnsupportedLanguageIsNotAConversionCandidate() {
        let fixture = makeFixture()
        fixture.layouts.maps["en->ja"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "q", target: "あ")
        ]])

        let result = fixture.converter.convert(
            "q",
            current: source("en", locale: "en"),
            availableInputSources: [source("en", locale: "en"), source("ja", locale: "ja")]
        )

        XCTAssertNil(result)
    }

    func testRussianSingleCharacterWordCanWin() {
        let fixture = makeFixture()
        fixture.frequencies.values["ru:я"] = 0.7
        fixture.layouts.characters["en"] = ["z"]
        fixture.layouts.maps["en->ru"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "z", target: "я")
        ]])

        let result = fixture.converter.convert(
            "z",
            current: source("en", locale: "en"),
            availableInputSources: [source("en", locale: "en"), source("ru", locale: "ru")]
        )

        XCTAssertEqual(result?.text, "я")
    }

    func testBrazilianPortugueseLocaleUsesSeparateLexicon() {
        XCTAssertEqual(LexiconLanguageResolver.languageCode(for: "pt-BR"), "pt_br")
        XCTAssertEqual(LexiconLanguageResolver.languageCode(for: "pt_PT"), "pt")
        XCTAssertEqual(LexiconLanguageResolver.languageCode(for: "ja_JP"), "ja")
    }

    private func makeFixture() -> ConverterFixture {
        let layouts = KeyboardLayoutProviderFake()
        layouts.characters = [
            "en": Set("ghbdtn"),
            "ru": Set("приветна")
        ]
        layouts.maps["en->ru"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "g", target: "п"),
            KeyboardLayoutPair(source: "h", target: "р"),
            KeyboardLayoutPair(source: "b", target: "и"),
            KeyboardLayoutPair(source: "d", target: "в"),
            KeyboardLayoutPair(source: "t", target: "е"),
            KeyboardLayoutPair(source: "n", target: "т")
        ]])
        layouts.maps["ru->en"] = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "п", target: "g"),
            KeyboardLayoutPair(source: "р", target: "h"),
            KeyboardLayoutPair(source: "и", target: "b"),
            KeyboardLayoutPair(source: "в", target: "d"),
            KeyboardLayoutPair(source: "е", target: "t"),
            KeyboardLayoutPair(source: "т", target: "n"),
            KeyboardLayoutPair(source: "а", target: "f")
        ]])
        let frequencies = WordFrequencyProviderFake(supported: ["en", "ru"])
        let spelling = WordSpellingCheckerFake()
        return ConverterFixture(
            layouts: layouts,
            frequencies: frequencies,
            spelling: spelling,
            converter: LanguageAwareLayoutConverter(
                keyboardLayoutProvider: layouts,
                frequencyProvider: frequencies,
                spellingChecker: spelling
            )
        )
    }

    private func source(_ id: String, locale: String) -> InputSource {
        InputSource(
            id: id,
            displayName: id,
            localeIdentifier: locale,
            supportsTextConversion: true
        )
    }
}

private struct ConverterFixture {
    let layouts: KeyboardLayoutProviderFake
    let frequencies: WordFrequencyProviderFake
    let spelling: WordSpellingCheckerFake
    let converter: LanguageAwareLayoutConverter
}

private final class KeyboardLayoutProviderFake: KeyboardLayoutProvider {
    var maps: [String: KeyboardLayoutMap] = [:]
    var characters: [String: Set<Character>] = [:]

    func characters(inputSourceID: String) -> Set<Character>? {
        characters[inputSourceID]
    }

    func map(from sourceInputSourceID: String, to targetInputSourceID: String) -> KeyboardLayoutMap? {
        maps["\(sourceInputSourceID)->\(targetInputSourceID)"]
    }
}

private final class WordFrequencyProviderFake: WordFrequencyProviding {
    let supported: Set<String>
    var values: [String: Double] = [:]
    var queries: [String] = []

    init(supported: Set<String>) {
        self.supported = supported
    }

    func supports(languageCode: String) -> Bool {
        supported.contains(languageCode)
    }

    func normalizedFrequency(of word: String, languageCode: String) -> Double? {
        queries.append("\(languageCode):\(word)")
        return values["\(languageCode):\(word)"]
    }
}

private final class WordSpellingCheckerFake: WordSpellingChecking {
    var correct: Set<String> = []

    func isCorrectlySpelled(_ word: String, languageCode: String) -> Bool {
        correct.contains("\(languageCode):\(word)")
    }
}
