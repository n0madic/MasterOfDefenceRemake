-- Mouse picking (`CameraPick`): a ray from the camera against the build zones (triangle
-- lists from the exporter), tower boxes and monster spheres / boxes.
local M = {}

M.FOV = 0.8173  -- vertical, 60 degrees horizontal at 4:3
M.TOWER_BOX = {x = 2.8, y = 8.4, z = 2.8}
M.ENEMY_RADIUS = 2.5
M.AIR_BOX = {x = 3, y = 3, z = 3}
M.AIR_OFFSET_Y = 3

-- World-space ray through window pixel (x, y) (origin bottom-left) of a `w` x `h` window.
function M.ray(cam_pos, cam_rot, x, y, w, h)
	local t = math.tan(M.FOV / 2)
	local nx = (2 * x / w - 1) * t * (w / h)
	local ny = (2 * y / h - 1) * t
	local dir = vmath.normalize(vmath.rotate(cam_rot, vmath.vector3(nx, ny, -1)))
	return cam_pos, dir
end

local EPS = 1e-7

-- Moeller-Trumbore ray/triangle test; returns the distance along the ray or nil.
local function hit_triangle(o, d, ax, ay, az, bx, by, bz, cx, cy, cz)
	local e1x, e1y, e1z = bx - ax, by - ay, bz - az
	local e2x, e2y, e2z = cx - ax, cy - ay, cz - az
	local px = d.y * e2z - d.z * e2y
	local py = d.z * e2x - d.x * e2z
	local pz = d.x * e2y - d.y * e2x
	local det = e1x * px + e1y * py + e1z * pz
	if det > -EPS and det < EPS then
		return nil
	end
	local inv = 1 / det
	local tx, ty, tz = o.x - ax, o.y - ay, o.z - az
	local u = (tx * px + ty * py + tz * pz) * inv
	if u < 0 or u > 1 then
		return nil
	end
	local qx = ty * e1z - tz * e1y
	local qy = tz * e1x - tx * e1z
	local qz = tx * e1y - ty * e1x
	local v = (d.x * qx + d.y * qy + d.z * qz) * inv
	if v < 0 or u + v > 1 then
		return nil
	end
	local dist = (e2x * qx + e2y * qy + e2z * qz) * inv
	if dist > EPS then
		return dist
	end
	return nil
end

-- Nearest zone hit: zone name, point, distance.
function M.pick_zone(zones, o, d)
	local best, best_zone
	for zone, tris in pairs(zones) do
		for i = 1, #tris, 9 do
			local dist = hit_triangle(o, d, tris[i], tris[i + 1], tris[i + 2], tris[i + 3], tris[i + 4], tris[i + 5], tris[i + 6], tris[i + 7], tris[i + 8])
			if dist and (not best or dist < best) then
				best, best_zone = dist, zone
			end
		end
	end
	if best then
		return best_zone, o + d * best, best
	end
	return nil
end

-- Ray/axis-aligned box (centre c, half extents h): distance or nil.
local function hit_box(o, d, c, h)
	local tmin, tmax = -math.huge, math.huge
	for _, axis in ipairs({"x", "y", "z"}) do
		local lo, hi = c[axis] - h[axis], c[axis] + h[axis]
		if math.abs(d[axis]) < EPS then
			if o[axis] < lo or o[axis] > hi then
				return nil
			end
		else
			local t1, t2 = (lo - o[axis]) / d[axis], (hi - o[axis]) / d[axis]
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmax < 0 then
		return nil
	end
	return math.max(tmin, 0)
end

local function hit_sphere(o, d, c, r)
	local lx, ly, lz = c.x - o.x, c.y - o.y, c.z - o.z
	local tca = lx * d.x + ly * d.y + lz * d.z
	local d2 = lx * lx + ly * ly + lz * lz - tca * tca
	if d2 > r * r then
		return nil
	end
	local thc = math.sqrt(r * r - d2)
	local t = tca - thc
	if t < 0 then
		t = tca + thc
	end
	if t < 0 then
		return nil
	end
	return t
end

-- The nearest tower under the ray (hitbox 2.8 x 8.4 x 2.8 standing on the ground).
function M.pick_tower(towers, o, d)
	local best, found
	local half = {x = M.TOWER_BOX.x / 2, y = M.TOWER_BOX.y / 2, z = M.TOWER_BOX.z / 2}
	for _, t in ipairs(towers) do
		local c = {x = t.position.x, y = t.position.y + half.y, z = t.position.z}
		local dist = hit_box(o, d, c, half)
		if dist and (not best or dist < best) then
			best, found = dist, t
		end
	end
	return found
end

function M.pick_enemy(enemies, o, d)
	local best, found
	local half = {x = M.AIR_BOX.x / 2, y = M.AIR_BOX.y / 2, z = M.AIR_BOX.z / 2}
	for _, e in ipairs(enemies) do
		local p = e.path.body
		local dist
		if e.air then
			dist = hit_box(o, d, {x = p.x, y = p.y + M.AIR_OFFSET_Y, z = p.z}, half)
		else
			dist = hit_sphere(o, d, p, M.ENEMY_RADIUS)
		end
		if dist and (not best or dist < best) then
			best, found = dist, e
		end
	end
	return found
end

return M
