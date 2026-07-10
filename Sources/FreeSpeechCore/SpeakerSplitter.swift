import Foundation

public struct TimedSegment: Equatable {
    public let start: Double
    public let text: String

    public init(start: Double, text: String) {
        self.start = start
        self.text = text
    }
}

// Two-pass speaker splitting: the accurate model produces the words, a
// separate tinydiarize pass produces only the times where the voice changed.
// Splitting works at word level — whisper's segments can span 10+ seconds and
// a turn inside one would otherwise be lost.
public enum SpeakerSplitter {
    // Absorbs timestamp drift between two independent whisper runs. Kept tight:
    // too loose and the break lands a word early on the previous speaker.
    public static let defaultTolerance = 0.25

    // `pieces` are whisper token texts in order (a leading space marks a word
    // boundary; pieces concatenate verbatim). A turn breaks the line at the
    // next word boundary, so a turn mid-word can never split the word.
    public static func merged(
        pieces: [TimedSegment], turnTimes: [Double],
        tolerance: Double = defaultTolerance
    ) -> String {
        let turns = turnTimes.sorted()
        var turnIndex = 0
        var pendingTurn = false
        var out = ""
        for piece in pieces {
            while turnIndex < turns.count, turns[turnIndex] <= piece.start + tolerance {
                pendingTurn = true
                turnIndex += 1
            }
            if out.isEmpty {
                pendingTurn = false
                out = String(piece.text.drop { $0 == " " })
            } else if pendingTurn, piece.text.hasPrefix(" ") {
                pendingTurn = false
                out += "\n" + piece.text.dropFirst()
            } else {
                out += piece.text
            }
        }
        return capitalizeLineStarts(out)
    }

    // Each line is a fresh utterance, so sentence casing is safe here.
    private static func capitalizeLineStarts(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            guard let first = line.first, first.isLowercase else { return line }
            return first.uppercased() + line.dropFirst()
        }.joined(separator: "\n")
    }
}
