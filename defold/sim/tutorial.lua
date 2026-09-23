-- The tutorial (`_fhandletutorial`, `_fnexttutorialpage`, `_ftutorialstep`,
-- `_fdisabletutorial`; docs/09): the page shown (Tutorial.txt line) and how gameplay
-- events move it on. Engine independent; `page` is what the HUD shows (0 = nothing), and
-- `events` collects `open_skills` requests for the screen. While the tutorial runs the raid
-- timer stands still (`tick`).
local M = {}
M.__index = M

M.PAGE_GOLD, M.PAGE_TOWERS, M.PAGE_HIDDEN_BUILD, M.PAGE_UPGRADE = 1, 2, 3, 4
M.PAGE_SELL, M.PAGE_SPEED, M.PAGE_MONSTERS, M.PAGE_SKILLS = 5, 6, 7, 8
M.PAGE_BALLOON, M.PAGE_HELP = 9, 10
M.LOCATION1_EXTRA_WAIT = -5.0
local BUILD_TASK_TEXT, MONSTERS_COMING_TEXT = 56, 54
local TASK_MS, COMING_MS = 2000, 3000
local MSG_WHITE = 1

function M.new(game)
	return setmetatable({game = game, state = 0, visible = false}, M)
end

-- The page on screen, 0 when hidden.
function M:page()
	return self.visible and self.state or 0
end

function M:running()
	return self.state > 0
end

function M:start(page)
	if page and page > 0 then
		self.state, self.visible = page, true
	end
end

local function show(self, page)
	self.state, self.visible = page, true
end

local function hide_for_build(self)
	self.state, self.visible = M.PAGE_HIDDEN_BUILD, false
end

-- `_fdisabletutorial`: leaving a campaign page (not Help) on location 1 warns that the
-- monsters come and gives 5 extra seconds before the first raid.
local function finish(self)
	local game = self.game
	local extra_wait = not game.survival_mode and self.state < M.PAGE_HELP and game.location == 1
	self.state, self.visible = 0, false
	if extra_wait then
		game.ingame_time = M.LOCATION1_EXTRA_WAIT
		game:message(game.data:text(MONSTERS_COMING_TEXT), MSG_WHITE, COMING_MS)
	end
end

-- "Next" (`_fnexttutorialpage`): pages 1-6 advance; leaving page 2 hides the sheet until a
-- tower is placed and states the task; page 8 opens the skills window.
function M:next()
	local s = self.state
	if s == M.PAGE_TOWERS then
		hide_for_build(self)
		self.game:message(self.game.data:text(BUILD_TASK_TEXT), MSG_WHITE, TASK_MS)
	elseif s == M.PAGE_GOLD or (s >= M.PAGE_HIDDEN_BUILD and s <= M.PAGE_SPEED) then
		show(self, s + 1)
	elseif s == M.PAGE_SKILLS then
		finish(self)
		return "open_skills"
	else
		finish(self)
	end
	return nil
end

-- `_ftutorialstep`: gameplay events.
function M:on_build_button()
	if self.state == M.PAGE_TOWERS then
		hide_for_build(self)
	end
end

function M:on_tower_placed()
	if self.state == M.PAGE_HIDDEN_BUILD then
		show(self, M.PAGE_UPGRADE)
	end
end

-- The upgrade button steps to page 5, hidden until the upgrade finishes.
function M:on_upgrade_pressed()
	if self.state == M.PAGE_UPGRADE then
		self.state, self.visible = M.PAGE_SELL, false
	end
end

function M:on_upgrade_finished()
	if self.state == M.PAGE_SELL and not self.visible then
		self.visible = true
	end
end

function M:on_sell()
	if self.state == M.PAGE_SELL and self.visible then
		show(self, M.PAGE_SPEED)
	end
end

-- The "skip this tutorial" checkbox.
function M:disable()
	if self.visible then
		finish(self)
	end
end

-- `_fhandletutorial`, before each game tick: the raid timer holds while it runs.
function M:tick()
	if self.state > 0 then
		self.game.ingame_time = 0
	end
end

return M
