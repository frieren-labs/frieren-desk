# Frieren · mascota asistente

Chibi de Frieren en el escritorio con una burbuja de chat que habla con
`opencode` y puede modificar el sistema.

## Cómo se usa

- Arrastrala con el mouse: la posición se guarda en `~/.local/state/frieren/state.json`.
- Clic (sin arrastrar): abre o cierra el chat.
- `SUPER + SHIFT + R`: abre el chat desde cualquier lado.
- `Esc` o `✕`: cierra. `＋`: conversación nueva. El botón `■` corta la ejecución en curso.
- La conversación mantiene contexto entre reinicios: se guarda el session ID de opencode.

IPC útil:

```bash
qs -c frieren ipc call frieren toggle
qs -c frieren ipc call frieren ask "cuánto espacio libre hay en /"
qs -c frieren ipc call frieren fresh
qs -c frieren ipc call frieren stop
qs -c frieren ipc call frieren hide
```

## Cómo habla con el sistema

Cada mensaje ejecuta:

```bash
opencode run --format json --model opencode-go/deepseek-v4.1-flash \
  --agent frieren --session <id> "<mensaje>"
```

- Usa la auth ya configurada de opencode (`opencode auth list`). No hay ninguna
  API key escrita en este config.
- Los eventos JSON se parsean en `shell.qml`: texto del asistente, tool calls
  (comando + salida, visibles en el chat como bitácora) y errores.
- El agente vive en `~/.config/opencode/agents/frieren.md` y trae la lista negra:
  `sudo`, `doas`, `su`, `rm -rf /`, `rm -rf ~`, `mkfs`, `dd of=/dev/*`,
  `shutdown`, `reboot`, `poweroff`, `| sh`, `| bash`, y lectura de secretos
  (`~/.ssh`, `~/.gnupg`, `~/.aws`, `.env`, `*.pem`, `auth.json`).
- Para cambiar de modelo: editá `modelName` en `shell.qml` y `model` en el
  agent markdown, o pedile al agente que use otro proveedor.

## Archivos

```
~/.config/quickshell/frieren/
├── shell.qml                  # ventanas, backend de opencode, estado
├── components/
│   ├── PetSprite.qml          # sprite, animación idle, drag
│   ├── ChatPanel.qml          # burbuja de chat
│   └── MessageBubble.qml      # burbujas y bloques de tool
├── assets/frieren-chibi.png   # sprite (fondo transparente)
└── assets/frieren-chibi-raw.webp
```

Arranque automático: bloque al final de `~/.config/hypr/hyprland.lua`
(`qs -c frieren -n`). El `-n` evita duplicados.

## Detalles técnicos

- Ventana de la mascota: `PanelWindow` a pantalla completa, capa `Overlay`,
  `exclusionMode: Ignore` y `mask: Region { item: hitArea }`, así el resto del
  escritorio sigue clickeable. La posición es del item, no de la ventana, para
  que el drag no entre en loop con el compositor.
- El chat es otra `PanelWindow` chica que se ubica al lado de la mascota.
- `stdin` del proceso se cierra con `< /dev/null`: si opencode ve un pipe
  abierto espera EOF y se queda colgado.
- Cuando opencode termina con error de cuota, el mensaje aparece en el chat.
- Si el teclado no toma foco al abrir el chat, cambialo a
  `WlrKeyboardFocus.Exclusive` en `shell.qml` (bloquea el teclado global
  mientras esté abierto).

## Apagar / reiniciar

```bash
python3 - <<'EOF'
import os, glob, signal
for p in glob.glob('/proc/[0-9]*/cmdline'):
    try:
        a = [x.decode() for x in open(p,'rb').read().split(b'\0') if x]
    except OSError:
        continue
    if len(a) >= 3 and a[0].endswith('/qs') and a[1:3] == ['-c','frieren']:
        os.kill(int(p.split('/')[2]), signal.SIGTERM)
EOF

qs -c frieren            # primer plano, logs en stderr
qs -c frieren -d         # daemon
```
