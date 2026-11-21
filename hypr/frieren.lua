-- Frieren, desktop assistant.
-- Copy this file to ~/.config/hypr/frieren.lua and add
-- require("frieren") at the end of your hyprland.lua.
--
-- If you use DankMaterialShell, you can put the bind directly in
-- ~/.config/hypr/dms/binds-user.lua (it loads automatically) and skip the require.

hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))

hl.on("hyprland.start", function()
	hl.exec_cmd("qs -c frieren -n")
end)
