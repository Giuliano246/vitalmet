# Sprint D — Estados contables RT 54 exportables · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generar desde el ERP los cuatro estados básicos, las notas de composición y los anexos del modelo de EECC para Entidades Pequeñas (CPCECABA), con columna comparativa reexpresada a moneda de cierre, en Excel.

**Architecture:** Sin migración. `saldosEECC` agrega saldos con las reglas de exclusión (cierre/apertura patrimonial siempre; refundición/pasaje sólo del ejercicio en curso). `computeEstadosRT54` arma ESP (rubro × corriente/no corriente vía `_grupoBimon`), ER por función, EEPN, notas de composición y anexos de gastos por naturaleza, CMV, previsiones y partes relacionadas. `computeEFE` clasifica los asientos que tocan efectivo por el rubro de la contrapartida. La página "EECC RT 54" (sub-tab de Estados contables) muestra ESP/ER/EFE y exporta el Excel con `xlsxBuild` (una hoja por estado/anexo, mismo orden que el xlsx del Consejo).

**Spec:** `docs/analisis/2026-09-02-auditoria-rt54.md` E-02, E-03, E-08 y sección 6 Sprint D.

## Tareas
- [x] 1. Puras `saldosEECC`, `computeEstadosRT54`, `computeEFE` + tests `tests/eecc-rt54.test.js`.
- [x] 2. Página `eecc`: selector de ejercicio, TC de cierre (anexo ME), comparativo con coeficiente IPC hasta / IPC hasta anterior, vista previa, avisos (cuentas sin rubro, ESP que no cuadra).
- [x] 3. Excel `EECC_RT54_<fecha>.xlsx`: Carátula, 1-ESP, 2-ER, 3-EEPN, 4-EFE, Notas, Anexo ME, Anexo BU, Anexo Prev, Anexo CMV, Anexo Gastos, Anexo Partes rel.
- [x] 4. Docs y push.

Fuera de alcance: notas de políticas contables (texto del contador), EFE reexpresado partida por partida (sale sintético con línea de RECPAM del efectivo), anexo bienes de uso en moneda homogénea.
