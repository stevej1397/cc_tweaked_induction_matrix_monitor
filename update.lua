-- Pulls the latest installer and re-runs it. Existing config.lua is preserved.
local INSTALLER_URL = "https://raw.githubusercontent.com/stevej1397/cc_tweaked_induction_matrix_monitor/main/installer.lua"
print("Fetching latest installer...")
shell.run("wget", "run", INSTALLER_URL, "--update")
