-- Core simulation checks: Blitz numerics, the tables, economy, skills and a full scripted
-- defense of location 1.
return function(h)
local check, blitz, data, Game, Skills = h.check, h.blitz, h.data_module, h.Game, h.Skills
-- blitz numerics
check(blitz.round_int(2.5) == 2 and blitz.round_int(3.5) == 4 and blitz.round_int(2.6) == 3, "round half to even")
check(blitz.idiv(-7, 2) == -3 and blitz.idiv(7, 2) == 3, "idiv truncates")
check(math.abs(blitz.f32(0.1) - 0.100000001490116) < 1e-12, "f32 rounding")
check(blitz.fmod(-1.5, 1) == -0.5, "fmod sign")
if string.pack then
	-- The LuaJIT fallback must match the IEEE conversion bit for bit.
	local acc_packed, acc_frexp, same = 0, 0, true
	for _ = 1, 2000 do
		acc_packed = blitz.f32(acc_packed + blitz.f32(0.01))
		acc_frexp = blitz.f32_frexp(acc_frexp + blitz.f32_frexp(0.01))
		same = same and acc_packed == acc_frexp
	end
	for _, x in ipairs({0.1, -0.1, 1 / 3, -1 / 3, 1 + 2 ^ -24, 1 + 3 * 2 ^ -24, -(1 + 2 ^ -24), 123456.789, -2.5e-7}) do
		same = same and blitz.f32(x) == blitz.f32_frexp(x)
	end
	check(same, "f32 fallback rounds half to even like string.pack")
end
local rng = blitz.Random(1)
local ok = true
for _ = 1, 1000 do
	local r = rng:rand(1, 4)
	local x = rng:rnd(-1, 1)
	ok = ok and r >= 1 and r <= 4 and x >= -1 and x < 1
end
check(ok, "rng ranges")

local d = h.data
check(d:text(48) == "Raid", "texts loaded: " .. tostring(d:text(48)))
check(d.location_first_raid[2] == 16, "location_first_raid")
check(#d.paths[1].pos == 21 and d.paths[1].frames == 20, "path 1 keys")

-- Path travel time of the slowest raid of location 1: docs/03 gives 938 ticks at 1.03.
local g = Game.new(d, 7)
g:start_campaign(0, 1)
do
	local e = g:create_enemy(false, 10)
	local ticks = 0
	while not e.path:finished() and ticks < 5000 do
		e.path:advance(e.speed, e.speed * 0.25)
		ticks = ticks + 1
	end
	check(math.abs(ticks - 938) <= 30, "travel time " .. ticks)
	g:delete_enemy(e, false, false)
end

-- The raid's last monster takes the last life in the tick that ends the raid: the game is
-- lost and the raid is not finished (no income, no automatic save, no completed location).
do
	local lg = Game.new(d, 11)
	lg:start_campaign(0, 1)
	lg.create_enemies_mode = false
	local e = lg:create_enemy(false, 10)
	while not e.path:finished() do
		e.path:advance(e.speed, e.speed * 0.25)
	end
	lg.lifes, lg.old_lifes = 1, 1
	lg:take_events()
	lg:update_enemies()
	local kinds = {}
	for _, ev in ipairs(lg:take_events()) do
		kinds[ev.type] = ev
	end
	check(kinds.game_over and lg.curlevel == 1, "game over at the raid reached")
	check(not kinds.raid_finished and not kinds.autosave and not kinds.location_completed, "a lost raid does not finish")
end

-- Tower economics
g.gold = 200
local t = g:build_tower(1, {x = 60, y = 0, z = -50})
check(t ~= nil and g.gold == 170, "build charges 30")
g:select_tower(t)
check(g:upgrade_selected_tower() and g.gold == 150 and t.level == 1, "upgrade charges 20")
check(t.upgrade_pending, "upgrade pending until idle seq ends")
local guard = 0
while Game.tower_is_upgrading(t) == false and guard < 200 do
	g:tick()
	guard = guard + 1
end
check(Game.tower_is_upgrading(t), "upgrade animation started")
while Game.tower_is_upgrading(t) and guard < 500 do
	g:tick()
	guard = guard + 1
end
check(t.land_damage == 40 and t.rate_of_fire_ms == 892, "level 1 parameters after the animation")
check(g:sell_value(t) == blitz.round_int(0.75 * 50), "sell value")
check(g:sell_selected_tower() and #g.towers == 0, "sell")

-- A stopped tower after one that found a target: the shared candidate reaches it, `shoot`
-- refuses it, and its stale target is cleared (Game.gd / `_fhandletowers`).
do
	local tg = Game.new(d, 3)
	tg:start_campaign(0, 1)
	tg.gold = 1000
	local e = tg:create_enemy(false, 1)
	local p = e.path.body
	local first = tg:build_tower(data.TOWER_PLANT, {x = p.x + 2, y = 0, z = p.z})
	local stopped = tg:build_tower(data.TOWER_PLANT, {x = p.x - 2, y = 0, z = p.z})
	first.timer = first.rate_of_fire_ms + 1
	stopped.stopped, stopped.target = true, e
	tg:handle_towers()
	check(first.target == e, "the first tower targets the monster in range")
	check(stopped.target == nil, "a stopped tower drops its stale target")
end

-- `_fhandleenemyselection` / `_fselecttower`: one selection at a time; an inhabitant is
-- selected but never becomes the towers' target.
do
	local WORKER_UNIT = 32  -- Male
	local sg = Game.new(d, 3)
	sg:start_campaign(0, 1)
	sg.gold = 1000
	local e = sg:create_enemy(false, 1)
	local t = sg:build_tower(data.TOWER_LAND, {x = e.path.body.x + 30, y = 0, z = e.path.body.z})
	sg:select_tower(t)
	sg:select_enemy(e)
	check(sg.selected_enemy == e and e.selected, "the monster is selected")
	check(t.target == e, "the selected monster becomes every tower's target")
	check(sg.selected_tower == nil and not t.selected, "selecting a monster drops the tower")
	sg:select_tower(t)
	check(sg.selected_enemy == nil and not e.selected, "selecting a tower drops the monster")
	t.target = nil
	local worker = sg:create_enemy(false, WORKER_UNIT)
	check(worker.worker, "unit 32 is an inhabitant")
	sg:select_enemy(worker)
	check(sg.selected_enemy == worker and t.target == nil, "a selected inhabitant is not targeted")
	-- `_fshowenemyinfoondisplay`: the text opens with a line break (the time slider covers
	-- the first line); an 8-digit life loses the space after the colon.
	local hud = require("main.location.hud_model")
	e.life = 90
	check(hud.enemy_info(sg, e):find("\n" .. d:text(69) .. ": 90\n", 1, true) == 1, "enemy info starts below the slider")
	e.life = 12345678
	check(hud.enemy_info(sg, e):find("\n" .. d:text(69) .. ":12345678\n", 1, true) == 1, "no space before an 8-digit life")
end

-- Skills
g.experience = 500
local sk = g.skills
sk:operate(g, Skills.DAMAGE, false)
check(g.experience == 450 and g.protos[1][0].land_damage > 20, "damage skill scales prototypes")
sk:cancel(g)
check(g.experience == 500 and math.abs(g.protos[1][0].land_damage - 20) < 1e-4, "cancel restores")

-- Full scripted defense of location 1: towers next to the path keys, away from the spawn
-- point (a raid whose first monster dies before the second spawns ends at once, like the
-- original's `_fdeleteenemy` -> `_fnextlevel`, and the rest of it spills into the next raid).
g = Game.new(d, 42)
g:start_campaign(0, 1)
g.gold = 400
local keys = d.paths[1].pos
for i = 6, 18, 3 do
	local k = keys[i]
	g:build_tower(1, {x = k.x + 4, y = 0, z = k.z + 4})
	g:build_tower(3, {x = k.x - 4, y = 0, z = k.z - 4})
end
g:build_tower(2, {x = keys[9].x, y = 0, z = keys[9].z + 5})
g:build_tower(2, {x = keys[15].x, y = 0, z = keys[15].z + 5})
local ticks = 0
local raids_started, enemies_seen = 0, 0
-- A stand-in for main/level.script's view bookkeeping: every creation event must be
-- matched by a removal event, otherwise the engine would keep drawing dead objects.
local views = {enemies = {}, towers = {}, bullets = {}}
local leaks = 0
local function view_open(set, obj)
	if set[obj] then
		leaks = leaks + 1
	end
	set[obj] = true
end
local function view_close(set, obj)
	if not set[obj] then
		leaks = leaks + 1
	end
	set[obj] = nil
end
while not g.location_completed and not g.is_game_over and ticks < 200000 do
	g:tick()
	ticks = ticks + 1
	for _, ev in ipairs(g:take_events()) do
		if ev.type == "raid_started" then
			raids_started = raids_started + 1
		elseif ev.type == "enemy_spawned" then
			enemies_seen = enemies_seen + 1
			view_open(views.enemies, ev.enemy)
		elseif ev.type == "enemy_died" then
			-- Why the views are keyed by the object and not by its id: `_fdeleteenemy`
			-- clears the id right after emitting, and events are drained after the tick.
			check(ev.enemy.id == 0, "a drained enemy_died event has a cleared id")
			view_close(views.enemies, ev.enemy)
		elseif ev.type == "tower_built" then
			view_open(views.towers, ev.tower)
		elseif ev.type == "tower_removed" then
			view_close(views.towers, ev.tower)
		elseif ev.type == "bullet_created" then
			view_open(views.bullets, ev.bullet)
		elseif ev.type == "bullet_removed" then
			check(ev.bullet.id == 0, "a drained bullet_removed event has a cleared id")
			view_close(views.bullets, ev.bullet)
		end
	end
	-- Keep upgrading the first tower whenever gold allows.
	-- Upgrade the cheapest-to-upgrade tower whenever gold allows.
	if g.gold > 100 then
		for _, t in ipairs(g.towers) do
			if t.level < t.max_upgrades and not Game.tower_is_upgrading(t) and not t.upgrade_pending then
				g:select_tower(t)
				if g:upgrade_selected_tower() then
					break
				end
			end
		end
	end
end
check(leaks == 0, "every view creation is matched by a removal, " .. leaks .. " mismatch(es)")
for name, set in pairs({enemies = g.enemies, towers = g.towers, bullets = g.bullets}) do
	local live, open = {}, 0
	for _, obj in ipairs(set) do live[obj] = true end
	for obj in pairs(views[name]) do
		open = open + 1
		check(live[obj], "leaked " .. name .. " view")
	end
	check(open == #set, name .. " views " .. open .. " vs simulation " .. #set)
end
check(raids_started == 15, "15 raids started, got " .. raids_started)
check(g.location_completed, "location completed (game over=" .. tostring(g.is_game_over) .. ", lifes=" .. g.lifes .. ", ticks=" .. ticks .. ")")
check(g.experience >= 15 * 20, "experience per raid")
print(string.format("campaign: %d ticks, %d enemies, lifes %d, gold %d, exp %d", ticks, enemies_seen, g.lifes, g.gold, g.experience))

end
