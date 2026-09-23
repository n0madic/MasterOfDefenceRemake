-- Bone-matrix uploads of a bone-posed model (main/views/model.lua `pose`): one `go.set`
-- per group with a table of joints, the static joints sent only with a full pose. Runs
-- headless on stand-ins for the engine's vmath / go / sys.

local V4 = {}
V4.__index = V4
V4.__eq = function(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w
end
local function vector4(x, y, z, w)
	return setmetatable({x = x or 0, y = y or 0, z = z or 0, w = w or 0}, V4)
end

local stubs = {
	vmath = {
		vector4 = vector4,
		matrix4 = function()
			return {c0 = vector4(1, 0, 0, 0), c1 = vector4(0, 1, 0, 0), c2 = vector4(0, 0, 1, 0), c3 = vector4(0, 0, 0, 1)}
		end,
		lerp = function(a, p, q)
			return vector4(p.x + (q.x - p.x) * a, p.y + (q.y - p.y) * a, p.z + (q.z - p.z) * a, p.w + (q.w - p.w) * a)
		end,
	},
}

-- Little-endian float32 bytes of the values the blob uses.
local F32 = {[0] = "\0\0\0\0", [1] = "\0\0\128\63", [2] = "\0\0\0\64"}

-- Two joints over two frames, row-major 4x4 each: joint 1 stays the identity, joint 2
-- scales by 2 on frame 1.
local function bone_blob()
	local out = {}
	for f = 0, 1 do
		for j = 1, 2 do
			local d = (j == 2 and f == 1) and 2 or 1
			for r = 0, 3 do
				for c = 0, 3 do
					out[#out + 1] = F32[(r == c) and (r == 3 and 1 or d) or 0]
				end
			end
		end
	end
	return table.concat(out)
end

return function(h)
	local check = h.check
	local saved = {vmath = rawget(_G, "vmath"), go = rawget(_G, "go"), sys = rawget(_G, "sys")}
	local sets = {}
	vmath = stubs.vmath
	go = {set = function(url, property, value)
		local keys = {}
		for j in pairs(value) do
			keys[#keys + 1] = j
		end
		table.sort(keys)
		sets[#sets + 1] = {url = url, property = property, keys = table.concat(keys, ","), value = value}
	end}
	sys = {load_resource = function()
		return bone_blob()
	end}
	package.loaded["generated.models"] = {}
	package.loaded["main.views.model"] = nil
	local model = require("main.views.model")

	local obj = {key = "pose_test", meta = {bones = {count = 2, frames = 2, resource = "/pose_test.bin"}}, urls = {"a", "b"}}
	local function last_keys()
		return sets[#sets] and sets[#sets].keys
	end

	model.pose(obj, 0)
	check(#sets == 2 and sets[1].property == "bone_matrices" and last_keys() == "1,2",
		"the first pose sends every joint to each group in one go.set")
	check(#obj.bones.animated == 1 and obj.bones.animated[1] == 2, "only joint 2 is animated")
	model.pose(obj, 0)
	check(#sets == 2, "an unchanged plain pose sends nothing")
	model.pose(obj, 1)
	check(#sets == 4 and last_keys() == "2", "a later plain pose resends only the animated joint")
	check(sets[4].value[2].c0.x == 2, "the animated joint takes the new frame")
	model.pose(obj, 1, {[1] = true})
	check(#sets == 6 and last_keys() == "1,2" and sets[6].value[1].c0.x == 0, "a hidden joint goes out as a zero matrix")
	model.pose(obj, 1)
	check(#sets == 8 and last_keys() == "1,2" and sets[8].value[1].c0.x == 1,
		"after a hidden pose the next plain pose restores every joint")

	package.loaded["main.views.model"] = nil
	package.loaded["generated.models"] = nil
	vmath, go, sys = saved.vmath, saved.go, saved.sys
end
