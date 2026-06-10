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

-- ============================================================
-- Temporary diagnostic log. Records every history_tick fire +
-- timer-id transition so we can tell whether the stuck-at-N bug
-- is the timer never re-firing or history_tick returning early.
-- Lives at /monitor.diag.log, reset each boot. Remove later.
-- ============================================================
local DIAG_PATH = "/monitor.diag.log"
pcall(fs.delete, DIAG_PATH)
local function diag(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local line = string.format("[%s | t=%.1fs] %s",
        os.date("!%T"), (os.epoch("utc") - session_start_ms) / 1000, msg)
    pcall(function()
        local f = fs.open(DIAG_PATH, "a")
        if f then f.writeLine(line); f.close() end
    end)
end
diag("=== boot. loaded=%d  live_int=%s  hist_int=%s ===",
    samples_at_boot,
    tostring(config.live_interval or 2),
    tostring(config.history_interval or 30))

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
    diag("history_tick enter (last_sample=%s)", last_sample and "set" or "nil")
    local c, g
    if last_sample then
        c, g = last_sample.c, last_sample.g
    else
        c, g = read_both()
    end
    if not (c and g) then
        diag("history_tick SKIP (c=%s g=%s)",
            c and "ok" or "nil", g and "ok" or "nil")
        return
    end
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
    diag("history_tick appended; session_appends=%d total=%d",
        session_appends, history:count())
    local t0 = os.epoch("utc")
    local ok, err = pcall(history.save, history)
    local elapsed = (os.epoch("utc") - t0) / 1000
    if not ok then
        diag("history_tick SAVE FAILED after %.2fs: %s", elapsed, tostring(err))
        print("[history] save failed: " .. tostring(err))
    else
        diag("history_tick save ok (%.2fs)", elapsed)
    end
    render:draw_graph(history:get())
    diag("history_tick complete")
end

-- Initial read so the display isn't empty for the first tick.
live_tick()
history_tick()

local live_timer = os.startTimer(config.live_interval or 2)
local history_timer = os.startTimer(config.history_interval or 30)
diag("initial timers armed: live_id=%s history_id=%s",
    tostring(live_timer), tostring(history_timer))

print("[monitor] running. live=" .. (config.live_interval or 2) ..
      "s  history=" .. (config.history_interval or 30) .. "s")
print("[monitor] press CTRL+T to terminate")

while true do
    -- pullEventRaw so the explicit 'terminate' branch below runs instead
    -- of pullEvent's default behaviour of raising a 'Terminated' error.
    local event, p1 = os.pullEventRaw()
    if event == "timer" then
        if p1 == live_timer then
            local ok, e = pcall(live_tick)
            if not ok then
                print("[live] " .. tostring(e))
                diag("live_tick ERROR: %s", tostring(e))
            end
            live_timer = os.startTimer(config.live_interval or 2)
        elseif p1 == history_timer then
            diag("HISTORY TIMER FIRED id=%s", tostring(p1))
            local ok, e = pcall(history_tick)
            if not ok then
                print("[history] " .. tostring(e))
                diag("history_tick ERROR: %s", tostring(e))
            end
            history_timer = os.startTimer(config.history_interval or 30)
            diag("history_timer rearmed to id=%s", tostring(history_timer))
        else
            -- A timer fired that we don't recognise -- log it so we can
            -- tell whether something is consuming IDs out from under us.
            diag("unknown timer fired id=%s (live=%s history=%s)",
                tostring(p1), tostring(live_timer), tostring(history_timer))
        end
    elseif event == "peripheral_detach" then
        print("[monitor] peripheral detached: " .. tostring(p1))
        diag("peripheral_detach %s", tostring(p1))
    elseif event == "peripheral" then
        print("[monitor] peripheral attached: " .. tostring(p1))
        diag("peripheral_attach %s", tostring(p1))
    elseif event == "terminate" then
        diag("terminate event received")
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
