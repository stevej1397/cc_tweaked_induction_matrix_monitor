-- Auto-launches the monitor program on boot.
-- If it crashes, prints the error and drops to shell instead of looping.
print("Induction Matrix Monitor: starting...")
local ok, err = pcall(function() shell.run("monitor") end)
if not ok then
    term.setTextColor(colors.red)
    print("monitor exited with error:")
    print(err)
    term.setTextColor(colors.white)
    print("\nFix config.lua then reboot, or run 'check' to diagnose.")
end
