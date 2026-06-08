local M = {}
M.__index = M

function M.load(path, max_samples)
    local self = setmetatable({}, M)
    self.path = path or "/history.dat"
    self.max = max_samples or 1440
    self.samples = {}
    if fs.exists(self.path) then
        local f = fs.open(self.path, "r")
        local data = f.readAll()
        f.close()
        local ok, decoded = pcall(textutils.unserialize, data)
        if ok and type(decoded) == "table" then
            self.samples = decoded
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

function M:save()
    local tmp = self.path .. ".tmp"
    local f = fs.open(tmp, "w")
    if not f then return false, "cannot open tmp file" end
    f.write(textutils.serialize(self.samples))
    f.close()
    if fs.exists(self.path) then fs.delete(self.path) end
    fs.move(tmp, self.path)
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
