-- Blitz3D runtime numerics (docs/12 conventions C1/C4), engine independent.
local M = {}

-- Blitz `Round`: x87 `fistp`, round half to even.
function M.round_int(x)
	local f = math.floor(x)
	local diff = x - f
	if diff < 0.5 then
		return f
	elseif diff > 0.5 then
		return f + 1
	end
	return (f % 2 == 0) and f or f + 1
end

-- Blitz integer division `\`: truncation toward zero.
function M.idiv(a, b)
	local q = math.floor(math.abs(a) / math.abs(b))
	if (a < 0) ~= (b < 0) then
		return -q
	end
	return q
end

-- C `fmod`: the result keeps the sign of the dividend (Lua's `%` floors).
function M.fmod(a, b)
	return a - b * (a < 0 and math.ceil(a / b) or math.floor(a / b))
end

-- Round to single precision: Blitz keeps every float as 32 bit, and the accumulators that
-- gate events (ingametime, tower AnimTime, skill multipliers) drift differently in double.
-- LuaJIT (the Defold runtime) has no `string.pack`, so the mantissa is rounded by hand to
-- 24 bits with IEEE round-half-to-even (symmetric for negative values).
local MANTISSA = 2 ^ 24
function M.f32_frexp(x)
	if x == 0 or x ~= x or x == math.huge or x == -math.huge then
		return x
	end
	local m, e = math.frexp(x)
	return math.ldexp(M.round_int(m * MANTISSA) / MANTISSA, e)
end

if string.pack then
	function M.f32(x)
		return (string.unpack("<f", string.pack("<f", x)))
	end
else
	M.f32 = M.f32_frexp
end

-- Blitz `Rand` / `Rnd`: the Park-Miller generator of bbmath.cpp.
local RND_A, RND_M, RND_Q, RND_R = 48271, 2147483647, 44488, 3399

local Random = {}
Random.__index = Random

function M.Random(seed)
	local self = setmetatable({}, Random)
	self:seed(seed or 0x2545F491)
	return self
end

function Random:seed(seed)
	seed = math.floor(seed) % RND_M
	if seed == 0 then
		seed = 1
	end
	self.state = seed
end

function Random:next()
	local s = self.state
	s = RND_A * (s % RND_Q) - RND_R * math.floor(s / RND_Q)
	if s < 0 then
		s = s + RND_M
	end
	self.state = s
	return (s % 65536) / 65536
end

-- `Rnd(a, b)`: float in [a, b).
function Random:rnd(a, b)
	return self:next() * (b - a) + a
end

-- `Rand(a, b)`: inclusive integer range.
function Random:rand(a, b)
	if b < a then
		a, b = b, a
	end
	return math.floor(self:next() * (b - a + 1)) + a
end

return M
