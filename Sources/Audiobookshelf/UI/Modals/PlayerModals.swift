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
      .background(Theme.bg)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .shadow(color: .black.opacity(0.66), radius: 6, x: 2, y: 8)
    }
  }

  private var options: some View {
    VStack(spacing: 0) {
      ForEach(SleepTimer.presets, id: \.self) { s in
        row(
          s >= 7200
            ? L.s("LabelTimeDurationXHours", String(Int(s / 3600)))
            : L.s("LabelTimeDurationXMinutes", String(Int(s / 60)))
        ) {
          player.setSleepTimer(seconds: s)
          player.showSleepTimer = false
        }
      }
      if !player.chapters.isEmpty {
        row(L.s("LabelEndOfChapter")) {
          player.setSleepTimerEndOfChapter()
          player.showSleepTimer = false
        }
      }
      HStack(spacing: 8) {
        TextField(L.s("LabelTimeInMinutes"), text: $custom)
          .textFieldStyle(.plain)
          .font(Theme.sans(14))
          .padding(.horizontal, 8)
          .frame(height: 32)
          .background(Theme.primary)
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gray600))
          .onSubmit(submit)
        WebButton(L.s("ButtonSubmit"), small: true, action: submit)
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

  private func row(_ text: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(text)
        .font(Theme.sans(16))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .hoverHighlight(Theme.primary.opacity(0.6))
  }

  private var running: some View {
    VStack(spacing: 16) {
      if player.sleep.mode == .countdown {
        let remaining = player.sleep.remaining
        HStack(spacing: 16) {
          WebButton(
            small: true, disabled: remaining < 30 * 60, paddingX: 8,
            action: { player.decrementSleepTimer(30 * 60) }
          ) {
            HStack(spacing: 4) {
              Icon("remove", size: 18)
              Text("30m").font(Theme.sans(14))
            }
          }
          IconButton(icon: "remove") { player.decrementSleepTimer(5 * 60) }
          Text(Format.timestamp(remaining)).font(Theme.mono(24)).foregroundStyle(.white).frame(
            minWidth: 80)
          IconButton(icon: "add") { player.incrementSleepTimer(5 * 60) }
          WebButton(small: true, paddingX: 8, action: { player.incrementSleepTimer(30 * 60) }) {
            HStack(spacing: 4) {
              Icon("add", size: 18)
              Text("30m").font(Theme.sans(14))
            }
          }
        }
      } else {
        Text(L.s("LabelEndOfChapter")).font(Theme.sans(18)).foregroundStyle(.white)
      }
      WebButton(
        color: Theme.primary,
        action: {
          player.cancelSleepTimer()
          player.showSleepTimer = false
        }
      ) {
        Text(L.s("ButtonCancel")).frame(maxWidth: .infinity)
      }
    }
    .padding(16)
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
              Button {
                player.seek(to: c.start)
                player.showChapters = false
              } label: {
                HStack(spacing: 8) {
                  Text(c.title).font(Theme.sans(16)).foregroundStyle(.white).lineLimit(1)
                  Text(Format.elapsedPrettyExtended((c.end - c.start) / player.rate))
                    .font(Theme.mono(12)).foregroundStyle(Theme.gray400)
                  Spacer()
                  Text(Format.timestamp(c.start / player.rate)).font(Theme.mono(14))
                    .foregroundStyle(Theme.gray300)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                  isCurrent
                    ? Theme.yellow400.opacity(0.2) : (done ? Theme.success.opacity(0.1) : .clear)
                )
                .overlay(alignment: .leading) { if isCurrent { Theme.yellow400.frame(width: 2) } }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .id(c.id)
            }
          }
        }
        .frame(maxHeight: 560)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        ScrollView {
          VStack(spacing: 0) {
            if marks.isEmpty {
              Text(L.s("MessageNoBookmarks")).font(Theme.sans(16)).foregroundStyle(Theme.gray300)
                .padding(24)
            }
            ForEach(marks, id: \.time) { b in bookmarkRow(b) }
          }
        }
        .frame(maxHeight: 400)
        if !marks.contains(where: { abs($0.time - now) < 1 }) {
          HStack(spacing: 8) {
            Icon("bookmark_add", size: 20).foregroundStyle(Theme.gray300)
            Text(Format.timestamp(now / player.rate)).font(Theme.mono(14)).foregroundStyle(
              Theme.gray300)
            TextField("Note", text: $note)
              .textFieldStyle(.plain)
              .font(Theme.sans(14))
              .padding(.horizontal, 8)
              .frame(height: 32)
              .background(Theme.primary)
              .clipShape(RoundedRectangle(cornerRadius: 4))
              .onSubmit(add)
            IconButton(icon: "add", action: add)
          }
          .padding(16)
          .background(Theme.primary.opacity(0.5))
        }
      }
      .background(Theme.bg)
      .clipShape(RoundedRectangle(cornerRadius: 8))
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
    HStack(spacing: 8) {
      Icon("bookmark", size: 20, filled: true).foregroundStyle(Theme.gray300)
      Text(Format.timestamp(b.time / player.rate)).font(Theme.mono(14)).foregroundStyle(
        Theme.gray300)
      if editing == b.time {
        TextField("", text: $editText)
          .textFieldStyle(.plain)
          .font(Theme.sans(14))
          .onSubmit {
            let t = editText
            editing = nil
            Task { await player.renameBookmark(b, to: t) }
          }
        HoverIcon(icon: "forward", size: 20) {
          let t = editText
          editing = nil
          Task { await player.renameBookmark(b, to: t) }
        }
        HoverIcon(icon: "close", size: 20) { editing = nil }
      } else {
        Text(b.title).font(Theme.sans(15)).foregroundStyle(.white).lineLimit(1)
        Spacer()
        HoverIcon(icon: "edit", size: 18) {
          editText = b.title
          editing = b.time
        }
        HoverIcon(icon: "delete", size: 18, hoverColor: Theme.error) {
          Task { await player.deleteBookmark(b) }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .contentShape(Rectangle())
    .onTapGesture {
      guard editing == nil else { return }
      player.seek(to: b.time)
      player.showBookmarks = false
    }
    .hoverHighlight()
  }
}

/// modals/player/QueueItemsModal.vue (800 px).
struct QueueModal: View {
  @Bindable var player = PlayerModel.shared
  @Bindable var settings = AppSettings.shared

  var body: some View {
    WebModal(title: L.s("HeaderPlayerQueue"), width: 800, isPresented: $player.showQueue) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("\(player.queue.count) Items").font(Theme.sans(16)).foregroundStyle(Theme.gray300)
          Spacer()
          Toggle("Auto Play", isOn: $settings.playerQueueAutoPlay).toggleStyle(.checkbox).font(
            Theme.sans(14))
        }
        .padding(16)
        ScrollView {
          VStack(spacing: 0) {
            ForEach(player.queue) { q in
              HStack(spacing: 12) {
                BookCover(
                  item: nil, width: 48, itemId: q.libraryItemId, updatedAt: q.coverUpdatedAt,
                  hasCover: q.hasCover)
                VStack(alignment: .leading, spacing: 2) {
                  Text(q.title).font(Theme.sans(15)).foregroundStyle(.white).lineLimit(1)
                  Text(q.subtitle).font(Theme.sans(13)).foregroundStyle(Theme.gray400).lineLimit(1)
                }
                Spacer()
                if q.libraryItemId == player.item?.id {
                  Text("Playing").font(Theme.sans(13)).foregroundStyle(Theme.gray300)
                } else {
                  HoverIcon(icon: "play_arrow", size: 24, color: Theme.success) {
                    Task { await player.play(q.libraryItemId) }
                  }
                  HoverIcon(icon: "close", size: 22, color: Theme.error) {
                    player.removeFromQueue(q.libraryItemId)
                  }
                  Text(q.duration > 0 ? Format.elapsedPretty(q.duration) : "N/A").font(
                    Theme.sans(13)
                  ).foregroundStyle(Theme.gray400)
                }
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .hoverHighlight()
            }
          }
        }
        .frame(maxHeight: 480)
      }
      .background(Theme.bg)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }
}

/// modals/PlayerSettingsModal.vue (500 px).
struct PlayerSettingsModal: View {
  @Bindable var player = PlayerModel.shared
  @Bindable var settings = AppSettings.shared

  var body: some View {
    WebModal(
      title: L.s("HeaderPlayerSettings"), width: 500, isPresented: $player.showPlayerSettings
    ) {
      VStack(alignment: .leading, spacing: 20) {
        Toggle(L.s("LabelUseChapterTrack"), isOn: $settings.useChapterTrack).toggleStyle(.switch)
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
      .font(Theme.sans(16))
      .foregroundStyle(.white)
      .padding(24)
      .background(Theme.bg)
      .clipShape(RoundedRectangle(cornerRadius: 8))
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
