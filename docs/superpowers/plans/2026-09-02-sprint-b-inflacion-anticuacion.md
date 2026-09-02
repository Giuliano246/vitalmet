# Sprint B — Ajuste por inflación con anticuación · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar el motor de ajuste por inflación de coeficiente único por uno que anticúa cada partida por su mes de origen (RT 54, Nota 1.3 del modelo EP), lleve el ajuste del Capital a "Ajuste de capital" y reexprese el comparativo a moneda de cierre.

**Architecture:** Una función pura `computeAnticuacion` recibe líneas, asientos, cuentas e índices y devuelve por cuenta el saldo nominal, el ajuste anticuado mes a mes y las líneas del asiento (RECPAM como contrapartida). Detecta el último asiento de ajuste confirmado: todo lo anterior ya está en moneda de esa fecha y se reexpresa con un solo coeficiente; lo posterior se anticúa por mes. La página Ajuste por inflación, el comparativo Histórico vs Ajustado y el Comparativo entre ejercicios consumen el mismo motor. No requiere SQL (usa `rubro_rt54` de la 072).

**Tech Stack:** index.html vanilla JS; `node --test` con `tests/_harness.js`.

**Spec:** `docs/analisis/2026-09-02-auditoria-rt54.md` hallazgo M-01 y sección 6 Sprint B.

## Global Constraints

- Sin migración: el frontend se pushea directo tras tests verdes (regla 1: un cambio, deploy, verificar).
- Asientos por RPC `crear_asiento`, en borrador, `origen_tipo 'ajuste_inflacion'` (el motor lo usa para reconocer ajustes previos: NO cambiar el valor).
- Índice: serie IPC cargada en `indices_ipc` (INDEC nacional = serie FACPCE desde 2017). Un mes sin índice usa el índice anterior más cercano y se avisa.
- Voseo, `esc()`, `node --check`, tests.

---

### Task 1: Motor `computeAnticuacion` + tests
**Files:** `index.html` (bloque "AJUSTE POR INFLACIÓN"), `tests/ajuste-inflacion.test.js`.
**Interfaz:**
```js
computeAnticuacion({lineas, asientos, cuentas, indices, hasta, recpamId, ajusteCapitalId, ignorarAjustes=false})
// → {error} | {mesHasta, ipcCierre, fechaAsiento, ultimoAjuste, filas:[{cuenta, destino, saldoHist, ajuste, saldoAjustado, coefPromedio, detalle:[{mes, monto, coef, ajuste}]}],
//    lineas:[{cuenta_id,debe,haber,descripcion,orden}], totDebe, totHaber, recpamDebe, recpamHaber, mesesSinIndice:[], advertencias:[]}
ipcMasCercano(indicesMap, mes) // → {indice, mesUsado} | null   (indicesMap: {'AAAA-MM': número})
```
- [ ] Tests: caso base (apertura + alta a mitad de año + venta en el mes de cierre; Capital → Ajuste de capital; RECPAM plug), ajuste previo (todo lo anterior con coef único), `ignorarAjustes`, mes sin índice (usa el anterior + aviso), falta IPC de cierre → error, refundición ya registrada → advertencia.
- [ ] Implementar; `node --test tests/ajuste-inflacion.test.js` verde.
- [ ] Commit `feat(inflacion): motor de anticuación mensual con tests`

### Task 2: Página Ajuste por inflación sobre el motor
**Files:** `index.html` HTML `page-ajuste` (selects Desde/Hasta → sólo Cierre mes/año + panel "último ajuste"), JS `renderAjuste`/`calcularPreviewAjuste`/`pintarPreviewAjuste`/`generarAsientoAjusteInflacion`.
- [ ] Preview: tabla por cuenta con saldo nominal, ajuste, saldo ajustado, debe/haber, `title` con el detalle por mes; stats: IPC cierre, cuentas, RECPAM; advertencias (meses sin índice, refundición ya registrada, sin cuenta Ajuste de capital).
- [ ] Generar: mismo flujo (borrador, RPC). Commit `feat(inflacion): página de ajuste con anticuación mensual`.

### Task 3: Comparativos en moneda homogénea
**Files:** `index.html` `renderComparativoHA` (usa el motor con `ignorarAjustes:true`; HTML sin selects de IPC base), `renderComparativoEjercicios` (checkbox "Moneda homogénea": saldos con ajustes incluidos y columna A × IPC_B / IPC_A).
- [ ] Commit `feat(comparativos): histórico vs ajustado por anticuación y comparativo reexpresado a moneda de cierre`.

### Task 4: Docs
- [ ] CLAUDE.md bullet "Ajuste por inflación con anticuación (Sprint B)", manual §11.8, docx, textos "RT 6" → "RT 54" en subtítulos. Commit y push.
