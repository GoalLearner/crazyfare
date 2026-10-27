--!strict
-- Who is racing: the real Players plus the AI rival taxis (BotService). A bot is a plain table standing in for a Player
-- wherever services key their state by driver (cars, fares, passengers, items, standings). It carries the few Player
-- fields those services read (UserId below 0, Name, DisplayName, Parent) and GetAttribute / SetAttribute, but it is
-- never a real Instance: anything that talks to a client (FireClient) or to saved data must skip it (Racers.IsBot).

local Players = game:GetService("Players")

local Racers = {}

local bots: { Player } = {}

function Racers.IsBot(driver: Player): boolean
	return typeof(driver) ~= "Instance"
end

-- Every driver in the race: real players first, then bots.
function Racers.All(): { Player }
	local list = Players:GetPlayers()
	for _, bot in bots do
		table.insert(list, bot)
	end
	return list
end

function Racers.Bots(): { Player }
	return table.clone(bots)
end

-- A new stand-in driver. `slot` (1, 2, 3...) gives it UserId -slot, so ids stay unique and never collide with a player.
function Racers.NewBot(slot: number, name: string): Player
	local attributes: { [string]: any } = {}
	local bot = {
		UserId = -slot,
		Name = "Bot_" .. name,
		DisplayName = name,
		Parent = Players, -- reads as "still here" wherever a service checks player.Parent
		IsBot = true,
		GetAttribute = function(_self: any, key: string): any
			return attributes[key]
		end,
		SetAttribute = function(_self: any, key: string, value: any)
			attributes[key] = value
		end,
	}
	local driver = (bot :: any) :: Player
	table.insert(bots, driver)
	return driver
end

function Racers.RemoveBot(bot: Player)
	local index = table.find(bots, bot)
	if index then
		table.remove(bots, index)
	end
	;(bot :: any).Parent = nil
end

return Racers
