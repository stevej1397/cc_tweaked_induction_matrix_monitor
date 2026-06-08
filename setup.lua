-- Interactive configurator. Detects induction matrices and monitors,
-- asks which is which, asks for redstone sides + polarity + thresholds,
-- and writes a fresh config.lua.
--
-- Safe to run repeatedly; existing config.lua is backed up to config.lua.bak.

local function header(s)
    term.setTextColor(colors.cyan); print(s); term.setTextColor(colors.white)
end

local function info(s)
    term.setTextColor(colors.lightGray); print("  " .. s); term.setTextColor(colors.white)
end

local function warn(s)
    term.setTextColor(colors.yellow); print("  " .. s); term.setTextColor(colors.white)
end

local function prompt(question, default)
    if default ~= nil and tostring(default) ~= "" then
        write(question .. " [" .. tostring(default) .. "]: ")
    else
        write(question .. ": ")
    end
    local line = read()
    if line == "" then return default end
    return line
end

local function is_matrix(p)
    return type(p.getEnergy) == "function"
       and type(p.getMaxEnergy) == "function"
       and type(p.getLastInput) == "function"
       and type(p.getLastOutput) == "function"
end

local function is_monitor(p)
    return type(p.setTextScale) == "function"
       and type(p.getSize) == "function"
       and type(p.write) == "function"
end

local function find_candidates(predicate)
    local matches = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ok, p = pcall(peripheral.wrap, name)
        if ok and p and predicate(p) then
            matches[#matches + 1] = name
        end
    end
    return matches
end

local function describe_matrix(name)
    local ok, p = pcall(peripheral.wrap, name)
    if not ok or not p then return "" end
    local ok2, energy = pcall(p.getEnergy)
    local ok3, max = pcall(p.getMaxEnergy)
    if ok2 and ok3 and energy and max and max > 0 then
        return string.format("  (%.1f%% full)", (energy / max) * 100)
    end
    return ""
end

local function describe_monitor(name)
    local ok, p = pcall(peripheral.wrap, name)
    if not ok or not p then return "" end
    local ok2, w, h = pcall(p.getSize)
    if ok2 and w and h then return string.format("  (%dx%d chars)", w, h) end
    return ""
end

local function pick_peripheral(label, candidates, current, describer)
    print("")
    header(label)
    if #candidates == 0 then
        warn("no candidates detected -- you can still enter a name manually")
    else
        for i, name in ipairs(candidates) do
            local extra = describer and describer(name) or ""
            local marker = (name == current) and "*" or " "
            info(string.format("%s [%d] %s%s", marker, i, name, extra))
        end
        info("  [m]   enter a name manually")
    end
    local default = current
    if not default and #candidates > 0 then default = candidates[1] end
    while true do
        local answer = prompt("  choose", default)
        if answer == nil then return nil end
        local n = tonumber(answer)
        if n and candidates[n] then return candidates[n] end
        if answer == "m" or answer == "M" then
            local typed = prompt("  enter peripheral name", current)
            if typed and typed ~= "" then return typed end
        else
            for _, name in ipairs(candidates) do
                if name == answer then return answer end
            end
            if answer == default and default then return default end
        end
        info("not recognized, try again")
    end
end

local VALID_SIDES = {top=true, bottom=true, left=true, right=true, front=true, back=true}

local function pick_side(label, current)
    print("")
    header(label)
    info("valid sides: top, bottom, left, right, front, back")
    info("enter 'none' to leave this gate disabled")
    while true do
        local answer = prompt("  side", current or "none")
        if answer == nil or answer == "none" or answer == "" then return nil end
        if VALID_SIDES[answer] then return answer end
        warn("not a valid side")
    end
end

local function pick_polarity(current)
    print("")
    header("Gate polarity")
    info("high_opens: computer emits redstone HIGH to OPEN a gate (recommended)")
    info("low_opens : computer emits redstone LOW  to OPEN a gate")
    info("Pair this with your Mekanism cable's Configurator redstone mode.")
    while true do
        local answer = prompt("  polarity", current or "high_opens")
        if answer == "high_opens" or answer == "low_opens" then return answer end
        warn("must be 'high_opens' or 'low_opens'")
    end
end

local function pick_pct(label, current)
    while true do
        local answer = prompt(label, tostring(current))
        local n = tonumber(answer)
        if n then
            if n > 1 and n <= 100 then n = n / 100 end
            if n > 0 and n < 1 then return n end
        end
        warn("enter a fraction (0.75) or percent (75)")
    end
end

-- Try to load existing config as defaults
local existing = {}
if fs.exists("config.lua") then
    local ok, t = pcall(dofile, shell.resolve("config.lua"))
    if ok and type(t) == "table" then existing = t end
end

term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
header("Induction Matrix Monitor: interactive setup")
print("")
print("Scanning peripherals...")
print("")

local matrix_candidates = find_candidates(is_matrix)
local monitor_candidates = find_candidates(is_monitor)

info(string.format("found %d induction matrix port(s), %d monitor(s)",
    #matrix_candidates, #monitor_candidates))

local critical = pick_peripheral(
    "Pick the CRITICAL matrix port:",
    matrix_candidates,
    existing.critical_matrix,
    describe_matrix)

local remaining = {}
for _, n in ipairs(matrix_candidates) do
    if n ~= critical then remaining[#remaining + 1] = n end
end
local general = pick_peripheral(
    "Pick the GENERAL matrix port:",
    remaining,
    existing.general_matrix == critical and nil or existing.general_matrix,
    describe_matrix)

local mon = pick_peripheral(
    "Pick the MONITOR:",
    monitor_candidates,
    existing.monitor,
    describe_monitor)

local cg_side = pick_side(
    "Redstone side for the CRITICAL -> GENERAL gate cable:",
    existing.critical_to_general_side)
local gs_side = pick_side(
    "Redstone side for the GENERAL -> SINK gate cable:",
    existing.general_to_sink_side)

local polarity = pick_polarity(existing.gate_signal)

print("")
header("Gate thresholds (fraction 0..1 or percent 0..100):")
local c_open  = pick_pct("  critical opens at  ", existing.critical_open_at or 0.75)
local c_close = pick_pct("  critical closes at ", existing.critical_close_at or 0.70)
local g_open  = pick_pct("  general opens at   ", existing.general_open_at or 0.90)
local g_close = pick_pct("  general closes at  ", existing.general_close_at or 0.85)

if c_close > c_open then
    warn("critical close > open; swapping")
    c_open, c_close = c_close, c_open
end
if g_close > g_open then
    warn("general close > open; swapping")
    g_open, g_close = g_close, g_open
end

local function fmt_str(s)
    if s == nil then return "nil" end
    return string.format("%q", s)
end

local config_text = string.format([[
-- ============================================================
-- Induction Matrix Monitor configuration
-- Generated by setup. Re-run 'setup' to regenerate interactively,
-- or edit values below by hand.
-- ============================================================
return {
    -- Peripheral names
    critical_matrix = %s,
    general_matrix  = %s,
    monitor         = %s,

    -- Redstone sides (set to nil to disable a gate)
    critical_to_general_side = %s,
    general_to_sink_side     = %s,

    -- "high_opens" or "low_opens"
    gate_signal = %s,

    -- Gate thresholds (fractions, with hysteresis)
    critical_open_at  = %s,
    critical_close_at = %s,
    general_open_at   = %s,
    general_close_at  = %s,

    -- Sampling
    live_interval        = %s,
    history_interval     = %s,
    history_max_samples  = %s,
    history_path         = "/history.dat",

    -- Display
    text_scale     = %s,
    critical_color = colors.lime,
    general_color  = colors.cyan,
}
]],
    fmt_str(critical),
    fmt_str(general),
    fmt_str(mon),
    fmt_str(cg_side),
    fmt_str(gs_side),
    fmt_str(polarity),
    c_open, c_close, g_open, g_close,
    existing.live_interval or 2,
    existing.history_interval or 30,
    existing.history_max_samples or 1440,
    existing.text_scale or 0.5
)

print("")
header("Summary")
info("critical matrix : " .. tostring(critical))
info("general  matrix : " .. tostring(general))
info("monitor         : " .. tostring(mon))
info("c->g redstone   : " .. tostring(cg_side or "(disabled)"))
info("g->s redstone   : " .. tostring(gs_side or "(disabled)"))
info("polarity        : " .. tostring(polarity))
info(string.format("critical gate   : open >= %d%%, close <= %d%%", c_open * 100, c_close * 100))
info(string.format("general  gate   : open >= %d%%, close <= %d%%", g_open * 100, g_close * 100))

print("")
write("Write this configuration to config.lua? [Y/n]: ")
local confirm = read()
if confirm ~= "" and confirm:sub(1,1):lower() == "n" then
    print("Cancelled. config.lua not modified.")
    return
end

if fs.exists("config.lua") then
    if fs.exists("config.lua.bak") then fs.delete("config.lua.bak") end
    fs.copy("config.lua", "config.lua.bak")
    info("backed up previous config to config.lua.bak")
end

local f = fs.open("config.lua", "w")
f.write(config_text)
f.close()

term.setTextColor(colors.lime); print("config.lua written."); term.setTextColor(colors.white)
print("")
print("Next: run 'check' to verify, then reboot (or run 'monitor') to start.")
