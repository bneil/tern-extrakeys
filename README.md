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
> block, so it *should* appear on any client attached to the host. Run Plugin Check first
> (palette › **New Plugin Check block**, then tap your shell; you should see
> `tern-plugin-ok`).
>
> The docs disagree on installing from a subfolder. The Distribution guide says "there is no way
> to name a subdirectory", but its own table and the CLI reference accept
> `github.com/OWNER/REPO/subdir`. If the `/hello` line fails, clone the repo and run
> `tern plugin install ./tern-extrakeys/hello`.

For development, clone the repo and run `tern plugin link .` (and `tern plugin link ./hello`).
Edits then reload live.

## Use

To open the bar, use the palette › **New Extra Keys block**, or **Extra Keys: open bar below this
pane** (window half). Pick the target pane with **→**.

- **Keys**: a tap sends the key's bytes to the target pane.
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

1. `<plugin data>/termux.properties` (`extra-keys` and `extra-keys-style`)
2. `<plugin data>/extra-keys.json` (just the `extra-keys` value)
3. `~/.termux/termux.properties`
4. Termux's default:

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
