import XCTest

/// Parser tests pinned to the changesets output format that generates the real
/// CHANGELOG.md: `## x.y.z` version headers, `### Minor/Patch Changes`
/// subsections, and bullets prefixed by a commit sha or PR link.
final class ChangelogParserTests: XCTestCase {
    private let fixture = """
    # signal

    ## 1.2.0

    ### Minor Changes

    - 599d50f: Prompt for App Store review after completing the day for the first time
    - 756064b: Add Task Stats view with a new hotkey to view statistics

    ### Patch Changes

    - e621a6d: Fix Preferences window not coming to foreground when opening

    ## 1.1.0

    ### Minor Changes

    - 901e7c0: Add automatic updates for direct-download installs.

    ## 1.0.2

    ### Patch Changes

    - c72b52b: Add About Tab to Preferences window

    ## 1.0.1

    ### Patch Changes

    - 681534b: Fix missing app icon in distributed builds
    """

    func testParsesRealFormat() {
        let releases = ChangelogParser.parse(fixture)

        XCTAssertEqual(releases.map(\.version), ["1.2.0", "1.1.0", "1.0.2", "1.0.1"])
        XCTAssertEqual(releases[0].features, [
            "Prompt for App Store review after completing the day for the first time",
            "Add Task Stats view with a new hotkey to view statistics",
        ])
        XCTAssertEqual(releases[0].fixes, [
            "Fix Preferences window not coming to foreground when opening",
        ])
        XCTAssertEqual(releases[1].features, ["Add automatic updates for direct-download installs."])
        XCTAssertEqual(releases[1].fixes, [])
        XCTAssertEqual(releases[2].fixes, ["Add About Tab to Preferences window"])
    }

    func testStripsPRLinkPrefix() {
        let releases = ChangelogParser.parse("""
        ## 2.0.0

        ### Patch Changes

        - [#42](https://github.com/thiagobrez/Signal/pull/42): Fix the thing
        """)
        XCTAssertEqual(releases.first?.fixes, ["Fix the thing"])
    }

    func testBulletWithoutPrefixSurvivesIntact() {
        let releases = ChangelogParser.parse("""
        ## 2.0.0

        ### Minor Changes

        - Just a plain bullet with no prefix
        """)
        XCTAssertEqual(releases.first?.features, ["Just a plain bullet with no prefix"])
    }

    func testMultiLineBulletJoins() {
        let releases = ChangelogParser.parse("""
        ## 2.0.0

        ### Minor Changes

        - abc1234: A long entry that wraps
          onto a second line
        """)
        XCTAssertEqual(releases.first?.features, ["A long entry that wraps onto a second line"])
    }

    func testUnknownSectionIgnoredWithoutCorruptingNeighbors() {
        let releases = ChangelogParser.parse("""
        ## 2.0.0

        ### Breaking Changes

        - abc1234: Should not appear anywhere

        ### Patch Changes

        - def5678: Fix kept
        """)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.features, [])
        XCTAssertEqual(releases.first?.fixes, ["Fix kept"])
    }

    func testEmptyReleaseDropped() {
        let releases = ChangelogParser.parse("""
        ## 2.0.0

        ## 1.9.0

        ### Patch Changes

        - abc1234: Fix
        """)
        XCTAssertEqual(releases.map(\.version), ["1.9.0"])
    }

    func testGarbageInputYieldsEmpty() {
        XCTAssertEqual(ChangelogParser.parse(""), [])
        XCTAssertEqual(ChangelogParser.parse("random text\nwith no headers"), [])
    }

    func testReleasesAfterFiltersOlderAndEqual() {
        let releases = ChangelogParser.parse(fixture)
        let newer = ChangelogParser.releases(after: "1.0.2", in: releases)
        XCTAssertEqual(newer.map(\.version), ["1.2.0", "1.1.0"])
    }

    func testReleasesAfterDowngradeIsEmpty() {
        let releases = ChangelogParser.parse(fixture)
        XCTAssertEqual(ChangelogParser.releases(after: "9.9.9", in: releases), [])
    }

    func testVersionCompareIsNumericNotLexicographic() {
        XCTAssertTrue(ChangelogParser.isVersion("1.10.0", newerThan: "1.9.0"))
        XCTAssertFalse(ChangelogParser.isVersion("1.9.0", newerThan: "1.10.0"))
    }

    func testVersionCompareEqualIsFalse() {
        XCTAssertFalse(ChangelogParser.isVersion("1.2.0", newerThan: "1.2.0"))
    }

    func testVersionCompareHandlesDifferentComponentCounts() {
        XCTAssertTrue(ChangelogParser.isVersion("1.2.1", newerThan: "1.2"))
        XCTAssertFalse(ChangelogParser.isVersion("1.2", newerThan: "1.2.0"))
    }
}
