/// Who replaces the app with a newer version. A copy installed by Homebrew is left to Homebrew: if
/// Sparkle replaced it, Homebrew's records would go stale and the two would fight over the bundle.
public enum UpdateChannel: Sendable, Equatable {
    /// Downloaded from GitHub Releases: the app updates itself with Sparkle.
    case sparkle
    /// Installed with `brew install --cask`: `brew upgrade` updates it.
    case homebrew

    /// Where the cask puts the app.
    public static let caskAppPath = "/Applications/Halodeck.app"
    /// The cask's record in the Caskroom, under each Homebrew prefix (Apple silicon, then Intel).
    public static let caskroomEntries = ["/opt/homebrew/Caskroom/halodeck", "/usr/local/Caskroom/halodeck"]

    public static func detect(appPath: String, fileExists: (String) -> Bool) -> UpdateChannel {
        var path = appPath
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        guard path == caskAppPath, caskroomEntries.contains(where: fileExists) else { return .sparkle }
        return .homebrew
    }
}

public enum Homebrew {
    /// The fully qualified cask: the tap `disc/tap` is the repository `disc/homebrew-tap`
    /// (`TAP_REPOSITORY` in version.env; a test checks they match).
    public static let cask = "disc/tap/halodeck"
    /// `BUNDLE_ID` in version.env.
    public static let bundleID = "io.github.disc.halodeck"

    /// Upgrades the cask (which quits Halodeck first) and opens it again.
    public static var upgradeCommand: String {
        "brew upgrade --cask \(cask) && open -b \(bundleID)"
    }

    /// A `.command` file for Terminal that runs `command` in a login shell. It deletes itself first,
    /// and puts both Homebrew prefixes on the PATH in case the shell profile doesn't.
    public static func commandFile(running command: String) -> String {
        """
        #!/bin/zsh -l
        rm -f -- "$0"
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        \(command)

        """
    }
}
