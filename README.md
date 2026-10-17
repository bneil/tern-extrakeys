# tern-extrakeys

A Termux-style extra-keys bar for [Tern](https://stencil.so/tern) by Stencil. It's a pane of
buttons (ESC, CTRL, ALT, TAB, arrows, `-`, `/`, `|`, HOME, END, PGUP, PGDN, …) that types
into a terminal pane you choose. It uses Termux's own `extra-keys` config format.

## Install

On the machine that runs your shells:

```sh
tern plugin install github.com/bneil/tern-extrakeys
```

Optional diagnostic, **Plugin Check**, to see which plugin halves your client runs:

```sh
tern plugin install github.com/bneil/tern-extrakeys/hello
```

> **Android: untested so far.** Tern's docs don't cover Android. The bar is a host-side
> block, so it *should* appear on any client attached to the host. Plugin Check shows
> whether your client runs window halves, without needing the palette. Look for a
> `plugin check: window …` status segment and a "window half loaded" toast. Tapping the
> segment types `echo tern-plugin-ok-window` into the focused shell.
>
> The docs disagree on installing from a subfolder. The Distribution guide says "there is no way
> to name a subdirectory", but its own table and the CLI reference accept
> `github.com/OWNER/REPO/subdir`. If the `/hello` line fails, clone the repo and run
> `tern plugin install ./tern-extrakeys/hello`.

Installing the bar puts the `⌨ keys` segment in the status line and opens one bar when a window
starts (see [Opening the bar](#opening-the-bar)).

For development, clone the repo and run `tern plugin link .` (and `tern plugin link ./hello`).
Edits then reload live.

## Opening the bar

None of these need the command palette:

- **Auto-open (on by default).** When a Tern window starts and its session has no Extra Keys
  bar yet, one opens below the focused shell, aimed at it. Restored sessions and extra
  windows don't get a second bar. Closing the bar keeps it closed until the next window
  start.
- **The `⌨ keys` status-line segment.** Tap it to open a bar below the focused pane, aimed at
  it. If no shell is focused, the bar opens and asks you to pick a pane. The segment only
  shows while Tern's status bar is on.
- **"Open with › Extra Keys" on a config file.** This is Tern's ⋯ menu on a file block, or the
  Files pane's context menu, for a file named `termux.properties`, `extra-keys.json` or
  `*.extra-keys.json`. The bar uses that file as its layout. One way to get there without
  the palette is to type `tern open ~/.termux/termux.properties` in a shell, then use the file's
  ⋯ menu. Tern's docs describe these menus, but they haven't been tried on Android.
- **With a keyboard:** palette › **New Extra Keys block** or **Extra Keys: open bar below this
  pane**. You can also bind `plugin.extrakeys.open` in `settings.json` `keybinds`.

The first two need the plugin's window half to run in your client. The docs don't document
any other palette-free way to open a plugin block. The other documented openers (routes,
layouts and workspaces, `cx:new_block`) all run from plugin code.

### Turning auto-open off

Either:

- run **Extra Keys: toggle opening a bar when a window starts** (it's stored per machine in
  `tern.kv`); or
- create `extrakeys.properties` in the plugin's data folder (`<state>/plugin-data/extrakeys/`
  on the machine running the window) containing:

  ```properties
  auto-open = false
  ```

The toggle command's choice wins over the file.

## Troubleshooting

- **No `⌨ keys` in the status line, and no bar appears at start:** your client isn't running
  the plugin's window half. This may be the case on the Android APK, which Tern's docs don't
  cover. First check the status bar is on. Then install Plugin Check: if its
  `plugin check: window …` segment and its "window half loaded" toast don't appear either,
  window halves don't run there. The bar itself is host-side, so it still works once it's
  open. Try "Open with" (above), or open it from a desktop window attached to the same
  session; the bar shows up on every client.
- **"Extra Keys isn't ready on this host":** install the plugin on the machine that runs your
  shells (`tern plugin list` there should say ready).

## Use

- **Keys**: a tap sends the key's bytes to the target pane. **→** picks the target.
- **CTRL / ALT / SHIFT / FN**: one-shot, so a tap arms the modifier for the next key. Double-tap,
  or 🔒 then the modifier, locks it on. Tap again to release.
- **⇅**: shows each key's `popup` (Termux's swipe-up key) for one tap. Double-tap to keep it on.
- **APP**: application cursor keys, which make arrows send `ESC O A`. Use it if arrows misbehave
  in full-screen programs.
- **follow**: types into the focused terminal pane. This needs the window half on the same machine as the daemon.
- **⟳**: reloads the config.
- Keys typed while the bar itself is focused are forwarded to the target, with the sticky
  modifiers applied.

## Config

The bar reads the first file that exists, on the host:

1. the file it was opened with through "Open with" (remembered across restarts)
2. `<plugin data>/termux.properties` (`extra-keys` and `extra-keys-style`)
3. `<plugin data>/extra-keys.json` (just the `extra-keys` value)
4. `~/.termux/termux.properties`
5. Termux's default:

```properties
extra-keys = [['ESC','/',{key: '-', popup: '|'},'HOME','UP','END','PGUP'], \
              ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]
```

The format is the same as Termux's:

- Keys are names, or `{key|macro, display, popup}` objects.
- Macros are space-separated, with modifiers applying to the next key (`{macro: 'CTRL f d'}`).
- Termux's aliases and `extra-keys-style` values (`default`, `arrows-only`, `arrows-all`, `all`,
  `none`) work.
- A broken config falls back to the default and shows the error.
- `KEYBOARD`, `DRAWER`, `PASTE` and `SCROLL` are Termux app keys and do nothing here.

## Limits

- It's a pane you place yourself, not a toolbar pinned above the soft keyboard. Tern has no API for that.
- It sends raw xterm-style bytes, not key events, so it can't follow a program's cursor mode
  (use **APP**) or the kitty keyboard protocol.
- No swipe, long-press, key repeat or haptics. Tern only offers click and double-click.
- Sticky modifiers don't apply to letters typed on the phone keyboard into the shell pane.
- Tapping the bar may move focus away from the shell and hide the soft keyboard. Untested.

## Development

```sh
tern plugin types .   # or copy tern.d.luau from github.com/stencil-hq/tern-sdk
./check.sh            # luau-lsp type check + tests (needs luau-lsp, luau, python3)
```

The pure modules are `lib/config.luau` (the Termux config parser) and `lib/keys.luau` (keys to
bytes). The block is in `host.luau`, and the palette command and focus tracking are in `window.luau`.
Tests in `tests/run.luau` cover the parser and encoder, and run both plugins against a mock
`tern` API.

## License

MIT. See [LICENSE](LICENSE).
