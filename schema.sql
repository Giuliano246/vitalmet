-- ═══════════════════════════════════════════════════════════
-- VitalStock — Schema completo de referencia
-- NO EJECUTAR — esto es solo documentación
-- ═══════════════════════════════════════════════════════════

-- empresas
-- id uuid PK, nombre text, slug text, codigo_invitacion text UNIQUE, created_at timestamptz

-- usuarios  
-- id uuid PK (= auth.uid()), empresa_id uuid, nombre text, email text, rol text, es_admin bool, created_at timestamptz

-- certificados
-- id uuid PK, empresa_id uuid, nro text, proveedor text, material text, colada text, fecha date, metros float8, file_data text, file_name text, created_at timestamptz

-- barras
-- id uuid PK, empresa_id uuid, lote text UNIQUE, material text, perfil text, diametro text, kg_disponibles float8, unidades int, nro_colada text, certificado_id uuid FK, kg_minimo float8, observaciones text, created_at timestamptz

-- ordenes_produccion
-- id uuid PK, empresa_id uuid, nro text, pieza text, descripcion text, cantidad int, precio_unitario float8, lote_pt text, barra_id uuid FK, kg_usados float8, merma_kg float8, operario text, estado text, fecha date, fecha_fin date, horas_total text, codigo_plano text, oc_material text, origen_material text, created_at timestamptz

-- productos_terminados
-- id uuid PK, empresa_id uuid, lote text, pieza text, descripcion text, cantidad int, precio_unitario float8, costo_unitario float8, barra_id uuid FK, orden_id uuid FK, created_at timestamptz

-- ventas (expandida estilo Tango)
-- id uuid PK, empresa_id uuid, nro_remito text, nro_pedido text, cliente text, fecha date, condicion_pago text, estado text, observaciones text,
-- sucursal text, nro_original text, estado_pedido text DEFAULT 'ingresado',
-- coef_registracion numeric, coef_registracion_moneda text DEFAULT 'ARS',
-- coef_emision numeric, coef_emision_moneda text DEFAULT 'ARS',
-- coef_deuda numeric, coef_deuda_moneda text DEFAULT 'ARS',
-- fecha_entrega_desde date, fecha_entrega_hasta date,
-- total numeric, bonif_pct_1 numeric, bonif_pct_2 numeric, contribucion_marginal numeric,
-- lista_precios_id uuid FK, grupo_bonificacion text, vendedor_id uuid FK,
-- limite_credito numeric, saldo_actual_cliente numeric,
-- created_at timestamptz

-- venta_items (expandida)
-- id uuid PK, venta_id uuid FK, producto_id uuid FK, pieza text, cantidad int, precio_unitario float8,
-- tipo_cambio numeric, total numeric,
-- cantidad_bonificada numeric, bonif_1 numeric, bonif_2 numeric, bonif_3 numeric, tot_pct_bonif numeric,
-- created_at timestamptz

-- materiales
-- id uuid PK, empresa_id uuid, nombre text, descripcion text, orden int, activo bool, created_at timestamptz

-- tratamientos
-- id uuid PK, empresa_id uuid, orden_id uuid FK, tipo text, descripcion text, proveedor text, fecha date, certificado_nro text, certificado_file_name text, certificado_file_data text, created_at timestamptz

-- permisos_usuario
-- id uuid PK, empresa_id uuid, usuario_id uuid FK, modulo text, created_at timestamptz

-- clientes
-- id uuid PK, empresa_id uuid, nombre text, contacto text, telefono text, email text, direccion text, cuit text, notas text, limite_credito numeric, saldo_actual numeric, lista_precios_id uuid FK, created_at timestamptz

-- vendedores
-- id uuid PK, empresa_id uuid, codigo text, nombre text, email text, telefono text, comision_pct numeric, activo bool, created_at timestamptz

-- listas_precios
-- id uuid PK, empresa_id uuid, codigo text, nombre text, descripcion text, moneda text DEFAULT 'ARS', activo bool, created_at timestamptz

-- asientos_contables
-- id uuid PK, empresa_id uuid, venta_id uuid FK, cuenta text, debe numeric, haber numeric, descripcion text, fecha date, created_at timestamptz
