import ABSCore
import SwiftUI

/// `ui-btn`: rounded-md, gray-600 border, shadow, white/10 overlay on hover.
struct WebButton<Label: View>: View {
  var color: Color = Theme.primary
  var small = false
  var disabled = false
  var paddingX: CGFloat?
  var paddingY: CGFloat?
  let action: () -> Void
  @ViewBuilder var label: () -> Label
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      label()
        .font(Theme.sans(small ? 14 : 16))
        .foregroundStyle(.white)
        .padding(.horizontal, paddingX ?? (small ? 16 : 32))
        .padding(.vertical, paddingY ?? (small ? 4 : 8))
        .background(color)
        .overlay(hover && !disabled ? Color.white.opacity(0.1) : .clear)
        .overlay(disabled ? Color.black.opacity(0.2) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.gray600, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .onHover { hover = $0 }
  }
}

extension WebButton where Label == Text {
  init(
    _ title: String, color: Color = Theme.primary, small: Bool = false, disabled: Bool = false,
    action: @escaping () -> Void
  ) {
    self.init(color: color, small: small, disabled: disabled, action: action) { Text(title) }
  }
}

/// `ui-icon-btn`: square bordered icon button.
struct IconButton: View {
  let icon: String
  var size: CGFloat = 36
  var iconSize: CGFloat = 20
  var bg: Color = Theme.primary
  var disabled = false
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      Icon(icon, size: iconSize)
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(bg)
        .overlay(hover && !disabled ? Color.white.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.gray600, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.5 : 1)
    .onHover { hover = $0 }
  }
}

/// Plain icon that brightens on hover (player and toolbar icons).
struct HoverIcon: View {
  let icon: String
  var size: CGFloat = 24
  var filled = false
  var color: Color = Theme.gray300
  var hoverColor: Color = .white
  var disabled = false
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      Icon(icon, size: size, filled: filled)
        .foregroundStyle(disabled ? Theme.gray500 : (hover ? hoverColor : color))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .onHover { hover = $0 }
  }
}

/// `modals-modal`: full-window dimmed backdrop, header top-left, ✕ top-right,
/// the content card centered. Esc or a click on the backdrop closes it.
struct WebModal<Content: View>: View {
  let title: String
  let width: CGFloat
  @Binding var isPresented: Bool
  @ViewBuilder var content: () -> Content

  var body: some View {
    ZStack {
      Theme.primary.opacity(0.75)
        .overlay(alignment: .top) {
          LinearGradient(
            colors: [Theme.black500.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom
          )
          .frame(height: 144)
          .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isPresented = false }
      VStack(spacing: 0) {
        content()
      }
      .frame(width: width)
      .frame(minWidth: 380)
      .environment(\.colorScheme, .dark)
    }
    .overlay(alignment: .topLeading) {
      Text(title)
        .font(Theme.sans(30))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(20)
        .allowsHitTesting(false)
    }
    .overlay(alignment: .topTrailing) {
      HoverIcon(icon: "close", size: 36, color: Theme.gray200) { isPresented = false }
        .padding(20)
    }
    .transition(.opacity)
  }
}

/// Bottom-right stack of toasts (vue-toastification look).
struct ToastStack: View {
  let toasts: [Toast]

  var body: some View {
    VStack(alignment: .trailing, spacing: 8) {
      ForEach(toasts) { t in
        HStack(spacing: 10) {
          Icon(icon(t.kind), size: 20).foregroundStyle(.white)
          Text(t.text).font(Theme.sans(15)).foregroundStyle(.white).fixedSize(
            horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 380, alignment: .leading)
        .background(color(t.kind))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .onTapGesture { AppModel.shared.toasts.removeAll { $0.id == t.id } }
      }
    }
    .padding(16)
    .animation(.easeOut(duration: 0.2), value: toasts)
  }

  func color(_ k: Toast.Kind) -> Color {
    switch k {
    case .info: return Theme.info
    case .success: return Theme.success
    case .warning: return Theme.warning
    case .error: return Theme.error
    }
  }

  func icon(_ k: Toast.Kind) -> String {
    switch k {
    case .info: return "info"
    case .success: return "check_circle"
    case .warning: return "warning"
    case .error: return "error"
    }
  }
}

/// Tailwind-ish hover highlight for rows.
struct HoverHighlight: ViewModifier {
  var color: Color = Theme.primary.opacity(0.3)
  @State private var hover = false
  func body(content: Content) -> some View {
    content.background(hover ? color : .clear).onHover { hover = $0 }
  }
}

extension View {
  func hoverHighlight(_ c: Color = Theme.primary.opacity(0.3)) -> some View {
    modifier(HoverHighlight(color: c))
  }

  /// Pointing-hand cursor for clickable text, like links on the web.
  func linkCursor() -> some View {
    pointerStyle(.link)
  }
}

/// Remembers a page's vertical scroll offset per route, so Back returns to
/// the same place (the web keeps the bookshelf scroll the same way).
@MainActor
final class ScrollMemory {
  static let shared = ScrollMemory()
  var offsets: [Route: CGFloat] = [:]
}

private struct RestoresScroll: ViewModifier {
  let route: Route
  @State private var position = ScrollPosition(edge: .top)
  @State private var restored = false

  func body(content: Content) -> some View {
    content
      .scrollPosition($position)
      .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
        if restored { ScrollMemory.shared.offsets[route] = y }
      }
      .task {
        let y = ScrollMemory.shared.offsets[route] ?? 0
        if y > 1 {
          // Lazy content needs a layout pass before the offset exists.
          try? await Task.sleep(for: .milliseconds(30))
          position.scrollTo(y: y)
        }
        restored = true
      }
  }
}

extension View {
  func restoresScroll(_ route: Route) -> some View { modifier(RestoresScroll(route: route)) }
}
