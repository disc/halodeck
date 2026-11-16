/// The SF Symbol for a volume level, like the system indicator.
public enum SpeakerSymbol {
    public static func name(level: Double, muted: Bool) -> String {
        if isSilent(level: level, muted: muted) { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// The sound is off: muted, or the volume at 0% (which sounds the same). nil is an output without
    /// that control (no volume control, no mute switch), which never silences it.
    public static func isSilent(level: Double?, muted: Bool?) -> Bool {
        muted == true || level.map { $0 <= 0.001 } == true
    }
}
