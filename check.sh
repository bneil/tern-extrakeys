#!/usr/bin/env sh
# Type-check both plugins against Tern's API definitions and run the tests.
# Needs: luau-lsp and luau on PATH (or LUAU_LSP / LUAU set), python3.
# TERN_DEFS defaults to ./tern.d.luau; create it with `tern plugin types .`
# (or copy plugins/tern.d.luau from github.com/stencil-hq/tern-sdk).
set -eu
cd "$(dirname "$0")"
LUAU_LSP=${LUAU_LSP:-luau-lsp}
LUAU=${LUAU:-luau}
DEFS=${TERN_DEFS:-tern.d.luau}
"$LUAU_LSP" analyze --platform=standard --definitions=@tern="$DEFS" \
	host.luau window.luau lib/config.luau lib/keys.luau \
	hello/host.luau hello/window.luau
python3 tests/embed.py
"$LUAU" tests/run.luau
