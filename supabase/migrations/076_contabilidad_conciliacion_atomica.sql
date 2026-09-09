-- Conciliación bancaria atómica y sin doble vinculación.
create unique index if not exists uq_extracto_bancario_asiento_linea
  on public.extracto_bancario (asiento_linea_id)
  where asiento_linea_id is not null;

create or replace function public.conciliar_extracto(
  p_extracto_id uuid,
  p_asiento_linea_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_extracto public.extracto_bancario%rowtype;
  v_linea public.asiento_lineas%rowtype;
  v_asiento public.asientos%rowtype;
  v_cuenta_bancaria public.cuentas_bancarias%rowtype;
  v_otro_extracto uuid;
begin
  select * into v_extracto
    from public.extracto_bancario
   where id = p_extracto_id
   for update;
  if not found then
    raise exception 'Movimiento de extracto inexistente';
  end if;

  select l.* into v_linea
    from public.asiento_lineas l
    join public.asientos a on a.id = l.asiento_id
   where l.id = p_asiento_linea_id
   for update;
  if not found then
    raise exception 'Línea contable inexistente';
  end if;
  select a.* into v_asiento
    from public.asientos a
   where a.id = v_linea.asiento_id
   for update;
  if v_asiento.estado <> 'confirmado' then
    raise exception 'Solo se pueden conciliar asientos confirmados';
  end if;
  if v_asiento.empresa_id <> v_extracto.empresa_id then
    raise exception 'El extracto y el asiento pertenecen a empresas distintas';
  end if;

  select * into v_cuenta_bancaria
    from public.cuentas_bancarias
   where id = v_extracto.cuenta_bancaria_id;
  if not found or v_cuenta_bancaria.cuenta_contable_id <> v_linea.cuenta_id then
    raise exception 'La línea no pertenece a la cuenta contable bancaria del extracto';
  end if;

  select id into v_otro_extracto
    from public.extracto_bancario
   where asiento_linea_id = p_asiento_linea_id
     and id <> p_extracto_id
   limit 1;
  if v_otro_extracto is not null then
    raise exception 'La línea contable ya está conciliada con otro movimiento';
  end if;

  update public.extracto_bancario
     set conciliado = true,
         asiento_linea_id = p_asiento_linea_id
   where id = p_extracto_id;

  return jsonb_build_object(
    'extracto_id', p_extracto_id,
    'asiento_linea_id', p_asiento_linea_id,
    'conciliado', true
  );
end;
$$;

revoke all on function public.conciliar_extracto(uuid, uuid) from public;
grant execute on function public.conciliar_extracto(uuid, uuid) to authenticated;
