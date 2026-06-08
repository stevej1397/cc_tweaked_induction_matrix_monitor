local util = require("lib.util")
local Graph = require("lib.graph")

local M = {}
M.__index = M

local TITLE = "INDUCTION MATRIX MONITOR"

local function draw_text(mon, x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    if fg then mon.setTextColor(fg) end
    if bg then mon.setBackgroundColor(bg) end
    mon.write(text)
end

local function clear_row(mon, y, w, bg)
    mon.setBackgroundColor(bg or colors.black)
    mon.setCursorPos(1, y)
    mon.write(string.rep(" ", w))
end

local function bar(mon, x, y, width, fill, fg_color, bg_color)
    fill = util.clamp(fill or 0, 0, 1)
    local filled = math.floor(fill * width + 0.5)
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(fg_color)
    mon.write(string.rep(" ", filled))
    mon.setBackgroundColor(bg_color)
    mon.write(string.rep(" ", width - filled))
end

function M.new(monitor, cfg)
    monitor.setTextScale(cfg.text_scale or 0.5)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local w, h = monitor.getSize()

    -- Layout:
    --   row 1            : title bar
    --   row 2            : blank
    --   rows 3..stats_end: two-column stats (critical | general)
    --   rows ..gate_end  : gate status
    --   row graph_title  : graph header + legend
    --   rows ..h-1       : pixelbox graph window
    --   row h            : x-axis labels
    local stats_height = 8
    local gate_height = 4
    local stats_start = 3
    local stats_end = stats_start + stats_height - 1   -- 10
    local gate_start = stats_end + 2                   -- 12 (blank row at 11)
    local gate_end = gate_start + gate_height - 1      -- 15
    local graph_title = gate_end + 2                   -- 17 (blank row at 16)
    local graph_axis = h
    local graph_win_start = graph_title + 1
    local graph_win_end = graph_axis - 1
    local graph_win_height = graph_win_end - graph_win_start + 1
    if graph_win_height < 4 then
        -- Monitor too short. Squeeze.
        graph_win_height = math.max(2, h - graph_title - 1)
        graph_win_end = graph_win_start + graph_win_height - 1
    end

    local graph_window = window.create(monitor, 1, graph_win_start, w, graph_win_height, true)
    local graph = Graph.new(
        graph_window,
        cfg.history_max_samples or 1440,
        colors.black,
        colors.gray,
        cfg.critical_color or colors.lime,
        cfg.general_color or colors.cyan
    )

    return setmetatable({
        monitor = monitor,
        cfg = cfg,
        w = w,
        h = h,
        graph = graph,
        graph_window = graph_window,
        regions = {
            stats_start = stats_start,
            stats_end = stats_end,
            gate_start = gate_start,
            gate_end = gate_end,
            graph_title = graph_title,
            graph_axis = graph_axis,
        },
    }, M)
end

function M:draw_static()
    local m = self.monitor
    local w = self.w

    clear_row(m, 1, w, colors.gray)
    draw_text(m, 2, 1, TITLE, colors.white, colors.gray)
    if self.cfg.version then
        local v = "v" .. self.cfg.version
        draw_text(m, w - #v, 1, v, colors.lightGray, colors.gray)
    end

    -- Column headers
    local mid = math.floor(w / 2)
    clear_row(m, self.regions.stats_start, w, colors.black)
    draw_text(m, 2, self.regions.stats_start, "CRITICAL MATRIX", colors.lime, colors.black)
    draw_text(m, mid + 2, self.regions.stats_start, "GENERAL MATRIX", colors.cyan, colors.black)

    -- Gate header
    clear_row(m, self.regions.gate_start, w, colors.black)
    draw_text(m, 2, self.regions.gate_start, "POWER GATES", colors.yellow, colors.black)

    -- Graph header + legend
    clear_row(m, self.regions.graph_title, w, colors.black)
    draw_text(m, 2, self.regions.graph_title, "12-HOUR FILL HISTORY", colors.white, colors.black)
    draw_text(m, w - 24, self.regions.graph_title, "critical", colors.lime, colors.black)
    draw_text(m, w - 14, self.regions.graph_title, "general", colors.cyan, colors.black)
    draw_text(m, w - 6, self.regions.graph_title, "grid", colors.gray, colors.black)

    -- X-axis labels at bottom
    local axis_y = self.regions.graph_axis
    clear_row(m, axis_y, w, colors.black)
    local labels = {"-12h", "-9h", "-6h", "-3h", "now"}
    for i, label in ipairs(labels) do
        local frac = (i - 1) / (#labels - 1)
        local x = math.max(1, math.min(w - #label + 1, math.floor(frac * (w - 1)) + 1))
        if i == 1 then x = 1 end
        if i == #labels then x = w - #label + 1 end
        draw_text(m, x, axis_y, label, colors.lightGray, colors.black)
    end
end

local function make_row(m, x0, col_w)
    return function(y, label, value, value_color)
        m.setBackgroundColor(colors.black)
        m.setTextColor(colors.lightGray)
        m.setCursorPos(x0, y)
        m.write(string.rep(" ", col_w))
        m.setCursorPos(x0, y)
        m.write(label)
        if value then
            m.setTextColor(value_color or colors.white)
            m.setCursorPos(x0 + 10, y)
            m.write(value)
        end
    end
end

function M:draw_stats(critical, general, gates)
    local m = self.monitor
    local w = self.w
    local mid = math.floor(w / 2)
    local col_w = mid - 2
    local left_x = 2
    local right_x = mid + 2

    local r_start = self.regions.stats_start + 1

    local unit = self.cfg.energy_unit or "J"

    local function side(x0, data, fill_color)
        local row = make_row(m, x0, col_w)
        if not data then
            row(r_start,     "Status:",  "OFFLINE", colors.red)
            for i = 1, 6 do
                m.setBackgroundColor(colors.black)
                m.setCursorPos(x0, r_start + i)
                m.write(string.rep(" ", col_w))
            end
            return
        end
        row(r_start,     "Energy:",   util.format_energy(data.energy, unit), colors.white)
        row(r_start + 1, "Capacity:", util.format_energy(data.max, unit), colors.lightGray)
        row(r_start + 2, "Fill:",     util.format_pct(data.fill), colors.white)
        -- Fill bar on row + 3
        m.setBackgroundColor(colors.black)
        m.setTextColor(colors.lightGray)
        m.setCursorPos(x0, r_start + 3)
        m.write("[")
        bar(m, x0 + 1, r_start + 3, col_w - 2, data.fill, fill_color, colors.gray)
        m.setBackgroundColor(colors.black)
        m.setTextColor(colors.lightGray)
        m.setCursorPos(x0 + col_w - 1, r_start + 3)
        m.write("]")

        row(r_start + 4, "Input:",  util.format_rate_per_sec(data.input, unit), colors.green)
        row(r_start + 5, "Output:", util.format_rate_per_sec(data.output, unit), colors.orange)
        row(r_start + 6, "ETA:",    util.format_eta(data.energy, data.max, data.net),
            data.net >= 0 and colors.green or colors.orange)
    end

    side(left_x, critical, self.cfg.critical_color or colors.lime)
    side(right_x, general, self.cfg.general_color or colors.cyan)

    -- Gates
    local g_start = self.regions.gate_start + 1
    local function draw_gate(y, label, open, hint)
        m.setBackgroundColor(colors.black)
        m.setCursorPos(1, y)
        m.write(string.rep(" ", w))
        m.setCursorPos(2, y)
        m.setTextColor(colors.lightGray)
        m.write(label)
        local state_x = 26
        m.setCursorPos(state_x, y)
        if open then
            m.setTextColor(colors.lime)
            m.write("[ OPEN ]")
        else
            m.setTextColor(colors.red)
            m.write("[ SHUT ]")
        end
        m.setTextColor(colors.gray)
        m.setCursorPos(state_x + 10, y)
        m.write(hint or "")
    end

    local c_open_pct  = math.floor((self.cfg.critical_open_at  or 0.75) * 100 + 0.5)
    local c_close_pct = math.floor((self.cfg.critical_close_at or 0.70) * 100 + 0.5)
    local g_open_pct  = math.floor((self.cfg.general_open_at   or 0.90) * 100 + 0.5)
    local g_close_pct = math.floor((self.cfg.general_close_at  or 0.85) * 100 + 0.5)

    draw_gate(g_start, "Critical -> General",
        gates and gates.cg_open or false,
        string.format("open>=%d%%  close<=%d%%", c_open_pct, c_close_pct))

    -- General -> Sink also requires critical to be at threshold. Surface
    -- the *reason* the gate is shut when we can: blocked-by-critical is
    -- the most informative thing to see at a glance.
    local gs_hint
    if gates and gates.gs_open then
        gs_hint = string.format("open>=%d%% & critical full", g_open_pct)
    else
        local critical_fill = critical and critical.fill or nil
        local general_fill  = general and general.fill or nil
        if critical_fill and critical_fill < self.cfg.critical_open_at then
            gs_hint = "blocked: critical not full"
        elseif general_fill and general_fill < self.cfg.general_open_at then
            gs_hint = string.format("waiting: general < %d%%", g_open_pct)
        else
            gs_hint = string.format("open>=%d%% close<=%d%%", g_open_pct, g_close_pct)
        end
    end
    draw_gate(g_start + 1, "General  -> Sink   ",
        gates and gates.gs_open or false, gs_hint)

    -- Refresh title bar timestamp
    local ts = textutils.formatTime(os.time(), false)
    local label = " " .. ts .. " "
    m.setBackgroundColor(colors.gray)
    m.setTextColor(colors.lightGray)
    m.setCursorPos(self.w - #label - 1, 1)
    m.write(label)
end

function M:draw_graph(samples)
    self.graph:render(samples or {})
end

function M:draw_error(msg)
    local m = self.monitor
    m.setBackgroundColor(colors.red)
    m.setTextColor(colors.white)
    m.setCursorPos(2, self.regions.stats_start)
    m.write(util.center(msg or "ERROR", self.w - 2))
end

return M
