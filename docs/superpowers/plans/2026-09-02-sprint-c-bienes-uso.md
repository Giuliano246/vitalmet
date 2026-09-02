# Sprint C — Bienes de uso y depreciaciones · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Subledger de bienes de uso con depreciación lineal por meses, asiento automático en el cierre y anexo "Bienes de uso" del modelo RT 54 (hallazgo M-03).

**Architecture:** Migración 073 crea `bienes_uso` y `depreciaciones` (batería RLS completa), cuentas de amortización acumulada faltantes y de depreciación por centro, y la RPC `registrar_depreciacion` que arma el asiento (gasto al debe / amort. acumulada al haber, agrupado por cuenta) vía `crear_asiento` y graba las filas de depreciación en la misma transacción. Frontend: página Bienes de uso (alta, edición, baja), puras `computeDepreciacion` y `computeAnexoBienesUso`, paso 6 del panel de cierre RT 54 y exportable del anexo.

**Spec:** `docs/analisis/2026-09-02-auditoria-rt54.md` M-03 y sección 6 Sprint C.

## Tareas
- [x] 1. Migración `073_bienes_uso.sql` (tablas + trigger BU-nnnn + cuentas 122015/122016/123010/421019/422016 + RPC).
- [x] 2. Puras `computeDepreciacion(bien, desde, hasta, previas)` y `computeAnexoBienesUso(bienes, deprecs, desde, hasta)` con tests en `tests/bienes-uso.test.js`.
- [x] 3. Página `bienesuso` (grupo contabilidad, sub-tab de "Cierre e inflación"), modales alta/edición y baja, TBL `bienes_uso` / `depreciaciones`.
- [x] 4. Paso 6 "Depreciación de bienes de uso" en Ajustes de cierre RT 54 → RPC.
- [x] 5. Exportable "Anexo Bienes de uso (RT 54)".
- [x] 6. Docs (CLAUDE.md, manual md+docx). Push tras correr 073 en el SQL Editor.

Fuera de alcance: asiento automático de alta desde la factura de compra y asiento de baja (se registran en Asientos); anexo en moneda homogénea (sprint D).
