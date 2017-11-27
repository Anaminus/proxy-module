--[[
Dummy

	Replaces a function environment with a Dummy object. Accessing the dummy
	object reports the access, and returns more Dummy objects. Since a Dummy
	can stand in for tables, functions, and userdata, this can be used to
	explore the content of unknown functions.

]]

local NewDummy
local depth = setmetatable({}, {__mode = "k"})
local ref = setmetatable({}, {__mode = "k"})
local nref = 0

local CallReturns = 2
local HookDummy = {}

--[[
{
	number of arguments (<0 for any),
	arguments to match (HookDummy matches a Dummy object),
	...,
	function of values returned instead of Dummy objects,
}
]]
local Hooks = {
	-- Match __index of RunService.IsStudio, replace with function that
	-- returns false.
	{2, HookDummy, "IsStudio", function(...)
		return function() return false end
	end},
}

local function pack(...)
	return {n=select("#", ...), ...}
end

local replicator = Instance.new("RemoteEvent")
replicator.Name = "ReportReplicator"
replicator.Parent = game.ReplicatedStorage
local ready = false
do
	local conn; conn = replicator.OnServerEvent:Connect(function(...)
		ready = true
		conn:Disconnect()
	end)
end

local Freq = 1
local ChunkSize = 1000
local buffer = {}
local function Flush()
	if not ready then
		return
	end
	if #buffer == 0 then
		return
	end
	local data = table.concat(buffer, "\n")
	buffer = {}
	local i = 1
	while i <= #data do
		replicator:FireAllClients(data:sub(i, i+ChunkSize-1))
		i = i + ChunkSize
	end
end

local function SendReport(data)
	buffer[#buffer+1] = data
end

spawn(function()
	while true do
		Flush()
		wait(Freq)
	end
end)

local function report(method, r, n, ...)
	local nargs = select("#", ...)
	local args = {...}
	local data = {"REPORT", string.format("%-11s", method), "ARGUMENTS", nargs}
	for i = 1, nargs do
		local arg = args[i]
		if ref[arg] then
			data[#data+1] = string.format("dummy(%04x:%02d)", ref[arg], depth[arg])
		else
			data[#data+1] = string.format("%q", tostring(arg)):gsub("\\\n", "\\n")
		end
	end

	local ret
	for _, hook in pairs(Hooks) do
		if nargs == hook[1] or hook[1] < 0 then
			local ok = true
			for i = 1, #hook-2 do
				if args[i] ~= hook[i+1] then
					if ref[args[i]] and hook[i+1] == HookDummy then
					else
						ok = false
						break
					end
				end
			end
			if ok then
				ret = pack(hook[#hook](...))
			end
		end
	end
	if not ret then
		ret = {n=r}
		for i = 1, r do
			ret[i] = NewDummy(n)
		end
	end
	if ret.n > 0 then
		data[#data+1] = "RETURNS"
		data[#data+1] = ret.n
		for i = 1, ret.n do
			local arg = ret[i]
			if ref[arg] then
				data[#data+1] = string.format("dummy(%04x:%02d)", ref[arg], depth[arg])
			else
				data[#data+1] = string.format("%q", tostring(arg)):gsub("\\\n", "\\n")
			end
		end
	end
	SendReport(table.concat(data, " | "))
	return unpack(ret, 1, ret.n)
end

local mtDummy = {}
mtDummy.__add = function(...)
	report("__add", 0, nil, ...)
	return 43
end
mtDummy.__sub = function(...)
	report("__sub", 0, nil, ...)
	return 45
end
mtDummy.__mul = function(...)
	report("__mul", 0, nil, ...)
	return 42
end
mtDummy.__div = function(...)
	report("__div", 0, nil, ...)
	return 47
end
mtDummy.__mod = function(...)
	report("__mod", 0, nil, ...)
	return 37
end
mtDummy.__pow = function(...)
	report("__pow", 0, nil, ...)
	return 94
end
mtDummy.__unm = function(...)
	report("__unm", 0, nil, ...)
	return -45
end
mtDummy.__concat = function(...)
	report("__concat", 0, nil, ...)
	return "concat"
end
mtDummy.__len = function(...)
	report("__len", 0, nil, ...)
	return 35
end
mtDummy.__eq = function(...)
	report("__eq", 0, nil, ...)
	return false
end
mtDummy.__lt = function(...)
	report("__lt", 0, nil, ...)
	return false
end
mtDummy.__le = function(...)
	report("__le", 0, nil, ...)
	return false
end
mtDummy.__index = function(...)
	return report("__index", CallReturns, depth[(...)],  ...)
end
mtDummy.__newindex = function(...)
	report("__newindex", 0, nil, ...)
end
mtDummy.__call = function(...)
	return report("__call", CallReturns, depth[(...)],  ...)
end
-- mtDummy.__namecall = function(...)
-- 	return report("__namecall", CallReturns, depth[(...)],  ...)
-- end
mtDummy.__metatable = "The metatable is locked"
mtDummy.__tostring = function(...)
	report("__tostring", ...)
	return "Instance"
end

function NewDummy(n, t)
	local dummy
	if t then
		dummy = setmetatable(t, mtDummy)
	else
		dummy = newproxy(true)
		local mt = getmetatable(dummy)
		for k, v in pairs(mtDummy) do
			mt[k] = v
		end
	end
	nref = nref + 1
	ref[dummy] = nref
	depth[dummy] = (n or 0) + 1
	return dummy
end

return function(f)
	setfenv(f, NewDummy(nil, {}))
	return f
end
