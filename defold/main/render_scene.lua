-- The screens' `set_scene` message to render/blitz.render_script: the background colour
-- and the scene light (the generated `light` tables: {dir, color, ambient, points}).
local messages = require("main.messages")
local screen = require("main.screen")

local M = {}

-- The 2D screens (map, ending): black, full ambient, no light.
M.NEUTRAL = {clear_color = {0, 0, 0}, light = {dir = {0, -1, 0}, color = {0, 0, 0}, ambient = {1, 1, 1}}}

local function vec4(v, w)
	return vmath.vector4(v[1], v[2], v[3], w)
end

-- `scene`: {clear_color, light, max_aspect (default 4:3)}.
function M.set(scene)
	local l = scene.light
	local message = {
		clear_color = vec4(scene.clear_color, 1),
		light_dir = vec4(l.dir, 0), light_color = vec4(l.color, 1), ambient = vec4(l.ambient, 1),
		max_aspect = scene.max_aspect or screen.ASPECT,
	}
	for i, point in ipairs(l.points or {}) do
		message["point_light" .. (i - 1)] = vec4(point.pos, point.range)
		message["point_color" .. (i - 1)] = vec4(point.color, 1)
	end
	msg.post(messages.RENDER, messages.SET_SCENE, message)
end

return M
