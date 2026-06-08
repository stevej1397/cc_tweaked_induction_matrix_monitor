-- Pre-flight check: verifies that the configured peripherals exist
-- and that the redstone sides are valid. Run this after wiring and
-- after editing config.lua.

local config = require("config")
local peripherals_lib = require("lib.peripherals")

local ok_count, fail_count = 0, 0

local function ok(msg)
    term.setTextColor(colors.lime)
    write("  OK    ")
    term.setTextColor(colors.white)
    print(msg)
    ok_count = ok_count + 1
end

local function fail(msg)
    term.setTextColor(colors.red)
    write("  FAIL  ")
    term.setTextColor(colors.white)
    print(msg)
    fail_count = fail_count + 1
end

local function info(msg)
    term.setTextColor(colors.lightGray)
    print("  " .. msg)
    term.setTextColor(colors.white)
end

print("Induction Matrix Monitor: pre-flight check")
print("------------------------------------------")

-- Connected peripherals overview
print("Connected peripherals:")
local names = peripheral.getNames()
if #names == 0 then
    info("(none) -- attach wired modems and matrix ports!")
else
    for _, name in ipairs(names) do
        info(string.format("%-30s %s", name, peripheral.getType(name) or "?"))
    end
end
print("")

-- Critical matrix
local p, err = peripherals_lib.find_matrix(config.critical_matrix)
if p then
    ok("critical matrix: " .. config.critical_matrix)
    local snap = peripherals_lib.read_matrix(p)
    if snap then
        info(string.format("energy=%.0f J  max=%.0f J  fill=%.1f%%",
            snap.energy, snap.max, snap.fill * 100))
    end
else
    fail("critical matrix: " .. err)
end

-- General matrix
local p2, err2 = peripherals_lib.find_matrix(config.general_matrix)
if p2 then
    ok("general matrix: " .. config.general_matrix)
    local snap = peripherals_lib.read_matrix(p2)
    if snap then
        info(string.format("energy=%.0f J  max=%.0f J  fill=%.1f%%",
            snap.energy, snap.max, snap.fill * 100))
    end
else
    fail("general matrix: " .. err2)
end

-- Monitor
local mon, err3 = peripherals_lib.find_monitor(config.monitor)
if mon then
    ok("monitor: " .. config.monitor)
    local w, h = mon.getSize()
    info(string.format("size=%dx%d chars  (text_scale=%s)",
        w, h, tostring(config.text_scale)))
    if w < 40 or h < 20 then
        info("WARN: monitor is small; layout assumes ~60x30 (4x3 advanced monitors at scale 0.5)")
    end
else
    fail("monitor: " .. err3)
end

-- Redstone outputs (new multi-output schema, plus legacy fallback)
local function check_outputs(label, list_key, legacy_key)
    local spec = config[list_key] or config[legacy_key]
    local outputs = peripherals_lib.compile_outputs(spec)
    if #outputs == 0 then
        info(label .. ": disabled (no outputs)")
        return
    end
    for i, o in ipairs(outputs) do
        local side_ok = peripherals_lib.valid_side(o.side)
        local target_ok = (o.peripheral == "computer") or peripheral.isPresent(o.peripheral)
        local desc = string.format("%s [#%d]: %s side=%s",
            label, i, tostring(o.peripheral or "?"), tostring(o.side or "?"))
        if side_ok and target_ok then
            ok(desc)
        else
            local why = {}
            if not target_ok then why[#why + 1] = "peripheral not present" end
            if not side_ok then why[#why + 1] = "invalid side" end
            fail(desc .. "  (" .. table.concat(why, ", ") .. ")")
        end
    end
end
check_outputs("critical -> general", "critical_to_general_outputs", "critical_to_general_side")
check_outputs("general  -> sink",    "general_to_sink_outputs",    "general_to_sink_side")

-- Thresholds
local function check_thresh(label, open_at, close_at)
    if not (open_at and close_at) then
        fail(label .. ": thresholds missing")
    elseif open_at < close_at then
        fail(label .. ": open_at (" .. open_at .. ") must be >= close_at (" .. close_at .. ")")
    elseif open_at <= 0 or open_at > 1 or close_at < 0 or close_at >= 1 then
        fail(label .. ": thresholds must be in (0, 1)")
    else
        ok(string.format("%s: open >= %.0f%%, close <= %.0f%%",
            label, open_at * 100, close_at * 100))
    end
end
check_thresh("critical gate", config.critical_open_at, config.critical_close_at)
check_thresh("general gate",  config.general_open_at,  config.general_close_at)

-- external deps
local function check_file(label, path, hint)
    if fs.exists(path) or fs.exists("/" .. path) then
        ok(label)
    else
        fail(label .. " - " .. (hint or ("run 'update' to fetch " .. path)))
    end
end
check_file("pixelbox_lite", "pixelbox_lite.lua")
check_file("pixelui",       "pixelui.lua", "run 'update' to fetch pixelui.lua")
check_file("shrekbox",      "shrekbox.lua", "run 'update' to fetch shrekbox.lua (pixelui dep)")

print("")
term.setTextColor(colors.white)
write(ok_count .. " ok / ")
term.setTextColor(fail_count == 0 and colors.lime or colors.red)
write(fail_count .. " fail")
term.setTextColor(colors.white)
print("")
if fail_count == 0 then
    print("All good. Reboot or run 'monitor' to start.")
else
    print("Fix the issues above (edit config.lua) and re-run 'check'.")
end
