local M = {}
M.__index = M

function M.load(path, max_samples)
    local self = setmetatable({}, M)
    self.path = path or "/history.dat"
    self.max = max_samples or 1440
    self.samples = {}
    self.load_error = nil
    self.load_status = "no history file yet"
    if fs.exists(self.path) then
        local f = fs.open(self.path, "r")
        if not f then
            self.load_error = "could not open " .. self.path
        else
            local data = f.readAll()
            f.close()
            if not data or data == "" then
                self.load_error = "history file is empty (" .. self.path .. ")"
            else
                local ok, decoded = pcall(textutils.unserialize, data)
                if ok and type(decoded) == "table" then
                    self.samples = decoded
                    self.load_status = string.format("loaded %d samples from %s",
                        #self.samples, self.path)
                elseif ok then
                    self.load_error = "history file did not contain a table"
                else
                    self.load_error = "unserialize failed: " .. tostring(decoded)
                end
            end
        end
    end
    -- Defensive trim in case max shrank
    while #self.samples > self.max do
        table.remove(self.samples, 1)
    end
    return self
end

function M:append(sample)
    self.samples[#self.samples + 1] = sample
    while #self.samples > self.max do
        table.remove(self.samples, 1)
    end
end

-- Save raises a Lua error on any failure so the caller (history_tick in
-- monitor.lua) can pcall it and surface the reason. Returning false from
-- here was too easy to silently ignore.
function M:save()
    local tmp = self.path .. ".tmp"
    local f, err = fs.open(tmp, "w")
    if not f then
        error("history save: cannot open " .. tmp .. ": " .. tostring(err), 0)
    end
    local ok, ser_err = pcall(function()
        f.write(textutils.serialize(self.samples))
        f.close()
    end)
    if not ok then
        pcall(function() f.close() end)
        error("history save: write failed: " .. tostring(ser_err), 0)
    end
    if fs.exists(self.path) then
        local ok_del = pcall(fs.delete, self.path)
        if not ok_del then
            error("history save: cannot delete old " .. self.path, 0)
        end
    end
    local ok_mv, mv_err = pcall(fs.move, tmp, self.path)
    if not ok_mv then
        error("history save: cannot move tmp to " .. self.path .. ": " .. tostring(mv_err), 0)
    end
    return true
end

function M:get()
    return self.samples
end

function M:count()
    return #self.samples
end

function M:clear()
    self.samples = {}
end

return M
