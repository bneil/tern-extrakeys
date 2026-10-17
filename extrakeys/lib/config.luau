--!strict
-- Termux-compatible `extra-keys` configuration: a port of termux-app's
-- ExtraKeysInfo / ExtraKeyButton / ExtraKeysConstants (display maps and
-- aliases), plus a lenient reader for the JSON-ish syntax org.json accepts
-- (bare words, single quotes) and a reader for termux.properties files.
-- Pure Luau: no `tern` global, so tests can run it under the plain `luau` CLI.

local M = {}

export type Button = {
	--- Normalized key name, or a space-joined macro (aliases replaced).
	key: string,
	--- True when the button came from `macro`.
	macro: boolean,
	--- Label shown on the button.
	display: string,
	--- The swipe-up key in Termux; here the alternate layer.
	popup: Button?,
}

export type Config = {
	rows: { { Button } },
	style: string,
}

M.DEFAULT_EXTRA_KEYS =
	"[['ESC','/',{key: '-', popup: '|'},'HOME','UP','END','PGUP'], ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]"
M.DEFAULT_STYLE = "default"

-- ExtraKeysConstants.CONTROL_CHARS_ALIASES
M.ALIASES = {
	ESCAPE = "ESC",
	CONTROL = "CTRL",
	SHFT = "SHIFT",
	RETURN = "ENTER",
	FUNCTION = "FN",
	LT = "LEFT",
	RT = "RIGHT",
	DN = "DOWN",
	PAGEUP = "PGUP",
	PAGE_UP = "PGUP",
	["PAGE UP"] = "PGUP",
	["PAGE-UP"] = "PGUP",
	PAGEDOWN = "PGDN",
	PAGE_DOWN = "PGDN",
	["PAGE-DOWN"] = "PGDN",
	DELETE = "DEL",
	BACKSPACE = "BKSP",
	BACKSLASH = "\\",
	QUOTE = '"',
	APOSTROPHE = "'",
} :: { [string]: string }

local function merge(...: { [string]: string }): { [string]: string }
	local out: { [string]: string } = {}
	for _, t in { ... } do
		for k, v in t do
			out[k] = v
		end
	end
	return out
end

-- ExtraKeysConstants.EXTRA_KEY_DISPLAY_MAPS
local CLASSIC_ARROWS = { LEFT = "←", RIGHT = "→", UP = "↑", DOWN = "↓" }
local WELL_KNOWN = {
	ENTER = "↲",
	TAB = "↹",
	BKSP = "⌫",
	DEL = "⌦",
	DRAWER = "☰",
	KEYBOARD = "⌨",
	PASTE = "⎘",
	SCROLL = "⇳",
}
local LESS_KNOWN = { HOME = "⇱", END = "⇲", PGUP = "⇑", PGDN = "⇓" }
local NOT_KNOWN_ISO = { CTRL = "⎈", ALT = "⎇", ESC = "⎋" }
local NICER_LOOKING = { ["-"] = "―" }

M.DISPLAY_MAPS = {
	default = merge(CLASSIC_ARROWS, WELL_KNOWN, NICER_LOOKING),
	["arrows-only"] = merge(CLASSIC_ARROWS, NICER_LOOKING),
	["arrows-all"] = merge(CLASSIC_ARROWS, WELL_KNOWN, LESS_KNOWN, NICER_LOOKING),
	all = merge(CLASSIC_ARROWS, WELL_KNOWN, LESS_KNOWN, NICER_LOOKING, NOT_KNOWN_ISO),
	none = {},
} :: { [string]: { [string]: string } }

function M.display_map(style: string): { [string]: string }
	return M.DISPLAY_MAPS[style] or M.DISPLAY_MAPS.default
end

------------------------------------------------------------------------------
-- Lenient JSON-ish reader (org.json JSONTokener style).
-- Arrays `[...]`, objects `{...}`, strings in "..." or '...' with escapes,
-- and bare words (read up to , : ] } [ { or a quote, then trimmed).
-- Separators `,` or `;`; object pairs `k: v`, `k = v` or `k => v`.
-- Bare words stay strings (so `[1, 2]` gives the keys "1" and "2").
------------------------------------------------------------------------------

type Reader = { s: string, i: number }

local function fail(r: Reader, msg: string): never
	error(string.format("extra-keys: %s at character %d", msg, r.i), 0)
end

local function skip_ws(r: Reader)
	while r.i <= #r.s do
		local c = string.sub(r.s, r.i, r.i)
		if c == " " or c == "\t" or c == "\n" or c == "\r" then
			r.i += 1
		else
			break
		end
	end
end

local function peek(r: Reader): string
	return string.sub(r.s, r.i, r.i)
end

local function read_quoted(r: Reader): string
	local q = peek(r)
	r.i += 1
	local out: { string } = {}
	while true do
		if r.i > #r.s then
			fail(r, "unterminated string")
		end
		local c = string.sub(r.s, r.i, r.i)
		r.i += 1
		if c == q then
			break
		elseif c == "\\" then
			local e = string.sub(r.s, r.i, r.i)
			r.i += 1
			if e == "n" then
				table.insert(out, "\n")
			elseif e == "t" then
				table.insert(out, "\t")
			elseif e == "r" then
				table.insert(out, "\r")
			elseif e == "b" then
				table.insert(out, "\b")
			elseif e == "f" then
				table.insert(out, "\f")
			elseif e == "u" then
				local hex = string.sub(r.s, r.i, r.i + 3)
				local n = tonumber(hex, 16)
				if #hex ~= 4 or not n then
					fail(r, "bad \\u escape")
				end
				r.i += 4
				table.insert(out, utf8.char(n :: number))
			elseif e == "" then
				fail(r, "unterminated string")
			else
				table.insert(out, e)
			end
		else
			table.insert(out, c)
		end
	end
	return table.concat(out)
end

local BARE_STOP = { [","] = true, [":"] = true, ["]"] = true, ["}"] = true, ["["] = true, ["{"] = true, [";"] = true, ['"'] = true, ["'"] = true, ["\n"] = true }

local function read_bare(r: Reader): string
	local start = r.i
	while r.i <= #r.s do
		local c = string.sub(r.s, r.i, r.i)
		if BARE_STOP[c] then
			break
		end
		-- `=` / `=>` separates an object key from its value.
		if c == "=" then
			break
		end
		r.i += 1
	end
	local word = string.gsub(string.sub(r.s, start, r.i - 1), "^%s+", "")
	word = string.gsub(word, "%s+$", "")
	if word == "" then
		fail(r, "missing value")
	end
	return word
end

local read_value: (r: Reader) -> any

local function read_array(r: Reader): { any }
	r.i += 1 -- [
	local out: { any } = {}
	skip_ws(r)
	if peek(r) == "]" then
		r.i += 1
		return out
	end
	while true do
		skip_ws(r)
		local c = peek(r)
		if c == "," or c == ";" then
			-- empty slot (org.json would put null): skip it
			r.i += 1
		elseif c == "]" then
			r.i += 1
			return out
		else
			table.insert(out, read_value(r))
			skip_ws(r)
			c = peek(r)
			if c == "," or c == ";" then
				r.i += 1
			elseif c == "]" then
				r.i += 1
				return out
			else
				fail(r, "expected , or ]")
			end
		end
	end
end

local function read_object(r: Reader): { [string]: any }
	r.i += 1 -- {
	local out: { [string]: any } = {}
	while true do
		skip_ws(r)
		local c = peek(r)
		if c == "}" then
			r.i += 1
			return out
		elseif c == "" then
			fail(r, "unterminated object")
		end
		local k: string
		if c == '"' or c == "'" then
			k = read_quoted(r)
		else
			k = read_bare(r)
		end
		skip_ws(r)
		c = peek(r)
		if c == ":" then
			r.i += 1
		elseif c == "=" then
			r.i += 1
			if peek(r) == ">" then
				r.i += 1
			end
		else
			fail(r, "expected : after key")
		end
		skip_ws(r)
		out[k] = read_value(r)
		skip_ws(r)
		c = peek(r)
		if c == "," or c == ";" then
			r.i += 1
		elseif c == "}" then
			r.i += 1
			return out
		else
			fail(r, "expected , or }")
		end
	end
end

read_value = function(r: Reader): any
	skip_ws(r)
	local c = peek(r)
	if c == "[" then
		return read_array(r)
	elseif c == "{" then
		return read_object(r)
	elseif c == '"' or c == "'" then
		return read_quoted(r)
	elseif c == "" then
		fail(r, "unexpected end")
	end
	return read_bare(r)
end

--- Reads the JSON-ish text; raises a readable message on bad syntax.
function M.read(text: string): any
	local r: Reader = { s = text, i = 1 }
	local v = read_value(r)
	skip_ws(r)
	if r.i <= #r.s then
		fail(r, "trailing characters")
	end
	return v
end

------------------------------------------------------------------------------
-- ExtraKeysInfo port
------------------------------------------------------------------------------

local function alias(k: string): string
	return M.ALIASES[k] or k
end

local function normalize(v: any): { [string]: any }
	if type(v) == "string" then
		return { key = v }
	elseif type(v) == "table" then
		return v
	end
	error("extra-keys: a key in the extra-key matrix must be a string or an object", 0)
end

local function button_of(obj: { [string]: any }, popup: Button?, dmap: { [string]: string }): Button
	local key = obj.key
	local macro = obj.macro
	if key ~= nil and type(key) ~= "string" then
		key = tostring(key)
	end
	if macro ~= nil and type(macro) ~= "string" then
		macro = tostring(macro)
	end
	local keys: { string } = {}
	local is_macro = false
	if key ~= nil and macro ~= nil then
		error(string.format('extra-keys: both key and macro can\'t be set for the same key. key: "%s", macro: "%s"', key, macro), 0)
	elseif key ~= nil then
		keys = { alias(key) }
	elseif macro ~= nil then
		is_macro = true
		-- Java's split(" ") drops trailing empties but keeps inner ones; empty
		-- tokens send nothing either way, so drop them.
		for part in string.gmatch(macro, "[^ ]+") do
			table.insert(keys, alias(part))
		end
	else
		error("extra-keys: all keys have to specify either key or macro", 0)
	end
	local display: string
	if type(obj.display) == "string" then
		display = obj.display
	elseif obj.display ~= nil then
		display = tostring(obj.display)
	else
		local parts: { string } = {}
		for _, k in keys do
			table.insert(parts, dmap[k] or k)
		end
		display = table.concat(parts, " ")
	end
	return { key = table.concat(keys, " "), macro = is_macro, display = display, popup = popup }
end

--- Builds the button matrix from an `extra-keys` value and an `extra-keys-style`.
function M.parse(text: string, style: string?): Config
	local st = style or M.DEFAULT_STYLE
	local dmap = M.display_map(st)
	local data = M.read(text)
	if type(data) ~= "table" then
		error("extra-keys: expected an array of rows", 0)
	end
	local rows: { { Button } } = {}
	for _, line in data :: { any } do
		if type(line) ~= "table" then
			error("extra-keys: each row must be an array", 0)
		end
		local row: { Button } = {}
		for _, item in line :: { any } do
			local obj = normalize(item)
			local popup: Button? = nil
			if obj.popup ~= nil then
				popup = button_of(normalize(obj.popup), nil, dmap)
			end
			table.insert(row, button_of(obj, popup, dmap))
		end
		table.insert(rows, row)
	end
	return { rows = rows, style = st }
end

------------------------------------------------------------------------------
-- termux.properties reader (java.util.Properties rules, enough for Termux)
------------------------------------------------------------------------------

local function unescape_props(s: string): string
	local out: { string } = {}
	local i = 1
	while i <= #s do
		local c = string.sub(s, i, i)
		if c == "\\" and i < #s then
			local e = string.sub(s, i + 1, i + 1)
			if e == "t" then
				table.insert(out, "\t")
			elseif e == "n" then
				table.insert(out, "\n")
			elseif e == "r" then
				table.insert(out, "\r")
			elseif e == "f" then
				table.insert(out, "\f")
			elseif e == "u" and tonumber(string.sub(s, i + 2, i + 5), 16) and #string.sub(s, i + 2, i + 5) == 4 then
				table.insert(out, utf8.char(tonumber(string.sub(s, i + 2, i + 5), 16) :: number))
				i += 4
			else
				table.insert(out, e)
			end
			i += 2
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

--- Parses a .properties file: `#`/`!` comments, `key=value`, `key: value` or
--- `key value`, and lines continued with a trailing backslash.
function M.parse_properties(text: string): { [string]: string }
	local props: { [string]: string } = {}
	local logical: { string } = {}
	local pending: string? = nil
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local line = string.gsub(raw, "\r$", "")
		if pending ~= nil then
			line = pending .. (string.gsub(line, "^[ \t\f]+", ""))
			pending = nil
		else
			line = string.gsub(line, "^[ \t\f]+", "")
			local first = string.sub(line, 1, 1)
			if first == "#" or first == "!" then
				line = ""
			end
		end
		-- odd number of trailing backslashes continues the line
		local trail = string.match(line, "(\\*)$") or ""
		if #trail % 2 == 1 then
			pending = string.sub(line, 1, #line - 1)
		elseif line ~= "" then
			table.insert(logical, line)
		end
	end
	if pending ~= nil and pending ~= "" then
		table.insert(logical, pending)
	end
	for _, line in logical do
		-- key ends at the first unescaped =, :, or whitespace
		local i = 1
		local key_end = #line
		local sep_found = false
		while i <= #line do
			local c = string.sub(line, i, i)
			if c == "\\" then
				i += 2
			elseif c == "=" or c == ":" or c == " " or c == "\t" or c == "\f" then
				key_end = i - 1
				sep_found = true
				break
			else
				i += 1
			end
		end
		local key = unescape_props(string.sub(line, 1, key_end))
		local rest = if sep_found then string.sub(line, key_end + 1) else ""
		rest = string.gsub(rest, "^[ \t\f]+", "")
		local s1 = string.sub(rest, 1, 1)
		if s1 == "=" or s1 == ":" then
			rest = string.gsub(string.sub(rest, 2), "^[ \t\f]+", "")
		end
		props[key] = unescape_props(rest)
	end
	return props
end

--- Config from properties text: uses `extra-keys` and `extra-keys-style`, with Termux's defaults.
function M.from_properties(text: string): Config
	local props = M.parse_properties(text)
	local value = props["extra-keys"]
	if value == nil or string.match(value, "^%s*$") then
		value = M.DEFAULT_EXTRA_KEYS
	end
	return M.parse(value :: string, props["extra-keys-style"])
end

function M.default(): Config
	return M.parse(M.DEFAULT_EXTRA_KEYS, M.DEFAULT_STYLE)
end

return M
