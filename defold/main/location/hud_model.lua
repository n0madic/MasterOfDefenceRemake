-- The HUD as data (docs/09, docs/13): widget layout in the 800x600 box and the texts and
-- tooltips composed from the simulation. Engine independent; main/location/hud.gui_script
-- draws the snapshot `build` returns and owns the input.
local Game = require("sim.game")
local Skills = require("sim.skills")
local profile = require("sim.profile")
local data = require("sim.data")
local blitz = require("sim.blitz")
local text_layout = require("main.blitz_text")

local M = {}

M.STYLE_BIG, M.STYLE_SMALL1, M.STYLE_SMALL2 = 0, 1, 2
M.COLOR_GOLD = {1, 203 / 255, 0}
M.COLOR_LIFES = {110 / 255, 200 / 255, 230 / 255}
M.COLOR_EXTRA = {180 / 255, 227 / 255, 242 / 255}
M.COLOR_EXP = {247 / 255, 232 / 255, 172 / 255}
M.COLOR_HELP = {247 / 255, 232 / 255, 171 / 255}
M.COLOR_EXP_TITLE = {0, 200 / 255, 120 / 255}
M.COLOR_FIRE6 = {1, 207 / 255, 115 / 255}
M.COLOR_WHITE = {1, 1, 1}
M.MSG_COLORS = {[1] = {1, 1, 1}, [2] = {1, 0, 0}, [3] = M.COLOR_GOLD, [4] = {0, 1, 0}}
M.MESSAGE_X, M.MESSAGE_Y, M.MESSAGE_STEP, M.MESSAGE_FADE = 20, 510, 16, 0.01
M.GOLD_POPUP_RISE, M.GOLD_POPUP_MS = 0.5, 100
M.TIP_WIDTH, M.TIP_LINE, M.TIP_MARGIN = 175, 12.8, 6.4
M.HELP_X, M.HELP_Y, M.HELP_WIDTH = 15, 120, 185
M.SLIDER = {x = 400, y = 500, w = 190, h = 20, edge = 7}
M.RESET_MARK = {x = 432 + 8 - 10, y = 477 + 12 - 10, w = 20, h = 15}
M.PROGRESS = {x = 648, y = 512, w = 152, h = 32}
M.TOWER_BUTTON_Y = 530
M.TOWER_BUTTON_X = {5, 70, 135, 200, 265}
M.UPGRADE_SLOTS = {200, 265, 330}
M.SKILL_ROWS = {
	-- {id, y button, y text, tip+, tip-, help index}
	{Skills.COLD, 105, 113, 61, 96, 0},
	{Skills.FIRE, 135, 141, 62, 97, 1},
	{Skills.POISON, 165, 172, 63, 98, 2},
	{Skills.SPEED, 202, 212, 36, 94, 3},
	{Skills.RANGE, 233, 240, 37, 95, 4},
	{Skills.DAMAGE, 263, 266, 35, 93, 5},
	{Skills.SELL, 293, 295, 34, 92, 6},
	{Skills.RESISTANCE, 328, 335, 64, 99, 7},
	{Skills.GOLD, 360, 365, 32, 91, 8},
}
M.SKILL_PLUS_X, M.SKILL_MINUS_X, M.SKILL_TEXT_X, M.SKILL_BUTTON = 520, 550, 470, 30
M.COLOR_STORY = {0, 1, 130 / 255}
-- Wide-screen anchors (godot HudLayout): -1 / 0 / 1 per axis = left or top edge of the
-- canvas, centred with the box, right or bottom edge. Widgets and texts without one stay in
-- the box.
M.TOP_LEFT, M.TOP_CENTRE, M.TOP_RIGHT = {-1, -1}, {0, -1}, {1, -1}
M.BOTTOM_LEFT, M.BOTTOM_CENTRE, M.BOTTOM_RIGHT = {-1, 1}, {0, 1}, {1, 1}
M.TUTORIAL_TEXT = {x = 100, y = 105, spacing = 4.5}
M.TUTORIAL_SKIP_LABEL = {x = 122, y = 347, scale = 0.8, text = 81}
M.TUTORIAL_PAGE_HELP = 10

-- --- widgets ----------------------------------------------------------------------------

-- `x0`, `y0`: the widget's place in the box; `x`, `y`: where it is this frame (`build`).
local function button(name, style, icon, x, y, w, h, tip, anchor)
	return {name = name, kind = "button", style = style, icon = icon, x0 = x, y0 = y, x = x, y = y, w = w, h = h,
		tip = tip, anchor = anchor, visible = true}
end

local function rect(name, kind, r, tip, anchor)
	return {name = name, kind = kind, x0 = r.x, y0 = r.y, x = r.x, y = r.y, w = r.w, h = r.h, tip = tip, anchor = anchor, visible = true}
end

function M.build_widgets()
	local w = {}
	for type_id = 1, 5 do
		w[#w + 1] = button("tower" .. type_id, M.STYLE_BIG, type_id, M.TOWER_BUTTON_X[type_id], M.TOWER_BUTTON_Y, 64, 64, 20 + type_id, M.BOTTOM_LEFT)
	end
	w[#w + 1] = button("balloon", M.STYLE_BIG, 8, M.UPGRADE_SLOTS[3], M.TOWER_BUTTON_Y, 64, 64, 89, M.BOTTOM_LEFT)
	w[#w + 1] = button("upgrade", M.STYLE_BIG, 6, 664, M.TOWER_BUTTON_Y, 64, 64, 26, M.BOTTOM_RIGHT)
	w[#w + 1] = button("sell", M.STYLE_BIG, 7, 737, M.TOWER_BUTTON_Y, 64, 64, 29, M.BOTTOM_RIGHT)
	w[#w + 1] = button("menu", M.STYLE_SMALL2, 1, 278, -3, 32, 32, 67, M.TOP_CENTRE)
	w[#w + 1] = button("save", M.STYLE_SMALL2, 3, 310, -3, 32, 32, 65, M.TOP_CENTRE)
	w[#w + 1] = button("load", M.STYLE_SMALL2, 0, 450, -3, 32, 32, 66, M.TOP_CENTRE)
	w[#w + 1] = button("health", M.STYLE_SMALL1, 10, 483, -3, 32, 32, 79, M.TOP_CENTRE)
	w[#w + 1] = button("skills", M.STYLE_SMALL2, 2, 600, 480, 35, 35, 68, M.BOTTOM_CENTRE)
	w[#w + 1] = button("stop", M.STYLE_SMALL2, 12, 590, 520, 30, 30, 100, M.BOTTOM_CENTRE)
	w[#w + 1] = rect("slider", "slider", M.SLIDER, 31, M.BOTTOM_CENTRE)
	w[#w + 1] = rect("reset", "rect", M.RESET_MARK, nil, M.BOTTOM_CENTRE)
	for _, row in ipairs(M.SKILL_ROWS) do
		local plus = button("skill_plus_" .. row[1], M.STYLE_SMALL1, 1, M.SKILL_PLUS_X, row[2], M.SKILL_BUTTON, M.SKILL_BUTTON, nil)
		plus.skill, plus.downgrade, plus.row, plus.panel = row[1], false, row, true
		local minus = button("skill_minus_" .. row[1], M.STYLE_SMALL2, 11, M.SKILL_MINUS_X, row[2], M.SKILL_BUTTON, M.SKILL_BUTTON, nil)
		minus.skill, minus.downgrade, minus.row, minus.panel = row[1], true, row, true
		w[#w + 1] = plus
		w[#w + 1] = minus
	end
	-- The tutorial panel: "next" and the "skip this tutorial" checkbox.
	local next_page = button("tutorial_next", M.STYLE_SMALL1, 9, 665, 345, 32, 32, nil)
	next_page.tutorial = true
	w[#w + 1] = next_page
	local skip = rect("tutorial_skip", "checkbox", {x = 100, y = 345, w = 20, h = 20})
	skip.visible, skip.tutorial = false, true
	w[#w + 1] = skip
	local ok = button("skills_ok", M.STYLE_SMALL1, 2, 530, 405, 35, 35, nil)
	ok.panel = true
	local cancel = button("skills_cancel", M.STYLE_SMALL2, 4, 335, 402, 35, 35, nil)
	cancel.panel = true
	w[#w + 1] = ok
	w[#w + 1] = cancel
	return w
end

M.widgets = M.build_widgets()
M.by_name = {}
for _, w in ipairs(M.widgets) do
	M.by_name[w.name] = w
end

-- --- Wide-screen anchors -----------------------------------------------------------------

-- How far the groups anchored to the left, top, right and bottom move out of the box, in
-- box pixels (main/screen.lua `anchor_shifts`).
M.shifts = {l = 0, t = 0, r = 0, b = 0}

function M.set_anchor_shifts(l, t, r, b)
	local s = M.shifts
	s.l, s.t, s.r, s.b = l, t, r, b
end

-- The offset of a group at `anchor` (nil: the box).
function M.anchor_offset(anchor)
	if not anchor then
		return 0, 0
	end
	local s = M.shifts
	local ax, ay = anchor[1], anchor[2]
	return ax * (ax > 0 and s.r or s.l), ay * (ay > 0 and s.b or s.t)
end

-- Every widget's place this frame: its box place moved with its anchor.
function M.place_widgets()
	for _, w in ipairs(M.widgets) do
		local dx, dy = M.anchor_offset(w.anchor)
		w.x, w.y = w.x0 + dx, w.y0 + dy
	end
end

-- The interactive widget under box point (x, y), visibility as of the last `build`.
function M.widget_at(x, y)
	for i = #M.widgets, 1, -1 do
		local w = M.widgets[i]
		if w.visible and not w.inert and x >= w.x and x < w.x + w.w and y >= w.y and y < w.y + w.h then
			return w
		end
	end
	return nil
end

-- --- texts ------------------------------------------------------------------------------

local GOLD = "<colR=255><colG=203><colB=000>"
local WHITE = "<colR=255><colG=255><colB=255>"
local GREEN = "<colR=000><colG=200><colB=120>"

local function fmt_land(land)
	if land <= 0 or land >= 1 then
		return tostring(blitz.round_int(land))
	end
	return tostring(land):sub(1, 4)
end

-- `_ftowerinfo(type, level, showCost)`: `level < 0` = build tooltip (cost of level 0).
function M.tower_info(game, type_id, level, show_cost)
	local d = game.data
	local s = ""
	local full = true
	if show_cost then
		s = s .. string.format("\n%s%s:%d%s", GOLD, d:text(33), game.protos[type_id][level].price, WHITE)
	end
	if level < 0 then
		level = 0
		s = s .. string.format("\n%sCost:%d%s", GOLD, game.protos[type_id][0].price, WHITE)
		full = false
	end
	local p = game.protos[type_id][level]
	s = s .. string.format("\n%s%s[%d/%d]:%s", GREEN, d:text(1 + type_id), level, p.max_upgrades, WHITE)
	local land = p.land_damage
	if land > 0 then
		s = s .. string.format("\n%s - %s", d:text(7), fmt_land(land))
	end
	local air = p.air_damage
	if air > 0 then
		s = s .. string.format("\n%s - %d", d:text(8), blitz.round_int(air))
	end
	if full then
		s = s .. string.format("\n%s - %d", d:text(9), blitz.round_int(p.range))
	end
	if type_id ~= data.TOWER_FLAME then
		s = s .. string.format("\n%s - %d", d:text(10), math.floor((1000 - p.rate_of_fire_ms) / 10))
	end
	if full then
		local fz = p.freeze * game.skills.cold_magic
		if fz > 0 then
			s = s .. string.format("\n<colR=110><colG=200><colB=230>%s - %d%s", d:text(11), fz, WHITE)
		end
	end
	local fm = math.min(game.skills.fire_magic, 5)
	if p.fire * fm > 0 then
		s = s .. string.format("\n<colR=255><colG=110><colB=080>%s - %d%s", d:text(12), math.floor(blitz.round_int(fm * land * p.fire) / 10), WHITE)
	end
	if game.skills.fire_magic == 6 and type_id == data.TOWER_MAGIC then
		s = s .. string.format("\n<colR=255><colG=110><colB=080>%s - %d%s", d:text(12), blitz.round_int(air * 0.5), WHITE)
	end
	if p.poison_coof * game.skills.poison_magic > 0 then
		s = s .. string.format("\n<colR=000><colG=255><colB=000>%s - %d%s", d:text(49), math.floor(blitz.round_int(game.skills.poison_magic * p.poison_damage * p.poison_coof) / 10), WHITE)
	end
	return s
end

-- `_fcreatetip`: the tooltip of widget `w`, or "".
function M.tip_for(game, w)
	local d = game.data
	if w.skill then
		local id = w.skill
		local row = w.row
		local tip_color = "<colR=247><colG=232><colB=172>"
		if w.downgrade then
			return string.format("%s\n%s%s: %d %s", d:text(row[5]), tip_color, d:text(90), math.floor(game.skills:price_of(id) / 2), d:text(60))
		end
		if not game.skills:can_buy(id, 1000000) then
			return d:text(78)
		end
		if id == Skills.FIRE and game.skills.fire_magic == 5 then
			return string.format("%s\n%s%s: %d %s", d:text(87), tip_color, d:text(33), game.skills:price_of(Skills.FIRE6), d:text(60))
		end
		return string.format("%s\n%s%s: %d %s", d:text(row[4]), tip_color, d:text(33), game.skills:price_of(id), d:text(60))
	end
	local k = w.tip
	if not k then
		return ""
	end
	local name = w.name
	if name:sub(1, 5) == "tower" then
		return d:text(k) .. M.tower_info(game, tonumber(name:sub(6)), -1)
	elseif name == "upgrade" then
		local t = game.selected_tower
		if not t then
			return d:text(26) .. d:text(76)
		end
		if Game.tower_is_upgrading(t) then
			return ""
		end
		if t.level >= t.max_upgrades then
			return d:text(27)
		end
		return d:text(26) .. M.tower_info(game, t.type, t.level + 1, true)
	elseif name == "sell" then
		local t = game.selected_tower
		if not t then
			return d:text(28)
		end
		return string.format("%s\n<colR=255><colG=203><colB=000>%d %s", d:text(29), game:sell_value(t), d:text(30))
	elseif name == "health" then
		return d:text(game.show_units_life and 80 or 79)
	elseif name == "stop" then
		local t = game.selected_tower
		return d:text((t and t.stopped) and 101 or 100)
	end
	return d:text(k)
end

-- `_fshowenemyinfoondisplay`: every line opens with `<vd>`, so the text starts a line
-- below the time slider, as the tower's does; a life of 8+ digits loses the space after
-- its colon. Texts 72 / 73 are the whole "Type: ground" / "Type: air" line.
function M.enemy_info(game, e)
	local d = game.data
	local life = tostring(blitz.round_int(e.life))
	return string.format("\n%s:%s%s\n%s: %d\n%s: %d\n%s", d:text(69), #life < 8 and " " or "", life, d:text(70), e.armor,
		d:text(71), math.floor(e.speed * 100), d:text(e.air and 73 or 72))
end

-- `_ftowerinfo` / `_fshowenemyinfoondisplay` for the info panel.
function M.info_text(game)
	local t, e = game.selected_tower, game.selected_enemy
	if t then
		return M.tower_info(game, t.type, t.level)
	elseif e then
		return M.enemy_info(game, e)
	end
	return ""
end

-- --- snapshot ---------------------------------------------------------------------------

local function text(t, x, y, color, opts)
	opts = opts or {}
	local dx, dy = M.anchor_offset(opts.anchor)
	return {text = t, x = x + dx, y = y + dy, color = color, scale = opts.scale or 1, spacing = opts.spacing or 5,
		cx = opts.cx or false, cy = opts.cy or false, alpha = opts.alpha or 1}
end

-- The HUD snapshot of this frame. `ctx`: {skills_open, end_screen, menu_open, tutorial_page,
-- tutorial_skip, slider (0..100),
-- messages, popups, mouse, hover, pressed, help_enabled}.
function M.build(game, ctx)
	local d = game.data
	local ui = {}
	local skills = game.skills
	-- Buttons: visibility per game state. `_fupdateupgradebuttons`: Icerock, Flame and the
	-- balloon take the free slots from the left.
	local extra = {
		{M.by_name.tower4, skills.cold_magic > 0},
		{M.by_name.tower5, skills.fire_magic > 0},
		{M.by_name.balloon, game.balloon ~= nil and game.balloon.enabled},
	}
	local slot = 1
	for _, e in ipairs(extra) do
		local w = e[1]
		w.visible = e[2]
		if w.visible then
			w.x0 = M.UPGRADE_SLOTS[slot]
			slot = slot + 1
		end
	end
	local t = game.selected_tower
	M.by_name["stop"].visible = t ~= nil and t.freeze * skills.cold_magic > 0
	-- `_fhandlelevels`: the save / load buttons (sim/profile.lua has the rules).
	M.by_name["save"].visible = profile.can_quick_save(game, true)
	M.by_name["load"].visible = profile.can_quick_load(game, true)
	M.by_name["upgrade"].disabled = t ~= nil and Game.tower_is_upgrading(t)
	-- A modal sheet (the in-game menu, the end screen, else the skills window) leaves the
	-- panel drawn but inert: only its own widgets, and the skills button that closes the
	-- window, respond.
	local modal = ((ctx.menu_open or ctx.end_screen) and "end_screen") or (ctx.skills_open and "panel") or nil
	M.place_widgets()
	for _, w in ipairs(M.widgets) do
		w.inert = modal ~= nil and not w[modal] and not (modal == "panel" and w.name == "skills")
		if w.panel then
			w.visible = ctx.skills_open
		end
		if w.tutorial then
			w.visible = ctx.tutorial_page > 0
		end
		if w.skill then
			if w.downgrade then
				w.visible = ctx.skills_open and skills:can_downgrade(w.skill) and w.skill ~= Skills.DAMAGE
			end
			w.modulate = (w.skill == Skills.FIRE and not w.downgrade and skills.fire_magic == 5) and M.COLOR_FIRE6 or nil
		end
	end
	-- `_fshowtutorial`: the "skip" checkbox exists only on location 1 below the help page.
	local skip = M.by_name["tutorial_skip"]
	skip.visible = skip.visible and game.location == 1 and ctx.tutorial_page < M.TUTORIAL_PAGE_HELP
	skip.checked = ctx.tutorial_skip
	ui.widgets = M.widgets
	ui.hover = ctx.hover
	ui.pressed = ctx.pressed
	-- Texts.
	ui.texts = {
		gold = text(tostring(game.gold), 50, 9, M.COLOR_GOLD, {cx = true, cy = true, anchor = M.TOP_LEFT}),
		lifes = text(tostring(game.lifes), 760, 40, M.COLOR_LIFES, {cx = true, cy = true, anchor = M.TOP_RIGHT}),
		extra = text(game.extra_lifes > 0 and ("+" .. game.extra_lifes) or "", 765, 55, M.COLOR_EXTRA,
			{scale = 0.9, spacing = 4, anchor = M.TOP_RIGHT}),
		exp = text(tostring(game.experience), 15, 41, M.COLOR_EXP, {cx = true, cy = true, anchor = M.TOP_LEFT}),
		raid = text(game.survival_mode and string.format("%s: %d", d:text(48), game.curlevel)
			or string.format("%s: %d/%d", d:text(48), game:raid_index_in_location(), game:raids_in_location()), 330, 5, M.COLOR_WHITE,
			{anchor = M.TOP_CENTRE}),
		info = text(M.info_text(game), 400, 500, M.COLOR_WHITE, {anchor = M.BOTTOM_CENTRE}),
	}
	ui.slider = ctx.slider / 100
	local px, py = M.anchor_offset(M.BOTTOM_RIGHT)
	ui.progress_rect = {x = M.PROGRESS.x + px, y = M.PROGRESS.y + py, w = M.PROGRESS.w, h = M.PROGRESS.h}
	if ctx.tutorial_page > 0 then
		local t = M.TUTORIAL_TEXT
		ui.tutorial = text(d:tutorial_text(ctx.tutorial_page), t.x, t.y, M.COLOR_STORY, {spacing = t.spacing})
		ui.tutorial.page = ctx.tutorial_page
		if skip.visible then
			local l = M.TUTORIAL_SKIP_LABEL
			ui.tutorial_skip_label = text(d:text(l.text), l.x, l.y, M.COLOR_STORY, {scale = l.scale})
		end
	end
	ui.progress = (t and Game.tower_is_upgrading(t)) and (t.anim_time * 10) or 0
	ui.messages = ctx.messages
	ui.popups = ctx.popups
	-- Skills panel.
	ui.skills_open = ctx.skills_open
	if ctx.skills_open then
		local rows = {}
		for _, row in ipairs(M.SKILL_ROWS) do
			local level = skills:level_of(row[1])
			rows[#rows + 1] = text(tostring(level), M.SKILL_TEXT_X, row[3], M.COLOR_HELP, {scale = 0.8})
		end
		ui.skill_texts = rows
		ui.skills_exp = text(string.format("%s: %d", d:text(82), game.experience), 240, 62, M.COLOR_EXP_TITLE)
	end
	-- Tooltip and help for the hovered widget.
	ui.tooltip = nil
	ui.help = nil
	local hovered = ctx.hover and M.by_name[ctx.hover]
	if hovered and hovered.kind ~= "rect" and not ctx.pressed then
		if hovered.row and ctx.help_enabled then
			local help = d:help(hovered.row[6])
			local th = text_layout.line_count(help) * M.TIP_LINE
			ui.help = {text = text(help, M.HELP_X, M.HELP_Y, M.COLOR_HELP, {scale = 0.8, spacing = 7}),
				frame = {x = M.HELP_X, y = M.HELP_Y - M.TIP_MARGIN, w = M.HELP_WIDTH, h = th + 2 * M.TIP_MARGIN}}
		end
		local tip = M.tip_for(game, hovered)
		if tip ~= "" then
			local th = text_layout.line_count(tip) * M.TIP_LINE
			local mx, my = ctx.mouse.x, ctx.mouse.y
			local x = mx - 16 - math.max(0, 170 - (800 - mx))
			local y = my - th
			ui.tooltip = {text = text(tip, x, y, M.COLOR_WHITE, {scale = 0.8, spacing = 7}),
				frame = {x = x, y = y - M.TIP_MARGIN, w = M.TIP_WIDTH, h = th + 2 * M.TIP_MARGIN}}
		end
	end
	return ui
end

-- --- messages ---------------------------------------------------------------------------

-- The message and gold popup lists of the HUD, laid out here (the messages keep the
-- bottom-left corner): newest message at the bottom, older ones stacked above, a multi-line message takes a
-- slot per line; fading per tick.
function M.layout_messages(messages, ticks, now_ms)
	local dx, dy = M.anchor_offset(M.BOTTOM_LEFT)
	local y = M.MESSAGE_Y + dy
	for i = #messages, 1, -1 do
		local m = messages[i]
		if now_ms >= m.end_ms then
			m.alpha = m.alpha - M.MESSAGE_FADE * ticks
		end
		y = y - (m.lines - 1) * M.MESSAGE_STEP
		m.x, m.y = M.MESSAGE_X + dx, y
		if m.alpha <= 0 then
			table.remove(messages, i)
		end
		y = y - M.MESSAGE_STEP
	end
end

return M
