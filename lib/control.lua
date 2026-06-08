local M = {}
M.__index = M

function M.new(cfg)
    local self = setmetatable({}, M)
    self.cfg = cfg
    -- Default to "closed" so a fresh boot starts safe (no power flowing past critical).
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
    self.cg_open = update_gate(self.cg_open, critical_fill,
        cfg.critical_open_at, cfg.critical_close_at)
    self.gs_open = update_gate(self.gs_open, general_fill,
        cfg.general_open_at, cfg.general_close_at)
    self:apply_redstone()
end

function M:apply_redstone()
    local cfg = self.cfg
    local high_opens = cfg.gate_signal ~= "low_opens"
    local function signal(open) if high_opens then return open else return not open end end
    if cfg.critical_to_general_side then
        redstone.setOutput(cfg.critical_to_general_side, signal(self.cg_open))
    end
    if cfg.general_to_sink_side then
        redstone.setOutput(cfg.general_to_sink_side, signal(self.gs_open))
    end
end

function M:close_all()
    self.cg_open = false
    self.gs_open = false
    self:apply_redstone()
end

function M:state()
    return {cg_open = self.cg_open, gs_open = self.gs_open}
end

return M
