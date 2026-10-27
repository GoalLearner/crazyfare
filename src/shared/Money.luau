--!strict
-- Money is stored and sent as integer cents (CLAUDE.md: integers for money). Config writes fares, prices and quotas in
-- dollars for readability; convert at the boundary with Money.Cents and show with Money.Format.

local Money = {}

function Money.Cents(dollars: number): number
	return math.round(dollars * 100)
end

-- "$12.30", or "$12" when there are no cents.
function Money.Format(cents: number): string
	local whole = math.round(cents)
	local sign = if whole < 0 then "-" else ""
	whole = math.abs(whole)
	local dollars, rest = whole // 100, whole % 100
	if rest == 0 then
		return string.format("%s$%d", sign, dollars)
	end
	return string.format("%s$%d.%02d", sign, dollars, rest)
end

-- Always two decimals: "$12.00". For counters that roll, so the width never jumps.
function Money.FormatCents(cents: number): string
	local whole = math.max(0, math.round(cents))
	return string.format("$%d.%02d", whole // 100, whole % 100)
end

return Money
