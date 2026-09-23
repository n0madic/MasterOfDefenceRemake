-- The in-game menu (`Menu/ingame.b3d`, `_fcreateingamemenu` / `_fshowingamemenu` /
-- `_fhandleingamemenu`, docs/09): the sheet with back / restart / help / to menu / exit hangs
-- in front of the camera, tilts with the mouse and carries the 3D volume sliders
-- `music.b3d` / `sound.b3d` (children of its `themusic` / `thesound` nodes) whose knob is the
-- animation frame `99.99 - volume * 100`, dragged with `_fcalcposfordragger`.
local MenuScene = require("main.ui.menu_scene")
local messages = require("main.messages")
local session = require("main.session")
local blitz = require("sim.blitz")
local screen = require("main.screen")

local M = {}
M.__index = M

local ITEMS = {"back", "restart", "tomenu", "exit", "help"}
local EXIT_LABEL = "Plane10"  -- the "Exit" caption mesh of ingame.b3d
local OPEN_SPEED = 0.4
local SLIDER_FRAMES, SLIDER_TOP = 100, 99.99
-- `RotateEntity(menu, -(my - h/2) / (h/30), (mx - w/2) / (w/40), 0)` in integer maths.
local TILT_PITCH_DIVISIONS, TILT_YAW_DIVISIONS = 30, 40

-- One volume slider: its sheet, the back plank that is dragged and the knob node.
local function slider(id, key, back, knob, holder)
	local s = {scene = MenuScene.new(id, key, {}), back = back, knob = knob, holder = holder}
	s.scene:set_item_passive(back)
	return s
end

-- `sheet_ids`: {menu, music, sound, cursor} game object ids of the location collection.
function M.new(sheet_ids)
	local self = setmetatable({}, M)
	self.menu = MenuScene.new(sheet_ids.menu, "Menu/ingame", ITEMS, sheet_ids.cursor)
	self.music = slider(sheet_ids.music, "Menu/music", "musicback", "music", "themusic")
	self.sound = slider(sheet_ids.sound, "Menu/sound", "soundback", "sound", "thesound")
	if html5 then
		-- In a browser tab "exit" would mean closing the tab: the button goes.
		self.menu:set_node_visible("exit", false)
		self.menu:set_node_visible(EXIT_LABEL, false)
	end
	self.open = false
	self.dragging = nil  -- the slider being dragged
	self:set_visible(false)
	return self
end

function M:set_visible(on)
	self.menu:set_visible(on)
	self.music.scene:set_visible(on)
	self.sound.scene:set_visible(on)
end

local function set_slider_volume(s, volume)
	s.scene:seek(SLIDER_TOP - volume * SLIDER_FRAMES)
end

local function slider_volume(s)
	return 1 - s.scene.time / SLIDER_FRAMES
end

function M:show()
	self.open = true
	self:set_visible(true)
	self.menu:animate(MenuScene.ANIM_ONESHOT, OPEN_SPEED)
	set_slider_volume(self.music, session.settings.MusicVol)
	set_slider_volume(self.sound, session.settings.SoundVol)
end

function M:hide()
	self.open = false
	self.dragging = nil
	self:set_visible(false)
end

-- `_fcalcposfordragger`: the frame (0..99) whose knob projects closest to the mouse.
local function nearest_frame(s, x, y)
	local best, best_dist = 0, math.huge
	for t = 0, SLIDER_FRAMES - 1 do
		local kx, ky = s.scene:screen_point(s.knob, t)
		if kx then
			local d = (kx - x) ^ 2 + (ky - y) ^ 2
			if d < best_dist then
				best, best_dist = t, d
			end
		end
	end
	return best
end

local function apply_volumes(self)
	msg.post(messages.AUDIO, messages.SET_VOLUMES, {music = slider_volume(self.music), sound = slider_volume(self.sound)})
end

-- Mouse held: a pick on a slider's back starts or continues dragging its knob.
local function handle_sliders(self, x, y, held)
	if not held then
		self.dragging = nil
		return
	end
	for _, s in ipairs({self.music, self.sound}) do
		if s.scene:pick(x, y) == s.back then
			self.dragging = s
		end
	end
	if self.dragging then
		self.dragging.scene:seek(nearest_frame(self.dragging, x, y))
		apply_volumes(self)
	end
end

-- The sheet follows the cursor: whole-degree pitch and yaw.
local function tilt(self, x, y)
	local mx = math.max(0, math.min(screen.WIDTH - 1, math.floor(x)))
	local my = math.max(0, math.min(screen.HEIGHT - 1, math.floor(y)))
	local pitch = blitz.idiv(-(my - screen.HEIGHT / 2), blitz.idiv(screen.HEIGHT, TILT_PITCH_DIVISIONS))
	local yaw = blitz.idiv(mx - screen.WIDTH / 2, blitz.idiv(screen.WIDTH, TILT_YAW_DIVISIONS))
	go.set_rotation(vmath.quat_rotation_y(math.rad(yaw)) * vmath.quat_rotation_x(math.rad(-pitch)), self.menu.obj.id)
end

-- One tick at box point (x, y) with the button `held` or not.
function M:tick(x, y, held)
	if not self.open then
		return
	end
	handle_sliders(self, x, y, held)
	self.menu:tick(self.dragging and -1000 or x, self.dragging and -1000 or y)
	tilt(self, x, y)
	for _, s in ipairs({self.music, self.sound}) do
		s.scene:follow(self.menu:node_matrix(s.holder))
	end
end

-- The item clicked at (x, y) (not while a slider is dragged), or nil.
function M:click(x, y)
	if not self.open or self.dragging then
		return nil
	end
	return self.menu:click(x, y)
end

-- Keep the slider volumes in the settings (`_fsaveoptions`).
function M:save_volumes()
	session.settings.MusicVol = slider_volume(self.music)
	session.settings.SoundVol = slider_volume(self.sound)
	session.save_settings()
end

return M
