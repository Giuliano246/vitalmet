-- ═══════════════════════════════════════════════════════════════════
-- 027_cheques.sql
-- Cheques diferidos (fase 3, mes 3 — roadmap auditoría)
--
-- Cartera de cheques de pago diferido (físicos y echeqs):
--   · recibidos de clientes  → en_cartera → depositado → acreditado
--                              (o rechazado / endosado a un proveedor)
--   · emitidos a proveedores → entregado → debitado
--                              (o rechazado / anulado)
--
-- La fecha_pago (cobro diferido) alimenta el digest de alertas:
-- "cheques para depositar" y "cheques emitidos a cubrir" (fondos).
-- cliente_id / proveedor_id vinculan al tercero real; asiento_id
-- opcionalmente referencia el cobro/pago contable asociado.
--
-- Aditiva, retrocompatible, idempotente. Correr ANTES del deploy.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS cheques (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES empresas(id),
  tipo text NOT NULL CHECK (tipo IN ('recibido','emitido')),
  numero text NOT NULL,
  banco text,
  echeq boolean NOT NULL DEFAULT false,
  cliente_id uuid REFERENCES clientes(id) ON DELETE SET NULL,
  proveedor_id uuid REFERENCES proveedores(id) ON DELETE SET NULL,
  librador text,
  fecha_recepcion date,
  fecha_pago date NOT NULL,
  monto numeric NOT NULL CHECK (monto > 0),
  moneda text NOT NULL DEFAULT 'ARS' CHECK (moneda IN ('ARS','USD')),
  tipo_cambio numeric,
  estado text NOT NULL DEFAULT 'en_cartera'
    CHECK (estado IN ('en_cartera','depositado','acreditado','rechazado',
                      'endosado','entregado','debitado','anulado')),
  asiento_id uuid REFERENCES asientos(id) ON DELETE SET NULL,
  observaciones text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cheques_empresa ON cheques (empresa_id);
-- Los estados "vivos" son los que importan para vencimientos
CREATE INDEX IF NOT EXISTS idx_cheques_fecha_pago ON cheques (fecha_pago)
  WHERE estado IN ('en_cartera','entregado','depositado');

-- ─── RLS: mismo patrón tenant_isolation que el resto ─────────────────
ALTER TABLE cheques ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON cheques;
CREATE POLICY tenant_isolation ON cheques FOR ALL TO authenticated
  USING (empresa_id = public.current_empresa_id())
  WITH CHECK (empresa_id = public.current_empresa_id());

-- ─── Auditoría: es plata, va al audit_log como ventas/asientos ───────
DROP TRIGGER IF EXISTS trg_audit ON cheques;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON cheques
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después)
-- ═══════════════════════════════════════════════════════════════════
-- SELECT (SELECT count(*) FROM information_schema.tables
--          WHERE table_name='cheques') AS tabla,
--        (SELECT count(*) FROM pg_policies
--          WHERE tablename='cheques' AND policyname='tenant_isolation') AS rls,
--        (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
--          WHERE c.relname='cheques' AND t.tgname='trg_audit') AS audit;
