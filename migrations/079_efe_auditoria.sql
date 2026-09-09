BEGIN;
ALTER TABLE public.efe_clasificaciones ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS efe_clasificaciones_id ON public.efe_clasificaciones(id);
DROP TRIGGER IF EXISTS contador_guard ON public.efe_clasificaciones;
CREATE TRIGGER contador_guard BEFORE INSERT OR UPDATE OR DELETE ON public.efe_clasificaciones FOR EACH STATEMENT EXECUTE FUNCTION public.fn_contador_guard();
COMMIT;
-- Verificación: SELECT tgname, tgtype FROM pg_trigger WHERE tgrelid='public.efe_clasificaciones'::regclass;
