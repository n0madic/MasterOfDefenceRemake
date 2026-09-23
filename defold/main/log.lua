-- Leveled logging, the only place that prints. The level comes from the `main.log_level`
-- project setting (debug | info | warn | error; default info), e.g.
-- `--config=main.log_level=debug`.
local M = {}

local LEVELS = {debug = 1, info = 2, warn = 3, error = 4}
local NAMES = {"DEBUG", "INFO", "WARN", "ERROR"}

local threshold = LEVELS[sys.get_config_string("main.log_level", "info")] or LEVELS.info

local function emit(level, tag, fmt, ...)
	if level < threshold then
		return
	end
	local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
	print(string.format("%s [%s] %s", NAMES[level], tag, text))
end

function M.debug(tag, fmt, ...) emit(1, tag, fmt, ...) end
function M.info(tag, fmt, ...) emit(2, tag, fmt, ...) end
function M.warn(tag, fmt, ...) emit(3, tag, fmt, ...) end
function M.error(tag, fmt, ...) emit(4, tag, fmt, ...) end

return M
