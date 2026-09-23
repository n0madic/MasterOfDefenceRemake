-- Debug / launch options: `--config=main.<name>=<value>` on the desktop engine, or the
-- query parameter `?<name>=<value>` on the web (the bundle has no command line).
local M = {}

local function query(name)
	if not html5 then
		return nil
	end
	return html5.run(string.format("(new URLSearchParams(window.location.search)).get(%q) || ''", name))
end

function M.get_int(name, default)
	local value = sys.get_config_int("main." .. name, 0)
	if value ~= 0 then
		return value
	end
	return tonumber(query(name) or "") or default
end

function M.get_string(name, default)
	local value = sys.get_config_string("main." .. name, "")
	if value ~= "" then
		return value
	end
	local q = query(name)
	if q and q ~= "" then
		return q
	end
	return default
end

function M.get_flag(name)
	return M.get_int(name, 0) ~= 0
end

return M
