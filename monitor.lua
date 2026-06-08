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

for _, side in ipairs({"critical_to_general_side", "general_to_sink_side"}) do
    local s = config[side]
    if s and not peripherals_lib.valid_side(s) then
        die("invalid redstone side for " .. side .. ": " .. tostring(s))
    end
end

local history = History.load(config.history_path, config.history_max_samples)
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
        render:draw_stats(c, g, control:state())
        last_sample = {c = c, g = g}
    else
        -- Read failed: keep gates in current state but make it visible
        render:draw_stats(c, g, control:state())
    end
end

local function history_tick()
    local c, g
    if last_sample then
        c, g = last_sample.c, last_sample.g
    else
        c, g = read_both()
    end
    if c and g then
        history:append({
            t = os.epoch("utc"),
            critical_fill = c.fill,
            general_fill = g.fill,
            critical_input = c.input,
            critical_output = c.output,
            general_input = g.input,
            general_output = g.output,
        })
        history:save()
        render:draw_graph(history:get())
    end
end

-- Initial read so the display isn't empty for the first tick.
live_tick()
history_tick()

local live_timer = os.startTimer(config.live_interval or 2)
local history_timer = os.startTimer(config.history_interval or 30)

print("[monitor] running. live=" .. (config.live_interval or 2) ..
      "s  history=" .. (config.history_interval or 30) .. "s")
print("[monitor] press CTRL+T to terminate")

while true do
    local event, p1 = os.pullEvent()
    if event == "timer" then
        if p1 == live_timer then
            local ok, e = pcall(live_tick)
            if not ok then print("[live] " .. tostring(e)) end
            live_timer = os.startTimer(config.live_interval or 2)
        elseif p1 == history_timer then
            local ok, e = pcall(history_tick)
            if not ok then print("[history] " .. tostring(e)) end
            history_timer = os.startTimer(config.history_interval or 30)
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
