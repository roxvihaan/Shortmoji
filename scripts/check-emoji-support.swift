import Foundation
import CoreText

let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 24, nil)
let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
var supported: [String] = []
var counts: [Int: Int] = [:]
for line in text.components(separatedBy: .newlines) {
    guard line.contains("; fully-qualified") || line.contains("; component"), let part = line.components(separatedBy: ";").first else { continue }
    let scalars = part.split(separator: " ").compactMap { UInt32($0, radix: 16).flatMap(UnicodeScalar.init) }
    let emoji = String(String.UnicodeScalarView(scalars))
    let value = NSAttributedString(string: emoji, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let shaped = CTLineCreateWithAttributedString(value)
    let runs = CTLineGetGlyphRuns(shaped) as! [CTRun]
    let glyphs = CTLineGetGlyphCount(shaped)
    counts[glyphs, default: 0] += 1
    var valid = !runs.isEmpty
    var advancingGlyphs = 0
    for run in runs {
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        valid = valid && CTFontCopyPostScriptName(runFont) as String == "AppleColorEmoji"
        var gs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
        var advances = [CGSize](repeating: .zero, count: gs.count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &gs)
        CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
        valid = valid && !gs.contains(0)
        advancingGlyphs += advances.filter { $0.width > 0 }.count
    }
    // Some mixed-tone emoji use multiple overlaid glyphs, with only one advance.
    // Unsupported joined sequences instead render as separate advancing glyphs.
    if valid && advancingGlyphs == 1 { supported.append(emoji) }
}
try JSONEncoder().encode(supported).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("Supported: \(supported.count); glyph counts: \(counts)")
