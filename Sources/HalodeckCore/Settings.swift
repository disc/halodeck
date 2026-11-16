import Foundation

public enum Side: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case left, right, top, bottom
    public var isVertical: Bool { self == .left || self == .right }
}
public enum Corner: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}
public enum SideAction: String, Codable, CaseIterable, Sendable {
    case volume, brightness, keyboardBacklight, mediaSeek, track, switchTab, customKeys, nothing

    /// A 0...1 level that steps up and down (fine control applies; silent at the ends).
    public var isLevel: Bool {
        switch self {
        case .volume, .brightness, .keyboardBacklight: true
        case .mediaSeek, .track, .switchTab, .customKeys, .nothing: false
        }
    }

    /// Multiplier on "slide per step": one-off actions need a longer slide than level changes.
    public var stepScale: Double {
        switch self {
        case .volume, .brightness, .keyboardBacklight, .nothing: 1
        case .mediaSeek: 1.5
        case .switchTab, .customKeys: 3
        case .track: 4
        }
    }
}
public enum FineControlKey: String, Codable, CaseIterable, Sendable { case option, off }
/// The key held for eighth steps on level sides.
public enum CoarseControlKey: String, Codable, CaseIterable, Sendable { case shift, off }
/// The sound played at each step. Synthesised styles are built in; the others are macOS system sounds.
public enum SoundStyle: String, Codable, CaseIterable, Sendable {
    case softClick, marimba, glass, tink, pop, bottle, morse

    public var title: String {
        switch self {
        case .softClick: "Soft click"
        case .marimba: "Marimba"
        case .glass: "Glass"
        case .tink: "Tink"
        case .pop: "Pop"
        case .bottle: "Bottle"
        case .morse: "Morse"
        }
    }
}

public enum NotchEffect: String, Codable, CaseIterable, Sendable {
    /// Sides with a level light the notch's bottom edge from its left corner to the level, like a
    /// gauge (the right ear shows the number). Other sides send a comet along the edge that a fast
    /// slide feeds rather than crowding it with streaks.
    case levelGauge
    /// A short streak runs along the outline with every step, in the slide's direction.
    case everyStep
    case off
}

/// How strong the trackpad's tap at every step is (Settings → Advanced → Feedback → Haptic feedback),
/// over the stored `hapticsEnabled` switch and `hapticTick`.
public enum HapticStrength: CaseIterable, Sendable {
    case off, soft, medium, strong

    /// The actuator's tap id for this strength; nil when off.
    public var tick: Int32? {
        switch self {
        case .off: nil
        case .soft: 1
        case .medium: 4
        case .strong: 6
        }
    }
}

public enum MuteSignsSide: String, Codable, CaseIterable, Sendable {
    /// Both right of the notch, the sound sign first and the microphone's outermost.
    case right
    /// Both left of the notch, mirrored: the microphone's outermost.
    case left
}

/// What a LEFT click on the menu-bar icon does; a right click does the other.
public enum MenuBarClick: String, Codable, CaseIterable, Sendable { case toggle, openPanel }

public enum CornerAction: Codable, Equatable, Hashable, Sendable {
    case nothing
    case mute
    case muteMicrophone
    case keyCombo(KeyCombo)
    case openApp(path: String)
    case openLink(url: String)
    case runShortcut(name: String)
    case lockScreen
    case missionControl
    /// The current app's windows (App Exposé).
    case appExpose
    case showDesktop
    /// The Apps launcher (Launchpad before macOS 26).
    case showApps
}

public extension CornerAction {
    /// False for Nothing and for an action still waiting for its app, keys, link or Shortcut (or with
    /// a link `OpenLink` refuses): such a corner isn't active, so its clicks stay ordinary clicks.
    var isReady: Bool {
        switch self {
        case .nothing: false
        case .keyCombo(let combo): combo.isSet
        case .openApp(let path): !path.isEmpty
        case .openLink(let url): OpenLink.url(url) != nil
        case .runShortcut(let name): !name.isEmpty
        default: true
        }
    }
}

/// The shortcuts a "Custom keys" side presses: one per step, `up` for sliding up (or right on the
/// top and bottom sides), `down` for the other way. Either can be empty.
public struct CustomKeys: Codable, Equatable, Hashable, Sendable {
    public var up: KeyCombo?
    public var down: KeyCombo?

    public init(up: KeyCombo? = nil, down: KeyCombo? = nil) {
        self.up = up; self.down = down
    }
}

public struct HalodeckSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var sides: [Side: SideAction] = HalodeckSettings.defaultSides
    /// The one-click action of each corner.
    public var corners: [Corner: CornerAction] = HalodeckSettings.defaultCorners
    /// Actions for a double click on a corner, keyed by the click count 2 (none by default).
    public var multiClickCorners: [Corner: [Int: CornerAction]] = [:]
    /// Per side: may a plain swipe (no click) start it? Press-and-slide always works.
    /// Top and bottom swipes follow stricter rules (start right at the border, clearly sideways).
    public var swipeWithoutClick: [Side: Bool] = HalodeckSettings.defaultSwipe
    /// Per side: play sound/haptic ticks for its steps. Off by default for top/bottom, whose actions
    /// (seek, tabs) have no level to show whether anything happened.
    public var ticksEnabled: [Side: Bool] = HalodeckSettings.defaultTicks
    public var customKeys: [Side: CustomKeys] = [:]
    public var hapticsEnabled = true
    public var soundEnabled = false
    public var soundStyle: SoundStyle = .softClick
    /// True when a step can make itself felt or heard at all; with both off the per-side
    /// Feedback switches have nothing to play.
    public var anyFeedback: Bool { hapticsEnabled || soundEnabled }
    public var sideWidthFraction = 0.10
    public var slidePerStepMM = 4.0
    public var fineControlKey: FineControlKey = .option
    public var coarseControlKey: CoarseControlKey = .shift
    public var hapticTick: Int32 = 1
    public var menuBarClick: MenuBarClick = .toggle
    /// Hidden: set brightness through DisplayServices instead of the brightness keys (no indicator).
    public var brightnessDirect = false
    /// Show Halodeck's pill for steps macOS shows nothing for (tabs, seek, tracks).
    public var showIndicator = true
    /// On a MacBook with a notch, the indicator grows out of the notch instead of showing as a pill.
    public var showInNotch = true
    public var notchEffect: NotchEffect = .levelGauge
    public var muteSignsSide: MuteSignsSide = .right

    /// Settings → Advanced → Sound feedback as one choice: nil is Off, otherwise the sound to play.
    /// Off keeps the chosen sound, so turning sound on again brings it back.
    public var soundChoice: SoundStyle? {
        get { soundEnabled ? soundStyle : nil }
        set {
            soundEnabled = newValue != nil
            if let newValue { soundStyle = newValue }
        }
    }

    /// The tap's strength, Off when haptic feedback is off (an unknown saved tap id reads as Soft).
    /// Setting it stores the switch and the tap.
    public var hapticStrength: HapticStrength {
        get {
            guard hapticsEnabled else { return .off }
            return HapticStrength.allCases.first { $0.tick == hapticTick } ?? .soft
        }
        set {
            hapticsEnabled = newValue != .off
            if let tick = newValue.tick { hapticTick = tick }
        }
    }
    public static let sideWidthRange = 0.05...0.20
    public static let slidePerStepRange = 2.0...8.0
    static let defaultSides: [Side: SideAction] = [.left: .brightness, .right: .volume,
                                                     .top: .mediaSeek, .bottom: .customKeys]
    // Every side works on a click and slide; a swipe without a click is opt-in per side in Settings,
    // so a stray swipe near a side changes nothing.
    static let defaultSwipe: [Side: Bool] = [.left: false, .right: false, .top: false, .bottom: false]
    static let defaultTicks: [Side: Bool] = [.left: true, .right: true, .top: false, .bottom: false]
    // The top corners mute; the bottom ones wait for an app and keys of your choosing in Settings.
    static let defaultCorners: [Corner: CornerAction] = [.topLeft: .muteMicrophone, .topRight: .mute,
                                                         .bottomLeft: .openApp(path: ""), .bottomRight: .keyCombo(.unset)]

    public init() {}

    /// Values clamped to their ranges, unknown tick ids reset to 1, missing sides/corners filled with defaults.
    public func sanitized() -> HalodeckSettings {
        var s = self
        s.sideWidthFraction = min(max(sideWidthFraction, Self.sideWidthRange.lowerBound), Self.sideWidthRange.upperBound)
        s.slidePerStepMM = min(max(slidePerStepMM, Self.slidePerStepRange.lowerBound), Self.slidePerStepRange.upperBound)
        s.hapticTick = HapticStrength.allCases.contains { $0.tick == hapticTick } ? hapticTick : 1
        s.sides = Self.defaultSides.merging(sides) { _, mine in mine }
        s.corners = Self.defaultCorners.merging(corners) { _, mine in mine }
        s.swipeWithoutClick = Self.defaultSwipe.merging(swipeWithoutClick) { _, mine in mine }
        s.ticksEnabled = Self.defaultTicks.merging(ticksEnabled) { _, mine in mine }
        return s
    }

    /// One or two clicks: a third would be hard to hit and make every double click wait for it.
    public static let maxCornerClicks = 2

    /// The action for `clicks` quick clicks on a corner (1 = the corner's main action).
    public func cornerAction(_ corner: Corner, clicks: Int) -> CornerAction {
        guard clicks <= Self.maxCornerClicks else { return .nothing }
        return clicks == 1 ? corners[corner] ?? .nothing : multiClickCorners[corner]?[clicks] ?? .nothing
    }

    public mutating func setCornerAction(_ action: CornerAction, for corner: Corner, clicks: Int) {
        guard (1...Self.maxCornerClicks).contains(clicks) else { return }
        if clicks == 1 {
            corners[corner] = action
        } else {
            var extra = multiClickCorners[corner] ?? [:]
            extra[clicks] = action == .nothing ? nil : action
            multiClickCorners[corner] = extra.isEmpty ? nil : extra
        }
    }

    /// The highest click count with an action on this corner; 0 when it has none.
    public func maxClicks(_ corner: Corner) -> Int {
        (1...Self.maxCornerClicks).last { cornerAction(corner, clicks: $0).isReady } ?? 0
    }

    /// The shortcut a "Custom keys" side presses for one step, without Fn (macOS ignores Fn in key
    /// presses an app sends), or nil when that direction has none.
    public func customKey(_ side: Side, up: Bool) -> KeyCombo? {
        guard var combo = up ? customKeys[side]?.up : customKeys[side]?.down else { return nil }
        combo.modifiers &= ~KeyCombo.fnFlag
        return combo
    }

    /// The sides that do something: not Nothing, and a Custom keys side only once it has a shortcut.
    public var activeSides: [Side: SideAction] {
        sides.filter { side, function in
            switch function {
            case .nothing: false
            case .customKeys: customKey(side, up: true) != nil || customKey(side, up: false) != nil
            default: true
            }
        }
    }

    public var activeCorners: Set<Corner> {
        Set(Corner.allCases.filter { maxClicks($0) > 0 })
    }

    // The stored keys predate the code's "side" wording; keep them so saved settings load in every
    // version.
    private enum CodingKeys: String, CodingKey {
        case enabled
        case sides = "edges"
        case corners, multiClickCorners, swipeWithoutClick, ticksEnabled, customKeys
        case hapticsEnabled, soundEnabled, soundStyle
        case sideWidthFraction = "edgeWidthFraction"
        case slidePerStepMM, fineControlKey, coarseControlKey, hapticTick, menuBarClick, brightnessDirect
        case showIndicator, showInNotch, notchEffect, muteSignsSide
    }

    // Decoding is lenient field by field: a missing, malformed or unknown value (an action from a
    // newer version, say) keeps that field's default, and in the per-side and per-corner maps only
    // the entries that don't decode are dropped (`sanitized()` fills in their defaults).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HalodeckSettings()
        enabled = c.lenient(.enabled) ?? d.enabled
        sides = c.lenientMap(.sides) ?? d.sides
        corners = c.lenientMap(.corners) ?? d.corners
        multiClickCorners = (c.lenient(.multiClickCorners) as LenientMap<Corner, LenientMap<Int, CornerAction>>?)
            .map { $0.entries.mapValues(\.entries).filter { !$0.value.isEmpty } } ?? d.multiClickCorners
        swipeWithoutClick = c.lenientMap(.swipeWithoutClick) ?? d.swipeWithoutClick
        ticksEnabled = c.lenientMap(.ticksEnabled) ?? d.ticksEnabled
        customKeys = c.lenientMap(.customKeys) ?? d.customKeys
        hapticsEnabled = c.lenient(.hapticsEnabled) ?? d.hapticsEnabled
        soundEnabled = c.lenient(.soundEnabled) ?? d.soundEnabled
        soundStyle = c.lenient(.soundStyle) ?? d.soundStyle
        sideWidthFraction = c.lenient(.sideWidthFraction) ?? d.sideWidthFraction
        slidePerStepMM = c.lenient(.slidePerStepMM) ?? d.slidePerStepMM
        fineControlKey = c.lenient(.fineControlKey) ?? d.fineControlKey
        coarseControlKey = c.lenient(.coarseControlKey) ?? d.coarseControlKey
        hapticTick = c.lenient(.hapticTick) ?? d.hapticTick
        menuBarClick = c.lenient(.menuBarClick) ?? d.menuBarClick
        brightnessDirect = c.lenient(.brightnessDirect) ?? d.brightnessDirect
        showIndicator = c.lenient(.showIndicator) ?? d.showIndicator
        showInNotch = c.lenient(.showInNotch) ?? d.showInNotch
        notchEffect = c.lenient(.notchEffect) ?? d.notchEffect
        muteSignsSide = c.lenient(.muteSignsSide) ?? d.muteSignsSide
    }
}

/// A dictionary keyed by an enum (or Int) that keeps only the entries whose key and value decode.
private struct LenientMap<Key: Hashable & CodingKeyRepresentable, Value: Decodable>: Decodable {
    var entries: [Key: Value] = [:]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for key in c.allKeys {
            guard let k = Key(codingKey: key), let v = try? c.decode(Value.self, forKey: key) else { continue }
            entries[k] = v
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String, intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; intValue = Int(stringValue) }
        init(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }
}

private extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    func lenientMap<MapKey: Hashable & CodingKeyRepresentable, Value: Decodable>(_ key: Key) -> [MapKey: Value]? {
        (lenient(key) as LenientMap<MapKey, Value>?)?.entries
    }
}
