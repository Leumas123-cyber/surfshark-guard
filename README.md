# Surfshark Guard

Unofficial macOS menu-bar helper (Apple Silicon, macOS 13+) that keeps [qBittorrent](https://www.qbittorrent.org) bound to the current VPN tunnel ([Surfshark](https://surfshark.com), plus unofficial detection for Mullvad, Proton VPN, or any WireGuard).

**Download:** [latest DMG](https://github.com/Leumas123-cyber/surfshark-guard/releases/latest)

This is **not** a Surfshark or qBittorrent product. It is a hobby upload. I vibe-coded it and I am **not** an expert on this codebase. The notes below describe how the project is *supposed* to work. If something breaks, **fix it yourself** (or don’t use it). There is no support.

## Why this exists

I only uploaded this so other people don’t have to repeat the same annoying manual check every time they want BitTorrent traffic to stay on a VPN tunnel.

Many WireGuard VPNs (Surfshark included) create a new `utun` interface on almost every reconnect. qBittorrent’s *Settings → Advanced → Network interface* is a **fixed** choice. After a reconnect that old interface is gone, so transfers stall — or worse, they can fall back to Wi‑Fi/Ethernet and leak your real IP.

This app watches the tunnel and rewrites qBittorrent’s interface binding so you don’t have to poke `ifconfig` / `netstat` / the qBittorrent settings by hand each time.

## Legal (please read)

- **Open source:** MIT License. See [LICENSE](LICENSE).
- **Lawful use only.** This tool only changes which **local network interface** qBittorrent uses. It does not download anything, crack anything, bypass copyright, or hide illegal activity. If you use BitTorrent, you are responsible for sharing only content you have the right to share. I am not telling you to infringe copyright, and I am not responsible if you do.
- **Not affiliated.** Surfshark and qBittorrent are trademarks of their owners. This project is unofficial and unauthorized. I don’t speak for those companies.
- **No warranty.** MIT already says this. I’ll say it again: I vibe-coded this. I do not really know, in a professional sense, that every path is correct. Use at your own risk. If it fails, fix it or delete it.
- **Not legal advice.** This README is not a lawyer. If you need one, get one.

## First-run on a downloaded DMG

The DMG is ad-hoc signed (no paid Apple Developer ID / notarization). macOS Gatekeeper will complain once.

1. Open the DMG and drag **Surfshark Guard** into **Applications**.
2. **Right-click** the app → **Open** → **Open**.
3. Or, in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/SurfsharkGuard.app
```

Needs an Apple Silicon Mac. Intel Macs are not supported.

## Using it

1. Connect the VPN as a **full tunnel**. Do not put qBittorrent in a split-tunnel / bypass list. Settings → Provider can stay **Auto**, or pick Surfshark / Mullvad / Proton VPN / Any WireGuard.
2. Start Surfshark Guard. A shield appears in the menu bar. First launch opens a short setup checklist.
3. Turn on **Watch**. Optionally **Auto-fix**, **Pause if down**, and **Alerts**.
4. For live rebinding while qBittorrent is running, enable qBittorrent’s Web UI on `127.0.0.1` and type those credentials under **Settings**. The password is stored in the **macOS Keychain** on your Mac (older UserDefaults copies are migrated once, then deleted). Requests only go to localhost. If the menu says **Web UI offline / check**, qBittorrent’s Web UI is not answering. The menu prefers the **live** Web UI binding over a stale `qBittorrent.ini`.

**Quit qB & bind** quits qBittorrent normally (not force-killed) and writes the tunnel name into `qBittorrent.ini`.

| Icon | Meaning |
|---|---|
| Green shield | qBittorrent is bound to the tunnel |
| Red shield | Wrong or missing binding — leak risk |
| Orange slash | No VPN tunnel right now |

## How the project works

This is the part I *can* describe from the source. If I got a detail wrong, read the Swift files. They are short.

### Pieces

| File | Job |
|---|---|
| `SurfsharkGuardApp.swift` | Menu-bar SwiftUI app (`LSUIElement`, no Dock icon) plus a settings window |
| `Detector.swift` | Asks macOS which VPN interface is the current tunnel |
| `VPNProvider.swift` | Process matching for Auto / Surfshark / Mullvad / Proton / WireGuard |
| `Parsers.swift` | Parses `route` / `netstat` / `ifconfig` text and edits `qBittorrent.ini` |
| `QBittorrent.swift` | Finds the newest qBittorrent config on **this** user account and writes a backup + new binding |
| `WebUI.swift` | Optional localhost login, live prefs, pause-all, plus a cheap reachability probe |
| `Keychain.swift` | Web UI password in the macOS Keychain (migrates leftover UserDefaults) |
| `GuardState.swift` | Timer (5 s default, with tolerance), `NWPathMonitor`, pause-on-drop, notifications, auto-fix, login-item toggle |
| `Views.swift` | Menu and settings UI |
| `OnboardingView.swift` | First-run checklist (VPN, tunnel, localhost Web UI, login test) |

There are no servers of mine, no analytics, and no account. The app only talks to your Mac and, if you enable it, `http://127.0.0.1` on qBittorrent.

### How it picks the tunnel

Every check runs roughly this, in order:

1. `ifconfig -a` — keep `utun*` / `ipsec*` / `ppp*` interfaces that have a real IPv4 (not `127.*`). iCloud’s extra utuns usually have no IPv4, so they are ignored.
2. `route -n get default` — if the default route sits on one of those VPN interfaces, that is the tunnel.
3. Else `netstat -rn -f inet` — look for WireGuard-style full-tunnel routes `0/1` and `128.0/1` on a VPN interface.
4. Else, if a matching VPN process is running and there is **exactly one** VPN interface with IPv4, use that.
5. `pgrep` against the selected provider — warn if that VPN app is not running (the tunnel might belong to something else).

If a tunnel is up but an `en*` interface still has a **global IPv6**, the menu shows a leak hint. The app does not disable IPv6 for you.

### How it rebinds qBittorrent

qBittorrent stores the chosen NIC as `Session\Interface` / `Session\InterfaceName` (and sometimes `Session\InterfaceAddress`) under `[BitTorrent]`.

The app looks for the newest of:

- `~/Library/Preferences/qBittorrent/qBittorrent.ini`
- `~/Library/Application Support/qBittorrent/qBittorrent.ini`
- `~/.config/qBittorrent/qBittorrent.ini`

Paths use **your** home directory at runtime. Nothing from my Mac is hardcoded.

- **Web UI on:** `POST /api/v2/auth/login`, then read `GET /api/v2/app/preferences` for the live NIC, and `POST /api/v2/app/setPreferences` to rebind. Takes effect immediately.
- **Web UI off:** write the ini (with a `.bak-…` next to it). qBittorrent must be quit first or it will overwrite the file when it exits. Auto-fix will **not** force-quit qBittorrent.
- **Pause if down:** when the status flips from “has a tunnel” to “no tunnel”, the Web UI is asked to pause/stop all torrents (`/torrents/stop`, then `/torrents/pause` for older qB).

**Watch** repeats `route` / `ifconfig` on a timer (default 5 seconds, never a tight loop) and also after `NWPathMonitor` path changes (debounced ~0.4 s). The timer has macOS coalescing tolerance and stretches in Low Power Mode. **Auto-fix** tries the Web UI, or the ini write once qBittorrent is already quit.

### Build (if you don’t trust the DMG)

```bash
git clone https://github.com/Leumas123-cyber/surfshark-guard.git
cd surfshark-guard
./scripts/make-app.sh
```

That script builds **arm64** only, strips debug info, remaps source paths so the binary should not contain the builder’s `/Users/…` path, ad-hoc signs the app, and makes a DMG.

## If it does not work

Fix it yourself. This is vibe-coded. I am not offering support, refunds, or a guarantee that I understand every edge case.

Ideas if you want to poke at it:

- Confirm the VPN is connected as a full tunnel and qBittorrent is **not** in a bypass / split-tunnel list.
- Click **Check now** and read the status text.
- Enable the Web UI on localhost if you want live fixes.
- Read `Detector.swift` and `GuardState.swift`.

Pull requests are fine if you want to send a fix. I may or may not merge them. Issues that are just “it doesn’t work, please help” will probably sit there.

## Privacy of this upload

The published source and the Release DMG are meant to contain no home-folder paths, no passwords, and no settings from my machine. The Web UI password you type later lives in **your** Keychain (`app.surfsharkguard.webui`), not in the app binary.

## Limits

- Only qBittorrent is rebound. Other apps need Surfshark’s own kill switch or a firewall.
- An ini-file fix applies on the next qBittorrent start unless the Web UI is enabled.

## License

[MIT](LICENSE). Unofficial community tool. Use at your own risk.
