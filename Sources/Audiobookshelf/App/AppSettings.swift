import Foundation
import Observation

/// User settings. The first block uses the web client's keys and defaults
/// (client/store/user.js); the rest are the mobile app's player options and
/// native-only preferences. Stored in UserDefaults.
@MainActor @Observable
final class AppSettings {
  static let shared = AppSettings()
  private let d = UserDefaults.standard

  // MARK: Web (store/user.js)
  var playbackRate: Double { didSet { d.set(playbackRate, forKey: "playbackRate") } }
  var playbackRateIncrementDecrement: Double {
    didSet { d.set(playbackRateIncrementDecrement, forKey: "playbackRateIncrementDecrement") }
  }
  var jumpForwardAmount: Double { didSet { d.set(jumpForwardAmount, forKey: "jumpForwardAmount") } }
  var jumpBackwardAmount: Double {
    didSet { d.set(jumpBackwardAmount, forKey: "jumpBackwardAmount") }
  }
  var useChapterTrack: Bool { didSet { d.set(useChapterTrack, forKey: "useChapterTrack") } }
  var bookshelfCoverSize: Double {
    didSet { d.set(bookshelfCoverSize, forKey: "bookshelfCoverSize") }
  }
  var orderBy: String { didSet { d.set(orderBy, forKey: "orderBy") } }
  var orderDesc: Bool { didSet { d.set(orderDesc, forKey: "orderDesc") } }
  var filterBy: String { didSet { d.set(filterBy, forKey: "filterBy") } }
  var collapseSeries: Bool { didSet { d.set(collapseSeries, forKey: "collapseSeries") } }
  var showSubtitles: Bool { didSet { d.set(showSubtitles, forKey: "showSubtitles") } }
  var seriesSortBy: String { didSet { d.set(seriesSortBy, forKey: "seriesSortBy") } }
  var seriesSortDesc: Bool { didSet { d.set(seriesSortDesc, forKey: "seriesSortDesc") } }
  var seriesFilterBy: String { didSet { d.set(seriesFilterBy, forKey: "seriesFilterBy") } }
  var authorSortBy: String { didSet { d.set(authorSortBy, forKey: "authorSortBy") } }
  var authorSortDesc: Bool { didSet { d.set(authorSortDesc, forKey: "authorSortDesc") } }
  var volume: Double { didSet { d.set(volume, forKey: "volume") } }
  var playerQueueAutoPlay: Bool {
    didSet { d.set(playerQueueAutoPlay, forKey: "playerQueueAutoPlay") }
  }

  // MARK: Mobile player options
  var disableAutoRewind: Bool { didSet { d.set(disableAutoRewind, forKey: "disableAutoRewind") } }
  var disableSleepTimerFadeOut: Bool {
    didSet { d.set(disableSleepTimerFadeOut, forKey: "disableSleepTimerFadeOut") }
  }
  var sleepTimerChime: Bool { didSet { d.set(sleepTimerChime, forKey: "sleepTimerChime") } }
  var autoSleepTimer: Bool { didSet { d.set(autoSleepTimer, forKey: "autoSleepTimer") } }
  var autoSleepStart: String { didSet { d.set(autoSleepStart, forKey: "autoSleepStart") } }
  var autoSleepEnd: String { didSet { d.set(autoSleepEnd, forKey: "autoSleepEnd") } }
  /// Seconds; 0 = End of Chapter.
  var autoSleepLength: Double { didSet { d.set(autoSleepLength, forKey: "autoSleepLength") } }
  var autoSleepAutoRewind: Bool {
    didSet { d.set(autoSleepAutoRewind, forKey: "autoSleepAutoRewind") }
  }
  var autoSleepAutoRewindTime: Double {
    didSet { d.set(autoSleepAutoRewindTime, forKey: "autoSleepAutoRewindTime") }
  }
  var allowSeekingOnMediaControls: Bool {
    didSet { d.set(allowSeekingOnMediaControls, forKey: "allowSeekingOnMediaControls") }
  }

  // MARK: Native
  var nextPrevSkipsChapters: Bool {
    didSet { d.set(nextPrevSkipsChapters, forKey: "nextPrevSkipsChapters") }
  }
  var pauseOnHeadphonesDisconnect: Bool {
    didSet { d.set(pauseOnHeadphonesDisconnect, forKey: "pauseOnHeadphonesDisconnect") }
  }
  var showMenuBarExtra: Bool { didSet { d.set(showMenuBarExtra, forKey: "showMenuBarExtra") } }
  var miniplayerOnTop: Bool { didSet { d.set(miniplayerOnTop, forKey: "miniplayerOnTop") } }
  var controlPortEnabled: Bool {
    didSet { d.set(controlPortEnabled, forKey: "controlPortEnabled") }
  }
  var controlPort: Int { didSet { d.set(controlPort, forKey: "controlPort") } }
  var notifyDownloads: Bool { didSet { d.set(notifyDownloads, forKey: "notifyDownloads") } }
  var notifyNewBooks: Bool { didSet { d.set(notifyNewBooks, forKey: "notifyNewBooks") } }
  var notifyFinished: Bool { didSet { d.set(notifyFinished, forKey: "notifyFinished") } }
  var showWindowAtLaunch: Bool {
    didSet { d.set(showWindowAtLaunch, forKey: "showWindowAtLaunch") }
  }
  var autoDownloadEnabled: Bool {
    didSet { d.set(autoDownloadEnabled, forKey: "autoDownloadEnabled") }
  }
  var autoDownloadCount: Int { didSet { d.set(autoDownloadCount, forKey: "autoDownloadCount") } }
  /// 0 = never delete finished downloads automatically.
  var deleteFinishedAfterDays: Int {
    didSet { d.set(deleteFinishedAfterDays, forKey: "deleteFinishedAfterDays") }
  }
  var downloadsFolder: String { didSet { d.set(downloadsFolder, forKey: "downloadsFolder") } }
  /// "timeDomain" (voice-tuned) or "spectral".
  var pitchAlgorithm: String { didSet { d.set(pitchAlgorithm, forKey: "pitchAlgorithm") } }
  /// action name -> "keyCode:modifiers"
  var hotkeys: [String: String] { didSet { d.set(hotkeys, forKey: "hotkeys") } }

  private init() {
    let d = UserDefaults.standard
    func dbl(_ k: String, _ def: Double) -> Double {
      d.object(forKey: k) == nil ? def : d.double(forKey: k)
    }
    func bool(_ k: String, _ def: Bool) -> Bool {
      d.object(forKey: k) == nil ? def : d.bool(forKey: k)
    }
    func str(_ k: String, _ def: String) -> String { d.string(forKey: k) ?? def }
    func int(_ k: String, _ def: Int) -> Int {
      d.object(forKey: k) == nil ? def : d.integer(forKey: k)
    }

    playbackRate = dbl("playbackRate", 1)
    playbackRateIncrementDecrement = dbl("playbackRateIncrementDecrement", 0.1)
    jumpForwardAmount = dbl("jumpForwardAmount", 10)
    jumpBackwardAmount = dbl("jumpBackwardAmount", 10)
    useChapterTrack = bool("useChapterTrack", false)
    bookshelfCoverSize = dbl("bookshelfCoverSize", 120)
    orderBy = str("orderBy", "media.metadata.title")
    orderDesc = bool("orderDesc", false)
    filterBy = str("filterBy", "all")
    collapseSeries = bool("collapseSeries", false)
    showSubtitles = bool("showSubtitles", false)
    seriesSortBy = str("seriesSortBy", "name")
    seriesSortDesc = bool("seriesSortDesc", false)
    seriesFilterBy = str("seriesFilterBy", "all")
    authorSortBy = str("authorSortBy", "name")
    authorSortDesc = bool("authorSortDesc", false)
    volume = dbl("volume", 1)
    playerQueueAutoPlay = bool("playerQueueAutoPlay", true)

    disableAutoRewind = bool("disableAutoRewind", false)
    disableSleepTimerFadeOut = bool("disableSleepTimerFadeOut", false)
    sleepTimerChime = bool("sleepTimerChime", false)
    autoSleepTimer = bool("autoSleepTimer", false)
    autoSleepStart = str("autoSleepStart", "22:00")
    autoSleepEnd = str("autoSleepEnd", "06:00")
    autoSleepLength = dbl("autoSleepLength", 900)
    autoSleepAutoRewind = bool("autoSleepAutoRewind", false)
    autoSleepAutoRewindTime = dbl("autoSleepAutoRewindTime", 300)
    allowSeekingOnMediaControls = bool("allowSeekingOnMediaControls", false)

    nextPrevSkipsChapters = bool("nextPrevSkipsChapters", false)
    pauseOnHeadphonesDisconnect = bool("pauseOnHeadphonesDisconnect", true)
    showMenuBarExtra = bool("showMenuBarExtra", true)
    miniplayerOnTop = bool("miniplayerOnTop", true)
    controlPortEnabled = bool("controlPortEnabled", true)
    controlPort = int("controlPort", 9801)
    notifyDownloads = bool("notifyDownloads", true)
    notifyNewBooks = bool("notifyNewBooks", true)
    notifyFinished = bool("notifyFinished", true)
    showWindowAtLaunch = bool("showWindowAtLaunch", true)
    autoDownloadEnabled = bool("autoDownloadEnabled", false)
    autoDownloadCount = int("autoDownloadCount", 3)
    deleteFinishedAfterDays = int("deleteFinishedAfterDays", 0)
    let defaultDownloads = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Audiobookshelf/Downloads").path
    downloadsFolder = str("downloadsFolder", defaultDownloads)
    pitchAlgorithm = str("pitchAlgorithm", "timeDomain")
    hotkeys = (d.dictionary(forKey: "hotkeys") as? [String: String]) ?? [:]
  }

  static let jumpOptions: [Double] = [10, 15, 30, 60, 120, 300]
  static let rateSteps: [Double] = [0.1, 0.05]
}
