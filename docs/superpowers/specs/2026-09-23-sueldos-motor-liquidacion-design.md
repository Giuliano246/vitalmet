# Sueldos: motor de liquidación completo (UOM + fuera de convenio + Ganancias + ARCA) — Diseño

**Fecha:** 2026-09-23
**Estado:** implementado en la rama `feat/sueldos-motor`, 2026-09-24; rulings en el ledger del sprint (`.superpowers/sdd/2026-09-23-sueldos-motor-liquidacion/progress.md`, R1–R45). Falta correr la migración 083 en prod y el smoke con datos reales (ver "Verificación" más abajo).
**Origen:** pedido del usuario (2026-09-23): "quiero que mires todas las posibilidades y las agregues, debe ser lo más completo posible" sobre conceptos no remunerativos, antigüedad, bonos, etc. Decisiones tomadas en la sesión: el ERP pasa a ser **liquidador completo** (la contadora revisa y confirma); planta bajo **UOM CCT 260/75 rama 17**, administración **fuera de convenio**; escala cargada **a mano con historial**; **Ganancias 4ta categoría sí** (uno o más empleados alcanzados); novedades **cargadas a mano por período** con precarga opcional desde los timers de planta; motor de reglas **configurable** (opción 1); recibo impreso **igual al que emite hoy el sistema de la contadora** (dos páginas, duplicado); códigos de concepto **adoptados del padrón ARCA existente**.

**Material de referencia** (en `docs/sueldos/referencia/`):
- `arca-padron-conceptos-2026-09-23.csv`: exportación de ARCA (LSD → Conceptos) del CUIT 34-59751980-1 con los 121 conceptos ya registrados y sus 15 marcas. Separador `;`, UTF-8 con BOM.
- `LSD-ARMADO-TXT-Conceptos.xlsx`: planilla oficial de ARCA para la carga masiva de conceptos (registro de 195 posiciones) con el catálogo de 142 códigos ARCA en la hoja "Conceptos ARCA" y el layout en "Interfase".
- La planilla `LSD-ARMADO-TXT-Liquidaciones.xlsx` ya fue implementada en la 082 (registros 01–04).
- Dos fotos de un recibo real (1ª quincena septiembre 2026, jornal ingresante) sirvieron de modelo del recibo impreso y para confirmar parámetros. No se commitean (datos personales).

## Contexto

Hoy (065/066/082) el módulo registra el recibo que arma la contadora: por empleado se tipean los renglones (concepto, cantidad, unidad, importe), la RPC recalcula bruto / no rem / aportes / neto, se contabiliza, y se exporta el TXT del Libro de Sueldos Digital. No calcula nada por sí mismo: ni antigüedad, ni escala, ni SAC, ni Ganancias. El catálogo de conceptos tiene código, nombre, tipo y unidad; le faltan el código ARCA y las marcas de subsistemas, sin las cuales ARCA rechaza el TXT de liquidaciones cuando un código no está registrado.

Lo que confirmó el recibo real de septiembre 2026:
- Los jornales se liquidan **por quincena** (tipo `quincena1`/`quincena2`, ya soportado en `liquidaciones.tipo`).
- Jornal ingresante $4.485,97/h (escala UOM rama 17 desde 08/2026), 90 h en la quincena, feriado 9 h.
- Aportes: jubilación 11 %, ley 19.032 3 %, obra social 3 %, sindicato UOM 2,5 %; sobre la suma no remunerativa de paritaria: sindicato 2,5 % y obra social 3 %.
- Contribuciones Dec. 814/01 art. 2 inc. b (18 % sobre base detraída: jubilación 10,77 / INSSJP 1,59 / FNE 0,94 / AAFF 4,70) + obra social 5,10 % y ANSSAL 0,90 % sobre remunerativo **más** no remunerativo con marca OS; seguro de vida colectivo suma fija ($424,62 por quincena).
- Detracción Ley 27.430: **$7.003,68 por mes** ($3.501,84 por quincena), aplica a SIPA/INSSJP/FNE/AAFF y no a OS.
- Concepto "Redondeo" para llevar el neto a múltiplo de $10.

## Decisiones

- **Motor en funciones puras de JS** (`computeRecibo` y auxiliares) con tests en `node:test`, siguiendo el patrón del módulo: el navegador calcula, la RPC `guardar_liquidacion` sigue recalculando totales desde los renglones. Las reglas viven en el catálogo (`conceptos_sueldo.regla`), no en el código; el código sólo conoce las **bases** y los **tipos de regla**.
- **Códigos del empleador = los del padrón ARCA.** Se importan los 121 conceptos registrados con su código ARCA y sus marcas exactas. Quedan **activos** los canónicos; los duplicados y los de una sola vez (retroactivos 2023, decreto 438, cuotas UOM 2023) quedan **inactivos** (`activo=false`, `legacy=true`) para que el historial cierre y no aparezcan en el selector. Los conceptos nuevos que el motor necesita reciben códigos libres en el mismo estilo numérico y se dan de alta en ARCA con el TXT de conceptos.
- **Marcas ARCA → bases del F.931.** Cada base imponible del registro 04 se calcula como Σ de los importes de los conceptos cuya marca correspondiente está en 1, con tope/prorrateo después. Reemplaza la estimación actual de `computeF931Default` (que queda como fallback cuando un ítem no tiene conceptos).
- **Escala y parámetros con vigencias** en tablas propias (no en `config_contable`): el motor toma la vigente al último día del período. Los dos campos `lsd_importe_detraer` / `lsd_tope_aportes` de `config_contable` se migran a `parametros_previsionales` y dejan de usarse.
- **Novedades por período** en tabla propia (`sueldos_novedades`), una fila por empleado y período. Sin fila = mes completo, sin extras ni ausencias.
- **Ganancias con método acumulado RG 4003** y acumulados persistidos por liquidación (`liquidacion_items.ganancias` jsonb) para que cada mes parta del anterior.
- **Recibo impreso** desde el navegador (HTML + `@media print`), dos páginas por empleado, original y duplicado, layout calcado del recibo actual.
- **Single-tenant, sin abstracciones de más:** un solo convenio (UOM rama 17) más "fuera de convenio". No se modela multi-convenio; `empleados.convenio` es un enum de dos valores.

## Alcance

1. Catálogo ARCA de referencia + conceptos ampliados (código ARCA, 15 marcas, regla) + importador del padrón + exportador TXT de conceptos + Excel rellenado.
2. Escala UOM con vigencias, parámetros del convenio, parámetros previsionales, tablas de Ganancias.
3. Legajo ampliado (convenio, categoría, sueldo pactado, jornada, afiliación, adicionales fijos, conceptos recurrentes, Ganancias / F.572, datos del recibo).
4. Novedades del mes (grilla) con precarga desde timers.
5. Motor: básico, antigüedad, adicionales, presentismo, extras, feriados, licencias, vacaciones, IMGR, no remunerativo de paritaria, recurrentes, aportes con topes, sindicales, Ganancias, contribuciones, redondeo. Mensual y quincenal.
6. SAC (semestre / proporcional) y vacaciones.
7. Liquidación final por causa de egreso.
8. Pantalla de liquidación con "Calcular", detalle editable con traza y "Recalcular".
9. Recibo imprimible (2 páginas, duplicado) y lote de recibos.
10. Vista de acumulados; validaciones; tests; manual (md + docx).

## Fuera de alcance

Importar la escala desde el PDF de la UOM; traer el F.572 desde el web service de SIRADIG; otros convenios; trabajadores eventuales (registro 05 del LSD); firma digital y envío del recibo por mail; Ganancias con rentas de otras fuentes; embargos judiciales con más de un acreedor; liquidación de jornada parcial con reglas especiales de obra social (Ley 26.474): sólo se prorratea por `horas_semanales`.

## Modelo de datos (migración 083)

Todas las tablas nuevas pasan por `pg_temp.aplicar_bateria` (empresa_id + RLS + audit, patrón de la 065/082).

### `conceptos_arca` (referencia, sin empresa_id, sólo lectura)
`codigo text PK` (6 dígitos), `familia text` (remunerativo / no_remunerativo / descuento), `descripcion text`, `uso_libre boolean`, `rango_desde text`, `rango_hasta text`. Sembrada con las 142 filas de la hoja "Conceptos ARCA" (incluidos los rangos "de uso libre" como filas con `uso_libre=true`).

### `conceptos_sueldo` (ampliada)
Columnas nuevas:
- `codigo_arca text REFERENCES conceptos_arca` (obligatorio para exportar LSD; NULL permitido para `informativo`).
- `repeticion boolean default true` (marca de repetición del registro ARCA).
- `marcas char(15)`: las 15 marcas en el orden del CSV de ARCA: SIPA-A, SIPA-C, INSSJP-A, INSSJP-C, OS-A, OS-C, FSR-A, FSR-C, RENATEA-A, RENATEA-C, AAFF-C, FNE-C, LRT-C, DIF-A, ESP-A. El exportador las ubica en las posiciones 168–186 del registro intercalando los cuatro "libre". Defaults por tipo: remunerativo `111111111111100`; descuento e informativo `000000000000000`; no_remunerativo según familia ARCA: 540000 `000011110000000`, 550000 `000011110000100`, 520000/551000 `000000000000000` (todos tomados del padrón real). Editables.
- `regla jsonb`: ver "Reglas".
- `legacy boolean default false`, `origen text` (`padron` / `seed` / `manual`).
- `unidades` se mantiene.

### `sueldos_convenio_parametros`
`id, empresa_id, vigencia_desde date, imgr numeric, no_rem_paritaria numeric, no_rem_codigo text` (código del concepto, default 102), `antiguedad_pct numeric` (1.00), `horas_mes integer` (200: divisor para valor hora de mensualizados y para extras), `horas_dia numeric` (8), `presentismo_pct numeric` (default 0: la empresa lo define), `presentismo_tolerancia_dias smallint` (0), `sepelio_importe numeric`, `scvo_importe numeric` (seguro de vida colectivo, patronal, por mes), `cuota_sindical_pct` (2.5), `aporte_solidario_pct` (2.0, **verificar con la contadora**), `redondeo_a numeric` (10). Única por (empresa, vigencia_desde).

### `sueldos_escala`
`id, empresa_id, vigencia_desde date, categoria text, modalidad text` (`jornal` / `mensual`), `valor_hora numeric, basico_mensual numeric, orden int`. Única por (empresa, vigencia_desde, categoria). Categorías seed rama 17 jornales: Ingresante, Operario, Operario Calificado, Medio Oficial, Operario Especializado, Oficial, Operario Especializado Múltiple, Oficial Múltiple; mensualizados: Administrativo A1–A4, Técnico B1–B6. Sólo **Ingresante** viene con valor (4.485,97 desde 2026-08-01; 4.665,41 desde 2026-10-01; 4.852,02 desde 2026-12-01; 4.949,06 desde 2027-01-01; 5.122,28 desde 2027-03-01, fuente acuerdo UOM homologado DI-2026-1099). Las demás quedan en 0 para que el usuario las cargue desde la planilla de la UOM.

### `sueldos_parametros_previsionales`
`id, empresa_id, vigencia_desde date, tope_min numeric, tope_max numeric, detraccion numeric, aporte_jubilacion_pct (11), aporte_inssjp_pct (3), aporte_os_pct (3), aporte_os_adherente_pct (1.5), tipo_empresa smallint` (1 = inc. b), `contrib_sipa_pct (10.77), contrib_inssjp_pct (1.59), contrib_fne_pct (0.94), contrib_aaff_pct (4.70), contrib_os_pct (5.10), contrib_fsr_pct (0.90), art_pct numeric, art_fijo numeric, ganancias_tope_retencion_pct (35)`. Seed 2026-09-01: tope_min 144.363,55; tope_max 4.691.748,47; detracción 7.003,68; ART según póliza (0 hasta que el usuario lo cargue).

### `sueldos_ganancias_tablas`
`id, empresa_id, vigencia_desde date` (1 de enero o 1 de julio), `gni_anual, deduccion_especial_anual, conyuge_anual, hijo_anual, hijo_incap_anual, tramos jsonb` ([{desde, hasta, fijo, pct}] anuales, 9 tramos). Seed 2026-07-01 con los valores publicados para el segundo semestre 2026 (GNI 6.019.671,36; especial 28.894.422,56; cónyuge 5.669.323,06; hijo 2.859.060,30; hijo incapacitado 5.718.120,61; escala de 5 % a 35 % con primer tramo hasta 2.336.953,69).

### `sueldos_novedades`
`id, empresa_id, empleado_id, periodo date, tipo text` (`mensual` / `quincena1` / `quincena2`), `dias_trabajados numeric, horas_normales numeric, hs_extra_50 numeric, hs_extra_100 numeric, feriados_no_trabajados smallint, feriados_trabajados_hs numeric, ausencias_injustificadas numeric, licencia_paga_dias numeric, licencia_paga_tipo text, licencia_sin_goce_dias numeric, vacaciones_dias numeric, adelanto numeric, premio_produccion numeric, otros jsonb` ([{codigo, cantidad, importe}]), `observaciones text`. Única por (empresa, empleado, periodo, tipo).

### `empleados` (ampliada)
`convenio text` (`uom` / `fuera`, default `uom`), `categoria_escala text` (FK lógica a `sueldos_escala.categoria`), `sueldo_pactado numeric` (fuera de convenio), `horas_semanales numeric` (48), `afiliado_sindicato boolean` (true), `presentismo boolean` (true), `antiguedad_pct numeric` (NULL = usar convenio; fuera de convenio default 0), `adicionales_fijos jsonb` ([{codigo, pct | importe}]), `conceptos_recurrentes jsonb` ([{codigo, importe | pct_base, cuotas_total, cuotas_pagadas, desde, hasta}]), `ganancias_aplica boolean` (false), `ganancias_deducciones jsonb` ([{periodo_desde, periodo_hasta, tipo, importe_mensual}] — tipos: alquiler, servicio_domestico, cuota_medica, seguro_vida, intereses_hipotecarios, donaciones, gastos_educativos, otros), `fecha_ingreso_reconocida date` (para antigüedad cuando difiere de `fecha_ingreso`), `contratacion text` (leyenda del recibo, ej. "Nuevo período de prueba"), `tarea text`, `lugar_pago text` (default "Casa Central"), `banco_deposito text`, `causa_egreso text`.

### `liquidacion_conceptos` (ampliada)
`origen text` (`auto` / `manual`), `traza jsonb` ({regla, base, cantidad, factor, formula: "..."}), `base numeric` (para la columna BASE del recibo).

### `liquidacion_items` (ampliada)
`ganancias jsonb` ({rem_gravada_acum, deducciones_acum, gni_acum, impuesto_acum, retenido_previo, retencion_mes, tabla_vigencia}), `contribuciones_detalle jsonb` ([{codigo, nombre, pct, base, importe}] para el bloque "Costo total empleador" del recibo), `recibo_nro integer`.

### `config_contable` (ampliada)
`recibo_prox_nro integer` (numerador de recibos), `razon_social_recibo text, domicilio_recibo text, actividad_recibo text, f931_ultimo_periodo text, f931_ultimo_fecha date, f931_banco text` (encabezado del recibo; si están vacíos se usa `empresas`).

### Vista `v_sueldos_acumulados`
Por (empresa, empleado, año, mes): bruto remunerativo, no remunerativo, aportes, Ganancias retenida, SAC pagado, días trabajados, desde liquidaciones **confirmadas**. Alimenta SAC (mejor remuneración del semestre), Ganancias (acumulados y retenido previo) y liquidación final (mejor remuneración normal y habitual).

## Catálogo de conceptos

### Códigos adoptados del padrón (activos)
| Código | Concepto | ARCA | Tipo |
|---|---|---|---|
| 1 | Sueldo básico (mensual) | 110000 | rem |
| 4 | Jornal | 110000 | rem |
| 5 | Feriado | 110007 | rem |
| 7 | Enfermedad (licencia paga) | 111000 | rem |
| 8 | Accidente ART primeros 10 días | 110008 | rem |
| 9 | Antigüedad | 160001 | rem |
| 6 | Aumento voluntario / a cuenta futuros aumentos | 160000 | rem |
| 20 | Aguinaldo (SAC) | 120000 | rem |
| 28 | SAC proporcional | 120000 | rem |
| 102 | Gratificación extraordinaria no remunerativa (paritaria) | 540000 | no rem (OS-A/C, FSR-A/C) |
| 31 | Asignación no remunerativa | 550000 | no rem |
| 85 | Extraordinaria no remunerativa | 551000 | no rem |
| 400 | Préstamo otorgado | 551000 | no rem |
| 200 | Jubilación 11 % | 810000 | desc |
| 201 | Ley 19.032 3 % | 810001 | desc |
| 202 | Obra social 3 % | 810002 | desc |
| 203 | Sindicato UOM 2,5 % | 810004 | desc |
| 204 | Seguro de vida | 810005 | desc |
| 208 | Obra social s/ no remunerativo | 810002 | desc |
| 211 | Sindicato s/ no remunerativo | 810004 | desc |
| 900 | Retención Impuesto a las Ganancias | 810008 | desc |
| 999 | Redondeo (débito) | 820000 | desc |
| 517 | Vacaciones no gozadas | 520012 | no rem |
| 521 | SAC s/ vacaciones no gozadas | 520018 | no rem |

Los códigos 224, 225 y 516 del recibo de septiembre **no están en el padrón**: se crean como alias inactivos de 211, 208 y 102 y se pregunta a la contadora cómo los mapea.

### Códigos nuevos (a registrar en ARCA con el TXT de conceptos)
| Código | Concepto | ARCA | Tipo |
|---|---|---|---|
| 3 | Presentismo | 170001 | rem |
| 10 | Horas extras 50 % | 130001 | rem |
| 16 | Horas extras 100 % | 130002 | rem |
| 17 | Feriado trabajado | 130002 | rem |
| 18 | Vacaciones | 150000 | rem |
| 24 | Complemento IMGR | 110000 | rem |
| 25 | Tarea peligrosa 20 % (art. 65) | 160003 | rem |
| 26 | Altas calorías 20 % (art. 66) | 160003 | rem |
| 27 | Adicional por título | 160002 | rem |
| 37 | Licencia paga (examen, matrimonio, nacimiento, fallecimiento) | 111000 | rem |
| 64 | Premio por producción | 170002 | rem |
| 75 | Bono / gratificación remunerativa | 170000 | rem |
| 86 | Preaviso trabajado | 110001 | rem |
| 106 | Viáticos con comprobante | 520000 | no rem |
| 205 | Aporte solidario UOM (no afiliados) | 810004 | desc |
| 206 | Seguro de sepelio UOM | 810005 | desc |
| 207 | Obra social adherentes 1,5 % | 810009 | desc |
| 223 | Adelanto de sueldo | 820000 | desc |
| 226 | Embargo judicial | 820000 | desc |
| 227 | Cuota de préstamo | 810007 | desc |
| 530 | Indemnización por antigüedad art. 245 | 520014 | no rem |
| 531 | Indemnización sustitutiva de preaviso | 520015 | no rem |
| 532 | Integración mes de despido | 520016 | no rem |
| 533 | SAC s/ preaviso e integración | 520017 | no rem |
| 998 | Redondeo (crédito) | 499999 | rem sin marcas (`000000000000000`) |

Contribuciones patronales (640–647 del recibo actual) **no son conceptos ARCA** (se guardan con esos mismos códigos para el recibo): se guardan en `liquidacion_items.contribuciones_detalle` y se imprimen, pero no van al LSD (ARCA las calcula desde las bases).

### Reglas (`conceptos_sueldo.regla`)
```json
{
  "auto": true,
  "aplica_convenio": "uom" | "fuera" | "todos",
  "aplica_modalidad": "jornal" | "mensual" | "todos",
  "base": "basico" | "valor_hora" | "valor_hora_extra" | "rem_bruto" | "no_rem" | "no_rem_os" | "rem_topeado" | "mejor_rem_semestre" | "neto" | "fijo",
  "pct": 11.0,            // opcional
  "importe": 0,           // opcional (suma fija)
  "cantidad": "novedad.hs_extra_50" | "legajo.antiguedad_anios" | "novedad.feriados_no_trabajados" | "novedad.vacaciones_dias" | "1",
  "factor": 1.5,          // opcional (recargo)
  "condicion": "presentismo_ok" | "afiliado" | "no_afiliado" | "ganancias_aplica" | null,
  "orden": 40
}
```
El motor evalúa `importe = round2(base × pct/100 × cantidad × factor)` o `importe = importe_fijo × cantidad`. Las bases son las únicas cosas que conoce el código; agregar un concepto nuevo es una fila del catálogo. Los conceptos con `auto=false` sólo se cargan a mano o desde `novedades.otros` / `conceptos_recurrentes`.

## Motor de cálculo (`computeRecibo`)

Firma: `computeRecibo({empleado, periodo, tipo, novedad, escala, convenio, previsional, ganTabla, catalogo, acumulados, fechaPago}) → {conceptos: [...], totales, f931, contribuciones, ganancias, alertas}`. Puro; sin acceso a red ni DOM; tests en `tests/sueldos-motor.test.js`.

Orden y fórmulas (todo a 2 decimales; `dias_periodo` = 30 mensual / 15 quincena; `factor_periodo` = 1 / 0,5; `factor_jornada` = horas_semanales / 48):

1. **Días base.** Mes de ingreso/egreso: `dias_trabajados = min(días del período, días entre ingreso/egreso y límites)`. Se descuentan ausencias injustificadas y licencia sin goce. Para jornales, si la novedad trae `horas_normales` manda eso; si no, `dias_trabajados × horas_dia`.
2. **Básico.** Jornal (código 4): `valor_hora × horas_normales`. Mensual UOM (1): `basico_mensual × dias_trabajados / dias_periodo`. Fuera de convenio (1): `sueldo_pactado × factor_periodo × dias_trabajados / dias_periodo`. Alerta si la categoría no tiene valor en la escala vigente.
3. **Antigüedad (9).** `años = floor(años entre fecha_ingreso_reconocida ?? fecha_ingreso y último día del período)`; `importe = básico × antiguedad_pct/100 × años`. Fuera de convenio usa `empleados.antiguedad_pct` (default 0).
4. **Adicionales fijos del legajo** (25, 26, 27, 6): `pct` sobre básico o `importe × factor_periodo`.
5. **Presentismo (3).** `(básico + antigüedad) × presentismo_pct/100` si `ausencias_injustificadas ≤ tolerancia` y `empleados.presentismo`. Si `presentismo_pct = 0` no se genera.
6. **Valor hora extra.** Jornal: `valor_hora × (1 + antiguedad_pct×años/100 + Σ pct adicionales)`. Mensual: `(básico_mensual + antigüedad + adicionales porcentuales) / horas_mes`. Fuera: `(sueldo_pactado + antigüedad) / horas_mes`.
7. **Horas extras** 10: `vhe × 1,5 × hs_extra_50`; 16: `vhe × 2 × hs_extra_100`. **Feriados**: 5 (jornales, no trabajado): `valor_hora × horas_dia × feriados_no_trabajados`; 17 (trabajado, todos): `vhe × 2 × feriados_trabajados_hs`.
8. **Licencias pagas** (7 enfermedad, 8 accidente, 37 otras): jornales `valor_hora × horas_dia × días`; mensuales se informan con importe `básico/dias_periodo × días` y el básico se reduce en la misma cantidad (así el recibo abre el concepto y el total no cambia). Enfermedad respeta art. 208 LCT sólo como alerta (no corta el pago).
9. **Vacaciones (18).** Días según LCT art. 150 por antigüedad al 31/12: <6 meses 1 día cada 20 trabajados; hasta 5 años 14; hasta 10 21; hasta 20 28; más 35. Importe: mensual `(básico + antigüedad + adicionales)/25 × días`; jornal `valor_hora × horas_dia × días` (art. 155). Los días de vacaciones se restan de `dias_trabajados`.
10. **Complemento IMGR (24)** sólo UOM: `piso = imgr × factor_jornada × factor_periodo`; `suma = básico + antigüedad + presentismo + adicionales + no_rem_paritaria` (sin extras ni feriados trabajados); si `suma < piso` → `piso − suma`.
11. **No remunerativo de paritaria (102).** `no_rem_paritaria × factor_jornada × factor_periodo × dias_trabajados/dias_periodo`.
12. **Recurrentes y novedades.** `conceptos_recurrentes` vigentes en el período (bono 75, viáticos 106, cuota de préstamo 227 con `cuotas_pagadas++` al confirmar, embargo 226 con tope 20 % del neto previo a embargo). `novedad.adelanto` → 223; `novedad.premio_produccion` → 64; `novedad.otros` → tal cual.
13. **Redondeo (999).** `neto_objetivo = ceil(neto / redondeo_a) × redondeo_a`; la diferencia se agrega como crédito 998 (ARCA 499999, sin marcas) o débito 999 (820000) según el signo, con `redondeo_a` del convenio (10). Si `redondeo_a = 0` no se genera.
14. **Bases y aportes.**
    - `rem_bruto` = Σ remunerativos; `no_rem` = Σ no remunerativos; `no_rem_os` = Σ no remunerativos con marca OS-A.
    - `tope_max_prorr = tope_max × dias_tope/30` donde `dias_tope` = días del período si es mes de ingreso/egreso o vacaciones, si no 30 (LSD reg. 02 "días para proporcionar el tope"). En quincenas el tope se prorratea por 15 salvo que la configuración diga que se controla por mes (default: por quincena, como hace la contadora).
    - `rem_topeado = min(max(rem_bruto, tope_min_prorr), tope_max_prorr)`.
    - 200: `rem_topeado × 11 %`; 201: `× 3 %`; 202: `× 3 %`; 207: `× 1,5 % × adherentes`; 208: `no_rem_os × 3 %`.
    - 203 si afiliado: `(rem_bruto) × 2,5 %` y 211: `no_rem × 2,5 %`; 205 si no afiliado: `rem_bruto × aporte_solidario_pct`; 204 y 206: importes fijos × factor_periodo.
15. **Ganancias (900)**: ver sección propia; sólo si `ganancias_aplica` y `tipo ∈ {mensual, sac, final}` (en quincenas se calcula en la segunda con el acumulado del mes).
16. **Contribuciones** (no son conceptos, van a `contribuciones_detalle`): `base_sipa = max(rem_topeado_contrib − detraccion × factor_periodo, 0)` donde `rem_topeado_contrib` usa el tope máximo de contribuciones (ídem aportes); 644 jubilación 10,77 %, 642 INSSJP 1,59 %, 646 FNE 0,94 %, 647 AAFF 4,70 % sobre `base_sipa`; 645 OS 5,10 % y 643 FSR 0,90 % sobre `rem_bruto + no_rem_os`; ART `art_pct × rem_bruto + art_fijo × factor_periodo`; 640 SCVO `scvo_importe × factor_periodo`.
17. **F.931 (registro 04)** desde marcas: `base_i = Σ importes de conceptos con marca i` para SIPA-A (1), SIPA-C (2), FNE/AAFF/RENATEA (3), OS-A (4), INSSJP-A (5), DIF (6), ESP (7), OS-C (8), LRT (9); topes en 1/4/5 (aportes) con `tope_max_prorr`; base 10 = base 2 − detracción prorrateada (mínimo `tope_min`); `rem_bruta = rem_bruto + no_rem`; `importe_detraer = detraccion × factor_periodo`; días/horas desde novedad.
18. **Totales**: bruto = rem_bruto; no_remunerativo = no_rem; aportes = Σ descuentos; neto = bruto + no_rem − aportes (validación de la RPC sin cambios); contribuciones y ART = Σ detalle (para el asiento 065 sin cambios).
19. **Traza**: cada concepto lleva `{regla, base, cantidad, factor, formula}` legible ("4.485,97 × 90 h", "403.737,30 × 1 % × 0 años").

Alertas devueltas (no bloquean): categoría sin valor en escala, empleado sin fecha de ingreso, sin novedad cargada, tope superado, ausencias > 0 con presentismo perdido, préstamo con última cuota, Ganancias calculada con tabla de un semestre distinto al del período.

## SAC

Liquidación de tipo `sac` para el período 06 o 12: por empleado, `mejor_rem = max(bruto remunerativo mensual del semestre)` desde `v_sueldos_acumulados` (quincenas sumadas por mes; excluye vacaciones no gozadas y conceptos de la familia 520000); `dias_sem = días trabajados en el semestre (máx 181/184)`; `importe = mejor_rem × 50 % × dias_sem / días del semestre`. Concepto 20 si el semestre está completo, 28 si es proporcional (ingreso en el semestre). Aportes, sindicales, Ganancias y contribuciones se calculan igual que en un mensual; el tope de aportes del SAC es el 50 % del tope mensual. El consumo de la provisión SAC (066/082) no cambia.

## Ganancias 4ta categoría (RG 4003, método acumulado)

Por mes `m` del año fiscal (tabla vigente = la de `vigencia_desde ≤ 1 del mes`; en julio se recalcula todo el año con la tabla nueva):
1. `rem_gravada_acum = Σ_{1..m} (rem_bruto + no_rem gravado − aportes 200/201/202/207 − sindicales 203/205 − horas extras 100 % y feriados trabajados (exentos)) + SAC devengado 1/12 de cada mes` (cuando se paga el SAC real, ese mes no suma el doceavo y descuenta lo ya prorrateado si difiere).
2. `deducciones_personales_acum = (gni + especial + cónyuge×[conyuge] + hijo×hijos + hijo_incap×hijos_incap) × m/12`.
3. `deducciones_f572_acum = Σ deducciones del legajo vigentes en 1..m` con topes: cuota médica ≤ 5 % de la ganancia neta acumulada; alquiler ≤ 40 % de la GNI acumulada; servicio doméstico ≤ GNI acumulada; seguro de vida y sepelio ≤ tope anual prorrateado (parámetro en tabla); donaciones ≤ 5 %; intereses hipotecarios ≤ 20.000 anuales (prorrateado); gastos educativos ≤ 40 % GNI.
4. `gnsi_acum = max(rem_gravada_acum − deducciones_personales_acum − deducciones_f572_acum, 0)`.
5. `impuesto_acum = fijo_tramo + (gnsi_acum − desde_tramo) × pct` con los tramos anuales × m/12.
6. `retencion_mes = impuesto_acum − retenido_previo`; si `< 0` es devolución (crédito 900); tope: `retencion_mes ≤ ganancias_tope_retencion_pct % × rem_bruto del mes` (el excedente pasa al mes siguiente).
7. Se persiste en `liquidacion_items.ganancias` y el mes siguiente parte de `retenido_previo = Σ retenciones confirmadas del año`.
8. En liquidación final: se liquida como último mes con deducciones hasta ese mes.

## Liquidación final

Modal "Baja de empleado": fecha de egreso, causa (`renuncia`, `despido_sin_causa`, `despido_con_causa`, `mutuo_acuerdo`, `fin_contrato`, `fallecimiento`), preaviso otorgado (sí/no, días trabajados de preaviso), tope indemnizatorio (3 × promedio del CCT, cargado a mano; alerta si está vacío). Genera una liquidación `tipo='final'` con:
- Días trabajados del mes (motor normal, `dias_trabajados` hasta el egreso) y **preaviso trabajado (86)** si lo hubo.
- **SAC proporcional (28)** del semestre en curso.
- **Vacaciones no gozadas (517)**: días proporcionales del año (`días_lct × dias_trabajados_año/365`) menos gozados, × valor día; **SAC s/ vac. no gozadas (521)** = 517 × 1/12.
- Si despido sin causa o mutuo acuerdo con indemnización: **530** `mejor_rem_normal_habitual × años` (fracción > 3 meses = 1 año; mínimo 1 mejor remuneración; tope si está cargado); **531** preaviso omitido (15 días en prueba, 1 mes hasta 5 años, 2 meses después) × remuneración mensual; **532** integración (días que faltan del mes); **533** SAC s/ 531+532 = 1/12.
- Aportes sólo sobre lo remunerativo; los 5xx son no remunerativos sin marcas.
- Al confirmar: `empleados.fecha_egreso`, `activo=false`, `causa_egreso`; LSD reg. 02 con días para tope = días trabajados.

## Exportadores e importador ARCA

- **TXT de conceptos** (`buildConceptosTxt(conceptos)`): una línea por concepto activo sin `legacy`, 195 posiciones: ARCA(6) + código(10, izquierda) + descripción(150, izquierda, ASCII) + marcas(20) + libre(9). CRLF. Control de largo en test. Botón "Exportar conceptos ARCA" en la pantalla de conceptos, con filtro "sólo los que faltan en ARCA".
- **Importador del padrón** (`parseArcaPadron(csv)`): lee el CSV `;` exportado por ARCA (UTF-8 con BOM, 20 columnas); compara por `codigo` con el catálogo: (a) en ARCA y no en el ERP → alta como `legacy` inactivo con marcas de ARCA; (b) en el ERP y no en ARCA → listado "pendientes de alta en ARCA"; (c) en ambos con marcas distintas → alerta. Botón "Importar padrón ARCA". La migración 083 corre esta misma lógica con el CSV de referencia embebido como seed.
- **Excel rellenado**: `xlsxHoja` existente genera "Armado txt" con las 21 columnas de la planilla y la columna de TXT, y para liquidaciones las hojas reg1–reg4 con las columnas verdes cargadas. Sin fórmulas (valores), un archivo por exportación.
- **Validación previa al LSD**: antes de `buildLSD`, todos los códigos de `liquidacion_conceptos` deben tener `codigo_arca` y no ser `legacy`; si no, se bloquea con la lista.

## Recibo impreso

`renderRecibo(item, liquidacion, empresa, empleado, config)` devuelve HTML de dos páginas A4 (`@media print` con `page-break-after`), repetido para ORIGINAL y DUPLICADO (marca en el ángulo superior izquierdo). Numerador `config_contable.recibo_prox_nro` asignado al confirmar (`liquidacion_items.recibo_nro`).

**Página 1** (calcada del recibo actual):
- Cabecera: "Recibo de haberes", razón social, domicilio (calle y localidad), actividad, CUIT; Nro (recibo_nro), Piso, Depto vacíos.
- Fila 1: PERÍODO ABONADO (MM/AAAA) · DESCRIPCIÓN DEL PAGO ("1RA QUINC SEPTIEMBRE 2026" / "MENSUAL SEPTIEMBRE 2026" / "SAC 1ER SEMESTRE 2026" / "LIQUIDACIÓN FINAL") · FECHA DE PAGO · LUGAR DE PAGO.
- Fila 2: LEGAJO · APELLIDO Y NOMBRE · C.U.I.L. · FECHA ÚLTIMO INGRESO.
- Fila 3: CATEGORÍA · INICIO TIEMPO SERVICIO (fecha_ingreso_reconocida) · ANTIGÜEDAD ("0a 4m 20d").
- Fila 4: CONTRATACIÓN · OBRA SOCIAL.
- Fila 5: ÚLTIMO DEPÓSITO PREVISIONAL (banco) · PERÍODO · FECHA (del último F.931 pagado: campos nuevos `config_contable.f931_ultimo_periodo`, `f931_ultimo_fecha`, `f931_banco`, editables en Configuración) · TAREA · SUELDO/JORNAL (valor hora o básico).
- Bloque COSTO TOTAL EMPLEADOR (total a la derecha): tabla COD · CONCEPTO · UNIDAD · BASE · MONTO con `contribuciones_detalle`; SUBTOTAL CONTRIBUCIONES EMPLEADOR.
- Bloque SUELDO BRUTO (total): tabla COD · CONCEPTO · UNIDAD · BASE · MONTO con los conceptos (descuentos con signo negativo).
- COMPOSICIÓN LABORAL: Remunerativo · No Remunerativo · Descuentos.
- SUELDO NETO en números y en letras (`numeroALetras`, función pura nueva con test; hoy no existe en el ERP).
- Pie: "Incluido aumento de futuros convenios, leyes y/o resoluciones." · Página 1 de 2 · Firma del empleado · Firma del empleador.

**Página 2**: misma cabecera; "Detalle de la composición salarial": Total Costo Sindical (empleador / trabajador), Total Seguridad Social, Total Obra Social, Total otros descuentos, Total costo INSSJP, Total costo ART, Total costo SCVO, Total Otros, cada uno abierto en Empleador / Trabajador; cuadro "Costo total empleador" con porcentajes (sueldo neto, otros descuentos, costo SS, OS, INSSJP, SCVO, ART) y torta SVG; nota "Seguridad social del empleador incluye SIPA, Fondo Nacional de Empleo y Asignaciones Familiares"; pie igual.

Botones: "Imprimir recibo" en el detalle del empleado y "Imprimir todos" en la liquidación (un documento con todos los empleados, en orden de legajo).

## Pantallas

1. **Sueldos → Escalas y parámetros** (nueva página, admin): pestañas Escala UOM (grilla categoría × vigencia, "Nueva vigencia" copia la anterior con % de aumento), Convenio (parámetros con historial), Previsional (topes y alícuotas con historial), Ganancias (tablas por semestre con los 9 tramos).
2. **Legajo** (modal actual ampliado con pestañas): Datos (lo actual + tarea, contratación, lugar de pago, banco), Remuneración (convenio, categoría, sueldo pactado, horas semanales, afiliado, presentismo, antigüedad %, fecha reconocida), Conceptos fijos (adicionales + recurrentes con cuotas), Ganancias (aplica, cónyuge/hijos ya existen, deducciones por período), ARCA (los campos SICOSS de la 082).
3. **Sueldos → Novedades** (nueva página): selector período y tipo; grilla editable con una fila por empleado activo; botón "Precargar horas desde planta" (usa `computeParteHoras`, sólo rellena `horas_normales` de jornales vacíos); guardado por fila.
4. **Liquidación** (modal actual): botón **Calcular** (crea/actualiza items y conceptos `origen='auto'` para todos los empleados activos; respeta los renglones `manual`), tabla con bruto / no rem / descuentos / neto / alertas por empleado; detalle (modal 082) con columna Origen y ícono de traza (tooltip con la fórmula), botón **Recalcular empleado** (descarta manuales), edición manual como hoy. Confirmar sin cambios (asiento, provisión SAC, numerador de recibos, cuotas de préstamos).
5. **Baja de empleado** (modal desde el legajo): genera la liquidación final.
6. **Conceptos** (modal actual ampliado): columnas Código ARCA (selector con el catálogo de 142), marcas (20 casillas agrupadas), regla (formulario: base, %, cantidad, factor, condición, aplica), legacy; botones Exportar TXT, Exportar Excel, Importar padrón.
7. **Recibos**: "Imprimir" en detalle y en liquidación.

## Persistencia y validaciones

- `guardar_liquidacion` (082) acepta los campos nuevos de `liquidacion_conceptos` (`origen`, `traza`, `base`) y de `liquidacion_items` (`ganancias`, `contribuciones_detalle`); sigue recalculando totales desde conceptos; contribuciones y ART pasan a venir de `contribuciones_detalle` cuando existe.
- `confirmar_liquidacion`: además de lo actual, asigna `recibo_nro` correlativo por empresa, incrementa `cuotas_pagadas` de los préstamos incluidos, y en `final` cierra el legajo.
- Nueva RPC `guardar_novedades(p_periodo, p_tipo, p_items jsonb)` (upsert por empleado).
- Índices: `sueldos_escala (empresa_id, categoria, vigencia_desde desc)`, `sueldos_novedades (empresa_id, periodo, tipo)`.
- RLS y permisos: mismas políticas que `liquidaciones` (módulo `sueldos`, sólo admin/contable; planta y contador sin escritura; contador lectura).
- Exportar LSD bloquea si hay códigos sin ARCA o `legacy`.

## Tests (`node:test`, puros)

`tests/sueldos-motor.test.js`:
- Jornal ingresante 1ª quincena 09/2026 con 90 h y 9 h de feriado, no rem 40.000: reproduce el recibo real (bruto 444.111,03; aportes 200/201/202/203/211/208; neto 395.310 con redondeo 0,62; contribuciones 108.780,94 con detracción 3.501,84; SCVO 424,62).
- Mensual UOM oficial con 3 años de antigüedad, presentismo 8,33 %, 10 h extra 50 y 4 h extra 100, 1 ausencia injustificada (pierde presentismo).
- Fuera de convenio con Ganancias: 3 meses acumulados con la tabla 2S-2026, cónyuge y un hijo, alquiler; verifica retención mensual y devolución en el mes 3 al cargar una deducción retroactiva.
- Julio: recálculo con tabla nueva y ajuste.
- SAC 1er semestre completo y proporcional (ingreso 15/03).
- Vacaciones 14 y 21 días, mensual (divisor 25) y jornal.
- Complemento IMGR con jornada reducida (24 h semanales).
- Tope máximo de aportes superado y prorrateo por 20 días en mes de ingreso.
- Préstamo: cuota, última cuota y alerta; embargo con tope 20 % del neto.
- Liquidación final por despido sin causa a los 2 años y 4 meses: 530 × 3, 531 un mes, 532, 533, 517, 521, 28; por renuncia: sólo proporcionales.
- F.931: bases 1–10 desde marcas coinciden con `computeF931Default` en el caso simple y difieren correctamente con no rem 540000.
- `buildConceptosTxt`: largo 195, ASCII, marcas por tipo; `parseArcaPadron` con el CSV real: 121 filas, 20 columnas, detección de duplicados, diff contra catálogo.
- `renderRecibo`: contiene todos los bloques, número en letras, 2 páginas × 2 copias; suma de la torta = 100 %.

Suite existente (`sueldos.test.js`, `sueldos-lsd.test.js`) debe seguir verde; `computeF931Default` sigue como fallback.

## Datos de referencia sembrados (2026)

| Dato | Valor | Fuente |
|---|---|---|
| Valor hora ingresante rama 17 | 4.485,97 (08/26) · 4.665,41 (10/26) · 4.852,02 (12/26) · 4.949,06 (01/27) · 5.122,28 (03/27) | Acuerdo UOM homologado DI-2026-1099-APN-DNRYRT#MCH; confirmado por recibo 09/2026 |
| No rem paritaria | 40.000 por quincena en 09/2026 (recibo); cargar por vigencia | Recibo real; acuerdo UOM |
| Topes ANSES 09/2026 | mín 144.363,55 · máx 4.691.748,47 | ANSES Res. 257/2026 |
| Detracción Ley 27.430 | 7.003,68 mensual | Recibo real (3.501,84 por quincena) |
| Aportes | 11 / 3 / 3 · adherente 1,5 | Ley 24.241, 19.032, 23.660 |
| Contribuciones inc. b | 10,77 / 1,59 / 0,94 / 4,70 + OS 5,10 + FSR 0,90 | Ley 27.541 art. 19; recibo real |
| Sindicato UOM | 2,5 % afiliados; aporte solidario 2 % (**verificar**) | Recibo real; CCT 260/75 |
| Ganancias 2S-2026 | GNI 6.019.671,36; especial 28.894.422,56; cónyuge 5.669.323,06; hijo 2.859.060,30; hijo incap. 5.718.120,61; tramos 5–35 % desde 2.336.953,69 | Actualización IPC 16,85 % (RG 4003) |
| IMGR, sepelio, SCVO, ART, presentismo % | a cargar por el usuario (alertas hasta que existan) | — |

## Preguntas abiertas para la contadora (no bloquean)

1. Cómo mapea en LSD los códigos 224, 225 y 516 del recibo de septiembre, que no están en el padrón.
2. Porcentaje del aporte solidario UOM para no afiliados y valor vigente del seguro de sepelio.
3. Si el tope de aportes lo controla por quincena o por mes.
4. Tope indemnizatorio vigente del CCT 260/75 (3 × promedio).

## Verificación

### Suite y estado del código (hecho)

- [x] `node --test tests/*.test.js` → 334 pass / 0 fail (2026-09-24).
- [x] `node -e "require('./tests/_harness').load()"` sin error.
- [x] Manual de usuario actualizado (`docs/MANUAL_USUARIO.md` §11.9 + `docs/MANUAL_USUARIO.docx` regenerado con pandoc).
- [x] `CLAUDE.md` con el bloque "Sueldos 083 — motor de liquidación".

### Paso 1 — Correr la migración 083 en prod (usuario, antes de cualquier push)

1. Abrir el SQL Editor de prod (Supabase → proyecto `dqvlqhaxgvtilhiuatpv` → SQL Editor).
2. Pegar y correr el contenido completo de `migrations/083_sueldos_motor.sql` (es idempotente: `BEGIN`/`COMMIT`, `IF NOT EXISTS`, `ON CONFLICT`).
3. Al terminar sin error, correr el bloque **VERIFICACIÓN** que está comentado al pie del archivo (quitar los `--` y ejecutar el `SELECT`) y confirmar:
   - `arca` = 116 (conceptos_arca sembrados, incluye el código de uso libre 551001).
   - `padron` = 121 (conceptos_sueldo con `origen='padron'`, los códigos adoptados del padrón real de Vitalmet).
   - `seed` = 26 (conceptos_sueldo con `origen='seed'` y `regla` cargada — los que calcula el motor).
   - `escala` = 50 (8 categorías jornal × 5 vigencias + 10 categorías mensualizadas).
   - `pol` = 6 (policies RLS en `sueldos_novedades`: tenant_isolation, planta_lockdown, contador_no_ins/upd/del, modulo_sueldos).
4. Si algún número no coincide, no seguir: revisar el log de la migración antes de tocar el frontend (regla del proyecto — SQL antes que código).
5. Recién con la migración corrida y verificada: `git push origin main` (Netlify deploya el frontend).

### Paso 2 — Cargar datos reales antes de liquidar (usuario)

Antes de calcular la primera liquidación con el motor, en Sueldos → **Escalas y parámetros**:
- [ ] Cargar el valor hora de las categorías reales que tengan empleados (además de "Ingresante", que ya viene sembrada) y del/los empleado/s con IMGR aplicable.
- [ ] Cargar el importe de ART (pestaña Previsional) y el importe de sepelio (pestaña Convenio) — vienen en 0 hasta que el usuario los complete con la póliza real.
- [ ] En el legajo de cada empleado alcanzado por Ganancias: tildar "Se retiene Impuesto a las Ganancias" y cargar sus deducciones F.572 (pestaña Ganancias).

### Paso 3 — Smoke checklist en prod (usuario, con datos reales)

- [ ] Cargar novedades de la 2ª quincena de septiembre de 2026 (Sueldos → Novedades → período 09/2026, tipo "2ª quincena").
- [ ] Liquidar esa quincena para un jornal con **⚙ Calcular** y comparar el resultado, renglón por renglón, contra el recibo real que emitió la contadora (el mismo que sirvió de referencia para el diseño).
- [ ] Exportar el TXT de conceptos "faltan en ARCA" (Conceptos → Exportar TXT (faltan en ARCA)) y subirlo en ARCA → Libro de Sueldos Digital → Conceptos.
- [ ] Exportar el LSD de esa liquidación (botón LSD) y confirmar que el preview no lista rechazos.
- [ ] Imprimir un recibo (🖨 Recibos) y compararlo visualmente con la foto del recibo real (encabezado, bloques, neto en letras, página 2).

### Pendientes menores (deferred durante el sprint, no bloquean)

Catálogo y RLS (T1): `recibo_nro` sin UNIQUE y queda NULL si no hay `config_contable`; el contador de cuotas del préstamo 227 avanza por cada ítem con ese código (dos quincenas del mismo mes = 2 cuotas) y sobre todas las entradas 227 del ítem; los seeds de los conceptos 470-472/493 se re-aplican en cada corrida de la migración; el INSERT del padrón (paso 2d) no guarda empresa/origen; el `ON CONFLICT` del seed (2c) no refresca `tipo`/`nombre` de conceptos ya existentes; el concepto '400' (préstamo otorgado) queda activo como haber no remunerativo; el concepto '2' queda activo sin regla.

Importador/exportador ARCA (T2, T7): `ARCA_MARCAS_POS` descartado (ver Ruling R15 en el ledger); `parseArcaPadron` deja asignaciones sin uso; el contador de marcas de la UI no se actualiza en vivo; importar/exportar sin `try/catch` ni `setBusy` externos; mensajes de "fuera de catálogo" inconsistentes entre sí; sin validación de largo de `codigo_arca` en `parseArcaPadron`.

Fechas y texto (T3): la aproximación de 180 días para "6 meses" no quedó comentada en el código; sin tests de bordes de mes adicionales a los de la review.

Motor de cálculo (T4): `base3` sólo considera AAFF; queda código muerto (`bases`, `adicImp`, `CONTRIB_CODIGOS`); la cantidad de los adicionales fijos no tiene clamp a 999,99; los conceptos recurrentes fuerzan `origen:'auto'`; período `null` sin guard explícito; el push del básico (concepto '1') es explícito y saltea `aplica()`/chequeo de activo; `bases.no_rem` se lee después del redondeo; la alerta de licencia sin concepto re-agregador también dispara para jornales con `horas_normales` cargadas a mano.

Ganancias (T5): el seguro de vida se deduce al 100 % del GNI en vez de un tope anual prorrateado; el tope del 5 % se aplica sobre la ganancia bruta y no es acumulativo mes a mes; la rama de `quincena2` cae en la rama "mensual" sin test dedicado; el test 4 sólo assertea un campo; en liquidación `'final'` sin códigos 20/28 se restan los doceavos sin sumar el SAC real correspondiente.

SAC y liquidación final (T6): `mutuo_acuerdo` en período de prueba genera el concepto 531 (punto a confirmar legalmente); el régimen de vacaciones para empleados ingresados el año anterior con menos de 180 días trabajados en el año del egreso no está cubierto; el redondeo de días de vacaciones no quedó documentado en el código; el tramo de vacaciones se toma a la fecha de egreso y no al 31/12; los "2 meses de preaviso" aplican justo al cumplir 5 años sin margen; M5 lee 531/532 desde el array de conceptos en vez de una referencia directa.

Pantallas (T8, T9, T10, T11, T12): Escalas y parámetros sin botón borrar; en Baja de empleado, `previewBaja` hardcodea el centro de costo (dc) al armar 900/901 y puede disparar doble toast si falla dentro de `saveBajaEmpleado`; Novedades hace upsert de filas vacías para todos los empleados activos, no sólo los editados; en el detalle de liquidación, `liqdPrellenar` sigue usando `detraer`/`tope` de `configContable` en vez de `sueldos_parametros_previsionales`, la traza del SAC queda con `base=1`/`"1"`, `liqCalcular` no guarda contra un catálogo de conceptos vacío, `sinArca` ignora códigos ausentes del catálogo, y quedó un comentario viejo sobre `_liqDetalle`; el walkthrough manual del paso 5 (verificación visual en navegador) sigue pendiente. Recibo: la leyenda de la torta no oculta los segmentos en 0, la localidad del encabezado queda hardcodeada en `''` (no hay columna `localidad_recibo`), la posición de Nro./Piso/Depto. es aproximada, y el botón "Imprimir recibo" del detalle de un empleado individual es inalcanzable en liquidaciones ya confirmadas — el camino operativo es "🖨 Recibos" por liquidación completa (Ruling R42).
