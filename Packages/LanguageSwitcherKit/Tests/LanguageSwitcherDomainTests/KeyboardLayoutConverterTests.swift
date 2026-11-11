// SPDX-FileCopyrightText: 2026 Vitalik Makhnev
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

import LanguageSwitcherDomain
import XCTest

final class KeyboardLayoutConverterTests: XCTestCase {
    func testConvertsCharactersByPhysicalKeyPairs() {
        let map = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "q", target: "й"),
            KeyboardLayoutPair(source: "Q", target: "Й"),
            KeyboardLayoutPair(source: "w", target: "ц")
        ]])

        XCTAssertEqual(
            KeyboardLayoutConverter.convert("Qw q!\n42", using: map),
            "Йц й!\n42"
        )
    }

    func testPreservesUnknownCharactersAndExtendedGraphemes() {
        let map = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "a", target: "ф")
        ]])

        XCTAssertEqual(
            KeyboardLayoutConverter.convert("aé 👨‍👩‍👧", using: map),
            "фé 👨‍👩‍👧"
        )
    }

    func testOmitsAmbiguousSourceCharacter() {
        let map = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "x", target: "ч"),
            KeyboardLayoutPair(source: "x", target: "ь")
        ]])

        XCTAssertEqual(KeyboardLayoutConverter.convert("x", using: map), "x")
        XCTAssertTrue(map.isEmpty)
    }

    func testOmitsEmptyAndMultiCharacterSources() {
        let map = KeyboardLayoutMap(pairTiers: [[
            KeyboardLayoutPair(source: "", target: "a"),
            KeyboardLayoutPair(source: "ab", target: "в")
        ]])

        XCTAssertEqual(KeyboardLayoutConverter.convert("ab", using: map), "ab")
        XCTAssertTrue(map.isEmpty)
    }

    func testHigherPriorityTypingPairWinsOverConflictingOptionPair() {
        let map = KeyboardLayoutMap(pairTiers: [
            [
                KeyboardLayoutPair(source: "И", target: "B")
            ],
            [
                KeyboardLayoutPair(source: "И", target: "ı"),
                KeyboardLayoutPair(source: "₽", target: "$")
            ]
        ])

        XCTAssertEqual(
            KeyboardLayoutConverter.convert("ЩДВ_ИГААУК", using: map),
            "ЩДВ_BГААУК"
        )
        XCTAssertEqual(KeyboardLayoutConverter.convert("₽", using: map), "$")
    }

    func testMainKeyboardPunctuationWinsOverKeypadPairs() {
        let map = KeyboardLayoutMap(pairTiers: [
            [
                KeyboardLayoutPair(source: ",", target: "б"),
                KeyboardLayoutPair(source: ".", target: "ю"),
                KeyboardLayoutPair(source: "/", target: ".")
            ],
            [
                KeyboardLayoutPair(source: ",", target: ","),
                KeyboardLayoutPair(source: ".", target: ".")
            ]
        ])

        XCTAssertEqual(
            KeyboardLayoutConverter.convert("xnj,s j,hfnyj./", using: map),
            "xnjбs jбhfnyjю."
        )
    }

    func testLowerPriorityTierFillsUnmappedCharacter() {
        let map = KeyboardLayoutMap(pairTiers: [
            [KeyboardLayoutPair(source: "a", target: "ф")],
            [KeyboardLayoutPair(source: "₽", target: "$")]
        ])

        XCTAssertEqual(KeyboardLayoutConverter.convert("a₽", using: map), "ф$")
    }

    func testLowerPriorityTierCannotReplaceAmbiguousHigherPriorityCharacter() {
        let map = KeyboardLayoutMap(pairTiers: [
            [
                KeyboardLayoutPair(source: "x", target: "ч"),
                KeyboardLayoutPair(source: "x", target: "ь")
            ],
            [KeyboardLayoutPair(source: "x", target: "å")]
        ])

        XCTAssertEqual(KeyboardLayoutConverter.convert("x", using: map), "x")
        XCTAssertTrue(map.isEmpty)
    }

    func testRussianAndABCPhysicalPunctuationRoundTrips() {
        let russian = Array("пибжэъёх")
        let abc = Array("gb,;']\\[")
        let russianToABC = KeyboardLayoutMap(
            pairTiers: [zip(russian, abc).map {
                KeyboardLayoutPair(source: String($0), target: String($1))
            }]
        )
        let abcToRussian = KeyboardLayoutMap(
            pairTiers: [zip(abc, russian).map {
                KeyboardLayoutPair(source: String($0), target: String($1))
            }]
        )

        let converted = KeyboardLayoutConverter.convert("пибжэъёх", using: russianToABC)

        XCTAssertEqual(converted, "gb,;']\\[")
        XCTAssertEqual(
            KeyboardLayoutConverter.convert(converted, using: abcToRussian),
            "пибжэъёх"
        )
    }
}
