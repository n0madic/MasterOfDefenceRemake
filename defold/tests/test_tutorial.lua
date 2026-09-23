-- The tutorial's page sequence (`_fhandletutorial`, `_fnexttutorialpage`, `_ftutorialstep`).
local Tutorial = require("sim.tutorial")

return function(h)
	local check, Game, d = h.check, h.Game, h.data
	local g = Game.new(d, 1)
	g:start_campaign(0)
	local t = Tutorial.new(g)
	t:start(d:location(1).tutorial_page)
	check(t:page() == Tutorial.PAGE_GOLD, "location 1 starts on page 1")
	g.ingame_time = 3
	t:tick()
	check(g.ingame_time == 0, "the raid timer holds while the tutorial runs")
	t:next()
	check(t:page() == Tutorial.PAGE_TOWERS, "next: page 2")
	g:take_events()
	t:next()
	check(t:page() == 0 and t.state == Tutorial.PAGE_HIDDEN_BUILD, "page 2 hides until a tower is placed")
	local ev = g:take_events()
	check(#ev == 1 and ev[1].type == "message" and ev[1].text == d:text(56), "the build task is stated")
	t:on_tower_placed()
	check(t:page() == Tutorial.PAGE_UPGRADE, "a placed tower shows page 4")
	t:on_upgrade_pressed()
	check(t:page() == 0 and t.state == Tutorial.PAGE_SELL, "the upgrade hides the sheet")
	t:on_upgrade_finished()
	check(t:page() == Tutorial.PAGE_SELL, "the finished upgrade shows page 5")
	t:on_sell()
	check(t:page() == Tutorial.PAGE_SPEED, "selling shows page 6")
	t:next()
	check(t:page() == Tutorial.PAGE_MONSTERS, "page 7")
	t:next()
	check(t:page() == 0 and not t:running() and g.ingame_time == Tutorial.LOCATION1_EXTRA_WAIT,
		"the end on location 1 gives 5 extra seconds")

	-- Page 8 on location 2 opens the skills window; help (10) gives no extra wait.
	g:next_location()
	local t2 = Tutorial.new(g)
	t2:start(d:location(2).tutorial_page)
	check(t2:page() == Tutorial.PAGE_SKILLS and t2:next() == "open_skills", "page 8 opens the skills window")
	g.ingame_time = 1
	t2:start(Tutorial.PAGE_HELP)
	t2:next()
	check(t2:page() == 0 and g.ingame_time == 1, "help closes without the extra wait")
	local t3 = Tutorial.new(g)
	t3:start(Tutorial.PAGE_GOLD)
	t3:disable()
	check(not t3:running(), "skip ends the tutorial")
end
