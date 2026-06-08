-- Induction Matrix Monitor installer.
--
-- Usage on a CC:Tweaked computer:
--   wget run https://raw.githubusercontent.com/stevej1397/cc_tweaked_induction_matrix_monitor/main/installer.lua
--
-- Flags:
--   --force   overwrite config.lua with defaults (otherwise existing config is kept)
--   --update  alias for default behavior; used by update.lua

local VERSION = "0.1.0"
local REPO_BASE = "https://raw.githubusercontent.com/stevej1397/cc_tweaked_induction_matrix_monitor/main/"
local PIXELBOX_URL = "https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/master/pixelbox_lite.lua"

local FILES = {
    "monitor.lua",
    "startup.lua",
    "check.lua",
    "update.lua",
    "lib/util.lua",
    "lib/peripherals.lua",
    "lib/history.lua",
    "lib/control.lua",
    "lib/graph.lua",
    "lib/render.lua",
    "README.md",
}

local args = {...}
local force = false
for _, a in ipairs(args) do
    if a == "--force" then force = true end
end

if not http then
    error("HTTP API is disabled in this CC:Tweaked install. Enable it in the mod config first.")
end

local function header(s)
    term.setTextColor(colors.cyan)
    print(s)
    term.setTextColor(colors.white)
end

local function ok(s)
    term.setTextColor(colors.lime)
    write("  ok   ")
    term.setTextColor(colors.white)
    print(s)
end

local function fail(s)
    term.setTextColor(colors.red)
    write("  FAIL ")
    term.setTextColor(colors.white)
    print(s)
end

local function download(url, dest)
    local response, err = http.get(url)
    if not response then
        return false, tostring(err)
    end
    local status = response.getResponseCode and response.getResponseCode() or 200
    if status ~= 200 then
        response.close()
        return false, "HTTP " .. tostring(status)
    end
    local data = response.readAll()
    response.close()

    local parent = fs.getDir(dest)
    if parent and parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
    local f = fs.open(dest, "w")
    if not f then return false, "cannot open " .. dest end
    f.write(data)
    f.close()
    return true
end

header("Induction Matrix Monitor installer v" .. VERSION)
print("Source: " .. REPO_BASE)
print("")

header("[1/3] downloading program files")
local errors = 0
for _, file in ipairs(FILES) do
    local success, err = download(REPO_BASE .. file, file)
    if success then
        ok(file)
    else
        fail(file .. "  (" .. tostring(err) .. ")")
        errors = errors + 1
    end
end

print("")
header("[2/3] downloading pixelbox_lite")
local success, err = download(PIXELBOX_URL, "pixelbox_lite.lua")
if success then
    ok("pixelbox_lite.lua")
else
    fail("pixelbox_lite.lua  (" .. tostring(err) .. ")")
    errors = errors + 1
end

print("")
header("[3/3] config.lua")
if fs.exists("config.lua") and not force then
    ok("config.lua exists -- keeping your edits")
    local s, e = download(REPO_BASE .. "config.lua", "config.example.lua")
    if s then
        ok("config.example.lua  (fresh defaults for reference)")
    else
        fail("config.example.lua  (" .. tostring(e) .. ")")
    end
else
    local s, e = download(REPO_BASE .. "config.lua", "config.lua")
    if s then
        ok("config.lua  (defaults installed -- EDIT BEFORE RUNNING)")
    else
        fail("config.lua  (" .. tostring(e) .. ")")
        errors = errors + 1
    end
end

print("")
if errors > 0 then
    term.setTextColor(colors.red)
    print(errors .. " file(s) failed to download. Fix network/HTTP API access and retry.")
    term.setTextColor(colors.white)
    return
end

term.setTextColor(colors.lime)
print("Install complete.")
term.setTextColor(colors.white)
print("")
print("Next steps:")
print("  1. Edit config.lua: set peripheral names and redstone sides")
print("  2. Run 'check' to validate everything is wired correctly")
print("  3. Reboot, or run 'monitor' to start")
print("")
header("Running 'check' now...")
print("")
shell.run("check")
