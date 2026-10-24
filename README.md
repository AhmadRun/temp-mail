# Temp Mail for Omarchy

A disposable email address in the Omarchy bar. Use it to sign up on websites without giving them your real email. The address lives for 10 or 30 minutes, then it is deleted, together with everything it received.

Powered by the free [mail.tm](https://mail.tm) API.

## Features

- One click makes a random address and copies it to the clipboard.
- The bar shows a countdown (`󰇮 8:42`) and the number of unread emails.
- Inbox popup: sender, subject, and age of each email.
- Emails are shown as plain text with clickable links. Nothing loads from the sender unless you press **Open in browser**, which opens the HTML version with scripts and forms blocked.
- Verification codes get a **Copy code** button.
- **+10 min** adds time (an address never lives more than 60 minutes from now), **New** replaces the address, and **Delete** removes it right away.
- A notification arrives for new mail and one minute before the address expires.
- Survives shell restarts and suspend: expiry is checked against the real clock.

## Install

```bash
omarchy plugin add https://github.com/AhmadRun/temp-mail --enable
```

Or copy this folder to `~/.config/omarchy/plugins/io.github.ahmadrun.temp-mail/` and run `omarchy plugin enable io.github.ahmadrun.temp-mail`.

Needs `curl`, `jq`, and `wl-copy` (all part of Omarchy).

## Usage

| Action | How |
|---|---|
| Open the popup | Left-click the bar icon |
| Copy the address (or create one) | Middle-click the bar icon |
| Move / open / delete a message | `↑` `↓`, `Enter`, `Delete` |
| Copy, new, refresh, extend | `c`, `n`, `r`, `+` |
| Back / close | `Esc` |

Keybind-friendly IPC:

```bash
omarchy-shell io.github.ahmadrun.temp-mail toggle
omarchy-shell io.github.ahmadrun.temp-mail.mail create 10   # or 30
omarchy-shell io.github.ahmadrun.temp-mail.mail copy
omarchy-shell io.github.ahmadrun.temp-mail.mail extend
omarchy-shell io.github.ahmadrun.temp-mail.mail remove
```

The helper also works from a terminal: `bin/temp-mail new 10`, `bin/temp-mail messages`, `bin/temp-mail delete`.

## Settings

In the plugin settings form: default lifetime (10 or 30 minutes), extend minutes, how often to check for mail, new-mail notifications, and icon-only mode.

## Privacy

- The account token is stored only in `~/.local/state/omarchy/settings/temp-mail.json` (mode 0600). It reaches `curl` through stdin, never through process arguments.
- New-mail notifications show only the sender, never the subject, because subjects often carry codes.
- Anyone who knows the address can't read it, but mail.tm can. Never use a temp address for anything important or for account recovery.
- Some websites block known temp-mail domains.

## Tests

```bash
node tests/test_temp_mail.js
```

## License

MIT
