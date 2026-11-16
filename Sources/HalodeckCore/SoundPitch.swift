import Foundation

/// Maps a level (0...1) to a note so the sound ticks rise and fall with volume or brightness.
/// Two octaves of the C-major pentatonic scale (C5…C7) always sound pleasant, step after step.
public enum SoundPitch {
    static let notes: [Double] = [
        523.25, 587.33, 659.25, 783.99, 880.00,   // C5 D5 E5 G5 A5
        1046.50, 1174.66, 1318.51, 1567.98, 1760.00,   // C6 D6 E6 G6 A6
        2093.00,   // C7
    ]

    public static func frequency(forLevel level: Double?) -> Double {
        guard let level else { return notes[3] }   // G5 when the level is unknown
        let index = Int((min(1, max(0, level)) * Double(notes.count - 1)).rounded())
        return notes[index]
    }

    /// The same note as a pitch shift in cents from the middle note (C6), for recorded sounds.
    public static func cents(forLevel level: Double?) -> Double {
        1200 * log2(frequency(forLevel: level) / notes[5])
    }
}
