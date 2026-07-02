# Observaciones de la Revisión 0 del SGC — 2026-07-01

Huecos detectados durante la redacción de los PG (Rev 0) entre lo que declara MC-01 y lo
implementado en el ERP. Ninguno bloquea la operación: todos quedaron cubiertos por vía
procedimental en el PG correspondiente. Se listan como candidatos a mejora del módulo
Calidad o a corrección documental en la próxima revisión de MC-01/PG-01.

## Mejoras candidatas del ERP

| # | Tema | Detalle | PG que lo cubre |
|---|------|---------|-----------------|
| 1 | NC mayor/menor | `no_conformidades` no clasifica mayor/menor ni registra aprobación de disposición por Dirección (MC-01 §5 la exige). | PG-09 §6.3.11 |
| 2 | Concesión sin justificación | La justificación de concesión solo se valida en frontend (`saveNC()`); no hay guard en DB. | PG-09 |
| 3 | Notificación al cliente | `fn_nc_cierre_guard` no exige `cliente_notificado` para cerrar NC de origen 'cliente'. | PG-09 §6.4.15 |
| 4 | Estados CAPA | El select permite saltar de 'abierta' a 'cerrada'; único gate duro es la verificación de eficacia. | PG-10 §6.5.15 |
| 5 | Certificado de conformidad no archivado | `generateCertConformidadPDF` genera on-demand y no persiste el PDF emitido (MTRs/calibraciones sí guardan `file_data`). | PG-07 §7 |
| 6 | Tipo 'plano' inexistente | El CHECK de `documentos_controlados.tipo` no incluye 'plano'; se cargan como 'otro'. | PG-15 |
| 7 | `codigo_plano` texto libre | Sin FK a `documentos_controlados`: la OP no garantiza referenciar la revisión vigente del plano. | PG-15 §6.6 |
| 8 | WPS obsoleto con OP abierta | El gate valida vigencia solo al asignar; no re-bloquea referencias existentes si el WPS pasa a 'obsoleto'. | PG-16 §6.3.11 |
| 9 | Selector de documento sin filtro por tipo | En operaciones se puede asociar cualquier documento vigente (p. ej. un formulario a una soldadura). | PG-16 |
| 10 | Conversión de presupuesto 'enviado' | El frontend permite convertir sin estado 'aprobado'; la RPC solo valida no-convertido. | PG-03 |
| 11 | OTD: `fecha_entrega_hasta` | `convertir_presupuesto` copia la validez comercial de la oferta como compromiso de entrega. | PG-03 §6.5.13 |
| 12 | Alta manual de barras | Elude la cuarentena (default 'aceptado' por diseño de mig. 039). | PG-05 §6.1.5 |
| 13 | Independencia de Calidad | Aceptar/rechazar recepciones es PATCH sin restricción de rol en DB (permisos por módulo solo visuales — deuda conocida). | PG-05 §6.3.11 |
| 14 | Alerta de NC ≥30 días | El digest alerta NC abiertas sin umbral de antigüedad; la meta de cierre ≤30 días de MC-01 no tiene aviso. | PG-09 |
| 15 | Semáforo OTD | MC-01 fija meta ≥95% pero el dashboard pinta verde desde ≥90%. | PG-03 |
| 16 | `registro_calidad_id` en NC | Existe en DB pero el modal de NC no permite setearlo. | PG-09 |

## Tareas operativas pendientes

- **Depurar colada histórica**: lo cargado antes de 2026-07-01 en `certificados.colada` /
  `barras.nro_colada` contiene números de OC (etiqueta de UI errónea, ver mig. 045).
  Regularizar a mano contra cada MTR. Hasta entonces la trazabilidad por colada solo es
  confiable para material cargado desde hoy.
- **Regularizar AVL del backfill**: los proveedores existentes quedaron aprobados en bloque
  "por historial de suministro" (mig. 038). Completar la evaluación real en la primera
  reevaluación (PG-04 §6.1.5).

## Correcciones documentales para la próxima revisión

- MC-01 §6.7 vs PG-01 §6.5.6: contradicción sobre dónde viven los WPQ (documentos
  controlados vs planilla física). PG-16 siguió a MC-01; corregir PG-01.
- Unificar títulos de la lista maestra de MC-01 §6.7 con el mapa de procesos §6.3
  (PG-03, PG-05, PG-07, PG-15 tienen títulos distintos en cada lugar).
- Verificar numeración de cláusulas API Q1 citadas (MoC en PG-14 y contingencia en PG-02
  citan ambas §5.11) contra la edición vigente de la norma.
- Definir dónde se proceduraliza la facturación (el mapa la asigna a PG-07 pero es un
  paso administrativo vía microservicio de billing).
