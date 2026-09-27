import ABSCore
import SwiftUI

/// modals/SleepTimerModal.vue (350 px).
struct SleepTimerModal: View {
  @Bindable var player = PlayerModel.shared
  @State private var custom = ""

  var body: some View {
    WebModal(title: L.s("HeaderSleepTimer"), width: 350, isPresented: $player.showSleepTimer) {
      VStack(spacing: 0) {
        if player.sleep.isSet {
          running
        } else {
          options
        }
      }
    }
  }

  private var options: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        ForEach(SleepTimer.presets, id: \.self) { s in
          ModalRow {
            player.setSleepTimer(seconds: s)
            player.showSleepTimer = false
          } content: {
            Text(
              s >= 7200
                ? L.s("LabelTimeDurationXHours", String(Int(s / 3600)))
                : L.s("LabelTimeDurationXMinutes", String(Int(s / 60))))
            Spacer()
          }
        }
        if !player.chapters.isEmpty {
          ModalRow {
            player.setSleepTimerEndOfChapter()
            player.showSleepTimer = false
          } content: {
            Text(L.s("LabelEndOfChapter"))
            Spacer()
          }
        }
      }
      .padding(.horizontal, 8)
      HStack(spacing: 8) {
        ModalField(placeholder: L.s("LabelTimeInMinutes"), text: $custom, onSubmit: submit)
        PillButton(title: "Set", action: submit)
      }
      .padding(16)
    }
  }

  private func submit() {
    guard let m = Double(custom.replacingOccurrences(of: ",", with: ".")), m > 0 else {
      custom = ""
      return
    }
    player.setSleepTimer(seconds: (m * 60).rounded())
    custom = ""
    player.showSleepTimer = false
  }

  private var running: some View {
    VStack(spacing: 18) {
      if player.sleep.mode == .countdown {
        let remaining = player.sleep.remaining
        HStack(spacing: 10) {
          PillButton(title: "30m", symbol: "minus", disabled: remaining < 30 * 60) {
            player.decrementSleepTimer(30 * 60)
          }
          SymbolButton(symbol: "minus", size: 12, weight: .bold, help: "5 minutes less") {
            player.decrementSleepTimer(5 * 60)
          }
          Text(Format.timestamp(remaining))
            .font(.system(size: 26, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .frame(minWidth: 84)
          SymbolButton(symbol: "plus", size: 12, weight: .bold, help: "5 minutes more") {
            player.incrementSleepTimer(5 * 60)
          }
          PillButton(title: "30m", symbol: "plus") { player.incrementSleepTimer(30 * 60) }
        }
      } else {
        Text(L.s("LabelEndOfChapter")).font(.system(size: 17, weight: .medium))
          .foregroundStyle(.white)
      }
      PillButton(title: "Turn Off Timer") {
        player.cancelSleepTimer()
        player.showSleepTimer = false
      }
    }
    .padding(.top, 6)
    .padding([.horizontal, .bottom], 20)
  }
}

/// modals/ChaptersModal.vue (600 px).
struct ChaptersModal: View {
  @Bindable var player = PlayerModel.shared

  var body: some View {
    WebModal(title: L.s("HeaderChapters"), width: 600, isPresented: $player.showChapters) {
      let current = player.currentChapter
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(player.chapters) { c in
              let isCurrent = c.id == current?.id
              let done = !isCurrent && c.end / player.rate <= (current?.start ?? 0) / player.rate
              ModalRow(selected: isCurrent) {
                player.seek(to: c.start)
                player.showChapters = false
              } content: {
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "checkmark")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(isCurrent ? Theme.accent : Theme.gray500)
                  .opacity(isCurrent || done ? 1 : 0)
                  .frame(width: 14)
                Text(c.title).lineLimit(1)
                  .foregroundStyle(isCurrent ? .white : done ? Theme.gray400 : Theme.gray100)
                Spacer()
                Text(Format.elapsedPrettyExtended((c.end - c.start) / player.rate))
                  .foregroundStyle(Theme.gray500)
                Text(Format.timestamp(c.start / player.rate))
                  .foregroundStyle(Theme.gray400)
                  .frame(width: 64, alignment: .trailing)
              }
              .id(c.id)
            }
          }
          .font(.system(size: 13).monospacedDigit())
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
        .frame(height: min(560, CGFloat(player.chapters.count) * 34 + 8))
        .onAppear { if let id = current?.id { proxy.scrollTo(id, anchor: .center) } }
      }
    }
  }
}

/// modals/BookmarksModal.vue (500 px).
struct BookmarksModal: View {
  @Bindable var player = PlayerModel.shared
  @State private var note = ""
  @State private var editing: Double?
  @State private var editText = ""
  /// Web: the time is taken when the modal opens, not when the note is submitted.
  @State private var now: Double = 0

  var body: some View {
    WebModal(title: L.s("LabelYourBookmarks"), width: 500, isPresented: $player.showBookmarks) {
      let marks = player.bookmarks
      VStack(spacing: 0) {
        if marks.isEmpty {
          Text(L.s("MessageNoBookmarks")).font(.system(size: 13))
            .foregroundStyle(Theme.gray400)
            .padding(.vertical, 16)
        } else {
          ScrollView {
            VStack(spacing: 0) {
              ForEach(marks, id: \.time) { b in bookmarkRow(b) }
            }
            .padding(.horizontal, 8)
          }
          .frame(height: min(400, CGFloat(marks.count) * 34))
        }
        if !marks.contains(where: { abs($0.time - now) < 1 }) {
          HStack(spacing: 8) {
            Text(Format.timestamp(now / player.rate))
              .font(.system(size: 12).monospacedDigit())
              .foregroundStyle(Theme.gray400)
            ModalField(placeholder: "Note", text: $note, onSubmit: add)
            PillButton(title: "Add", symbol: "bookmark.fill", action: add)
          }
          .padding(16)
        }
      }
    }
    .onAppear {
      now = floor(player.liveTime)
      note = ""
      editing = nil
    }
  }

  private func add() {
    let text = note
    let time = now
    note = ""
    player.showBookmarks = false
    Task { await player.addBookmark(title: text, time: time) }
  }

  @ViewBuilder private func bookmarkRow(_ b: Bookmark) -> some View {
    ModalRow {
      guard editing == nil else { return }
      player.seek(to: b.time)
      player.showBookmarks = false
    } content: {
      Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundStyle(Theme.gray500)
      Text(Format.timestamp(b.time / player.rate)).monospacedDigit()
        .foregroundStyle(Theme.gray400)
      if editing == b.time {
        TextField("", text: $editText)
          .textFieldStyle(.plain)
          .onSubmit { rename(b) }
        SymbolButton(symbol: "checkmark", size: 11, weight: .bold, help: "Save") { rename(b) }
        SymbolButton(symbol: "xmark", size: 11, weight: .bold, help: "Cancel") { editing = nil }
      } else {
        Text(b.title).foregroundStyle(Theme.gray100).lineLimit(1)
        Spacer()
        SymbolButton(symbol: "pencil", size: 12, help: "Rename") {
          editText = b.title
          editing = b.time
        }
        SymbolButton(symbol: "trash", size: 12, help: "Delete") {
          Task { await player.deleteBookmark(b) }
        }
      }
    }
    .font(.system(size: 13))
  }

  private func rename(_ b: Bookmark) {
    let t = editText
    editing = nil
    Task { await player.renameBookmark(b, to: t) }
  }
}

/// modals/player/QueueItemsModal.vue (800 px).
struct QueueModal: View {
  @Bindable var player = PlayerModel.shared
  @Bindable var settings = AppSettings.shared

  var body: some View {
    WebModal(title: L.s("HeaderPlayerQueue"), width: 640, isPresented: $player.showQueue) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("\(player.queue.count) items").foregroundStyle(Theme.gray400)
          Spacer()
          Toggle("Auto Play", isOn: $settings.playerQueueAutoPlay).toggleStyle(.switch)
            .controlSize(.mini)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        ScrollView {
          VStack(spacing: 0) {
            ForEach(player.queue) { q in
              let playing = q.libraryItemId == player.item?.id
              ModalRow(selected: playing, height: 60) {
                if !playing { Task { await player.play(q.libraryItemId) } }
              } content: {
                BookCover(
                  item: nil, width: 44, itemId: q.libraryItemId, updatedAt: q.coverUpdatedAt,
                  hasCover: q.hasCover
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                  Text(q.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                  Text(q.subtitle).font(.system(size: 12)).foregroundStyle(Theme.gray400)
                    .lineLimit(1)
                }
                Spacer()
                if playing {
                  Image(systemName: "speaker.wave.2.fill").font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                } else {
                  Text(q.duration > 0 ? Format.elapsedPretty(q.duration) : "")
                    .font(.system(size: 12)).foregroundStyle(Theme.gray500)
                  SymbolButton(symbol: "xmark", size: 10, weight: .bold, help: "Remove from queue")
                  {
                    player.removeFromQueue(q.libraryItemId)
                  }
                }
              }
              .help(playing ? "Playing" : "Play now")
            }
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
        .frame(height: min(480, CGFloat(player.queue.count) * 60 + 8))
      }
    }
  }
}

/// modals/PlayerSettingsModal.vue (500 px).
struct PlayerSettingsModal: View {
  @Bindable var player = PlayerModel.shared
  @Bindable var settings = AppSettings.shared

  var body: some View {
    WebModal(
      title: L.s("HeaderPlayerSettings"), width: 460, isPresented: $player.showPlayerSettings
    ) {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text(L.s("LabelUseChapterTrack"))
          Spacer()
          Toggle("", isOn: $settings.useChapterTrack).toggleStyle(.switch).labelsHidden()
            .controlSize(.small)
        }
        pickerRow(L.s("LabelJumpForwardAmount"), $settings.jumpForwardAmount)
        pickerRow(L.s("LabelJumpBackwardAmount"), $settings.jumpBackwardAmount)
        HStack {
          Text(L.s("LabelPlaybackRateIncrementDecrement"))
          Spacer()
          Picker("", selection: $settings.playbackRateIncrementDecrement) {
            ForEach(AppSettings.rateSteps, id: \.self) { Text(Format.trimNumber($0)).tag($0) }
          }
          .labelsHidden()
          .frame(width: 120)
        }
      }
      .font(.system(size: 13))
      .foregroundStyle(Theme.gray100)
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .padding(.bottom, 20)
      .onChange(of: settings.jumpForwardAmount) { NowPlaying.shared.refreshCommandConfig() }
      .onChange(of: settings.jumpBackwardAmount) { NowPlaying.shared.refreshCommandConfig() }
    }
  }

  private func pickerRow(_ label: String, _ value: Binding<Double>) -> some View {
    HStack {
      Text(label)
      Spacer()
      Picker("", selection: value) {
        ForEach(AppSettings.jumpOptions, id: \.self) { s in
          Text(s >= 120 ? "\(Int(s / 60)) minutes" : "\(Int(s)) seconds").tag(s)
        }
      }
      .labelsHidden()
      .frame(width: 140)
    }
  }
}

/// One clickable row in a sheet: rounded hover, a tint when it is the current one.
struct ModalRow<Content: View>: View {
  var selected = false
  var height: CGFloat = 34
  let action: () -> Void
  @ViewBuilder var content: () -> Content
  @State private var hover = false

  var body: some View {
    HStack(spacing: 10) { content() }
      .font(.system(size: 13))
      .foregroundStyle(Theme.gray100)
      .padding(.horizontal, 12)
      .frame(height: height)
      .background(
        RoundedRectangle(cornerRadius: 7).fill(
          selected ? Theme.accent.opacity(0.12) : Color.white.opacity(hover ? 0.06 : 0))
      )
      .contentShape(Rectangle())
      .onHover { hover = $0 }
      .onTapGesture(perform: action)
  }
}

/// The sheet's text field: a soft rounded well, accent ring while typing.
struct ModalField: View {
  let placeholder: String
  @Binding var text: String
  let onSubmit: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    TextField(placeholder, text: $text)
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      .focused($focused)
      .padding(.horizontal, 10)
      .frame(height: 30)
      .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
      .overlay(
        RoundedRectangle(cornerRadius: 7).stroke(
          focused ? Theme.accent.opacity(0.6) : Color.white.opacity(0.08))
      )
      .onSubmit(onSubmit)
  }
}
