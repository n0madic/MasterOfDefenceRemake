-- Minimal JSON decoder for the headless tests (the engine has `json.decode`).
local M = {}

local function skip(s, i)
	local _, j = s:find("^[ \n\r\t]*", i)
	return j + 1
end

local decode_value

local function decode_string(s, i)
	local out = {}
	i = i + 1
	while true do
		local c = s:sub(i, i)
		if c == '"' then
			return table.concat(out), i + 1
		elseif c == "\\" then
			local n = s:sub(i + 1, i + 1)
			local map = {n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/"}
			if n == "u" then
				local code = tonumber(s:sub(i + 2, i + 5), 16)
				out[#out + 1] = utf8 and utf8.char(code) or string.char(code % 256)
				i = i + 6
			else
				out[#out + 1] = map[n] or n
				i = i + 2
			end
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
end

decode_value = function(s, i)
	i = skip(s, i)
	local c = s:sub(i, i)
	if c == "{" then
		local obj = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "}" then
			return obj, i + 1
		end
		while true do
			local key
			key, i = decode_string(s, skip(s, i))
			i = skip(s, i)
			assert(s:sub(i, i) == ":", "expected ':' at " .. i)
			local value
			value, i = decode_value(s, i + 1)
			obj[key] = value
			i = skip(s, i)
			local d = s:sub(i, i)
			if d == "}" then
				return obj, i + 1
			end
			assert(d == ",", "expected ',' at " .. i)
			i = i + 1
		end
	elseif c == "[" then
		local arr = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "]" then
			return arr, i + 1
		end
		while true do
			local value
			value, i = decode_value(s, i)
			arr[#arr + 1] = value
			i = skip(s, i)
			local d = s:sub(i, i)
			if d == "]" then
				return arr, i + 1
			end
			assert(d == ",", "expected ',' at " .. i)
			i = i + 1
		end
	elseif c == '"' then
		return decode_string(s, i)
	elseif s:sub(i, i + 3) == "true" then
		return true, i + 4
	elseif s:sub(i, i + 4) == "false" then
		return false, i + 5
	elseif s:sub(i, i + 3) == "null" then
		return nil, i + 4
	else
		local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
		assert(num and #num > 0, "bad JSON at " .. i)
		return tonumber(num), i + #num
	end
end

function M.decode(s)
	return (decode_value(s, 1))
end

return M
