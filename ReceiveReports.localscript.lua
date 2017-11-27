--[[

Receive reports, print them so that they will fit in log files (logged
messages are truncated). Include random ID to signal the start of a message
chunk.

]]
local printMessageLength = 1024
local stampLength = #("0000.00000 0000: ")
local UniqueID = "00000000"
do
	math.randomseed(tick())
	math.random(); math.random(); math.random()
	local c = {}
	for i = 0, 255 do
		if string.char(i):match("^[0-9A-Za-z]$") then
			c[#c+1] = string.char(i)
		end
	end
	c = table.concat(c)
	local n = #UniqueID
	UniqueID = ""
	for i = 1, n do
		local r = math.random(#c)
		UniqueID = UniqueID .. c:sub(r, r)
	end
end
local ChunkSize = printMessageLength - stampLength - #UniqueID

print("UNIQUEID:" .. UniqueID)

local replicator = game.ReplicatedStorage:WaitForChild("ReportReplicator")

replicator.OnClientEvent:Connect(function(data)
	local i = 1
	while i <= #data do
		print(UniqueID .. data:sub(i, i+ChunkSize-1))
		i = i + ChunkSize
	end
end)

replicator:FireServer("ready")
