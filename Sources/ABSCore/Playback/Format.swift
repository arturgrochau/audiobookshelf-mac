import Foundation

/// Ports of the web client's formatting helpers (client/plugins/utils.js), so
/// every time and size reads exactly as it does in the browser.
public enum Format {
  /// `$secondsToTimestamp`: "0:00", "m:ss", "h:mm:ss" (seconds floored).
  public static func timestamp(_ seconds: Double, alwaysIncludeHours: Bool = false) -> String {
    guard seconds.isFinite, seconds != 0 else { return alwaysIncludeHours ? "00:00:00" : "0:00" }
    let s = max(0, seconds)
    var minutes = Int(floor(s / 60))
    let secs = Int(floor(s - Double(minutes) * 60))
    let hours = minutes / 60
    minutes -= hours * 60
    if alwaysIncludeHours {
      return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
    if hours == 0 { return String(format: "%d:%02d", minutes, secs) }
    return String(format: "%d:%02d:%02d", hours, minutes, secs)
  }

  /// `$elapsedPretty`: "42 sec", "12 min", "3 hr", "12 hr 34 min" (minutes shown up to 69).
  public static func elapsedPretty(_ seconds: Double, fullNames: Bool = false) -> String {
    let seconds = max(0, seconds.isFinite ? seconds : 0)
    if seconds < 60 { return "\(Int(floor(seconds))) sec\(fullNames ? "onds" : "")" }
    var minutes = Int(floor(seconds / 60))
    if minutes < 70 {
      return "\(minutes) min" + (fullNames ? "ute\(minutes == 1 ? "" : "s")" : "")
    }
    let hours = minutes / 60
    minutes -= hours * 60
    if minutes == 0 { return "\(hours) \(fullNames ? "hours" : "hr")" }
    let h = fullNames ? "hour\(hours == 1 ? "" : "s")" : "hr"
    let m = fullNames ? "minute\(minutes == 1 ? "" : "s")" : "min"
    return "\(hours) \(h) \(minutes) \(m)"
  }

  /// `$elapsedPrettyExtended`: "1d 2h 3m 4s".
  public static func elapsedPrettyExtended(
    _ seconds: Double, useDays: Bool = true, showSeconds: Bool = true
  ) -> String {
    guard seconds.isFinite else { return "" }
    var secs = Int(seconds.rounded())
    var minutes = secs / 60
    secs -= minutes * 60
    var hours = minutes / 60
    minutes -= hours * 60
    if minutes != 0, secs != 0, !showSeconds {
      if secs >= 30 { minutes += 1 }
      if minutes >= 60 {
        hours += 1
        minutes -= 60
      }
    }
    var days = 0
    if useDays || hours / 24 >= 100 {
      days = hours / 24
      hours -= days * 24
    }
    var parts: [String] = []
    if days != 0 { parts.append("\(days)d") }
    if hours != 0 { parts.append("\(hours)h") }
    if minutes != 0 { parts.append("\(minutes)m") }
    if secs != 0, showSeconds { parts.append("\(secs)s") }
    return parts.joined(separator: " ")
  }

  /// `$bytesPretty` (base 1000, 2 decimals, trailing zeros dropped).
  public static func bytesPretty(_ bytes: Double, decimals: Int = 2) -> String {
    guard bytes.isFinite, bytes != 0 else { return "0 Bytes" }
    let sizes = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
    let i = max(0, min(sizes.count - 1, Int(floor(log(bytes) / log(1000)))))
    let v = bytes / pow(1000, Double(i))
    let rounded = (v * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
    return "\(trimNumber(rounded)) \(sizes[i])"
  }

  /// JS `parseFloat(x.toFixed(n))` style: 1.50 -> "1.5", 2.00 -> "2".
  public static func trimNumber(_ v: Double) -> String {
    if v == v.rounded() { return String(Int(v)) }
    var s = String(format: "%.2f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
  }

  /// Player speed label: "1x", "1.2x", "1.25x" (web PlaybackSpeedControl).
  public static func rate(_ r: Double) -> String { "\(trimNumber((r * 100).rounded() / 100))x" }

  /// Sleep-timer badge in the player: "EoC", "45s", "12m", "2h".
  public static func sleepBadge(remaining: Double?, isEndOfChapter: Bool) -> String {
    if isEndOfChapter { return "EoC" }
    guard let remaining else { return "" }
    let r = Int(remaining.rounded())
    if r < 90 { return "\(r)s" }
    let m = Int((Double(r) / 60).rounded())
    if m <= 90 { return "\(m)m" }
    return "\(Int((Double(m) / 60).rounded()))h"
  }

  /// Web jump tooltip: "Jump Backward - 10 seconds" / "- 2 minutes".
  public static func jumpAmount(_ seconds: Double) -> String {
    if seconds > 60 { return "\(Int(floor(seconds / 60))) minutes" }
    return "\(Int(seconds)) seconds"
  }
}
