# Sprite prompt (poses nuevas)

Prompt adaptado del original (6 poses, ChatGPT) para generar poses nuevas de a
pares manteniendo al personaje consistente. Referencia visual: usar
`quickshell/frieren/assets/poses/idle.png` como imagen adjunta.

## ES

Usá la imagen adjunta como referencia exacta del personaje y del estilo.

Generá una HOJA DE SPRITES de 2 columnas por 1 fila, en 1024x512, con 2 celdas iguales de 512x512. Sin líneas de división, sin marcos, sin texto, sin números, sin títulos y sin etiquetas. Las 2 celdas van pegadas, sin espacios entre ellas.

FONDO: magenta puro #FF00FF, plano y uniforme en toda la imagen. No uses otro color de fondo, ni degradados, ni sombras.

PERSONAJE (idéntico en las 2 celdas): Frieren chibi fan art, pixel art. Pelo blanco plateado muy largo en dos colas con moños dorados, orejas de elfo, ojos verdes, túnica blanca y dorada con gema roja en el cuello, bastón de madera con medialuna dorada y gema roja en la punta. Proporciones chibi, cabeza grande. Mismo tamaño, mismo encuadre, cuerpo completo, centrada, mirando al frente y con los pies sobre la misma línea imaginaria en ambas celdas.

POSES, en este orden exacto (izquierda a derecha):
1. celebrate: festejando de alegría, ambos brazos en alto (el bastón en la mano derecha levantada), ojos cerrados en curva, gran sonrisa, pequeño salto.
2. reading: leyendo tranquila, un grimorio grande de tapas marrones abierto que sostiene con ambas manos, mirada baja hacia el libro, expresión concentrada (sin bastón a la vista).

REGLAS: no cambies el estilo, la paleta, el grosor de línea, las proporciones ni el tamaño del personaje. No agregues sombras en el piso, decoraciones, marcos ni objetos extra (salvo el grimorio de la celda 2). No escribas texto en ninguna parte.
Si no obedece bien el layout, esta versión en inglés suele funcionar mejor:

## EN

Use the attached image as the exact character and style reference.

Create a SPRITE SHEET with 2 columns and 1 row, 1024x512, two equal 512x512 cells. No dividers, no grid lines, no frames, no text, no numbers, no labels, no title. The cells must touch each other with no gaps.

BACKGROUND: flat pure magenta #FF00FF across the entire image. No other background color, no gradients, no shadows.

CHARACTER (identical in both cells): Frieren chibi fan art, pixel art. Very long silver-white hair in twin tails with gold bows, pointed elf ears, green eyes, white and gold mage robe with a red gem at the collar, wooden staff topped with a gold crescent and a red gem. Chibi proportions, big head. Same size, same framing, full body, centered, facing the viewer, feet on the same imaginary baseline in both cells.

POSES in this exact order (left to right):
1. celebrate: cheering with joy, both arms raised (staff in the raised right hand), eyes closed in a happy curve, big smile, tiny jump.
2. reading: calmly reading, a large open brown grimoire held with both hands, eyes looking down at the book, focused expression (no staff visible).

RULES: do not change the art style, palette, line weight, proportions or character size. Do not add floor shadows, decorations, frames or extra objects (except the cell 2 grimoire). Do not write text anywhere.

## Post-proceso (magenta -> sprite 228x256 con transparencia)

```bash
# 1. partir la hoja por la mitad (ajustar W্যা según identify)
magick sheet.webp -crop ${HALF}x${H}+0+0 +repage cell-celebrate.png
magick sheet.webp -crop ${HALF}x${H}+${HALF}+0 +repage cell-reading.png
# 2. chroma key + encuadre (subir fuzz si queda halo, 12-20%)
magick cell-celebrate.png -fuzz 18% -transparent "#FF00FF" -trim +repage \
  -resize 228x256 -background none -gravity center -extent 228x256 celebrate.png
# 3. registrar ojos para el blink en quickshell/frieren/assets/poses/poses.json
#    (eyes: [] si los tiene cerrados; skin: muestrear la mejilla)
```
