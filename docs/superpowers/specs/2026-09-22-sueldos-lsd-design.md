# Sueldos: cierre de revisión + Libro de Sueldos Digital (ARCA) — Diseño

**Fecha:** 2026-09-22
**Estado:** implementado en rama `feat/sueldos-lsd` · migración 082 validada en Postgres 17 local (esquema stub + smoke funcional de las 3 RPCs), NO contra prod · 12 tests nuevos + 1 ajustado, suite 287/287 verde · pendiente: correr la 082 en el SQL Editor, deployar, cargar datos ARCA de los legajos y validar el primer TXT en ARCA.
**Origen:** revisión del módulo de sueldos (2026-09-22) + pedido del usuario: "debe tener validez frente a ARCA" con el formato `LSD-ARMADO-TXT-Liquidaciones.xlsx` (carga masiva de liquidaciones del Libro de Sueldos Digital).

## Contexto

Fase 1/2 (065/066) registran la liquidación que hace la contadora y la
contabilizan. No había forma de generar lo que ARCA exige para el Libro de
Sueldos Digital: un TXT de ancho fijo con registros 01 (cabecera), 02 (uno
por empleado), 03 (conceptos del recibo) y 04 (atributos de la relación
laboral + bases imponibles del F.931). El ERP tampoco guardaba los conceptos
del recibo ni los datos SICOSS del legajo.

La revisión además encontró 4 huecos de integridad (pagos huérfanos al
eliminar, meses duplicados, pago parcial que marca PAGADO, consumo de
provisión SAC sin corte de fecha) y 3 menores (corte UTC de las horas de
planta, período por defecto, KPI de último costo).

## Decisiones

- **Conceptos del recibo como fuente de verdad.** Catálogo
  `conceptos_sueldo` (códigos PROPIOS del empleador, los que la contadora
  asocia a los conceptos ARCA en LSD → Conceptos) con `tipo`
  remunerativo / no_remunerativo / descuento / informativo. Cuando un ítem
  trae conceptos, `guardar_liquidacion` recalcula bruto / no rem / aportes /
  neto desde ellos (la fila del modal queda bloqueada). Contribuciones y
  ART siguen tipeados: no van al LSD, ARCA los calcula desde las bases.
- **Datos SICOSS en el legajo, bases por liquidación.** `empleados` suma
  CBU / forma de pago / dependencia (reg. 02) y cónyuge, hijos, marcas,
  situación, condición, actividad, modalidad, siniestrado, localidad,
  situación de revista, obra social RNOS y adherentes (reg. 04). Las bases
  imponibles y días/horas van en `liquidacion_items.f931` (jsonb): lo que
  falta se deriva del bruto al exportar (`computeF931Default`: bases 1–9 =
  bruto remunerativo, 1/4/5 con tope configurable, 6/7 = 0, rem. bruta =
  rem + no rem, base 10 = bruto − detracción o 0). Todo editable por la
  contadora en el modal "Conceptos y F.931".
- **Datos del empleador en config_contable:** `cuit_empleador`,
  `lsd_tipo_empresa` (Dec. 814/01, default 1), `lsd_importe_detraer`
  (Ley 27.430), `lsd_tope_aportes` (0 = sin tope). Se guardan al descargar.
- **Formato = las fórmulas del Excel de ARCA, literal.** `lsdReg1..4` +
  helpers (`lsdNum` ceros a la izquierda, `lsdImp` importe ×100 en 15,
  `lsdStr` texto a la izquierda, `lsdStrR` a la derecha, `lsdAscii` sin
  acentos). Largos 35 / 115 / 51 / 370, CRLF, ASCII. Los registros 05
  (eventuales) y 06 (observaciones, optativo) no se generan: Vitalmet no
  tiene eventuales.
- **`buildLSD` valida lo que ARCA rechaza y no deja descargar con
  errores:** CUIT/CUIL con dígito verificador, CBU (22 dígitos, pesos
  7-1-3-9) obligatorio si forma de pago = 3, fecha de pago, conceptos por
  empleado, obra social 6 dígitos, actividad 3 dígitos, modalidad 3,
  días XOR horas, rem. bruta > 0, largo exacto de cada línea, cant. de
  reg. 04 = empleados. El preview muestra igual el archivo con los
  problemas listados.
- **Número de liquidación** (`liquidaciones.lsd_nro`): sugerido = máximo
  del período + 1; se persiste con `lsd_exportado_at` al descargar. El
  botón LSD muestra ✓ si ya se exportó. Se puede exportar un borrador
  (para validar en ARCA antes de confirmar), con aviso.

## Fixes de la revisión (082)

1. **Pagos huérfanos:** `guardar_liquidacion` / `anular_liquidacion` (delete
   de borrador) fallan si hay asientos `liquidacion-pago-*` vivos. Anular
   una confirmada sigue permitido (vuelve a borrador con el pago vivo, que
   ahora bloquea editar/eliminar hasta anularlo).
2. **Mes duplicado:** índice único parcial `(empresa, periodo, tipo)` para
   mensual / quincena1 / quincena2 / sac; la RPC traduce la violación a
   "Ya existe una liquidación mensual del período MM/AAAA". `vacaciones`,
   `final` y `otro` pueden repetirse. La migración aborta con lista si ya
   hay duplicados en prod.
3. **Pago parcial:** el importe del modal de pago es el de la liquidación
   (readonly + validación ±0,05). Parciales → asiento manual (el badge
   PAGADO significa pagado completo).
4. **Provisión SAC:** el consumo al confirmar un `sac` toma sólo asientos
   con fecha ≤ fin del período del SAC.
5. Empleado repetido en `p_items` → error claro.
6. Horas de planta: corte de mes en `-03:00` (fetch y `computeParteHoras`).
7. Período por defecto = mes anterior; KPI "Último costo laboral" = última
   mensual confirmada.

## Fuera de alcance

- Liquidar (calcular) sueldos: el ERP sigue registrando lo que liquida la
  contadora. Los % del modal son ayuda.
- Registros 05/06 del LSD, rectificativas parciales, topes automáticos por
  período (el tope es un número en config, lo actualiza la contadora).
- Validación online contra ARCA: el único juez es la carga del TXT en el
  sistema LSD. La primera subida real es la prueba de aceptación.

## Verificación

- `node --test tests/*.test.js` → 287/287.
- Migración 082 + smoke en Postgres 17 local (`docker run postgres:17-alpine`,
  esquema stub): seed de 16 conceptos, totales recalculados desde conceptos,
  error por concepto inexistente / empleado repetido / período duplicado,
  `otro` repetible, confirmación con provisión SAC, bloqueo de edición y
  eliminación con pago vivo, corte de fecha del consumo SAC (SAC 06 no
  consume la provisión de julio; SAC 12 sí).
- Pendiente en prod: correr 082, completar CUIT empleador + datos ARCA de
  los 10 legajos + conceptos reales, exportar la última liquidación y
  subirla en ARCA → LSD → Carga de liquidación.
