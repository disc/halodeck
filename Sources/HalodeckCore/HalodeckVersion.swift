/// The version of this source tree, for runs without a bundle (`swift run`, tests), where
/// Info.plist gives none. It must equal `MARKETING_VERSION` in `version.env`; a test fails when the
/// two differ, so a release bumps both.
public enum HalodeckVersion {
    public static let marketing = "0.1.0"
}
