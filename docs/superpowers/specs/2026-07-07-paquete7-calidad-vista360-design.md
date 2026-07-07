# Paquete 7 — Calidad + Vista 360: auto-NCR, docs en digest, ficha enriquecida

**Fecha:** 2026-07-07 · **Estado:** aprobado por Giuliano · **Último paquete del roadmap.** Sin migraciones.

## 7A. Auto-draft de NCR al rechazar recepción

- En `rechazarRecepcion(id)`, tras el PATCH de `estado_inspeccion:'rechazado'`: POST a `no_conformidades` con `origen_tipo:'recepcion'`, `recepcion_id`, descripción pre-armada (`Rechazo de recepción <fecha> — OC <nro> · <proveedor> · ítem <detalle>` con los datos disponibles de la recepción/OC), `estado` inicial y `numero` replicando EXACTAMENTE el mecanismo del alta manual (`saveNC` — leerlo antes: si el numero lo asigna la DB, no mandarlo; si lo calcula el front, copiar el cálculo).
- `reload('recepciones_oc','ordenes_compra','oc_items','barras','no_conformidades')` + notify `NC-XXXX creada — completá la disposición en Calidad → NCR`.
- Si el POST de la NC falla, el rechazo NO se revierte: notify de error pidiendo carga manual (comportamiento actual como fallback).

## 7B. Documentos controlados en el digest

- Detector nuevo en `computeAlertas()`: `documentosControlados` con `estado==='vigente'` y `fecha_vigencia` anterior a hoy−365 días → warn "N documento(s) con revisión anual pendiente" (detalle: código + rev + fecha), page `doccontrol`. Criterio ISO 9001 de revisión periódica anual.

## 7C. Vista 360 del cliente (enriquecer `openFichaCliente`)

Se agregan a la ficha existente (sin tocar lo que ya muestra):
1. **Cta. corriente**: card con saldo total y saldo vencido del cliente (de `computeCtaCte()`, matcheando por `cliente.id`/nombre), color coral si hay vencido, botón "Ver cta. corriente" → `showPage('ctacte')`.
2. **Presupuestos abiertos**: lista de `estado in (enviado, aprobado)` del cliente con días desde `fecha`, cada uno con deep-link `showPage('presupuestos', id)`.
3. **Rentabilidad histórica**: función pura `computeRentabilidadCliente(ventasCliente, ptsArr, costoFn) → {facturado, costoEstimado, margenPct}` usando `computeCostoPT` por pieza (costo ACTUAL — aproximación documentada en la UI con un asterisco "al costo de hoy"). Test en `tests/cliente360.test.js` con `costoFn` inyectada.
4. **Último precio por pieza**: en el ranking de piezas ya existente, columna con `resolverPrecio(pieza, cliente,…)` (origen 'cliente') mostrando el último precio cobrado.

## Verificación

Suite + `node --check` por task; manual en prod: rechazar una recepción de prueba crea la NC pre-cargada; el digest muestra docs con revisión vencida (si los hay); la ficha de un cliente real muestra saldo/presupuestos/margen. Un deploy al cierre (fin del roadmap).

## Fuera de alcance
Editar la NC auto-creada desde el modal de recepción, workflow de revisión de documentos (solo alerta), rentabilidad con costos históricos por lote.
