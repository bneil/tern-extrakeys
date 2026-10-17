--!strict
-- Host half: the `extrakeys.bar` block. A grid of Termux-style extra keys;
-- each tap writes bytes into a target pane with `tern.pane.write`.
--
-- Launch args: `extrakeys.bar [PANE_ID]`. Without one the bar uses the last
-- target (kv `last_target`), the window half's focus (kv `focused_target`,
-- when "follow" is on), or asks you to pick a pane.

local config = require("./lib/config")
local keys = require("./lib/keys")

local ui = tern.ui

local MOD_NAMES = { "CTRL", "ALT", "SHIFT", "FN" }
local BAR_TITLE = "Extra Keys"
local MAX_CONFIG_BYTES = 64 * 1024

type ModState = { active: boolean, locked: boolean }

type State = {
	cx: BlockCx,
	cfg: config.Config,
	source: string,
	err: string?,
	target: number?,
	follow: boolean,
	mods: { [string]: ModState },
	lock_armed: boolean,
	layer: boolean,
	layer_locked: boolean,
	picking: boolean,
	app_cursor: boolean,
	note: string?,
}

-- Props on a builder's node, under --!strict (see "Props under --!strict").
local function with(node: Node, props: { [string]: any }): Node
	local p: { [string]: any } = node.p or {}
	for k, v in props do
		p[k] = v
	end
	node.p = p
	return node
end

------------------------------------------------------------------------------
-- Configuration
------------------------------------------------------------------------------

local function read_file(path: string): string?
	local ok_exists, exists = pcall(tern.fs.exists, path)
	if not ok_exists or not exists then
		return nil
	end
	local ok, text = pcall(tern.fs.read, path, MAX_CONFIG_BYTES)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

-- Where the layout comes from, first found wins.
local function config_candidates(): { { path: string, kind: string } }
	local out: { { path: string, kind: string } } = {
		{ path = tern.plugin.data .. "/termux.properties", kind = "properties" },
		{ path = tern.plugin.data .. "/extra-keys.json", kind = "value" },
	}
	local home = tern.getenv("HOME")
	if home and home ~= "" then
		table.insert(out, { path = home .. "/.termux/termux.properties", kind = "properties" })
	end
	return out
end

local function load_config(): (config.Config, string, string?)
	for _, c in config_candidates() do
		local text = read_file(c.path)
		if text then
			local ok, res = pcall(function(): config.Config
				if c.kind == "properties" then
					return config.from_properties(text)
				end
				return config.parse(text, nil)
			end)
			if ok then
				return res, c.path, nil
			end
			return config.default(), "built-in default", c.path .. ": " .. tostring(res)
		end
	end
	return config.default(), "built-in default", nil
end

------------------------------------------------------------------------------
-- Target pane
------------------------------------------------------------------------------

local function other_panes(state: State): { PaneInfo }
	local out: { PaneInfo } = {}
	for _, p in tern.pane.list() do
		if p.pane ~= state.cx.pane and string.sub(p.title or "", 1, #BAR_TITLE) ~= BAR_TITLE then
			table.insert(out, p)
		end
	end
	return out
end

local function pane_exists(state: State, id: number?): boolean
	if id == nil or id == state.cx.pane then
		return false
	end
	for _, p in tern.pane.list() do
		if p.pane == id then
			return true
		end
	end
	return false
end

local function pane_label(p: PaneInfo): string
	local label = if p.title ~= "" then p.title else (p.program or "pane")
	return string.format("#%d %s", p.pane, label)
end

local function label_of(state: State, id: number?): string
	if id == nil then
		return "no target"
	end
	for _, p in tern.pane.list() do
		if p.pane == id then
			return pane_label(p)
		end
	end
	return string.format("#%d (gone)", id)
end

-- The pane keys go to now, or nil (and the picker opens).
local function resolve_target(state: State): number?
	if state.follow then
		local f = tern.kv.get("focused_target")
		if type(f) == "number" and pane_exists(state, f) then
			return f
		end
	end
	if pane_exists(state, state.target) then
		return state.target
	end
	return nil
end

local function set_target(state: State, id: number)
	state.target = id
	state.picking = false
	tern.kv.set("last_target", id)
	state.note = "Target: " .. label_of(state, id)
end

------------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------------

local function sticky(state: State): keys.Mods
	return {
		ctrl = state.mods.CTRL.active,
		alt = state.mods.ALT.active,
		shift = state.mods.SHIFT.active,
		fn = state.mods.FN.active,
	}
end

-- One-shot modifiers are used up by the next key; locked ones stay
-- (ExtraKeysView.readSpecialButton(btn, autoSetInActive = true)).
local function consume_mods(state: State)
	for _, name in MOD_NAMES do
		local m = state.mods[name]
		if not m.locked then
			m.active = false
		end
	end
end

local function write(state: State, bytes: string): boolean
	if bytes == "" then
		return false
	end
	local target = resolve_target(state)
	if target == nil then
		state.picking = true
		state.note = "Pick a pane for the keys first."
		return false
	end
	tern.pane.write(target, bytes)
	return true
end

local function press_modifier(state: State, name: string, double: boolean)
	local m = state.mods[name]
	if m == nil then
		return
	end
	if double or state.lock_armed then
		m.active = true
		m.locked = true
		state.lock_armed = false
		state.note = name .. " locked (tap it to release)"
		return
	end
	-- ExtraKeysView.onAnyExtraKeyButtonClick: toggle; inactive clears the lock.
	m.active = not m.active
	if not m.active then
		m.locked = false
	end
	state.note = nil
end

local function press(state: State, b: config.Button)
	if not b.macro and keys.MODIFIERS[b.key] then
		press_modifier(state, b.key, false)
		return
	end
	if not b.macro and keys.APP_KEYS[b.key] then
		state.note = b.key .. " is a Termux app key; Tern has no equivalent."
		return
	end
	local bytes: string
	if b.macro then
		local skipped: { string }
		bytes, skipped = keys.macro(b.key, state.app_cursor)
		if #skipped > 0 then
			state.note = "Skipped Termux app keys: " .. table.concat(skipped, ", ")
		end
	else
		bytes = keys.encode(b.key, sticky(state), state.app_cursor) or ""
	end
	if write(state, bytes) then
		if not b.macro then
			consume_mods(state)
		end
		if state.layer and not state.layer_locked then
			state.layer = false
		end
		if not state.picking then
			state.note = nil
		end
	end
end

local function button_at(state: State, value: string?): config.Button?
	if value == nil then
		return nil
	end
	local r, c = string.match(value, "^(%d+):(%d+)$")
	if not r or not c then
		return nil
	end
	local row = state.cfg.rows[tonumber(r) :: number]
	if row == nil then
		return nil
	end
	local b = row[tonumber(c) :: number]
	if b == nil then
		return nil
	end
	if state.layer and b.popup then
		return b.popup
	end
	return b
end

------------------------------------------------------------------------------
-- View
------------------------------------------------------------------------------

local function key_button(state: State, r: number, c: number, base: config.Button): Node
	local b = if state.layer and base.popup then base.popup else base
	local classes = { "ek-key" }
	local actions: { [string]: string } = { click = string.format("k=%d:%d", r, c) }
	if not b.macro and keys.MODIFIERS[b.key] then
		table.insert(classes, "ek-mod")
		local m = state.mods[b.key]
		if m and m.active then
			table.insert(classes, "on")
		end
		if m and m.locked then
			table.insert(classes, "locked")
		end
		actions.dblclick = string.format("kd=%d:%d", r, c)
	end
	if state.layer and base.popup then
		table.insert(classes, "ek-popup")
	elseif base.popup then
		table.insert(classes, "has-popup")
	end
	local attrs: { [string]: any } = {}
	if base.popup and not state.layer then
		attrs["data-popup"] = base.popup.display
	end
	local title = if base.popup and not state.layer then b.display .. " (⇅: " .. base.popup.display .. ")" else b.display
	return ui.el("button", {
		key = string.format("k%d_%d", r, c),
		class = table.concat(classes, " "),
		text = b.display,
		title = title,
		attrs = attrs,
		actions = actions,
	})
end

local function ctl_button(id: string, text: string, title: string, on: boolean, dbl: string?): Node
	local actions: { [string]: string } = { click = "ui=" .. id }
	if dbl then
		actions.dblclick = "ui=" .. dbl
	end
	return ui.el("button", {
		key = "c_" .. id,
		class = "ek-ctl-btn" .. (if on then " on" else ""),
		text = text,
		title = title,
		actions = actions,
	})
end

local function picker(state: State): Node
	local items: { Node } = {}
	for _, p in other_panes(state) do
		local cls = "ek-pick-item" .. (if p.pane == state.target then " on" else "")
		local detail = p.cwd or ""
		table.insert(
			items,
			ui.el("button", {
				key = "p" .. p.pane,
				class = cls,
				text = pane_label(p) .. (if detail ~= "" then "  " .. detail else ""),
				actions = { click = "t=" .. p.pane },
			})
		)
	end
	if #items == 0 then
		table.insert(items, ui.text(ui.span("No other panes on this host. Open a shell, then tap ⟳.", "muted")))
	end
	table.insert(items, ctl_button("pick", "Cancel", "Close the pane picker", false, nil))
	return ui.el("div", { key = "picker", class = "ek-picker" }, items)
end

local function view(state: State, _cx: BlockCx): BlockView
	local target = resolve_target(state)
	local target_text = "→ " .. (if target then label_of(state, target) else "pick a pane")
	local controls = ui.el("div", { key = "ctl", class = "ek-ctl" }, {
		ctl_button("pick", target_text, "Choose the pane the keys type into", state.picking, nil),
		ctl_button("layer", "⇅", "Show the popup (swipe-up) keys; double-tap to keep them", state.layer, "layerlock"),
		ctl_button("lock", "🔒", "Arm: the next modifier you tap locks on", state.lock_armed, nil),
		ctl_button("app", "APP", "Application cursor keys (arrows send ESC O A…)", state.app_cursor, nil),
		ctl_button("follow", "follow", "Type into the focused pane (needs the window half on this machine)", state.follow, nil),
		ctl_button("reload", "⟳", "Reload the extra-keys config", false, nil),
	})

	local children: { Node } = { controls }
	if state.picking then
		table.insert(children, picker(state))
	end
	local grid: { Node } = {}
	for r, row in state.cfg.rows do
		local buttons: { Node } = {}
		for c, b in row do
			table.insert(buttons, key_button(state, r, c, b))
		end
		table.insert(grid, ui.el("div", { key = "r" .. r, class = "ek-row" }, buttons))
	end
	table.insert(children, ui.el("div", { key = "grid", class = "ek-grid" .. (if state.layer then " layer" else "") }, grid))
	local note = state.note or (if state.err then "Config error, using the default: " .. state.err else nil)
	if note then
		table.insert(children, with(ui.text(ui.span(note, "muted")), { key = "note", role = "extrakeys.note" }))
	end
	return { main = with(ui.col(children), { role = "extrakeys.bar" }) }
end

------------------------------------------------------------------------------
-- Block
------------------------------------------------------------------------------

local function fresh_mods(): { [string]: ModState }
	local out: { [string]: ModState } = {}
	for _, name in MOD_NAMES do
		out[name] = { active = false, locked = false }
	end
	return out
end

local function init(cx: BlockCx, args: { string }, saved: any): State
	local cfg, source, err = load_config()
	local state: State = {
		cx = cx,
		cfg = cfg,
		source = source,
		err = err,
		target = nil,
		follow = false,
		mods = fresh_mods(),
		lock_armed = false,
		layer = false,
		layer_locked = false,
		picking = false,
		app_cursor = false,
		note = nil,
	}
	if type(saved) == "table" then
		if type(saved.target) == "number" then
			state.target = saved.target
		end
		state.follow = saved.follow == true
		state.app_cursor = saved.app_cursor == true
		if type(saved.locked) == "table" then
			for _, name in MOD_NAMES do
				if saved.locked[name] == true then
					state.mods[name] = { active = true, locked = true }
				end
			end
		end
	end
	for _, a in args do
		local n = tonumber(a)
		if a == "follow" then
			state.follow = true
		elseif n then
			state.target = n
		end
	end
	if not pane_exists(state, state.target) then
		local last = tern.kv.get("last_target")
		if type(last) == "number" and pane_exists(state, last) then
			state.target = last
		else
			local others = other_panes(state)
			state.target = if #others == 1 then others[1].pane else nil
		end
	end
	if resolve_target(state) == nil then
		state.picking = true
	end
	return state
end

local function event(state: State, ev: UiEvent, cx: BlockCx)
	if ev.ev ~= "action" then
		return
	end
	local act, value = ev.act, ev.value
	if act == "k" then
		local b = button_at(state, value)
		if b then
			press(state, b)
		end
	elseif act == "kd" then
		local b = button_at(state, value)
		if b and not b.macro and keys.MODIFIERS[b.key] then
			press_modifier(state, b.key, true)
		end
	elseif act == "t" then
		local n = tonumber(value)
		if n and pane_exists(state, n) then
			set_target(state, n)
		end
	elseif act == "ui" then
		if value == "pick" then
			state.picking = not state.picking
			state.note = nil
		elseif value == "layer" then
			state.layer = not state.layer
			state.layer_locked = false
		elseif value == "layerlock" then
			state.layer = true
			state.layer_locked = true
		elseif value == "lock" then
			state.lock_armed = not state.lock_armed
		elseif value == "app" then
			state.app_cursor = not state.app_cursor
		elseif value == "follow" then
			state.follow = not state.follow
			state.note = if state.follow
				then "Following the focused pane (works only where the window half runs on this host)."
				else nil
		elseif value == "reload" then
			state.cfg, state.source, state.err = load_config()
			state.note = "Loaded " .. state.source
			if state.err then
				cx:toast("error", "Extra Keys: bad config", state.err)
			end
		end
	end
end

-- Keys typed while the bar itself has focus are forwarded to the target,
-- with the sticky modifiers merged in.
local function key(state: State, k: Key, _cx: BlockCx): boolean?
	if k.name == "paste" then
		return write(state, k.text or "") or state.picking
	end
	local s = sticky(state)
	local m: keys.Mods = { ctrl = s.ctrl or k.ctrl, alt = s.alt or k.alt, shift = s.shift or k.shift, fn = s.fn }
	local token = keys.from_tern_name(k.name)
	local bytes: string? = nil
	if token then
		bytes = keys.named(token, m, state.app_cursor)
	elseif k.text and k.text ~= "" then
		-- the typed text already carries Shift; don't apply it twice
		bytes = keys.text(k.text, { ctrl = m.ctrl, alt = m.alt, shift = s.shift, fn = m.fn })
	elseif utf8.len(k.name) == 1 then
		bytes = keys.text(k.name, m)
	end
	if bytes == nil or bytes == "" then
		return false
	end
	if write(state, bytes) then
		consume_mods(state)
	end
	return true
end

local function title(state: State): string?
	return BAR_TITLE .. " → " .. label_of(state, resolve_target(state))
end

local function save(state: State): any
	local locked: { [string]: boolean } = {}
	for _, name in MOD_NAMES do
		if state.mods[name].locked then
			locked[name] = true
		end
	end
	return { target = state.target, follow = state.follow, app_cursor = state.app_cursor, locked = locked }
end

local def: BlockDef<State> = {
	init = init,
	view = view,
	title = title,
	key = key,
	event = event,
	save = save,
}

tern.block.define("bar", def)
