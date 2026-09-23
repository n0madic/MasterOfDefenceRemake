-- Display settings: the 4:3 / Wide screen mode and the gamma (both drawn by the render
-- script, told with `set_display`) and, in a browser, fullscreen. The desktop window mode
-- is the platform's (game.project / the window manager): the engine cannot switch it.
local messages = require("main.messages")

local M = {}

M.GAMMA_RANGE = 100

function M.can_toggle_fullscreen()
	return html5 ~= nil
end

function M.is_fullscreen()
	return html5 ~= nil and html5.run("document.fullscreenElement ? '1' : '0'") == "1"
end

-- A browser enters fullscreen only from a user gesture: the request runs on the next
-- click or key press (html5 interaction listener).
function M.set_fullscreen(on)
	if not html5 then
		return
	end
	html5.set_interaction_listener(function()
		html5.set_interaction_listener(nil)
		if on then
			html5.run("document.documentElement.requestFullscreen && document.documentElement.requestFullscreen()")
		else
			html5.run("document.fullscreenElement && document.exitFullscreen()")
		end
	end)
end

-- Debug (`wide=1`): the Wide mode regardless of the saved setting.
M.force_wide = false

-- Send the settings' screen mode and gamma to the render script (and the mouse mapping).
function M.apply(settings)
	msg.post(messages.RENDER, messages.SET_DISPLAY, {wide = M.force_wide or settings.WideScreen == 1, gamma = settings.GammaIntensity})
end

return M
