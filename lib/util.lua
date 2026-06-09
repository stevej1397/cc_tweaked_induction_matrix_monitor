local M = {}

-- Mekanism's native unit is Joules. These are the multipliers it uses
-- internally when converting (you can verify in /config/mekanism-common.toml
-- under "config.general.energyConversionRate" -- defaults below).
M.UNIT_FACTORS = {
    J  = 1,
    FE = 0.4,    -- 1 J = 0.4 FE  (i.e. 1 FE = 2.5 J)
    RF = 0.4,    -- Forge Energy and Redstone Flux share the rate
    EU = 0.04,   -- 1 J = 0.04 EU (i.e. 1 EU = 25 J)
}

local PREFIXES = {"", "k", "M", "G", "T", "P", "E", "Z"}

local function scale(value)
    local sign = ""
    if value < 0 then sign = "-"; value = -value end
    local i = 1
    while value >= 1000 and i < #PREFIXES do
        value = value / 1000
        i = i + 1
    end
    return sign, value, PREFIXES[i]
end

function M.unit_factor(unit)
    return M.UNIT_FACTORS[unit] or 1
end

function M.format_energy(j, unit)
    if j == nil then return "?" end
    unit = unit or "J"
    local converted = j * M.unit_factor(unit)
    local sign, value, prefix = scale(converted)
    return string.format("%s%.2f %s%s", sign, value, prefix, unit)
end

function M.format_rate_per_sec(j_per_tick, unit)
    if j_per_tick == nil then return "?" end
    return M.format_energy(j_per_tick * 20, unit) .. "/s"
end

-- Format an input/output rate. period = "s" (per second; multiply by 20)
-- or "t" (per tick; raw Mekanism value -- matches the in-game GUI).
function M.format_rate(j_per_tick, unit, period)
    if j_per_tick == nil then return "?" end
    period = period or "s"
    if period == "t" then
        return M.format_energy(j_per_tick, unit) .. "/t"
    end
    return M.format_energy(j_per_tick * 20, unit) .. "/s"
end

function M.format_pct(fill)
    if fill == nil then return "  ?  " end
    return string.format("%5.1f%%", fill * 100)
end

function M.format_eta(energy, max, rate_per_tick)
    -- rate_per_tick: positive = filling, negative = draining (we infer with sign of net)
    -- We accept either input-output as net rate.
    if not energy or not max or not rate_per_tick or rate_per_tick == 0 then return "-" end
    local seconds
    if rate_per_tick > 0 then
        seconds = (max - energy) / (rate_per_tick * 20)
    else
        seconds = energy / (-rate_per_tick * 20)
    end
    if seconds < 0 or seconds ~= seconds then return "-" end
    if seconds < 60 then return string.format("%ds", math.floor(seconds)) end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format("%dh%dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)) end
    return string.format("%dd", math.floor(seconds / 86400))
end

function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.center(text, width)
    local pad = math.max(0, width - #text)
    local left = math.floor(pad / 2)
    return string.rep(" ", left) .. text .. string.rep(" ", pad - left)
end

return M
