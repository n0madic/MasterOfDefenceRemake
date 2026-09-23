-- The running session, shared by the screens (`script.shared_state`): the game tables, the
-- player's settings and the simulation of the current game. The screen controller
-- (main/controller.script) creates, replaces and saves the game; only the location screen
-- ticks it.
local data = require("sim.data")
local Game = require("sim.game")
local savegame = require("sim.savegame")
local profile = require("sim.profile")
local storage = require("main.storage")
local log = require("main.log")

local M = {}

M.SETTINGS = "settings"
M.HIGHSCORES = "highscores"

M.data = nil       -- sim.data tables, loaded once
M.settings = nil   -- sim.profile settings
M.game = nil       -- sim.game of the current game
M.notice = nil     -- {text, kind, duration_ms}: a message the next location screen shows
M.ending = nil     -- what the ending screen shows: {titles, score, survival}
M.tutorial_page = nil  -- the tutorial page the next location screen opens with

local function read(path)
	return assert(sys.load_resource(path), "missing " .. path)
end

function M.load()
	if not M.data then
		M.data = data.load(read, json.decode)
		M.settings = profile.with_defaults(storage.read(M.SETTINGS))
	end
end

function M.save_settings()
	storage.write(M.SETTINGS, M.settings)
end

local function new_sim()
	return Game.new(M.data, os.time())
end

-- A new campaign at difficulty `titul`, from `location` (1 unless debugging).
function M.new_campaign(titul, location)
	M.game = new_sim()
	M.game:start_campaign(titul, location)
	return M.game
end

-- A new survival game (`_finitsurvival`).
function M.new_survival()
	M.game = new_sim()
	M.game:start_survival()
	return M.game
end

-- Replace the game by save `name`; false when there is none (or it cannot be restored).
function M.load_game(name)
	local save = storage.read(name)
	if not savegame.is_valid(save) then
		if save then
			log.warn("session", "save %s is not compatible, ignored", name)
		end
		return false
	end
	local game = new_sim()
	local ok, err = pcall(savegame.restore, game, save)
	if not ok then
		log.error("session", "cannot restore %s: %s", name, tostring(err))
		return false
	end
	M.game = game
	return true
end

function M.save_game(name, save)
	storage.write(name, save or savegame.serialize(M.game))
end

-- Record a finished game's score in the local high score table.
function M.add_highscore(survival, score)
	local tables = storage.read(M.HIGHSCORES) or profile.new_highscores()
	profile.add_highscore(tables, survival, M.settings.PlayerName, score, os.date("%Y-%m-%d"))
	storage.write(M.HIGHSCORES, tables)
end

return M
