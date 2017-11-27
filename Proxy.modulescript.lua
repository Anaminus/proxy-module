--[[
Proxy

	Wraps a function environment to create a bridge between the user and the
	global environment.

		User <--> Proxy <--> API

	Proxy can report APIs that are accessed, spoof APIs, or deny access
	entirely.

]]

local function pack(...)
	return {n = select("#", ...), ...}
end

local function pindex(t, k)
	return t[k]
end

local function pnewindex(t, k, v)
	t[k] = v
end

local function printtable(t, ref)
	ref = ref or {n=0}
	ref.n = ref.n + 1
	ref[t] = ref.n
	local s = {"{ref(",ref.n,"); "}
	local first = true
	local count = 0
	for k,v in pairs(t) do
		if first then
			first = false
		else
			s[#s+1] = ", "
		end
		count = count + 1
		if count >= 20 then
			local n = 0
			for k,v in pairs(t) do
				n = n + 1
			end
			s[#s+1] = "("
			s[#s+1] = n - count
			s[#s+1] = " more items...)"
			break
		end
		s[#s+1] = "["
		if type(k) == "table" then
			if not ref[k] then
				s[#s+1] = printtable(k, ref)
			end
		elseif type(k) == "string" then
			s[#s+1] = string.format("%q", tostring(k)):gsub("\\\n", "\\n")
		else
			s[#s+1] = tostring(k)
		end
		s[#s+1] = "] = "
		if type(v) == "table" then
			if not ref[v] then
				s[#s+1] = printtable(v, ref)
			end
		elseif type(v) == "string" then
			s[#s+1] = string.format("%q", tostring(v)):gsub("\\\n", "\\n")
		else
			s[#s+1] = tostring(v)
		end
	end
	s[#s+1] = "}"
	return table.concat(s)
end

local function newProxy(mt)
	local proxy = newproxy(true)
	local mtp = getmetatable(proxy)
	for k, v in pairs(mt) do
		mtp[k] = v
	end
	return proxy
end

local WeakTable do
	local wt = {
		k  = {__mode = "k"},
		v  = {__mode = "v"},
		kv = {__mode = "kv"},
	}
	function WeakTable(mode)
		return setmetatable({}, wt[mode])
	end
end

local SuppressReporting = true
local Report do
	local replicator = Instance.new("RemoteEvent")
	replicator.Name = "ReportReplicator"
	replicator.Parent = game.ReplicatedStorage
	local conns = {}
	local ready = 0

	local function IsOwner(id)
		if id == game.CreatorId then
			-- Does this work?
			return true
		end
		if game:GetService("RunService"):IsStudio() and id < 0 then
			return true
		end
	end

	game.Players.PlayerAdded:Connect(function(player)
		if not IsOwner(player.UserId) then
			return
		end
		conns[player] = replicator.OnServerEvent:Connect(function(peer, data)
			if peer == player and data == "ready" then
				conns[player]:Disconnect()
				ready = ready + 1
			end
		end)
	end)

	game.Players.PlayerRemoving:Connect(function(player)
		if not conns[player] then
			return
		end
		if conns[player].Connected then
			conns[player]:Disconnect()
		else
			ready = ready - 1
		end
		conns[player] = nil
	end)

	local Freq = 1
	local ChunkSizeKbps = 40
	local ChunkSize = math.floor(ChunkSizeKbps*1000/8)/Freq

	local buffer = {}
	local function FlushReports()
		if ready <= 0 or #buffer == 0 then
			return
		end
		local data = table.concat(buffer, "\n")
		buffer = {}
		local i = 1
		while i <= #data do
			for player in pairs(conns) do
				replicator:FireClient(player, data:sub(i, i+ChunkSize-1))
			end
			i = i + ChunkSize
			wait()
		end
	end

	spawn(function()
		while true do
			FlushReports()
			wait(Freq)
		end
	end)

	function Report(...)
		if SuppressReporting then
			return
		end
		local data = {}
		local nargs = select("#", ...)
		local args = {...}
		for i = 1, nargs do
			local arg = args[i]
			if type(arg) == "table" then
				arg = printtable(arg)
			else
				arg = string.format("%q", tostring(arg)):gsub("\\\n", "\\n")
			end
			data[#data+1] = arg
		end
		buffer[#buffer+1] = table.concat(data, " | ")
	end
end


--------------------------------
--------------------------------

local Hooks = {}
-- Get a spoofed value from a value.
local HookLookup = {}

local function HookTable()
	local data = WeakTable("kv")
	return setmetatable({}, {
		__index = data,
		__newindex = function(self, wrapper, value)
			local hook = Hooks[value]
			if hook then
				local access = hook.access
				if access == false then
					error(string.format("cannot access %s", hook.name), 2)
				elseif type(access) == "function" then
					local ok, result = access(wrapper, value)
					if not ok then
						error(string.format("cannot access %s", hook.name), 2)
					end
					HookLookup[value] = result
				end
				if hook.report ~= false then
					Report("hook.access", hook.name)
				end
			end
			data[wrapper] = value
		end,
	})
end

--------------------------------
--------------------------------

local mtWrapper

-- Lookup a wrapper from a value.
local WrapperLookup = WeakTable("k")
-- Lookup a value from a wrapper.
local ValueLookup = HookTable()
-- Registers a function as a non-user-defined function.
local RegisteredFuncs = {}

local function IsCFunction(func)
	return not pcall(string.dump, func)
end

-- Is it a function created by the user (not registered, not a wrapper created
-- by this module, not a C function).
local function IsUserFunction(func)
	return not (
		RegisteredFuncs[func] or
		ValueLookup[func] or
		IsCFunction(func)
	)
end

local function RegisterWrapper(value, wrapper, level)
	level = level or 2
	WrapperLookup[value] = wrapper
	local ok, err = pcall(pnewindex, ValueLookup, wrapper, value)
	if not ok then
		error(err:match("^.*:%d+: (.*)$"), level+1)
	end
end

local function GetWrapper(value, mt, level)
	level = level or 2
	local wrapper = WrapperLookup[value]
	if wrapper == nil then
		wrapper = newProxy(mt)
		RegisterWrapper(value, wrapper, level+1)
	end
	return wrapper
end

local WrapArgs, UnwrapArgs
local WrapUFunction, WrapNFunction
local WrapValue, UnwrapValue

function UnwrapArgs(...)
	local n = select("#", ...)
	local args = {...}
	for i = 1, n do
		args[i] = UnwrapValue(args[i], 3)
	end
	return unpack(args, 1, n)
end

function WrapArgs(...)
	local n = select("#", ...)
	local args = {...}
	for i = 1, n do
		args[i] = WrapValue(args[i], 3)
	end
	return unpack(args, 1, n)
end

-- Wraps a user-defined function to a UFunc, which can be safely called by
-- APIs.
function WrapUFunction(func, level)
	level = level or 2
	local wrapper; wrapper = function(...)
		local func = ValueLookup[wrapper]
		local hfunc = HookLookup[func] or func
		local results = pack(pcall(hfunc, WrapArgs(...)))
		if not results[1] then
			error(results[2], 2)
		end
		return UnwrapArgs(unpack(results, 2, results.n))
	end
	RegisterWrapper(func, wrapper, level+1)
	return wrapper
end

-- Wraps a non-user-defined function to an NFunc, which can be safely called
-- by the user.
function WrapNFunction(func, level)
	level = level or 2
	local wrapper; wrapper = function(...)
		local args = pack(UnwrapArgs(...))
		local func = ValueLookup[wrapper]
		local hfunc = HookLookup[func] or func
		local results = pack(pcall(hfunc, unpack(args, 1, args.n)))
		local hook = Hooks[func]
		if hook and hook.report ~= false then
			Report("hook.call", hook.name, args, results)
		end
		if not results[1] then
			error(results[2], 2)
		end
		return WrapArgs(unpack(results, 2, results.n))
	end
	RegisterWrapper(func, wrapper, level+1)
	return wrapper
end

-- Make a value safe for the user.
function WrapValue(value, level)
	level = level or 2
	if type(value) == "userdata" then
		return GetWrapper(value, mtWrapper, level+1)
	elseif type(value) == "table" then
		local wrapper = {}
		for k, v in pairs(value) do
			wrapper[WrapValue(k, level+1)] = WrapValue(v, level+1)
		end
		return wrapper
	elseif type(value) == "function" then
		local func = ValueLookup[value]
		if func then
			-- Argument is a UFunc wrapper, return its value.
			return func
		end
		if not IsUserFunction(value) then
			return WrapNFunction(value, level+1)
		end
		-- TODO
	end
	return value
end

-- Make a value safe for the API.
function UnwrapValue(wrapper, level)
	level = level or 2
	if type(wrapper) == "table" then
		local value = {}
		for k, v in pairs(wrapper) do
			value[UnwrapValue(k, level+1)] = UnwrapValue(v, level+1)
		end
		return value
	elseif type(wrapper) == "function" then
		local value = ValueLookup[wrapper]
		if value then
			-- Argument is an NFunc wrapper, return its value.
			return value
		end
		if IsUserFunction(wrapper) then
			return WrapUFunction(wrapper, level+1)
		end
		-- TODO
		return value
	end
	local value = ValueLookup[wrapper]
	return value ~= nil and value or wrapper
end

mtWrapper = {
	__index = function(self, k)
		self = UnwrapValue(self, 2)
		k = UnwrapValue(k, 2)
		Report("__index", self, k)
		self = HookLookup[self] or self
		local ok, result = pcall(pindex, self, k)
		if not ok then
			error(result, 2)
		end
		return WrapValue(result, 2)
	end,
	__newindex = function(self, k, v)
		self = UnwrapValue(self, 2)
		k = UnwrapValue(k, 2)
		v = UnwrapValue(v, 2)
		Report("__newindex", self, k, v)
		self = HookLookup[self] or self
		local ok, result = pcall(pnewindex, self, k, v)
		if not ok then
			error(result, 2)
		end
	end,
	__eq = function(a, b)
		a = UnwrapValue(a, 2)
		b = UnwrapValue(b, 2)
		Report("__eq", a, b)
		return a == b
	end,
	__tostring = function(self)
		return tostring(UnwrapValue(self, 2))
	end,
	__metatable = "The metatable is locked",
}

--------------------------------
--------------------------------

--[[

Hooks[value] = {
	name   = string,
	report = bool
	access = bool | function
}

Run a hook when `value` is accessed. `name` is an identifier to use for
reporting. `report`, when false, disables reporting. If `access` is false, an
error is thrown when attempting to access the value. If `access` is a
function, it must return a bool and a value. The bool determines whether the
value can be accessed. If true, then the returned value will replace the
original value when accessed.

]]

-- Deny access to sensitive APIs.
Hooks[game:GetService("HttpService").GetAsync] = {
	name = "HttpService.GetAsync",
	access = false,
}
Hooks[game:GetService("HttpService").PostAsync] = {
	name = "HttpService.PostAsync",
	access = false,
}
Hooks[game:GetService("TeleportService")] = {
	name = "TeleportService",
	access = false,
}
Hooks[game:GetService("AssetService")] = {
	name = "AssetService",
	access = false,
}
-- Replace require so that it does nothing but report its arguments.
Hooks[require] = {
	name = "require",
	access = function(wrapper, value)
		return true, function(...)
			Report("require", UnwrapArgs(...))
			return function(...)
				Report("require.func", UnwrapArgs(...))
			end
		end
	end,
}
-- Report accesses to HttpService.
Hooks[game:GetService("HttpService")] = {name = "HttpService"}
-- Spoof results of a specific call to GetProductInfo.
Hooks[game:GetService("MarketplaceService").GetProductInfo] = {
	name = "MarketplaceService.GetProductInfo",
	access = function(wrapper, value)
		return true, function(MarketplaceService, assetId, infoType)
			if assetId == 1194188859 then
				return {Description = "{\"followId\": \"jhylxbnmks\"}"}
			end
			return MarketplaceService:GetProductInfo(assetId, infoType)
		end
	end,
}

-- Global environment cannot be enumerated; must be done manually.
local environment = {
	-- These can probably just be wrapped.
	type = function(...)
		if select("#", ...) == 0 then
			error("bad argument #1 to 'type' (value expected)", 2)
		end
		return type(UnwrapValue((...)))
	end,
	typeof = function(...)
		if select("#", ...) == 0 then
			error("bad argument #1 to 'type' (value expected)", 2)
		end
		return typeof(UnwrapValue((...)))
	end,
	_G                     = _G,
	_VERSION               = _VERSION,
	assert                 = assert,
	collectgarbage         = collectgarbage,
	error                  = error,
	getfenv                = WrapNFunction(getfenv),
	getmetatable           = getmetatable,
	ipairs                 = ipairs,
	loadstring             = function()end,
	next                   = next,
	pairs                  = pairs,
	pcall                  = pcall,
	print                  = print,
	rawequal               = WrapNFunction(rawequal),
	rawget                 = rawget,
	rawset                 = rawset,
	select                 = select,
	setfenv                = WrapNFunction(setfenv),
	setmetatable           = setmetatable,
	tonumber               = tonumber,
	tostring               = tostring,
	unpack                 = unpack,
	xpcall                 = xpcall,
	coroutine              = coroutine,
	math                   = math,
	string                 = string, -- dump?
	table                  = table,
	Enum                   = Enum,
	UserSettings           = WrapNFunction(UserSettings),
	delay                  = delay,
	elapsedTime            = elapsedTime,
	game                   = WrapValue(game),
	gcinfo                 = gcinfo,
	newproxy               = newproxy,
	require                = WrapNFunction(require),
	shared                 = shared,
	spawn                  = spawn,
	tick                   = tick,
	time                   = time,
	wait                   = wait,
	warn                   = warn,
	workspace              = WrapValue(workspace),
	ypcall                 = ypcall,
	os                     = os,
	debug                  = debug, -- maybe?
	utf8                   = utf8,
	Axes                   = Axes,
	BrickColor             = BrickColor,
	CFrame                 = CFrame,
	CellId                 = CellId, --?
	ColorSequence          = WrapValue(ColorSequence),
	ColorSequenceKeypoint  = WrapValue(ColorSequenceKeypoint),
	Faces                  = Faces,
	Instance               = WrapValue(Instance),
	NumberRange            = NumberRange,
	NumberSequence         = WrapValue(NumberSequence),
	NumberSequenceKeypoint = WrapValue(NumberSequenceKeypoint),
	PhysicalProperties     = PhysicalProperties,
	Ray                    = Ray,
	Rect                   = Rect,
	Region3                = Region3,
	Region3int16           = Region3int16,
	TweenInfo              = WrapValue(TweenInfo),
	UDim                   = UDim,
	UDim2                  = UDim2,
	Vector2                = Vector2,
	Vector2int16           = Vector2int16,
	Vector3                = Vector3,
	Vector3int16           = Vector3int16,
--#SuppressAnalysis
--	DebuggerManager        = WrapNFunction(DebuggerManager),
	Delay                  = Delay,
	ElapsedTime            = ElapsedTime,
	Game                   = WrapValue(Game),
	LoadLibrary            = WrapNFunction(LoadLibrary),
	PluginManager          = WrapNFunction(PluginManager),
	Spawn                  = Spawn,
	Stats                  = WrapNFunction(Stats),
	Version                = Version,
	Wait                   = Wait,
	Workspace              = WrapValue(Workspace),
	printidentity          = printidentity,
	settings               = WrapNFunction(settings),
	stats                  = WrapNFunction(stats),
	version                = version,
	dofile                 = dofile,
	load                   = load,
	loadfile               = loadfile,
--#/SuppressAnalysis
}

SuppressReporting = false

return function(f)
	-- Main env; protected like regular env.
	local e = setmetatable({script = getfenv(f).script}, {
		__index = environment,
		__metatable = "The metatable is locked",
	})
	-- Proxy env; reports access.
	local p = setmetatable({}, {
		__index = function(t, k)
			Report("getglobal", k)
			return e[k]
		end,
		__newindex = function(t, k, v)
			Report("setglobal", k, v)
			e[k] = v
		end,
		__metatable = "The metatable is locked",
	})
	setfenv(f, p)
	return f
end
