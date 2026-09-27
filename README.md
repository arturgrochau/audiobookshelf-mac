# Audiobookshelf for macOS (unofficial)

A native Mac client for [Audiobookshelf](https://github.com/advplyr/audiobookshelf). It looks and works like the web client, with the same pages, player controls and wording, but plays audio through AVFoundation and feels like a Mac app.

![Demo: home shelves, speed and sleep timer, chapters, the mini player over the desktop, library and authors](docs/demo.gif)

<sub>24 seconds, sped up 1.25x. [MP4 version](docs/demo.mp4).</sub>

## Listening

- Playback keeps going when the window is closed. Media keys, Now Playing and AirPods controls work.
- Multi-file books play gaplessly, straight from the server.
- Progress syncs on the web client's schedule, so the web and phone apps pick up where you stopped.
- Speed presets, a fine step, and quick keys: `S` 2x, `A` 1.5x, `X` 1.2x, `Z` back to 1x.
- Sleep timer with a gentle fade, including end of chapter.
- Mini player (`⌘⇧M`): a small floating panel with the book, play/pause, jumps and speed. It stays on top across Spaces and full-screen apps without stealing focus.
- Keep awake (☕): the Mac stays awake while a book plays. With a one-time permission it keeps playing with the lid closed too, and gives sleep back the moment playback stops, the sleep timer fires, or the battery drops under 20%.
- Books can be downloaded for offline listening. Offline sessions are uploaded when you're back online.
- You stay logged in: tokens refresh on their own.

## Keys

| Key | Action |
|---|---|
| Space | Play / pause |
| ← / → | Jump back / forward |
| ⌘← / ⌘→ | Previous / next chapter |
| ↑ / ↓ | Volume |
| ⇧↑ / ⇧↓ | Speed step |
| S · A · X · Z | 2x · 1.5x · 1.2x · 1x |
| M | Mute |
| L | Chapters |
| ⌘⇧M | Mini player |
| ⌘1 to ⌘7 | Home, Library, Series, Collections, Playlists, Authors, Narrators |

It's not affiliated with the Audiobookshelf project. Tested against server 2.36.

## Build

Needs macOS 15 or later and the Xcode Command Line Tools.

```sh
./build.sh   # builds and installs ~/Applications/Audiobookshelf.app
./test.sh    # unit tests
```

Set `SIGN_IDENTITY` to a code-signing identity (a self-signed one is fine) if you want the Local Network permission to survive rebuilds.

The lid-closed option installs one sudoers rule, `/etc/sudoers.d/audiobookshelf-lid`, that allows only `pmset -a disablesleep 0|1`. Remove that file to undo it. If lid sleep ever stays off after a crash or power loss, the next launch restores it, or run `sudo pmset -a disablesleep 0`.

## License

GPL-3.0, like Audiobookshelf itself. See `LICENSE` and `NOTICE` for the bundled fonts and strings.
