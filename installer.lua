-- Induction Matrix Monitor installer.
--
-- Usage on a CC:Tweaked computer:
--   wget run https://raw.githubusercontent.com/stevej1397/cc_tweaked_induction_matrix_monitor/main/installer.lua
--
-- Flags:
--   --force        overwrite config.lua and re-run interactive setup
--   --reconfigure  re-run interactive setup even if config.lua exists
--   --no-setup     skip the interactive setup step
--   --update       used by update.lua (no-op marker; preserves config)

local VERSION = "0.6.0"
local REPO_BASE = "https://raw.githubusercontent.com/stevej1397/cc_tweaked_induction_matrix_monitor/main/"
local PIXELBOX_URL = "https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/master/pixelbox_lite.lua"
local PIXELUI_URL  = "https://raw.githubusercontent.com/Shlomo1412/PixelUI-v2/main/pixelui.lua"
local SHREKBOX_URL = "https://codeberg.org/ShreksHellraiser/shrekbox/raw/branch/main/shrekbox.lua"

local FILES = {
    "monitor.lua",
    "startup.lua",
    "check.lua",
    "update.lua",
    "setup.lua",
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
local reconfigure = false
local skip_setup = false
for _, a in ipairs(args) do
    if a == "--force" then force = true; reconfigure = true end
    if a == "--reconfigure" then reconfigure = true end
    if a == "--no-setup" then skip_setup = true end
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
header("[2/3] downloading external dependencies")

local function download_external(url, dest)
    local success, err = download(url, dest)
    if success then
        ok(dest)
    else
        fail(dest .. "  (" .. tostring(err) .. ")")
        errors = errors + 1
    end
end

download_external(PIXELBOX_URL, "pixelbox_lite.lua")  -- still used for the monitor graph
download_external(PIXELUI_URL,  "pixelui.lua")        -- GUI library for setup wizard
download_external(SHREKBOX_URL, "shrekbox.lua")       -- pixelui's teletext renderer

print("")
header("[3/3] config.lua")
local s, e = download(REPO_BASE .. "config.lua", "config.example.lua")
if s then
    ok("config.example.lua  (fresh defaults for reference)")
else
    fail("config.example.lua  (" .. tostring(e) .. ")")
end

local need_setup
if force then
    if fs.exists("config.lua") then
        if fs.exists("config.lua.bak") then fs.delete("config.lua.bak") end
        fs.copy("config.lua", "config.lua.bak")
        fs.delete("config.lua")
        ok("config.lua backed up to config.lua.bak (--force)")
    end
    need_setup = true
elseif reconfigure then
    need_setup = true
elseif not fs.exists("config.lua") then
    need_setup = true
    ok("no config.lua yet -- will run interactive setup")
else
    need_setup = false
    ok("config.lua exists -- keeping your edits (use --reconfigure to redo)")
end

print("")
if errors > 0 then
    term.setTextColor(colors.red)
    print(errors .. " file(s) failed to download. Fix network/HTTP API access and retry.")
    term.setTextColor(colors.white)
    return
end

term.setTextColor(colors.lime)
print("Files installed.")
term.setTextColor(colors.white)
print("")

if need_setup and not skip_setup then
    header("Running interactive setup...")
    print("")
    shell.run("setup")
    print("")
    header("Running 'check' to verify...")
    print("")
    shell.run("check")
else
    if skip_setup and need_setup then
        print("Setup skipped (--no-setup). Run 'setup' before starting.")
    else
        header("Running 'check'...")
        print("")
        shell.run("check")
    end
end

print("")
print("To reconfigure later: run 'setup'")
print("To pull updates:      run 'update'")
print("To start the monitor: run 'monitor' (or reboot)")
