-- Headless checks of the Lua simulation: `lua defold/tests/run_sim_tests.lua` from the
-- repository root (needs godot/data, i.e. `make data`). Each tests/test_*.lua returns a
-- function taking the harness below.
local root = arg[0]:match("^(.*)/defold/tests/") or "."
package.path = root .. "/defold/?.lua;" .. root .. "/defold/tests/?.lua;" .. package.path

local json = require("json")
local data = require("sim.data")

local TEST_FILES = {"test_core", "test_campaign", "test_tutorial", "test_balloon", "test_survival", "test_gesture", "test_camera_view", "test_text"}

local function read(path)
	local f = assert(io.open(root .. "/godot" .. path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local failures = 0
local h = {
	blitz = require("sim.blitz"),
	data_module = data,
	Game = require("sim.game"),
	Skills = require("sim.skills"),
	data = data.load(read, json.decode),
}

function h.check(cond, msg)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. msg)
	end
end

for _, name in ipairs(TEST_FILES) do
	require(name)(h)
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("sim tests OK")
