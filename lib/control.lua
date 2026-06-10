local peripherals_lib = require("lib.peripherals")

local M = {}
M.__index = M

function M.new(cfg)
    local self = setmetatable({}, M)
    self.cfg = cfg

    -- Normalize each gate to a list of {peripheral, side}.
    self.cg_outputs = peripherals_lib.compile_outputs(
        cfg.critical_to_general_outputs or cfg.critical_to_general_side)
    self.sps_outputs = peripherals_lib.compile_outputs(
        cfg.general_to_sps_outputs)
    self.gs_outputs = peripherals_lib.compile_outputs(
        cfg.general_to_sink_outputs or cfg.general_to_sink_side)

    -- All gates default closed on boot so a fresh start is safe.
    self.cg_open = false
    self.sps_open = false
    self.gs_open = false
    self:apply_redstone()
    return self
end

-- Plain single-sided gate (no critical dependency).
local function update_simple_gate(currently_open, fill, open_at, close_at)
    if currently_open then
        if fill <= close_at then return false end
        return true
    else
        if fill >= open_at then return true end
        return false
    end
end

-- Compound gate: opens only when BOTH its own fill is above threshold AND
-- the critical matrix is also above its threshold. Closes the moment
-- either falls below its close threshold.
local function update_compound_gate(currently_open,
                                    general_fill, critical_fill,
                                    gen_open_at, gen_close_at,
                                    crit_open_at, crit_close_at)
    if currently_open then
        if general_fill <= gen_close_at
           or critical_fill <= crit_close_at then
            return false
        end
        return true
    else
        if general_fill >= gen_open_at
           and critical_fill >= crit_open_at then
            return true
        end
        return false
    end
end

function M:update(critical_fill, general_fill)
    local cfg = self.cfg

    -- Critical -> General: simple, fires off the critical fill.
    self.cg_open = update_simple_gate(self.cg_open, critical_fill,
        cfg.critical_open_at, cfg.critical_close_at)

    -- General -> SPS: simple. SPS is treated as a useful consumer (not a
    -- waste path), so we feed it whenever the general matrix has enough
    -- buffer -- no critical-fill dependency.
    self.sps_open = update_simple_gate(self.sps_open, general_fill,
        cfg.general_sps_open_at, cfg.general_sps_close_at)

    -- General -> Sink: compound. Sink only opens when the general matrix
    -- is very full AND the critical matrix is also topped up -- a true
    -- overflow path that we never want to dump into prematurely.
    self.gs_open = update_compound_gate(self.gs_open,
        general_fill, critical_fill,
        cfg.general_open_at, cfg.general_close_at,
        cfg.critical_open_at, cfg.critical_close_at)

    self:apply_redstone()
end

function M:apply_redstone()
    local high_opens = self.cfg.gate_signal ~= "low_opens"
    local function signal(open) if high_opens then return open else return not open end end
    for _, out in ipairs(self.cg_outputs) do
        peripherals_lib.set_output(out, signal(self.cg_open))
    end
    for _, out in ipairs(self.sps_outputs) do
        peripherals_lib.set_output(out, signal(self.sps_open))
    end
    for _, out in ipairs(self.gs_outputs) do
        peripherals_lib.set_output(out, signal(self.gs_open))
    end
end

function M:close_all()
    self.cg_open = false
    self.sps_open = false
    self.gs_open = false
    self:apply_redstone()
end

function M:state()
    return {
        cg_open = self.cg_open,
        sps_open = self.sps_open,
        gs_open = self.gs_open,
        cg_outputs = self.cg_outputs,
        sps_outputs = self.sps_outputs,
        gs_outputs = self.gs_outputs,
    }
end

return M
