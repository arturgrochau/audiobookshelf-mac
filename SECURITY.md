# Security policy

## Supported versions

Only the latest commit on `main` is supported. There are no release branches yet.

## Reporting a vulnerability

Please report security issues privately, not in a public issue:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.

This is a one-person project. I'll acknowledge a report within a week and keep you updated until it's fixed. If you'd like credit in the fix commit, say so in the report.

## What the app touches

Useful context when you're looking for problems:

- **Network:** the app talks only to the Audiobookshelf server you log in to (and its optional local address). There is no analytics or telemetry.
- **Tokens:** the access and refresh tokens are stored in `~/Library/Application Support/Audiobookshelf/account.json` with mode `0600`.
- **Password:** kept in your login Keychain, used only to log back in silently when the refresh token has expired.
- **Lid-closed playback (optional):** after you agree to it and enter your admin password, the app installs `/etc/sudoers.d/audiobookshelf-lid`. That rule allows exactly `pmset -a disablesleep 0` and `pmset -a disablesleep 1`, nothing else. The rule is written and validated with `visudo` inside the privileged shell. Delete the file to remove it.
- **URL scheme:** `audiobookshelf://` accepts playback, navigation and appearance commands (play, pause, speed, seek, open a page, mini player, theme). Test hooks that start or delete downloads are off unless you enable `debugURLRoutes` in the app's defaults.
