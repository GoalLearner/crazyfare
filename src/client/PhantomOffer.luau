--!strict
-- The Phantom's Robux offer window (Config.Monetization.PhantomOffer, unix seconds UTC, checked against server time)
-- and the owner count (a workspace attribute LeaderboardService keeps), as the Garage and the shop's CARS tab show
-- them. Outside the window it can't be bought: MYTHIC DROP ONLY.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PhantomOffer = {}

local P = Config.Vehicles.Phantom

-- Seconds until the offer ends (0 = no offer running).
function PhantomOffer.SecondsLeft(): number
	local w = Config.Monetization.PhantomOffer
	local now = workspace:GetServerTimeNow()
	if w.EndUtc <= 0 or now < w.StartUtc or now >= w.EndUtc then
		return 0
	end
	return w.EndUtc - now
end

-- "R$ OFFER: 2D 4H LEFT", or MYTHIC DROP ONLY outside the window.
function PhantomOffer.StatusText(): string
	local left = math.floor(PhantomOffer.SecondsLeft())
	if left <= 0 then
		return P.DropOnlyLine
	end
	local text = if left >= 86400
		then string.format("%dD %dH", left // 86400, left % 86400 // 3600)
		elseif left >= 3600 then string.format("%dH %dM", left // 3600, left % 3600 // 60)
		else string.format("%dM", math.max(1, left // 60))
	return string.format(P.OfferLine, text)
end

function PhantomOffer.OwnersText(): string
	local count = workspace:GetAttribute(P.CountAttribute)
	local n = if typeof(count) == "number" then count else 0
	if n <= 0 then
		return P.NoOwnersLine
	end
	return string.format(if n == 1 then P.OneOwnerLine else P.OwnersLine, n)
end

-- Fires when the owner count changes (a panel that's open redraws).
function PhantomOffer.OnOwnersChanged(listener: () -> ())
	workspace:GetAttributeChangedSignal(P.CountAttribute):Connect(listener)
end

return PhantomOffer
