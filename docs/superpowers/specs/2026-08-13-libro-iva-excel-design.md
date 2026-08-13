# Libro IVA Digital en Excel (.xlsx) — Diseño

**Fecha:** 2026-08-13
**Estado:** implementado · 6 tests nuevos + suite completa (160/160) verde · validado abriendo un .xlsx real con openpyxl · sin commitear (rama local)
**Rama:** `feat/libro-iva-excel`

## Objetivo

Agregar al módulo Exportables un botón **"Libro IVA Digital (Excel)"** que
descargue un `.xlsx` formateado, **espejo exacto** de los 4 TXT que se
importan a ARCA. Sirve para que la contadora revise, comprobante por
comprobante y con los totales cuadrados, exactamente lo que se va a
importar **antes** de subirlo a ARCA (los TXT son ilegibles a ojo).

## Valor

Único delta genuino sobre los CSV de IVA que ya existen: **reconciliación
pre-importación 1:1 con el TXT**. Los CSV actuales (`expIvaVentas`,
`expIvaCompras`) usan un alcance distinto (todas las facturas emitidas, no
solo las de producción que entran al TXT). Este Excel sale de las **mismas**
funciones de datos que el TXT, garantizando el espejo. Es higiene
contable / control de calidad, no una feature que mueva la aguja del negocio.

## Enfoque

**Elegido (A): generador xlsx en JS puro, reusando `zipStore`.**
Un `.xlsx` es un ZIP de XML. El ERP ya tiene `zipStore()` (JS puro, con
CRC32) y `descargarBytes()`. Cero dependencias externas, fiel al modelo
single-file/offline.

Descartados:
- **B) SheetJS** — ~500 KB de dependencia; rompe single-file/offline.
- **C) SpreadsheetML 2003 / tabla-HTML-como-.xls** — Excel tira warning de
  "el formato no coincide con la extensión"; estilos pobres.

## Componentes

### 1. `xlsxBuild(hojas)` — helper genérico (nuevo)
- Input: `[{nombre, filas, cols?}]`. Cada celda: primitivo (string/number) o
  `{v, t, s}` (valor, tipo `s|n`, estilo por nombre).
- Genera las partes XML del xlsx (`[Content_Types].xml`, `_rels/.rels`,
  `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/styles.xml`,
  `xl/worksheets/sheetN.xml`) usando `inlineStr` para textos (evita
  `sharedStrings`), y las pasa a `zipStore` → `Uint8Array`.
- Estilos fijos: header (negrita + fondo + borde + centrado, fila
  congelada), moneda `#,##0.00`, total (negrita + borde superior), texto.
- Fechas: string ya formateado `dd/mm/aaaa` (no serial), robusto y legible.

### 2. `libroIvaExcelHojas(ventas, compras, excluidos)` — puro (nuevo, testeable)
Arma las 3 hojas desde los arrays que devuelven `_lidVentasData` /
`_lidComprasData`:
- **Ventas**: fecha · tipo (label `cbteAfipInfo`) · comprobante (pv-nro) ·
  cliente · doc receptor · neto · IVA · alíc.% · total. NC/ND con signo
  (convención de `expIvaVentas`, así TOTALES = neto real). Fila TOTALES.
- **Compras**: fecha · tipo · comprobante · proveedor · CUIT · neto · IVA ·
  alíc.% · percep. IVA/IIBB/Gcias · crédito fiscal · total. Fila TOTALES +
  nota con `excluidos` (B/C sin crédito fiscal).
- **Resumen (Posición IVA)**: DF (Σ signo·IVA ventas), CF (Σ signo·crédito
  fiscal compras), saldo técnico, percepciones, saldo a pagar/favor —
  calculado de los mismos datos, cuadra con las dos hojas.

### 3. `expLibroIvaExcel(d, h)` — builder (nuevo)
Fetchea con `_lidVentasData(d,h)` y `_lidComprasData(d,h)` (mismos GET que el
TXT), llama a `libroIvaExcelHojas`, luego `xlsxBuild`. Devuelve
`{nombre:'Libro_IVA_Digital_AAAA-MM.xlsx', bytes, mime, resumen}`.

### 4. Ruteo binario (ajuste mínimo a código existente)
`exportarUno` y `descargarCarpeta` hoy asumen `contenido` texto. Se adaptan:
si el builder devuelve `bytes`, usan `descargarBytes(nombre, bytes, mime)`;
si no, `descargarTexto` como hasta ahora. **Retrocompatible** — los CSV
siguen siendo texto.

## Data flow

```
botón → exportarUno(idx) → expLibroIvaExcel(desde,hasta)
  → _lidVentasData + _lidComprasData   (mismos GET que el TXT)
  → libroIvaExcelHojas(...)            (arma filas, puro)
  → xlsxBuild(hojas) → zipStore(...)   (bytes .xlsx)
  → descargarBytes(nombre, bytes, mime)
```

**Fuente única de verdad:** Excel y TXT llaman a las mismas funciones de
datos → espejo 1:1 sin duplicar lógica.

## Testing

`tests/xlsx-writer.test.js` (harness `node --test` existente):
1. `xlsxBuild` produce un ZIP con las partes esperadas; el contenido (store,
   sin comprimir) contiene `[Content_Types].xml`, `xl/worksheets/sheet1.xml`
   y celdas con XML escapado.
2. `libroIvaExcelHojas` sobre datos de muestra: los TOTALES de Ventas/Compras
   coinciden con los netos/IVA de entrada (prueba el espejo).
3. Validación end-to-end fuera del harness: generar un `.xlsx` de muestra y
   abrirlo con openpyxl para confirmar que es un workbook válido.

## Riesgo

Aditivo. **No se toca el path legal de los TXT.** El único cambio a código
vivo es el ruteo binario (retrocompatible). Deploy a prod es merge a `main`
(Netlify) — se hace solo con OK explícito del usuario.

## Fuera de alcance (YAGNI)

Solo el Libro IVA en Excel. `xlsxBuild` queda reusable para portar Libro
Diario / Mayores a Excel más adelante; no se construyen ahora.
