-- Frieren, asistente de escritorio.
-- Copiá este archivo como ~/.config/hypr/frieren.lua y agregá
-- require("frieren") al final de tu hyprland.lua.
--
-- Si usás DankMaterialShell, podés poner el bind directamente en
-- ~/.config/hypr/dms/binds-user.lua (que ya se carga solo) y omitir el require.

hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))

hl.on("hyprland.start", function()
	hl.exec_cmd("qs -c frieren -n")
end)
