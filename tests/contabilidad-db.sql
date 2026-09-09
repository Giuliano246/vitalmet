-- Integration tests against the deployed schema. All fixtures roll back.
BEGIN;
DO $$
DECLARE uid uuid; emp uuid; banco uuid; contra uuid; cb uuid; ex uuid; ex2 uuid; r jsonb; lid uuid; n int;
BEGIN
 SELECT id,empresa_id INTO uid,emp FROM public.usuarios WHERE es_admin=true AND coalesce(es_contador,false)=false AND coalesce(es_auditor,false)=false AND coalesce(es_planta,false)=false LIMIT 1;
 IF uid IS NULL THEN RAISE EXCEPTION 'Missing test admin'; END IF;
 PERFORM set_config('request.jwt.claim.sub',uid::text,true);
 PERFORM set_config('role','authenticated',true);
 SELECT id INTO banco FROM public.cuentas_contables WHERE empresa_id=emp AND imputable=true AND rubro_rt54='caja_bancos' LIMIT 1;
 SELECT id INTO contra FROM public.cuentas_contables WHERE empresa_id=emp AND imputable=true AND id<>banco LIMIT 1;
 INSERT INTO public.cuentas_bancarias(empresa_id,nombre,moneda,cuenta_contable_id) VALUES(emp,'TEST rollback contabilidad','USD',banco) RETURNING id INTO cb;
 INSERT INTO public.extracto_bancario(empresa_id,cuenta_bancaria_id,fecha,importe) VALUES(emp,cb,'2099-06-01',123) RETURNING id INTO ex;
 BEGIN
   PERFORM public.crear_asiento_extracto(ex,contra,NULL);
   RAISE EXCEPTION 'TEST missing TC accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%tipo de cambio%' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM public.asientos WHERE origen_id=ex) THEN RAISE EXCEPTION 'Failed operation left an asiento'; END IF;
 r:=public.crear_asiento_extracto(ex,contra,1000);
 lid:=(r->>'asiento_linea_id')::uuid;
 IF lid IS NULL THEN RAISE EXCEPTION 'Missing linked line'; END IF;
 PERFORM public.crear_asiento_extracto(ex,contra,1000);
 SELECT count(*) INTO n FROM public.asientos WHERE origen_id=ex;
 IF n<>1 THEN RAISE EXCEPTION 'Retry duplicated asiento'; END IF;
 PERFORM public.guardar_clasificacion_efe(lid,'op.otros');
 PERFORM public.guardar_clasificacion_efe(lid,'fin.prestamos');
 IF NOT EXISTS(SELECT 1 FROM public.efe_clasificaciones WHERE linea_id=lid AND categoria='fin.prestamos') THEN RAISE EXCEPTION 'Classification not persisted'; END IF;
 INSERT INTO public.extracto_bancario(empresa_id,cuenta_bancaria_id,fecha,importe) VALUES(emp,cb,'2099-06-01',124) RETURNING id INTO ex2;
 BEGIN
   PERFORM public.conciliar_extracto(ex2,lid);
   RAISE EXCEPTION 'TEST incompatible amount accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%importe y el signo%' THEN RAISE; END IF; END;
 UPDATE public.extracto_bancario SET importe=123 WHERE id=ex2;
 BEGIN
   PERFORM public.conciliar_extracto(ex2,lid);
   RAISE EXCEPTION 'TEST duplicate link accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%ya conciliada%' THEN RAISE; END IF; END;
 BEGIN
   INSERT INTO public.periodos_contables(empresa_id,anio,mes,estado) VALUES(emp,2099,6,'cerrado');
   RAISE EXCEPTION 'TEST pending bank allowed closing';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%bancarios pendientes%' THEN RAISE; END IF; END;
 -- A valid user with no company must neither read nor mutate the tenant fixtures.
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 IF EXISTS(SELECT 1 FROM public.efe_clasificaciones WHERE linea_id=lid) THEN RAISE EXCEPTION 'Tenant isolation failed'; END IF;
 BEGIN
   PERFORM public.guardar_clasificacion_efe(lid,'op.otros');
   RAISE EXCEPTION 'TEST foreign tenant wrote classification';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'TEST%' THEN RAISE; END IF; END;
 BEGIN
   PERFORM public.conciliar_extracto(ex,lid);
   RAISE EXCEPTION 'TEST foreign tenant reconciled';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'TEST%' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_function_privilege('anon','public.conciliar_extracto(uuid,uuid)','EXECUTE') OR has_function_privilege('anon','public.crear_asiento_extracto(uuid,uuid,numeric)','EXECUTE') OR has_function_privilege('anon','public.guardar_clasificacion_efe(uuid,text)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous execution permitted'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'PASS: atomic creation, retry, TC, amounts, duplicate links, closing, EFE persistence and tenant isolation' AS result;
ROLLBACK;
