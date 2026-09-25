# Audiobookshelf for macOS (unofficial)

A native Mac client for [Audiobookshelf](https://github.com/advplyr/audiobookshelf). It looks and works like the web client, with the same pages, player controls and wording, but plays audio through AVFoundation.

- Playback keeps going when the window is closed. Media keys and Now Playing work.
- Multi-file books play gaplessly, straight from the server.
- Progress syncs on the web client's schedule.
- Books can be downloaded for offline listening. Offline sessions are uploaded when you're back online.
- You stay logged in: tokens refresh on their own.

It's not affiliated with the Audiobookshelf project. Tested against server 2.36.

## Build

Needs macOS 15 or later and the Xcode Command Line Tools.

```sh
./build.sh   # builds and installs ~/Applications/Audiobookshelf.app
./test.sh    # unit tests
```

Set `SIGN_IDENTITY` to a code-signing identity (a self-signed one is fine) if you want the Local Network permission to survive rebuilds.

## License

GPL-3.0, like Audiobookshelf itself. See `LICENSE` and `NOTICE` for the bundled fonts and strings.
