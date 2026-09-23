-- Persistent tables (saves, settings, high scores) in the platform's save directory
-- (sys.get_save_file: the user's application data on desktop and mobile, IndexedDB on the
-- web). A missing or unreadable file reads as nil; a failed write is logged and the game
-- goes on.
local log = require("main.log")

local M = {}

local APP = "MasterOfDefense"

local function path(name)
	return sys.get_save_file(APP, name)
end

-- The table stored under `name`, or nil.
function M.read(name)
	local ok, t = pcall(sys.load, path(name))
	if not ok then
		log.warn("storage", "cannot read %s: %s", name, tostring(t))
		return nil
	end
	if type(t) ~= "table" or next(t) == nil then
		return nil
	end
	return t
end

function M.write(name, t)
	local ok, err = pcall(sys.save, path(name), t)
	if not ok or not err then
		log.error("storage", "cannot write %s: %s", name, tostring(err))
		return false
	end
	return true
end

function M.exists(name)
	return M.read(name) ~= nil
end

-- Remove `name` (an empty table reads as missing, which also works where files cannot be
-- deleted, e.g. the web's IndexedDB store).
function M.delete(name)
	M.write(name, {})
end

return M
