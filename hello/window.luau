--!strict
-- Window half check: if this half runs on your client, the status line shows
-- "plugin check: window <os>" and the palette has "Plugin Check: type in
-- focused pane", which types `echo tern-plugin-ok-window` with cx:run.

tern.chrome.status(function(_pane: StatusPaneInfo): { StatusSegment }?
	return { { text = "plugin check: window " .. tern.runtime.os, icon = "stethoscope", tone = "muted", command = "plugin.ek-hello.type" } }
end)

tern.command({
	id = "type",
	title = "Plugin Check: type in focused pane",
	icon = "stethoscope",
	run = function(cx: WindowCx)
		local f = cx.session:focused()
		if f == nil then
			cx:toast("error", "Plugin Check", "No focused pane")
			return
		end
		cx:run(f, "echo tern-plugin-ok-window\r")
		cx:toast("success", "Plugin Check", "window half ran on " .. tern.runtime.os)
	end,
})

tern.on("window_start", function(cx: WindowCx)
	cx:toast("info", "Plugin Check: window half loaded", tern.runtime.os)
end)
