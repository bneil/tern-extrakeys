# Extra Keys for Tern

This is a Termux-style **extra-keys bar** for [Tern](https://stencil.so/tern) by Stencil. It's a
small pane of buttons (ESC, CTRL, ALT, TAB, arrows, `-`, `/`, `|`, HOME, END, PGUP,
PGDN, …). Each tap types the matching bytes into a terminal pane you choose. The
layout uses Termux's own `extra-keys` format, so an existing
`~/.termux/termux.properties` layout works unchanged.

The folder holds two plugins and some tests:

| Folder | Plugin id | What it is |
|---|---|---|
| `extrakeys/` | `extrakeys` | The bar: block type `extrakeys.bar` (host half), plus an optional window half |
| `hello/` | `ek-hello` | **Plugin Check**: a diagnostic that shows which plugin halves your Tern client runs |
| `tests/` | — | Unit tests for the config parser and key encoder, plus a simulated run of every entry |

> **Android status: unverified.** Tern's plugin docs (docs.stencil.so/tern) cover
> macOS, Linux, Windows, iOS and the web tab only. Android isn't mentioned. The
> 0.9.0 Android APK exists, but nobody has documented whether it runs plugins. Use **Plugin Check**
> (below) to find out before relying on the bar.

## How it works (and why it's a pane, not a keyboard toolbar)

Tern plugins can't add UI above the on-screen keyboard. No API for that is
documented. What a plugin *can* do:

- **Host half** (`host.luau`, runs in the session daemon). It can define a block (a pane
  drawn from Lua) whose buttons send events back to the host, and it can write bytes into
  any pane on that host with `tern.pane.write(pane, text)`. Blocks are mirrored to every
  client attached to the session. The docs say this for the iOS client and the web tab,
  where clicks still reach the host's code. If the Android app attaches to a desktop
  host the same way, the bar should show up there too.
- **Window half** (`window.luau`, runs in each Tern window). It adds a palette command that
  opens the bar below the focused pane, and it remembers the focused terminal for
  "follow" mode.

So the bar is an ordinary pane. Split it under your shell and make it short.

## Install

On the machine that runs your shells (the host your Android app connects to):

```sh
git clone <this repo> tern-extrakeys        # or unzip tern-extrakeys.zip
cd tern-extrakeys
tern plugin link ./hello                    # optional: the diagnostic
tern plugin link ./extrakeys                # development: edits reload live
# or copy instead of linking:
tern plugin install ./extrakeys
tern plugin list                            # both should say "ready"
```

`tern plugin link`/`install`/`list` are the documented CLI verbs. Tern reloads on save.
On iOS, where there's no CLI, the docs say to copy plugin folders into Files › Tern ›
Plugins. Only the window half runs there; blocks come from the host.

### Android (undocumented, test first)

1. Install both plugins on the **desktop host** as above. The host half runs there, not on
   the phone.
2. In the Android app, connect to that host and open a shell.
3. Open the palette and run **New Plugin Check block**. Palette rows for plugin blocks come
   from the host's catalog, so this doesn't need any plugin code on the phone.
4. Tap the button for your shell pane. If `echo tern-plugin-ok` appears and runs in
   that shell, host-half blocks and taps work on Android, and so will the bar.
5. Check the window half. If the status line shows `plugin check: window <os>` (or a
   "window half loaded" toast appears), the APK runs window halves from *some* plugins
   folder. That folder isn't documented for Android. If nothing appears, it doesn't, or
   it isn't loading them from the host.
6. Open the bar: palette › **New Extra Keys block** (or, where the window half runs,
   **Extra Keys: open bar below this pane**). Pick your shell with the `→` button.

## Using the bar

- **Tap a key**: its bytes go to the target pane.
- **CTRL / ALT / SHIFT / FN** are one-shot sticky modifiers, as in Termux. A tap arms one
  (highlighted) and the next key uses it up. Tapping an armed modifier again turns it off.
- **Lock a modifier**: double-tap it, or tap 🔒 and then the modifier. A locked modifier is filled
  in and stays on until you tap it again. (Termux uses long-press, but Tern's view actions
  only offer `click` and `dblclick`.)
- **⇅ (popup layer)**: Termux opens a key's `popup` when you swipe up on it. Here ⇅ swaps every key
  to its popup for one tap. Double-tap ⇅ to keep the popup layer on. Keys with a popup have
  an underline.
- **→ target**: opens a picker of the host's panes (it hides other Extra Keys bars). The
  choice is saved with the bar and remembered as the default for new bars.
- **APP**: application cursor mode. Arrows and Home/End send `ESC O A` instead of `ESC [ A`.
  Turn it on if arrows misbehave in a full-screen program (see limits below).
- **follow**: types into whichever terminal pane is focused instead of a fixed one. It needs
  the window half running on the **same machine** as the daemon, because they share
  `tern.kv`. Desktop only, in practice.
- **⟳**: reloads the config.
- **Typing while the bar is focused**: keys you press while the bar pane itself has focus
  are passed to the target, with the sticky modifiers applied. Pastes are passed through as-is.
  This is the only way the bar's modifiers can apply to keyboard letters (see limits).

## Configuration (Termux format)

The bar reads the first of these that exists, on the host:

1. `<plugin data>/termux.properties`: a properties file with `extra-keys` and
   `extra-keys-style`. The data folder is Tern's per-plugin data directory, the one that
   holds `kv.json`.
2. `<plugin data>/extra-keys.json`: just the `extra-keys` value.
3. `~/.termux/termux.properties`: an existing Termux file, if the host has one.
4. The Termux default:

```properties
extra-keys = [['ESC','/',{key: '-', popup: '|'},'HOME','UP','END','PGUP'], \
              ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]
extra-keys-style = default
```

The format is a port of termux-app's `ExtraKeysInfo`:

- A list of rows. Each key is a name, or an object `{key: …}` / `{macro: …}` with optional
  `display` and `popup` (a name or another object).
- `macro` is space-separated. `CTRL`, `ALT`, `SHIFT` and `FN` apply to the next key and then
  reset, e.g. `{macro: 'CTRL f d', display: 'tmux exit'}`.
- Named keys: ESC TAB ENTER BKSP DEL INS SPACE UP DOWN LEFT RIGHT HOME END PGUP PGDN F1–F12,
  plus CTRL ALT SHIFT FN. Anything else is typed as text.
- Aliases, which are case-sensitive as in Termux: ESCAPE CONTROL SHFT RETURN FUNCTION LT RT DN PAGEUP
  PAGE_UP "PAGE UP" PAGE-UP PAGEDOWN PAGE_DOWN PAGE-DOWN DELETE BACKSPACE BACKSLASH QUOTE
  APOSTROPHE.
- `extra-keys-style`: `default`, `arrows-only`, `arrows-all`, `all`, or `none` (Termux's display maps).
- The syntax is as lenient as Termux's org.json: bare words, `'single'` or `"double"`
  quotes, `,` or `;` separators. Properties files follow java.util.Properties rules, including `\`
  line continuation and escapes, so write `BACKSLASH` rather than `\`.
- If a config file has an error, the bar uses the default layout and shows the error.
- `KEYBOARD`, `DRAWER`, `PASTE` and `SCROLL` control the Termux app itself and do nothing here.

Bytes sent (xterm-style, the same as Termux's normal mode):

- ESC `\e`, TAB `\t` (Shift+TAB `\e[Z`), ENTER `\r`, BKSP `\x7f` (Ctrl `\b`).
- Arrows `\e[A–D`, HOME `\e[H`, END `\e[F`.
- INS/DEL/PGUP/PGDN `\e[2~ 3~ 5~ 6~`.
- F1–F4 `\eOP–S`, F5–F12 `\e[15~ … 24~`.
- With modifiers: `\e[1;<m>X` or `\e[<n>;<m>~`, where m = 1 + Shift + 2·Alt + 4·Ctrl.
- Text: Ctrl maps letters and `@[\]^_ 2-8 / space` to control bytes (as Termux does), Alt puts
  `\e` in front, and Shift uppercases ASCII letters.

## Known limits

- **Not above the keyboard.** It's a pane you place yourself. The keyboard can cover it, and
  it takes up rows of screen.
- **Raw bytes, not key events.** Termux sends key events through its terminal view, which
  adapts to the running program's modes. A plugin can only write bytes. Arrows default to
  normal mode (`\e[A`), which can misbehave in full-screen programs that switch to
  application cursor mode (some `vim`/`less` setups). Use **APP** for those. Programs that
  turned on the kitty keyboard protocol see plain legacy sequences. Bracketed paste
  isn't added.
- **No swipe-up, long-press, key repeat or haptics.** Tern's actions are `click` and
  `dblclick` only. Instead there's ⇅ for popups and double-tap/🔒 for locks. Holding an arrow
  doesn't repeat it.
- **Modifiers don't reach the phone keyboard's letters** when you type into the shell pane.
  Those keystrokes go to the shell, and no documented hook lets a plugin see or change
  them. Either tap letters in a macro/key, or type into the focused bar (see above).
- **Focus stealing.** Tapping the bar may focus it and close or move the soft keyboard
  (compare tern-sdk issue #52, where touch on Android opens or closes the keyboard unexpectedly).
  Not tested on a device.
- **Target choice is host-side.** The host API has no "focused pane". `follow` needs the
  window half and the daemon on one machine. Pane ids from a remote window may not match
  host ids. The palette command passes the focused pane id as a launch argument, and the bar
  ignores ids its host doesn't list.
- `FN` is shown and toggles, but changes no bytes (Termux uses it for its own key handling).

## Development

```sh
tern plugin types .            # writes tern.d.luau for your Tern (or copy it from tern-sdk)
./check.sh                     # luau-lsp analyze (strict) + tests
```

`check.sh` runs `luau-lsp analyze --platform=standard --definitions=@tern=tern.d.luau` on
every entry and module, as the Getting Started page recommends. It then runs `tests/run.luau`
with the `luau` CLI. `tests/embed.py` embeds the entry sources so the tests can run them
against a mock `tern` table. The bundled `tern.d.luau` is copied from stencil-hq/tern-sdk.
Regenerate it with `tern plugin types .` to match your Tern version.

Code map:

- `extrakeys/lib/config.luau`: parser and Termux tables (pure Luau)
- `extrakeys/lib/keys.luau`: key and macro to bytes (pure Luau)
- `extrakeys/host.luau`: the block
- `extrakeys/window.luau`: palette command and focus tracking
- `extrakeys/extrakeys.css`: styles, scoped to `[data-surface='plugin.extrakeys.bar']`
