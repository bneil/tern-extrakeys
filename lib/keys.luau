--!strict
-- Key names and text to the bytes a terminal expects (xterm-style, the
-- sequences Termux's KeyHandler sends in normal mode), plus macro expansion
-- in the way termux-app's TerminalExtraKeys does it. Pure Luau.

local M = {}

export type Mods = { ctrl: boolean, alt: boolean, shift: boolean, fn: boolean }

M.MODIFIERS = { CTRL = true, ALT = true, SHIFT = true, FN = true } :: { [string]: boolean }

-- Termux-only keys that act on the Termux UI, not the terminal.
M.APP_KEYS = { KEYBOARD = true, DRAWER = true, PASTE = true, SCROLL = true } :: { [string]: boolean }

local ESC = "\27"

local function no_mods(): Mods
	return { ctrl = false, alt = false, shift = false, fn = false }
end
M.no_mods = no_mods

-- xterm modifier parameter: 1 + shift(1) + alt(2) + ctrl(4).
local function mod_param(m: Mods): number
	local n = 1
	if m.shift then
		n += 1
	end
	if m.alt then
		n += 2
	end
	if m.ctrl then
		n += 4
	end
	return n
end

-- CSI final letters (arrows, home/end) and SS3 for the app cursor mode.
local LETTER = { UP = "A", DOWN = "B", RIGHT = "C", LEFT = "D", HOME = "H", END = "F" } :: { [string]: string }
-- CSI <n> ~ keys.
local TILDE = {
	INS = 2,
	DEL = 3,
	PGUP = 5,
	PGDN = 6,
	F5 = 15,
	F6 = 17,
	F7 = 18,
	F8 = 19,
	F9 = 20,
	F10 = 21,
	F11 = 23,
	F12 = 24,
} :: { [string]: number }
-- F1-F4: SS3 P..S, CSI 1;m P..S with modifiers.
local PF = { F1 = "P", F2 = "Q", F3 = "R", F4 = "S" } :: { [string]: string }

--- Whether `name` is one of Termux's PRIMARY_KEY_CODES_FOR_STRINGS (a named key, not text).
function M.is_named(name: string): boolean
	return LETTER[name] ~= nil
		or TILDE[name] ~= nil
		or PF[name] ~= nil
		or name == "ESC"
		or name == "TAB"
		or name == "ENTER"
		or name == "BKSP"
		or name == "SPACE"
end

local function alt_prefix(m: Mods, s: string): string
	if m.alt then
		return ESC .. s
	end
	return s
end

--- Bytes for a named key. `app_cursor` mirrors DECCKM (application cursor
--- keys): arrows and Home/End send SS3 instead of CSI when unmodified.
function M.named(name: string, m: Mods, app_cursor: boolean?): string?
	local any = m.shift or m.alt or m.ctrl
	local letter = LETTER[name]
	if letter then
		if any then
			return string.format("%s[1;%d%s", ESC, mod_param(m), letter)
		elseif app_cursor then
			return ESC .. "O" .. letter
		end
		return ESC .. "[" .. letter
	end
	local n = TILDE[name]
	if n then
		if any then
			return string.format("%s[%d;%d~", ESC, n, mod_param(m))
		end
		return string.format("%s[%d~", ESC, n)
	end
	local pf = PF[name]
	if pf then
		if any then
			return string.format("%s[1;%d%s", ESC, mod_param(m), pf)
		end
		return ESC .. "O" .. pf
	end
	if name == "ESC" then
		return alt_prefix(m, ESC)
	elseif name == "TAB" then
		if m.shift then
			return ESC .. "[Z"
		end
		return alt_prefix(m, "\t")
	elseif name == "ENTER" then
		return alt_prefix(m, "\r")
	elseif name == "BKSP" then
		return alt_prefix(m, if m.ctrl then "\8" else "\127")
	elseif name == "SPACE" then
		return alt_prefix(m, if m.ctrl then "\0" else " ")
	end
	return nil
end

-- Ctrl applied to one code point, as Termux's TerminalView.inputCodePoint does.
local function ctrl_byte(cp: number): number?
	if cp >= 97 and cp <= 122 then -- a-z
		return cp - 96
	elseif cp >= 65 and cp <= 90 then -- A-Z
		return cp - 64
	elseif cp == 32 or cp == 50 or cp == 64 then -- space 2 @
		return 0
	elseif cp == 91 or cp == 51 then -- [ 3
		return 27
	elseif cp == 92 or cp == 52 then -- \ 4
		return 28
	elseif cp == 93 or cp == 53 then -- ] 5
		return 29
	elseif cp == 94 or cp == 54 then -- ^ 6
		return 30
	elseif cp == 95 or cp == 55 or cp == 47 then -- _ 7 /
		return 31
	elseif cp == 56 then -- 8
		return 127
	end
	return nil
end

--- Bytes for typed text with modifiers: Shift uppercases ASCII letters, Ctrl
--- maps to control bytes where one exists, Alt prefixes ESC per character.
function M.text(s: string, m: Mods): string
	local out: { string } = {}
	for _, cp in utf8.codes(s) do
		local c = cp
		if m.shift and c >= 97 and c <= 122 then
			c -= 32
		end
		local piece: string
		local cb = if m.ctrl then ctrl_byte(c) else nil
		if cb ~= nil then
			piece = string.char(cb)
		else
			piece = utf8.char(c)
		end
		table.insert(out, alt_prefix(m, piece))
	end
	return table.concat(out)
end

--- Bytes for one key token (a named key or literal text). Nil for modifiers
--- and Termux app keys, which send nothing.
function M.encode(token: string, m: Mods, app_cursor: boolean?): string?
	if M.MODIFIERS[token] or M.APP_KEYS[token] then
		return nil
	end
	if M.is_named(token) then
		return M.named(token, m, app_cursor)
	end
	return M.text(token, m)
end

--- A macro ("CTRL f d"): modifier tokens apply to the next key, then reset,
--- exactly as TerminalExtraKeys.onExtraKeyButtonClick. Returns the bytes and
--- any app keys it named (which the caller may report as unsupported).
function M.macro(spec: string, app_cursor: boolean?): (string, { string })
	local out: { string } = {}
	local skipped: { string } = {}
	local m = no_mods()
	for token in string.gmatch(spec, "[^ ]+") do
		if token == "CTRL" then
			m.ctrl = true
		elseif token == "ALT" then
			m.alt = true
		elseif token == "SHIFT" then
			m.shift = true
		elseif token == "FN" then
			m.fn = true
		else
			if M.APP_KEYS[token] then
				table.insert(skipped, token)
			else
				local b = M.encode(token, m, app_cursor)
				if b then
					table.insert(out, b)
				end
			end
			m = no_mods()
		end
	end
	return table.concat(out), skipped
end

-- Tern Key.name values (lowercase) to Termux key names, for forwarding keys
-- typed while the bar pane has focus.
local TERN_NAMES = {
	escape = "ESC",
	esc = "ESC",
	tab = "TAB",
	enter = "ENTER",
	["return"] = "ENTER",
	backspace = "BKSP",
	delete = "DEL",
	insert = "INS",
	up = "UP",
	down = "DOWN",
	left = "LEFT",
	right = "RIGHT",
	home = "HOME",
	["end"] = "END",
	page_up = "PGUP",
	page_down = "PGDN",
	space = "SPACE",
} :: { [string]: string }

--- Maps a Tern key name ("up", "f5", "a") to a Termux token, or nil when it
--- is not a named key (the caller then uses the key's text).
function M.from_tern_name(name: string): string?
	local t = TERN_NAMES[name]
	if t then
		return t
	end
	local f = string.match(name, "^f(%d+)$")
	if f then
		local n = tonumber(f) :: number
		if n >= 1 and n <= 12 then
			return "F" .. n
		end
	end
	return nil
end

return M
