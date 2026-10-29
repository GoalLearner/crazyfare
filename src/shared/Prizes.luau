--!strict
-- What a prize is called (a drop's reveal, a level reward's notice and its chip in QUESTS), from Config.Drops.Names.

local Config = require(script.Parent.Config)

local Prizes = {}

function Prizes.Name(prize: Config.Prize): string
	local names = Config.Drops.Names
	local ref = prize.Ref or ""
	if prize.Kind == "Gems" then
		return string.format(names.Gems, tostring(prize.Amount or 0))
	elseif prize.Kind == "Paint" then
		return string.format(names.Paint, string.upper(ref))
	elseif prize.Kind == "Vehicle" then
		local stats = Config.Vehicles.Stats[ref]
		return string.format(names.Vehicle, string.upper(if stats then stats.DisplayName else ref))
	elseif prize.Kind == "Boost" then
		local item = Config.Items.Pool[ref]
		return string.format(names.Boost, string.upper(if item then item.DisplayName else ref))
	elseif prize.Kind == "Trail" then
		local def = Config.Cosmetics.Trails[ref]
		return string.format(names.Trail, if def then def.Name else ref)
	elseif prize.Kind == "Horn" then
		local def = Config.Cosmetics.Horns[ref]
		return string.format(names.Horn, if def then def.Name else ref)
	elseif prize.Kind == "Card" then
		local def = Config.Cosmetics.Cards[ref]
		return string.format(names.Card, if def then def.Name else ref)
	end
	return prize.Id
end

-- The same, short enough for a small tile: a start-with item is just the item's name.
function Prizes.Short(prize: Config.Prize): string
	if prize.Kind == "Boost" then
		local item = Config.Items.Pool[prize.Ref or ""]
		return string.upper(if item then item.DisplayName else prize.Ref or "")
	end
	return Prizes.Name(prize)
end

return Prizes
