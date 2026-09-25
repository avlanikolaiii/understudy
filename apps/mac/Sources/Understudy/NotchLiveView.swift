import SwiftUI

/// The landing page's notch colors (`--notch*` tokens).
enum NotchStyle {
    static let ink = Color(red: 0.949, green: 0.953, blue: 0.961)        // #F2F3F5
    static let muted = Color(red: 0.604, green: 0.631, blue: 0.682)      // #9AA1AE
    static let ok = Color(red: 0.498, green: 0.824, blue: 0.608)         // #7FD29B
    static let hold = Color(red: 0.949, green: 0.643, blue: 0.553)       // #F2A48D
    static let highlight = Color(red: 0.957, green: 0.773, blue: 0.204)  // #F4C534
    static let rehearse = Color(red: 0.561, green: 0.722, blue: 1.0)     // #8FB8FF
    static let script = Font.custom("Courier New", size: 12)
    static let openWidth: CGFloat = 440
    static let menuWidth: CGFloat = 560
    /// The outward curves where the shape meets the top edge, like the hardware notch's.
    static let openEar: CGFloat = 12
    static let hoverEar: CGFloat = 6
    static let closedRadius: CGFloat = 13
    static let openRadius: CGFloat = 22
    /// The page's `cubic-bezier(.3,.9,.3,1)` over 0.5 s, as a spring.
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)

    static func color(_ tone: NotchRow.Tone) -> Color {
        switch tone {
        case .plain: ink
        case .said: highlight
        case .ok: ok
        case .hold: hold
        }
    }
}

@MainActor
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var hovering = false
}

/// The glowing dot. It pulses while watching (1 → 0.35 opacity every 1.4 s) and turns blue while rehearsing.
struct NotchDot: View {
    let style: NotchActivity.Dot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = style == .rehearse ? NotchStyle.rehearse : NotchStyle.highlight
        let pulsing = style == .pulse && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulsing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle().fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.7), radius: 4)
                .opacity(pulsing ? 0.675 + 0.325 * cos(2 * .pi * t / 1.4) : 1)
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)
    }
}

/// A black shape around the notch. At rest it's exactly the camera housing's size, so only the
/// hardware shows; under the pointer it widens a little and shows the dot. It opens into the live
/// strip when something is happening, and into the menu when clicked.
///
/// The black is pure #000000 and opaque: no material, tint, or shadow. On an LCD the backlight
/// still lights it faintly, which is why it stays hidden behind the hardware at rest.
struct NotchLiveView: View {
    @ObservedObject var activity: NotchActivity
    @ObservedObject var state: NotchState
    @ObservedObject var menu: NotchMenu
    let notchSize: CGSize
    let hasNotch: Bool
    let onTap: () -> Void
    @Namespace private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var open: Bool { state.expanded }
    private var isMenu: Bool { activity.mode == .menu }
    private var bandHeight: CGFloat { hasNotch ? notchSize.height : 30 }
    /// At rest: the housing exactly. Under the pointer: room for the dot beside it.
    private var pillWidth: CGFloat { hasNotch ? notchSize.width + (state.hovering ? 64 : 0) : 200 }
    private var openWidth: CGFloat { isMenu ? NotchStyle.menuWidth : NotchStyle.openWidth }
    private var ear: CGFloat { !hasNotch ? 0 : open ? NotchStyle.openEar : state.hovering ? NotchStyle.hoverEar : 0 }
    /// The space beside the camera housing on each side, when open.
    private var wing: CGFloat { hasNotch ? (openWidth - notchSize.width) / 2 - 16 : .infinity }

    var body: some View {
        let shape = NotchShape(ear: ear, bottom: open ? NotchStyle.openRadius : NotchStyle.closedRadius)
        VStack(alignment: .leading, spacing: 0) {
            head.frame(height: bandHeight)
            if open {
                Group {
                    if isMenu { NotchMenuBody(menu: menu) } else { content }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, open ? 16 : state.hovering ? 12 : 0)
        .frame(width: open ? openWidth : pillWidth, alignment: .top)
        .padding(.horizontal, ear)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : NotchStyle.spring) { state.hovering = hovering }
        }
        .foregroundStyle(NotchStyle.ink)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(activity.mode == .idle ? "Shows your skills" : "Opens Understudy")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onTap() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var head: some View {
        if open && isMenu {
            NotchMenuHeader(menu: menu, dot: activity.dot, wing: wing, gap: hasNotch ? notchSize.width : 8, space: space)
        } else if open {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    NotchDot(style: activity.dot).matchedGeometryEffect(id: "dot", in: space)
                    Text(activity.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                .frame(maxWidth: wing, alignment: .leading)
                Spacer(minLength: hasNotch ? notchSize.width : 8)
                Text(activity.meta).font(NotchStyle.script).monospacedDigit()
                    .foregroundStyle(NotchStyle.muted).lineLimit(1)
                    .frame(maxWidth: wing, alignment: .trailing)
            }
        } else {
            HStack {
                Spacer()
                NotchDot(style: activity.dot).matchedGeometryEffect(id: "dot", in: space)
                    .opacity(state.hovering || !hasNotch ? 1 : 0)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let detail = activity.detail {
                Text(detail).font(.system(size: 12, weight: .semibold)).lineLimit(1).padding(.bottom, 2)
            }
            ForEach(activity.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.app).foregroundStyle(NotchStyle.muted).frame(width: 66, alignment: .leading)
                    Text(row.text).foregroundStyle(NotchStyle.color(row.tone)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let end = row.end { Text(end).foregroundStyle(NotchStyle.color(row.endTone)).lineLimit(1) }
                }
                .font(NotchStyle.script)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)), removal: .opacity))
            }
            if !activity.footer.isEmpty {
                Text(activity.footer).font(.system(size: 10)).foregroundStyle(NotchStyle.muted).padding(.top, 4)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: activity.rows)
    }

    private var accessibilityText: String {
        guard activity.mode != .idle else { return "Understudy" }
        return (["Understudy", activity.label, activity.detail ?? "", activity.meta, activity.footer]).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
