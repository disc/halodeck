import AppKit
import HalodeckCore
import SwiftUI

/// The Settings window's tabs, in toolbar order.
enum SettingsTab: Int, CaseIterable {
    case bindings, advanced, about

    var title: String {
        switch self {
        case .bindings: "Bindings"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .bindings: "rectangle.and.hand.point.up.left"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private let engine: Engine
    private let updates: UpdateService
    private var tabs: SettingsTabViewController?
    private(set) var window: NSWindow?

    init(store: SettingsStore, engine: Engine, updates: UpdateService = .shared) {
        self.store = store
        self.engine = engine
        self.updates = updates
    }

    func show(tab: SettingsTab = .bindings) {
        let window = prepareWindow(tab: tab)
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window once (without showing it) and selects `tab`. Snapshots use it directly.
    func prepareWindow(tab: SettingsTab, maxPageHeight: CGFloat = Metrics.settingsMaxPageHeight,
                       fitsScreen: Bool = true) -> NSWindow {
        if let window, let tabs {
            tabs.select(tab)
            return window
        }
        let tabs = SettingsTabViewController()
        tabs.fitsScreen = fitsScreen
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []   // switch tabs instantly; the window resize is the only animation
        for t in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: page(t, tabs: tabs, maxPageHeight: maxPageHeight))
            hosting.sizingOptions = [.preferredContentSize]   // the window follows the page's height
            hosting.title = t.title
            let item = NSTabViewItem(viewController: hosting)
            item.label = t.title
            item.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Metrics.settingsWidth, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.contentViewController = tabs   // the window takes the selected tab's title
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        // Lay every page out at the window's width now, so each knows its height before it is shown.
        for item in tabs.tabViewItems {
            guard let view = item.viewController?.view else { continue }
            view.frame.size = NSSize(width: Metrics.settingsWidth, height: maxPageHeight)
            view.layoutSubtreeIfNeeded()
        }
        tabs.select(tab)
        tabs.fitWindow(animated: false)
        self.window = window
        self.tabs = tabs
        return window
    }

    private func page(_ tab: SettingsTab, tabs: SettingsTabViewController, maxPageHeight: CGFloat) -> AnyView {
        let content: AnyView = switch tab {
        case .bindings:
            AnyView(BindingsPage(store: store, engine: engine) { [weak tabs] in tabs?.select(.advanced) })
        case .advanced:
            AnyView(AdvancedPage(store: store, engine: engine))
        case .about:
            AnyView(AboutPage(updates: updates))
        }
        return AnyView(SettingsTabPage(maxHeight: maxPageHeight) { content })
    }
}

@MainActor
final class SettingsTabViewController: NSTabViewController {
    /// Keep the window within the screen's visible height (off only for full-length snapshots).
    var fitsScreen = true

    func select(_ tab: SettingsTab) {
        selectedTabViewItemIndex = tab.rawValue
        selectionChanged()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        selectionChanged()
    }

    private var selectedItem: NSTabViewItem? {
        tabViewItems.indices.contains(selectedTabViewItemIndex) ? tabViewItems[selectedTabViewItemIndex] : nil
    }

    private func selectionChanged() {
        if let selectedItem { view.window?.title = selectedItem.label }
        fitWindow(animated: view.window?.isVisible == true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard selectedItem?.viewController === viewController else { return }
        fitWindow(animated: view.window?.isVisible == true)
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window, let page = selectedItem?.viewController else { return }
        var height = page.preferredContentSize.height
        guard height > 0 else { return }
        let chrome = window.frameRect(forContentRect: .zero).height
        if fitsScreen, let screen = window.screen ?? NSScreen.main {
            height = min(height, screen.visibleFrame.height - chrome - 40)
        }
        let size = NSSize(width: Metrics.settingsWidth, height: height.rounded())
        preferredContentSize = size   // the window also sizes itself to this when it lays out
        guard window.contentLayoutRect.size != size else { return }
        var frame = window.frame
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.y += frame.height - newFrame.height   // keep the top edge where it is
        frame.size = newFrame.size
        window.setFrame(frame, display: true, animate: animated)
    }
}
