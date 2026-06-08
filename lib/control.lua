local peripherals_lib = require("lib.peripherals")

local M = {}
M.__index = M

function M.new(cfg)
    local self = setmetatable({}, M)
    self.cfg = cfg

    -- Normalize each gate to a list of {peripheral, side}.
    -- Accepts both the new "_outputs" list schema and the legacy "_side"
    -- single-string schema, with the list taking priority.
    self.cg_outputs = peripherals_lib.compile_outputs(
        cfg.critical_to_general_outputs or cfg.critical_to_general_side)
    self.gs_outputs = peripherals_lib.compile_outputs(
        cfg.general_to_sink_outputs or cfg.general_to_sink_side)

    -- Default to "closed" so a fresh boot starts safe.
    self.cg_open = false
    self.gs_open = false
    self:apply_redstone()
    return self
end

local function update_gate(currently_open, fill, open_threshold, close_threshold)
    if currently_open then
        if fill <= close_threshold then return false end
        return true
    else
        if fill >= open_threshold then return true end
        return false
    end
end

function M:update(critical_fill, general_fill)
    local cfg = self.cfg

    -- Critical -> General: opens when the critical matrix is at threshold.
    self.cg_open = update_gate(self.cg_open, critical_fill,
        cfg.critical_open_at, cfg.critical_close_at)

    -- General -> Sink: opens only when BOTH conditions are met --
    --   general matrix is at its open threshold, AND
    --   critical matrix is at its open threshold.
    -- Closes the moment either drops below its close threshold.
    -- That way we never bleed power to the sink while the critical
    -- matrix is still drawing.
    if self.gs_open then
        if general_fill <= cfg.general_close_at
           or critical_fill <= cfg.critical_close_at then
            self.gs_open = false
        end
    else
        if general_fill >= cfg.general_open_at
           and critical_fill >= cfg.critical_open_at then
            self.gs_open = true
        end
    end

    self:apply_redstone()
end

function M:apply_redstone()
    local high_opens = self.cfg.gate_signal ~= "low_opens"
    local function signal(open) if high_opens then return open else return not open end end
    for _, out in ipairs(self.cg_outputs) do
        peripherals_lib.set_output(out, signal(self.cg_open))
    end
    for _, out in ipairs(self.gs_outputs) do
        peripherals_lib.set_output(out, signal(self.gs_open))
    end
end

function M:close_all()
    self.cg_open = false
    self.gs_open = false
    self:apply_redstone()
end

function M:state()
    return {
        cg_open = self.cg_open,
        gs_open = self.gs_open,
        cg_outputs = self.cg_outputs,
        gs_outputs = self.gs_outputs,
    }
end

return M
