-- The decorations of a location (`_fdecoratelocation` / `_fhandledecorates`): location 1's
-- clock showing the system time, location 2's eagle circling on its bird path and the
-- water loop at location 2's door, heard louder as the camera comes near.
local model = require("main.views.model")
local messages = require("main.messages")
local blitz = require("sim.blitz")

local f32 = blitz.f32

local M = {}
M.__index = M

local SECOND_STEP, MINUTE_STEP = f32(0.016666668), f32(0.00027777778)
local HOURS = 12
local PATH_SPEED, EAGLE_SPEED = 0.1, 0.1
local EAGLE_TURN = vmath.quat_rotation_y(math.pi)  -- `TurnEntity eagle, 0, 180, 0`
local WATER_SOUND = "water"
-- `CreateListener(camera, rolloff 0.08)`: DirectSound3D's distance attenuation.
local WATER_ROLLOFF, WATER_MIN_DISTANCE = 0.08, 1

-- `location`: the generated/locations entry.
function M.new(location)
	local self = setmetatable({}, M)
	self.location = location
	if location.clock then
		-- `_fdecoratelocation`: the hands start at the system time (12-hour dial).
		local now = os.date("*t")
		self.hours = now.hour > HOURS and now.hour - HOURS or now.hour
		self.minutes, self.seconds = f32(now.min), f32(now.sec)
		self:set_clock()
	end
	if location.eagle then
		local first = location.eagle.frames[1]
		self.eagle = model.spawn(location.eagle.model, vmath.vector3(first.pos[1], first.pos[2], first.pos[3]), vmath.quat(), 1)
		self.path_time, self.eagle_time = 0, 0
	end
	if location.water_emitter then
		msg.post(messages.AUDIO, messages.PLAY_LOOP, {name = WATER_SOUND})
		local p = location.water_emitter
		self.water_at = vmath.vector3(p[1], p[2], p[3])
	end
	return self
end

function M:set_clock()
	local ids = self.location.clock
	go.set_rotation(vmath.quat_rotation_z(math.rad(-self.hours * 30)), ids.hours)
	go.set_rotation(vmath.quat_rotation_z(math.rad(-self.minutes * 6)), ids.minutes)
	go.set_rotation(vmath.quat_rotation_z(math.rad(-self.seconds * 6)), ids.seconds)
end

-- `_fhandledecorates`, once per tick (the original's own rollovers).
local function tick_clock(self)
	self.seconds = f32(self.seconds + SECOND_STEP)
	self.minutes = f32(self.minutes + MINUTE_STEP)
	if self.seconds >= 60 then
		self.seconds = 0
	end
	if self.minutes > 60 then
		self.minutes = 1
		self.hours = self.hours + 1
	end
	if self.hours > HOURS then
		self.hours = 1
	end
end

local function place_eagle(self)
	local pos, rot = model.sample_pose(self.location.eagle.frames, self.path_time, true)
	go.set_position(pos, self.eagle.id)
	go.set_rotation(rot * EAGLE_TURN, self.eagle.id)
	model.md2_frame(self.eagle, self.eagle_time, self.eagle.meta.morph_targets)
end

-- After `ticks` game ticks; `camera_pos` places the listener.
function M:sync(ticks, camera_pos)
	if self.hours then
		for _ = 1, ticks do
			tick_clock(self)
		end
		if ticks > 0 then
			self:set_clock()
		end
	end
	if self.eagle then
		local frames = #self.location.eagle.frames
		self.path_time = (self.path_time + PATH_SPEED * ticks) % frames
		self.eagle_time = (self.eagle_time + EAGLE_SPEED * ticks) % math.max(self.eagle.meta.morph_targets, 1)
		place_eagle(self)
	end
	if self.water_at then
		local d = math.max(WATER_MIN_DISTANCE, vmath.length(camera_pos - self.water_at))
		local gain = WATER_MIN_DISTANCE / (WATER_MIN_DISTANCE + WATER_ROLLOFF * (d - WATER_MIN_DISTANCE))
		if not self.water_gain or math.abs(gain - self.water_gain) > 0.01 then
			self.water_gain = gain
			msg.post(messages.AUDIO, messages.SET_LOOP_GAIN, {name = WATER_SOUND, gain = gain})
		end
	end
end

return M
