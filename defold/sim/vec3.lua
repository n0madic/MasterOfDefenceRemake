-- Minimal 3-vectors as plain tables, so the simulation runs outside the engine too.
local M = {}

function M.new(x, y, z)
	return {x = x or 0, y = y or 0, z = z or 0}
end

function M.copy(v)
	return {x = v.x, y = v.y, z = v.z}
end

function M.add(a, b)
	return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
end

function M.sub(a, b)
	return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
end

function M.scale(v, s)
	return {x = v.x * s, y = v.y * s, z = v.z * s}
end

function M.length(v)
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

function M.distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.normalized(v)
	local l = M.length(v)
	if l == 0 then
		return {x = 0, y = 0, z = 0}
	end
	return {x = v.x / l, y = v.y / l, z = v.z / l}
end

function M.lerp(a, b, t)
	return {x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t}
end

-- Rotation about the Y axis by `degrees` (Godot `Vector3.rotated(UP, angle)`).
function M.rotate_y(v, degrees)
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return {x = v.x * c + v.z * s, y = v.y, z = -v.x * s + v.z * c}
end

return M
