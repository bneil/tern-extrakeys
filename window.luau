--!strict
-- Window half (optional): remembers the focused terminal pane for bars in
-- "follow" mode, and adds a palette command that opens a bar below the
-- focused pane, aimed at it. The kv store is per machine, so "follow" only
-- works when this window and the daemon running the bar share a machine.

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
		local args: { string } = {}
		local f = cx.session:focused()
		if f then
			table.insert(args, tostring(f))
		end
		local pane = cx:new_block("extrakeys.bar", args, "below", { focus = false })
		if pane == nil then
			cx:toast("error", "Extra Keys isn't ready on this host", "Install the plugin on the machine that runs your shells.")
		end
	end,
})
