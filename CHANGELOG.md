# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Space, Latte and Princess look clearly different from the other themes. Space is near-black with a purple glow and cyan accents, Latte is a cool lavender-grey, and Princess is a soft pink with plum text and a rose accent.
- The README shows four short feature clips (themes, browsing, the player and the mini player) in a grid instead of one long demo.

## [0.2.0] - 2026-10-06

### Added

- Themes. A sun/moon button in the top right (or `⌥⌘L`) flips between light and dark. Right-click it, use View ▸ Theme, or open Settings to pick one of seven: Audiobookshelf, Light, Space (Tokyo Night), Nord, Catppuccin, Latte and Princess. Every surface, accent and native control follows the theme. "Match system appearance" follows macOS light and dark mode.
- Mini player (`⌘⇧M`): a small floating panel with the cover, play/pause, jumps and a speed menu. It stays on top across Spaces and full-screen apps without taking focus. Hover it to set its opacity for when the pointer is away.
- Speed keys: `S` 2x, `A` 1.5x, `X` 1.2x, `Z` 1x. They match by character, so they work on any keyboard layout.
- Keep awake (☕). The Mac stays awake while a book plays. An optional lid-closed mode installs one sudoers rule that allows only `pmset -a disablesleep 0|1`. Sleep comes back on pause, when the sleep timer fires, on quit, below 20% battery, or after a crash.
- `audiobookshelf://theme?id=…` and `audiobookshelf://mini-player` URL routes for Stream Deck and scripts.
- Security policy with private vulnerability reporting, CI (release build and tests on every push), issue templates and contributing notes.

### Changed

- A book that finishes downloading while you listen moves to the local copy without a cut. Files further along switch right away. The current file switches at the next pause, seek or file boundary, or at once if the stream stalls. Removing a download goes back to the stream the same way.
- The player bar and pages are quieter and more minimal.
- Search also matches narrators, tags and genres.
- Different editions of a book download to separate folders.

### Fixed

- `⌘⇧M` zoomed the window instead of opening the mini player when a system-wide shortcut for Window ▸ Zoom used the same keys.
- Series pages showed nothing on servers that return no rows for a zero or missing page size.
- Collections and playlists were hidden on Audiobookshelf 2.36.
- A cancelled catalog refresh could overwrite newer data.

### Security

- The URL routes that start or delete downloads are off unless `debugURLRoutes` is set, so a web link can't remove offline downloads.

## [0.1.0] - 2026-09-24

First version: a native SwiftUI and AVFoundation client for Audiobookshelf 2.36 with the web client's pages, player controls and wording.

- Gapless playback of multi-file books, Now Playing, media keys and AirPods controls.
- Progress sync on the web client's schedule, sleep timer with fade, bookmarks, chapters and queue.
- Offline downloads, with offline sessions uploaded once you're back online.
- Persistent login: tokens refresh on their own, and only a rejected password logs you out.

[Unreleased]: https://github.com/arturgrochau/audiobookshelf-mac/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/arturgrochau/audiobookshelf-mac/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/arturgrochau/audiobookshelf-mac/releases/tag/v0.1.0
