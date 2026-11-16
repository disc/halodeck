import AppKit
import HalodeckCore
import Observation
import SwiftUI

enum CornerKind: String, CaseIterable, Identifiable {
    case mute, muteMicrophone
    case missionControl, appExpose, showDesktop, showApps, lockScreen
    case keyCombo, openApp, openLink, runShortcut
    case nothing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nothing: "Nothing"
        case .mute: "Mute sound"
        case .muteMicrophone: "Mute microphone"
        case .keyCombo: "Key combination"
        case .openApp: "Open app"
        case .openLink: "Open link"
        case .runShortcut: "Run Shortcut"
        case .missionControl: "Mission Control"
        case .appExpose: "App windows"
        case .showDesktop: "Show desktop"
        case .showApps: "Show apps"
        case .lockScreen: "Lock screen"
        }
    }

    init(_ action: CornerAction) {
        switch action {
        case .nothing: self = .nothing
        case .mute: self = .mute
        case .muteMicrophone: self = .muteMicrophone
        case .keyCombo: self = .keyCombo
        case .openApp: self = .openApp
        case .openLink: self = .openLink
        case .runShortcut: self = .runShortcut
        case .missionControl: self = .missionControl
        case .appExpose: self = .appExpose
        case .showDesktop: self = .showDesktop
        case .showApps: self = .showApps
        case .lockScreen: self = .lockScreen
        }
    }

    var defaultAction: CornerAction {
        switch self {
        case .nothing: .nothing
        case .mute: .mute
        case .muteMicrophone: .muteMicrophone
        case .keyCombo: .keyCombo(.unset)   // the row asks you to record the keys
        case .openApp: .openApp(path: "")
        case .openLink: .openLink(url: "")
        case .runShortcut: .runShortcut(name: "")
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .showDesktop: .showDesktop
        case .showApps: .showApps
        case .lockScreen: .lockScreen
        }
    }
}

struct CornersSection: View {
    @ObservedObject var store: SettingsStore
    @Binding var selection: ZoneSelection?
    private let shortcuts = ShortcutsLibrary.shared
    /// Which click count (1 or 2) each corner's row is showing.
    @State private var clickTab: [Corner: Int] = [:]

    private let order: [Corner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
            GridRow {
                TableHeader(title: "Corner")
                TableHeader(title: "Clicks")
                TableHeader(title: "Action")
                TableHeader(title: "Details")
            }
            .padding(.vertical, 10)
            ForEach(order, id: \.self) { corner in
                Divider().gridCellUnsizedAxes(.horizontal)
                row(corner)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .settingsCard(clipsContent: true)

        Text("Clicking a corner that has an action runs the action instead of an ordinary click. If the corner also has a 2× action, a single click waits as long as your double-click speed before it runs.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func clicks(_ corner: Corner) -> Int { clickTab[corner] ?? 1 }

    private func action(_ corner: Corner) -> CornerAction {
        store.settings.cornerAction(corner, clicks: clicks(corner))
    }

    private func set(_ corner: Corner, _ action: CornerAction) {
        store.settings.setCornerAction(action, for: corner, clicks: clicks(corner))
    }

    private func clickTabs(_ corner: Corner) -> some View {
        HStack(spacing: 4) {
            ForEach(1...HalodeckSettings.maxCornerClicks, id: \.self) { n in
                let selected = clicks(corner) == n
                let assigned = store.settings.cornerAction(corner, clicks: n).isReady
                Button { clickTab[corner] = n } label: {
                    Text("\(n)×")
                        .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(selected ? Color.white : assigned ? Theme.accent : Color.secondary)
                        .frame(width: 30, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? Theme.accent : Color.primary.opacity(0.06)))
                        .overlay(alignment: .topTrailing) {
                            if assigned && !selected {
                                Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(x: -3, y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(n == 1 ? "One click" : "\(n) quick clicks")
                .accessibilityLabel("\(n) clicks\(assigned ? ", has an action" : "")")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func row(_ corner: Corner) -> some View {
        let current = action(corner)
        let live = store.settings.maxClicks(corner) > 0 && store.settings.enabled
        GridRow {
            HStack(spacing: 10) {
                SideGlyph(corners: [corner], highlight: live ? Theme.accent : .secondary)
                Text(corner.title.replacingOccurrences(of: " corner", with: "")).fontWeight(.medium)
                    .foregroundStyle(selection == .corner(corner) ? Theme.accent : .primary)
            }
            .frame(minWidth: 110, alignment: .leading)
            clickTabs(corner)
            kindMenu(corner, current)
            // Fixed height: the details differ (text, key recorder, app button), and switching
            // between 1×/2× must not make the row jump.
            detail(corner, current)
                .frame(minWidth: 150, maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { selection = .corner(corner) }
        .id(ZoneSelection.corner(corner))
    }

    private func kindMenu(_ corner: Corner, _ current: CornerAction) -> some View {
        let kind = CornerKind(current)
        return Menu {
            ForEach(CornerKind.allCases) { k in
                if k == .missionControl || k == .keyCombo || k == .nothing { Divider() }
                Button {
                    if k != CornerKind(action(corner)) { set(corner, k.defaultAction) }
                } label: { Label(k.title, systemImage: Theme.symbol(for: k.defaultAction)) }
            }
        } label: {
            Label(kind.title, systemImage: Theme.symbol(for: current))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(current == .nothing ? .secondary : Theme.accent)
        .padding(.leading, 10).padding(.trailing, 26).padding(.vertical, 5)
        .frame(width: 175, alignment: .leading)
        .actionMenuChrome()
        .accessibilityLabel("\(corner.title) action: \(kind.title)")
    }

    @ViewBuilder private func detail(_ corner: Corner, _ current: CornerAction) -> some View {
        switch current {
        case let .keyCombo(combo):
            CompactKeyRecorder(combo: Binding(get: { combo.isSet ? combo : nil }, set: { if let c = $0 { set(corner, .keyCombo(c)) } }),
                               onClear: { set(corner, .nothing) })
        case let .openApp(path):
            Button { chooseApp(for: corner) } label: {
                HStack(spacing: 6) {
                    if path.isEmpty {
                        Image(systemName: "plus.app").foregroundStyle(.secondary)
                        Text("Choose app…")
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                        Text(FileManager.default.displayName(atPath: path)).lineLimit(1)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        case let .openLink(url):
            // A refused link (not http, https or mailto) is outlined in red and never runs: the corner
            // isn't ready (`CornerAction.isReady`), so its clicks stay ordinary clicks.
            let refused = !url.isEmpty && OpenLink.url(url) == nil
            TextField("https://", text: Binding(get: { url }, set: { set(corner, .openLink(url: $0)) }))
                .textFieldStyle(.roundedBorder)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .systemRed), lineWidth: refused ? 1.2 : 0))
                .help(refused ? "Only http, https and mailto links can be opened" : "")
                .accessibilityHint(refused ? "Only http, https and mailto links can be opened" : "")
        case let .runShortcut(name):
            Menu {
                if shortcuts.names.isEmpty {
                    Text(shortcuts.isLoading ? "Loading shortcuts…" : "No shortcuts in the Shortcuts app")
                }
                ForEach(shortcuts.names, id: \.self) { n in
                    Button(n) { set(corner, .runShortcut(name: n)) }
                }
            } label: {
                Text(name.isEmpty ? "Choose Shortcut…" : name)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            // Read once, the first time a corner runs a Shortcut; again when Halodeck comes back to
            // the front (a shortcut may have been added in the Shortcuts app meanwhile).
            .onAppear { shortcuts.loadIfNeeded() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                shortcuts.reload()
            }
        case .nothing:
            Text(clicks(corner) == 1 ? "Ordinary click" : "Not set").foregroundStyle(.secondary)
        case .mute:
            Text("System indicator").foregroundStyle(.secondary)
        case .muteMicrophone:
            Text("On-screen indicator").foregroundStyle(.secondary)
        case .missionControl:
            Text("All open windows").foregroundStyle(.secondary)
        case .appExpose:
            Text("Windows of the app in front").foregroundStyle(.secondary)
        case .showDesktop:
            Text("Moves windows aside").foregroundStyle(.secondary)
        case .showApps:
            Text("The Apps launcher").foregroundStyle(.secondary)
        case .lockScreen:
            Text("Locks right away").foregroundStyle(.secondary)
        }
    }

    private func chooseApp(for corner: Corner) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            set(corner, .openApp(path: url.path))
        }
    }
}

extension Corner {
    var title: String {
        switch self {
        case .topLeft: "Top-left corner"
        case .topRight: "Top-right corner"
        case .bottomLeft: "Bottom-left corner"
        case .bottomRight: "Bottom-right corner"
        }
    }
}

@MainActor
@Observable
final class ShortcutsLibrary {
    static let shared = ShortcutsLibrary()

    private(set) var names: [String] = []
    private(set) var isLoading = false
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func loadIfNeeded() {
        guard !loaded else { return }
        reload()
    }

    func reload() {
        task?.cancel()
        isLoading = true
        task = Task { [weak self] in
            let names = await Self.list()
            guard let self, !Task.isCancelled else { return }
            if let names { self.names = names }
            loaded = true
            isLoading = false
            task = nil
        }
    }

    /// `shortcuts list`, sorted; nil if it couldn't run. Cancelling the task stops the process.
    nonisolated private static func list() async -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let running = RunningProcess(process)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[String]?, Never>) in
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                // Read to the end off the main thread (the pipe must be drained or a long list blocks
                // the process), then wait for it to exit.
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    running.process.waitUntilExit()
                    guard running.process.terminationStatus == 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let names = String(decoding: data, as: UTF8.self)
                        .split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
                    continuation.resume(returning: names)
                }
            }
        } onCancel: {
            running.terminate()
        }
    }

    /// The `shortcuts` process, shared with the cancellation handler (which may run on any thread).
    private final class RunningProcess: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func terminate() { if process.isRunning { process.terminate() } }
    }
}
