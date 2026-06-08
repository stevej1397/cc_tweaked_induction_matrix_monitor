local M = {}

local REQUIRED_METHODS = {"getEnergy", "getMaxEnergy", "getLastInput", "getLastOutput"}

function M.find_matrix(name)
    if not name or name == "" then return nil, "no peripheral name configured" end
    local p = peripheral.wrap(name)
    if not p then return nil, "peripheral not found: " .. tostring(name) end
    for _, method in ipairs(REQUIRED_METHODS) do
        if type(p[method]) ~= "function" then
            return nil, string.format("peripheral '%s' is missing method '%s' (not an induction matrix port?)", name, method)
        end
    end
    return p
end

function M.find_monitor(name)
    if not name or name == "" then return nil, "no monitor name configured" end
    local p = peripheral.wrap(name)
    if not p then return nil, "monitor not found: " .. tostring(name) end
    if type(p.setTextScale) ~= "function" or type(p.getSize) ~= "function" then
        return nil, "peripheral '" .. name .. "' is not a monitor"
    end
    return p
end

function M.read_matrix(p)
    if not p then return nil, "matrix not wrapped" end
    local ok, energy = pcall(p.getEnergy)
    if not ok or not energy then return nil, "getEnergy failed" end
    local ok2, max = pcall(p.getMaxEnergy)
    if not ok2 or not max or max <= 0 then return nil, "getMaxEnergy failed" end
    local _, input = pcall(p.getLastInput)
    local _, output = pcall(p.getLastOutput)
    return {
        energy = energy,
        max = max,
        fill = energy / max,
        input = input or 0,
        output = output or 0,
        net = (input or 0) - (output or 0),
    }
end

local VALID_SIDES = {top = true, bottom = true, left = true, right = true, front = true, back = true}

function M.valid_side(s)
    return VALID_SIDES[s] == true
end

return M
