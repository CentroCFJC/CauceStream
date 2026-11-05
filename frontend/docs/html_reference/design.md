# DESIGN.md — CAUCE · Circuito Interactivo

> Sistema de diseño derivado del manual de marca **MANUAL_CAUCE.pdf**.
> Los valores marcados con ⚠️ **no están rotulados en el manual** y fueron estimados visualmente; conviene confirmarlos con el equipo de marca.

---

## 1. Identidad

**Nombre:** CAUCE — Circuito Interactivo
**Subtítulo / descriptor:** Circuito Interactivo

**Propósito:** proyecto expositivo de divulgación orientado a públicos amplios y ciudadanos. No es un dispositivo académico tradicional ni un proceso de apropiación en sentido estricto. La divulgación se entiende como un **ejercicio social y ciudadano** cuyo objetivo es **hacer visible el conocimiento universitario** mediante lenguajes **accesibles, sensibles e interactivos**.

**Personalidad visual:** cálida, orgánica, fluida (la metáfora del "cauce"/río), lúdica y tecnológica a la vez. Colores terrosos y saturados, formas curvas continuas, tipografía ancha y contundente.

**Tono de voz (a partir de los lemas del manual):**
- Frases cortas, afirmativas y poéticas.
- Se resalta la palabra clave en color de acento.
- Ejemplos:
  - "Un cauce no contiene: **transforma.**"
  - "Aquí el conocimiento **toma movimiento.**"

---

## 2. Paleta de colores

Paleta general de la marca.

| Rol | Nombre sugerido | HEX | Notas |
|---|---|---|---|
| Primario / acento | Naranja | `#ea580c` | Color protagonista; logo principal, énfasis en titulares |
| Secundario | Marrón | `#6d432d` | Tono terroso |
| Secundario oscuro | Vino / granate | ⚠️ `#600a0a` aprox. | En el manual aparece rotulado `6d432d` por error de duplicado; el tono visible es un granate oscuro (fondo de la sección tipográfica, textura oscura) |
| Secundario cálido | Amarillo | `#f2c744` | Formas decorativas, texturas |
| Secundario frío | Azul petróleo | `#2b8190` | Logo alterno, formas, texturas |
| Fondo claro | Crema | `#faf6db` | Fondo principal de tarjetas y lienzos claros |
| Fondo oscuro | Verde petróleo oscuro | ⚠️ `#17404a` aprox. | Fondo de páginas oscuras del manual; no está rotulado |

### Tokens CSS sugeridos

```css
:root {
  --cauce-orange:   #ea580c;
  --cauce-brown:    #6d432d;
  --cauce-maroon:   #600a0a; 
  --cauce-yellow:   #f2c744;
  --cauce-teal:     #2b8190;
  --cauce-cream:    #faf6db; 
}
```

### Uso recomendado
- **Fondos:** crema (`--cauce-cream`) para superficies claras; verde petróleo oscuro o granate para superficies oscuras.
- **Texto sobre fondo claro:** verde petróleo oscuro (títulos) y tonos oscuros neutros.
- **Texto sobre fondo oscuro:** crema.
- **Acento:** naranja para destacar palabras clave de los lemas.
- Mantener un contraste legible entre texto y fondo.

---

## 3. Tipografía

Tres familias (todas disponibles en Google Fonts):

| Familia | Peso / estilo | Rol sugerido* |
|---|---|---|
| 
| **Space Grotesk** | Regular | Titulos, Subtítulos, etiquetas |
| **Plus Jakarta Sans** | Regular / Bold | Párrafos y texto corrido |

\*El manual muestra las tres familias con su alfabeto completo (incluida la **ñ**) pero no asigna roles explícitos; los roles anteriores se deducen de cómo aparecen en las piezas.

### Escala sugerida

| Nivel | Familia | Tamaño | Notas |
|---|---|---|---|
| Display / lema | Special Gothic Expanded One | 40–64 px | Interlineado ajustado (~1.1); palabra clave en naranja |
| H1 | Special Gothic Expanded One | 32–40 px | |
| H2 | Special Gothic Expanded One | 24–28 px | |
| Subtítulo / etiqueta | Space Grotesk | 16–20 px | |
| Cuerpo | Plus Jakarta Sans | 16–18 px | Interlineado ~1.5; negrita para frases clave |
| Pie / legal | Plus Jakarta Sans | 12–14 px | |

```css
:root {
  --font-display: "Special Gothic Expanded One", sans-serif;
  --font-ui:      "Space Grotesk", sans-serif;
  --font-body:    "Plus Jakarta Sans", sans-serif;
}
```

---

## 4. Logotipo

### Composición
Símbolo de trazo fluido entrelazado (tipo laberinto/cauce) + wordmark **CAUCE** en bloque (CAU / CE) + descriptor **"Circuito Interactivo"** en pequeño.

### Versiones
Tres formatos, cada uno en tres colores:

| Formato | Contenido |
|---|---|
| Horizontal completo | Símbolo + wordmark + descriptor |
| Solo wordmark | CAUCE |
| Solo símbolo | Símbolo + descriptor |

| Color | Fondo recomendado |
|---|---|
| Naranja `#ea580c` | Crema / fondos claros |
| Azul petróleo `#2b8190` | Crema / fondos claros |
| Negro | Crema / fondos claros (versión monocromática) |

Para fondos oscuros, usar la versión en crema/azul sobre fondo oscuro, como en el encabezado del manual (logo azul petróleo sobre crema).

### Usos incorrectos ❌
Según la sección "Usos incorrectos" del manual, **no**:
- Rotar o inclinar el logotipo.
- Aplicar sombras o efectos (degradados, relieves) al logotipo.
- Estirar, comprimir o deformar las proporciones (versión angosta o ancha).
- Cambiar los colores del logo por combinaciones no definidas, ni usarlo en un color que se pierda con el fondo.
- Alterar la posición o proporción entre símbolo, wordmark y descriptor.

*(Los usos incorrectos se interpretaron a partir de las miniaturas del manual.)*

---

## 5. Elementos gráficos

### 5.1 Formas
Formas **orgánicas, fluidas y continuas** que evocan un cauce: curvas en S, lazos tipo infinito (∞) y manchas redondeadas.
- Se usan como **máscaras de fotografías** (recortes ondulados sobre la imagen).
- Se superponen a las fotos como cintas de color (amarillo, azul petróleo, crema).
- Esquinas siempre redondeadas; evitar ángulos rectos duros.

### 5.2 Iconos por estaciones
Estilo: línea/silueta sólida y redondeada, en crema sobre fondo oscuro.

| Estación | Icono |
|---|---|
| VR | Gafas de realidad virtual |
| Repositorio | Carpeta |
| Táctil | Mano tocando |
| Audio | Auriculares |
| AR | Cubo 3D dentro de marco de enfoque |
| Tótem | Tótem / pantalla vertical con base |

### 5.3 Texturas
Patrones repetitivos tonales (tono sobre tono) en cuatro colores base, con tres variantes de patrón cada uno:

| Color base | Variantes |
|---|---|
| Azul petróleo | Ondas ovaladas · zigzag ondulado · mezcla |
| Naranja | Ondas ovaladas · zigzag ondulado · mezcla |
| Amarillo | Ondas ovaladas · zigzag ondulado · mezcla |
| Granate | Ondas ovaladas · zigzag ondulado · mezcla |

Uso: fondos de secciones y bandas decorativas; mantener el patrón sutil (bajo contraste) para no competir con el contenido. El fondo oscuro del manual usa este patrón en verde petróleo.

---

## 6. Componentes y patrones de composición

### Tarjetas
- Fondo crema `#faf6db`.
- Esquinas muy redondeadas (≈ 24–32 px).
- Título en azul petróleo/oscuro; palabra clave en naranja; texto corrido en tono oscuro.
- Pueden incluir indicadores de carrusel (puntos) en la parte inferior.

### Fotografía
- Fotos en **blanco y negro / escala de grises** con grano, combinadas con formas de color (amarillo con textura de brillo, azul petróleo).
- También se usan fotos a color recortadas con máscara orgánica sobre fondo crema/beige.
- Temática: personas interactuando con VR/AR y exposiciones.

### Titulares sobre imagen
- Texto en crema/blanco con la **palabra final** en naranja (p. ej. "transforma.").
- Alineación izquierda, tipografía de display.

### Contenedores
- Bloques redondeados sobre fondos oscuros; secciones con cortes curvos (arcos y semicírculos).


---

## 7. Espaciado y forma (sugerido)


```css
:root {
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 16px;
  --space-4: 24px;
  --space-5: 40px;
  --space-6: 64px;

  --radius-sm: 12px;
  --radius-md: 24px;
  --radius-lg: 32px;
  --radius-pill: 999px;
}
```