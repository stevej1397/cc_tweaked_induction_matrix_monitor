-- Main monitor program.
-- Two timers drive everything:
--   live_interval (default 2s)   : read matrices, update redstone gates, redraw stats
--   history_interval (default 30s): append sample to history, persist, redraw graph

local config = require("config")
local util = require("lib.util")
local peripherals_lib = require("lib.peripherals")
local History = require("lib.history")
local Control = require("lib.control")
local Render = require("lib.render")

local function die(msg)
    term.setTextColor(colors.red)
    print("[monitor] " .. msg)
    term.setTextColor(colors.white)
    error(msg, 0)
end

-- Wrap peripherals
local critical, err = peripherals_lib.find_matrix(config.critical_matrix)
if not critical then die("critical matrix: " .. err) end
local general, err2 = peripherals_lib.find_matrix(config.general_matrix)
if not general then die("general matrix: " .. err2) end
local monitor, err3 = peripherals_lib.find_monitor(config.monitor)
if not monitor then die("monitor: " .. err3) end

-- Validate every configured redstone output before going live.
local function validate_outputs(label, list_key, legacy_key)
    local outputs = peripherals_lib.compile_outputs(config[list_key] or config[legacy_key])
    for i, o in ipairs(outputs) do
        if not peripherals_lib.valid_side(o.side) then
            die(string.format("%s output #%d: invalid side '%s'", label, i, tostring(o.side)))
        end
        if o.peripheral ~= "computer" and not peripheral.isPresent(o.peripheral) then
            die(string.format("%s output #%d: peripheral '%s' not present", label, i, tostring(o.peripheral)))
        end
    end
end
validate_outputs("critical->general", "critical_to_general_outputs", "critical_to_general_side")
validate_outputs("general->sps",      "general_to_sps_outputs",      nil)
validate_outputs("general->sink",     "general_to_sink_outputs",     "general_to_sink_side")

local history = History.load(config.history_path, config.history_max_samples)
if history.load_error then
    term.setTextColor(colors.yellow)
    print("[monitor] history: " .. history.load_error)
    print("[monitor] starting with empty history buffer")
    term.setTextColor(colors.white)
else
    print("[monitor] history: " .. (history.load_status or "(?)"))
end
local samples_at_boot = history:count()
local session_appends = 0
local session_start_ms = os.epoch("utc")


local function health_status()
    return {
        session_start_ms = session_start_ms,
        samples = history:get(),
        session_appends = session_appends,
    }
end
local control = Control.new(config)
local render = Render.new(monitor, config)

render:draw_static()
render:draw_graph(history:get())

local last_sample

local function read_both()
    local c = peripherals_lib.read_matrix(critical)
    local g = peripherals_lib.read_matrix(general)
    return c, g
end

local function live_tick()
    local c, g = read_both()
    if c and g then
        control:update(c.fill, g.fill)
        render:draw_stats(c, g, control:state(), health_status())
        last_sample = {c = c, g = g}
    else
        -- Read failed: keep gates in current state but make it visible
        render:draw_stats(c, g, control:state(), health_status())
    end
end

local function history_tick()
    local c, g
    if last_sample then
        c, g = last_sample.c, last_sample.g
    else
        c, g = read_both()
    end
    if not (c and g) then return end
    history:append({
        t = os.epoch("utc"),
        critical_fill = c.fill,
        general_fill = g.fill,
        critical_input = c.input,
        critical_output = c.output,
        general_input = g.input,
        general_output = g.output,
    })
    session_appends = session_appends + 1
    local ok, err = pcall(history.save, history)
    if not ok then
        print("[history] save failed: " .. tostring(err))
    end
    render:draw_graph(history:get())
end

-- Initial read so the display isn't empty for the first tick.
live_tick()
history_tick()

-- Single timer drives everything. Separate os.startTimer(30) for
-- history was unreliable on CraftOS 1.9 +MBS (the rearmed long-
-- duration timer just never fired), while the short-duration live
-- timer always worked. We rearm a single 2-second timer in a loop
-- and fire history_tick whenever wall-clock has advanced past the
-- next history deadline. Using epoch-time deadlines (rather than
-- counting ticks) keeps the history cadence locked to the configured
-- interval even when each live tick takes longer than its nominal
-- duration to process.
local TICK_INTERVAL = config.live_interval or 2
local HISTORY_INTERVAL_MS = (config.history_interval or 30) * 1000
local next_history_at_ms = os.epoch("utc") + HISTORY_INTERVAL_MS
local tick_timer = os.startTimer(TICK_INTERVAL)

print("[monitor] running. tick=" .. TICK_INTERVAL ..
      "s  history=" .. (config.history_interval or 30) .. "s")
print("[monitor] press CTRL+T to terminate")

while true do
    -- pullEventRaw so the explicit 'terminate' branch below runs instead
    -- of pullEvent's default behaviour of raising a 'Terminated' error.
    local event, p1 = os.pullEventRaw()
    if event == "timer" then
        if p1 == tick_timer then
            local ok, e = pcall(live_tick)
            if not ok then print("[live] " .. tostring(e)) end

            local now_ms = os.epoch("utc")
            if now_ms >= next_history_at_ms then
                local ok2, e2 = pcall(history_tick)
                if not ok2 then print("[history] " .. tostring(e2)) end
                next_history_at_ms = next_history_at_ms + HISTORY_INTERVAL_MS
                -- If we'd somehow fallen far behind (e.g. paused for
                -- minutes), don't burst-fire every missed sample on
                -- recovery -- just resume from now.
                if next_history_at_ms < now_ms then
                    next_history_at_ms = now_ms + HISTORY_INTERVAL_MS
                end
            end

            tick_timer = os.startTimer(TICK_INTERVAL)
        end
    elseif event == "peripheral_detach" then
        print("[monitor] peripheral detached: " .. tostring(p1))
    elseif event == "peripheral" then
        print("[monitor] peripheral attached: " .. tostring(p1))
    elseif event == "terminate" then
        -- Be safe on terminate: close gates so power doesn't keep flowing past critical.
        control:close_all()
        monitor.setBackgroundColor(colors.black)
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.setTextColor(colors.white)
        monitor.write("monitor stopped")
        print("[monitor] terminated; gates closed")
        return
    end
end
