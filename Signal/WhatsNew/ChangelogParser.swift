import Foundation

/// One `## x.y.z` section of the bundled CHANGELOG.md, with its bullets split
/// into features ("Major/Minor Changes") and fixes ("Patch Changes").
struct ChangelogRelease: Equatable {
    let version: String
    var features: [String]
    var fixes: [String]
}

/// Parses the changesets-generated CHANGELOG.md that ships in the app bundle.
/// Expected shape: a `# signal` H1, then per release a `## <version>` header
/// with `### Minor Changes` / `### Patch Changes` subsections whose bullets
/// look like `- 599d50f: Did the thing` (changesets prefixes each entry with a
/// commit sha or a PR link).
enum ChangelogParser {
    /// Splits into features vs. fixes buckets; nil means "not inside a known
    /// subsection", so stray bullets (or unknown `###` sections) are ignored.
    private enum Bucket {
        case features, fixes
    }

    /// Commit-sha (`599d50f:`) or PR-link (`[#12](https://…):`) prefix that
    /// changesets puts in front of every bullet.
    private static let bulletPrefix =
        /^(?:[0-9a-f]{7,40}|\[[^\]]+\]\([^)]*\)):\s*/

    /// Parses the whole changelog into releases, newest first (file order).
    /// Releases whose known sections are all empty are dropped. Never throws:
    /// unrecognized lines and sections are skipped.
    static func parse(_ markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        var current: ChangelogRelease?
        var bucket: Bucket?

        func commit() {
            if let current, !current.features.isEmpty || !current.fixes.isEmpty {
                releases.append(current)
            }
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("## "), !line.hasPrefix("### ") {
                commit()
                current = ChangelogRelease(
                    version: String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces),
                    features: [],
                    fixes: []
                )
                bucket = nil
            } else if line.hasPrefix("### ") {
                switch line.dropFirst(4).lowercased() {
                case "major changes", "minor changes": bucket = .features
                case "patch changes": bucket = .fixes
                default: bucket = nil
                }
            } else if line.hasPrefix("- ") {
                guard current != nil, let bucket else { continue }
                var text = String(line.dropFirst(2))
                text = text.replacing(bulletPrefix, with: "")
                append(text, to: bucket, of: &current)
            } else if !line.isEmpty, !line.hasPrefix("#") {
                // Continuation of a multi-line bullet: fold into the last one.
                guard current != nil, let bucket else { continue }
                extend(with: line, bucket: bucket, of: &current)
            }
        }
        commit()
        return releases
    }

    /// The releases strictly newer than `storedVersion`, preserving the
    /// newest-first file order. Equal or older versions (downgrades) yield [].
    static func releases(after storedVersion: String, in releases: [ChangelogRelease]) -> [ChangelogRelease] {
        releases.filter { isVersion($0.version, newerThan: storedVersion) }
    }

    /// Numeric per-component compare so "1.10.0" > "1.9.0"; strictly greater.
    /// Non-numeric components count as 0.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0 ..< max(lhs.count, rhs.count) {
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func append(_ text: String, to bucket: Bucket, of release: inout ChangelogRelease?) {
        guard !text.isEmpty else { return }
        switch bucket {
        case .features: release?.features.append(text)
        case .fixes: release?.fixes.append(text)
        }
    }

    private static func extend(with text: String, bucket: Bucket, of release: inout ChangelogRelease?) {
        switch bucket {
        case .features:
            guard let last = release?.features.indices.last else { return }
            release?.features[last] += " " + text
        case .fixes:
            guard let last = release?.fixes.indices.last else { return }
            release?.fixes[last] += " " + text
        }
    }
}
