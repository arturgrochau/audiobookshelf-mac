import AppKit
import CoreText
import SwiftUI

/// Design tokens from client/assets/tailwind.css (@theme) and app.css.
enum Theme {
  static let bg = Color(hex: 0x373838)
  static let primary = Color(hex: 0x232323)
  static let accent = Color(hex: 0x1AD691)
  static let error = Color(hex: 0xFF5252)
  static let info = Color(hex: 0x2196F3)
  static let success = Color(hex: 0x4CAF50)
  static let warning = Color(hex: 0xFB8C00)
  static let yellow400 = Color(hex: 0xFDC700)
  static let yellow300 = Color(hex: 0xFFDF20)
  static let gray100 = Color(hex: 0xF3F4F6)
  static let gray200 = Color(hex: 0xE5E7EB)
  static let gray300 = Color(hex: 0xD1D5DC)
  static let gray400 = Color(hex: 0x99A1AF)
  static let gray500 = Color(hex: 0x6A7282)
  static let gray600 = Color(hex: 0x4A5565)
  static let gray700 = Color(hex: 0x364153)
  static let black50 = Color(hex: 0xBBBBBB)
  static let black100 = Color(hex: 0x666666)
  static let black200 = Color(hex: 0x555555)
  static let black300 = Color(hex: 0x444444)
  static let black400 = Color(hex: 0x333333)
  static let black500 = Color(hex: 0x222222)
  static let link = Color(hex: 0x5985FF)
  static let seriesBadge = Color(
    red: 0xCD / 255, green: 0x9D / 255, blue: 0x49 / 255, opacity: 0xDD / 255)
  static let tableBorder = Color(hex: 0x474747)
  static let tableEven = Color(hex: 0x2E2E2E)

  /// `#bookshelf` / `#page-wrapper` background.
  static let pageGradient = LinearGradient(
    colors: [
      0x2E2E2E, 0x303030, 0x313131, 0x333333, 0x353535, 0x343434, 0x323232, 0x313131, 0x2C2C2C,
      0x282828, 0x232323, 0x1F1F1F,
    ]
    .map { Color(hex: $0) },
    startPoint: .topLeading, endPoint: .bottomTrailing)

  static let railWidth: CGFloat = 80
  static let toolbarHeight: CGFloat = 40
  static let appBarHeight: CGFloat = 52
  static let playerHeight: CGFloat = 160

  // MARK: Fonts

  static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    switch weight {
    case .light, .thin, .ultraLight: return .custom("SourceSansPro-Light", size: size)
    case .semibold, .bold, .heavy, .black, .medium:
      return .custom("SourceSansPro-SemiBold", size: size)
    default: return .custom("SourceSansPro-Regular", size: size)
    }
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
