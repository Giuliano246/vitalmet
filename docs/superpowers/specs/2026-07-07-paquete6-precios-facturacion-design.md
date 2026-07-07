# Paquete 6 — Precios y Facturación: precios base, último precio, lote

**Fecha:** 2026-07-07 · **Estado:** aprobado por Giuliano (modelo elegido: precio base por producto + último precio al cliente)

## 6A. Precios base (migración 049)

```sql
CREATE TABLE IF NOT EXISTS precios_base (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  pieza text NOT NULL,
  precio_usd numeric NOT NULL DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  UNIQUE(empresa_id, pieza)
);
```
Con RLS `tenant_isolation` (patrón estándar) + trigger `touch_updated_at`.

- Nueva tab **"precios"** en el grupo Ventas (registro estándar de página). Tabla pieza/precio/actualizado con edición inline (input number + guardar on-change), alta manual, y:
  - **"Ajustar todo %"**: prompt de porcentaje → preview (afecta N piezas) → confirmación → UPDATE masivo.
  - **"Importar desde stock"**: para cada `pieza` distinta de `pts` sin entrada en `precios_base`, crea la fila con el `precio_unitario` más reciente de ese PT.
- `precios_base` entra al registro `TBL` (carga en `loadAll`, es chica) y los saves usan `reload('precios_base')`.

## 6B. Resolver de precio en cascada

- Función pura `resolverPrecio(pieza, cliente, ventas, preciosBase, pts) → {precio, origen}` con `origen ∈ 'cliente'|'base'|'pt'|null`:
  1. Última venta no anulada de `cliente` (match por nombre, case-insensitive) que contenga un ítem cuya pieza (vía embed `productos_terminados(pieza)`) coincida → su `precio_unitario`.
  2. `precios_base` por pieza (case-insensitive).
  3. `precio_unitario` del PT más reciente de esa pieza.
  4. `{precio:0, origen:null}`.
- Tests en `tests/precios.test.js` (harness vm).
- Wiring: en el alta de ítem de venta (donde hoy se setea `precio:0`) y en el cotizador de presupuesto (que hoy usa solo el precio del PT): al seleccionar la pieza/PT se autocompleta con el resolver, con hint visible `últ. a este cliente: US$ X` / `precio de lista` según `origen`. El precio queda siempre editable.

## 6C. Facturación en lote

- Botón "Facturar entregadas (N)" en la toolbar de Ventas (visible si N>0): confirm → itera secuencialmente las ventas `estado='entregado'` sin `factura_emitida_id` llamando el flujo existente de `emitirFactura` (reusar su lógica sin el confirm individual), con progreso en el botón (`setBusy` + contador) y resumen final (`X facturadas, Y con error`). Ante error en una, sigue con las demás.
- Tipo de comprobante sigue B hardcodeado; A/B automático queda bloqueado por el cert X.509 de AFIP (fuera de alcance).

## Orden y reglas

6A (migración 049 → SQL Editor → UI precios) → 6B (resolver + tests + wiring) → 6C (lote). Reglas CLAUDE.md vigentes; deploy por bloque.

## Fuera de alcance
Listas múltiples por cliente, bonificaciones por grupo (`grupo_bonificacion` existente queda igual), A/B automático, precios en ARS.
