local M = {}

local ENERGY_UNITS = {"J", "kJ", "MJ", "GJ", "TJ", "PJ", "EJ", "ZJ"}

function M.format_energy(j)
    if j == nil then return "?" end
    local sign = ""
    if j < 0 then sign = "-"; j = -j end
    local i = 1
    while j >= 1000 and i < #ENERGY_UNITS do
        j = j / 1000
        i = i + 1
    end
    return string.format("%s%.2f %s", sign, j, ENERGY_UNITS[i])
end

function M.format_rate_per_sec(j_per_tick)
    if j_per_tick == nil then return "?" end
    return M.format_energy(j_per_tick * 20) .. "/s"
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
