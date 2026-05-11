-- ═══════════════════════════════════════════════════════════════════
-- 010_cuentas_cierre_ejercicio.sql
-- Cuentas patrimoniales necesarias para la Fase 3 (cierre de ejercicio
-- automático): refundición de resultados + pasaje a no asignados.
--
-- Cuentas que crea:
--   314001 Resultado del Ejercicio       (PN transitoria, se cierra
--                                         con el pasaje a No Asignados)
--   314002 Resultados No Asignados       (PN permanente, absorbe el
--                                         resultado del ejercicio cerrado)
--
-- Ambas se crean con es_ajustable=true porque las cuentas de PN se
-- reexpresan por inflación (RT 6).
--
-- Idempotente: usa NOT EXISTS, no duplica si ya están creadas.
-- ═══════════════════════════════════════════════════════════════════
--
-- INSTRUCCIONES:
-- Copiar todo el archivo y pegarlo en Supabase SQL Editor → Run.
-- El UUID de empresa (Vitalmet SA) ya viene hardcodeado.
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  emp_id uuid := 'a0a19507-2a50-4e80-a716-e9459f51d653';  -- Vitalmet SA
  creadas int := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cuentas_contables
     WHERE empresa_id = emp_id AND codigo = '314001'
  ) THEN
    INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable)
    VALUES (emp_id, '314001', 'Resultado del Ejercicio', 'patrimonio', true, true, true);
    creadas := creadas + 1;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM cuentas_contables
     WHERE empresa_id = emp_id AND codigo = '314002'
  ) THEN
    INSERT INTO cuentas_contables (empresa_id, codigo, nombre, tipo, imputable, activa, es_ajustable)
    VALUES (emp_id, '314002', 'Resultados No Asignados', 'patrimonio', true, true, true);
    creadas := creadas + 1;
  END IF;

  RAISE NOTICE 'Migration 010: % cuenta(s) creada(s)', creadas;
END $$;
