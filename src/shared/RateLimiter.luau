--!strict
-- Per-player token buckets keyed by remote name. Server-only in practice.

local RateLimiter = {}

type Bucket = { tokens: number, last: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

-- Returns true if the call is within budget. perSecond is the refill rate; burst (default = perSecond) the cap.
function RateLimiter.Allow(player: Player, key: string, perSecond: number, burst: number?): boolean
	local now = os.clock()
	local cap = burst or perSecond
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { tokens = cap, last = now }
		playerBuckets[key] = bucket
	end
	bucket.tokens = math.min(cap, bucket.tokens + (now - bucket.last) * perSecond)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.Clear(player: Player)
	buckets[player] = nil
end

return RateLimiter
