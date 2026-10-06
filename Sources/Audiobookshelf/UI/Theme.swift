import AppKit
import CoreText
import SwiftUI

/// Design tokens from client/assets/tailwind.css (@theme) and app.css, read
/// from the active palette. Views read them in `body`, so Observation redraws
/// whatever uses a token when the palette changes.
enum Theme {
  private static var p: Palette { ThemeStore.shared.palette }

  static var bg: Color { p.bg }
  static var primary: Color { p.primary }
  /// Text and icons on the app's own surfaces (white in the dark palettes).
  static var ink: Color { p.ink }
  static var accent: Color { p.accent }
  static var error: Color { p.error }
  static var info: Color { p.info }
  static var success: Color { p.success }
  static var warning: Color { p.warning }
  static var yellow400: Color { p.yellow400 }
  static var yellow300: Color { p.yellow300 }
  static var gray100: Color { p.gray[0] }
  static var gray200: Color { p.gray[1] }
  static var gray300: Color { p.gray[2] }
  static var gray400: Color { p.gray[3] }
  static var gray500: Color { p.gray[4] }
  static var gray600: Color { p.gray[5] }
  static var gray700: Color { p.gray[6] }
  static var black300: Color { p.black300 }
  static var black400: Color { p.black400 }
  static var link: Color { p.link }
  static let seriesBadge = Color(
    red: 0xCD / 255, green: 0x9D / 255, blue: 0x49 / 255, opacity: 0xDD / 255)
  static var tableBorder: Color { p.tableBorder }
  static var tableEven: Color { p.tableEven }
  /// `#bookshelf` / `#page-wrapper` background.
  static var pageGradient: LinearGradient { p.pageGradient }
  static var isDark: Bool { p.isDark }
  static var scheme: ColorScheme { p.isDark ? .dark : .light }
  /// Dark glyphs on the white play disc drawn over cover art, any palette.
  static let onLight = Color(hex: 0x232323)

  /// White or the palette's dark ink, whichever reads on `fill`.
  static func ink(on fill: Color) -> Color {
    guard let c = NSColor(fill).usingColorSpace(.sRGB) else { return .white }
    let l = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    return l > 0.6 ? (p.isDark ? Color(hex: 0x1C1C1E) : p.ink) : .white
  }

  static let railWidth: CGFloat = 72
  static let toolbarHeight: CGFloat = 40
  static let appBarHeight: CGFloat = 52
  static let playerHeight: CGFloat = 96

  // MARK: Fonts

  /// The web's Source Sans sizes, drawn in the system font. SF runs larger at
  /// the same point size, so 0.92 keeps the web's layout metrics.
  static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: (size * 0.92).rounded(), weight: weight == .bold ? .semibold : weight)
  }

  static func mono(_ size: CGFloat) -> Font { .custom("UbuntuMono-Regular", size: size) }

  static func registerFonts() {
    guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
    let urls =
      (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    for url in urls where url.pathExtension == "ttf" {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}

/// One colour scheme. The stock palette is the web client's exact values;
/// Nord, Catppuccin and Latte follow those MIT-licensed schemes; Light, Space
/// and Princess are our own. All map onto the same roles, with the grey ramp
/// mixed from text and background so contrast steps match the original.
struct Palette: Identifiable, Equatable {
  let id: String
  let name: String
  let credit: String?
  let isDark: Bool
  let bg, primary, ink, accent, link, yellow400, yellow300: Color
  let error, info, success, warning: Color
  let gray: [Color]
  let black300, black400, tableBorder, tableEven: Color
  let pageGradient: LinearGradient
  let swatch: [Color]

  static func == (a: Palette, b: Palette) -> Bool { a.id == b.id }

  static let audiobookshelf = Palette(
    id: "audiobookshelf", name: "Audiobookshelf", credit: nil, isDark: true,
    bg: Color(hex: 0x373838), primary: Color(hex: 0x232323), ink: .white,
    accent: Color(hex: 0x1AD691), link: Color(hex: 0x5985FF),
    yellow400: Color(hex: 0xFDC700), yellow300: Color(hex: 0xFFDF20),
    error: Color(hex: 0xFF5252), info: Color(hex: 0x2196F3), success: Color(hex: 0x4CAF50),
    warning: Color(hex: 0xFB8C00),
    gray: [0xF3F4F6, 0xE5E7EB, 0xD1D5DC, 0x99A1AF, 0x6A7282, 0x4A5565, 0x364153].map {
      Color(hex: $0)
    },
    black300: Color(hex: 0x444444), black400: Color(hex: 0x333333),
    tableBorder: Color(hex: 0x474747), tableEven: Color(hex: 0x2E2E2E),
    pageGradient: LinearGradient(
      colors: [
        0x2E2E2E, 0x303030, 0x313131, 0x333333, 0x353535, 0x343434, 0x323232, 0x313131,
        0x2C2C2C, 0x282828, 0x232323, 0x1F1F1F,
      ]
      .map { Color(hex: $0) },
      startPoint: .topLeading, endPoint: .bottomTrailing),
    swatch: [0x373838, 0x232323, 0x1AD691, 0xFDC700].map { Color(hex: $0) })

  static let all: [Palette] = [
    audiobookshelf,
    make(
      "light", "Light", nil, dark: false, bg: 0xF2F2F1, primary: 0xFFFFFF, ink: 0x1C1C1E,
      accent: 0x0E9F6E, link: 0x2F5BEA, yellow: 0xD99A00, error: 0xD32F2F, info: 0x1976D2,
      success: 0x2E7D32, warning: 0xE67700, gradient: (0xFAFAF9, 0xEBEBEA)),
    make(
      "space", "Space", "Tokyo Night accents", dark: true, bg: 0x15132B, primary: 0x0C0B1A,
      ink: 0xD6DCFF, accent: 0x7DCFFF, link: 0xBB9AF7, yellow: 0xE0AF68, error: 0xF7768E,
      info: 0x7AA2F7, success: 0x9ECE6A, warning: 0xFF9E64, gradient: (0x251B4D, 0x09091A)),
    make(
      "nord", "Nord", "Nord", dark: true, bg: 0x3B4252, primary: 0x2E3440, ink: 0xECEFF4,
      accent: 0x88C0D0, link: 0x81A1C1, yellow: 0xEBCB8B, error: 0xBF616A, info: 0x5E81AC,
      success: 0xA3BE8C, warning: 0xD08770, gradient: (0x394050, 0x2A2F3A)),
    make(
      "mocha", "Catppuccin", "Catppuccin Mocha", dark: true, bg: 0x1E1E2E, primary: 0x181825,
      ink: 0xCDD6F4, accent: 0xCBA6F7, link: 0x89B4FA, yellow: 0xF9E2AF, error: 0xF38BA8,
      info: 0x89B4FA, success: 0xA6E3A1, warning: 0xFAB387, gradient: (0x1E1E2E, 0x11111B)),
    make(
      "latte", "Latte", "Catppuccin Latte", dark: false, bg: 0xDCE0E8, primary: 0xE6E9EF,
      ink: 0x4C4F69, accent: 0x8839EF, link: 0x1E66F5, yellow: 0xDF8E1D, error: 0xD20F39,
      info: 0x1E66F5, success: 0x40A02B, warning: 0xFE640B, gradient: (0xE6E9EF, 0xCCD0DA)),
    make(
      "princess", "Princess", nil, dark: false, bg: 0xF1D3E0, primary: 0xFAE8F0,
      ink: 0x4A2141, accent: 0xC2185B, link: 0x8E44AD, yellow: 0xD4880F, error: 0xB3261E,
      info: 0x6A4C93, success: 0x2E7D5B, warning: 0xC56A1A, gradient: (0xF7E1EB, 0xE9C3D4)),
  ]

  static func named(_ id: String?) -> Palette? { all.first { $0.id == id } }

  private static func make(
    _ id: String, _ name: String, _ credit: String?, dark: Bool, bg: UInt32, primary: UInt32,
    ink: UInt32, accent: UInt32, link: UInt32, yellow: UInt32, error: UInt32, info: UInt32,
    success: UInt32, warning: UInt32, gradient: (UInt32, UInt32)
  ) -> Palette {
    // Where the stock greys sit between white text and the page, 0 = text.
    let steps = [0.06, 0.12, 0.2, 0.42, 0.58, 0.72, 0.82]
    return Palette(
      id: id, name: name, credit: credit, isDark: dark,
      bg: Color(hex: bg), primary: Color(hex: primary), ink: Color(hex: ink),
      accent: Color(hex: accent), link: Color(hex: link), yellow400: Color(hex: yellow),
      yellow300: mix(yellow, dark ? 0xFFFFFF : ink, 0.2),
      error: Color(hex: error), info: Color(hex: info), success: Color(hex: success),
      warning: Color(hex: warning),
      gray: steps.map { mix(ink, bg, $0) },
      black300: mix(bg, ink, 0.08),
      black400: dark ? mix(bg, primary, 0.3) : mix(bg, ink, 0.05),
      tableBorder: mix(bg, ink, 0.07),
      tableEven: dark ? mix(bg, primary, 0.6) : mix(bg, ink, 0.03),
      pageGradient: LinearGradient(
        colors: [Color(hex: gradient.0), Color(hex: gradient.1)],
        startPoint: .topLeading, endPoint: .bottomTrailing),
      swatch: [bg, primary, accent, yellow].map { Color(hex: $0) })
  }

  private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
    func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) / 255 }
    func m(_ s: UInt32) -> Double { ch(a, s) * (1 - t) + ch(b, s) * t }
    return Color(.sRGB, red: m(16), green: m(8), blue: m(0))
  }
}

/// The chosen palette, kept in UserDefaults. The light/dark toggle flips to
/// the last palette used on the other side, so a favourite pair sticks.
/// "Match system" follows the macOS appearance with that same pair.
@Observable
final class ThemeStore: @unchecked Sendable {
  static let shared = ThemeStore()

  private(set) var palette: Palette
  private(set) var followSystem: Bool
  private var observer: NSObjectProtocol?

  private init() {
    let d = UserDefaults.standard
    followSystem = d.bool(forKey: "themeFollowSystem")
    palette = Palette.named(d.string(forKey: "theme")) ?? .audiobookshelf
    if followSystem { palette = Self.systemPick() }
  }

  var lastDark: Palette { Self.last(dark: true) }
  var lastLight: Palette { Self.last(dark: false) }

  private static func last(dark: Bool) -> Palette {
    Palette.named(UserDefaults.standard.string(forKey: dark ? "themeLastDark" : "themeLastLight"))
      ?? (dark ? .audiobookshelf : Palette.all[1])
  }

  /// An explicit pick always wins over Match System.
  @MainActor func select(_ p: Palette) {
    if followSystem { setFollowSystem(false) }
    set(p)
  }

  @MainActor func toggleLightDark() {
    setFollowSystem(false)
    set(palette.isDark ? lastLight : lastDark)
  }

  @MainActor func setFollowSystem(_ on: Bool) {
    followSystem = on
    UserDefaults.standard.set(on, forKey: "themeFollowSystem")
    if on { set(Self.systemPick()) }
  }

  /// Call once at launch: applies the AppKit side and starts following
  /// system appearance changes.
  @MainActor func start() {
    applyAppKit()
    observer = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.followSystem else { return }
        self.set(Self.systemPick())
      }
    }
  }

  @MainActor private func set(_ p: Palette) {
    let d = UserDefaults.standard
    d.set(p.id, forKey: "theme")
    d.set(p.id, forKey: p.isDark ? "themeLastDark" : "themeLastLight")
    guard p != palette else { return }
    palette = p
    applyAppKit()
  }

  /// Native controls (menus, popovers, text fields, scrollers) and the
  /// window behind the SwiftUI content follow the palette too.
  @MainActor private func applyAppKit() {
    NSApp.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
    AppDelegate.shared?.window?.backgroundColor = NSColor(palette.bg)
  }

  private static var systemIsDark: Bool {
    UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
  }

  private static func systemPick() -> Palette { last(dark: systemIsDark) }
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: opacity)
  }
}

/// Material Symbols Rounded, drawn by glyph name resolved to its codepoint
/// (never by ligature text: a typo would render as words and VoiceOver would
/// read "play_arrow").
enum Icons {
  private static let aliases = ["bookmark_border": "bookmark", "watch_later": "schedule"]
  private static var cache: [String: Character] = [:]
  private static var reverse: [CGGlyph: UInt32]?
  private static let fontName = "MaterialSymbolsRounded24pt-Regular"

  static func character(_ name: String) -> Character? {
    if let c = cache[name] { return c }
    let glyphName = aliases[name] ?? name
    let font = CTFontCreateWithName(fontName as CFString, 24, nil)
    let glyph = CTFontGetGlyphWithName(font, glyphName as CFString)
    guard glyph != 0 else { return nil }
    if reverse == nil { reverse = buildReverse(font) }
    guard let cp = reverse?[glyph], let scalar = Unicode.Scalar(cp) else { return nil }
    let c = Character(scalar)
    cache[name] = c
    return c
  }

  private static func buildReverse(_ font: CTFont) -> [CGGlyph: UInt32] {
    var map: [CGGlyph: UInt32] = [:]
    for cp in UInt32(0xE000)...UInt32(0xF8FF) {
      var ch = UniChar(cp)
      var g: CGGlyph = 0
      if CTFontGetGlyphsForCharacters(font, &ch, &g, 1), g != 0, map[g] == nil { map[g] = cp }
    }
    return map
  }

  /// A filled variant needs the FILL=1 variation of the variable font.
  static func font(size: CGFloat, filled: Bool) -> Font {
    guard filled else { return .custom(fontName, size: size) }
    let base = CTFontCreateWithName(fontName as CFString, size, nil)
    let fillTag: UInt32 = 0x4649_4C4C  // 'FILL'
    let desc = CTFontDescriptorCreateCopyWithVariation(
      CTFontCopyFontDescriptor(base), fillTag as CFNumber, 1)
    return Font(CTFontCreateWithFontDescriptor(desc, size, nil))
  }
}

/// `<span class="material-symbols">name</span>`.
struct Icon: View {
  let name: String
  var size: CGFloat = 24
  var filled = false

  init(_ name: String, size: CGFloat = 24, filled: Bool = false) {
    self.name = name
    self.size = size
    self.filled = filled
  }

  var body: some View {
    Text(Icons.character(name).map { String($0) } ?? "?")
      .font(Icons.font(size: size, filled: filled))
      .accessibilityLabel(name.replacingOccurrences(of: "_", with: " "))
  }
}

/// UI strings from client/strings/en-us.json, same keys as the web.
enum L {
  static let table: [String: String] = {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("strings/en-us.json"),
      let d = try? Data(contentsOf: url),
      let o = try? JSONSerialization.jsonObject(with: d) as? [String: String]
    else { return [:] }
    return o
  }()

  static func s(_ key: String) -> String { table[key] ?? key }

  static func s(_ key: String, _ args: String...) -> String {
    var out = s(key)
    for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "{\(i)}", with: a) }
    return out
  }
}
