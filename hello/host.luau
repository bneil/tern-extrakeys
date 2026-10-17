--!strict
-- Host half check: a block with one button per other pane. Tapping one writes
-- `echo tern-plugin-ok` into it with tern.pane.write. If this block opens and
-- the line appears, host-half blocks and their button events work on your
-- client (they run on the host; the client only mirrors and sends taps).

local ui = tern.ui

type State = { cx: BlockCx, sent: string? }

local function view(state: State, cx: BlockCx): BlockView
	local items: { Node } = {
		ui.text({ ui.span("Host half: running on " .. tern.runtime.os, "strong") }),
		ui.text(ui.span("Tap a pane to type `echo tern-plugin-ok` into it:", "muted")),
	}
	local any = false
	for _, p in tern.pane.list() do
		if p.pane ~= cx.pane then
			any = true
			table.insert(
				items,
				ui.el("button", {
					key = "p" .. p.pane,
					class = "ek-hello-btn",
					text = string.format("#%d %s", p.pane, if p.title ~= "" then p.title else (p.program or "pane")),
					actions = { click = "send=" .. p.pane },
				})
			)
		end
	end
	if not any then
		table.insert(items, ui.text(ui.span("No other panes on this host yet: open a shell, then tap Refresh.", "muted")))
	end
	table.insert(items, ui.el("button", { key = "refresh", class = "ek-hello-btn", text = "Refresh", actions = { click = "refresh" } }))
	if state.sent then
		table.insert(items, ui.text(ui.span(state.sent, "success")))
	end
	return { main = ui.col(items) }
end

tern.block.define("check", {
	init = function(cx: BlockCx, _args: { string }, _saved: any): State
		return { cx = cx, sent = nil }
	end,
	view = view,
	event = function(state: State, ev: UiEvent, cx: BlockCx)
		if ev.ev == "action" and ev.act == "send" then
			local n = tonumber(ev.value)
			if n then
				tern.pane.write(n, "echo tern-plugin-ok\r")
				state.sent = "Sent to pane #" .. n .. ". Look for tern-plugin-ok there."
				cx:toast("success", "Plugin Check", "tern.pane.write sent to #" .. n)
			end
		end
	end,
} :: BlockDef<State>)
