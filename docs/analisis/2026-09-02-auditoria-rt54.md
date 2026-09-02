# Auditoría contable VitalStock vs. RT 54 (modelo EECC para Entidades Pequeñas)

**Fecha:** 2026-09-02
**Referencia:** "Modelo de presentación de estados contables para entidades pequeñas con fines de lucro — primer ejercicio de aplicación" (CPCECABA, Res. P. 460/2024), archivos `RT 54 Modelo de EECC para EP con fines de lucro.docx` / `.xlsx`.
**Alcance:** módulo contable de `~/vitalmet-erp` (index.html @ bbae63b, migraciones 007–071). Se auditó el diseño y el código, no los saldos de producción.
**Vigencia RT 54:** obligatoria para ejercicios iniciados desde el 01/01/2025. El próximo cierre de Vitalmet SA ya cae bajo la norma.

---

> **Estado de implementación (2026-09-02):** los cuatro sprints de la sección 6 están implementados. Sprint A (mig 072, ajustes de cierre), B (inflación con anticuación), C (mig 073, bienes de uso) y D (estados RT 54 exportables) LIVE. Quedan a cargo de Vitalmet: cargar los bienes de uso reales, asignar rubro a las cuentas que la 072 dejó sin clasificar, unificar RNA 314000/314002 con la contadora, y redactar las notas de políticas contables sobre el modelo del Consejo.

---

## 1. Veredicto

La **base registral es sólida** y cumple con lo que la norma da por supuesto: partida doble validada en la base, asientos inmutables, períodos mensuales bloqueados, ejercicios con cierre y apertura, Libro Diario y Mayores exportables, audit log, IPC cargado.

Pero **hoy el ERP no puede emitir los estados contables que exige la RT 54**. El modelo del Consejo pide 4 estados + notas + 8 anexos en moneda homogénea y comparativos. VitalStock produce un balance de sumas y saldos, un "balance general" plano por tipo de cuenta y un estado de resultados en dos columnas. Entre lo que produce y lo que la norma exige hay **7 brechas de medición** (afectan los números) y **8 brechas de exposición** (afectan cómo se presentan).

Lo más grave, en orden:

1. El ajuste por inflación aplica un coeficiente único al saldo acumulado, sin anticuación de partidas. Sobreestima el ajuste de todo lo incorporado durante el ejercicio y ajusta el Capital contra sí mismo.
2. No existe costo de ventas ni costo de producción contable. Los bienes de cambio nunca salen del activo por la vía contable.
3. No hay bienes de uso con depreciaciones. Anexo imposible, activo sobrevaluado, resultado subestimado.
4. Activos y pasivos en dólares quedan al tipo de cambio histórico del asiento. La norma exige tipo de cambio de cierre.
5. No se devengan impuesto a las ganancias, previsiones por incobrables ni vacaciones al cierre.

---

## 2. Cobertura del modelo RT 54

| Componente del modelo | Estado | Qué tiene VitalStock | Qué falta |
|---|---|---|---|
| Carátula (datos societarios, capital) | 🟡 | `empresas` con CUIT, `ejercicios` con N° y fechas | Composición del capital, datos IGJ |
| Estado de Situación Patrimonial | 🟡 | `renderBalanceGeneral` (plano, por tipo); `_grupoBimon` clasifica corriente/no corriente por prefijo | Rubros RT 54, corriente/no corriente en el ESP, comparativo, referencias a notas |
| Estado de Resultados | 🟡 | `renderEstadoResultados` (ingresos vs egresos, lista plana) | CMV, resultado bruto, gastos por función, RFyT+RECPAM en una línea, IIGG, comparativo |
| Estado de Evolución del PN | ❌ | Cuentas 31xxxx sin nombre; cierre pasa resultado a 314002 | Capital / Ajuste de capital / Reserva legal / RNA, movimientos del ejercicio |
| Estado de Flujos de Efectivo (sintético, directo) | ❌ | Nada (el "cashflow" de sueldos es proyección) | Todo. Insumo disponible: asientos contra 111xxx |
| Nota 1.3 Unidad de medida | 🟡 | IPC INDEC dic-2016=100, RECPAM 412004, comparativo hist/ajustado | Anticuación, reexpresión del comparativo, Ajuste de capital separado |
| Nota 2 Políticas de medición | 🟡 | Bienes de cambio a costo de OC (USD) y PT a costo real de OP | ME a TC cierre, previsiones, préstamos a costo amortizado, IIGG |
| Nota 3 Composición de rubros | 🟡 | Mayores por cuenta | Mapeo cuenta → rubro RT 54 |
| Anexo A y P en moneda extranjera | 🟡 | Asientos bimonetarios (`moneda`, `tipo_cambio`, `tc_tipo`) | Saldo por moneda por cuenta y revalúo al cierre |
| Anexo Bienes de uso | ❌ | Cuentas 122xxx + amort. acumuladas (sin uso) | Subledger, altas/bajas, depreciación del ejercicio |
| Anexo Propiedades de inversión | n/a | No aplica a Vitalmet | — |
| Anexo Activos intangibles | 🟡 | 122004 "Sist y programas" está dentro de bienes de uso | Reclasificar a 123xxx, amortizar |
| Anexo Previsiones | ❌ | Ninguna previsión en el plan ni en el código | Incobrables (hay aging FIFO en cta cte), desvalorización, juicios |
| Anexo Costo de bienes vendidos | ❌ | Kardex + valuación de inventario en USD (`computeValuacionMP/PT`), fuera de la contabilidad | EI + compras + costo producción − EF |
| Anexo Costo de producción y gastos por naturaleza | 🟡 | Plan ya separado por función (421/422/423) con naturaleza en el nombre | Atributo "naturaleza" por cuenta para armar la matriz |
| Anexo Partes relacionadas | 🟡 | Cuentas particulares de socios 113013–113016 | Rubro propio + anexo de saldos y transacciones |

---

## 3. Hallazgos de medición (afectan los importes)

### M-01 · Ajuste por inflación sin anticuación de partidas — GRAVE
**Evidencia:** `index.html:7423` `calcularAjusteInflacion` toma el saldo acumulado de cada cuenta `es_ajustable` a la fecha "hasta" y lo multiplica por `IPC_hasta / IPC_desde`. Un solo coeficiente para todo el saldo.
**Por qué está mal (RT 54, Nota 1.3 del modelo):** la norma exige "determinar el momento de origen de las partidas" y aplicar a cada una el coeficiente desde su origen. Con un coeficiente único:
- Una máquina comprada en octubre se reexpresa como si fuera de enero.
- Las ventas y gastos del ejercicio (cuentas 4xxxxx marcadas ajustables en la migración 009) se reexpresan con el coeficiente anual completo en vez de mes a mes.
- El RECPAM, que sale como contrapartida de cuadre (`recpamDebe/recpamHaber`), absorbe todo ese error.
**Efecto adicional:** la cuenta 310000 (Capital) es ajustable y recibe el ajuste **en la misma cuenta**. RT 54 Nota 2.16: "Capital" se mantiene a valor nominal y el ajuste va a "Ajuste de capital". El capital social contable dejaría de coincidir con el estatuto.
**Comparativo:** `renderComparativoEjercicios` (`index.html:7691`) compara saldos nominales y **excluye** los asientos de ajuste. La norma exige el ejercicio anterior reexpresado a moneda de cierre del actual.
**Recomendación:** rehacer el motor con anticuación mensual: (a) saldo de inicio ya reexpresado × coef(inicio→cierre); (b) cada movimiento del ejercicio × coef(mes del movimiento→cierre); (c) capital y aportes: ajuste a 312000; (d) resultados mes a mes; (e) comparativo = saldos del cierre anterior × coef(cierre anterior→cierre actual). El índice a citar es la serie FACPCE (misma serie INDEC nacional desde 2017).

### M-02 · Sin costo de ventas ni costo de producción contable — GRAVE
**Evidencia:** `generarAsientoFactura` (`index.html:4592`) asienta Deudores / Ventas + IVA Débito. No hay asiento de costo. Las compras de materia prima debitan 114002 (config `cta_compra_mp`, migración 012) y nunca se acreditan al consumir: `consumir_barra` mueve kardex, no contabilidad. Los costos de fábrica (421xxx: sueldos, cargas, mantenimiento) van directo a resultado. `CLAUDE.md` lo lista como pendiente ("CMV/inventario permanente contable").
**Consecuencia:** Bienes de cambio en el balance = compras históricas acumuladas menos ajustes manuales. Resultado bruto no determinable. El anexo CMV del modelo no se puede armar.
**Recomendación (camino EP, mínimo cambio):** la RT 54 admite para EP el costo de ventas por **diferencia de inventario** (Nota 2.14 del modelo). Ya existe la valuación de existencia final (`computeValuacionMP/PT`, exportable "Valuación de inventario", conteo físico). Falta un paso en el wizard de cierre: "Variación de existencias" que lleve los saldos 114xxx a la valuación al cierre contra una cuenta nueva **511000 Costo de los bienes vendidos**, y reclasifique 421xxx como "Costo de producción" dentro del anexo. Con eso el ER queda Ventas − CMV = Resultado bruto sin inventario permanente.

### M-03 · Bienes de uso sin depreciaciones — GRAVE
**Evidencia:** cero ocurrencias de "amortiz"/"deprec" en `index.html` y migraciones. Las cuentas 122010–122014 (Amort. Acum.) están definidas con `saldo_habitual='deudor'` (migración 014), es decir como activo y no como regularizadora. No hay amortización acumulada para Herramientas (122008), Sist. y programas (122004) ni Construcciones (122006).
**Consecuencia:** activo no corriente sobrevaluado, resultado sobreestimado, anexo Bienes de uso (valores de origen, altas, bajas, depreciación del ejercicio y acumulada) imposible. Además la RT 6/54 queda incompleta en su partida principal para una metalúrgica.
**Recomendación:** tabla `bienes_uso` (rubro, fecha alta, valor origen, vida útil, baja) + cálculo lineal anual + asiento automático en el cierre + anexo. Cada bien anticuado por su fecha de alta alimenta también M-01.

### M-04 · Moneda extranjera al tipo de cambio histórico — GRAVE
**Evidencia:** cada asiento guarda `moneda`, `tipo_cambio` y `tc_tipo`; los reportes convierten con `toARS(l.debe, a)` al TC del asiento (`_agregarSaldos`, `index.html:8708`). No existe cuenta "Diferencia de cambio" (424xxx no la tiene) ni proceso de revalúo. Como el core opera en USD (ventas, presupuestos, stock, facturas convertidas al TC BNA del día), Deudores por ventas y proveedores del exterior quedan a TC de origen.
**Norma:** Nota 2.1 del modelo: "activos y pasivos en moneda extranjera medidos al tipo de cambio de cierre". Anexo "Activos y pasivos en ME" exige monto en moneda extranjera, TC aplicado y monto en pesos por rubro.
**Recomendación:** paso de cierre "Diferencia de cambio": para cada cuenta monetaria con líneas en USD, saldo en USD × TC cierre − saldo en ARS contabilizado → asiento contra 424006 Diferencias de cambio (dentro de RFyT). Exponer saldo por moneda en el mayor.

### M-05 · Impuesto a las ganancias no devengado — MEDIO
**Evidencia:** existen 425001 "Imp. a las ganancias", 213005 "Ganancias a pagar" y 113009 "Anticipo ganancias", pero ningún flujo las usa; el cierre (`calcularCierre`, `index.html:7135`) refunde resultados sin línea de impuesto.
**Norma:** el modelo permite a EP el método del impuesto determinado (Nota 2.15) sin impuesto diferido. Igual hay que devengarlo antes de refundir.
**Recomendación:** paso 0 del wizard de cierre: importe del impuesto determinado (lo carga la contadora) → 425001 / 213005 neto de anticipos y retenciones (113009, 113018, 113022).

### M-06 · Sin previsiones — MEDIO
**Evidencia:** ninguna cuenta ni rutina de previsión (incobrables, desvalorización de bienes de cambio, juicios). La cta cte ya calcula aging FIFO.
**Norma:** Nota 2.4 ("previsión por antigüedad de la cartera") y Anexo Previsiones con saldo inicial, aumentos, utilizaciones, reversiones.
**Recomendación:** cuenta regularizadora 112090 Previsión para incobrables + política por tramos de antigüedad (configurable) + asiento de cierre + anexo. Registrar previsión para juicios laborales si los hubiera.

### M-07 · Deudas laborales incompletas — MEDIO
**Evidencia:** provisión SAC (214008, migración 066) = 1/12 del bruto **sin cargas sociales** (simplificación documentada). No hay provisión de vacaciones (migración 065: "fuera de Fase 1").
**Norma:** Nota 3.11 del modelo: "Provisión para vacaciones y cargas sociales" y "Provisión para SAC y cargas sociales".
**Recomendación:** sumar contribuciones (27,35 % hoy configurado) a la provisión SAC y agregar provisión de vacaciones devengada (días ganados × valor día) al cierre.

---

## 4. Hallazgos de exposición (afectan la presentación)

### E-01 · Cuentas de PN sin nombre y RNA duplicada
310000, 312000, 313001 y 314000 tienen como nombre su propio código (migración 014). El cierre pasa el resultado a **314002** "Resultados No Asignados" (migración 010) mientras el histórico presumiblemente vive en **314000**. Sin nombres no se puede armar el EEPN (Capital suscripto / Ajuste de capital / Aportes irrevocables / Reserva legal / Otras reservas / RNA). Falta reserva legal (art. 70 LGS) y registro de distribuciones.
**Acción:** renombrar 310000 Capital suscripto, 312000 Ajuste de capital, 313001 Reserva legal, unificar RNA en una sola cuenta (migrar saldo de 314000 a 314002 o al revés) y desactivar la sobrante.

### E-02 · Estado de Resultados sin estructura RT 54
`renderEstadoResultados` (`index.html:8723`) lista cuentas de ingreso y egreso. El modelo exige: Ventas · CMV · **Ganancia bruta** · Gastos de comercialización (423) · Gastos de administración (422) · Desvalorizaciones · **RFyT incl. RECPAM** (424 + 412003 + 412004 + diferencias de cambio) · Otros ingresos y egresos (425 + 412) · Resultado antes de IIGG · IIGG · Resultado del ejercicio, con columna comparativa. Las agrupadoras ya permiten el mapeo salvo CMV (M-02).

### E-03 · ESP sin rubros ni corriente/no corriente
`renderBalanceGeneral` (`index.html:8768`) muestra activo/pasivo/PN planos. Existe la heurística `_grupoBimon` (prefijo 11/12/21/22) que sirve de base, pero el plan no tiene 220000 Pasivo no corriente y el leasing (212002) cae en corriente. El ESP del modelo exige los rubros de la tabla del punto 5, con doble columna y referencia a notas.

### E-04 · Reporte de Ratios usa un plan de cuentas inexistente
`_esActivoCorriente` y compañía (`index.html:8832–8835`) filtran por códigos con puntos (`1.1.`, `5.1.01`, `2.1.08`) que no existen en el plan Vitalmet (6 dígitos). Liquidez, endeudamiento, CMV y días de inventario dan cero. Es código muerto que engaña. Reemplazar por `_grupoBimon` + agrupadoras.

### E-05 · Reclasificaciones de plan de cuentas necesarias
Ver tabla del punto 5. Las principales: cheques de cobro diferido (111006) van a Cuentas por cobrar a clientes, no a Caja y bancos; plazo fijo y FCI (111007, 111009) van a **Inversiones financieras**; cuentas particulares de socios (113013–016) van a **Créditos en moneda con partes relacionadas**; cheques de pago diferido (212003) van dentro de Proveedores; leasing (212002) va a **Préstamos y otros pasivos financieros** a costo amortizado, con porción no corriente; 122004 Sist. y programas es **Activo intangible**.

### E-06 · Anticipos de clientes sin tratamiento
Cero ocurrencias de "anticipo" de clientes. Un cobro a cuenta antes de facturar queda como saldo acreedor en Deudores (activo negativo). El modelo lo expone como pasivo "Deudas en especie — Anticipos recibidos de clientes" (Nota 2.12, medido al mayor entre el bien a entregar y los costos de cumplir). Para una empresa que trabaja a pedido con seña, es material.
**Acción:** cuenta 215001 Anticipos de clientes + en `registrar_cobro`, cuando el cobro supera la deuda facturada, el excedente va al pasivo y se aplica al facturar.

### E-07 · Limpieza de datos del plan
111002 y 113008 sin nombre; 112001 "RODADOS" colgado de Créditos por ventas (duplica 122001); 666666 "Cuenta de ajustes" tipo egreso, huérfana, comentada como contrapartida RECPAM pero el código usa 412004; 425006 "Gastos de bienes de uso" ambigua; 213012 "BP-Acciones" (bienes personales de los accionistas pagado por la sociedad) debería ir contra partes relacionadas, no como deuda fiscal propia.

### E-08 · Estados que no existen
EEPN, EFE (con conciliación efectivo vs ESP, RT 54 p. 672.a) y todos los anexos. Todo se puede derivar de `asientos` + `asiento_lineas` + un atributo `rubro_rt54` por cuenta; el xlsx del Consejo es un template válido para el exportable.

---

## 5. Mapeo propuesto: plan Vitalmet → rubros RT 54

| Cuentas Vitalmet | Rubro RT 54 | Observación |
|---|---|---|
| 111001–111004, 111005, 111008 | Caja y bancos | Efectivo, bancos, valores a depositar |
| 111007 Plazo fijo, 111009 FCI | **Inversiones financieras** | Reclasificar (hoy en Disponibilidades) |
| 112016 Deudores por ventas, 111006 Cheques diferidos recibidos | **Cuentas por cobrar a clientes en moneda** | Neto de previsión (M-06); cheques reclasificar |
| 113001–113009, 113018–113022 | Créditos impositivos | OK |
| 113013–113016 Ctas. particulares | **Créditos en moneda con partes relacionadas** | Reclasificar + Anexo partes relacionadas |
| 113023, 121001 Préstamos personal, 121002 | Otras cuentas por cobrar en moneda | Corriente / no corriente según plazo |
| 114001 Mercaderías (PT), 114002 MP, 114003 Accesorios | Bienes de cambio | Requiere CMV (M-02) |
| 122001–122008 menos 122004 | Bienes de uso | Requiere depreciaciones (M-03) |
| 122004 Sist. y programas | **Activos intangibles** | Reclasificar a 123xxx |
| 211002 Proveedores, 212003 Cheques diferidos emitidos, GR/IR | Proveedores de bienes y servicios | Cheques reclasificar |
| 212002 Leasing | **Préstamos y otros pasivos financieros** | Costo amortizado, porción no corriente |
| 213002–213015 | Deudas fiscales | Sumar IIGG determinado (M-05) |
| 214001–214008 | Deudas laborales y previsionales | Sumar vacaciones y cargas s/SAC (M-07) |
| (nueva) 215001 Anticipos de clientes | **Deudas en especie** | E-06 |
| (nueva) 216001 Previsión para juicios | Previsiones | Si aplica |
| 310000 / 312000 / 313001 / 314000-314002 | PN: Capital / Ajuste de capital / Reserva legal / RNA | Renombrar y unificar (E-01) |
| 411001–411009 | Ingresos por venta de bienes | Netos de NC (ya) |
| 421xxx | Costo de producción → CMV (Anexo) | M-02 |
| 423xxx | Gastos de comercialización | OK |
| 422xxx | Gastos de administración | OK |
| 424xxx, 412003, 412004 RECPAM, (nueva) dif. de cambio | Resultados financieros y por tenencia (incl. RECPAM) | Una línea, opción EP |
| 425002–425008, 412 otros | Otros ingresos y egresos | OK |
| 425001 | Impuesto a las ganancias | Línea propia |

---

## 6. Roadmap sugerido (orden por impacto en el próximo cierre)

**Sprint A — "Cierre RT 54 mínimo" (plan + wizard de cierre)**
1. Migración de plan: renombrar PN, unificar RNA, crear 312000 Ajuste de capital activo, 511000 CMV, 424006 Diferencias de cambio, 112090 Previsión incobrables, 215001 Anticipos de clientes, 123xxx Intangibles; reclasificar padres según punto 5; corregir `saldo_habitual` de amort. acumuladas; limpiar E-07. Agregar columna `rubro_rt54` y `naturaleza` a `cuentas_contables`.
2. Wizard de cierre con pasos previos a la refundición: (0) IIGG determinado, (1) previsión incobrables por aging, (2) provisión vacaciones + cargas s/SAC, (3) diferencia de cambio al TC cierre, (4) variación de existencias contra valuación de inventario (CMV por diferencia de inventario), (5) depreciaciones (cuando exista Sprint C).
3. Arreglar Ratios (E-04) sobre `_grupoBimon`.

**Sprint B — Ajuste por inflación con anticuación (M-01)**
Motor nuevo: partidas por mes de origen, saldo inicial reexpresado + movimientos mensuales, ajuste de capital a 312000, RECPAM directo por partidas monetarias (no como plug), comparativo reexpresado a moneda de cierre. Índice: serie FACPCE.

**Sprint C — Bienes de uso (M-03)**
Tabla `bienes_uso`, altas desde OC (herramientas ya tienen cuenta), depreciación lineal, asiento de cierre, anexo con valores de origen / altas / bajas / acumuladas, anticuación por fecha de alta.

**Sprint D — Estados RT 54 exportables**
ESP, ER, EEPN, EFE sintético con conciliación, Notas 3.x de composición y anexos (ME, BU, Previsiones, CMV, Gastos por naturaleza, Partes relacionadas), doble columna comparativa, generados sobre el xlsx del Consejo como template. Modo Contador los consume en solo lectura.

---

## 7. Qué puede hacer la contadora hoy con el ERP

Exportables ya disponibles y útiles para armar los EECC afuera: Balance de sumas y saldos, Libro Diario, Mayores, Plan de cuentas, Valuación de inventario (existencia final para el CMV por diferencia), Cheques, Cta. cte con aging (base de la previsión), Retenciones sufridas, Posición IVA, Libro IVA Digital. Con eso más los ajustes extracontables de los puntos M-01 a M-07 se llega al primer balance RT 54. Lo que el ERP **no** puede aportar hoy: depreciaciones, saldos en moneda extranjera por cuenta, anticuación de partidas.
