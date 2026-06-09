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
