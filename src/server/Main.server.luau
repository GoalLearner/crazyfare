--!strict
-- Server boot. Order: (Studio only) build the blockout city if the place has no Map,
-- then Init() every service, then Start() every service. RoundService starts last.

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

if not workspace:FindFirstChild("Map") then
	local DevBlockout = require(script.Parent.Studio.DevBlockout)
	DevBlockout.Generate()
end

type Service = { Init: () -> (), Start: () -> () }

local Services = script.Parent.Services
local ordered: { Service } = {
	require(Services.MapService),
	require(Services.DataService),
	require(Services.MonetizationService),
	require(Services.SessionService),
	require(Services.VehicleService),
	require(Services.ComboService),
	require(Services.PassengerService),
	require(Services.GemService),
	require(Services.FareService),
	require(Services.RiderService),
	require(Services.WalkerService),
	require(Services.ItemService),
	require(Services.StoreService),
	require(Services.RamService),
	require(Services.PedestrianService),
	require(Services.TrafficService),
	require(Services.BotService),
	require(Services.WorldEventService),
	require(Services.WeatherService),
	require(Services.PitStopService),
	require(Services.GarageService),
	require(Services.ProgressionService),
	require(Services.LeaderboardService),
	require(Services.DropService),
	require(Services.LevelRewardService),
	require(Services.DailyShopService),
	require(Services.QuestService),
	require(Services.ReplicationService),
	require(Services.DepotService),
	require(Services.DebugService),
	require(Services.MatchController),
	require(Services.MetricsService),
	require(Services.MapVoteService),
	require(Services.BadgesService),
	require(Services.RoundService),
}

for _, service in ordered do
	service.Init()
end
for _, service in ordered do
	service.Start()
end

print("[CrazyFare] server ready")
