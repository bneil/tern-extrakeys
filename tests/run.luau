-- Unit tests for the config parser and key encoder, plus a simulated run of
-- the host and window entries against a mock `tern` table.
-- Run: python3 tests/embed.py && luau tests/run.luau

local config = require("../lib/config")
local keys = require("../lib/keys")
local sources = require("./_sources")

local passed, failed = 0, 0

local function show(v: any): string
	if type(v) == "string" then
		return (string.gsub(string.format("%q", v), "\27", "\\27"))
	end
	return tostring(v)
end

local function eq(name: string, got: any, want: any)
	if got == want then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": got " .. show(got) .. ", want " .. show(want))
	end
end

local function raises(name: string, fn: () -> (), pattern: string?)
	local ok, err = pcall(fn)
	if not ok and (pattern == nil or string.find(tostring(err), pattern, 1, true)) then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": expected error" .. (if pattern then " containing " .. pattern else "") .. ", got " .. tostring(err))
	end
end

local M0 = keys.no_mods()
local function mods(s: string): keys.Mods
	return {
		ctrl = string.find(s, "c", 1, true) ~= nil,
		alt = string.find(s, "a", 1, true) ~= nil,
		shift = string.find(s, "s", 1, true) ~= nil,
		fn = false,
	}
end

------------------------------------------------------------------ reader
do
	local v = config.read("[[ESC, TAB, CTRL, ALT, {key: '-', popup: '|'}, DOWN, UP]]")
	eq("bare words row length", #v[1], 7)
	eq("bare ESC", v[1][1], "ESC")
	eq("object key", v[1][5].key, "-")
	eq("object popup", v[1][5].popup, "|")
	local w = config.read('[["a b", \'c\\\'d\', "\\u2190", {macro: CTRL f d, display => "tmux"}]]')
	eq("double quoted with space", w[1][1], "a b")
	eq("escaped single quote", w[1][2], "c'd")
	eq("unicode escape", w[1][3], "←")
	eq("bare macro with spaces", w[1][4].macro, "CTRL f d")
	eq("=> separator", w[1][4].display, "tmux")
	local n = config.read("[[1, 2;3], ]")
	eq("numbers stay strings", n[1][1], "1")
	eq("semicolon separator", n[1][3], "3")
	eq("trailing comma ignored", #n, 1)
	raises("unterminated string", function()
		config.read("[['ESC]]")
	end, "unterminated string")
	raises("missing bracket", function()
		config.read("[[ESC, TAB")
	end)
	raises("trailing garbage", function()
		config.read("[[ESC]] x")
	end, "trailing")
end

------------------------------------------------------------------ parse (ExtraKeysInfo)
do
	local d = config.default()
	eq("default rows", #d.rows, 2)
	eq("default row1 len", #d.rows[1], 7)
	eq("default row2 len", #d.rows[2], 7)
	eq("default r1c1", d.rows[1][1].key, "ESC")
	eq("default ESC display (default style keeps ESC)", d.rows[1][1].display, "ESC")
	eq("default dash display", d.rows[1][3].display, "―")
	eq("default dash popup", d.rows[1][3].popup and d.rows[1][3].popup.key, "|")
	eq("default UP display", d.rows[1][5].display, "↑")
	eq("default TAB display", d.rows[2][1].display, "↹")
	eq("default PGUP display (not in default map)", d.rows[1][7].display, "PGUP")

	local c = config.parse("[[ESCAPE, 'PAGE UP', PAGE_DOWN, BACKSLASH, {macro: 'CONTROL f BACKSPACE', display: 'tmux ←'}]]", "all")
	eq("alias ESCAPE", c.rows[1][1].key, "ESC")
	eq("alias PAGE UP", c.rows[1][2].key, "PGUP")
	eq("alias PAGE_DOWN", c.rows[1][3].key, "PGDN")
	eq("alias BACKSLASH", c.rows[1][4].key, "\\")
	eq("macro aliases", c.rows[1][5].key, "CTRL f BKSP")
	eq("macro flag", c.rows[1][5].macro, true)
	eq("explicit display", c.rows[1][5].display, "tmux ←")
	eq("style all ESC", c.rows[1][1].display, "⎋")
	eq("style all PGUP", c.rows[1][2].display, "⇑")

	local lc = config.parse("[[escape]]", "all")
	eq("aliases are case-sensitive like Termux", lc.rows[1][1].key, "escape")
	local m = config.parse("[[{macro: 'CTRL d'}]]", "default")
	eq("macro default display joins", m.rows[1][1].display, "CTRL d")
	local none = config.parse("[[UP]]", "none")
	eq("style none", none.rows[1][1].display, "UP")
	local unknown = config.parse("[[UP]]", "nonsense")
	eq("unknown style -> default", unknown.rows[1][1].display, "↑")

	raises("key and macro", function()
		config.parse("[[{key: a, macro: b}]]")
	end, "both key and macro")
	raises("neither", function()
		config.parse("[[{display: x}]]")
	end, "either key or macro")
	raises("not rows", function()
		config.parse("[ESC]")
	end, "each row must be an array")
end

------------------------------------------------------------------ properties
do
	local text = table.concat({
		"# comment",
		"! also comment",
		"bell-character = ignore",
		"extra-keys = [['ESC','|','/','HOME','UP','END','PGUP','DEL'], \\",
		"              ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN','BKSP']]",
		"extra-keys-style : arrows-all",
	}, "\n")
	local p = config.parse_properties(text)
	eq("prop simple", p["bell-character"], "ignore")
	eq("prop colon sep", p["extra-keys-style"], "arrows-all")
	local c = config.from_properties(text)
	eq("prop continuation rows", #c.rows, 2)
	eq("prop row2 len", #c.rows[2], 8)
	eq("prop style applied", c.rows[1][4].display, "⇱")
	eq("prop BKSP", c.rows[2][8].key, "BKSP")
	local esc = config.parse_properties("extra-keys = [['\\\\']]")
	eq("prop backslash unescape", esc["extra-keys"], "[['\\']]")
	local def = config.from_properties("fullscreen=true\n")
	eq("no extra-keys -> default", #def.rows, 2)
	eq("CRLF ok", config.parse_properties("a=b\r\nc=d\r\n").c, "d")
end

------------------------------------------------------------------ key encoding
do
	eq("ESC", keys.encode("ESC", M0), "\27")
	eq("TAB", keys.encode("TAB", M0), "\t")
	eq("shift TAB", keys.encode("TAB", mods("s")), "\27[Z")
	eq("ENTER", keys.encode("ENTER", M0), "\r")
	eq("BKSP", keys.encode("BKSP", M0), "\127")
	eq("ctrl BKSP", keys.encode("BKSP", mods("c")), "\8")
	eq("SPACE", keys.encode("SPACE", M0), " ")
	eq("ctrl SPACE", keys.encode("SPACE", mods("c")), "\0")
	eq("UP", keys.encode("UP", M0), "\27[A")
	eq("DOWN", keys.encode("DOWN", M0), "\27[B")
	eq("RIGHT", keys.encode("RIGHT", M0), "\27[C")
	eq("LEFT", keys.encode("LEFT", M0), "\27[D")
	eq("app UP", keys.encode("UP", M0, true), "\27OA")
	eq("app HOME", keys.encode("HOME", M0, true), "\27OH")
	eq("ctrl LEFT", keys.encode("LEFT", mods("c")), "\27[1;5D")
	eq("shift UP", keys.encode("UP", mods("s")), "\27[1;2A")
	eq("alt RIGHT", keys.encode("RIGHT", mods("a")), "\27[1;3C")
	eq("ctrl+alt+shift DOWN", keys.encode("DOWN", mods("cas")), "\27[1;8B")
	eq("mods ignore app cursor", keys.encode("UP", mods("c"), true), "\27[1;5A")
	eq("HOME", keys.encode("HOME", M0), "\27[H")
	eq("END", keys.encode("END", M0), "\27[F")
	eq("shift END", keys.encode("END", mods("s")), "\27[1;2F")
	eq("INS", keys.encode("INS", M0), "\27[2~")
	eq("DEL", keys.encode("DEL", M0), "\27[3~")
	eq("PGUP", keys.encode("PGUP", M0), "\27[5~")
	eq("PGDN", keys.encode("PGDN", M0), "\27[6~")
	eq("ctrl PGUP", keys.encode("PGUP", mods("c")), "\27[5;5~")
	eq("F1", keys.encode("F1", M0), "\27OP")
	eq("F4", keys.encode("F4", M0), "\27OS")
	eq("shift F1", keys.encode("F1", mods("s")), "\27[1;2P")
	eq("F5", keys.encode("F5", M0), "\27[15~")
	eq("F6", keys.encode("F6", M0), "\27[17~")
	eq("F12", keys.encode("F12", M0), "\27[24~")
	eq("ctrl F12", keys.encode("F12", mods("c")), "\27[24;5~")
	eq("alt ESC", keys.encode("ESC", mods("a")), "\27\27")
	eq("text", keys.encode("-", M0), "-")
	eq("text |", keys.encode("|", M0), "|")
	eq("ctrl c", keys.encode("c", mods("c")), "\3")
	eq("ctrl C", keys.encode("C", mods("c")), "\3")
	eq("ctrl [", keys.encode("[", mods("c")), "\27")
	eq("ctrl \\", keys.encode("\\", mods("c")), "\28")
	eq("ctrl /", keys.encode("/", mods("c")), "\31")
	eq("ctrl 2", keys.encode("2", mods("c")), "\0")
	eq("ctrl 8", keys.encode("8", mods("c")), "\127")
	eq("ctrl unmappable passes", keys.encode("-", mods("c")), "-")
	eq("alt x", keys.encode("x", mods("a")), "\27x")
	eq("ctrl alt x", keys.encode("x", mods("ca")), "\27\24")
	eq("shift letter", keys.encode("a", mods("s")), "A")
	eq("unicode text", keys.encode("é", M0), "é")
	eq("modifier sends nothing", keys.encode("CTRL", M0), nil)
	eq("app key sends nothing", keys.encode("KEYBOARD", M0), nil)

	local b, skipped = keys.macro("CTRL f d")
	eq("macro ctrl resets", b, "\6d")
	eq("macro no skipped", #skipped, 0)
	b = keys.macro("CTRL f BKSP")
	eq("macro tmux ←", b, "\6\127")
	b = keys.macro("ALT a")
	eq("macro alt", b, "\27a")
	b = keys.macro("CTRL ALT LEFT ESC")
	eq("macro named with mods", b, "\27[1;7D\27")
	b, skipped = keys.macro("KEYBOARD CTRL d")
	eq("macro skips app keys", b, "\4")
	eq("macro reports app keys", skipped[1], "KEYBOARD")
	b = keys.macro("echo SPACE hi ENTER")
	eq("macro words", b, "echo hi\r")

	eq("tern name up", keys.from_tern_name("up"), "UP")
	eq("tern name page_up", keys.from_tern_name("page_up"), "PGUP")
	eq("tern name escape", keys.from_tern_name("escape"), "ESC")
	eq("tern name f5", keys.from_tern_name("f5"), "F5")
	eq("tern name f13 none", keys.from_tern_name("f13"), nil)
	eq("tern name a none", keys.from_tern_name("a"), nil)
end

------------------------------------------------------------------ host block simulation
local function deep_find(node: any, pred: (any) -> boolean, out: { any }?): { any }
	local acc = out or {}
	if type(node) == "table" then
		if pred(node) then
			table.insert(acc, node)
		end
		for _, v in node do
			if type(v) == "table" then
				deep_find(v, pred, acc)
			end
		end
	end
	return acc
end

local function make_env(panes: { any }, files: { [string]: string }?)
	local writes: { { pane: number, text: string } } = {}
	local kv: { [string]: any } = {}
	local blocks: { [string]: any } = {}
	local toasts: { string } = {}
	local fs = files or {}
	local function node(kind: string, props: any?, children: any?): any
		return { k = kind, p = props, c = children }
	end
	local tern = {
		plugin = { id = "extrakeys", name = "Extra Keys", dir = "/plug", data = "/data" },
		runtime = { os = "linux", jit = false },
		getenv = function(n: string): string?
			return if n == "HOME" then "/home/u" else nil
		end,
		fs = {
			exists = function(p: string): boolean
				return fs[p] ~= nil
			end,
			read = function(p: string, _max: number?): string
				local t = fs[p]
				if t == nil then
					error("no such file " .. p)
				end
				return t
			end,
		},
		kv = {
			get = function(k: string): any
				return kv[k]
			end,
			set = function(k: string, v: any)
				kv[k] = v
			end,
		},
		pane = {
			list = function()
				return panes
			end,
			write = function(p: number, t: string)
				table.insert(writes, { pane = p, text = t })
			end,
		},
		block = {
			define = function(id: string, def: any)
				blocks[id] = def
			end,
		},
		ui = {
			span = function(t: string, s: string?)
				return { t = t, s = s }
			end,
			text = function(sp: any)
				return node("text", { spans = sp })
			end,
			col = function(c: any)
				return node("col", nil, c)
			end,
			row = function(c: any)
				return node("row", nil, c)
			end,
			el = function(tag: string, props: any?, children: any?)
				local p = table.clone(props or {})
				p.tag = tag
				return node("el", p, children)
			end,
		},
	}
	local function req(path: string): any
		if path == "./lib/config" then
			return config
		elseif path == "./lib/keys" then
			return keys
		end
		error("unexpected require " .. path)
	end
	local env = setmetatable({ tern = tern, require = req }, { __index = _G })
	return {
		tern = tern,
		env = env,
		writes = writes,
		kv = kv,
		blocks = blocks,
		toasts = toasts,
		load = function(name: string)
			local f, err = loadstring(sources[name], "=" .. name)
			assert(f, err)
			setfenv(f, env)
			f()
		end,
	}
end

local function mock_cx(pane: number, toasts: { string })
	return {
		pane = pane,
		cols = 80,
		rows = 6,
		toast = function(_self: any, level: string, text: string, sub: string?)
			table.insert(toasts, level .. ": " .. text .. " " .. (sub or ""))
		end,
		render = function() end,
		save = function() end,
	}
end

local function click(def: any, state: any, cx: any, action: string)
	local act, value = string.match(action, "^([^=]+)=?(.*)$")
	def.event(state, { ev = "action", act = act, value = if value ~= "" then value else nil }, cx)
end

local function find_button(view: any, text: string): any?
	local found = deep_find(view, function(n)
		return n.k == "el" and n.p and n.p.text == text
	end)
	return found[1]
end

do
	local panes = { { pane = 1, title = "zsh", program = "zsh", cwd = "/home/u" }, { pane = 9, title = "Extra Keys", program = "" } }
	local h = make_env(panes)
	h.load("host.luau")
	local def = h.blocks.bar
	eq("block defined", def ~= nil, true)
	local cx = mock_cx(9, h.toasts)
	local st = def.init(cx, {}, nil)
	eq("auto target single other pane", st.target, 1)
	eq("not picking", st.picking, false)
	local v = def.view(st, cx)
	eq("view has main", v.main ~= nil, true)
	eq("title", def.title(st), "Extra Keys → #1 zsh")
	local esc = find_button(v, "ESC")
	eq("ESC button present", esc ~= nil, true)
	eq("ESC action", esc and esc.p.actions.click, "k=1:1")

	click(def, st, cx, "k=1:1")
	eq("ESC wrote", h.writes[1] and h.writes[1].text, "\27")
	eq("ESC to pane 1", h.writes[1] and h.writes[1].pane, 1)

	-- CTRL one-shot then "-" (no ctrl byte) then UP with ctrl
	click(def, st, cx, "k=2:2") -- CTRL
	eq("CTRL active", st.mods.CTRL.active, true)
	local ctrlbtn = find_button(def.view(st, cx), "CTRL")
	eq("CTRL shows on", ctrlbtn and string.find(ctrlbtn.p.class, "on", 1, true) ~= nil, true)
	eq("CTRL has dblclick", ctrlbtn and ctrlbtn.p.actions.dblclick, "kd=2:2")
	click(def, st, cx, "k=1:5") -- UP
	eq("ctrl UP", h.writes[2].text, "\27[1;5A")
	eq("CTRL consumed", st.mods.CTRL.active, false)
	click(def, st, cx, "k=1:5")
	eq("UP after consume", h.writes[3].text, "\27[A")

	-- double tap locks: click, click, dblclick
	click(def, st, cx, "k=2:3")
	click(def, st, cx, "k=2:3")
	click(def, st, cx, "kd=2:3")
	eq("ALT locked", st.mods.ALT.locked, true)
	click(def, st, cx, "k=1:2") -- "/"
	click(def, st, cx, "k=1:2")
	eq("alt / twice (locked)", h.writes[4].text .. h.writes[5].text, "\27/\27/")
	click(def, st, cx, "k=2:3") -- tap releases
	eq("ALT released", st.mods.ALT.active or st.mods.ALT.locked, false)

	-- lock key arms the next modifier
	click(def, st, cx, "ui=lock")
	eq("lock armed", st.lock_armed, true)
	click(def, st, cx, "k=2:2")
	eq("CTRL locked via lock key", st.mods.CTRL.locked, true)
	eq("lock disarmed", st.lock_armed, false)
	click(def, st, cx, "k=2:2")
	eq("CTRL unlocked by tap", st.mods.CTRL.active, false)

	-- popup layer: "-" becomes "|", one-shot
	click(def, st, cx, "ui=layer")
	local lv = def.view(st, cx)
	eq("layer shows popup label", find_button(lv, "|") ~= nil, true)
	click(def, st, cx, "k=1:3")
	eq("popup sends |", h.writes[#h.writes].text, "|")
	eq("layer one-shot", st.layer, false)
	click(def, st, cx, "k=1:3")
	eq("base sends -", h.writes[#h.writes].text, "-")
	click(def, st, cx, "ui=layerlock")
	click(def, st, cx, "k=1:3")
	click(def, st, cx, "k=1:3")
	eq("locked layer stays", st.layer, true)
	eq("locked layer sends | twice", h.writes[#h.writes].text, "|")
	click(def, st, cx, "ui=layer")

	-- app cursor
	click(def, st, cx, "ui=app")
	click(def, st, cx, "k=2:4") -- LEFT
	eq("app LEFT", h.writes[#h.writes].text, "\27OD")

	-- keys typed into the bar are forwarded
	click(def, st, cx, "k=2:2") -- CTRL one-shot
	local r = def.key(st, { name = "c", text = "c", ctrl = false, alt = false, shift = false, meta = false }, cx)
	eq("typed c with sticky ctrl", h.writes[#h.writes].text, "\3")
	eq("key returns true", r, true)
	def.key(st, { name = "page_down", ctrl = false, alt = false, shift = false, meta = false }, cx)
	eq("typed page_down", h.writes[#h.writes].text, "\27[6~")
	def.key(st, { name = "A", text = "A", ctrl = false, alt = false, shift = true, meta = false }, cx)
	eq("typed shifted text not doubled", h.writes[#h.writes].text, "A")
	def.key(st, { name = "paste", text = "ls -la\n", ctrl = false, alt = false, shift = false, meta = false }, cx)
	eq("paste forwarded raw", h.writes[#h.writes].text, "ls -la\n")
	local n0 = #h.writes
	eq("unknown key returns false", def.key(st, { name = "media_play", ctrl = false, alt = false, shift = false, meta = false }, cx), false)
	eq("unknown key writes nothing", #h.writes, n0)

	-- save / restore
	click(def, st, cx, "kd=2:2")
	local saved = def.save(st)
	eq("save target", saved.target, 1)
	eq("save app_cursor", saved.app_cursor, true)
	eq("save locked CTRL", saved.locked.CTRL, true)
	local st2 = def.init(cx, {}, saved)
	eq("restore locked", st2.mods.CTRL.locked and st2.mods.CTRL.active, true)
	eq("restore app", st2.app_cursor, true)
end

do -- target picking, gone target, args, follow
	local panes = {
		{ pane = 1, title = "zsh", program = "zsh" },
		{ pane = 2, title = "", program = "bash", cwd = "/srv" },
		{ pane = 5, title = "Extra Keys → #1 zsh", program = "" },
		{ pane = 9, title = "Extra Keys", program = "" },
	}
	local h = make_env(panes)
	h.load("host.luau")
	local def = h.blocks.bar
	local cx = mock_cx(9, h.toasts)
	local st = def.init(cx, {}, nil)
	eq("ambiguous -> picking", st.picking, true)
	eq("ambiguous -> no target", st.target, nil)
	local v = def.view(st, cx)
	local items = deep_find(v, function(n)
		return n.k == "el" and n.p and type(n.p.actions) == "table" and type(n.p.actions.click) == "string" and string.sub(n.p.actions.click, 1, 2) == "t="
	end)
	eq("picker lists 2 panes (excludes bars)", #items, 2)
	click(def, st, cx, "k=1:1")
	eq("tap without target writes nothing", #h.writes, 0)
	click(def, st, cx, "t=2")
	eq("picked", st.target, 2)
	eq("kv last_target", h.kv.last_target, 2)
	click(def, st, cx, "k=1:1")
	eq("writes to picked", h.writes[1].pane, 2)

	local st3 = def.init(cx, { "1" }, nil)
	eq("arg target", st3.target, 1)
	local st4 = def.init(cx, {}, nil)
	eq("last_target reused", st4.target, 2)

	st3.follow = true
	h.kv.focused_target = 2
	click(def, st3, cx, "k=1:1")
	eq("follow uses focused pane", h.writes[#h.writes].pane, 2)
	h.kv.focused_target = 9 -- the bar itself: ignored
	click(def, st3, cx, "k=1:1")
	eq("follow ignores self", h.writes[#h.writes].pane, 1)

	-- target disappears
	table.remove(panes, 1)
	local before = #h.writes
	st3.follow = false
	click(def, st3, cx, "k=1:1")
	eq("gone target -> no write", #h.writes, before)
	eq("gone target -> picker", st3.picking, true)
end

do -- config files
	local h = make_env({ { pane = 1, title = "sh" } }, {
		["/home/u/.termux/termux.properties"] = "extra-keys = [[ESC, {key: CTRL, popup: {macro: 'CTRL d', display: exit}}]]\n",
	})
	h.load("host.luau")
	local def = h.blocks.bar
	local cx = mock_cx(9, h.toasts)
	local st = def.init(cx, {}, nil)
	eq("reads ~/.termux/termux.properties", st.source, "/home/u/.termux/termux.properties")
	eq("custom rows", #st.cfg.rows[1], 2)
	click(def, st, cx, "ui=layer")
	click(def, st, cx, "k=1:2")
	eq("popup macro on modifier key", h.writes[1].text, "\4")

	local bad = make_env({ { pane = 1, title = "sh" } }, { ["/data/extra-keys.json"] = "[[ESC, {key: a, macro: b}]]" })
	bad.load("host.luau")
	local st5 = bad.blocks.bar.init(mock_cx(9, bad.toasts), {}, nil)
	eq("bad config falls back", #st5.cfg.rows, 2)
	eq("bad config error kept", st5.err ~= nil and string.find(st5.err, "both key and macro", 1, true) ~= nil, true)

	local first = make_env({ { pane = 1, title = "sh" } }, {
		["/data/termux.properties"] = "extra-keys=[[TAB]]",
		["/home/u/.termux/termux.properties"] = "extra-keys=[[ESC]]",
	})
	first.load("host.luau")
	local st6 = first.blocks.bar.init(mock_cx(9, first.toasts), {}, nil)
	eq("plugin data config wins", st6.cfg.rows[1][1].key, "TAB")
end

do -- hello host block
	local panes = { { pane = 3, title = "zsh", program = "zsh" }, { pane = 4, title = "Plugin Check" } }
	local h = make_env(panes)
	h.load("hello/host.luau")
	local def = h.blocks.check
	local cx = mock_cx(4, h.toasts)
	local st = def.init(cx, {}, nil)
	local v = def.view(st, cx)
	local b = find_button(v, "#3 zsh")
	eq("hello lists pane", b ~= nil, true)
	click(def, st, cx, "send=3")
	eq("hello writes echo", h.writes[1].text, "echo tern-plugin-ok\r")
	eq("hello toast", #h.toasts, 1)
end

do -- window halves
	local h = make_env({})
	local handlers: { [string]: any } = {}
	local commands: { [string]: any } = {}
	local status_fn: any = nil
	local t: any = h.tern
	t.on = function(name: string, fn: any)
		handlers[name] = fn
	end
	t.command = function(def: any)
		commands[def.id] = def
	end
	t.chrome = { status = function(fn: any)
		status_fn = fn
	end }
	local opened: { any } = {}
	local ran: { any } = {}
	local wtoasts: { string } = {}
	local kinds: { [number]: string } = { [1] = "terminal", [7] = "plugin" }
	local wcx = {
		session = {
			pane = function(_self: any, id: number)
				return if kinds[id] then { pane = id, kind = kinds[id], title = "" } else nil
			end,
			focused = function(_self: any)
				return 1
			end,
		},
		new_block = function(_self: any, kind: string, args: { string }, how: string, reveal: any)
			table.insert(opened, { kind = kind, args = args, how = how, reveal = reveal })
			return 42
		end,
		run = function(_self: any, pane: number, text: string)
			table.insert(ran, { pane = pane, text = text })
		end,
		toast = function(_self: any, level: string, text: string, _sub: string?)
			table.insert(wtoasts, level .. ": " .. text)
		end,
	}
	h.load("window.luau")
	handlers.focus({ pane = 1, tab = 1 }, wcx)
	eq("focus stores terminal", h.kv.focused_target, 1)
	handlers.focus({ pane = 7, tab = 1 }, wcx)
	eq("focus ignores plugin panes", h.kv.focused_target, 1)
	commands.open.run(wcx)
	eq("open kind", opened[1].kind, "extrakeys.bar")
	eq("open arg is focused pane", opened[1].args[1], "1")
	eq("open below", opened[1].how, "below")
	eq("open keeps focus", opened[1].reveal.focus, false)

	h.load("hello/window.luau")
	local segs = status_fn({ pane = 1, title = "", program = "zsh", busy = false })
	eq("hello status segment", segs[1].text, "plugin check: window linux")
	eq("hello segment command", segs[1].command, "plugin.ek-hello.type")
	commands.type.run(wcx)
	eq("hello window types", ran[1].text, "echo tern-plugin-ok-window\r")
	handlers.window_start(wcx)
	eq("hello window_start toast", #wtoasts >= 2, true)
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed", 0)
end
