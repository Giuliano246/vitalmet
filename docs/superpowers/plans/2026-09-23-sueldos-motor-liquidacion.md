# Sueldos — Motor de liquidación completo · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El ERP calcula solo el recibo de cada empleado (UOM rama 17 por quincena o mes, fuera de convenio mensual) desde escala, legajo y novedades: antigüedad, presentismo, extras, feriados, licencias, vacaciones, IMGR, no remunerativo de paritaria, recurrentes, aportes con topes, sindicales, Ganancias 4ta, contribuciones; SAC y liquidación final; conceptos con código ARCA y marcas (TXT de conceptos + importador del padrón); recibo impreso igual al actual.

**Architecture:** Migración 083 agrega catálogo ARCA de referencia, columnas de conceptos (código ARCA, repetición, 15 marcas, regla), escala UOM y parámetros con vigencias, tablas de Ganancias, novedades por período, legajo ampliado, vista de acumulados y re-emite `guardar_liquidacion` / `confirmar_liquidacion`. Frontend: motor en funciones puras (`computeRecibo`, `computeGanancias`, `computeSAC`, `computeLiquidacionFinal`, `renderRecibo`) testeadas con `node:test` vía `tests/_harness.js`; el navegador calcula, la RPC recalcula totales desde los renglones (patrón 082). Páginas nuevas `sueldosnov` (Novedades) y `sueldosparam` (Escalas y parámetros) como sub-tabs de un tab "Nómina" del grupo contabilidad.

**Tech Stack:** `index.html` único (vanilla JS, CSS embebido), Supabase (PostgreSQL 17 + PostgREST + RPC plpgsql), `node:test`, escritor XLSX propio (`xlsxBuild`), impresión con `window.open` + `document.write` (patrón `openPDF`).

**Spec:** `docs/superpowers/specs/2026-09-23-sueldos-motor-liquidacion-design.md`

## Global Constraints

- Toda tabla nueva con `empresa_id` pasa por `pg_temp.aplicar_bateria(t)` (RLS `tenant_isolation`, `planta_lockdown`, `contador_no_ins/upd/del`, `contador_guard`, `trg_audit`) **y** por la policy `modulo_sueldos` (molde 082 líneas 52-77). `conceptos_arca` es referencia global sin `empresa_id`: RLS con policy `SELECT TO authenticated USING (true)`.
- Migración idempotente (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`), envuelta en `BEGIN; … COMMIT;`, con bloque de VERIFICACIÓN comentado al final. Se corre en el SQL Editor de prod **antes** de pushear el frontend (regla 2 de CLAUDE.md).
- `empresa_id` en todo POST (`currentEmpresa.id`). Todo dato de usuario interpolado en HTML pasa por `esc()`.
- Importes a 2 decimales con `r2 = x => Math.round(x*100)/100`. Los descuentos se guardan como importes positivos con `dc='D'` (regla de la 082: importe ≥ 0).
- Funciones puras: sin DOM, sin red, sin variables globales del ERP; se ubican en el bloque `// ─── Sueldos 083: motor de liquidación ───` a continuación de `buildLSD` (antes de `parsearExtractoPegado`, ~línea 16760 de `index.html`). Tests nuevos en `tests/sueldos-motor.test.js`, `tests/sueldos-ganancias.test.js`, `tests/sueldos-final.test.js`, `tests/sueldos-conceptos-arca.test.js`, `tests/sueldos-recibo.test.js`.
- Antes de cada commit: `node --test tests/*.test.js` (hoy 287/287) y `node -e "require('./tests/_harness').load()"` (chequeo de sintaxis del script inline).
- Página nueva → `PAGE_TO_GROUP` + `GROUP_TABS` + `PAGE_TO_PARENT` + `groupMods` en `aplicarPermisos()` + `PAGE_RENDERS` + `<div class="tabs"></div>` en el `.page-header`. Tabla nueva → variable global + entrada en `TBL` (registro `reload`) + `loadAll`.
- Texto de UI en español argentino (voseo). Commits con `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Códigos de concepto del empleador: los del padrón ARCA (1, 4, 5, 7, 8, 9, 6, 20, 28, 102, 31, 85, 400, 200, 201, 202, 203, 204, 208, 211, 900, 999, 517, 521) más los nuevos de la spec (3, 10, 16, 17, 18, 24, 25, 26, 27, 37, 64, 75, 86, 106, 205, 206, 207, 223, 226, 227, 530, 531, 532, 533, 998). **Corrección a la spec:** el 998 (redondeo crédito) va a ARCA **799999** "Redondeo (No Remunerativo)" y es `no_remunerativo` sin marcas, porque el recibo real lo suma en "No Remunerativo".

## Mapa de archivos

| Archivo | Responsabilidad |
|---|---|
| `migrations/083_sueldos_motor.sql` | DDL (tablas nuevas, columnas), seeds (catálogo ARCA, padrón importado, conceptos nuevos, escala, parámetros, Ganancias), vista `v_sueldos_acumulados`, RPC `guardar_novedades`, re-emisión de `guardar_liquidacion` y `confirmar_liquidacion` |
| `index.html` bloque puras 083 | `MARCAS_DEFAULT`, `parseArcaPadron`, `diffConceptosArca`, `buildConceptosTxt`, `antiguedadEntre`, `diasVacacionesLCT`, `vigenteA`, `numeroALetras`, `computeRecibo`, `computeGanancias`, `computeSAC`, `computeLiquidacionFinal`, `renderRecibo` |
| `index.html` HTML | página `page-sueldosnov`, página `page-sueldosparam`, modal `modal-empleado` (pestañas), modal `modal-baja-empleado`, modal `modal-conceptos` (columnas nuevas), botones en `page-sueldos` y en `modal-liquidacion` / `modal-liq-detalle` |
| `index.html` UI sueldos | `renderSueldosNovedades`, `saveNovedades`, `novPrecargarHoras`, `renderSueldosParam` (+ 4 sub-renders y saves), `liqCalcular`, `liqRecalcularEmpleado`, `openBajaEmpleado`, `saveBajaEmpleado`, `exportConceptosTxt`, `exportConceptosXlsx`, `importarPadronArca`, `imprimirRecibo`, `imprimirRecibosLiquidacion` |
| `tests/sueldos-*.test.js` | tests de cada pura |
| `docs/MANUAL_USUARIO.md` + `.docx`, `CLAUDE.md` | documentación |

## Tareas

- [ ] 1. Migración `083_sueldos_motor.sql`
- [ ] 2. Puras conceptos ARCA: `MARCAS_DEFAULT`, `parseArcaPadron`, `diffConceptosArca`, `buildConceptosTxt`
- [ ] 3. Puras auxiliares: `antiguedadEntre`, `diasVacacionesLCT`, `vigenteA`, `numeroALetras`
- [ ] 4. Motor `computeRecibo` (sin Ganancias) — reproduce el recibo real
- [ ] 5. `computeGanancias` + integración en `computeRecibo`
- [ ] 6. `computeSAC` y `computeLiquidacionFinal`
- [ ] 7. Frontend: catálogo de conceptos ampliado + exportar TXT/Excel + importar padrón
- [ ] 8. Frontend: página Escalas y parámetros (`sueldosparam`)
- [ ] 9. Frontend: legajo ampliado con pestañas + modal de baja
- [ ] 10. Frontend: página Novedades (`sueldosnov`) + precarga desde timers
- [ ] 11. Frontend: liquidación con "Calcular", detalle con origen/traza, payload 083, LSD con bases desde marcas
- [ ] 12. `renderRecibo` (pura) + impresión individual y por lote
- [ ] 13. Docs (manual md + docx, CLAUDE.md, estado de la spec) y cierre

---

### Task 1: Migración `083_sueldos_motor.sql`

**Files:**
- Create: `migrations/083_sueldos_motor.sql`
- Read: `migrations/082_sueldos_lsd.sql` (molde: batería RLS líneas 52-77, RPCs 215-500), `docs/sueldos/referencia/arca-padron-conceptos-2026-09-23.csv`, `docs/sueldos/referencia/LSD-ARMADO-TXT-Conceptos.xlsx` hoja "Conceptos ARCA"

**Interfaces:**
- Produces: tablas `conceptos_arca`, `sueldos_convenio_parametros`, `sueldos_escala`, `sueldos_parametros_previsionales`, `sueldos_ganancias_tablas`, `sueldos_novedades`; columnas nuevas en `conceptos_sueldo`, `empleados`, `liquidacion_conceptos`, `liquidacion_items`, `config_contable`; vista `v_sueldos_acumulados`; RPC `guardar_novedades(p_periodo date, p_tipo text, p_items jsonb) RETURNS jsonb`; `guardar_liquidacion` acepta `conceptos[].origen/traza/base` e `items[].ganancias/contribuciones_detalle`; `confirmar_liquidacion` asigna `recibo_nro`, avanza cuotas de préstamos y cierra el legajo en `final`.

- [ ] **Step 1: Cabecera, batería RLS y catálogo ARCA**

Copiar textualmente las líneas 52-77 de la 082 (`pg_temp.aplicar_bateria` con `modulo_sueldos`). Luego:

```sql
-- ─── 1. Catálogo ARCA de conceptos (referencia global, solo lectura) ──
CREATE TABLE IF NOT EXISTS public.conceptos_arca (
  codigo      text PRIMARY KEY CHECK (codigo ~ '^\d{6}$'),
  familia     text NOT NULL CHECK (familia IN ('remunerativo','no_remunerativo','descuento')),
  descripcion text NOT NULL,
  uso_libre   boolean NOT NULL DEFAULT false,
  rango_hasta text
);
ALTER TABLE public.conceptos_arca ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lectura_todos ON public.conceptos_arca;
CREATE POLICY lectura_todos ON public.conceptos_arca FOR SELECT TO authenticated USING (true);
INSERT INTO public.conceptos_arca (codigo, familia, descripcion, uso_libre, rango_hasta) VALUES
  ('110000','remunerativo','Sueldo',false,NULL),
  ('110001','remunerativo','Preaviso',false,NULL),
  ('110002','remunerativo','Remuneraciones en especie',false,NULL),
  ('110003','remunerativo','Comida',false,NULL),
  ('110004','remunerativo','Habitación',false,NULL),
  ('110005','remunerativo','Licencias por estudio',false,NULL),
  ('110006','remunerativo','Donación de sangre',false,NULL),
  ('110007','remunerativo','Feriado',false,NULL),
  ('110008','remunerativo','Prest. Dineraria Ley 24557 (primeros 10d)',false,NULL),
  ('110009','remunerativo','Prest. Dineraria Ley 24557 (a cargo de ART)',false,NULL),
  ('110010','remunerativo','Sueldo - RG 2252 actividades simultáneas',false,NULL),
  ('110011','remunerativo','Incremento solidario - Dec. 14/2020',false,NULL),
  ('111000','remunerativo','Sueldo - De uso libre',true,'119999'),
  ('120000','remunerativo','Sueldo anual complementario',false,NULL),
  ('120001','remunerativo','SAC 1er semestre',false,NULL),
  ('120002','remunerativo','SAC 2do semestre',false,NULL),
  ('120003','remunerativo','SAC proporcional',false,NULL),
  ('120004','remunerativo','SAC - RG 2252 actividades simultáneas',false,NULL),
  ('121000','remunerativo','SAC - De uso libre',true,'129999'),
  ('130000','remunerativo','Horas extras',false,NULL),
  ('130001','remunerativo','Horas extras al 50 %',false,NULL),
  ('130002','remunerativo','Horas extras al 100 %',false,NULL),
  ('130003','remunerativo','Horas extras al 200 %',false,NULL),
  ('130004','remunerativo','Horas extras - RG 2252 actividades simultáneas',false,NULL),
  ('131000','remunerativo','Horas extras - De uso libre',true,'139999'),
  ('140000','remunerativo','Zona desfavorable',false,NULL),
  ('140001','remunerativo','Zona desfavorable - RG 2252',false,NULL),
  ('141000','remunerativo','Zona desfavorable - De uso libre',true,'149999'),
  ('150000','remunerativo','Adelanto vacacional',false,NULL),
  ('150001','remunerativo','Adelanto vacacional - RG 2252',false,NULL),
  ('151000','remunerativo','Adelanto vacacional - De uso libre',true,'159999'),
  ('160000','remunerativo','Adicionales',false,NULL),
  ('160001','remunerativo','Adicional por antigüedad',false,NULL),
  ('160002','remunerativo','Adicional por título',false,NULL),
  ('160003','remunerativo','Adicional por tarea',false,NULL),
  ('160004','remunerativo','Adicional por desarraigo',false,NULL),
  ('160005','remunerativo','Adicionales - RG 2252',false,NULL),
  ('161000','remunerativo','Adicionales - De uso libre',true,'169999'),
  ('170000','remunerativo','Gratificaciones y/o Premios',false,NULL),
  ('170001','remunerativo','Premio por presentismo',false,NULL),
  ('170002','remunerativo','Premio por producción',false,NULL),
  ('170003','remunerativo','Comisiones',false,NULL),
  ('170004','remunerativo','Accesorios',false,NULL),
  ('170005','remunerativo','Viáticos sin comprobante',false,NULL),
  ('170006','remunerativo','Propinas habituales no prohibidas',false,NULL),
  ('170007','remunerativo','Gratificaciones - RG 2252',false,NULL),
  ('171000','remunerativo','Gratificaciones y/o Premios - De uso libre',true,'179999'),
  ('180000','remunerativo','Rectificativa por remuneración Ley 27.742',false,NULL),
  ('499999','remunerativo','Redondeo (Remunerativo)',false,NULL),
  ('510000','no_remunerativo','Asignaciones Familiares',false,NULL),
  ('510001','no_remunerativo','Ayuda escolar',false,NULL),
  ('510002','no_remunerativo','Asignación por hijo/hijo con discapacidad',false,NULL),
  ('510003','no_remunerativo','Asignación por maternidad',false,NULL),
  ('510004','no_remunerativo','Asignación por maternidad down',false,NULL),
  ('510005','no_remunerativo','Asignación por matrimonio',false,NULL),
  ('510006','no_remunerativo','Asignación por nacimiento / adopción',false,NULL),
  ('510007','no_remunerativo','Asignación por prenatal',false,NULL),
  ('511000','no_remunerativo','Asignaciones Familiares - De uso libre',true,'519999'),
  ('520000','no_remunerativo','Beneficios sociales',false,NULL),
  ('520001','no_remunerativo','Servicio de comedor',false,NULL),
  ('520002','no_remunerativo','Gastos médicos',false,NULL),
  ('520003','no_remunerativo','Provisión de ropa de trabajo',false,NULL),
  ('520004','no_remunerativo','Guardería',false,NULL),
  ('520005','no_remunerativo','Provisión de útiles escolares',false,NULL),
  ('520006','no_remunerativo','Gastos de sepelio',false,NULL),
  ('520007','no_remunerativo','Cursos de capacitación',false,NULL),
  ('520008','no_remunerativo','Becas (art. 7 Ley 24.241)',false,NULL),
  ('520009','no_remunerativo','Desempleo (art. 7 Ley 24.241)',false,NULL),
  ('520010','no_remunerativo','Gratificación por cese laboral (art. 7 Ley 24.241)',false,NULL),
  ('520011','no_remunerativo','Indemnización por extinción del contrato (art. 7 Ley 24.241)',false,NULL),
  ('520012','no_remunerativo','Vacaciones no gozadas (art. 7 Ley 24.241)',false,NULL),
  ('520013','no_remunerativo','Incapacidad permanente (art. 7 Ley 24.241)',false,NULL),
  ('520014','no_remunerativo','Indemnización por despido',false,NULL),
  ('520015','no_remunerativo','Indemnización sustitutiva del preaviso',false,NULL),
  ('520016','no_remunerativo','Integración mes de despido',false,NULL),
  ('520017','no_remunerativo','SAC sobre integración o preaviso',false,NULL),
  ('520018','no_remunerativo','SAC sobre vacaciones no gozadas',false,NULL),
  ('521000','no_remunerativo','Beneficios sociales - De uso libre',true,'529999'),
  ('530000','no_remunerativo','Incrementos no remunerativos (con aportes OS)',false,NULL),
  ('531000','no_remunerativo','Incrementos no rem. (con aportes OS) - De uso libre',true,'539999'),
  ('540000','no_remunerativo','Incrementos no remunerativos (con aportes y contribuciones OS)',false,NULL),
  ('541000','no_remunerativo','Incrementos no rem. (con aportes y contrib. OS) - De uso libre',true,'549999'),
  ('550000','no_remunerativo','Importes no remunerativos especiales',false,NULL),
  ('551000','no_remunerativo','Importes no remunerativos especiales - De uso libre',true,'559999'),
  ('560000','no_remunerativo','Mensual - PPC y CCT Especiales',false,NULL),
  ('560001','no_remunerativo','SAC - PPC y CCT Especiales',false,NULL),
  ('560002','no_remunerativo','SAC Proporcional - PPC y CCT Especiales',false,NULL),
  ('560003','no_remunerativo','Vacaciones - PPC y CCT Especiales',false,NULL),
  ('560004','no_remunerativo','Asign. dineraria progr. sociales - Dec. 551/2022',false,NULL),
  ('560005','no_remunerativo','Asign. No remunerativa Dec 841/2022',false,NULL),
  ('560006','no_remunerativo','Asignación no Remunerativa Dcto 438/2023',false,NULL),
  ('570000','no_remunerativo','Mensual - Remuneración No Contributiva',false,NULL),
  ('570001','no_remunerativo','SAC - Remuneración No Contributiva',false,NULL),
  ('570002','no_remunerativo','SAC Proporcional - Remuneración No Contributiva',false,NULL),
  ('570003','no_remunerativo','Vacaciones - Remuneración No Contributiva',false,NULL),
  ('799999','no_remunerativo','Redondeo (No Remunerativo)',false,NULL),
  ('810000','descuento','Sistema previsional',false,NULL),
  ('810001','descuento','INSSJyP',false,NULL),
  ('810002','descuento','Obra Social',false,NULL),
  ('810003','descuento','Fondo Solidario de Redistribución (ex ANSSAL)',false,NULL),
  ('810004','descuento','Cuota Sindical',false,NULL),
  ('810005','descuento','Seguro de Vida',false,NULL),
  ('810006','descuento','RENATEA (ex RENATRE)',false,NULL),
  ('810007','descuento','Préstamos',false,NULL),
  ('810008','descuento','Impuesto a las Ganancias',false,NULL),
  ('810009','descuento','Obra Social - Adherentes',false,NULL),
  ('810010','descuento','Fondo Solidario de Redistribución - Adherentes',false,NULL),
  ('810011','descuento','Ajuste Aporte Dec. 561/2019',false,NULL),
  ('810012','descuento','Salario complementario Dec 332/2020',false,NULL),
  ('810013','descuento','SAC - Ajuste Bases imponibles',false,NULL),
  ('810014','descuento','Pago a cuenta Asign. dineraria Dec. 551/2022',false,NULL),
  ('810015','descuento','Sistema previsional no nacional',false,NULL),
  ('810016','descuento','Obra Social provincial',false,NULL),
  ('820000','descuento','Otros descuentos',false,NULL),
  ('821000','descuento','Otros descuentos - De uso libre',true,'829999')
ON CONFLICT (codigo) DO NOTHING;
```

- [ ] **Step 2: `conceptos_sueldo` ampliada + import del padrón + conceptos nuevos**

```sql
-- ─── 2. Conceptos del empleador: código ARCA, marcas, regla ─────────
ALTER TABLE public.conceptos_sueldo
  ADD COLUMN IF NOT EXISTS codigo_arca text REFERENCES public.conceptos_arca(codigo),
  ADD COLUMN IF NOT EXISTS repeticion  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS marcas      char(15) NOT NULL DEFAULT '000000000000000' CHECK (marcas ~ '^[01]{15}$'),
  ADD COLUMN IF NOT EXISTS regla       jsonb,
  ADD COLUMN IF NOT EXISTS legacy      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS origen      text NOT NULL DEFAULT 'manual' CHECK (origen IN ('padron','seed','manual'));
COMMENT ON COLUMN public.conceptos_sueldo.marcas IS
  '15 marcas ARCA en orden del CSV: SIPA-A SIPA-C INSSJP-A INSSJP-C OS-A OS-C FSR-A FSR-C REN-A REN-C AAFF FNE LRT DIF ESP';

-- 2a. Padrón ARCA 2026-09-23 (121 filas). Formato: (codigo_arca, codigo, nombre, repeticion, marcas, activo)
--     Activos = canónicos; el resto legacy. Generar las 121 filas con:
--       python3 - <<'EOF'
--       import csv; rows=list(csv.reader(open('docs/sueldos/referencia/arca-padron-conceptos-2026-09-23.csv',encoding='utf-8-sig'),delimiter=';'))[1:]
--       ACT={'1','2','4','5','6','7','8','9','20','28','31','85','102','400','200','201','202','203','204','208','211','900','999','517','521'}
--       for r in rows: print(f"  ('{r[0]}','{r[2]}',{repr(r[3].strip())},{'true' if r[4]=='1' else 'false'},'{''.join(r[5:20])}',{'true' if r[2] in ACT else 'false'}),")
--       EOF
--     y pegar el resultado dentro del VALUES de abajo (reemplazar comillas simples internas por '').
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden, activo, codigo_arca, repeticion, marcas, legacy, origen)
SELECT c.empresa_id, p.codigo, p.nombre,
       CASE a.familia WHEN 'remunerativo' THEN 'remunerativo' WHEN 'no_remunerativo' THEN 'no_remunerativo' ELSE 'descuento' END,
       NULL, 500 + row_number() OVER (), p.activo, p.codigo_arca, p.repeticion, p.marcas, NOT p.activo, 'padron'
FROM public.config_contable c
CROSS JOIN (VALUES
  -- ← pegar acá las 121 filas generadas
  ('110000','4','JORNAL',true,'111111111111100',true)
) AS p(codigo_arca, codigo, nombre, repeticion, marcas, activo)
JOIN public.conceptos_arca a ON a.codigo = p.codigo_arca
ON CONFLICT (empresa_id, codigo) DO UPDATE
  SET codigo_arca = EXCLUDED.codigo_arca, repeticion = EXCLUDED.repeticion,
      marcas = EXCLUDED.marcas, origen = 'padron',
      legacy = EXCLUDED.legacy, activo = EXCLUDED.activo;

-- 2b. Seed 082 (100..900): pasa a legacy inactivo (no está en ARCA)
UPDATE public.conceptos_sueldo SET legacy = true, activo = false
 WHERE origen = 'manual' AND codigo IN ('100','110','120','130','131','140','150','160','190','300','310','320','330','340','350','900')
   AND codigo_arca IS NULL;

-- 2c. Conceptos nuevos del motor (regla declarativa). regla: ver spec §Reglas.
INSERT INTO public.conceptos_sueldo (empresa_id, codigo, nombre, tipo, unidades, orden, activo, codigo_arca, repeticion, marcas, regla, origen)
SELECT c.empresa_id, s.codigo, s.nombre, s.tipo, s.unidades, s.orden, true, s.arca, true, s.marcas, s.regla::jsonb, 'seed'
FROM public.config_contable c CROSS JOIN (VALUES
  ('3','Presentismo','remunerativo',NULL,30,'170001','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"basico_mas_antiguedad","pct_param":"presentismo_pct","cantidad":"1","condicion":"presentismo_ok","orden":30}'),
  ('10','Horas extras 50 %','remunerativo','H',40,'130001','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_hora_extra","factor":1.5,"cantidad":"novedad.hs_extra_50","orden":40}'),
  ('16','Horas extras 100 %','remunerativo','H',41,'130002','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_hora_extra","factor":2,"cantidad":"novedad.hs_extra_100","orden":41}'),
  ('17','Feriado trabajado','remunerativo','H',42,'130002','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_hora_extra","factor":2,"cantidad":"novedad.feriados_trabajados_hs","orden":42}'),
  ('18','Vacaciones','remunerativo','D',50,'150000','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_dia_vacaciones","cantidad":"novedad.vacaciones_dias","orden":50}'),
  ('24','Complemento IMGR','remunerativo',NULL,60,'110000','111111111111100','{"auto":true,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"complemento_imgr","cantidad":"1","orden":60}'),
  ('25','Tarea peligrosa 20 % (art. 65)','remunerativo','%',22,'160003','111111111111100','{"auto":false,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"basico","pct":20,"cantidad":"1","orden":22}'),
  ('26','Altas calorías 20 % (art. 66)','remunerativo','%',23,'160003','111111111111100','{"auto":false,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"basico","pct":20,"cantidad":"1","orden":23}'),
  ('27','Adicional por título','remunerativo','$',24,'160002','111111111111100','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":24}'),
  ('37','Licencia paga','remunerativo','D',45,'111000','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_dia","cantidad":"novedad.licencia_paga_dias","orden":45}'),
  ('64','Premio por producción','remunerativo','$',70,'170002','111111111111100','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"novedad.premio_produccion","orden":70}'),
  ('75','Bono / gratificación','remunerativo','$',71,'170000','111111111111100','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":71}'),
  ('86','Preaviso trabajado','remunerativo','D',80,'110001','111111111111100','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"valor_dia","cantidad":"1","orden":80}'),
  ('106','Viáticos con comprobante','no_remunerativo','$',110,'520000','000000000000000','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":110}'),
  ('205','Aporte solidario UOM','descuento','%',205,'810004','000000000000000','{"auto":true,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"rem_bruto","pct_param":"aporte_solidario_pct","cantidad":"1","condicion":"no_afiliado","orden":205}'),
  ('206','Seguro de sepelio UOM','descuento','$',206,'810005','000000000000000','{"auto":true,"aplica_convenio":"uom","aplica_modalidad":"todos","base":"fijo_param","importe_param":"sepelio_importe","cantidad":"1","orden":206}'),
  ('207','Obra social adherentes 1,5 %','descuento','%',207,'810009','000000000000000','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"rem_topeado","pct_param":"aporte_os_adherente_pct","cantidad":"legajo.adherentes","orden":207}'),
  ('223','Adelanto de sueldo','descuento','$',223,'820000','000000000000000','{"auto":true,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"novedad.adelanto","orden":223}'),
  ('226','Embargo judicial','descuento','$',226,'820000','000000000000000','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","tope_pct_neto":20,"orden":226}'),
  ('227','Cuota de préstamo','descuento','$',227,'810007','000000000000000','{"auto":false,"aplica_convenio":"todos","aplica_modalidad":"todos","base":"fijo","cantidad":"1","orden":227}'),
  ('530','Indemnización por antigüedad art. 245','no_remunerativo',NULL,530,'520014','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":530}'),
  ('531','Indemnización sustitutiva de preaviso','no_remunerativo',NULL,531,'520015','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":531}'),
  ('532','Integración mes de despido','no_remunerativo',NULL,532,'520016','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":532}'),
  ('533','SAC s/ preaviso e integración','no_remunerativo',NULL,533,'520017','000000000000000','{"auto":false,"base":"fijo","cantidad":"1","orden":533}'),
  ('998','Redondeo (crédito)','no_remunerativo',NULL,998,'799999','000000000000000','{"auto":true,"base":"redondeo","cantidad":"1","orden":998}')
) AS s(codigo, nombre, tipo, unidades, orden, arca, marcas, regla)
ON CONFLICT (empresa_id, codigo) DO UPDATE SET regla = EXCLUDED.regla, codigo_arca = EXCLUDED.codigo_arca, marcas = EXCLUDED.marcas, origen = 'seed';

-- 2d. Reglas de los canónicos del padrón (los importados no traen regla)
UPDATE public.conceptos_sueldo c SET regla = r.regla::jsonb, unidades = r.unidades, orden = r.orden
FROM (VALUES
  ('1','{"auto":true,"aplica_modalidad":"mensual","base":"basico","cantidad":"1","orden":10}',NULL,10),
  ('4','{"auto":true,"aplica_modalidad":"jornal","base":"valor_hora","cantidad":"horas_normales","orden":10}','H',10),
  ('5','{"auto":true,"aplica_modalidad":"jornal","base":"valor_hora","factor_horas_dia":true,"cantidad":"novedad.feriados_no_trabajados","orden":43}','D',43),
  ('7','{"auto":true,"base":"valor_dia","cantidad":"novedad.enfermedad_dias","orden":46}','D',46),
  ('8','{"auto":true,"base":"valor_dia","cantidad":"novedad.accidente_dias","orden":47}','D',47),
  ('9','{"auto":true,"base":"basico","pct_param":"antiguedad_pct","cantidad":"legajo.antiguedad_anios","orden":20}','%',20),
  ('6','{"auto":false,"base":"fijo","cantidad":"1","orden":25}','$',25),
  ('102','{"auto":true,"aplica_convenio":"uom","base":"no_rem_paritaria","cantidad":"1","orden":100}',NULL,100),
  ('200','{"auto":true,"base":"rem_topeado","pct_param":"aporte_jubilacion_pct","cantidad":"1","orden":200}','%',200),
  ('201','{"auto":true,"base":"rem_topeado","pct_param":"aporte_inssjp_pct","cantidad":"1","orden":201}','%',201),
  ('202','{"auto":true,"base":"rem_topeado","pct_param":"aporte_os_pct","cantidad":"1","orden":202}','%',202),
  ('203','{"auto":true,"aplica_convenio":"uom","base":"rem_bruto","pct_param":"cuota_sindical_pct","cantidad":"1","condicion":"afiliado","orden":203}','%',203),
  ('204','{"auto":false,"base":"fijo","cantidad":"1","orden":204}','$',204),
  ('208','{"auto":true,"base":"no_rem_os","pct_param":"aporte_os_pct","cantidad":"1","orden":208}','%',208),
  ('211','{"auto":true,"aplica_convenio":"uom","base":"no_rem","pct_param":"cuota_sindical_pct","cantidad":"1","condicion":"afiliado","orden":211}','%',211),
  ('900','{"auto":true,"base":"ganancias","cantidad":"1","condicion":"ganancias_aplica","orden":900}',NULL,900),
  ('999','{"auto":true,"base":"redondeo","cantidad":"1","orden":999}',NULL,999),
  ('20','{"auto":false,"base":"sac","cantidad":"1","orden":15}',NULL,15),
  ('28','{"auto":false,"base":"sac","cantidad":"1","orden":16}','D',16)
) AS r(codigo, regla, unidades, orden)
WHERE c.codigo = r.codigo;
```

- [ ] **Step 3: Escala, parámetros, Ganancias, novedades**

```sql
-- ─── 3. Escala UOM y parámetros con vigencias ────────────────────────
CREATE TABLE IF NOT EXISTS public.sueldos_convenio_parametros (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  vigencia_desde date NOT NULL,
  imgr numeric(14,2) NOT NULL DEFAULT 0, no_rem_paritaria numeric(14,2) NOT NULL DEFAULT 0, no_rem_codigo text NOT NULL DEFAULT '102',
  antiguedad_pct numeric(6,3) NOT NULL DEFAULT 1, horas_mes integer NOT NULL DEFAULT 200, horas_dia numeric(4,2) NOT NULL DEFAULT 8,
  presentismo_pct numeric(6,3) NOT NULL DEFAULT 0, presentismo_tolerancia_dias smallint NOT NULL DEFAULT 0,
  sepelio_importe numeric(14,2) NOT NULL DEFAULT 0, scvo_importe numeric(14,2) NOT NULL DEFAULT 0,
  cuota_sindical_pct numeric(6,3) NOT NULL DEFAULT 2.5, aporte_solidario_pct numeric(6,3) NOT NULL DEFAULT 2,
  redondeo_a numeric(6,2) NOT NULL DEFAULT 10, tope_por_quincena boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (empresa_id, vigencia_desde));
SELECT pg_temp.aplicar_bateria('sueldos_convenio_parametros');

CREATE TABLE IF NOT EXISTS public.sueldos_escala (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  vigencia_desde date NOT NULL, categoria text NOT NULL,
  modalidad text NOT NULL DEFAULT 'jornal' CHECK (modalidad IN ('jornal','mensual')),
  valor_hora numeric(14,2) NOT NULL DEFAULT 0, basico_mensual numeric(14,2) NOT NULL DEFAULT 0,
  orden integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, vigencia_desde, categoria));
SELECT pg_temp.aplicar_bateria('sueldos_escala');
CREATE INDEX IF NOT EXISTS idx_sueldos_escala_cat ON public.sueldos_escala (empresa_id, categoria, vigencia_desde DESC);

CREATE TABLE IF NOT EXISTS public.sueldos_parametros_previsionales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, vigencia_desde date NOT NULL,
  tope_min numeric(14,2) NOT NULL DEFAULT 0, tope_max numeric(14,2) NOT NULL DEFAULT 0, detraccion numeric(14,2) NOT NULL DEFAULT 0,
  aporte_jubilacion_pct numeric(6,3) NOT NULL DEFAULT 11, aporte_inssjp_pct numeric(6,3) NOT NULL DEFAULT 3,
  aporte_os_pct numeric(6,3) NOT NULL DEFAULT 3, aporte_os_adherente_pct numeric(6,3) NOT NULL DEFAULT 1.5,
  tipo_empresa smallint NOT NULL DEFAULT 1,
  contrib_sipa_pct numeric(6,3) NOT NULL DEFAULT 10.77, contrib_inssjp_pct numeric(6,3) NOT NULL DEFAULT 1.59,
  contrib_fne_pct numeric(6,3) NOT NULL DEFAULT 0.94, contrib_aaff_pct numeric(6,3) NOT NULL DEFAULT 4.70,
  contrib_os_pct numeric(6,3) NOT NULL DEFAULT 5.10, contrib_fsr_pct numeric(6,3) NOT NULL DEFAULT 0.90,
  art_pct numeric(6,3) NOT NULL DEFAULT 0, art_fijo numeric(14,2) NOT NULL DEFAULT 0,
  ganancias_tope_retencion_pct numeric(6,2) NOT NULL DEFAULT 35,
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (empresa_id, vigencia_desde));
SELECT pg_temp.aplicar_bateria('sueldos_parametros_previsionales');

CREATE TABLE IF NOT EXISTS public.sueldos_ganancias_tablas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, vigencia_desde date NOT NULL,
  gni_anual numeric(16,2) NOT NULL, deduccion_especial_anual numeric(16,2) NOT NULL,
  conyuge_anual numeric(16,2) NOT NULL, hijo_anual numeric(16,2) NOT NULL, hijo_incap_anual numeric(16,2) NOT NULL,
  tramos jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (empresa_id, vigencia_desde));
SELECT pg_temp.aplicar_bateria('sueldos_ganancias_tablas');

CREATE TABLE IF NOT EXISTS public.sueldos_novedades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL,
  empleado_id uuid NOT NULL REFERENCES public.empleados(id) ON DELETE CASCADE,
  periodo date NOT NULL, tipo text NOT NULL DEFAULT 'mensual' CHECK (tipo IN ('mensual','quincena1','quincena2')),
  dias_trabajados numeric(5,2), horas_normales numeric(6,2), hs_extra_50 numeric(6,2) NOT NULL DEFAULT 0, hs_extra_100 numeric(6,2) NOT NULL DEFAULT 0,
  feriados_no_trabajados smallint NOT NULL DEFAULT 0, feriados_trabajados_hs numeric(6,2) NOT NULL DEFAULT 0,
  ausencias_injustificadas numeric(5,2) NOT NULL DEFAULT 0, enfermedad_dias numeric(5,2) NOT NULL DEFAULT 0, accidente_dias numeric(5,2) NOT NULL DEFAULT 0,
  licencia_paga_dias numeric(5,2) NOT NULL DEFAULT 0, licencia_paga_tipo text, licencia_sin_goce_dias numeric(5,2) NOT NULL DEFAULT 0,
  vacaciones_dias numeric(5,2) NOT NULL DEFAULT 0, adelanto numeric(14,2) NOT NULL DEFAULT 0, premio_produccion numeric(14,2) NOT NULL DEFAULT 0,
  otros jsonb NOT NULL DEFAULT '[]'::jsonb, observaciones text, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (empresa_id, empleado_id, periodo, tipo));
SELECT pg_temp.aplicar_bateria('sueldos_novedades');
CREATE INDEX IF NOT EXISTS idx_sueldos_novedades_per ON public.sueldos_novedades (empresa_id, periodo, tipo);

-- Seeds 2026 (por empresa, sólo si no existen)
INSERT INTO public.sueldos_convenio_parametros (empresa_id, vigencia_desde, no_rem_paritaria)
SELECT empresa_id, '2026-08-01', 80000 FROM public.config_contable ON CONFLICT DO NOTHING;   -- 40.000 por quincena (recibo 09/2026)
INSERT INTO public.sueldos_escala (empresa_id, vigencia_desde, categoria, modalidad, valor_hora, orden)
SELECT c.empresa_id, v.vig::date, s.cat, 'jornal', CASE WHEN s.cat='Ingresante' THEN v.vh ELSE 0 END, s.ord
FROM public.config_contable c
CROSS JOIN (VALUES ('2026-08-01',4485.97),('2026-10-01',4665.41),('2026-12-01',4852.02),('2027-01-01',4949.06),('2027-03-01',5122.28)) v(vig,vh)
CROSS JOIN (VALUES ('Ingresante',1),('Operario',2),('Operario Calificado',3),('Medio Oficial',4),('Operario Especializado',5),('Oficial',6),('Operario Especializado Múltiple',7),('Oficial Múltiple',8)) s(cat,ord)
ON CONFLICT DO NOTHING;
INSERT INTO public.sueldos_escala (empresa_id, vigencia_desde, categoria, modalidad, basico_mensual, orden)
SELECT c.empresa_id, '2026-08-01', s.cat, 'mensual', 0, s.ord FROM public.config_contable c
CROSS JOIN (VALUES ('Administrativo A1',11),('Administrativo A2',12),('Administrativo A3',13),('Administrativo A4',14),('Técnico B1',21),('Técnico B2',22),('Técnico B3',23),('Técnico B4',24),('Técnico B5',25),('Técnico B6',26)) s(cat,ord)
ON CONFLICT DO NOTHING;
INSERT INTO public.sueldos_parametros_previsionales (empresa_id, vigencia_desde, tope_min, tope_max, detraccion)
SELECT empresa_id, '2026-09-01', 144363.55, 4691748.47, 7003.68 FROM public.config_contable ON CONFLICT DO NOTHING;
INSERT INTO public.sueldos_ganancias_tablas (empresa_id, vigencia_desde, gni_anual, deduccion_especial_anual, conyuge_anual, hijo_anual, hijo_incap_anual, tramos)
SELECT empresa_id, '2026-07-01', 6019671.36, 28894422.56, 5669323.06, 2859060.30, 5718120.61,
 '[{"desde":0,"hasta":2336953.69,"fijo":0,"pct":5},{"desde":2336953.69,"hasta":4673907.37,"fijo":116847.68,"pct":9},{"desde":4673907.37,"hasta":7010861.06,"fijo":327173.51,"pct":12},{"desde":7010861.06,"hasta":10516291.59,"fijo":607607.96,"pct":15},{"desde":10516291.59,"hasta":21032583.19,"fijo":1133422.53,"pct":19},{"desde":21032583.19,"hasta":31548874.78,"fijo":3131517.94,"pct":23},{"desde":31548874.78,"hasta":47323312.17,"fijo":5550265.01,"pct":27},{"desde":47323312.17,"hasta":70984968.27,"fijo":9809363.11,"pct":31},{"desde":70984968.27,"hasta":null,"fijo":17144476.49,"pct":35}]'::jsonb
FROM public.config_contable ON CONFLICT DO NOTHING;
-- Migrar los dos campos sueltos de config_contable (082) a la tabla con vigencia
UPDATE public.sueldos_parametros_previsionales p SET tope_max = c.lsd_tope_aportes, detraccion = c.lsd_importe_detraer
FROM public.config_contable c WHERE c.empresa_id = p.empresa_id AND p.vigencia_desde = '2026-09-01'
  AND c.lsd_tope_aportes > 0 AND c.lsd_importe_detraer > 0;
```

- [ ] **Step 4: Legajo, liquidación, config, vista**

```sql
-- ─── 4. Legajo ampliado ──────────────────────────────────────────────
ALTER TABLE public.empleados
  ADD COLUMN IF NOT EXISTS convenio text NOT NULL DEFAULT 'uom' CHECK (convenio IN ('uom','fuera')),
  ADD COLUMN IF NOT EXISTS categoria_escala text,
  ADD COLUMN IF NOT EXISTS sueldo_pactado numeric(14,2),
  ADD COLUMN IF NOT EXISTS horas_semanales numeric(5,2) NOT NULL DEFAULT 48,
  ADD COLUMN IF NOT EXISTS afiliado_sindicato boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS presentismo boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS antiguedad_pct numeric(6,3),
  ADD COLUMN IF NOT EXISTS adicionales_fijos jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS conceptos_recurrentes jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS ganancias_aplica boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ganancias_deducciones jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS hijos_incap smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fecha_ingreso_reconocida date,
  ADD COLUMN IF NOT EXISTS contratacion text, ADD COLUMN IF NOT EXISTS tarea text,
  ADD COLUMN IF NOT EXISTS lugar_pago text NOT NULL DEFAULT 'Casa Central',
  ADD COLUMN IF NOT EXISTS banco_deposito text, ADD COLUMN IF NOT EXISTS causa_egreso text;
UPDATE public.empleados SET convenio = 'fuera' WHERE centro = 'administracion' AND convenio = 'uom';

ALTER TABLE public.liquidacion_conceptos
  ADD COLUMN IF NOT EXISTS origen text NOT NULL DEFAULT 'manual' CHECK (origen IN ('auto','manual')),
  ADD COLUMN IF NOT EXISTS traza jsonb, ADD COLUMN IF NOT EXISTS base numeric(15,2);
ALTER TABLE public.liquidacion_items
  ADD COLUMN IF NOT EXISTS ganancias jsonb, ADD COLUMN IF NOT EXISTS contribuciones_detalle jsonb,
  ADD COLUMN IF NOT EXISTS recibo_nro integer;
ALTER TABLE public.liquidaciones ADD COLUMN IF NOT EXISTS causa_egreso text;
ALTER TABLE public.config_contable
  ADD COLUMN IF NOT EXISTS recibo_prox_nro integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS razon_social_recibo text, ADD COLUMN IF NOT EXISTS domicilio_recibo text,
  ADD COLUMN IF NOT EXISTS actividad_recibo text, ADD COLUMN IF NOT EXISTS f931_ultimo_periodo text,
  ADD COLUMN IF NOT EXISTS f931_ultimo_fecha date, ADD COLUMN IF NOT EXISTS f931_banco text;

-- ─── 5. Acumulados por empleado/año/mes (liquidaciones confirmadas) ──
CREATE OR REPLACE VIEW public.v_sueldos_acumulados AS
SELECT i.empresa_id, i.empleado_id, extract(year from l.periodo)::int AS anio, extract(month from l.periodo)::int AS mes, l.tipo,
       i.bruto, i.no_remunerativo, i.aportes, i.neto,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo = '900'), 0) AS ganancias_retenida,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo IN ('20','28')), 0) AS sac_pagado,
       COALESCE((SELECT sum(c.importe) FROM liquidacion_conceptos c WHERE c.item_id = i.id AND c.codigo IN ('16','17')), 0) AS extras_exentas,
       COALESCE((i.f931->>'dias')::numeric, 30) AS dias_trabajados
FROM liquidacion_items i JOIN liquidaciones l ON l.id = i.liquidacion_id
WHERE l.estado = 'confirmada';
GRANT SELECT ON public.v_sueldos_acumulados TO authenticated;
```

- [ ] **Step 5: RPC `guardar_novedades` + re-emisión de `guardar_liquidacion` y `confirmar_liquidacion`**

```sql
-- ─── 6. guardar_novedades ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.guardar_novedades(p_periodo date, p_tipo text, p_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $$
DECLARE emp uuid := public.current_empresa_id(); it jsonb; n int := 0;
BEGIN
  IF emp IS NULL THEN RAISE EXCEPTION 'Sin empresa asignada'; END IF;
  IF p_tipo NOT IN ('mensual','quincena1','quincena2') THEN RAISE EXCEPTION 'Tipo de novedad inválido'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
    IF NOT EXISTS (SELECT 1 FROM empleados e WHERE e.id = (it->>'empleado_id')::uuid AND e.empresa_id = emp) THEN
      RAISE EXCEPTION 'Empleado inexistente'; END IF;
    INSERT INTO sueldos_novedades (empresa_id, empleado_id, periodo, tipo, dias_trabajados, horas_normales, hs_extra_50, hs_extra_100,
      feriados_no_trabajados, feriados_trabajados_hs, ausencias_injustificadas, enfermedad_dias, accidente_dias, licencia_paga_dias,
      licencia_paga_tipo, licencia_sin_goce_dias, vacaciones_dias, adelanto, premio_produccion, otros, observaciones)
    VALUES (emp, (it->>'empleado_id')::uuid, p_periodo, p_tipo,
      NULLIF(it->>'dias_trabajados','')::numeric, NULLIF(it->>'horas_normales','')::numeric,
      COALESCE((it->>'hs_extra_50')::numeric,0), COALESCE((it->>'hs_extra_100')::numeric,0),
      COALESCE((it->>'feriados_no_trabajados')::int,0), COALESCE((it->>'feriados_trabajados_hs')::numeric,0),
      COALESCE((it->>'ausencias_injustificadas')::numeric,0), COALESCE((it->>'enfermedad_dias')::numeric,0), COALESCE((it->>'accidente_dias')::numeric,0),
      COALESCE((it->>'licencia_paga_dias')::numeric,0), NULLIF(it->>'licencia_paga_tipo',''), COALESCE((it->>'licencia_sin_goce_dias')::numeric,0),
      COALESCE((it->>'vacaciones_dias')::numeric,0), COALESCE((it->>'adelanto')::numeric,0), COALESCE((it->>'premio_produccion')::numeric,0),
      CASE WHEN jsonb_typeof(it->'otros')='array' THEN it->'otros' ELSE '[]'::jsonb END, it->>'observaciones')
    ON CONFLICT (empresa_id, empleado_id, periodo, tipo) DO UPDATE SET
      dias_trabajados = EXCLUDED.dias_trabajados, horas_normales = EXCLUDED.horas_normales, hs_extra_50 = EXCLUDED.hs_extra_50,
      hs_extra_100 = EXCLUDED.hs_extra_100, feriados_no_trabajados = EXCLUDED.feriados_no_trabajados, feriados_trabajados_hs = EXCLUDED.feriados_trabajados_hs,
      ausencias_injustificadas = EXCLUDED.ausencias_injustificadas, enfermedad_dias = EXCLUDED.enfermedad_dias, accidente_dias = EXCLUDED.accidente_dias,
      licencia_paga_dias = EXCLUDED.licencia_paga_dias, licencia_paga_tipo = EXCLUDED.licencia_paga_tipo, licencia_sin_goce_dias = EXCLUDED.licencia_sin_goce_dias,
      vacaciones_dias = EXCLUDED.vacaciones_dias, adelanto = EXCLUDED.adelanto, premio_produccion = EXCLUDED.premio_produccion,
      otros = EXCLUDED.otros, observaciones = EXCLUDED.observaciones;
    n := n + 1;
  END LOOP;
  RETURN jsonb_build_object('guardadas', n);
END $$;
REVOKE ALL ON FUNCTION public.guardar_novedades(date, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.guardar_novedades(date, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.guardar_novedades(date, text, jsonb) TO authenticated;
```

`guardar_liquidacion`: copiar íntegra la de la 082 (líneas 215-363) y cambiar sólo dos INSERT:

```sql
    -- INSERT liquidacion_items: agregar las 2 columnas nuevas
    INSERT INTO liquidacion_items (empresa_id, liquidacion_id, empleado_id, bruto,
      no_remunerativo, aportes, neto, contribuciones, art, detalle, observaciones, f931, ganancias, contribuciones_detalle)
    VALUES (emp, v_id, (it->>'empleado_id')::uuid, v_bruto, v_norem, v_aportes, v_neto,
            COALESCE((it->>'contribuciones')::numeric,0), COALESCE((it->>'art')::numeric,0),
            it->'detalle', it->>'observaciones',
            CASE WHEN jsonb_typeof(it->'f931') = 'object' THEN it->'f931' ELSE NULL END,
            CASE WHEN jsonb_typeof(it->'ganancias') = 'object' THEN it->'ganancias' ELSE NULL END,
            CASE WHEN jsonb_typeof(it->'contribuciones_detalle') = 'array' THEN it->'contribuciones_detalle' ELSE NULL END)
    RETURNING id INTO v_item_id;
    -- INSERT liquidacion_conceptos: agregar origen / traza / base
        INSERT INTO liquidacion_conceptos (empresa_id, liquidacion_id, item_id, empleado_id,
          codigo, cantidad, unidades, importe, dc, periodo_ajuste, orden, origen, traza, base)
        VALUES (emp, v_id, v_item_id, (it->>'empleado_id')::uuid,
          cc->>'codigo', COALESCE((cc->>'cantidad')::numeric, 0),
          NULLIF(cc->>'unidades',''), round(COALESCE((cc->>'importe')::numeric, 0), 2),
          v_dc, NULLIF(cc->>'periodo_ajuste',''), v_orden,
          CASE WHEN cc->>'origen' = 'auto' THEN 'auto' ELSE 'manual' END,
          CASE WHEN jsonb_typeof(cc->'traza') = 'object' THEN cc->'traza' ELSE NULL END,
          NULLIF(cc->>'base','')::numeric);
```

Además, en el loop de validación, rechazar conceptos `legacy`:
```sql
        IF EXISTS (SELECT 1 FROM conceptos_sueldo c WHERE c.empresa_id = emp AND c.codigo = cc->>'codigo' AND c.legacy) THEN
          RAISE EXCEPTION 'El concepto % es histórico (legacy) — usá el código vigente', cc->>'codigo';
        END IF;
```

`confirmar_liquidacion`: copiar íntegra la de la 082 (líneas 365-495) y, antes del `UPDATE liquidaciones SET estado = 'confirmada'`, agregar:

```sql
  -- 083: numerador de recibos, cuotas de préstamos, cierre de legajo en final
  FOR r IN SELECT i.id, i.empleado_id FROM liquidacion_items i WHERE i.liquidacion_id = p_liq_id ORDER BY i.created_at LOOP
    UPDATE config_contable SET recibo_prox_nro = recibo_prox_nro + 1 WHERE empresa_id = emp RETURNING recibo_prox_nro - 1 INTO v_nro;
    UPDATE liquidacion_items SET recibo_nro = v_nro WHERE id = r.id;
    -- préstamo 227 incluido → cuotas_pagadas + 1 en el legajo
    IF EXISTS (SELECT 1 FROM liquidacion_conceptos c WHERE c.item_id = r.id AND c.codigo = '227') THEN
      UPDATE empleados e SET conceptos_recurrentes = (
        SELECT COALESCE(jsonb_agg(CASE WHEN x->>'codigo' = '227' THEN x || jsonb_build_object('cuotas_pagadas', COALESCE((x->>'cuotas_pagadas')::int,0) + 1) ELSE x END), '[]'::jsonb)
        FROM jsonb_array_elements(e.conceptos_recurrentes) x)
      WHERE e.id = r.empleado_id;
    END IF;
    IF l.tipo = 'final' THEN
      UPDATE empleados SET activo = false, fecha_egreso = COALESCE(fecha_egreso, v_fin_mes), causa_egreso = COALESCE(causa_egreso, l.causa_egreso)
       WHERE id = r.empleado_id;
    END IF;
  END LOOP;
```
(declarar `r record; v_nro int;` en el DECLARE). Grants finales idénticos a la 082 §10 + los de `guardar_novedades`.

- [ ] **Step 6: Bloque VERIFICACIÓN y validación local**

```sql
-- SELECT (SELECT count(*) FROM conceptos_arca) AS arca,                         -- 111
--        (SELECT count(*) FROM conceptos_sueldo WHERE origen='padron') AS padron, -- 121
--        (SELECT count(*) FROM conceptos_sueldo WHERE origen='seed' AND regla IS NOT NULL) AS seed, -- 25
--        (SELECT count(*) FROM sueldos_escala) AS escala,                        -- 50 (8 cat × 5 vig + 10 mensuales)
--        (SELECT count(*) FROM pg_policies WHERE tablename='sueldos_novedades') AS pol; -- 6
```
Validar como la 082: `psql` local con el esquema stub de `tests/contabilidad-db.sql` + tablas 065/082, `\i migrations/083_sueldos_motor.sql`, correr la verificación. Comprobar que `\d conceptos_sueldo` muestra `marcas char(15)`.

- [ ] **Step 7: Commit**

```bash
git add migrations/083_sueldos_motor.sql
git commit -m "feat(sueldos): migración 083 — catálogo ARCA, conceptos con marcas y regla, escala/parámetros/Ganancias, novedades, legajo ampliado, acumulados"
```

---

### Task 2: Puras de conceptos ARCA

**Files:**
- Modify: `index.html` (bloque puras, después de `buildLSD`)
- Test: `tests/sueldos-conceptos-arca.test.js`

**Interfaces:**
- Produces: `MARCAS_DEFAULT(tipo, codigoArca) → string(15)`; `parseArcaPadron(csvText) → {filas:[{codigo_arca, codigo, nombre, repeticion, marcas}], errores:[]}`; `diffConceptosArca(padronFilas, catalogo) → {soloArca:[...], soloErp:[...], marcasDistintas:[{codigo, erp, arca}]}`; `buildConceptosTxt(catalogo, {soloFaltantes, padron}) → {lineas, txt, errores}`; `ARCA_MARCAS_POS` (posiciones 168-186 con "libre").

- [ ] **Step 1: Test**

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'); const path = require('path');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const CSV = fs.readFileSync(path.join(__dirname, '..', 'docs/sueldos/referencia/arca-padron-conceptos-2026-09-23.csv'), 'utf8');

test('MARCAS_DEFAULT: remunerativo todo 1 salvo DIF/ESP; descuento todo 0; 540000 OS/FSR; 550000 + LRT', () => {
  assert.equal(run(`MARCAS_DEFAULT('remunerativo','110000')`), '111111111111100');
  assert.equal(run(`MARCAS_DEFAULT('descuento','810000')`), '000000000000000');
  assert.equal(run(`MARCAS_DEFAULT('no_remunerativo','540000')`), '000011110000000');
  assert.equal(run(`MARCAS_DEFAULT('no_remunerativo','550000')`), '000011110000100');
  assert.equal(run(`MARCAS_DEFAULT('no_remunerativo','520014')`), '000000000000000');
});
test('parseArcaPadron: 121 filas, BOM, marcas de 15, repetición', () => {
  const r = run(`parseArcaPadron(${J(CSV)})`);
  assert.equal(r.errores.length, 0); assert.equal(r.filas.length, 121);
  const jornal = r.filas.find(f => f.codigo === '4');
  assert.deepEqual(jornal, { codigo_arca: '110000', codigo: '4', nombre: 'JORNAL', repeticion: true, marcas: '111111111111100' });
  assert.equal(r.filas.find(f => f.codigo === '104').marcas, '000011110000000');
});
test('diffConceptosArca: sólo en ARCA, sólo en ERP, marcas distintas', () => {
  const padron = [{ codigo: '4', codigo_arca: '110000', marcas: '111111111111100' }, { codigo: '52', codigo_arca: '110000', marcas: '111111111111100' }];
  const cat = [{ codigo: '4', codigo_arca: '110000', marcas: '111111111111100', activo: true }, { codigo: '10', codigo_arca: '130001', marcas: '111111111111100', activo: true }, { codigo: '52', codigo_arca: '110000', marcas: '000000000000000', legacy: true }];
  const d = run(`diffConceptosArca(${J(padron)},${J(cat)})`);
  assert.deepEqual(d.soloArca, []); assert.deepEqual(d.soloErp.map(c => c.codigo), ['10']);
  assert.deepEqual(d.marcasDistintas, [{ codigo: '52', erp: '000000000000000', arca: '111111111111100' }]);
});
test('buildConceptosTxt: 195 posiciones, ASCII, marcas intercaladas con libres, sólo faltantes', () => {
  const cat = [{ codigo: '10', nombre: 'Horas extras 50 %', tipo: 'remunerativo', codigo_arca: '130001', repeticion: true, marcas: '111111111111100', activo: true },
               { codigo: '4', nombre: 'Jornal', tipo: 'remunerativo', codigo_arca: '110000', repeticion: true, marcas: '111111111111100', activo: true },
               { codigo: '52', nombre: 'x', tipo: 'remunerativo', codigo_arca: '110000', marcas: '111111111111100', activo: false, legacy: true }];
  const r = run(`buildConceptosTxt(${J(cat)},{soloFaltantes:true,padron:[{codigo:'4'}]})`);
  assert.equal(r.errores.length, 0); assert.equal(r.lineas.length, 1);
  const l = r.lineas[0]; assert.equal(l.length, 195);
  assert.equal(l.slice(0, 6), '130001'); assert.equal(l.slice(6, 16), '10        ');
  assert.equal(l.slice(16, 166).trim(), 'Horas extras 50 %'); assert.equal(l[166], '1');
  assert.equal(l.slice(166, 186), '11111111111 1 1 10 0');   // rep + 19 (igual al ejemplo de la planilla, pos. 167-186)
  assert.equal(r.txt.endsWith('\r\n'), true);
  const sin = run(`buildConceptosTxt([{codigo:'9',nombre:'A',tipo:'remunerativo',codigo_arca:null,marcas:'111111111111100',activo:true}],{})`);
  assert.match(sin.errores[0], /sin código ARCA/);
});
```

- [ ] **Step 2: Correr y ver fallar** — `node --test tests/sueldos-conceptos-arca.test.js` → FAIL `MARCAS_DEFAULT is not defined`.

- [ ] **Step 3: Implementación**

```js
// ─── Sueldos 083: motor de liquidación — conceptos ARCA ───────────────
// 15 marcas en orden del CSV de ARCA. Posición en el registro de 195:
// 167 repetición · 168-177 las 10 primeras (SIPA-A..REN-C) · 178 libre · 179 AAFF · 180 libre · 181 FNE · 182 libre · 183 LRT · 184 DIF · 185 libre · 186 ESP · 187-195 libre
const ARCA_MARCAS_NOMBRES=['SIPA-A','SIPA-C','INSSJP-A','INSSJP-C','OS-A','OS-C','FSR-A','FSR-C','RENATEA-A','RENATEA-C','AAFF-C','FNE-C','LRT-C','DIF-A','ESP-A'];
function MARCAS_DEFAULT(tipo,codigoArca){
  if(tipo==='remunerativo')return '111111111111100';
  if(tipo!=='no_remunerativo')return '000000000000000';
  const fam=String(codigoArca||'').slice(0,2);
  if(fam==='53')return '000010100000000';          // aportes OS + FSR
  if(fam==='54')return '000011110000000';          // aportes y contribuciones OS + FSR
  if(fam==='55')return '000011110000100';          // ídem + LRT (padrón real)
  return '000000000000000';
}
function parseArcaPadron(texto){
  const errores=[];const filas=[];
  const lineas=String(texto||'').replace(/^﻿/,'').split(/\r?\n/).filter(l=>l.trim());
  if(!lineas.length)return {filas,errores:['Archivo vacío']};
  const hdr=lineas[0].split(';');
  if(hdr.length<20||!/C.digo AFIP/i.test(hdr[0]))errores.push('No parece el padrón de conceptos de ARCA (esperaba 20 columnas con "Código AFIP")');
  lineas.slice(1).forEach((l,i)=>{
    const c=l.split(';').map(x=>x.trim());
    if(c.length<20){errores.push(`Línea ${i+2}: ${c.length} columnas`);return;}
    const marcas=c.slice(5,20).map(x=>x==='1'?'1':'0').join('');
    filas.push({codigo_arca:c[0],codigo:c[2],nombre:c[3],repeticion:c[4]==='1',marcas});
  });
  return {filas,errores};
}
function diffConceptosArca(padron,catalogo){
  const porErp={};(catalogo||[]).forEach(c=>{porErp[c.codigo]=c;});
  const porArca={};(padron||[]).forEach(p=>{porArca[p.codigo]=p;});
  const soloArca=(padron||[]).filter(p=>!porErp[p.codigo]);
  const soloErp=(catalogo||[]).filter(c=>!c.legacy&&c.activo!==false&&!porArca[c.codigo]);
  const marcasDistintas=(padron||[]).filter(p=>porErp[p.codigo]&&porErp[p.codigo].marcas!==p.marcas).map(p=>({codigo:p.codigo,erp:porErp[p.codigo].marcas,arca:p.marcas}));
  return {soloArca,soloErp,marcasDistintas};
}
function buildConceptosTxt(catalogo,{soloFaltantes=false,padron=[]}={}){
  const errores=[];const enArca=new Set((padron||[]).map(p=>p.codigo));
  const lista=(catalogo||[]).filter(c=>c.activo!==false&&!c.legacy&&c.tipo!=='informativo').filter(c=>!soloFaltantes||!enArca.has(c.codigo))
    .slice().sort((a,b)=>(a.orden||0)-(b.orden||0));
  const lineas=[];
  lista.forEach(c=>{
    if(!/^\d{6}$/.test(String(c.codigo_arca||''))){errores.push(`${c.codigo} ${c.nombre}: sin código ARCA`);return;}
    const m=String(c.marcas||'').padEnd(15,'0');
    const flags=m.slice(0,10)+' '+m[10]+' '+m[11]+' '+m[12]+m[13]+' '+m[14];   // 19 chars (168-186)
    lineas.push(c.codigo_arca+lsdStr(c.codigo,10)+lsdStr(c.nombre,150)+(c.repeticion===false?'0':'1')+flags+' '.repeat(9));
  });
  lineas.forEach((l,i)=>{if(l.length!==195)errores.push(`Línea ${i+1}: largo ${l.length} ≠ 195`);});
  return {lineas,txt:lineas.join('\r\n')+(lineas.length?'\r\n':''),errores};
}
```

- [ ] **Step 4: Correr** — `node --test tests/sueldos-conceptos-arca.test.js` → 4 PASS. Suite completa verde.

- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): puras ARCA — marcas por defecto, parser del padrón, diff y TXT de conceptos (195)"`

---

### Task 3: Puras auxiliares de fechas, vacaciones, vigencias y letras

**Files:**
- Modify: `index.html` (bloque puras 083)
- Test: `tests/sueldos-motor.test.js` (primer bloque)

**Interfaces:**
- Produces: `antiguedadEntre(desdeISO, hastaISO) → {anios, meses, dias, texto:'0a 4m 20d'}`; `diasVacacionesLCT(aniosAl3112, diasTrabajadosAnio) → int`; `vigenteA(lista, fechaISO, campo='vigencia_desde') → fila|null` (la de mayor vigencia ≤ fecha); `numeroALetras(n) → 'TRESCIENTOS NOVENTA Y CINCO MIL TRESCIENTOS DIEZ'` (entero, mayúsculas, sin "PESOS"); `diasPeriodo(tipo) → 30|15`; `finPeriodo(periodoISO, tipo) → 'YYYY-MM-DD'` (día 15 para quincena1, último día del mes para el resto).

- [ ] **Step 1: Test**

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;

test('antiguedadEntre: años/meses/días cumplidos (recibo: 27/04/2026 → 15/09/2026 = 0a 4m 19d; 01/09 → 30/09 = 0a 0m 29d)', () => {
  assert.deepEqual(run(`antiguedadEntre('2026-04-27','2026-09-15')`), { anios: 0, meses: 4, dias: 19, texto: '0a 4m 19d' });
  assert.deepEqual(run(`antiguedadEntre('2023-03-10','2026-09-30')`), { anios: 3, meses: 6, dias: 20, texto: '3a 6m 20d' });
  assert.equal(run(`antiguedadEntre(null,'2026-09-30')`).anios, 0);
});
test('diasVacacionesLCT: <6 meses 1 cada 20 trabajados; 14/21/28/35', () => {
  assert.equal(run(`diasVacacionesLCT(0, 100)`), 5);
  assert.equal(run(`diasVacacionesLCT(0, 365)`), 14);   // ≥ 6 meses en el año → 14
  assert.equal(run(`diasVacacionesLCT(5, 365)`), 14);
  assert.equal(run(`diasVacacionesLCT(6, 365)`), 21);
  assert.equal(run(`diasVacacionesLCT(11, 365)`), 28);
  assert.equal(run(`diasVacacionesLCT(21, 365)`), 35);
});
test('vigenteA: mayor vigencia ≤ fecha, null si ninguna', () => {
  const l = [{ vigencia_desde: '2026-08-01', v: 'a' }, { vigencia_desde: '2026-10-01', v: 'b' }, { vigencia_desde: '2026-12-01', v: 'c' }];
  assert.equal(run(`vigenteA(${J(l)},'2026-09-30').v`), 'a');
  assert.equal(run(`vigenteA(${J(l)},'2026-10-01').v`), 'b');
  assert.equal(run(`vigenteA(${J(l)},'2026-07-31')`), null);
});
test('numeroALetras: recibo real y casos borde', () => {
  assert.equal(run(`numeroALetras(395310)`), 'TRESCIENTOS NOVENTA Y CINCO MIL TRESCIENTOS DIEZ');
  assert.equal(run(`numeroALetras(0)`), 'CERO');
  assert.equal(run(`numeroALetras(21)`), 'VEINTIUNO');
  assert.equal(run(`numeroALetras(100)`), 'CIEN');
  assert.equal(run(`numeroALetras(1000000)`), 'UN MILLON');
  assert.equal(run(`numeroALetras(2500116)`), 'DOS MILLONES QUINIENTOS MIL CIENTO DIECISEIS');
});
test('diasPeriodo / finPeriodo', () => {
  assert.equal(run(`diasPeriodo('quincena1')`), 15); assert.equal(run(`diasPeriodo('mensual')`), 30);
  assert.equal(run(`finPeriodo('2026-09-01','quincena1')`), '2026-09-15');
  assert.equal(run(`finPeriodo('2026-09-01','quincena2')`), '2026-09-30');
  assert.equal(run(`finPeriodo('2026-02-01','mensual')`), '2026-02-28');
});
```

- [ ] **Step 2: Correr y ver fallar** — `node --test tests/sueldos-motor.test.js` → FAIL `antiguedadEntre is not defined`.

- [ ] **Step 3: Implementación**

```js
// ─── Sueldos 083: auxiliares ──────────────────────────────────────────
function antiguedadEntre(desde,hasta){
  if(!desde||!hasta)return {anios:0,meses:0,dias:0,texto:'0a 0m 0d'};
  const d=new Date(desde+'T00:00:00Z'),h=new Date(hasta+'T00:00:00Z');
  let anios=h.getUTCFullYear()-d.getUTCFullYear(),meses=h.getUTCMonth()-d.getUTCMonth(),dias=h.getUTCDate()-d.getUTCDate();
  if(dias<0){meses--;dias+=new Date(Date.UTC(h.getUTCFullYear(),h.getUTCMonth(),0)).getUTCDate();}
  if(meses<0){anios--;meses+=12;}
  if(anios<0)return {anios:0,meses:0,dias:0,texto:'0a 0m 0d'};
  return {anios,meses,dias,texto:`${anios}a ${meses}m ${dias}d`};
}
// LCT art. 150/153: <6 meses de antigüedad → 1 día cada 20 trabajados; hasta 5 años 14; hasta 10: 21; hasta 20: 28; más: 35
function diasVacacionesLCT(anios,diasTrabajadosAnio){
  if(anios<=0&&diasTrabajadosAnio<180)return Math.floor(diasTrabajadosAnio/20);
  if(anios<=5)return 14;if(anios<=10)return 21;if(anios<=20)return 28;return 35;
}
function vigenteA(lista,fecha,campo='vigencia_desde'){
  return (lista||[]).filter(x=>x[campo]&&x[campo]<=fecha).sort((a,b)=>b[campo].localeCompare(a[campo]))[0]||null;
}
function diasPeriodo(tipo){return tipo==='quincena1'||tipo==='quincena2'?15:30;}
function finPeriodo(periodo,tipo){
  const [y,m]=periodo.slice(0,7).split('-').map(Number);
  if(tipo==='quincena1')return `${y}-${String(m).padStart(2,'0')}-15`;
  return `${y}-${String(m).padStart(2,'0')}-${String(new Date(Date.UTC(y,m,0)).getUTCDate()).padStart(2,'0')}`;
}
function numeroALetras(n){
  n=Math.floor(Math.abs(Number(n)||0));if(n===0)return 'CERO';
  const U=['','UNO','DOS','TRES','CUATRO','CINCO','SEIS','SIETE','OCHO','NUEVE','DIEZ','ONCE','DOCE','TRECE','CATORCE','QUINCE','DIECISEIS','DIECISIETE','DIECIOCHO','DIECINUEVE','VEINTE','VEINTIUNO','VEINTIDOS','VEINTITRES','VEINTICUATRO','VEINTICINCO','VEINTISEIS','VEINTISIETE','VEINTIOCHO','VEINTINUEVE'];
  const D=['','','','TREINTA','CUARENTA','CINCUENTA','SESENTA','SETENTA','OCHENTA','NOVENTA'];
  const C=['','CIENTO','DOSCIENTOS','TRESCIENTOS','CUATROCIENTOS','QUINIENTOS','SEISCIENTOS','SETECIENTOS','OCHOCIENTOS','NOVECIENTOS'];
  const cientos=x=>{if(x===0)return '';if(x===100)return 'CIEN';const c=Math.floor(x/100),r=x%100;
    const d=r<30?U[r]:(D[Math.floor(r/10)]+(r%10?' Y '+U[r%10]:''));return [C[c],d].filter(Boolean).join(' ');};
  const partes=[];
  const mill=Math.floor(n/1e6),miles=Math.floor((n%1e6)/1000),resto=n%1000;
  if(mill)partes.push(mill===1?'UN MILLON':cientos(mill)+' MILLONES');
  if(miles)partes.push(miles===1?'MIL':cientos(miles)+' MIL');
  if(resto)partes.push(cientos(resto));
  return partes.join(' ').replace(/VEINTIUNO MIL/,'VEINTIUN MIL').replace(/UNO MIL/,'UN MIL');
}
```

- [ ] **Step 4: Correr** — 5 PASS. Suite verde.
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): auxiliares del motor — antigüedad, vacaciones LCT, vigencias, número en letras, períodos"`

---

### Task 4: Motor `computeRecibo` (sin Ganancias) — reproduce el recibo real

**Files:**
- Modify: `index.html` (bloque puras 083)
- Test: `tests/sueldos-motor.test.js` (segundo bloque)

**Interfaces:**
- Consumes: Task 3, `computeItemDesdeConceptos` (082), `MARCAS_DEFAULT`.
- Produces:
```js
computeRecibo({empleado, periodo, tipo, novedad, escala, convenio, previsional, ganTabla, catalogo, acumulados, hoy})
→ {conceptos:[{codigo, cantidad, unidades, importe, dc, origen:'auto', base, traza:{formula}}],
   totales:{bruto, no_remunerativo, aportes, neto},
   bases:{rem_bruto, no_rem, no_rem_os, rem_topeado, tope_max_prorr, dias_trabajados, horas_normales, factor_periodo, factor_jornada},
   f931:{dias, horas, rem_bruta, base1..base10, detraer},
   contribuciones:[{codigo, nombre, pct, base, importe}], contribuciones_total, art,
   ganancias:null|{...}, alertas:[string]}
```
`empleado` = fila de `empleados`; `escala` = fila de `sueldos_escala` vigente para la categoría (o null); `convenio` = fila de `sueldos_convenio_parametros` vigente; `previsional` = fila vigente; `catalogo` = `conceptosSueldo`; `acumulados` = `{ganancias:{...}|null}` (Task 5); `novedad` = fila de `sueldos_novedades` o null.

- [ ] **Step 1: Test del recibo real (1ª quincena 09/2026, ingresante, 90 h + 9 h feriado)**

```js
const CAT = [ // subconjunto del catálogo 083 con reglas (mismos jsonb de la migración)
  { codigo:'4', nombre:'Jornal', tipo:'remunerativo', codigo_arca:'110000', marcas:'111111111111100', regla:{auto:true,aplica_modalidad:'jornal',base:'valor_hora',cantidad:'horas_normales',orden:10} },
  { codigo:'5', nombre:'Feriado', tipo:'remunerativo', codigo_arca:'110007', marcas:'111111111111100', regla:{auto:true,aplica_modalidad:'jornal',base:'valor_hora',factor_horas_dia:true,cantidad:'novedad.feriados_no_trabajados',orden:43} },
  { codigo:'9', nombre:'Antigüedad', tipo:'remunerativo', codigo_arca:'160001', marcas:'111111111111100', regla:{auto:true,base:'basico',pct_param:'antiguedad_pct',cantidad:'legajo.antiguedad_anios',orden:20} },
  { codigo:'3', nombre:'Presentismo', tipo:'remunerativo', codigo_arca:'170001', marcas:'111111111111100', regla:{auto:true,base:'basico_mas_antiguedad',pct_param:'presentismo_pct',cantidad:'1',condicion:'presentismo_ok',orden:30} },
  { codigo:'10', nombre:'Horas extras 50 %', tipo:'remunerativo', codigo_arca:'130001', marcas:'111111111111100', regla:{auto:true,base:'valor_hora_extra',factor:1.5,cantidad:'novedad.hs_extra_50',orden:40} },
  { codigo:'24', nombre:'Complemento IMGR', tipo:'remunerativo', codigo_arca:'110000', marcas:'111111111111100', regla:{auto:true,aplica_convenio:'uom',base:'complemento_imgr',cantidad:'1',orden:60} },
  { codigo:'102', nombre:'Gratif extraord no rem', tipo:'no_remunerativo', codigo_arca:'540000', marcas:'000011110000000', regla:{auto:true,aplica_convenio:'uom',base:'no_rem_paritaria',cantidad:'1',orden:100} },
  { codigo:'200', nombre:'Jubilación', tipo:'descuento', codigo_arca:'810000', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_jubilacion_pct',cantidad:'1',orden:200} },
  { codigo:'201', nombre:'Ley 19032', tipo:'descuento', codigo_arca:'810001', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_inssjp_pct',cantidad:'1',orden:201} },
  { codigo:'202', nombre:'Obra social', tipo:'descuento', codigo_arca:'810002', marcas:'000000000000000', regla:{auto:true,base:'rem_topeado',pct_param:'aporte_os_pct',cantidad:'1',orden:202} },
  { codigo:'203', nombre:'Sindicato UOM', tipo:'descuento', codigo_arca:'810004', marcas:'000000000000000', regla:{auto:true,aplica_convenio:'uom',base:'rem_bruto',pct_param:'cuota_sindical_pct',cantidad:'1',condicion:'afiliado',orden:203} },
  { codigo:'211', nombre:'Sindicato s/no rem', tipo:'descuento', codigo_arca:'810004', marcas:'000000000000000', regla:{auto:true,aplica_convenio:'uom',base:'no_rem',pct_param:'cuota_sindical_pct',cantidad:'1',condicion:'afiliado',orden:211} },
  { codigo:'208', nombre:'Obra social s/no rem', tipo:'descuento', codigo_arca:'810002', marcas:'000000000000000', regla:{auto:true,base:'no_rem_os',pct_param:'aporte_os_pct',cantidad:'1',orden:208} },
  { codigo:'998', nombre:'Redondeo', tipo:'no_remunerativo', codigo_arca:'799999', marcas:'000000000000000', regla:{auto:true,base:'redondeo',cantidad:'1',orden:998} },
  { codigo:'999', nombre:'Redondeo', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:true,base:'redondeo',cantidad:'1',orden:999} },
];
const CONV = { vigencia_desde:'2026-08-01', imgr:0, no_rem_paritaria:80000, no_rem_codigo:'102', antiguedad_pct:1, horas_mes:200, horas_dia:8, presentismo_pct:0, presentismo_tolerancia_dias:0, sepelio_importe:0, scvo_importe:849.24, cuota_sindical_pct:2.5, aporte_solidario_pct:2, redondeo_a:10, tope_por_quincena:true };
const PREV = { vigencia_desde:'2026-09-01', tope_min:144363.55, tope_max:4691748.47, detraccion:7003.68, aporte_jubilacion_pct:11, aporte_inssjp_pct:3, aporte_os_pct:3, aporte_os_adherente_pct:1.5, tipo_empresa:1, contrib_sipa_pct:10.77, contrib_inssjp_pct:1.59, contrib_fne_pct:0.94, contrib_aaff_pct:4.70, contrib_os_pct:5.10, contrib_fsr_pct:0.90, art_pct:0, art_fijo:0, ganancias_tope_retencion_pct:35 };
const EMP = { id:'e1', nombre:'AYALA, RODRIGO', convenio:'uom', modalidad:'jornal', categoria_escala:'Ingresante', fecha_ingreso:'2026-04-27', fecha_ingreso_reconocida:'2026-09-01', horas_semanales:48, afiliado_sindicato:true, presentismo:true, adherentes:0, adicionales_fijos:[], conceptos_recurrentes:[], ganancias_aplica:false };
const ESC = { vigencia_desde:'2026-08-01', categoria:'Ingresante', modalidad:'jornal', valor_hora:4485.97, basico_mensual:0 };
const NOV = { horas_normales:90, hs_extra_50:0, hs_extra_100:0, feriados_no_trabajados:1, feriados_trabajados_hs:0, ausencias_injustificadas:0, enfermedad_dias:0, accidente_dias:0, licencia_paga_dias:0, licencia_sin_goce_dias:0, vacaciones_dias:0, adelanto:0, premio_produccion:0, otros:[] };
function recibo(over) {
  return run(`computeRecibo(${J(Object.assign({ empleado:EMP, periodo:'2026-09-01', tipo:'quincena1', novedad:NOV, escala:ESC, convenio:CONV, previsional:PREV, ganTabla:null, catalogo:CAT, acumulados:{}, hoy:'2026-09-18' }, over || {}))})`);
}
const imp = (r, cod) => (r.conceptos.find(c => c.codigo === cod) || {}).importe;

test('computeRecibo: reproduce el recibo real de la 1ª quincena 09/2026', () => {
  const r = recibo();
  assert.equal(imp(r,'4'), 403737.30); assert.equal(imp(r,'5'), 40373.73);
  assert.equal(r.conceptos.find(c=>c.codigo==='9'), undefined);          // 0 años → no se genera
  assert.equal(imp(r,'102'), 40000);                                      // 80.000/mes × 0,5 quincena
  assert.equal(imp(r,'200'), 48852.21); assert.equal(imp(r,'201'), 13323.33); assert.equal(imp(r,'202'), 13323.33);
  assert.equal(imp(r,'203'), 11102.78); assert.equal(imp(r,'211'), 1000); assert.equal(imp(r,'208'), 1200);
  assert.equal(imp(r,'998'), 0.62); assert.equal(r.conceptos.find(c=>c.codigo==='999'), undefined);
  assert.deepEqual(r.totales, { bruto:444111.03, no_remunerativo:40000.62, aportes:88801.65, neto:395310 });
  assert.equal(r.bases.rem_topeado, 444111.03);
  const contrib = Object.fromEntries(r.contribuciones.map(c => [c.codigo, c.importe]));
  assert.deepEqual(contrib, { '640':424.62, '642':7005.69, '643':4357.00, '644':47453.61, '645':24689.66, '646':4141.73, '647':20708.63 });
  assert.equal(r.contribuciones_total, 108780.94);
  assert.equal(r.f931.base1, 444111.03); assert.equal(r.f931.base4, 484111.03); assert.equal(r.f931.base8, 484111.03);
  assert.equal(r.f931.base9, 484111.03); assert.equal(r.f931.detraer, 3501.84); assert.equal(r.f931.base10, 440609.19);
  assert.equal(r.f931.rem_bruta, 484111.65); assert.equal(r.f931.horas, 99); assert.equal(r.f931.dias, 0);
  assert.equal(r.conceptos.every(c => c.origen === 'auto' && c.traza && c.traza.formula), true);
});
test('computeRecibo: mensual UOM con antigüedad, presentismo, extras, ausencia (pierde presentismo) y ART', () => {
  const emp = { ...EMP, modalidad:'mensual', categoria_escala:'Administrativo A2', fecha_ingreso:'2023-03-10', fecha_ingreso_reconocida:null };
  const esc = { vigencia_desde:'2026-08-01', categoria:'Administrativo A2', modalidad:'mensual', valor_hora:0, basico_mensual:1200000 };
  const conv = { ...CONV, presentismo_pct:8.33, imgr:1500000 };
  const nov = { ...NOV, horas_normales:null, hs_extra_50:10, hs_extra_100:4, feriados_no_trabajados:0, ausencias_injustificadas:1 };
  const cat = CAT.concat([{ codigo:'16', nombre:'Horas extras 100 %', tipo:'remunerativo', codigo_arca:'130002', marcas:'111111111111100', regla:{auto:true,base:'valor_hora_extra',factor:2,cantidad:'novedad.hs_extra_100',orden:41} }]);
  const r = recibo({ empleado:emp, escala:esc, convenio:conv, novedad:nov, tipo:'mensual', catalogo:cat, previsional:{ ...PREV, art_pct:3, art_fijo:1000 } });
  // básico 1.200.000 × 29/30 = 1.160.000 (1 ausencia injustificada); antigüedad 3 años × 1 % = 34.800 → 1.194.800
  assert.equal(imp(r,'1'), 1160000); assert.equal(imp(r,'9'), 34800);
  assert.equal(r.conceptos.find(c=>c.codigo==='3'), undefined);            // presentismo perdido
  // valor hora extra = (1.200.000 + 36.000) / 200 = 6.180 → 50 %: 6.180×1,5×10 = 92.700 · 100 %: 6.180×2×4 = 49.440
  assert.equal(imp(r,'10'), 92700); assert.equal(imp(r,'16'), 49440);
  // IMGR: 1.194.800 + 80.000 (no rem) = 1.274.800 < 1.500.000 → complemento 225.200
  assert.equal(imp(r,'24'), 225200);
  assert.equal(r.bases.rem_bruto, 1562140);                                // 1.160.000+34.800+92.700+49.440+225.200
  assert.equal(r.art, 47864.20);                                            // 3 % × 1.562.140 + 1.000
  assert.ok(r.alertas.some(a => /presentismo/i.test(a)));
});
test('computeRecibo: fuera de convenio, mes de ingreso (20 días), tope máximo de aportes, sin sindicato ni no rem', () => {
  const emp = { ...EMP, convenio:'fuera', modalidad:'mensual', categoria_escala:null, sueldo_pactado:7500000, fecha_ingreso:'2026-09-11', fecha_ingreso_reconocida:null, afiliado_sindicato:false };
  const r = recibo({ empleado:emp, escala:null, novedad:null, tipo:'mensual' });
  assert.equal(imp(r,'1'), 5000000);                                       // 7.500.000 × 20/30
  assert.equal(r.conceptos.find(c=>c.codigo==='102'), undefined); assert.equal(r.conceptos.find(c=>c.codigo==='203'), undefined);
  assert.equal(r.bases.tope_max_prorr, 3127832.31);                        // 4.691.748,47 × 20/30
  assert.equal(imp(r,'200'), 344061.55);                                   // 11 % del tope prorrateado
  assert.equal(r.f931.dias, 20); assert.equal(r.f931.detraer, 4669.12);    // 7.003,68 × 20/30
  assert.ok(r.alertas.some(a => /tope/i.test(a)));
});
test('computeRecibo: recurrentes (préstamo con última cuota, embargo tope 20 % del neto), adelanto y premio', () => {
  const emp = { ...EMP, conceptos_recurrentes:[{codigo:'227',importe:50000,cuotas_total:3,cuotas_pagadas:2,desde:'2026-07-01'},{codigo:'226',importe:200000,desde:'2026-01-01'}] };
  const cat = CAT.concat([{ codigo:'227', nombre:'Cuota préstamo', tipo:'descuento', codigo_arca:'810007', marcas:'000000000000000', regla:{auto:false,base:'fijo',cantidad:'1',orden:227} },
                          { codigo:'226', nombre:'Embargo', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:false,base:'fijo',cantidad:'1',tope_pct_neto:20,orden:226} },
                          { codigo:'223', nombre:'Adelanto', tipo:'descuento', codigo_arca:'820000', marcas:'000000000000000', regla:{auto:true,base:'fijo',cantidad:'novedad.adelanto',orden:223} },
                          { codigo:'64', nombre:'Premio', tipo:'remunerativo', codigo_arca:'170002', marcas:'111111111111100', regla:{auto:true,base:'fijo',cantidad:'novedad.premio_produccion',orden:70} }]);
  const r = recibo({ empleado:emp, catalogo:cat, novedad:{ ...NOV, adelanto:30000, premio_produccion:25000 } });
  assert.equal(imp(r,'64'), 25000); assert.equal(imp(r,'223'), 30000); assert.equal(imp(r,'227'), 50000);
  assert.ok(r.alertas.some(a => /última cuota/i.test(a)));
  // neto antes de embargo: (444.111,03+25.000) rem + 40.000 − aportes(17 % de 469.111,03 + 2,5 % ... ) → embargo = min(200.000, 20 % de ese neto)
  const netoSinEmbargo = r.totales.neto + imp(r,'226') - (imp(r,'998')||0) + (imp(r,'999')||0);
  assert.ok(Math.abs(imp(r,'226') - Math.round(netoSinEmbargo*0.2*100)/100) < 1);
});
```

- [ ] **Step 2: Correr y ver fallar** — FAIL `computeRecibo is not defined`.

- [ ] **Step 3: Implementación**

```js
// ─── Sueldos 083: motor de liquidación (puro) ─────────────────────────
// Ver docs/superpowers/specs/2026-09-23-sueldos-motor-liquidacion-design.md §Motor.
const CONTRIB_CODIGOS={scvo:'640',inssjp:'642',fsr:'643',sipa:'644',os:'645',fne:'646',aaff:'647',art:'648'};
function computeRecibo(ctx){
  const r2=x=>Math.round(x*100)/100;
  const e=ctx.empleado||{},nov=ctx.novedad||{},conv=ctx.convenio||{},prev=ctx.previsional||{},esc=ctx.escala||null;
  const tipo=ctx.tipo||'mensual',periodo=ctx.periodo,fin=finPeriodo(periodo,tipo);
  const ini=tipo==='quincena2'?periodo.slice(0,8)+'16':periodo.slice(0,8)+'01';
  const alertas=[],conceptos=[];
  const num=v=>Number(v)||0;
  const cat=(ctx.catalogo||[]).filter(c=>c.activo!==false&&!c.legacy);
  const porCod={};cat.forEach(c=>{porCod[c.codigo]=c;});
  const esUom=(e.convenio||'uom')==='uom',esJornal=(e.modalidad||'jornal')==='jornal';
  const dPer=diasPeriodo(tipo),fPer=dPer/30,fJor=Math.min(1,num(e.horas_semanales||48)/48);
  const horasDia=num(conv.horas_dia)||8,horasMes=num(conv.horas_mes)||200;
  // 1. Días base
  let diasCal=dPer;
  if(e.fecha_ingreso&&e.fecha_ingreso>ini){diasCal-=Math.round((Date.parse(e.fecha_ingreso)-Date.parse(ini))/86400000);}
  if(e.fecha_egreso&&e.fecha_egreso<fin){diasCal-=Math.round((Date.parse(fin)-Date.parse(e.fecha_egreso))/86400000);}
  diasCal=Math.max(0,Math.min(dPer,diasCal));
  const ausencias=num(nov.ausencias_injustificadas)+num(nov.licencia_sin_goce_dias);
  const diasTrab=Math.max(0,(nov.dias_trabajados!=null?num(nov.dias_trabajados):diasCal)-ausencias-num(nov.vacaciones_dias));
  const horasNorm=esJornal?(nov.horas_normales!=null?num(nov.horas_normales):diasTrab*horasDia*fJor):0;
  const parcial=diasCal<dPer||num(nov.vacaciones_dias)>0;   // mes de ingreso/egreso o vacaciones → tope prorrateado
  if(!e.fecha_ingreso)alertas.push('Sin fecha de ingreso: antigüedad 0');
  if(!nov||!Object.keys(nov).length)alertas.push('Sin novedades cargadas: se asume período completo');
  // 2. Básico
  let valorHora=0,basicoMensual=0,basico=0;
  if(esUom){
    if(!esc)alertas.push(`Categoría "${e.categoria_escala||''}" sin valor en la escala vigente`);
    valorHora=num(esc?.valor_hora);basicoMensual=num(esc?.basico_mensual);
    if(esJornal)basico=r2(valorHora*horasNorm);else basico=r2(basicoMensual*fPer*diasTrab/dPer);
  }else{
    basicoMensual=num(e.sueldo_pactado);basico=r2(basicoMensual*fPer*diasTrab/dPer);
    if(!basicoMensual)alertas.push('Fuera de convenio sin sueldo pactado');
  }
  // 3. Antigüedad
  const antPct=esUom?num(conv.antiguedad_pct):num(e.antiguedad_pct);
  const anios=antiguedadEntre(e.fecha_ingreso_reconocida||e.fecha_ingreso,fin).anios;
  const antig=r2(basico*antPct/100*anios);
  // 4. Adicionales fijos (pct sobre básico o importe)
  let adicPct=0,adicImp=0;const adic=[];
  (e.adicionales_fijos||[]).forEach(a=>{const c=porCod[a.codigo];if(!c)return;
    const imp=a.pct!=null?r2(basico*num(a.pct)/100):r2(num(a.importe)*fPer);
    if(a.pct!=null)adicPct+=num(a.pct);adicImp+=imp;adic.push({c,imp,formula:a.pct!=null?`${basico} × ${a.pct} %`:`${a.importe} × ${fPer}`});});
  // 5. Presentismo
  const presOk=e.presentismo!==false&&num(nov.ausencias_injustificadas)<=num(conv.presentismo_tolerancia_dias);
  if(!presOk&&num(conv.presentismo_pct)>0)alertas.push('Presentismo perdido por ausencias injustificadas');
  // 6. Valor hora extra / valor día
  const vhe=esJornal?r2(valorHora*(1+antPct*anios/100+adicPct/100)):r2((basicoMensual*fPer+antig+r2(basico*adicPct/100))/(horasMes*fPer));
  const valorDia=esJornal?r2(valorHora*horasDia):r2(basicoMensual/30);
  const valorDiaVac=esJornal?r2(valorHora*horasDia):r2((basicoMensual+r2(basicoMensual*antPct/100*anios)+r2(basicoMensual*adicPct/100))/25);
  const noRemParit=esUom?r2(num(conv.no_rem_paritaria)*fJor*fPer*(diasTrab+num(nov.vacaciones_dias))/dPer):0;
  // ── Evaluación de reglas ──
  const bases={basico,basico_mas_antiguedad:r2(basico+antig),valor_hora:valorHora,valor_hora_extra:vhe,valor_dia:valorDia,valor_dia_vacaciones:valorDiaVac,no_rem_paritaria:noRemParit};
  const cantidadDe=(regla)=>{const k=regla.cantidad||'1';if(k==='1')return 1;if(k==='horas_normales')return horasNorm;
    if(k==='legajo.antiguedad_anios')return anios;if(k==='legajo.adherentes')return num(e.adherentes);
    if(k.startsWith('novedad.'))return num(nov[k.slice(8)]);return num(k);};
  const aplica=(c)=>{const g=c.regla||{};
    if(g.aplica_convenio&&g.aplica_convenio!=='todos'&&g.aplica_convenio!==(esUom?'uom':'fuera'))return false;
    if(g.aplica_modalidad&&g.aplica_modalidad!=='todos'&&g.aplica_modalidad!==(esJornal?'jornal':'mensual'))return false;
    if(g.condicion==='presentismo_ok'&&!presOk)return false;
    if(g.condicion==='afiliado'&&e.afiliado_sindicato===false)return false;
    if(g.condicion==='no_afiliado'&&e.afiliado_sindicato!==false)return false;
    if(g.condicion==='ganancias_aplica'&&!e.ganancias_aplica)return false;
    return true;};
  const push=(c,cantidad,importe,base,formula,extra)=>{importe=r2(importe);if(!(importe>0))return;
    conceptos.push(Object.assign({codigo:c.codigo,cantidad:r2(Math.min(999.99,cantidad)),unidades:c.unidades||'',importe,dc:c.tipo==='descuento'?'D':'C',
      origen:'auto',base:r2(base),traza:{regla:c.regla?.base,formula},periodo_ajuste:''},extra||{}));};
  // Haberes (remunerativos y no remunerativos) en orden
  cat.filter(c=>c.tipo!=='descuento'&&c.regla?.auto&&aplica(c)).sort((a,b)=>(a.regla.orden||0)-(b.regla.orden||0)).forEach(c=>{
    const g=c.regla,q=cantidadDe(g);
    switch(g.base){
      case 'basico':{const pct=g.pct!=null?num(g.pct):num(conv[g.pct_param]||e[g.pct_param]||0);const p=g.pct_param==='antiguedad_pct'?antPct:pct;
        push(c,q,basico*p/100*q,basico,`${basico} × ${p} % × ${q}`);break;}
      case 'basico_mas_antiguedad':{const p=num(conv[g.pct_param]);push(c,q,(basico+antig)*p/100*q,basico+antig,`${r2(basico+antig)} × ${p} %`);break;}
      case 'valor_hora':{const f=g.factor_horas_dia?horasDia:1;push(c,q,valorHora*f*q*(g.factor||1),valorHora,`${valorHora} × ${f*q} h`);break;}
      case 'valor_hora_extra':push(c,q,vhe*(g.factor||1)*q,vhe,`${vhe} × ${g.factor||1} × ${q} h`);break;
      case 'valor_dia':push(c,q,valorDia*q,valorDia,`${valorDia} × ${q} d`);break;
      case 'valor_dia_vacaciones':push(c,q,valorDiaVac*q,valorDiaVac,`${valorDiaVac} × ${q} d`);break;
      case 'no_rem_paritaria':push(c,1,noRemParit,noRemParit,`${conv.no_rem_paritaria} × ${fPer} × ${diasTrab+num(nov.vacaciones_dias)}/${dPer}`);break;
      case 'fijo':push(c,q>1?q:1,g.importe!=null?num(g.importe)*q:q,q,`${q}`);break;
      case 'complemento_imgr':{const piso=r2(num(conv.imgr)*fJor*fPer);const suma=conceptos.filter(x=>!['10','16','17'].includes(x.codigo)).reduce((a,x)=>a+x.importe,0);
        if(piso>0&&suma<piso)push(c,1,piso-suma,piso,`${piso} − ${r2(suma)}`);break;}
      default:break;   // sac, ganancias, redondeo: se resuelven aparte
    }
  });
  // Adicionales fijos y recurrentes del legajo (auto=false pero cargados en el legajo)
  adic.forEach(a=>push(a.c,1,a.imp,basico,a.formula));
  (e.conceptos_recurrentes||[]).forEach(rc=>{const c=porCod[rc.codigo];if(!c||c.tipo==='descuento')return;
    if(rc.desde&&rc.desde>fin)return;if(rc.hasta&&rc.hasta<ini)return;
    push(c,1,num(rc.importe)*fPer,num(rc.importe),`${rc.importe} × ${fPer}`);});
  (nov.otros||[]).forEach(o=>{const c=porCod[o.codigo];if(!c)return;push(c,num(o.cantidad)||1,num(o.importe),num(o.importe),'novedad');});
  // Bases
  const remBruto=r2(conceptos.filter(x=>porCod[x.codigo].tipo==='remunerativo').reduce((a,x)=>a+x.importe,0));
  const noRem=r2(conceptos.filter(x=>porCod[x.codigo].tipo==='no_remunerativo').reduce((a,x)=>a+x.importe,0));
  const noRemOs=r2(conceptos.filter(x=>porCod[x.codigo].tipo==='no_remunerativo'&&(porCod[x.codigo].marcas||'')[4]==='1').reduce((a,x)=>a+x.importe,0));
  const fTope=parcial?diasCal/30:(conv.tope_por_quincena!==false?fPer:1);
  const topeMax=r2(num(prev.tope_max)*fTope),topeMin=r2(num(prev.tope_min)*fTope);
  let remTopeado=remBruto;if(topeMax>0&&remBruto>topeMax){remTopeado=topeMax;alertas.push(`Remuneración supera el tope máximo de aportes (${topeMax})`);}
  if(topeMin>0&&remTopeado<topeMin&&remBruto>0)remTopeado=topeMin;
  const basesD={rem_bruto:remBruto,no_rem:noRem,no_rem_os:noRemOs,rem_topeado:remTopeado,fijo_param:0};
  // Descuentos
  cat.filter(c=>c.tipo==='descuento'&&c.regla?.auto&&aplica(c)).sort((a,b)=>(a.regla.orden||0)-(b.regla.orden||0)).forEach(c=>{
    const g=c.regla,q=cantidadDe(g);if(['ganancias','redondeo'].includes(g.base))return;
    if(g.base==='fijo'){push(c,1,q,q,`${q}`);return;}
    if(g.base==='fijo_param'){push(c,1,num(conv[g.importe_param])*fPer,num(conv[g.importe_param]),`${conv[g.importe_param]} × ${fPer}`);return;}
    const b=basesD[g.base]||0,p=num(prev[g.pct_param]??conv[g.pct_param]);
    push(c,q>1?q:p,b*p/100*(q||1),b,`${b} × ${p} % × ${q||1}`);
  });
  (e.conceptos_recurrentes||[]).forEach(rc=>{const c=porCod[rc.codigo];if(!c||c.tipo!=='descuento')return;
    if(rc.desde&&rc.desde>fin)return;if(rc.hasta&&rc.hasta<ini)return;
    if(rc.cuotas_total&&num(rc.cuotas_pagadas)>=num(rc.cuotas_total))return;
    let imp=num(rc.importe);const t=computeItemDesdeConceptos(conceptos,cat);
    if(c.regla?.tope_pct_neto){const max=r2(t.neto*num(c.regla.tope_pct_neto)/100);if(imp>max){imp=max;alertas.push(`${c.nombre}: limitado al ${c.regla.tope_pct_neto} % del neto`);}}
    if(rc.cuotas_total&&num(rc.cuotas_pagadas)+1>=num(rc.cuotas_total))alertas.push(`${c.nombre}: última cuota (${num(rc.cuotas_pagadas)+1}/${rc.cuotas_total})`);
    push(c,1,imp,imp,rc.cuotas_total?`cuota ${num(rc.cuotas_pagadas)+1}/${rc.cuotas_total}`:'recurrente');});
  // Ganancias (Task 5) — se enchufa acá
  let gan=null;
  if(e.ganancias_aplica&&typeof computeGanancias==='function'&&ctx.ganTabla&&['mensual','quincena2','sac','final'].includes(tipo)){
    gan=computeGanancias({empleado:e,periodo,tipo,conceptos,catalogo:cat,tabla:ctx.ganTabla,acumulados:ctx.acumulados?.ganancias||null,previsional:prev,remBruto,noRem});
    const c900=porCod['900'];if(c900&&gan.retencion_mes>0)push(c900,1,gan.retencion_mes,gan.gnsi_acum,gan.formula);
    if(gan.retencion_mes<0&&porCod['901'])push(porCod['901'],1,-gan.retencion_mes,0,'devolución Ganancias');
  }
  // Redondeo
  const rd=num(conv.redondeo_a);
  if(rd>0){const t=computeItemDesdeConceptos(conceptos,cat);const obj=Math.ceil(t.neto/rd)*rd;const dif=r2(obj-t.neto);
    if(dif>0&&porCod['998'])push(porCod['998'],1,dif,t.neto,`${obj} − ${t.neto}`);}
  const totales=computeItemDesdeConceptos(conceptos,cat);
  // Contribuciones patronales
  const detr=r2(num(prev.detraccion)*(parcial?diasCal/30:fPer));
  const baseSipa=Math.max(0,r2(remTopeado-detr)),baseOs=r2(remBruto+noRemOs);
  const contribuciones=[
    {codigo:'640',nombre:'SVC',pct:null,base:r2(num(conv.scvo_importe)*fPer),importe:r2(num(conv.scvo_importe)*fPer)},
    {codigo:'642',nombre:'CONTRIBUCION INSSJP',pct:num(prev.contrib_inssjp_pct),base:baseSipa,importe:r2(baseSipa*num(prev.contrib_inssjp_pct)/100)},
    {codigo:'643',nombre:'CONTRIBUCION ANSSAL',pct:num(prev.contrib_fsr_pct),base:baseOs,importe:r2(baseOs*num(prev.contrib_fsr_pct)/100)},
    {codigo:'644',nombre:'CONTRIBUCION JUBILACION',pct:num(prev.contrib_sipa_pct),base:baseSipa,importe:r2(baseSipa*num(prev.contrib_sipa_pct)/100)},
    {codigo:'645',nombre:'CONTRIBUCION OBRA SOCIAL',pct:num(prev.contrib_os_pct),base:baseOs,importe:r2(baseOs*num(prev.contrib_os_pct)/100)},
    {codigo:'646',nombre:'CONTRIBUCION FONDO DESEMPLEO',pct:num(prev.contrib_fne_pct),base:baseSipa,importe:r2(baseSipa*num(prev.contrib_fne_pct)/100)},
    {codigo:'647',nombre:'CONTRIBUCION SUBSIDIO FAMILIAR',pct:num(prev.contrib_aaff_pct),base:baseSipa,importe:r2(baseSipa*num(prev.contrib_aaff_pct)/100)},
  ].filter(x=>x.importe>0);
  const art=r2(remBruto*num(prev.art_pct)/100+num(prev.art_fijo)*fPer);
  const contribTotal=r2(contribuciones.reduce((a,x)=>a+x.importe,0));
  // F.931 desde marcas: base_i = Σ importes con marca i (índices del CSV: 0 SIPA-A,1 SIPA-C,4 OS-A,2 INSSJP-A,13 DIF,14 ESP,5 OS-C,12 LRT,10 AAFF)
  const sumMarca=i=>r2(conceptos.filter(x=>(porCod[x.codigo].marcas||'')[i]==='1').reduce((a,x)=>a+x.importe,0));
  const cap=v=>topeMax>0?Math.min(v,topeMax):v;
  const f931={dias:esJornal?0:Math.round(diasTrab+num(nov.vacaciones_dias)),horas:esJornal?Math.round(horasNorm+num(nov.feriados_no_trabajados)*horasDia):0,
    rem_bruta:r2(remBruto+noRem),detraer:detr,base1:cap(sumMarca(0)),base2:sumMarca(1),base3:sumMarca(10),base4:cap(sumMarca(4)),base5:cap(sumMarca(2)),
    base6:sumMarca(13),base7:sumMarca(14),base8:sumMarca(5),base9:sumMarca(12),base10:Math.max(0,r2(sumMarca(1)-detr))};
  return {conceptos,totales,bases:{rem_bruto:remBruto,no_rem:noRem,no_rem_os:noRemOs,rem_topeado:remTopeado,tope_max_prorr:topeMax,dias_trabajados:diasTrab,horas_normales:horasNorm,factor_periodo:fPer,factor_jornada:fJor,valor_hora:valorHora,valor_hora_extra:vhe,antiguedad_anios:anios},
    f931,contribuciones,contribuciones_total:contribTotal,art,ganancias:gan,alertas};
}
```

Notas de implementación: el orden de `push` de haberes sigue `regla.orden`; el complemento IMGR (orden 60) se evalúa después de básico/antigüedad/presentismo/adicionales (≤ 30) y antes de extras (40+)? **No**: en la spec el IMGR excluye extras y feriados trabajados, por eso en `complemento_imgr` se filtran los códigos 10/16/17. El no rem 102 (orden 100) entra a la suma del IMGR sólo si ya fue evaluado: poner orden 59 al 102 en la migración (2d) para que quede antes del 24. Corregir en Task 1 §2d: `('102', …,"orden":59)`.

- [ ] **Step 4: Correr** — `node --test tests/sueldos-motor.test.js` → 9 PASS (5 de Task 3 + 4). Si algún centavo difiere del recibo real, el error está en el orden de redondeo: cada concepto se redondea a 2 decimales **antes** de sumar (así hace el sistema de la contadora).
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): computeRecibo — motor de reglas, bases, aportes con topes, contribuciones, F.931 desde marcas (reproduce recibo real 09/2026)"`

---

### Task 5: `computeGanancias` (RG 4003, acumulado) + integración

**Files:**
- Modify: `index.html` (bloque puras 083, antes de `computeRecibo`)
- Test: `tests/sueldos-ganancias.test.js`

**Interfaces:**
- Consumes: `vigenteA`, tabla `sueldos_ganancias_tablas` (fila), acumulados del año (`v_sueldos_acumulados` agregada por el frontend).
- Produces:
```js
computeGanancias({empleado, periodo, tipo, conceptos, catalogo, tabla, acumulados, previsional, remBruto, noRem})
→ {mes, rem_gravada_mes, rem_gravada_acum, deducciones_personales_acum, deducciones_f572_acum, gnsi_acum,
   impuesto_acum, retenido_previo, retencion_mes, tope_aplicado, tabla_vigencia, formula}
```
`acumulados` = `{rem_gravada_acum, retenido_previo, sac_prorrateado_acum, sac_real_acum}` de los meses anteriores del año (null en enero o sin historial). `tipo='sac'`: no suma doceavo, suma el SAC real y descuenta los doceavos ya prorrateados del semestre. `tipo='final'`: idem SAC + cierra el año al mes de egreso.

- [ ] **Step 1: Test**

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const TABLA = { vigencia_desde:'2026-07-01', gni_anual:6019671.36, deduccion_especial_anual:28894422.56, conyuge_anual:5669323.06, hijo_anual:2859060.30, hijo_incap_anual:5718120.61,
  tramos:[{desde:0,hasta:2336953.69,fijo:0,pct:5},{desde:2336953.69,hasta:4673907.37,fijo:116847.68,pct:9},{desde:4673907.37,hasta:7010861.06,fijo:327173.51,pct:12},{desde:7010861.06,hasta:10516291.59,fijo:607607.96,pct:15},{desde:10516291.59,hasta:21032583.19,fijo:1133422.53,pct:19},{desde:21032583.19,hasta:31548874.78,fijo:3131517.94,pct:23},{desde:31548874.78,hasta:47323312.17,fijo:5550265.01,pct:27},{desde:47323312.17,hasta:70984968.27,fijo:9809363.11,pct:31},{desde:70984968.27,hasta:null,fijo:17144476.49,pct:35}] };
const CAT = [{codigo:'1',tipo:'remunerativo'},{codigo:'16',tipo:'remunerativo'},{codigo:'200',tipo:'descuento'},{codigo:'201',tipo:'descuento'},{codigo:'202',tipo:'descuento'},{codigo:'203',tipo:'descuento'},{codigo:'223',tipo:'descuento'}];
const PREV = { aporte_jubilacion_pct:11, aporte_inssjp_pct:3, aporte_os_pct:3, ganancias_tope_retencion_pct:35 };
const conc = (bruto, extras100=0) => [{codigo:'1',importe:bruto},{codigo:'16',importe:extras100},{codigo:'200',importe:(bruto+extras100)*0.11},{codigo:'201',importe:(bruto+extras100)*0.03},{codigo:'202',importe:(bruto+extras100)*0.03}];
const gan = (o) => run(`computeGanancias(${J(Object.assign({ empleado:{ganancias_aplica:true,conyuge:false,hijos:0,hijos_incap:0,ganancias_deducciones:[]}, periodo:'2026-01-01', tipo:'mensual', conceptos:conc(5000000), catalogo:CAT, tabla:TABLA, acumulados:null, previsional:PREV, remBruto:5000000, noRem:0 }, o))})`);

test('computeGanancias: enero, soltero sin deducciones, 5.000.000 brutos → 229.345,78 (cálculo a mano RG 4003)', () => {
  const g = gan();
  // rem gravada = (5.000.000 + 416.666,67 SAC 1/12) × (1 − 17 %) = 4.495.833,33
  assert.equal(g.rem_gravada_acum, 4495833.33);
  assert.equal(g.deducciones_personales_acum, 2909507.83);              // (GNI + especial) / 12
  assert.equal(g.gnsi_acum, 1586325.50);
  assert.equal(g.impuesto_acum, 229345.78);                              // tramo 5: 94.451,88 + 19 % × (1.586.325,50 − 876.357,63)
  assert.equal(g.retencion_mes, 229345.78); assert.equal(g.tabla_vigencia, '2026-07-01');
});
test('computeGanancias: febrero acumula y descuenta lo retenido; cónyuge + 1 hijo + alquiler con tope 40 % GNI', () => {
  const emp = { ganancias_aplica:true, conyuge:true, hijos:1, hijos_incap:0, ganancias_deducciones:[{tipo:'alquiler',importe_mensual:900000,periodo_desde:'2026-01',periodo_hasta:'2026-12'}] };
  const g = gan({ empleado:emp, periodo:'2026-02-01', acumulados:{ rem_gravada_acum:4495833.33, retenido_previo:229345.78, sac_prorrateado_acum:416666.67, sac_real_acum:0 } });
  assert.equal(g.rem_gravada_acum, 8991666.66);
  // personales: (6.019.671,36 + 28.894.422,56 + 5.669.323,06 + 2.859.060,30) × 2/12 = 7.240.412,88
  assert.equal(g.deducciones_personales_acum, 7240412.88);
  // alquiler: 1.800.000 pagados, tope 40 % de GNI acum (1.003.278,56 × 0,4 = 401.311,42)
  assert.equal(g.deducciones_f572_acum, 401311.42);
  assert.equal(g.gnsi_acum, 1349942.36);
  // tramos × 2/12: hasta 389.492,28 (5 %), 778.984,56 (9 %), 1.168.476,84 (12 %), 1.752.715,27 (15 %) → tramo 4: 101.267,99 + 15 % × (1.349.942,36 − 1.168.476,84)
  assert.equal(g.impuesto_acum, 128487.82);
  assert.equal(g.retencion_mes, -100857.96);                             // devolución
});
test('computeGanancias: horas extras 100 % exentas y tope 35 % del bruto', () => {
  const g = gan({ conceptos:conc(3000000, 2000000), remBruto:5000000, previsional:{ ...PREV, ganancias_tope_retencion_pct:1 } });
  assert.equal(g.rem_gravada_mes, 2075000 + 207500);                     // (3.000.000 × 0,83) + SAC 1/12 de 3.000.000 × 0,83
  assert.equal(g.tope_aplicado, true); assert.equal(g.retencion_mes, 50000);   // 1 % de 5.000.000
});
test('computeGanancias: junio SAC — reemplaza doceavos por el SAC real', () => {
  const g = gan({ tipo:'sac', periodo:'2026-06-01', conceptos:[{codigo:'1',importe:2500000},{codigo:'200',importe:275000},{codigo:'201',importe:75000},{codigo:'202',importe:75000}], remBruto:2500000,
    acumulados:{ rem_gravada_acum:22479166.65, retenido_previo:1500000, sac_prorrateado_acum:2083333.35, sac_real_acum:0 } });
  // se descuentan los 5 doceavos prorrateados (2.083.333,35 × 0,83) y se suma el SAC real neto (2.500.000 × 0,83)
  assert.equal(g.rem_gravada_mes, 345833.32);
});
```

- [ ] **Step 2: Correr y ver fallar.**
- [ ] **Step 3: Implementación**

```js
// ─── Sueldos 083: Ganancias 4ta categoría (RG 4003, acumulado) ───────
const GAN_TOPES_F572={cuota_medica:{pct_gn:5},alquiler:{pct_gni:40},servicio_domestico:{pct_gni:100},donaciones:{pct_gn:5},gastos_educativos:{pct_gni:40},intereses_hipotecarios:{anual:20000},seguro_vida:{pct_gni:100},otros:{}};
function computeGanancias(ctx){
  const r2=x=>Math.round(x*100)/100;const num=v=>Number(v)||0;
  const e=ctx.empleado||{},t=ctx.tabla,prev=ctx.previsional||{},ac=ctx.acumulados||{};
  const mes=Number((ctx.periodo||'').slice(5,7))||1,tipo=ctx.tipo||'mensual';
  const tipoDe={};(ctx.catalogo||[]).forEach(c=>{tipoDe[c.codigo]=c.tipo;});
  const EXENTOS=['16','17'];const APORTES=['200','201','202','203','205','207','208','211'];
  const conc=ctx.conceptos||[];
  const sum=f=>r2(conc.filter(f).reduce((a,c)=>a+num(c.importe),0));
  const remRem=sum(c=>tipoDe[c.codigo]==='remunerativo'&&!EXENTOS.includes(c.codigo));
  const aportes=sum(c=>APORTES.includes(c.codigo));
  const aportesPct=(num(prev.aporte_jubilacion_pct)+num(prev.aporte_inssjp_pct)+num(prev.aporte_os_pct))/100;
  const neto=r2(remRem-aportes);   // gravado del mes (no rem no gravado: sólo lo remunerativo)
  let sacMes=0,sacProrr=num(ac.sac_prorrateado_acum),sacReal=num(ac.sac_real_acum);
  if(tipo==='sac'||tipo==='final'){const real=sum(c=>['20','28'].includes(c.codigo))||remRem;   // en 'sac' el bruto ES el SAC
    sacMes=r2(real*(1-aportesPct)-(tipo==='sac'?sacProrr*(1-aportesPct):0));sacReal+=real;if(tipo==='sac')sacProrr=0;}
  else{sacMes=r2(remRem/12*(1-aportesPct));sacProrr+=r2(remRem/12);}
  const remGravMes=r2((tipo==='sac'?0:neto)+sacMes);
  const remGravAcum=r2(num(ac.rem_gravada_acum)+remGravMes);
  const k=mes/12;
  const pers=r2((num(t.gni_anual)+num(t.deduccion_especial_anual)+(e.conyuge?num(t.conyuge_anual):0)+num(e.hijos)*num(t.hijo_anual)+num(e.hijos_incap)*num(t.hijo_incap_anual))*k);
  const gniAcum=r2(num(t.gni_anual)*k),gnAcum=Math.max(0,remGravAcum);
  let f572=0;const per=(ctx.periodo||'').slice(0,7);
  (e.ganancias_deducciones||[]).forEach(d=>{
    if(d.periodo_desde&&d.periodo_desde>per)return;const desde=Number((d.periodo_desde||per.slice(0,4)+'-01').slice(5,7))||1;
    const hastaM=d.periodo_hasta&&d.periodo_hasta<per?Number(d.periodo_hasta.slice(5,7)):mes;const meses=Math.max(0,hastaM-desde+1);
    let imp=r2(num(d.importe_mensual)*meses);const tope=GAN_TOPES_F572[d.tipo]||{};
    if(tope.pct_gni)imp=Math.min(imp,r2(gniAcum*tope.pct_gni/100));if(tope.pct_gn)imp=Math.min(imp,r2(gnAcum*tope.pct_gn/100));if(tope.anual)imp=Math.min(imp,r2(tope.anual*k));
    f572+=imp;});
  f572=r2(f572);
  const gnsi=Math.max(0,r2(remGravAcum-pers-f572));
  const tr=(t.tramos||[]).map(x=>({desde:r2(num(x.desde)*k),hasta:x.hasta==null?Infinity:r2(num(x.hasta)*k),fijo:r2(num(x.fijo)*k),pct:num(x.pct)}));
  const tramo=tr.find(x=>gnsi>=x.desde&&gnsi<x.hasta)||tr[tr.length-1]||{desde:0,fijo:0,pct:0};
  const impuesto=gnsi>0?r2(tramo.fijo+(gnsi-tramo.desde)*tramo.pct/100):0;
  let ret=r2(impuesto-num(ac.retenido_previo)),tope=false;
  const max=r2(num(ctx.remBruto)*num(prev.ganancias_tope_retencion_pct)/100);
  if(ret>max){ret=max;tope=true;}
  return {mes,rem_gravada_mes:remGravMes,rem_gravada_acum:remGravAcum,deducciones_personales_acum:pers,deducciones_f572_acum:f572,gnsi_acum:gnsi,
    impuesto_acum:impuesto,retenido_previo:r2(num(ac.retenido_previo)),retencion_mes:ret,tope_aplicado:tope,tabla_vigencia:t.vigencia_desde,
    sac_prorrateado_acum:r2(sacProrr),sac_real_acum:r2(sacReal),
    formula:`GNSI ${gnsi} → tramo ${tramo.pct} %: ${tramo.fijo} + (${gnsi} − ${tramo.desde}) × ${tramo.pct} % = ${impuesto} − retenido ${r2(num(ac.retenido_previo))}`};
}
```
Devolución (retención negativa): en `computeRecibo` se carga como crédito con el concepto **901 "Devolución Ganancias"** (agregar en Task 1 §2c: `('901','Devolución Impuesto a las Ganancias','no_remunerativo',NULL,901,'550000','000000000000000','{"auto":true,"base":"ganancias","cantidad":"1","condicion":"ganancias_aplica","orden":901}')`).

Acumulados: el frontend (Task 11) arma `acumulados.ganancias` desde `v_sueldos_acumulados` del mismo año y empleado: `rem_gravada_acum` = Σ `liquidacion_items.ganancias.rem_gravada_mes` de los ítems confirmados (si un mes viejo no tiene `ganancias`, se toma `bruto − aportes − extras_exentas`), `retenido_previo` = Σ `ganancias_retenida` − Σ devoluciones (901), `sac_prorrateado_acum` / `sac_real_acum` del último `ganancias` guardado. **Julio:** si `tabla.vigencia_desde` cambió respecto del mes anterior, el frontend recalcula enero-junio con la tabla nueva (`computeGanancias` mes a mes con los conceptos guardados) y usa esa suma como `retenido_previo` teórico; la diferencia contra lo realmente retenido sale en julio (es lo que la norma pide). Alerta si `tabla_vigencia` de un mes anterior difiere.

- [ ] **Step 4: Correr** — 4 PASS. Suite completa verde (el test del recibo real de Task 4 no cambia: `ganancias_aplica=false`).
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): computeGanancias — RG 4003 acumulado con SAC prorrateado, deducciones F.572 con topes, devolución y tope 35 %"`

---

### Task 6: `computeSAC` y `computeLiquidacionFinal`

**Files:**
- Modify: `index.html` (bloque puras 083)
- Test: `tests/sueldos-final.test.js`

**Interfaces:**
- Produces: `computeSAC({empleado, periodo, acumulados:[{anio, mes, bruto, dias_trabajados, tipo}], catalogo}) → {codigo:'20'|'28', mejor_rem, dias_semestre, dias_trabajados, importe, formula}`; `computeLiquidacionFinal({empleado, fechaEgreso, causa, preavisoOtorgado, topeIndemnizatorio, acumulados, catalogo, convenio, escala, previsional, vacacionesGozadasAnio, reciboMes}) → {conceptos:[...], alertas, detalle:{anios_indemnizacion, mejor_rem_normal, dias_vac_prop, ...}}`. `reciboMes` es la salida de `computeRecibo` del último mes parcial (días trabajados hasta el egreso) y sus conceptos se incluyen tal cual.

- [ ] **Step 1: Test**

```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const CAT = [{codigo:'20',tipo:'remunerativo',nombre:'Aguinaldo'},{codigo:'28',tipo:'remunerativo',nombre:'SAC proporcional'},{codigo:'517',tipo:'no_remunerativo'},{codigo:'521',tipo:'no_remunerativo'},{codigo:'530',tipo:'no_remunerativo'},{codigo:'531',tipo:'no_remunerativo'},{codigo:'532',tipo:'no_remunerativo'},{codigo:'533',tipo:'no_remunerativo'}];
const ACUM = [1,2,3,4,5,6].map(m => ({ anio:2026, mes:m, tipo:'mensual', bruto: 1000000 + m*10000, dias_trabajados:30 }));

test('computeSAC: semestre completo = 50 % de la mejor remuneración', () => {
  const s = run(`computeSAC(${J({ empleado:{fecha_ingreso:'2020-01-01'}, periodo:'2026-06-01', acumulados:ACUM, catalogo:CAT })})`);
  assert.equal(s.codigo, '20'); assert.equal(s.mejor_rem, 1060000); assert.equal(s.importe, 530000);
});
test('computeSAC: ingreso 15/03 → proporcional a los días del semestre (108 de 181)', () => {
  const s = run(`computeSAC(${J({ empleado:{fecha_ingreso:'2026-03-15'}, periodo:'2026-06-01', acumulados:ACUM.slice(2), catalogo:CAT })})`);
  assert.equal(s.codigo, '28'); assert.equal(s.dias_trabajados, 108); assert.equal(s.dias_semestre, 181);
  assert.equal(s.importe, 316243.09);                                    // 1.060.000 × 0,5 × 108/181
});
test('computeSAC: las quincenas se suman por mes', () => {
  const ac = [{anio:2026,mes:1,tipo:'quincena1',bruto:400000,dias_trabajados:15},{anio:2026,mes:1,tipo:'quincena2',bruto:450000,dias_trabajados:15},{anio:2026,mes:2,tipo:'mensual',bruto:800000,dias_trabajados:30}];
  assert.equal(run(`computeSAC(${J({ empleado:{fecha_ingreso:'2020-01-01'}, periodo:'2026-06-01', acumulados:ac, catalogo:CAT })})`).mejor_rem, 850000);
});
test('computeLiquidacionFinal: despido sin causa a los 2a 4m, mensual 1.200.000, sin preaviso', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:false, topeIndemnizatorio:0,
    acumulados:[7,8].map(m=>({anio:2026,mes:m,tipo:'mensual',bruto:1200000,dias_trabajados:30})), catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[{codigo:'1',importe:800000,dc:'C'}],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  const imp = c => (r.conceptos.find(x => x.codigo === c) || {}).importe;
  assert.equal(r.detalle.anios_indemnizacion, 3);                        // 2a 4m: la fracción de 4 meses (> 3) cuenta como año
  assert.equal(imp('530'), 3600000);                                      // 1.200.000 × 3
  assert.equal(imp('531'), 1200000);                                      // preaviso 1 mes (antigüedad ≤ 5 años)
  assert.equal(imp('532'), 400000);                                       // integración: 10 días que faltan del mes
  assert.equal(imp('533'), 133333.33);                                    // (531 + 532) / 12
  assert.equal(imp('28'), 542857.14);                                     // SAC prop: 1.200.000 × 0,5 × 82/181 (01/07 → 20/09 = 82 días)
  // vacaciones no gozadas: 14 × 263/365 = 10,09 → 10 días × 48.000
  assert.equal(imp('517'), 480000); assert.equal(imp('521'), 40000);
  assert.equal(r.conceptos.some(c => c.codigo === '1'), true);
});
test('computeLiquidacionFinal: renuncia → sólo proporcionales', () => {
  const r = run(`computeLiquidacionFinal(${J({ empleado:{fecha_ingreso:'2024-05-10',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1200000}, fechaEgreso:'2026-09-20', causa:'renuncia', preavisoOtorgado:true, topeIndemnizatorio:0,
    acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:48000,dias_trabajados:20}} })})`);
  assert.deepEqual(r.conceptos.map(c => c.codigo).sort(), ['28','517','521']);
});
test('computeLiquidacionFinal: tope indemnizatorio y mínimo de un mes', () => {
  const base = { empleado:{fecha_ingreso:'2026-07-01',modalidad:'mensual',convenio:'fuera',sueldo_pactado:1000000}, fechaEgreso:'2026-09-20', causa:'despido_sin_causa', preavisoOtorgado:true, acumulados:[], catalogo:CAT, vacacionesGozadasAnio:0, reciboMes:{conceptos:[],bases:{valor_dia_vacaciones:40000,dias_trabajados:20}} };
  assert.equal(run(`computeLiquidacionFinal(${J({ ...base, topeIndemnizatorio:0 })})`).conceptos.find(c=>c.codigo==='530').importe, 1000000);   // mínimo 1 mes
  assert.equal(run(`computeLiquidacionFinal(${J({ ...base, topeIndemnizatorio:700000 })})`).conceptos.find(c=>c.codigo==='530').importe, 700000);
});
```

- [ ] **Step 2: Correr y ver fallar.**
- [ ] **Step 3: Implementación**

```js
// ─── Sueldos 083: SAC y liquidación final ─────────────────────────────
function _semestreDe(periodo){const y=Number(periodo.slice(0,4)),m=Number(periodo.slice(5,7));
  return m<=6?{ini:`${y}-01-01`,fin:`${y}-06-30`,meses:[1,2,3,4,5,6]}:{ini:`${y}-07-01`,fin:`${y}-12-31`,meses:[7,8,9,10,11,12]};}
const _dias=(a,b)=>Math.round((Date.parse(b)-Date.parse(a))/86400000)+1;
function computeSAC(ctx){
  const r2=x=>Math.round(x*100)/100;const e=ctx.empleado||{};const s=_semestreDe(ctx.periodo);const y=Number(ctx.periodo.slice(0,4));
  const porMes={};(ctx.acumulados||[]).filter(a=>a.anio===y&&s.meses.includes(a.mes)&&!['sac','final'].includes(a.tipo)).forEach(a=>{porMes[a.mes]=(porMes[a.mes]||0)+(Number(a.bruto)||0);});
  const mejor=r2(Math.max(0,...Object.values(porMes)));
  const diasSem=_dias(s.ini,s.fin);
  const desde=e.fecha_ingreso&&e.fecha_ingreso>s.ini?e.fecha_ingreso:s.ini;const hasta=e.fecha_egreso&&e.fecha_egreso<s.fin?e.fecha_egreso:s.fin;
  const diasTrab=Math.max(0,Math.min(diasSem,_dias(desde,hasta)));
  const completo=diasTrab>=diasSem;const importe=r2(mejor*0.5*(completo?1:diasTrab/diasSem));
  return {codigo:completo?'20':'28',mejor_rem:mejor,dias_semestre:diasSem,dias_trabajados:diasTrab,importe,
    formula:`${mejor} × 50 %${completo?'':` × ${diasTrab}/${diasSem}`}`};
}
function computeLiquidacionFinal(ctx){
  const r2=x=>Math.round(x*100)/100;const num=v=>Number(v)||0;const e=ctx.empleado||{},fe=ctx.fechaEgreso,cat=ctx.catalogo||[];
  const porCod={};cat.forEach(c=>{porCod[c.codigo]=c;});const out=[],alertas=[];
  const push=(cod,imp,cant,formula)=>{const c=porCod[cod];if(!c||!(imp>0))return;out.push({codigo:cod,cantidad:r2(cant||1),unidades:c.unidades||'',importe:r2(imp),dc:'C',origen:'auto',base:r2(imp),traza:{formula},periodo_ajuste:''});};
  // 1. Conceptos del mes parcial (ya calculados por computeRecibo)
  ((ctx.reciboMes||{}).conceptos||[]).forEach(c=>out.push(c));
  const remMensual=num(e.modalidad==='jornal'?num(ctx.escala?.valor_hora)*num(ctx.convenio?.horas_mes||200):(e.convenio==='fuera'?e.sueldo_pactado:ctx.escala?.basico_mensual));
  const mejorNormal=r2(Math.max(remMensual,...(ctx.acumulados||[]).filter(a=>!['sac','final'].includes(a.tipo)).map(a=>num(a.bruto))));
  // 2. SAC proporcional
  const sac=computeSAC({empleado:{...e,fecha_egreso:fe},periodo:fe.slice(0,7)+'-01',acumulados:ctx.acumulados,catalogo:cat});
  push('28',sac.importe,1,sac.formula);
  // 3. Vacaciones no gozadas + SAC s/ vac
  const ant=antiguadadSafe(e.fecha_ingreso_reconocida||e.fecha_ingreso,fe);
  const diasAnio=_dias(`${fe.slice(0,4)}-01-01`,fe);const diasVac=diasVacacionesLCT(ant.anios,diasAnio);
  const vacProp=Math.max(0,Math.round(diasVac*diasAnio/365)-num(ctx.vacacionesGozadasAnio));
  const vDia=num(ctx.reciboMes?.bases?.valor_dia_vacaciones)||r2(remMensual/25);
  push('517',vacProp*vDia,vacProp,`${vacProp} d × ${vDia}`);push('521',vacProp*vDia/12,1,'517 / 12');
  // 4. Indemnizaciones (despido sin causa / mutuo acuerdo)
  const indemniza=['despido_sin_causa','mutuo_acuerdo'].includes(ctx.causa);
  let aniosInd=ant.anios+(ant.meses>3||(ant.meses===3&&ant.dias>0)?1:0);
  if(indemniza){
    let base=mejorNormal;if(num(ctx.topeIndemnizatorio)>0&&base>num(ctx.topeIndemnizatorio)){base=num(ctx.topeIndemnizatorio);alertas.push('Indemnización con tope del CCT (3 × promedio)');}
    if(!num(ctx.topeIndemnizatorio))alertas.push('Sin tope indemnizatorio cargado: se usa la mejor remuneración sin tope');
    push('530',Math.max(base*aniosInd,mejorNormal),aniosInd,`${base} × ${aniosInd} años (mín. 1 mes)`);
    if(!ctx.preavisoOtorgado){const meses=ant.anios>=5?2:(ant.anios===0&&ant.meses<3?0.5:1);push('531',remMensual*meses,meses,`${remMensual} × ${meses} mes`);
      const ultimo=Number(finPeriodo(fe.slice(0,7)+'-01','mensual').slice(8,10)),diaEg=Number(fe.slice(8,10));
      const faltan=ultimo-diaEg;if(faltan>0)push('532',remMensual/30*faltan,faltan,`${remMensual}/30 × ${faltan} d`);
      const p=out.find(c=>c.codigo==='531')?.importe||0,i=out.find(c=>c.codigo==='532')?.importe||0;push('533',(p+i)/12,1,'(531 + 532) / 12');}
  }else if(ctx.causa==='despido_con_causa')alertas.push('Despido con causa: sólo rubros proporcionales; verificar con asesoramiento legal');
  return {conceptos:out,alertas,detalle:{anios_indemnizacion:aniosInd,mejor_rem_normal:mejorNormal,dias_vac_prop:vacProp,valor_dia_vac:vDia,antiguedad:ant.texto}};
}
function antiguadadSafe(d,h){return antiguedadEntre(d,h);}
```
(`antiguadadSafe` es sólo un alias defensivo; podés llamar `antiguedadEntre` directo.) Los `531`/`532`/`533` sólo se generan cuando NO hubo preaviso; en el test de despido `preavisoOtorgado:false`.

- [ ] **Step 4: Correr** — 6 PASS. Ajustar expectativas del test si el redondeo del SAC proporcional difiere en ±0,01 (documentar).
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): computeSAC y computeLiquidacionFinal — SAC por semestre, vacaciones no gozadas, indemnización art. 245, preaviso e integración"`

---

### Task 7: Frontend — catálogo de conceptos ampliado, exportar TXT/Excel, importar padrón

**Files:**
- Modify: `index.html` — `TBL` (línea ~4113: agregar `conceptos_arca`), globales (`let conceptosArca=[]` junto a `conceptosSueldo`), `modal-conceptos` (HTML ~2028), `renderConceptosRows` / `saveConceptosSueldo` (~5958-5991), botones en `page-sueldos` (~808)
- Test: sin tests nuevos (usa las puras de Task 2); verificación manual en el navegador

**Interfaces:**
- Consumes: `MARCAS_DEFAULT`, `parseArcaPadron`, `diffConceptosArca`, `buildConceptosTxt`, `xlsxBuild`, `descargarBytes`, `descargarTexto`.
- Produces: `exportConceptosTxt(soloFaltantes)`, `exportConceptosXlsx()`, `importarPadronArca(file)`, `_padronArca` (último padrón importado, en memoria + `localStorage 'arca_padron'`).

- [ ] **Step 1: Registro de tabla y carga**

En `TBL` después de `conceptos_sueldo`:
```js
  conceptos_arca:{label:'Catálogo ARCA',q:'?order=codigo.asc',set:r=>{conceptosArca=r||[];}},
```
y `let conceptosArca=[];` junto a la declaración de `conceptosSueldo`. `loadAll` itera `TBL`, no hace falta más.

- [ ] **Step 2: Modal de conceptos** — reemplazar el grid de 6 columnas por uno de 9: Código · Nombre · Tipo · ARCA (select con `conceptosArca` filtrado por familia del tipo, `<option value="${esc(a.codigo)}">${a.codigo} · ${esc(a.descripcion)}</option>`) · Unidad · Marcas (botón "15 marcas" que abre un `<details>` inline con 15 checkboxes rotulados con `ARCA_MARCAS_NOMBRES`; al cambiar el tipo o el ARCA sin marcas tocadas se aplican `MARCAS_DEFAULT`) · Regla (select `base` con las bases del motor + inputs `pct`/`importe`/`cantidad`/`factor`/`condicion`/`aplica_convenio`/`aplica_modalidad` en un `<details>`; se guarda como `regla` jsonb) · Orden · Activo. Los `legacy` se muestran colapsados bajo un `<details>` "Históricos del padrón (N)" en gris, sin edición salvo Activo. Ancho del modal a 1100px.

`saveConceptosSueldo`: `data` suma `codigo_arca:r.codigo_arca||null, repeticion:r.repeticion!==false, marcas:r.marcas||MARCAS_DEFAULT(r.tipo,r.codigo_arca), regla:r.regla||null`; validar `marcas` con `/^[01]{15}$/` y que todo concepto activo no informativo tenga `codigo_arca`.

- [ ] **Step 3: Botones** en el footer del modal: "Exportar TXT (todos)", "Exportar TXT (faltan en ARCA)", "Excel ARCA", "Importar padrón…" (input file oculto `#padron-file` accept `.txt,.csv`).

```js
let _padronArca=(()=>{try{return JSON.parse(localStorage.getItem('arca_padron')||'null');}catch(e){return null;}})();
function exportConceptosTxt(soloFaltantes){
  const r=buildConceptosTxt(conceptosSueldo,{soloFaltantes,padron:_padronArca?.filas||[]});
  if(r.errores.length)return notify(r.errores.slice(0,5).join(' · '),'err');
  if(!r.lineas.length)return notify('No hay conceptos para exportar','err');
  descargarBytes(`LSD_conceptos_${hoyLocal()}${soloFaltantes?'_faltantes':''}.txt`,new TextEncoder().encode(r.txt),'text/plain;charset=us-ascii');
  notify(`${r.lineas.length} conceptos — subilo en ARCA → Libro de Sueldos Digital → Conceptos → Carga masiva`);
}
function exportConceptosXlsx(){
  const hdr=['Código de concepto ARCA','Código de concepto empleador','Descripción de concepto empleador','Marca de repetición',...ARCA_MARCAS_NOMBRES,'TXT'];
  const r=buildConceptosTxt(conceptosSueldo,{});
  const lista=conceptosSueldo.filter(c=>c.activo!==false&&!c.legacy&&c.tipo!=='informativo').sort((a,b)=>(a.orden||0)-(b.orden||0));
  const filas=[hdr.map(h=>({v:h,s:1}))].concat(lista.map((c,i)=>[c.codigo_arca||'',c.codigo,c.nombre,c.repeticion===false?0:1,...String(c.marcas||'').split('').map(Number),r.lineas[i]||'']));
  descargarBytes(`LSD-conceptos-${hoyLocal()}.xlsx`,xlsxBuild([{nombre:'Armado txt',filas,cols:[12,12,40,8,...Array(15).fill(6),60}]),'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}
async function importarPadronArca(input){
  const f=input.files&&input.files[0];if(!f)return;
  const texto=await f.text();const r=parseArcaPadron(texto);
  if(r.errores.length)return notify(r.errores[0],'err');
  _padronArca={fecha:hoyLocal(),filas:r.filas};try{localStorage.setItem('arca_padron',JSON.stringify(_padronArca));}catch(e){}
  const d=diffConceptosArca(r.filas,conceptosSueldo);
  // (a) en ARCA y no en el ERP → alta legacy inactiva con las marcas de ARCA
  for(const p of d.soloArca){
    const a=conceptosArca.find(x=>x.codigo===p.codigo_arca);
    await POST('conceptos_sueldo',{empresa_id:currentEmpresa.id,codigo:p.codigo,nombre:p.nombre.slice(0,60),tipo:a?.familia||'remunerativo',orden:900,activo:false,codigo_arca:p.codigo_arca,repeticion:p.repeticion,marcas:p.marcas,legacy:true,origen:'padron'});
  }
  await reload('conceptos_sueldo');input.value='';openConceptosSueldo();
  const msg=[`Padrón: ${r.filas.length} conceptos`,d.soloArca.length?`${d.soloArca.length} nuevos importados como históricos`:'',
    d.soloErp.length?`${d.soloErp.length} del ERP faltan en ARCA (${d.soloErp.map(c=>c.codigo).join(', ')}) — exportá "faltan en ARCA"`:'',
    d.marcasDistintas.length?`${d.marcasDistintas.length} con marcas distintas: ${d.marcasDistintas.map(x=>x.codigo).join(', ')}`:''].filter(Boolean).join(' · ');
  notify(msg,d.soloErp.length||d.marcasDistintas.length?'err':'ok');
}
```
`xlsxBuild(hojas)` devuelve bytes (`zipStore`), igual que en `libroIvaExcelHojas` (línea ~3665): se pasan directo a `descargarBytes`.

- [ ] **Step 4: Verificar en el navegador** — abrir Conceptos ARCA: 25 nuevos con regla, 24 del padrón activos con ARCA y marcas, históricos colapsados; exportar TXT "faltan en ARCA" → 26 líneas (25 nuevos + 901) de 195; importar el CSV del padrón → 0 nuevos, 26 faltan; Excel abre en Excel/Numbers.
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): catálogo de conceptos con código ARCA, marcas y regla; exportar TXT/Excel de conceptos; importar padrón ARCA"`

---

### Task 8: Frontend — página Escalas y parámetros (`sueldosparam`)

**Files:**
- Modify: `index.html` — HTML nueva `page-sueldosparam` (después de `page-sueldos`, ~línea 820), `PAGE_TO_GROUP` (4138), `GROUP_TABS` (4147: reemplazar `{k:'sueldos',l:'Sueldos'}` por `{k:'nomina',l:'Sueldos',sub:[{k:'sueldos',l:'Liquidaciones'},{k:'sueldosnov',l:'Novedades'},{k:'sueldosparam',l:'Escalas y parámetros'}]}`), `PAGE_TO_PARENT` (4161: `sueldos:'nomina',sueldosnov:'nomina',sueldosparam:'nomina'`), `groupMods` (13147: contabilidad += `'sueldosnov','sueldosparam'`), `PAGE_RENDERS` (7314: `sueldosparam:[renderSueldosParam]`), `TBL` (4 tablas nuevas), globales.

**Interfaces:**
- Produces: globales `sueldosEscala`, `sueldosConvenio`, `sueldosPrevisional`, `sueldosGanTablas`; `renderSueldosParam()`, `paramTab(t)`, `escalaNuevaVigencia()`, `saveEscala()`, `saveConvenio()`, `savePrevisional()`, `saveGanTabla()`.

- [ ] **Step 1: TBL + globales**
```js
  sueldos_escala:{label:'Escala salarial',q:'?order=vigencia_desde.desc,orden.asc',set:r=>{sueldosEscala=r||[];_dirtyPages.add('sueldosparam');}},
  sueldos_convenio_parametros:{label:'Parámetros del convenio',q:'?order=vigencia_desde.desc',set:r=>{sueldosConvenio=r||[];}},
  sueldos_parametros_previsionales:{label:'Parámetros previsionales',q:'?order=vigencia_desde.desc',set:r=>{sueldosPrevisional=r||[];}},
  sueldos_ganancias_tablas:{label:'Tablas de Ganancias',q:'?order=vigencia_desde.desc',set:r=>{sueldosGanTablas=r||[];}},
```
- [ ] **Step 2: HTML** — página con `.page-header` (título "Escalas y parámetros de sueldos", `<div class="tabs"></div>`) y cuatro paneles internos conmutados por botones (`paramTab('escala'|'convenio'|'previsional'|'ganancias')`, estado en `_paramTab`):
  - **Escala:** selector de vigencia (`<select id="esc-vig">` con las vigencias distintas) + botón "Nueva vigencia" (prompt fecha + % de aumento → copia todas las categorías de la vigencia seleccionada con `valor_hora`/`basico_mensual` × (1 + %/100), redondeo a 2) + tabla editable categoría · modalidad · valor hora · básico mensual (inputs con `data-esc-id`) + "Guardar" (PATCH por fila cambiada; POST para nuevas con `+ Categoría`).
  - **Convenio / Previsional / Ganancias:** lista de vigencias a la izquierda (click carga el formulario), formulario con todos los campos de la tabla (labels en castellano con la unidad), "Nueva vigencia" (copia la seleccionada con la fecha nueva), "Guardar" (PATCH/POST). Ganancias: tabla de 9 tramos editable (desde · hasta · fijo · %) serializada a `tramos`.
- [ ] **Step 3: Render** — `renderSueldosParam()` dibuja el panel activo desde las globales; sin filas muestra "Cargá la primera vigencia". Alertas arriba: categorías con valor 0 en la vigencia actual, previsional con `vigencia_desde` anterior a 3 meses, tabla de Ganancias de un semestre anterior al actual.
- [ ] **Step 4: Verificar** — cargar valor hora de Oficial en la vigencia 08/2026, crear vigencia 10/2026 con +4 %, ver que Ingresante ya tiene 4.665,41 (seed) y Oficial el copiado.
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): página Escalas y parámetros — escala UOM con vigencias, convenio, previsional y tablas de Ganancias"`

---

### Task 9: Frontend — legajo ampliado con pestañas + modal de baja

**Files:**
- Modify: `index.html` — `modal-empleado` (HTML ~1930-1965), `openEmpleado` / `saveEmpleado` (5520-5582), nuevo `modal-baja-empleado` (HTML junto a los modales de sueldos), `renderSueldos` (botón "Baja" por empleado activo, columna Acciones ~5514)

**Interfaces:**
- Consumes: `computeRecibo`, `computeLiquidacionFinal`, `computeSAC` (Task 4-6), `vigenteA`, `sueldosEscala/Convenio/Previsional/GanTablas`, `RPC('guardar_liquidacion')`.
- Produces: `empTab(t)`, `empAddAdicional()`, `empAddRecurrente()`, `empAddDeduccion()`, `openBajaEmpleado(id)`, `previewBaja()`, `saveBajaEmpleado()`, helper `_ctxRecibo(empleado, periodo, tipo, novedad)` (arma el contexto del motor desde las globales; **reutilizado en Task 11**).

- [ ] **Step 1: Pestañas del modal** — envolver el contenido actual en `<div data-emptab="datos">`; agregar `<div data-emptab="remuneracion">`, `conceptos`, `ganancias`, `arca` (mover ahí el `<details id="emp-arca-details">` abierto). Barra de pestañas con botones `onclick="empTab('datos')"` que muestran/ocultan por `data-emptab`. Campos nuevos (ids):
  - Datos: `emp-tarea`, `emp-contratacion`, `emp-lugar-pago` (default Casa Central), `emp-banco`.
  - Remuneración: `emp-convenio` (uom/fuera), `emp-categoria-escala` (select con `[...new Set(sueldosEscala.map(e=>e.categoria))]`, visible si uom), `emp-sueldo-pactado` (visible si fuera), `emp-horas-semanales` (48), `emp-afiliado` (checkbox), `emp-presentismo` (checkbox), `emp-antiguedad-pct` (solo fuera), `emp-ingreso-reconocida`.
  - Conceptos fijos: dos listas editables (`_empAdic`, `_empRec`) con filas concepto (select del catálogo activo por tipo) · % o importe · para recurrentes además desde/hasta/cuotas total/pagadas. Se serializan a `adicionales_fijos` y `conceptos_recurrentes`.
  - Ganancias: `emp-gan-aplica`, `emp-hijos-incap`, lista `_empDed` (tipo select de `GAN_TOPES_F572` · importe mensual · desde · hasta) → `ganancias_deducciones`.
  `openEmpleado` carga todo; `saveEmpleado` suma los campos al `data` (jsonb como arrays). Validar: uom sin categoría → error; fuera sin sueldo pactado → error.

- [ ] **Step 2: Helper de contexto del motor**
```js
function _ctxRecibo(e,periodo,tipo,novedad){
  const fin=finPeriodo(periodo,tipo);
  const escala=e.convenio==='fuera'?null:vigenteA(sueldosEscala.filter(x=>x.categoria===e.categoria_escala),fin);
  const anio=periodo.slice(0,4);
  const acum=(sueldosAcumulados||[]).filter(a=>a.empleado_id===e.id&&String(a.anio)===anio);
  return {empleado:e,periodo,tipo,novedad:novedad||null,escala,convenio:vigenteA(sueldosConvenio,fin)||{},previsional:vigenteA(sueldosPrevisional,fin)||{},
    ganTabla:vigenteA(sueldosGanTablas,fin),catalogo:conceptosSueldo,hoy:hoyLocal(),
    acumulados:{ganancias:_ganAcumulados(e.id,anio,periodo),sac:acum}};
}
function _ganAcumulados(eid,anio,periodo){
  const items=liquidaciones.filter(l=>l.estado==='confirmada'&&(l.periodo||'').slice(0,4)===anio&&l.periodo<periodo).flatMap(l=>(l.liquidacion_items||[]).filter(i=>i.empleado_id===eid).map(i=>({l,i})));
  if(!items.length)return null;
  const g=items.map(x=>x.i.ganancias).filter(Boolean);const last=g[g.length-1]||{};
  const rem=items.reduce((a,x)=>a+(x.i.ganancias?Number(x.i.ganancias.rem_gravada_mes)||0:(Number(x.i.bruto)||0)-(Number(x.i.aportes)||0)),0);
  const ret=items.reduce((a,x)=>a+(x.i.liquidacion_conceptos||[]).reduce((b,c)=>b+(c.codigo==='900'?Number(c.importe):c.codigo==='901'?-Number(c.importe):0),0),0);
  return {rem_gravada_acum:Math.round(rem*100)/100,retenido_previo:Math.round(ret*100)/100,sac_prorrateado_acum:Number(last.sac_prorrateado_acum)||0,sac_real_acum:Number(last.sac_real_acum)||0};
}
```
`sueldosAcumulados` = global cargada de `v_sueldos_acumulados` (TBL: `v_sueldos_acumulados:{label:'Acumulados de sueldos',q:'?order=anio.desc,mes.desc',set:r=>{sueldosAcumulados=r||[];}}`).

- [ ] **Step 3: Modal de baja** — `modal-baja-empleado`: fecha de egreso (`baja-fecha`), causa (`baja-causa` select: renuncia / despido_sin_causa / despido_con_causa / mutuo_acuerdo / fin_contrato / fallecimiento), preaviso otorgado (`baja-preaviso` checkbox), tope indemnizatorio (`baja-tope`, prellenado con `configContable.tope_indemnizatorio` si existe, si no vacío), vacaciones gozadas en el año (`baja-vac-gozadas`, prellenado con Σ `vacaciones_dias` de `sueldosNovedades` del año), preview (`#baja-preview` tabla concepto · importe) y "Generar liquidación final".
```js
function previewBaja(){
  const e=empleados.find(x=>x.id===_bajaEmpId);const fe=g('baja-fecha');if(!e||!fe)return;
  const periodo=fe.slice(0,7)+'-01';const nov=sueldosNovedades.find(n=>n.empleado_id===e.id&&n.periodo===periodo&&n.tipo==='mensual')||null;
  const ctx=_ctxRecibo({...e,fecha_egreso:fe},periodo,'mensual',nov);const mes=computeRecibo(ctx);
  const fin=computeLiquidacionFinal({empleado:e,fechaEgreso:fe,causa:g('baja-causa'),preavisoOtorgado:document.getElementById('baja-preaviso').checked,
    topeIndemnizatorio:parseFloat(g('baja-tope'))||0,acumulados:ctx.acumulados.sac,catalogo:conceptosSueldo,convenio:ctx.convenio,escala:ctx.escala,previsional:ctx.previsional,
    vacacionesGozadasAnio:parseFloat(g('baja-vac-gozadas'))||0,reciboMes:mes});
  _bajaResultado={mes,fin};
  document.getElementById('baja-preview').innerHTML=fin.conceptos.map(c=>`<tr><td class="mono">${esc(c.codigo)}</td><td>${esc(_conceptoCat(c.codigo)?.nombre||'')}</td><td class="mono" style="text-align:right">${c.dc==='D'?'−':''}${fmtARS(c.importe)}</td></tr>`).join('')
    +`<tr><td colspan="3" style="color:var(--text3);font-size:11px">${[...mes.alertas,...fin.alertas].map(esc).join(' · ')}</td></tr>`;
}
async function saveBajaEmpleado(){
  if(!_bajaResultado)previewBaja();const {mes,fin}=_bajaResultado;const e=empleados.find(x=>x.id===_bajaEmpId);const fe=g('baja-fecha');
  const t=computeItemDesdeConceptos(fin.conceptos,conceptosSueldo);
  const item={empleado_id:e.id,...t,contribuciones:mes.contribuciones_total,art:mes.art,conceptos:fin.conceptos,f931:{...mes.f931,dias:mes.bases.dias_trabajados},ganancias:mes.ganancias,contribuciones_detalle:mes.contribuciones};
  setBusy('btn-save-baja',true);
  try{
    await RPC('guardar_liquidacion',{p_liq:{periodo:fe.slice(0,7)+'-01',tipo:'final',fecha_pago:fe,observaciones:`Liquidación final — ${g('baja-causa')} — egreso ${fmtFecha(fe)}`},p_items:[item]});
    await PATCH('empleados',{fecha_egreso:fe,causa_egreso:g('baja-causa')},`?id=eq.${e.id}`);
    await reload('liquidaciones','empleados');closeModal('modal-baja-empleado',true);renderAll();
    notify('Liquidación final en borrador — revisala y confirmala; al confirmar el legajo queda dado de baja');
  }catch(err){notify(msgError(err),'err');}finally{setBusy('btn-save-baja',false,'Generar liquidación final');}
}
```
`guardar_liquidacion` necesita `causa_egreso` en `p_liq`: agregar en Task 1 la línea `causa_egreso = p_liq->>'causa_egreso'` en el INSERT/UPDATE de `liquidaciones` (columna creada en §4).

- [ ] **Step 4: Verificar** — editar un legajo: pestañas, guardar convenio uom + categoría; abrir Baja de un empleado de prueba → preview con 28/517/521 (+530-533 si despido) → generar → aparece la liquidación `final` en borrador.
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): legajo con pestañas (remuneración, conceptos fijos, Ganancias, ARCA) y modal de baja con liquidación final"`

---

### Task 10: Frontend — página Novedades (`sueldosnov`) + precarga desde timers

**Files:**
- Modify: `index.html` — HTML nueva `page-sueldosnov` (después de `page-sueldos`), `TBL` (`sueldos_novedades`), `PAGE_RENDERS` (`sueldosnov:[renderSueldosNovedades]`), registro de navegación (ya hecho en Task 8)

**Interfaces:**
- Consumes: `RPC('guardar_novedades')`, `computeParteHoras` + `_fetchEntriesPeriodo` (066), `empleados`, `sueldosNovedades`.
- Produces: global `sueldosNovedades`; `renderSueldosNovedades()`, `novSetPeriodo()`, `saveNovedades()`, `novPrecargarHoras()`, `_novRows()`.

- [ ] **Step 1: TBL** — `sueldos_novedades:{label:'Novedades de sueldos',q:'?order=periodo.desc',set:r=>{sueldosNovedades=r||[];_dirtyPages.add('sueldosnov');}},` + `let sueldosNovedades=[];`.
- [ ] **Step 2: HTML** — header con `<div class="tabs"></div>`; toolbar: `<input type="month" id="nov-periodo">` (default mes actual), `<select id="nov-tipo">` (mensual / 1ª quincena / 2ª quincena), botón "⏱ Precargar horas de planta" (`novPrecargarHoras()`), botón "Guardar" (`saveNovedades()`, id `btn-save-nov`). Tabla `#nov-tbody` con columnas: Empleado · Días trab. · Horas norm. · Extras 50 · Extras 100 · Feriados no trab. · Feriado trab. (hs) · Aus. injust. · Enfermedad (d) · Accidente (d) · Lic. paga (d) · Tipo lic. · Sin goce (d) · Vacaciones (d) · Adelanto $ · Premio $ · Obs. Inputs `data-nov-emp="${e.id}" data-nov-campo="..."`. Fila por empleado activo; valores desde `sueldosNovedades` del período/tipo o vacíos. Para mensualizados, "Horas norm." deshabilitado; para jornales, "Días trab." deshabilitado (el motor deriva uno del otro).
- [ ] **Step 3: Funciones**
```js
function _novRows(){const por={};document.querySelectorAll('[data-nov-emp]').forEach(inp=>{const k=inp.dataset.novCampo;const v=inp.type==='number'?(inp.value===''?null:parseFloat(inp.value)):inp.value;(por[inp.dataset.novEmp]=por[inp.dataset.novEmp]||{empleado_id:inp.dataset.novEmp})[k]=v;});return Object.values(por);}
async function saveNovedades(){
  const periodo=g('nov-periodo');if(!periodo)return notify('Indicá el período','err');
  setBusy('btn-save-nov',true);
  try{await RPC('guardar_novedades',{p_periodo:periodo+'-01',p_tipo:g('nov-tipo'),p_items:_novRows()});await reload('sueldos_novedades');renderSueldosNovedades();notify('Novedades guardadas');}
  catch(e){notify(msgError(e),'err');}finally{setBusy('btn-save-nov',false,'Guardar');}
}
async function novPrecargarHoras(){
  const periodo=g('nov-periodo');const entries=await _fetchEntriesPeriodo(periodo);
  const ph=computeParteHoras(entries,ordenesProduccion,periodo);let n=0;
  empleados.filter(e=>e.activo!==false&&e.modalidad==='jornal'&&e.operario_nombre).forEach(e=>{
    const hs=ph.porOperario[e.operario_nombre.toLowerCase()];const inp=document.querySelector(`[data-nov-emp="${e.id}"][data-nov-campo="horas_normales"]`);
    if(hs&&inp&&inp.value==='')  {inp.value=g('nov-tipo')==='mensual'?hs:Math.round(hs/2*100)/100;n++;}});
  notify(n?`${n} jornales precargados desde los timers — revisá y guardá`:'No hay horas de planta para ese período');
}
```
(`ordenesProduccion` es la global que usa `liqTraerHoras`; copiar el nombre exacto de ahí. Para quincenas, la mitad de las horas del mes es una aproximación: la spec lo deja a corrección manual.)
- [ ] **Step 4: Verificar** — cargar septiembre 1ª quincena para un jornal (90 h, 1 feriado), guardar, recargar la página, ver que persiste.
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): página Novedades por período con precarga desde timers de planta"`

---

### Task 11: Frontend — liquidación con "Calcular", detalle con origen/traza, payload 083, LSD desde marcas

**Files:**
- Modify: `index.html` — `modal-liquidacion` (HTML 1967-1985: botón "⚙ Calcular" junto a "Traer horas de planta", columna "Alertas"), `openLiquidacion` (5599-5633), `_liqItems` (5654-5667), `liqOpenDetalle` / `renderLiqdConceptos` / `liqdAplicar` (5888-5952), `armarLSDInput` (6005-6024), `descargarLSD` (6036)

**Interfaces:**
- Consumes: `computeRecibo`, `computeSAC`, `_ctxRecibo`, `_ganAcumulados`, `sueldosNovedades`, `buildLSD`.
- Produces: `liqCalcular()`, `liqCalcularEmpleado(eid)`, `liqRecalcularEmpleado(eid)`; `_liqDetalle[eid]` pasa a `{conceptos, f931, ganancias, contribuciones_detalle, alertas}`; `_liqItems()` emite el payload 083.

- [ ] **Step 1: Calcular**
```js
function liqCalcularEmpleado(eid,forzar){
  const e=empleados.find(x=>x.id===eid);if(!e)return null;
  const periodo=g('liq-periodo')+'-01',tipo=g('liq-tipo');
  const prev=_liqDetalle[eid];
  const manuales=forzar?[]:(prev?.conceptos||[]).filter(c=>c.origen==='manual');
  let r;
  if(tipo==='sac'){
    const ctx=_ctxRecibo(e,periodo,'sac',null);const s=computeSAC({empleado:e,periodo,acumulados:ctx.acumulados.sac,catalogo:conceptosSueldo});
    // el SAC se liquida como un "mes" cuyo único haber es el SAC → aportes/contribuciones/Ganancias con el motor
    const cat=conceptosSueldo.map(c=>c.codigo===s.codigo?{...c,regla:{auto:true,base:'fijo',importe:s.importe,cantidad:'1',orden:15}}:(c.regla?.base&&['basico','valor_hora','valor_hora_extra','valor_dia','valor_dia_vacaciones','no_rem_paritaria','complemento_imgr','basico_mas_antiguedad'].includes(c.regla.base)?{...c,regla:{...c.regla,auto:false}}:c));
    r=computeRecibo({...ctx,catalogo:cat,novedad:{}});r.alertas.push(`SAC: ${s.formula}`);
  }else{
    const nov=sueldosNovedades.find(n=>n.empleado_id===eid&&n.periodo===periodo&&n.tipo===tipo)||null;
    r=computeRecibo(_ctxRecibo(e,periodo,tipo,nov));
  }
  const conceptos=r.conceptos.concat(manuales);const t=computeItemDesdeConceptos(conceptos,conceptosSueldo);
  _liqDetalle[eid]={conceptos,f931:r.f931,ganancias:r.ganancias,contribuciones_detalle:r.contribuciones,alertas:r.alertas};
  _liqSet(eid,'bruto',t.bruto);_liqSet(eid,'no_remunerativo',t.no_remunerativo);_liqSet(eid,'aportes',t.aportes);_liqSet(eid,'neto',t.neto);
  _liqSet(eid,'contribuciones',r.contribuciones_total);_liqSet(eid,'art',r.art);
  const al=document.getElementById(`liq-alertas-${eid}`);if(al){al.textContent=r.alertas.length?'⚠ '+r.alertas.length:'';al.title=r.alertas.join('\n');}
  return r;
}
function liqCalcular(){
  if(!sueldosConvenio.length||!sueldosPrevisional.length)return notify('Cargá primero Escalas y parámetros (convenio y previsional)','err');
  let n=0,al=0;document.querySelectorAll('[data-liq-campo="bruto"]').forEach(inp=>{const r=liqCalcularEmpleado(inp.dataset.liqEmp,false);if(r){n++;al+=r.alertas.length;}});
  Object.keys(_liqDetalle).forEach(eid=>liqAplicarDetalle(eid));liqResumen();_modalDirty['modal-liquidacion']=true;
  notify(`${n} recibos calculados${al?` · ${al} alertas (ícono ⚠ en la fila)`:''}`);
}
function liqRecalcularEmpleado(eid){liqCalcularEmpleado(eid,true);liqAplicarDetalle(eid);liqResumen();liqOpenDetalle(eid);}
```
Los inputs bruto/no rem/aportes/neto quedan `readonly` cuando `_liqDetalle[eid].conceptos.length` (ya lo hace `liqAplicarDetalle`). Agregar `<span id="liq-alertas-${eid}">` en cada fila (grid pasa a 9 columnas).

- [ ] **Step 2: Detalle con origen y traza** — en `renderLiqdConceptos` agregar columna Origen (badge "auto" / "manual") y un ícono `ⓘ` con `title="${esc(r.traza?.formula||'')}"`; al editar cualquier campo de una fila auto, la fila pasa a `origen:'manual'` (`liqdOnRow`: `r.origen='manual'`). Botón "↺ Recalcular" en el header del modal (`liqRecalcularEmpleado(_liqdEmp)`). Bloque "Contribuciones patronales" de solo lectura (tabla de `contribuciones_detalle`) y bloque "Ganancias" con `gnsi_acum`, `impuesto_acum`, `retenido_previo`, `retencion_mes` si aplica. `liqdAplicar` conserva `origen`, `traza`, `base`, `ganancias`, `contribuciones_detalle` y `alertas` en `_liqDetalle[eid]`; `liqdConceptosDefault` sigue para empleados sin cálculo.

- [ ] **Step 3: Payload 083 en `_liqItems`**
```js
    if((d.conceptos||[]).length)porEmp[eid].conceptos=d.conceptos.map(c=>({codigo:c.codigo,cantidad:c.cantidad||0,unidades:c.unidades||null,importe:c.importe||0,periodo_ajuste:c.periodo_ajuste||null,origen:c.origen||'manual',traza:c.traza||null,base:c.base??null}));
    if(d.f931)porEmp[eid].f931=d.f931;if(d.ganancias)porEmp[eid].ganancias=d.ganancias;if(d.contribuciones_detalle)porEmp[eid].contribuciones_detalle=d.contribuciones_detalle;
```
`openLiquidacion` rehidrata `_liqDetalle` con `origen/traza/base` desde `liquidacion_conceptos` y `ganancias`/`contribuciones_detalle` desde el ítem.

- [ ] **Step 4: LSD desde marcas** — en `armarLSDInput`, si el ítem tiene `f931` completo (viene del motor) usarlo tal cual; el `computeF931Default` queda como fallback cuando `f931` es null. Antes de armar, validar códigos:
```js
  const sinArca=(l.liquidacion_items||[]).flatMap(i=>(i.liquidacion_conceptos||[])).map(c=>_conceptoCat(c.codigo)).filter(c=>c&&c.tipo!=='informativo'&&(!c.codigo_arca||c.legacy)).map(c=>c.codigo);
  if(sinArca.length){notify(`Conceptos sin código ARCA o históricos: ${[...new Set(sinArca)].join(', ')} — corregí el catálogo`,'err');return null;}
```
`descargarLSD`: quitar el PATCH de `lsd_importe_detraer`/`lsd_tope_aportes` (ahora viven en previsional); los inputs `lsd-detraer`/`lsd-tope` se prellenan desde `vigenteA(sueldosPrevisional, fin)`.

- [ ] **Step 5: Verificar** — nueva liquidación 1ª quincena 09/2026 → Calcular → la fila del ingresante muestra bruto 444.111,03 / neto 395.310; detalle con 10 renglones auto, traza en cada uno; editar un renglón → manual; Recalcular → vuelve; guardar borrador → recargar → conceptos con origen; LSD → sin errores, base 4 = 484.111,03.
- [ ] **Step 6: Commit** — `git commit -m "feat(sueldos): liquidación calculada por el motor — Calcular/Recalcular, conceptos con origen y traza, contribuciones y Ganancias por empleado, LSD con bases desde marcas"`

---

### Task 12: `renderRecibo` (pura) + impresión individual y por lote

**Files:**
- Modify: `index.html` — bloque puras 083 (`renderRecibo`, `_reciboComposicion`), UI (`imprimirRecibo(liqId, eid)`, `imprimirRecibosLiquidacion(liqId)`), botones: en `renderSueldos` acción "🖨 Recibos" por liquidación confirmada, y "Imprimir recibo" en `modal-liq-detalle`
- Test: `tests/sueldos-recibo.test.js`

**Interfaces:**
- Consumes: `numeroALetras`, `antiguedadEntre`, `fmtFecha`, `esc`.
- Produces:
```js
renderRecibo({empresa:{razon_social, domicilio, localidad, actividad, cuit}, empleado, item, liquidacion, conceptosCat, config:{f931_ultimo_periodo, f931_ultimo_fecha, f931_banco}, escala, copias:['ORIGINAL','DUPLICADO']}) → string HTML
_reciboComposicion(item, conceptosCat) → {sindical:{emp, trab}, ss:{emp, trab}, os:{emp, trab}, inssjp:{emp, trab}, art:{emp}, scvo:{emp}, otros:{emp, trab}, otrosDesc:{trab}, costoTotal, pct:{neto, otrosDesc, ss, os, inssjp, scvo, art}}
```

- [ ] **Step 1: Test**
```js
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const erp = require('./_harness').load();
const run = c => erp.run(c); const J = JSON.stringify;
const CAT = [{codigo:'4',nombre:'JORNAL',tipo:'remunerativo'},{codigo:'5',nombre:'FERIADO',tipo:'remunerativo'},{codigo:'200',nombre:'JUBILACION',tipo:'descuento'},{codigo:'201',nombre:'LEY 19032',tipo:'descuento'},{codigo:'202',nombre:'OBRA SOCIAL',tipo:'descuento'},{codigo:'203',nombre:'SINDICATO UOM',tipo:'descuento'},{codigo:'211',nombre:'Sindicato S/No Rem',tipo:'descuento'},{codigo:'208',nombre:'Obra Social S/ No Rem',tipo:'descuento'},{codigo:'102',nombre:'Gratif extraord No Rem',tipo:'no_remunerativo'},{codigo:'998',nombre:'Redondeo',tipo:'no_remunerativo'}];
const ITEM = { recibo_nro:1603, bruto:444111.03, no_remunerativo:40000.62, aportes:88801.65, neto:395310, contribuciones:108780.94, art:0,
  liquidacion_conceptos:[{codigo:'4',cantidad:90,unidades:'H',importe:403737.30,dc:'C',orden:0},{codigo:'5',cantidad:9,unidades:'H',importe:40373.73,dc:'C',orden:1},{codigo:'200',cantidad:11,unidades:'%',importe:48852.21,dc:'D',orden:2},{codigo:'201',cantidad:3,unidades:'%',importe:13323.33,dc:'D',orden:3},{codigo:'202',cantidad:3,unidades:'%',importe:13323.33,dc:'D',orden:4},{codigo:'203',cantidad:2.5,unidades:'%',importe:11102.78,dc:'D',orden:5},{codigo:'211',cantidad:0,unidades:'',importe:1000,dc:'D',orden:6},{codigo:'208',cantidad:0,unidades:'',importe:1200,dc:'D',orden:7},{codigo:'102',cantidad:0,unidades:'',importe:40000,dc:'C',orden:8},{codigo:'998',cantidad:0,unidades:'',importe:0.62,dc:'C',orden:9}],
  contribuciones_detalle:[{codigo:'640',nombre:'SVC',pct:null,base:424.62,importe:424.62},{codigo:'642',nombre:'CONTRIBUCION INSSJP',pct:1.59,base:440609.19,importe:7005.69},{codigo:'643',nombre:'CONTRIBUCION ANSSAL',pct:0.9,base:484111.03,importe:4357},{codigo:'644',nombre:'CONTRIBUCION JUBILACION',pct:10.77,base:440609.19,importe:47453.61},{codigo:'645',nombre:'CONTRIBUCION OBRA SOCIAL',pct:5.1,base:484111.03,importe:24689.66},{codigo:'646',nombre:'CONTRIBUCION FONDO DESEMPLEO',pct:0.94,base:440609.19,importe:4141.73},{codigo:'647',nombre:'CONTRIBUCION SUBSIDIO FAMILIAR',pct:4.7,base:440609.19,importe:20708.63}] };
const ARGS = { empresa:{razon_social:'VITALMET SOCIEDAD ANONIMA',domicilio:'PERU 246',localidad:'VILLA MARTELLI',actividad:'Forjado, prensado, estampado y laminado de metales; pulvimetalurgia',cuit:'34-59751980-1'},
  empleado:{legajo:'69',nombre:'AYALA , RODRIGO EZEQUIEL',cuil:'20334592775',fecha_ingreso:'2026-04-27',fecha_ingreso_reconocida:'2026-09-01',categoria_escala:'INGRESANTE',contratacion:'Nuevo período de prueba',obra_social:'UNION OBRERA METALURGICA',tarea:'INGRESANTE',lugar_pago:'CASA CENTRAL',banco_deposito:'FRANCES'},
  item:ITEM, liquidacion:{periodo:'2026-09-01',tipo:'quincena1',fecha_pago:'2026-09-18'}, conceptosCat:CAT, config:{f931_ultimo_periodo:'08/2026',f931_ultimo_fecha:'2026-09-09'}, escala:{valor_hora:4485.97}, copias:['ORIGINAL','DUPLICADO'] };

test('_reciboComposicion: totales de la página 2 del recibo real', () => {
  const c = run(`_reciboComposicion(${J(ITEM)},${J(CAT)})`);
  assert.equal(c.ss.emp, 76660.97);          // SIPA 47.453,61 + FNE 4.141,73 + AAFF 20.708,63 + ANSSAL 4.357,00 (como la página 2 del recibo real)
  assert.equal(c.os.emp, 24689.66); assert.equal(c.inssjp.emp, 7005.69); assert.equal(c.scvo.emp, 424.62);
  assert.equal(c.otrosDesc.trab, 88801.65); assert.equal(c.costoTotal, 592892.59);
  assert.equal(Math.round(Object.values(c.pct).reduce((a, b) => a + b, 0)), 100);
});
test('renderRecibo: 2 páginas × 2 copias, bloques y neto en letras', () => {
  const html = run(`renderRecibo(${J(ARGS)})`);
  assert.equal((html.match(/class="recibo-pagina"/g) || []).length, 4);
  for (const s of ['Recibo de haberes','VITALMET SOCIEDAD ANONIMA','34-59751980-1','1RA QUINC SEPTIEMBRE 2026','18/09/2026','20-33459277-5','0a 4m 20d','COSTO TOTAL EMPLEADOR','592.892,59','SUELDO BRUTO','484.111,65','SUELDO NETO','395.310,00','TRESCIENTOS NOVENTA Y CINCO MIL TRESCIENTOS DIEZ','Detalle de la composici','Página 1 de 2','Página 2 de 2','ORIGINAL','DUPLICADO','1603'])
    assert.ok(html.includes(s), 'falta: ' + s);
  assert.ok(html.includes('-48.852,21'));
  assert.ok(html.includes('<svg'));
});
```
**Nota:** en el recibo real "Total Seguridad Social" del empleador incluye ANSSAL (643); Obra Social es sólo el 645.

- [ ] **Step 2: Implementación** — `_reciboComposicion`: empleador desde `contribuciones_detalle` (ss = 644+646+647+643, os = 645, inssjp = 642, scvo = 640, art = 648 o `item.art`); trabajador: sindical = 203+205+211+206, ss = 200, os = 202+207+208, inssjp = 201, otrosDesc = Σ descuentos (= `item.aportes`); `costoTotal = bruto + no_rem + Σ contribuciones + art`; `pct` de cada rubro sobre `costoTotal` con 2 decimales (neto, otrosDesc, ss.emp, os.emp, inssjp.emp, scvo.emp, art.emp).

`renderRecibo`: devuelve `<style>` de impresión (A4, `@page{size:A4;margin:12mm}`, `.recibo-pagina{page-break-after:always;font:11px Arial}`, tablas con bordes finos, encabezados en negrita como la foto) + por cada copia dos `<div class="recibo-pagina">`. Página 1 con los bloques de la spec (usar `fmt2 = n => n.toLocaleString('es-AR',{minimumFractionDigits:2,maximumFractionDigits:2})`, descuentos con `-`), descripción del pago según tipo (`{quincena1:'1RA QUINC',quincena2:'2DA QUINC',mensual:'MENSUAL',sac:'SAC',vacaciones:'VACACIONES',final:'LIQUIDACION FINAL'}` + mes en mayúsculas + año), antigüedad = `antiguedadEntre(fecha_ingreso, fecha_pago)` (así da 0a 4m 20d como en el recibo, con fecha de pago 18/09 y último ingreso 27/04… **verificar**: 27/04 → 18/09 = 0a 4m 22d; el recibo dice 20d porque cuenta hasta el 15/09 (fin de quincena). Usar `finPeriodo(periodo,tipo)`), "INICIO TIEMPO SERVICIO" = `fecha_ingreso_reconocida || fecha_ingreso`. Página 2: tabla de composición + cuadro de porcentajes + torta SVG (`<circle>` con `stroke-dasharray` por rubro, 7 colores planos) + nota. Pie en ambas: leyenda, "Página N de 2", firmas.

- [ ] **Step 3: UI**
```js
function _reciboArgs(l,i){
  const e=empleados.find(x=>x.id===i.empleado_id)||{};const cfg=configContable||{};const fin=finPeriodo(l.periodo,l.tipo);
  return {empresa:{razon_social:cfg.razon_social_recibo||currentEmpresa?.nombre||'',domicilio:cfg.domicilio_recibo||'',localidad:'',actividad:cfg.actividad_recibo||'',cuit:cfg.cuit_empleador||''},
    empleado:e,item:i,liquidacion:l,conceptosCat:conceptosSueldo,config:cfg,escala:e.convenio==='fuera'?{valor_hora:0,basico_mensual:e.sueldo_pactado}:vigenteA(sueldosEscala.filter(x=>x.categoria===e.categoria_escala),fin),copias:['ORIGINAL','DUPLICADO']};
}
function imprimirRecibo(liqId,eid){
  const l=liquidaciones.find(x=>x.id===liqId);const i=(l?.liquidacion_items||[]).find(x=>x.empleado_id===eid);if(!l||!i)return;
  const win=window.open('','_blank');if(!win)return notify('El navegador bloqueó la ventana emergente','err');
  win.document.write(`<!DOCTYPE html><html><head><title>Recibo ${esc(i.recibo_nro||'')}</title></head><body>${renderRecibo(_reciboArgs(l,i))}</body></html>`);win.document.close();
  setTimeout(()=>win.print(),300);
}
function imprimirRecibosLiquidacion(liqId){
  const l=liquidaciones.find(x=>x.id===liqId);if(!l)return;
  const items=(l.liquidacion_items||[]).slice().sort((a,b)=>String(empleados.find(e=>e.id===a.empleado_id)?.legajo||'').localeCompare(String(empleados.find(e=>e.id===b.empleado_id)?.legajo||''),undefined,{numeric:true}));
  const win=window.open('','_blank');if(!win)return notify('El navegador bloqueó la ventana emergente','err');
  win.document.write(`<!DOCTYPE html><html><head><title>Recibos ${liqPeriodoFmt(l.periodo)}</title></head><body>${items.map(i=>renderRecibo(_reciboArgs(l,i))).join('')}</body></html>`);win.document.close();
  setTimeout(()=>win.print(),500);
}
```
`renderRecibo` incluye su `<style>` una sola vez por documento: envolver el CSS en `<style id="recibo-css">` y en el lote concatenar sólo el primero (el resto con `{sinCss:true}`).

Configuración: agregar en la página Configuración → Imputación (o donde están `cuit_empleador`) los campos `razon_social_recibo`, `domicilio_recibo`, `actividad_recibo`, `f931_ultimo_periodo`, `f931_ultimo_fecha`, `f931_banco`, `tope_indemnizatorio` (agregar esta columna a `config_contable` en Task 1 §4: `tope_indemnizatorio numeric(14,2)`).

- [ ] **Step 4: Correr tests** (2 PASS) y verificar en el navegador: imprimir el recibo del ingresante y compararlo con la foto bloque por bloque.
- [ ] **Step 5: Commit** — `git commit -m "feat(sueldos): recibo de haberes imprimible (2 páginas, original y duplicado, composición salarial con torta) individual y por lote"`

---

### Task 13: Docs, verificación final y cierre

**Files:**
- Modify: `docs/MANUAL_USUARIO.md` (sección Sueldos: escalas y parámetros, legajo, novedades, calcular, baja, recibos, conceptos ARCA e importador), `docs/MANUAL_USUARIO.docx` (`pandoc docs/MANUAL_USUARIO.md -o docs/MANUAL_USUARIO.docx`), `CLAUDE.md` (bloque "Sueldos 083" en Supabase + módulo en la lista), spec (estado → implementado)

- [ ] **Step 1: Suite completa** — `node --test tests/*.test.js` → 287 + nuevos, 0 fallos. `node -e "require('./tests/_harness').load()"` sin error.
- [ ] **Step 2: Migración en prod** — pasar `migrations/083_sueldos_motor.sql` al SQL Editor, correr, ejecutar la VERIFICACIÓN. Recién entonces `git push origin main` (Netlify deploya).
- [ ] **Step 3: Smoke en prod (checklist del usuario, documentar en la spec §Verificación)**: cargar valor hora de las categorías reales y IMGR; cargar ART y sepelio; marcar el empleado alcanzado por Ganancias y sus deducciones; novedades de la 2ª quincena de septiembre; Calcular; comparar contra el recibo de la contadora renglón por renglón; exportar TXT de conceptos "faltan en ARCA" y subirlo en ARCA; exportar LSD; imprimir un recibo.
- [ ] **Step 4: CLAUDE.md** — párrafo "Sueldos 083 — motor de liquidación" con: tablas nuevas, columnas, puras y sus tests, páginas `sueldosnov`/`sueldosparam` bajo tab `nomina`, RPCs re-emitidas (**ediciones futuras de `guardar_liquidacion` / `confirmar_liquidacion` parten de 083**), regla de códigos (padrón ARCA), preguntas abiertas para la contadora.
- [ ] **Step 5: Commit y push** — `git commit -m "docs(sueldos): manual y CLAUDE.md para el motor de liquidación 083"` + `git push`.

---

## Self-review (hecho al escribir el plan)

- **Cobertura de la spec:** modelo de datos (T1), catálogo/padrón/TXT/Excel/importador (T1, T2, T7), escala y parámetros (T1, T8), legajo (T1, T9), novedades (T1, T10), motor completo con quincenas/topes/F.931/contribuciones/redondeo (T4), Ganancias (T5), SAC y final (T6, T9, T11), liquidación con Calcular/traza/Recalcular (T11), LSD con bloqueo (T11), recibo 2 páginas (T12), acumulados (T1 vista + T9 helper), tests (T2-T6, T12), manual (T13). Vacaciones: días por antigüedad y valor día en T3/T4 (concepto 18 vía novedad `vacaciones_dias`); en liquidación final en T6.
- **Correcciones a la spec incorporadas:** 998 → ARCA 799999 no remunerativo; ANSSAL cuenta en "Seguridad Social" del empleador en la página 2; concepto 901 devolución de Ganancias; `causa_egreso` en `liquidaciones`; `tope_indemnizatorio` en `config_contable`; orden 59 del concepto 102 para que entre en el IMGR.
- **Consistencia de nombres:** `computeRecibo` (T4) ↔ `_ctxRecibo` (T9) ↔ `liqCalcularEmpleado` (T11) ↔ `previewBaja` (T9); `_liqDetalle[eid]` con `{conceptos, f931, ganancias, contribuciones_detalle, alertas}` en T9/T11/T12; `contribuciones_detalle[].codigo` 640-647 en T4/T12; marcas de 15 en T1/T2/T4/T7; `sueldosAcumulados` de `v_sueldos_acumulados` en T9/T11.
- **Riesgo conocido:** los centavos del recibo real dependen del orden de redondeo; el test de T4 es la referencia y, si difiere, se ajusta el motor (no el test).
