--!strict
-- The daily rotating shop (Config.DailyShop): which cosmetics are for sale today and what they cost. The server and
-- every client work out the same list from the UTC day (seeded by it), so nothing has to be sent.

local Config = require(script.Parent.Config)

local DailyShop = {}

local cfg = Config.DailyShop
local DAY = 86400

-- Everything that can rotate in: the drop pool's trails and horns, and its drop-only paints, at a priced rarity.
local candidates: { Config.Prize } = {}
for _, entry in Config.Drops.Pool do
	if cfg.Prices[entry.Rarity] == nil then
		continue
	end
	local sellable = entry.Kind == "Trail" or entry.Kind == "Horn"
	if entry.Kind == "Paint" then
		for _, paint in Config.Paint.Colors do
			if paint.Name == entry.Ref and paint.DropOnly then
				sellable = true
			end
		end
	end
	if sellable then
		table.insert(candidates, entry)
	end
end

local function kindIndex(kind: string): number
	return table.find(cfg.KindOrder, kind) or #cfg.KindOrder + 1
end

function DailyShop.Day(serverTime: number): number
	return serverTime // DAY
end

function DailyShop.SecondsLeft(serverTime: number): number
	return (DailyShop.Day(serverTime) + 1) * DAY - serverTime
end

-- The day's items: a seeded shuffle, the first of each kind, then the rest of the shuffle up to Count; shown by kind.
function DailyShop.Items(day: number): { Config.Prize }
	local rng = Random.new(day)
	local shuffled = table.clone(candidates)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local picked: { Config.Prize } = {}
	local used: { [number]: boolean } = {}
	for _, kind in cfg.KindOrder do
		for i, item in shuffled do
			if not used[i] and item.Kind == kind and #picked < cfg.Count then
				used[i] = true
				table.insert(picked, item)
				break
			end
		end
	end
	for i, item in shuffled do
		if #picked >= cfg.Count then
			break
		end
		if not used[i] then
			used[i] = true
			table.insert(picked, item)
		end
	end
	table.sort(picked, function(a, b)
		local ka, kb = kindIndex(a.Kind), kindIndex(b.Kind)
		if ka ~= kb then
			return ka < kb
		end
		return a.Id < b.Id
	end)
	return picked
end

-- Today's item with this id, or nil (not for sale today).
function DailyShop.Find(day: number, id: string): Config.Prize?
	for _, item in DailyShop.Items(day) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

function DailyShop.Price(item: Config.Prize): number
	return cfg.Prices[item.Rarity] or 0
end

return DailyShop
