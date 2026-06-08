-- 12-hour history graph rendered with pixelbox_lite into a sub-window.
-- The sub-window covers the lower portion of the monitor.

local pixelbox = require("pixelbox_lite")

local M = {}
M.__index = M

local function plot_pixel(box, x, y, color)
    local row = box.canvas[y]
    if row and x >= 1 and x <= box.width then
        row[x] = color
    end
end

local function plot_line(box, x0, y0, x1, y1, color)
    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
        plot_pixel(box, x0, y0, color)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; x0 = x0 + sx end
        if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
end

-- Build a pixelbox graph attached to the given monitor window.
function M.new(window, total_samples, bg_color, grid_color, critical_color, general_color)
    local self = setmetatable({}, M)
    self.window = window
    self.box = pixelbox.new(window)
    self.total_samples = total_samples or 1440
    self.bg = bg_color or colors.black
    self.grid = grid_color or colors.gray
    self.critical_color = critical_color or colors.lime
    self.general_color = general_color or colors.cyan
    return self
end

function M:clear()
    local box = self.box
    for y = 1, box.height do
        local row = box.canvas[y]
        for x = 1, box.width do
            row[x] = self.bg
        end
    end
end

function M:draw_grid()
    local box = self.box
    local h = box.height
    -- Horizontal grid lines at 25%, 50%, 75%, 100%
    for _, pct in ipairs({0.25, 0.5, 0.75, 1.0}) do
        local y = math.max(1, math.floor(h - (pct * (h - 1))))
        for x = 1, box.width, 2 do
            plot_pixel(box, x, y, self.grid)
        end
    end
end

function M:draw_series(samples, field, color)
    local box = self.box
    local w = box.width
    local h = box.height
    if #samples == 0 then return end

    local samples_per_pixel = self.total_samples / w
    local prev_x, prev_y

    for px = 1, w do
        -- Columns map right-to-left to age in samples.
        -- Rightmost column (px = w) shows the newest sample.
        local age_pixels = w - px
        local end_idx = #samples - math.floor(age_pixels * samples_per_pixel)
        local start_idx = end_idx - math.max(1, math.floor(samples_per_pixel)) + 1
        if start_idx < 1 then start_idx = 1 end
        if end_idx >= 1 and end_idx <= #samples and start_idx <= end_idx then
            local sum, count = 0, 0
            for i = start_idx, end_idx do
                local v = samples[i][field]
                if v then sum = sum + v; count = count + 1 end
            end
            if count > 0 then
                local avg = sum / count
                if avg < 0 then avg = 0 end
                if avg > 1 then avg = 1 end
                local y = math.floor(h - avg * (h - 1) + 0.5)
                if y < 1 then y = 1 end
                if y > h then y = h end
                if prev_x then
                    plot_line(box, prev_x, prev_y, px, y, color)
                else
                    plot_pixel(box, px, y, color)
                end
                prev_x, prev_y = px, y
            end
        end
    end
end

function M:render(samples)
    self:clear()
    self:draw_grid()
    self:draw_series(samples, "critical_fill", self.critical_color)
    self:draw_series(samples, "general_fill", self.general_color)
    self.box:render()
end

function M:dimensions()
    return self.box.width, self.box.height
end

return M
