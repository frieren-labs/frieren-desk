# Frieren Desk

Una Frieren chibi que vive en tu escritorio de Hyprland. La arrastrás donde
quieras, le hacés clic y se abre una burbuja de chat conectada a
[opencode](https://opencode.ai): le pedís algo y lo hace sobre el sistema
(leer, editar archivos, correr comandos).

```
   ╭──────────────────────────╮
   │ Frieren   pensando…   + ✕│
   │  ┌────────────────────┐  │
   │  │ decime cuánto disco│  │
   │  │ libre queda        │  │
   │  └────────────────────┘  │
   │  ● df -h /               │
   │    /dev/nvme0n1p2 42%    │
   │  Te quedan 213 GB.       │
   │  ┌──────────────────┐ →  │
   │  │ pedime algo…     │    │
   ╰──────────────────────────╯
```

## Qué hace

- Sprite chibi pixel-art con animación idle, arrastrable y con posición persistente.
- Chat con streaming de la respuesta y bitácora de cada comando ejecutado
  (comando + salida real), más los errores tal cual vienen del proveedor.
- Contexto de conversación persistente: el session ID de opencode se guarda en
  `~/.local/state/frieren/state.json`.
- Usa la auth que ya tenés configurada en opencode. No hay ninguna API key
  escrita en el código.
- Lista negra de comandos destructivos y de lectura de secretos, definida en el
  agente de opencode.

## Requisitos

- Hyprland (o cualquier compositor con `wlr-layer-shell`).
- [Quickshell](https://quickshell.org) 0.3 o superior, binario `qs`.
- [opencode](https://opencode.ai) v2 con al menos un proveedor autenticado
  (`opencode auth list`).
- Qt 6 con `QtQuick.Controls`.

## Instalación

```bash
git clone https://github.com/jd-apprentice/frieren-desk
cd frieren-desk
./install.sh
```

El script copia:

- `quickshell/frieren/` → `~/.config/quickshell/frieren/`
- `opencode/agents/frieren.md` → `~/.config/opencode/agents/frieren.md`

Después enganchá el atajo y el autostart en tu config de Hyprland:

```lua
-- ~/.config/hypr/dms/binds-user.lua  (DankMaterialShell)
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c frieren ipc call frieren toggle"))

-- ~/.config/hypr/hyprland.lua
hl.on("hyprland.start", function()
	hl.exec_cmd("qs -c frieren -n")
end)
```

Sin DankMaterialShell: copiá `hypr/frieren.lua` a `~/.config/hypr/` y agregá
`require("frieren")` al final de `hyprland.lua`.

Arrancar a mano:

```bash
qs -c frieren -d
qs -c frieren ipc call frieren toggle
```

## Uso

| Acción | Cómo |
| --- | --- |
| Abrir o cerrar el chat | clic en la mascota, o `SUPER + SHIFT + R` |
| Moverla | arrastrala con el mouse |
| Conversación nueva | botón `+` en el header |
| Cortar una ejecución | botón `■` (mientras trabaja) |
| Cerrar el chat | `Esc` o `✕` |

IPC:

```bash
qs -c frieren ipc call frieren toggle
qs -c frieren ipc call frieren ask "cuánto espacio libre hay en /"
qs -c frieren ipc call frieren fresh
qs -c frieren ipc call frieren stop
qs -c frieren ipc call frieren hide
```

## Seguridad

La mascota ejecuta comandos de verdad. El freno está en el agente
(`~/.config/opencode/agents/frieren.md`), que corre en modo headless con estas
reglas de deny:

- escalada: `sudo`, `doas`, `su`
- borrado: `rm -rf /`, `rm -rf ~`, `rm -rf $HOME`, `rm -rf .*`
- discos: `mkfs*`, `dd of=/dev/*`, redirecciones a `/dev/sd*` y `/dev/nvme*`
- apagado: `shutdown`, `reboot`, `poweroff`, `halt`, `systemctl poweroff|reboot|halt`
- ejecución remota: `*| sh`, `*| bash`, `*|sh`, `*|bash`
- secretos: `~/.ssh/**`, `~/.gnupg/**`, `~/.aws/**`, `**/.env`, `**/*.pem`,
  `~/.local/share/opencode/auth.json`

Es una lista negra, no un sandbox: un comando destructivo que no matchee ningún
patrón va a pasar. Si querés más control, cambiá la regla general a
`effect: ask` en el agente y usá opencode desde la TUI, o sacá `bash` de los
permitidos y dejá que solo edite archivos.

Tampoco hay confirmación por comando en la UI: lo que ves es la bitácora
después de ejecutado. Está pensado para una máquina personal, no para un
servidor compartido.

## Cómo funciona

Cada mensaje ejecuta:

```bash
opencode run --format json --model <modelo> --agent frieren --session <id> "<mensaje>"
```

`shell.qml` corre ese proceso y parsea el NDJSON que emite:

- `text`: se muestra como respuesta y se actualiza en vivo.
- `tool_use`: se muestra como bloque con comando y salida.
- `error`: se muestra como aviso (por ejemplo, cuota agotada del proveedor).

Detalles que costaron encontrar y están resueltos en el código:

- El `stdin` del proceso se cierra con `< /dev/null`. Si opencode ve un pipe
  abierto espera EOF y se queda colgado.
- La `PanelWindow` de la mascota arranca en 500x500 antes de que el compositor
  configure la superficie, así que la posición se aplica recién cuando
  `petWin.screen` existe.
- La ventana es de pantalla completa con `mask: Region { item: hitArea }`, así
  el resto del escritorio sigue clickeable y la mascota puede moverse sin pelear
  con los márgenes del compositor.
- Los roles del modelo no llenan propiedades homónimas de un delegate: se
  bindean explícitamente.

## Personalización

- **Modelo**: `modelName` en `quickshell/frieren/shell.qml` y `model` en
  `opencode/agents/frieren.md`. Tienen que coincidir con un proveedor que tengas
  autenticado.
- **Sprite**: reemplazá `quickshell/frieren/assets/frieren-chibi.png` (PNG con
  transparencia, idealmente proporción 0.89:1).
- **Tamaño**: `width` y `height` en `components/PetSprite.qml`.
- **Persona**: el cuerpo del markdown en `opencode/agents/frieren.md`.
- **Colores**: se leen de `~/.cache/dms/dms-colors.json` (matugen de
  DankMaterialShell) y si no existen usan un fallback oscuro.
- **Teclado**: el chat pide foco con `WlrKeyboardFocus.OnDemand`. Si tu
  compositor no le da bola, cambiá a `Exclusive` en `shell.qml`.

## Estructura

```
quickshell/frieren/
├── shell.qml                 # ventanas, backend de opencode, estado, IPC
├── components/
│   ├── PetSprite.qml         # sprite, animación, drag
│   ├── ChatPanel.qml         # burbuja de chat
│   └── MessageBubble.qml     # mensajes y bloques de tool
├── assets/
│   ├── frieren-chibi.png     # sprite final, fondo transparente
│   └── frieren-chibi-raw.webp
└── README.md                 # notas de la config instalada
opencode/agents/frieren.md    # persona y permisos
hypr/frieren.lua              # keybind + autostart
install.sh
```

## Licencia

MIT. El personaje es de Sousou no Frieren (Kanehito Yamada / Tsukasa Abe); este
repo solo contiene código y un sprite generado como fan art.
