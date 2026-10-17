--!strict
-- Window half (optional). Gives touch clients ways to open the bar without
-- the command palette:
--   * a status-line segment "keys" whose click runs `plugin.extrakeys.open`;
--   * auto-open: on window_start, if the session has no Extra Keys bar yet,
--     one opens below the focused pane (disable with `auto-open = false` in
--     <plugin data>/extrakeys.properties, or the "toggle auto-open" command).
-- It also remembers the focused terminal pane for bars in "follow" mode.

local config = require("./lib/config")

local BLOCK_KIND = "extrakeys.bar"
local OPEN_ACTION = "plugin.extrakeys.open"
local SETTINGS_FILE = "extrakeys.properties"
local BAR_TITLE = "Extra Keys"

-- Whether `p` is an Extra Keys bar. The window's PaneInfo.block holds the
-- plugin block kind ("<plugin>.<block>"); the title is a fallback.
local function is_bar(p: PaneInfo): boolean
	local b = p.block
	if b ~= nil and (b == BLOCK_KIND or string.sub(b, -#BLOCK_KIND - 1) == "." .. BLOCK_KIND) then
		return true
	end
	return p.kind == "plugin" and string.sub(p.title or "", 1, #BAR_TITLE) == BAR_TITLE
end

local function has_bar(cx: WindowCx): boolean
	for _, p in cx.session:panes() do
		if is_bar(p) then
			return true
		end
	end
	return false
end

-- auto-open: the toggle command's choice (kv) wins, then the settings file,
-- then the default (on).
local function auto_open_enabled(): boolean
	local choice = tern.kv.get("auto_open")
	if type(choice) == "boolean" then
		return choice
	end
	local path = tern.plugin.data .. "/" .. SETTINGS_FILE
	local ok, text = pcall(function(): string?
		if tern.fs.exists(path) then
			return tern.fs.read(path, 64 * 1024)
		end
		return nil
	end)
	if ok and type(text) == "string" then
		local v = config.parse_properties(text)["auto-open"]
		if v ~= nil then
			local s = string.lower(v)
			return not (s == "false" or s == "no" or s == "off" or s == "0")
		end
	end
	return true
end

-- Opens a bar below the focused pane aimed at it; with no usable focus, a
-- bar in the default place that asks for a target. Keeps focus where it is.
local function open_bar(cx: WindowCx): number?
	local args: { string } = {}
	local how: How = "default"
	local f = cx.session:focused()
	if f then
		local p = cx.session:pane(f)
		if p and not is_bar(p) then
			if p.kind == "terminal" or p.kind == "agent" then
				table.insert(args, tostring(f))
			end
			how = "below"
		end
	end
	local pane = cx:new_block(BLOCK_KIND, args, how, { focus = false })
	if pane == nil then
		cx:toast("error", "Extra Keys isn't ready on this host", "Install the plugin on the machine that runs your shells.")
	end
	return pane
end

tern.on("focus", function(ev: FocusEvent, cx: WindowCx)
	local p = cx.session:pane(ev.pane)
	if p and (p.kind == "terminal" or p.kind == "agent") then
		tern.kv.set("focused_target", ev.pane)
	end
end)

tern.command({
	id = "open",
	title = "Extra Keys: open bar below this pane",
	icon = "keyboard",
	run = function(cx: WindowCx)
		open_bar(cx)
	end,
})

tern.command({
	id = "toggle-auto-open",
	title = "Extra Keys: toggle opening a bar when a window starts",
	icon = "keyboard",
	run = function(cx: WindowCx)
		local now = not auto_open_enabled()
		tern.kv.set("auto_open", now)
		cx:toast("info", "Extra Keys auto-open " .. (if now then "on" else "off"))
	end,
})

-- A tappable status-line segment: palette-free way to open a bar.
tern.chrome.status(function(_pane: StatusPaneInfo): { StatusSegment }?
	return { { text = "keys", icon = "keyboard", command = OPEN_ACTION } }
end)

tern.on("window_start", function(cx: WindowCx)
	if not auto_open_enabled() or has_bar(cx) then
		return
	end
	open_bar(cx)
end)
