-- The balloon (docs/07): locations 4-6 only, the cosine tween's length, bombs.
local Balloon = require("sim.balloon")
local savegame = require("sim.savegame")

return function(h)
	local check, Game, d = h.check, h.Game, h.data
	local g = Game.new(d, 3)
	g:start_campaign(0, 3)
	check(g.balloon == nil, "no balloon on location 3")
	g:start_campaign(0, 4)
	local b = g.balloon
	local bounds = d:location(4).bounds
	check(b and b.position.x == (bounds.x_min + bounds.x_max) / 2 and b.position.y == Balloon.HEIGHT, "location 4's balloon starts at its centre")

	-- `_fmoveballoonto`: Round(10 * dist) ticks, cosine eased, height kept.
	local start = {x = b.position.x, y = b.position.y, z = b.position.z}
	local dest = {x = start.x + 6, y = 0, z = start.z + 8}
	check(g:move_balloon(dest), "the balloon takes the order")
	local ticks = 0
	while b:moving() and ticks < 1000 do
		g:handle_balloon()
		ticks = ticks + 1
	end
	check(ticks == 101, "10 * 10 ticks plus the tween's first frame, got " .. ticks)
	check(math.abs(b.position.x - dest.x) < 1e-9 and math.abs(b.position.z - dest.z) < 1e-9 and b.position.y == Balloon.HEIGHT, "arrived at the height it flies")

	-- A bomb drops once the timer passed 200 with a monster near, falls 0.2 a tick and hits
	-- everything within 7 for 350 (armour ignored), freezing with cold magic.
	g.skills.cold_magic = 2
	local e = g:create_enemy(false, 1)
	e.path.body = {x = b.position.x, y = 0, z = b.position.z}
	e.life = 1000
	b.timer = Balloon.BOMB_INTERVAL_TICKS
	g:take_events()
	g:handle_balloon()
	local ev = g:take_events()
	check(#g.bombs == 1 and ev[#ev].type == "bomb_dropped" and b.timer == 0, "a bomb dropped")
	local fall = 0
	while #g.bombs > 0 and fall < 200 do
		g:handle_bombs()
		fall = fall + 1
	end
	-- 11 units at 0.2 a tick: after 55 float32 steps a sliver above the ground is left.
	check(fall == 56, "the bomb lands on the 56th tick, got " .. fall)
	check(e.life == 1000 - Game.BOMB_DAMAGE and e.freeze == 60, "bomb damage and freeze: " .. e.life .. " " .. e.freeze)

	-- The save keeps where the balloon is.
	local save = savegame.serialize(g)
	local r = Game.new(d, 4)
	savegame.restore(r, save)
	check(r.balloon and r.balloon.position.x == b.position.x and r.balloon.position.z == b.position.z, "the balloon's position is saved")
end
