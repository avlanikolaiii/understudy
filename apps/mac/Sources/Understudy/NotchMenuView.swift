import AppKit
import SwiftUI

/// The black shape around the notch. Where it's wider than the camera housing, its top corners
/// curve outward into the screen edge (the "ears"), so it reads as part of the hardware notch.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottom) }
        set { ear = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let e = min(ear, rect.width / 4), b = min(bottom, rect.height / 2, (rect.width - 2 * e) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + e, y: rect.minY + e), control: CGPoint(x: rect.minX + e, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + e, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + e + b, y: rect.maxY), control: CGPoint(x: rect.minX + e, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - e - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - e, y: rect.maxY - b), control: CGPoint(x: rect.maxX - e, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY + e))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - e, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// What the notch's menu offers: the skills that can run, and ways into the app.
@MainActor
final class NotchMenu: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// Its shortcut, its trigger, or how many steps it has.
        let caption: String
        /// The app it works in, for its icon.
        let bundle: String?
    }

    @Published var items: [Item] = []
    var choose: (UUID) -> Void = { _ in }
    var openApp: () -> Void = {}
    var teach: () -> Void = {}
}

/// The menu that opens out of the notch: a header beside the camera, then the skills as tiles.
/// Choosing one runs it after the countdown. It's all mouse: the notch never takes the keyboard.
struct NotchMenuHeader: View {
    @ObservedObject var menu: NotchMenu
    let dot: NotchActivity.Dot
    let wing: CGFloat
    let gap: CGFloat
    let space: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                NotchDot(style: dot).matchedGeometryEffect(id: "dot", in: space)
                Text("Understudy").font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: wing, alignment: .leading)
            Spacer(minLength: gap)
            HStack(spacing: 6) {
                NotchIconButton(symbol: "plus", label: "Teach a skill", action: menu.teach)
                NotchIconButton(symbol: "macwindow", label: "Open Understudy", action: menu.openApp)
            }
            .frame(maxWidth: wing, alignment: .trailing)
        }
    }
}

struct NotchMenuBody: View {
    static let perRow = 5
    static let limit = 10
    @ObservedObject var menu: NotchMenu
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(menu.items.isEmpty ? "NO SKILLS TO RUN YET" : "RUN A SKILL")
                .font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(NotchStyle.muted)
            if menu.items.isEmpty {
                Button(action: menu.teach) {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle").font(.system(size: 18)).foregroundStyle(NotchStyle.highlight)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Teach a skill").font(.system(size: 12, weight: .semibold))
                            Text("Show Understudy a task once; it learns the steps.")
                                .font(.system(size: 11)).foregroundStyle(NotchStyle.muted)
                        }
                        Spacer()
                    }
                    .padding(12).background(NotchTileBackground(hovered: false))
                }
                .buttonStyle(NotchPressStyle())
            } else {
                // Rows of five, two rows at most; more skills are a tile away in the app.
                let shown = menu.items.count > Self.limit ? Array(menu.items.prefix(Self.limit - 1)) : menu.items
                let more = menu.items.count - shown.count
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(stride(from: 0, to: shown.count + (more > 0 ? 1 : 0), by: Self.perRow)), id: \.self) { start in
                        HStack(spacing: 8) {
                            ForEach(start..<min(start + Self.perRow, shown.count + (more > 0 ? 1 : 0)), id: \.self) { index in
                                if index < shown.count {
                                    NotchSkillTile(item: shown[index]) { menu.choose(shown[index].id) }
                                } else {
                                    NotchMoreTile(count: more, action: menu.openApp)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
    }
}

/// A skill in the menu: its app's icon, its name, and its shortcut or trigger.
struct NotchSkillTile: View {
    /// Five fit across the open menu (560 wide, 16 on each side, 8 between).
    static let size = CGSize(width: 99, height: 108)
    let item: NotchMenu.Item
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                NotchAppIcon(bundle: item.bundle).frame(width: 30, height: 30)
                Text(item.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(item.caption).font(.system(size: 10, design: .monospaced)).foregroundStyle(NotchStyle.muted).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 10)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(NotchTileBackground(hovered: hovered))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(NotchStyle.highlight)
                    .padding(8).opacity(hovered ? 1 : 0)
            }
        }
        .buttonStyle(NotchPressStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { hovered = hovering } }
        .accessibilityLabel("Run \(item.name)")
        .accessibilityHint(item.caption)
    }
}

/// The last tile when there are more skills than fit: it opens them in the app.
struct NotchMoreTile: View {
    let count: Int
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("+\(count)").font(.system(size: 18, weight: .semibold)).frame(height: 30)
                Text("More skills").font(.system(size: 11, weight: .semibold))
                Text("in Understudy").font(.system(size: 10, design: .monospaced)).foregroundStyle(NotchStyle.muted)
            }
            .padding(.vertical, 10)
            .frame(width: NotchSkillTile.size.width, height: NotchSkillTile.size.height)
            .background(NotchTileBackground(hovered: hovered))
        }
        .buttonStyle(NotchPressStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { hovered = hovering } }
        .accessibilityLabel("\(count) more skills in Understudy")
    }
}

/// Tiles are a shade lighter than the black around them, and lighter still under the pointer.
struct NotchTileBackground: View {
    let hovered: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(hovered ? 0.12 : 0.06))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(hovered ? 0.14 : 0.05)))
    }
}

struct NotchIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(hovered ? 0.16 : 0.08)))
        }
        .buttonStyle(NotchPressStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { hovered = hovering } }
        .accessibilityLabel(label)
    }
}

/// A small press-in, like NotchNook's controls.
struct NotchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The icon of the app a skill works in, or a generic one.
struct NotchAppIcon: View {
    let bundle: String?
    var body: some View {
        if let bundle, let icon = Self.icon(bundle) {
            Image(decorative: icon, scale: 2).resizable().interpolation(.high)
        } else {
            Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(NotchStyle.highlight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
        }
    }
}

extension NotchAppIcon {
    @MainActor private static var cache: [String: CGImage] = [:]

    /// App icons come in a deep format that switches SwiftUI's drawing of the whole menu into
    /// 16-bit linear color (captures come out too dark). Each is drawn once into 8-bit sRGB.
    @MainActor static func icon(_ bundle: String) -> CGImage? {
        if let cached = cache[bundle] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let side = 64
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSWorkspace.shared.icon(forFile: url.path).draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let image = context.makeImage()
        cache[bundle] = image
        return image
    }
}
