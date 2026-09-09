BEGIN;
CREATE OR REPLACE FUNCTION public.guardar_clasificacion_efe(p_linea_id uuid,p_categoria text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE emp uuid:=current_empresa_id();
BEGIN
 IF emp IS NULL OR NOT EXISTS(SELECT 1 FROM asiento_lineas l JOIN asientos a ON a.id=l.asiento_id WHERE l.id=p_linea_id AND a.empresa_id=emp AND a.estado='confirmado') THEN RAISE EXCEPTION 'Línea inexistente o sin permiso'; END IF;
 INSERT INTO efe_clasificaciones(empresa_id,linea_id,categoria) VALUES(emp,p_linea_id,p_categoria)
 ON CONFLICT(empresa_id,linea_id) DO UPDATE SET categoria=excluded.categoria;
 RETURN jsonb_build_object('linea_id',p_linea_id,'categoria',p_categoria);
END $$;
REVOKE ALL ON FUNCTION public.guardar_clasificacion_efe(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.guardar_clasificacion_efe(uuid,text) TO authenticated;
DROP TRIGGER IF EXISTS trg_audit ON public.efe_clasificaciones;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON public.efe_clasificaciones FOR EACH ROW EXECUTE FUNCTION public.fn_audit();
COMMIT;
-- Verificación: SELECT to_regprocedure('public.guardar_clasificacion_efe(uuid,text)');
