import SwiftUI

/// One Settings tab. Its preferred height is the content's, up to `maxHeight`; taller content scrolls.
struct SettingsTabPage<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content
    /// The content's height, measured; starts at the limit so the first layout isn't tiny.
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: Metrics.settingsWidth, idealHeight: min(contentHeight ?? maxHeight, maxHeight))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toggleStyle(GlowSwitchStyle())
        .tint(Theme.accent)   // checkboxes, pickers and sliders share the switches' colour
    }
}

struct SettingsBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        _VariadicView.Tree(DividedRows()) { content }
            .settingsCard()
    }
}

/// Lays rows out top to bottom with a hairline between them (works on macOS 14).
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                if child.id != children.first?.id { Divider() }
                child
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct TableHeader: View {
    var title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.top, 8).padding(.leading, 4)
    }
}

extension View {
    /// Pop-up menus need an explicit width in this window, or AppKit collapses them to one letter.
    func settingsPopUp(width: CGFloat = 180) -> some View {
        frame(width: width)
    }

    /// `clipsContent` also clips the content to its shape (the tables).
    @ViewBuilder func settingsCard(clipsContent: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let fill = shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        let edge = shape.strokeBorder(Color.primary.opacity(0.09))
        if clipsContent {
            background(fill).clipShape(shape).overlay(edge)
        } else {
            background(fill).overlay(edge)
        }
    }

    /// The capsule round a table's action menu, with its up-down chevron. (macOS drops styling inside
    /// a menu's label, so they are drawn around it.)
    func actionMenuChrome() -> some View {
        background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
    }
}
