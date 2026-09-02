# Manual de usuario — VitalStock ERP (Vitalmet SA)

> Guía práctica para usar el ERP correctamente. Está pensada para que **cualquier persona** —aunque nunca haya tocado el sistema— pueda cargar datos, seguir el circuito completo y no romper nada.

**Acceso:** https://erp.vitalmetsa.com
**Empresa:** Vitalmet SA — Perú 246, Villa Martelli, Buenos Aires
**Versión del manual:** Julio 2026 *(incluye el módulo Calidad — ISO 9001:2015 / API Spec Q1)*

---

## Índice

1. [Antes de empezar: conceptos clave](#1-antes-de-empezar-conceptos-clave)
2. [Ingresar al sistema (login)](#2-ingresar-al-sistema-login)
3. [Cómo moverse: la navegación](#3-cómo-moverse-la-navegación)
4. [El tablero (Métricas)](#4-el-tablero-métricas)
5. [Inventario](#5-inventario)
6. [Producción](#6-producción)
7. [Compras](#7-compras)
8. [Ventas](#8-ventas)
9. [Análisis (costos y trazabilidad)](#9-análisis-costos-y-trazabilidad)
10. [Calidad (NCR/CAPA, documentos, PQP)](#10-calidad-ncrcapa-documentos-pqp)
11. [Contabilidad](#11-contabilidad)
12. [Configuración](#12-configuración)
13. [Los 4 circuitos completos (lo más importante)](#13-los-4-circuitos-completos-lo-más-importante)
14. [Reglas de oro y errores comunes](#14-reglas-de-oro-y-errores-comunes)
15. [Preguntas frecuentes](#15-preguntas-frecuentes)

---

## 1. Antes de empezar: conceptos clave

Leé esto una vez. Te ahorra el 90% de los problemas.

- **Moneda base: dólares (US$).** Casi todo el sistema trabaja en dólares. Las excepciones son la **contabilidad bimonetaria** y los **cheques**, que pueden ir en pesos (ARS) con su tipo de cambio.
- **Cada cosa tiene un "estado".** Presupuestos, ventas, órdenes de compra y asientos pasan por etapas (borrador → enviado → aprobado, etc.). El estado decide qué podés hacer con el documento. **No saltees estados.**
- **Todo lo que mueve plata genera un asiento contable automático.** Cuando facturás una venta, recibís mercadería o registrás un cobro, el sistema arma el asiento solo. No tenés que cargarlo a mano.
- **Trazabilidad de punta a punta.** Cada producto terminado se puede rastrear hacia atrás hasta la barra de acero, su **colada** (heat number) y su certificado MTC. Por eso es importante vincular bien las cosas al cargarlas.
- **El sistema tiene "candados" de calidad.** El material que llega queda **en cuarentena** hasta que se inspecciona; una orden de producción con un **hold point** sin firmar no se puede cerrar; una no conformidad no se cierra sin disposición. Si el sistema te rechaza un cambio de estado con un cartel rojo, **no es un error del sistema: es una regla de calidad**. Leé el mensaje, que te dice qué falta.
- **La evidencia de calidad no se borra.** No conformidades, acciones CAPA, documentos controlados, ensayos y calibraciones se retienen 10 años (requisito API Q1). Si algo quedó mal cargado, corregilo o cerralo con una nota; solo el administrador puede eliminarlo por excepción.
- **Guardá una cosa a la vez y esperá la confirmación.** Cuando apretás un botón de guardar, esperá el cartelito verde de confirmación antes de seguir.
- **Si algo no carga, vas a ver un cartel rojo arriba con un botón "Reintentar".** Apretalo. No recargues la página a lo loco.

---

## 2. Ingresar al sistema (login)

Al abrir https://erp.vitalmetsa.com vas a ver tres opciones:

| Opción | Para qué sirve | Quién la usa |
|--------|----------------|--------------|
| **Iniciar sesión** | Entrar con tu email y contraseña | Todos, todos los días |
| **Unirse a empresa** | Sumarte a Vitalmet con un **código de empresa** | Empleado nuevo |
| **Nueva empresa** | Crear una empresa nueva desde cero | (no usar — ya existe Vitalmet) |

### Si ya tenés cuenta
1. Tocá **Iniciar sesión**.
2. Escribí tu **email** y **contraseña**.
3. Entrá. El sistema carga todos los datos (puede tardar unos segundos la primera vez).

### Si sos nuevo
1. Pedile al administrador (Giuliano) el **código de empresa**.
2. Tocá **Unirse a empresa**.
3. Pegá el código, poné tu **nombre**, **email** y una **contraseña**.
4. Listo: ya quedás asociado a Vitalmet y el admin te habilita los módulos que vas a usar.

> **Salir:** el botón para cerrar sesión está abajo a la izquierda, en el pie del menú lateral.

---

## 3. Cómo moverse: la navegación

A la izquierda tenés el **menú lateral** con 9 grandes grupos. Al entrar a un grupo, arriba aparecen **pestañas** con sus secciones.

| Grupo | Qué contiene |
|-------|--------------|
| **Métricas** | Tablero de inicio con indicadores y alertas del día |
| **Inventario** | Materia prima, Productos terminados, Certificados MTC, Insumos, Herramientas |
| **Producción** | Órdenes de producción (con captura de tiempos, PQP y ensayos) |
| **Compras** | Órdenes de compra, **Inspección de entrada**, Proveedores (con AVL), Facturas recibidas |
| **Ventas** | Presupuestos, Ventas, Clientes, Cuenta corriente |
| **Análisis** | Costos y rentabilidad, Trazabilidad |
| **Calidad** | NCR / CAPA, Documentos controlados, Plantillas PQP |
| **Contabilidad** | Plan de cuentas, asientos, cobros/pagos, cheques, libros, balances, ajuste por inflación, cierre… |
| **Configuración** | Materiales, Usuarios y permisos, Imputación contable |

**En el celular:** el menú se esconde. Tocá el botón ☰ (hamburguesa) arriba para abrirlo.

**Tema claro/oscuro:** botón ☀ en el pie del menú.

> Si **no ves** un grupo o una sección, es porque tu usuario no tiene ese módulo habilitado. Pedíselo al administrador.

---

## 4. El tablero (Métricas)

Es la pantalla de inicio. Te muestra de un vistazo:

- **Indicadores operativos** en tiempo real (stock, ventas, etc.).
- **Panel "Para hoy":** un resumen de lo que requiere atención **hoy**:
  - Entregas atrasadas o comprometidas en los próximos 3 días.
  - Cobranzas vencidas.
  - Materiales bajo punto de reorden e insumos bajo stock mínimo.
  - Presupuestos sin respuesta o por vencer.
  - Cheques por depositar, cubrir o rechazados.
  - **Calidad:** instrumentos con calibración vencida (bloqueados) o por vencer en 30 días, recepciones **en cuarentena** esperando inspección, **no conformidades abiertas** (crítico si llevan más de 30 días), **acciones CAPA vencidas** y proveedores con **reevaluación AVL vencida**.

> Cuando hay pendientes, aparece un **globito de alerta** sobre "Métricas" en el menú (rojo si hay algo crítico). Revisalo todas las mañanas. Cada alerta tiene un botón **Ver** que te lleva directo a la pantalla donde se resuelve.

Al final del tablero hay dos paneles de gestión:

- **Facturación mensual (12 meses):** gráfico de barras con los pedidos registrados por mes en USD, más la comparativa **este mes vs el anterior** con su variación %.
- **Cash-flow proyectado:** cuánto entra y cuánto sale en las ventanas **vencido / 30 / 60 / 90 días**, y la **posición neta a 90 días**. Entradas: cuenta corriente pendiente por vencimiento + cheques en cartera. Salidas: facturas de proveedor por vencimiento + cheques emitidos. Es la respuesta a "¿me alcanza la plata?" antes de que duela.

---

## 5. Inventario

El grupo **Inventario** tiene 5 secciones. Esta es la base de todo: si el inventario está bien cargado, lo demás funciona.

### 5.1 Materia prima (barras de acero)

Stock de barras de acero que se consumen en producción.

**Para cargar una barra:**
1. Tocá **+ Nueva barra**.
2. Completá:
   - **Lote interno** (ej.: `BAR-2024-001`) *
   - **Material** (elegí de la lista) *
   - **Perfil** (redonda, hexagonal, cuadrada, caño, planchuela)
   - **Diámetro / Medida** (ej.: `Ø50mm`)
   - **Metros disponibles** *
   - **Cantidad de barras**
   - **Nº de OC** (orden de compra de origen) *
   - **Colada (heat nº)** * — el número de colada **que figura en el MTR** (ej.: `84512`). ⚠️ No es el número de OC ni el de remito: es el que identifica la fusión del acero y permite la trazabilidad exigida por API Q1.
   - **Metros mínimo** (umbral para que salte la alerta de reposición)
   - **Certificado MTC vinculado** (elegí el certificado de calidad de esa barra)
   - **Observaciones**
3. Guardá.

> **Importante:** vinculá siempre el **certificado MTC**, la **OC** y la **colada**. Eso es lo que permite la trazabilidad y los reclamos de calidad.

> **Valuación:** las barras que entran por recepción de OC **nacen valuadas** con el precio del ítem de la OC (convertido a USD si la OC era en pesos). Con eso el stock de MP tiene valor contable real: lo ves en la tarjeta **Valor stock (costo)** y en el exportable **Valuación de inventario** (por lote y con promedio ponderado por material).

**Estado de calidad de la barra:** en la tabla, además del stock, vas a ver un badge:
- **CUARENTENA** (ámbar): la barra llegó por una recepción de OC y **todavía no pasó la inspección de entrada**. No se puede consumir en producción hasta que Calidad la acepte (Compras → Inspección de entrada).
- **RECHAZADO** (rojo): la inspección la rechazó. Queda bloqueada; correspondería devolución al proveedor y su no conformidad.
- Sin badge: aceptada, usable.

> **Carga manual:** una barra cargada a mano con **+ Nueva barra** nace **aceptada** (no pasa por cuarentena). Usá la carga manual solo para regularizar stock histórico; el material nuevo tiene que entrar por el circuito de compras (OC → Recibir → Inspección).

**Buscar:** por tipo, OC o lote. Las barras por debajo del mínimo aparecen marcadas.

**Reposición sugerida:** abajo de la tabla, el sistema calcula por material el **punto de reorden** (consumo promedio durante el lead time + safety stock) y cuánto conviene pedir:

- La columna **En tránsito** muestra lo que ya está pedido en OC enviadas/confirmadas y todavía no se recibió — el "A pedir" **ya lo descuenta**, así no pedís dos veces lo mismo.
- El botón **Generar OC** arma una orden de compra borrador pre-cargada con la sugerencia: cantidad a pedir, y el **proveedor, precio y medida de la última compra** de ese material. Revisá proveedor y precio, y guardá — es una OC normal desde ahí en adelante.

**Kardex (historial de movimientos):** cada barra, producto terminado e insumo tiene un botón **Kardex** que muestra todos sus movimientos de stock: qué entró, qué salió, cuándo, cuánto quedó y quién lo hizo. Los movimientos se etiquetan solos (Consumo OP, Venta, Entrega, Ajuste, Conteo físico, etc.). Nada se mueve sin dejar rastro.

**Ajustes de stock:** si al editar una barra / PT / insumo cambiás la **cantidad**, el sistema te pide un **motivo obligatorio**. El ajuste queda en el kardex y, si el ítem tiene costo, genera automáticamente el **asiento contable** (cuenta de stock contra AJUSTES DE INVENTARIO). Corregir stock ya no es "pisar el número": queda documentado como en cualquier ERP serio.

**Conteo físico:** el botón **Conteo físico** (arriba de la tabla de barras) inicia un inventario: el sistema saca una foto del stock (barras, PT e insumos) y te da una planilla para cargar lo que contaste físicamente. Podés cargarla en varias sesiones — se guarda sola. Al **cerrar el conteo**, cada diferencia genera su ajuste documentado con asiento. Recomendado: un conteo por trimestre, o cíclico por familia de material.

### 5.2 Productos terminados (PT)

Stock de piezas listas para vender.

**Para cargar un PT a mano:**
1. **+ Nuevo PT**.
2. Completá **Lote PT** (`PT-2024-001`) *, **Pieza** (ej.: "Válvula esclusa") *, **Descripción** (ej.: "DN50 PN16 AISI 316"), **Cantidad** *, **Costo unitario US$**.
3. Si la pieza salió de una barra, vinculá la **Barra origen** (así se mantiene la trazabilidad y el PT hereda la **colada**, que se ve en su propia columna).
4. Guardá.

**Para cargar muchos PT de golpe:**
1. **Importar Excel**.
2. Descargá la plantilla, completala (mínimo: Lote, Pieza, Cantidad) y subila (`.xlsx` o `.csv`).

> Normalmente los PT se generan **solos** al completar una orden de producción (ver [Producción](#6-producción)). La carga manual es para casos puntuales.

### 5.3 Certificados MTC

Los certificados de calidad (Mill Test Certificate / MTR) de cada material.

**Para cargar uno:**
1. **+ Nuevo certificado**.
2. Completá **Nº cert.** *, **Proveedor** *, **Material** *, **Colada (heat nº)** * — la del MTR —, **Nº OC**, **Metros certificados**, **Fecha**.
3. Subí el **PDF** del certificado.
4. Asociá las **barras** que cubre.
5. Guardá.

> El PDF queda guardado en el sistema; se descarga cuando lo abrís.
> **El MTR no es opcional para el acero:** la inspección de entrada **no permite aceptar materia prima sin certificado vinculado** (ver [7.3](#73-inspección-de-entrada-cuarentena)).

### 5.4 Insumos

Consumibles: lubricantes, soldadura, limpieza, etc.

**Para cargar:** **+ Nuevo insumo** → **Código** *, **Nombre** *, **Categoría**, **Stock** *, **Unidad**, **Mínimo stock**, **Último precio**, **Proveedor**. Guardá.

### 5.5 Herramientas e instrumentos de medición

Insertos, mechas, hojas… y también los **instrumentos de medición** (calibres, manómetros, micrómetros) con su control de calibración.

**Para cargar:** **+ Nueva herramienta** → **Código** *, **Nombre** *, **Cantidad** *, **Estado** (nueva / en uso / mantenimiento / dada de baja), **Ubicación**, **Precio compra**, **Fecha compra**, **Proveedor**.

**Metrología (ISO 7.1.5 / API Q1 4.4.4):** si es un instrumento de medición, en el mismo modal completá:
- **Requiere calibración:** Sí — instrumento de medición.
- **Frecuencia (meses):** cada cuánto se calibra (ej.: 12).
- **Patrón / referencia:** contra qué se calibra.

**Registrar una calibración:** sobre el instrumento, tocá **Calibrar** y cargá **fecha**, **resultado** (conforme / no conforme), **Nº de certificado**, **laboratorio** y el **PDF del certificado**. El sistema calcula solo el próximo vencimiento según la frecuencia y guarda el historial.

**Qué significa cada badge en la tabla:**
- **SIN CALIBRAR** / **VENCIDA** (rojo): el instrumento está **bloqueado** — no se puede usar en ensayos ni inspecciones hasta calibrarlo.
- **VENCE** (ámbar): vence dentro de 30 días. Programá la calibración.
- **OK hasta…** (verde): al día.

> Un resultado de calibración **no conforme** también bloquea el instrumento. Los vencimientos aparecen en el panel "Para hoy".

---

## 6. Producción

### Órdenes de producción (OP)

Una OP convierte **materia prima en producto terminado**. Registra qué barra se consumió, cuánto tiempo llevó y qué pieza salió.

**Para crear una OP:**
1. **+ Nueva orden**.
2. Cabecera:
   - **Nº Orden de Trabajo** (ej.: `OT-2024-001`) *
   - **Fecha inicio** y **Fecha finalización**
   - **Tiempo total (horas)** — texto libre, ej.: "8hs torno + 2hs fresadora"
   - **Descripción pieza** (ej.: "Unión doble FIG 1502") *
   - **Código / Plano** (ej.: `PLN-001`)
3. Material y cantidades:
   - Origen del material: **Barra / Fundición / Forja**
   - **Barra consumida** (elegí de la lista) *
   - **Metros consumidos** *
   - **Merma / scrap (mts)** — lo que se desperdició
   - **Cantidad total** de piezas *
   - **Costo unitario US$**
4. **Estado**: `en-proceso` → cuando termina, pasalo a `completada` (o `suspendida` si se frena).
5. **Máquina / Operario**.
6. Guardá.

> ⚠️ **La barra tiene que estar aceptada.** Si elegís una barra en **cuarentena** o **rechazada**, el sistema no deja consumirla: primero tiene que pasar la inspección de entrada (Compras → Inspección).

**Qué pasa al completar la OP:**
- Se **descuenta** la materia prima consumida.
- Se **genera el producto terminado** (PT) con su lote.
- Queda armada la cadena de trazabilidad: certificado → colada → barra → OP → PT.
- Se **congela el costo real** de la orden (material consumido + horas productivas de los timers × tarifas + overhead) y el lote de PT queda **valuado a ese costo** — el margen que ves en Análisis → Costos deja de ser una foto recalculable.

**Si eliminás una OP:** los metros consumidos **vuelven a la barra** automáticamente. Y si la OP ya generó PT, tiene registros de calidad, no conformidades, tratamientos o puntos de control firmados, **no se puede eliminar** (retención de evidencia del SGC) — corregila o suspendela en vez de borrarla.

### Planos

La pestaña **Planos** (dentro de Producción) guarda el PDF o la imagen de cada plano, con su código, revisión y cliente:

- Cargalo con **+ Nuevo plano** usando **el mismo código** que escribís en el campo "Código de plano" de la OP — ese texto es el vínculo.
- En la tabla de OPs, el código de plano se vuelve **clickeable** cuando el plano está cargado: un click y lo ves.
- **En Modo Planta**: cuando el operario escanea el QR de la OP en el celular, aparece el botón **📐 VER PLANO** — el plano de la pieza en la mano, sin ir a buscar la carpeta.
- El tablero de Planos te avisa qué códigos usados en OPs **todavía no tienen plano cargado**.
- Cada cambio de archivo o revisión queda auditado (es un documento controlado).

### 6.1 Pasos de producción, tiempos y puntos de control (PQP)

El botón **Tiempos** de cada OP abre la **captura de tiempos por pasos**: la OP se divide en operaciones (torneado, roscado, control…) y se cronometra cada una.

**Agregar pasos:** con el botón **+ Paso** cargás descripción, máquina, tiempo estimado, tarifa y —lo nuevo—:
- **Punto de control (PQP):**
  - **Normal:** paso común.
  - **Hold point** (badge ámbar **HOLD**): la producción **se frena ahí**. No se puede avanzar al paso siguiente ni completar la OP hasta que Calidad lo libere con **Firmar QC**.
  - **Witness point** (badge azul **WITNESS**): requiere firma de calidad para darse por completado (presenciado), pero no frena los pasos siguientes.
- **Documento (WPS / instructivo):** vinculá el documento controlado que rige el paso (ej.: un WPS para soldadura). Solo se pueden vincular documentos **vigentes** — si la revisión quedó obsoleta, el sistema lo rechaza.

**Firmar un punto:** el botón **Firmar QC** libera el hold/witness point. La firma queda registrada **a tu nombre, con fecha y hora** (es la evidencia del signoff, no se puede deshacer).

**Aplicar un PQP:** en lugar de cargar los pasos a mano, el botón **PQP** instancia una **plantilla PQP** completa (el routing modelo del producto con sus hold/witness points y documentos — ver [10.4](#104-plantillas-pqp)). Solo funciona si la OP todavía no tiene pasos cargados.

**Gate de cierre:** una OP **no se puede pasar a `completada`** si tiene puntos hold/witness sin firmar. El select de estado va a volver solo a su valor anterior y vas a ver el mensaje indicando qué operación falta liberar.

### 6.2 Ensayos e inspecciones (registros de calidad)

Desde la misma pantalla de la OP, el botón **Ensayo** registra un **registro de calidad**:

- **Tipo de ensayo:** hidrostático, dimensional, visual, dureza, líquidos penetrantes, partículas magnéticas u otro.
- **Instrumento:** elegí el instrumento usado. Los que tienen la **calibración vencida aparecen con ⛔ y no se pueden usar** (bloqueo de metrología).
- **Resultado:** conforme / no conforme.
- Para el hidrostático: **presión (psi)**, **sostenimiento (min)** y **temperatura (°C)**.
- **Valores medidos / detalle**, **adjunto PDF** (reporte del ensayo) y observaciones.

> Si el resultado es **no conforme**, el sistema te lo recuerda: registrá la **No Conformidad** en Calidad → NCR y vinculá el ensayo (el modal de NC tiene el campo "Ensayo vinculado").

---

## 7. Compras

El grupo **Compras** tiene 4 pestañas: **Órdenes de compra**, **Inspección de entrada**, **Proveedores** y **Facturas recibidas**.

> El circuito de compras funciona con **triple coincidencia (3-way match)**: Orden de compra → Recepción de mercadería → Factura del proveedor. El sistema controla que las tres cosas coincidan antes de dar por buena la deuda. Y para el material, se suma la **inspección de entrada**: nada se usa en producción sin aceptarse primero.

### 7.1 Proveedores y AVL (lista de proveedores aprobados)

Cargalos primero, así después podés elegirlos en la OC.

**Para cargar:** **+ Nuevo proveedor** → **Razón social** *, **CUIT**, **Contacto**, **Teléfono**, **Email**, **Condición de pago** (ej.: "30 días FF"), **Dirección**, **Observaciones**.

**Sección "Calidad — AVL" del mismo modal** (API Q1 5.6):
- **Criticidad:** `Crítico` si provee material o servicios que afectan la calidad del producto O&G (acero, tratamientos térmicos, ensayos); `No crítico` para el resto (librería, limpieza…).
- **Estado AVL:** Aprobado / No aprobado.
- **Alcance de la aprobación** (qué está aprobado a proveer), **fecha de evaluación** y **fecha de próxima reevaluación**.

En la tabla ves la columna **AVL** (estado + badge "Crítico"), cuántas OCs tiene y la **deuda en USD**.

> 🔒 **Gate AVL:** el sistema **rechaza la OC** a un proveedor **crítico no aprobado**, o cuya **reevaluación está vencida**. El mensaje te dice qué hacer: evaluálo y aprobalo en Proveedores antes de emitir la OC. Los proveedores con reevaluación vencida también aparecen en el panel "Para hoy".

### 7.2 Órdenes de compra (OC)

**Para crear una OC:**
1. **+ Nueva OC**.
2. Cabecera:
   - **Nº OC** (ej.: `OC-0001`) *
   - **Proveedor** *
   - **Fecha** * y **Entrega esperada**
   - **Estado** (empieza en `borrador`)
   - **Condición de pago**, **Observaciones**
3. **Moneda y tipo de cambio:**
   - **Moneda** (ARS / USD) *
   - **Cotización**: Vendedor o Comprador
   - **TC ARS/USD** *
4. **Ítems:** agregá cada renglón (descripción, cantidad, precio unitario; el subtotal se calcula solo).
5. **(Opcional)** Nº de **remito** y **certificado MTC** (podés crear el certificado en el momento con **+ Nuevo cert**).
6. Guardá.

**Ciclo de vida de la OC (estados):**

```
borrador → enviada → confirmada → recibida_parcial → recibida → facturada
                                                                    └→ anulada
```

**Recibir mercadería:**
1. Sobre la OC, tocá **Recibir**.
2. Registrá lo que llegó de cada ítem.
3. Esto genera automáticamente el asiento de **GR/IR** ("mercadería recibida, factura por llegar").
4. **Si el ítem es acero (materia prima), la barra se crea en stock EN CUARENTENA:** queda usable recién cuando la inspección de entrada la acepta (pestaña siguiente).

**Registrar la factura del proveedor:**
1. Tocá **Factura** sobre la OC (o cargala desde "Facturas recibidas").
2. Completá **Nº factura** (ej.: `A-0001-00012345`), **Fecha de emisión** (la impresa en el comprobante), **Fecha contable**, **Vencimiento**, **Moneda**, **Neto**, **IVA** (el **Total** se calcula solo).
3. El sistema **concilia** la factura contra la recepción (3-way match) y arma el asiento que cancela el GR/IR.

> **Las dos fechas:** la **de emisión** es la del papel; la **contable** (viene propuesta con la fecha de hoy) es cuándo impacta en los libros — el asiento, el libro IVA Compras y la posición IVA van por la contable. Ejemplo típico: factura emitida en junio que te llega en agosto → emisión junio, contable agosto.

> **El orden importa: primero Recibir, después Factura.** El match compara la factura contra lo que **recepcionaste en el sistema**. Si la OC no tiene recepciones cargadas, el panel avisa **SIN RECEPCIONES**: registrá la recepción con **Recibir** y volvé... **o usá el atajo**: si el material llegó junto con la factura, tildá **"Recibí todo el material con esta factura"** en el mismo modal — el sistema registra la recepción completa de la OC (stock, kardex y asiento GR/IR) y recién después la factura, con el match cerrando solo. Un administrador puede registrar igual justificando el override (para material que entró antes de usar el sistema).

> **¿Te equivocaste en algo?** En la tabla de Facturas recibidas cada comprobante tiene **Corregir** (lo anula y te reabre el formulario precargado para que cambies lo que estaba mal y lo registres de nuevo) y **Anular** (pide motivo y lo elimina; el asiento contable queda en estado *anulado* — nunca se borra — y el motivo va al registro de auditoría). Si la factura tiene una NC/ND asociada, primero anulá la NC/ND. Las recepciones de la OC no se tocan al anular: el material entró igual.

> **Proveedor nuevo sin cargar:** tanto el modal de **nueva OC** como el de **factura sin OC** tienen el botón **+ CUIT** al lado del selector de proveedor: alta rápida de proveedor ocasional con CUIT validado, sin salir del formulario.

> **Monedas distintas:** si la OC está en USD y la factura en ARS (o al revés), el sistema convierte lo recibido a la moneda de la factura con el **tipo de cambio de la factura** (o el de la OC si no cargaste uno) y te lo muestra en el panel. Sin tipo de cambio no hay comparación posible y no deja registrar.

> Cuando la OC tiene recepción **y** factura, su estado pasa a `facturada`.

> **Protecciones:** una OC **con mercadería recibida no se puede eliminar** (para darla de baja, pasala a `anulada`) y al editarla **solo se actualiza la cabecera** — los ítems quedan como están, para no romper la trazabilidad de recepciones e inspecciones. Además, **el mismo comprobante del mismo proveedor no se puede registrar dos veces** (el sistema lo rechaza con aviso).

### 7.3 Inspección de entrada (cuarentena)

Acá vive el control de recepción (ISO 8.4 / API Q1 5.7.1.4): **toda recepción de OC aparece en esta tabla**, y la materia prima queda **en cuarentena** hasta que alguien de Calidad la libere.

**Cómo se trabaja:**
1. Las recepciones **en cuarentena aparecen primero** (badge ámbar). El contador de arriba te dice cuántas hay; también salta en el panel "Para hoy".
2. Verificá el material contra el remito y el **MTR** (columna con el certificado — tocalo para abrir el PDF).
3. **✓ Aceptar:** la barra vinculada se libera para producción.
4. **✕ Rechazar:** la barra queda **bloqueada** (badge RECHAZADO). Registrá después la **No Conformidad** en Calidad → NCR con origen "Recepción" y gestioná la devolución al proveedor.

> 🔒 **MTR obligatorio:** el sistema **no permite aceptar materia prima sin certificado de material (MTR) vinculado**. Si la fila dice **SIN MTR**, cargá primero el certificado en Inventario → Certificados MTC y vinculalo a la recepción o a la OC.

### 7.4 Facturas recibidas

Lista de todos los comprobantes de proveedores: facturas contra OC, facturas sin OC (gastos), y notas de crédito/débito. Acá ves la columna **Tipo** (FA/NC/ND + letra), **Match** (si coincide con su recepción) y el **Asiento** generado.

#### Comprobantes de proveedor: IVA, percepciones y notas de crédito

Al registrar una factura elegís **tipo** (Factura / Nota de débito / Nota de crédito) y **letra** (A/B/C/M/X). La letra se sugiere sola según la condición fiscal del proveedor (Resp. Inscripto → A, Monotributo → C).

- **IVA por alícuota**: cargá una fila por alícuota (10,5% / 21% / 27%...). El IVA se calcula solo desde la base; podés corregirlo por redondeos del proveedor. Las facturas B y C no discriminan IVA (no es crédito computable).
- **No gravado / Exento**: campos aparte, salen en el Libro IVA.
- **Percepciones**: IVA, IIBB (con jurisdicción) y Ganancias. Se contabilizan como crédito en sus cuentas (113007 / 113010 / 113011).
- **El total tiene que cerrar**: el sistema no deja guardar si la suma de componentes no coincide con el total del comprobante.
- **Factura sin OC** (botón en el tab Facturas): para gastos sin orden de compra (luz, fletes, contador) — elegís la cuenta contable de imputación.
- **NC/ND**: desde la fila de cualquier factura. La NC reduce la deuda con el proveedor y el crédito de IVA, y sale en negativo en el libro. No mueve stock: si hubo devolución física, el ajuste de inventario va por el circuito de inspección/rechazo.

El exportable **IVA compras** (Contabilidad → Exportables) sale en formato libro real: una columna por alícuota, no gravado, exento, percepciones por tipo con jurisdicción de IIBB, y las NC en negativo.

---

## 8. Ventas

El grupo **Ventas** tiene 4 pestañas: **Presupuestos**, **Ventas**, **Clientes** y **Cuenta corriente**. El circuito natural es:

```
Presupuesto → (aprobado) → Venta → (entregado) → Facturar (AFIP) → Cobro
```

### 8.1 Clientes

**Para cargar:** **+ Nuevo cliente** → **Razón social** *, **CUIT**, **Condición fiscal**, **Límite de crédito**, **Contacto**, **Teléfono**, **Email**, **Dirección**, **Notas**. Guardá.

- El **CUIT se valida** (dígito verificador): si está mal tipeado, no deja guardar.
- La **condición fiscal** (Responsable Inscripto, Monotributista, Exento, Consumidor final) define **qué letra de factura recibe** el cliente al facturarle (A o B). Cargala antes de facturar: si el cliente tiene CUIT y no tiene condición definida, el botón Facturar te la va a pedir.
- El **límite de crédito** (USD, vacío = sin límite) arma un **semáforo al vender**: si al registrar un pedido o convertir un presupuesto el cliente queda expuesto por encima del límite, o **tiene saldo vencido** en cuenta corriente, el sistema te lo avisa y te pide confirmación. No bloquea — la decisión final es tuya — pero no vendés a ciegas.
- Si un cliente con historial pasa **90 días sin comprar**, salta una alerta en el tablero ("momento de llamar"); a los **180 días** se marca como dormido. Además, el generador de recordatorios le encola un **mail de reactivación** (con tu aprobación previa, máximo uno cada 60 días).

- **Importar Excel:** para cargar muchos de una. Detecta duplicados por CUIT (o por nombre).
- **Ficha del cliente:** tocá el nombre para ver su historial completo (presupuestos, ventas, facturas, pagos).
- **Exportar:** botón **Excel**.

### 8.2 Presupuestos

**Para crear un presupuesto:**
1. **+ Nuevo presupuesto**.
2. Cabecera: **Nº** (ej.: `P-0001`) *, **Cliente** * (se autocompleta el CUIT), **Fecha** *, **Vence**, **Condición de pago**, **Estado** (empieza en `borrador`).
3. **Ítems:** agregá renglones con descripción, cantidad, precio unitario y descuento.
4. Mirá el **costeo automático**: el sistema te muestra costo de material, tiempo, overhead, costo total y el **margen** estimado (USD y %). Sirve para no vender por debajo del costo.
5. **Descuento %** general y **Observaciones** (validez, condiciones).
6. Guardá.

**Ciclo de vida:**

```
borrador → enviado → aprobado → (se convierte en Venta)
                  └→ rechazado / vencido
```

**Acciones:**
- **PDF:** genera el presupuesto en PDF para mandarle al cliente.
- **Venta:** aparece cuando el estado es `aprobado`. Lo convierte en una venta (pedido).
- **Excel:** exporta el listado.

### 8.3 Ventas (pedidos y remitos)

Una venta puede nacer de **convertir un presupuesto** o cargarse a mano con **+ Registro de venta**.

**Datos principales:**
- **Nº pedido** *, **Razón social** * (autocompleta CUIT), **Estado**, **Fecha** *.
- **Fechas de entrega** (desde / hasta) — la fecha "hasta" es el **compromiso con el cliente** y alimenta el indicador OTD.
- **Condiciones comerciales:** lista de precios, condición de pago (Contado, 15/30/60/90 días, etc.), vendedor, % bonificación.
- **Ítems:** pieza, descripción, cantidad, precio, descuento.

**Ciclo de vida:**

```
pendiente entrega → entregado → facturado
```

**OTD (On-Time Delivery):** en las estadísticas de Ventas hay un semáforo de **entregas a tiempo** (entregado en fecha ÷ entregas con fecha comprometida): **verde ≥95%**, ámbar ≥85%, rojo por debajo — la meta del SGC es 95%. Cada venta atrasada se marca en la tabla: **ATRASADO** (pendiente y ya pasó la fecha) o **ENTREGA TARDÍA** (se entregó después de lo prometido).

**Acciones sobre cada venta:**
- **Remito** 🚚 — genera el remito (PDF) para despachar.
- **Certificado** ✔ — genera el certificado de conformidad (PDF), con los MTC que respaldan el material.
- **Facturar** ⚡ (botón verde) — **emite la factura electrónica en AFIP**. Llama al servicio de facturación, obtiene el **CAE** (Código de Autorización Electrónica) y devuelve la factura en PDF. La venta pasa a `facturado` y se genera el asiento de venta automáticamente.
  - La **letra sale sola** de la condición fiscal del cliente: RI y monotributistas reciben **Factura A**, exentos y consumidor final reciben **B**. Factura A exige el CUIT del cliente.
  - La venta está en USD y **se factura en pesos al tipo de cambio vendedor BNA del día** (el TC usado se muestra al emitir).
  - El **punto de venta** se configura en Configuración → Imputación contable.
- **CAE** — una vez facturada, este botón te deja ver/descargar la factura.
- **Anular** — da de baja la venta (queda registro de auditoría).
- **Excel** — exporta el listado.

Al pasar una venta a **entregado**, el sistema encola un mail de **"pedido despachado"** para el cliente (si tiene email cargado) — lo aprobás en Ventas → Mailings antes de que salga. Lo mismo con **"pedido confirmado"** al convertir un presupuesto.

> **Ojo:** una vez que la venta tiene **CAE**, no se puede editar (lo bloquea el sistema). Revisá bien **antes** de facturar.

### 8.4 Cuenta corriente

Muestra cuánto te debe cada cliente y desde hace cuánto.

- **Cargos:** ventas facturadas o entregadas (los pedidos pendientes de entrega **no** cuentan).
- **Cobrado:** lo que se registró en "Cobros y Pagos".
- **Saldo** y **aging** (antigüedad): columnas **Al día**, **1-30**, **31-60**, **61-90**, **+90 días**.
- La imputación es **FIFO**: los cobros se aplican primero a las facturas más viejas.

Tocá un cliente para ver el detalle por factura. Exportás con **Excel**.

### 8.5 Mailings (recordatorios y avisos automáticos)

El ERP genera mails solos, pero **nada sale sin tu aprobación**: todo pasa por la cola de **Ventas → Mailings**.

**Qué se genera automáticamente (una vez por día, al abrir el ERP):**
- **Recordatorio de cobranza** — clientes con saldo vencido en cuenta corriente (con detalle de comprobantes y días de atraso).
- **Seguimiento de presupuesto** — presupuestos enviados hace 7+ días sin respuesta.
- **Reactivación** — clientes con historial que llevan 90+ días sin comprar (máximo un mail cada 60 días; si además deben plata, primero va la cobranza).

**Qué se genera por evento:**
- **Pedido confirmado** — al convertir un presupuesto en venta.
- **Pedido despachado** — al pasar una venta a `entregado`.

**Cómo funciona la cola:** cada mail queda **PENDIENTE** hasta que lo apruebes (podés editarlo antes con **Ver / Editar**, o cancelarlo). Los aprobados **salen solos**: un proceso del servidor los despacha **cada 15 minutos en horario laboral** (configurable), aunque nadie tenga el ERP abierto. Lo enviado queda en el **historial**.

Los textos salen de **plantillas editables** (pestaña Templates) con variables como `{cliente}`, `{monto}`, `{nro}`.

> **Requisito para el envío real:** la casilla de Office 365 tiene que estar conectada (integración con Microsoft, se configura una sola vez). Hasta entonces los mails aprobados quedan esperando en la cola, no se pierden.

---

## 9. Análisis (costos y trazabilidad)

### 9.1 Costos y rentabilidad

Calcula el costo real de cada pieza y su margen.

1. Configurá una vez: **Tarifa operario (USD/h)** y **Overhead %** (gastos indirectos: luz, alquiler…). Tocá **Guardar config**.
2. Tocá **↻ Recalcular**.
3. La tabla muestra, por pieza: costo de material, costo de tiempo, overhead, costo total, precio de venta promedio y **margen** (USD y %).

### 9.2 Trazabilidad

Dos buscadores:
- **Por pieza / lote PT:** te muestra el origen (PT ← OP ← barra ← colada ← certificado).
- **Por certificado / OC:** te muestra hacia adelante (certificado → barra → OP → PT → venta).

Sirve para reclamos de calidad y auditorías: con un número rastreás toda la cadena. La **colada** aparece en las columnas de Materia prima y Productos terminados, así que un reclamo por colada se resuelve buscando el certificado que la ampara.

> ⚠️ **Dato histórico:** el material cargado **antes de julio 2026** puede tener el número de OC en el campo colada (era la etiqueta vieja de la pantalla). La trazabilidad por colada es confiable para el material cargado desde julio 2026 en adelante.

---

## 10. Calidad (NCR/CAPA, documentos, PQP)

El grupo **Calidad** es el corazón del sistema de gestión (ISO 9001:2015 / API Spec Q1). Tiene 3 pestañas: **NCR / CAPA**, **Documentos** y **Plantillas PQP**. Además, como viste, el módulo "se mete" en todo el resto: cuarentena en Compras, hold points en Producción, calibración en Herramientas, AVL en Proveedores.

> Los procedimientos escritos del SGC (manual MC-01 y procedimientos PG-01 a PG-16) se cargan como **documentos controlados** en la pestaña Documentos: esa es la **lista maestra oficial**.

### 10.1 No conformidades (NC)

Una NC registra **cualquier incumplimiento**: material rechazado en recepción, un ensayo no conforme, un reclamo de cliente, un hallazgo de auditoría.

**Para registrar una:** Calidad → **+ Nueva NC**:
- **Fecha** y **Origen**: Recepción (proveedor) / Producción / Reclamo de cliente / Proveedor / Auditoría / Otro.
- **Vínculos** (usalos siempre que existan): **OP**, **recepción**, **venta** y/o **ensayo vinculado** (el registro de calidad que la detectó). Es lo que después permite trazar el problema.
- **Descripción** *: qué se detectó, contra qué requisito, cantidad afectada.
- **Disposición**: qué se hace con el producto no conforme — **Retrabajo**, **Reproceso**, **Rechazo/scrap**, **Concesión** (uso como está) o **Devolución a proveedor**.
- **Justificación de la disposición** — **obligatoria si la disposición es concesión** (el sistema no deja guardar una concesión sin justificar).
- **¿Cliente notificado?** — `N/A` si el producto no llegó al cliente; si es un reclamo o el producto ya se entregó, marcá `Sí` cuando lo hayas notificado.

**Numeración:** la pone el sistema, correlativa (`NC-0001`, `NC-0002`…). No se elige ni se repite.

**Estados:** `abierta → en tratamiento → cerrada`. Los candados para **cerrar** una NC:
- 🔒 No se cierra **sin disposición** cargada.
- 🔒 Una NC de **origen cliente** no se cierra con la notificación **pendiente** (poné "Sí", o "N/A" si no corresponde) — API Q1 5.10.3.

Si un candado rechaza el cierre, el select vuelve solo a su estado anterior y el cartel rojo te dice qué falta.

**Alertas:** las NC abiertas aparecen en el panel "Para hoy"; si llevan **más de 30 días abiertas** pasan a alerta crítica (la meta del SGC es cerrarlas en 30 días).

### 10.2 Acciones CAPA (correctivas y preventivas)

La NC arregla **el producto**; la CAPA ataca **la causa** para que no se repita.

**Para registrar una:** Calidad → **+ Nueva CAPA**:
- **Tipo:** Correctiva (a partir de una NC) o Preventiva (antes de que pase).
- **NC asociada** y **Responsable**.
- **Causa raíz:** el análisis (5 porqués, Ishikawa…).
- **Acción** *: qué se va a hacer para eliminar la causa.
- **Fecha compromiso** y **fecha de implementación**.
- **Verificación de eficacia** + **¿Eficaz?**: cómo comprobaste que funcionó.

**Numeración automática:** `AC-0001` (correctivas) / `AP-0001` (preventivas).

**Candado de cierre:** 🔒 una CAPA **no se puede cerrar sin la verificación de eficacia** cargada. Implementar no alcanza: hay que verificar que funcionó.

**Alertas:** las CAPA con fecha compromiso vencida y sin cerrar aparecen como alerta crítica en "Para hoy".

### 10.3 Documentos controlados

El archivo oficial de documentos del SGC: manual de calidad, procedimientos, instructivos, formularios, **planos**, WPS/PQR/WPQ, PQP y planes de contingencia. Control por **código + revisión** (ISO 7.5 / API Q1 4.4).

**Para cargar un documento o una revisión nueva:** Calidad → Documentos → **+ Nuevo documento / revisión**:
- **Código** * (ej.: `PG-04`, `WPS-01`, `PLN-1502`) y **Título** *.
- **Tipo** y **Revisión** (0, 1, 2…).
- **Estado:** `Borrador` o `Vigente`.
- **PDF** del documento y observaciones (motivo de la revisión).

**Regla de vigencia única:** 🔒 por cada código hay **una sola revisión vigente**. Cuando marcás una revisión nueva como vigente, **la anterior pasa a obsoleta automáticamente** — no hay que acordarse de nada. Y en Producción **solo se pueden referenciar documentos vigentes**: un paso de OP no puede apuntar a una revisión obsoleta.

### 10.4 Plantillas PQP

El **Product Quality Plan** es el routing modelo de cada producto crítico (unión fig. 1502, pup joint…): la secuencia de operaciones con sus **hold/witness points** y los documentos (WPS, instructivos) de cada paso.

**Para crear una:** Calidad → Plantillas PQP → **+ Nueva plantilla**:
- **Código** * (ej.: `PQP-1502`), **Producto** *, **Documento PQP** (el doc controlado que lo respalda) y descripción.
- **Operaciones del routing:** agregá cada paso con operación, máquina, **punto** (Normal / Hold / Witness), documento y minutos estimados.

**Cómo se usa:** al fabricar ese producto, en la OP → **Tiempos** → botón **PQP** elegís la plantilla y el sistema instancia todos los pasos de una (ver [6.1](#61-pasos-de-producción-tiempos-y-puntos-de-control-pqp)). Así todas las OPs del mismo producto siguen el mismo plan, siempre.

### 10.5 SGC — Tablero, revisión por dirección, auditorías y competencias

La pestaña **SGC** (dentro de Calidad) junta los rituales que pide ISO 9001 / API Q1 para certificar:

- **Tablero:** KPIs de calidad del período (OTD, NC nuevas y abiertas, CAPA abiertas/vencidas, calibraciones vencidas, auditorías) más el **registro de certificados de conformidad emitidos**. Cada certificado que generás desde Ventas queda numerado correlativamente (**CC-0001, CC-0002…**) y registrado con su snapshot de piezas y coladas; reimprimir usa el mismo número.
- **Revisión por la dirección** (§9.3): tocá **Nueva revisión**, elegí el período y el sistema **congela los KPIs automáticamente** — vos cargás asistentes, decisiones y acciones. Al **cerrarla** queda inmutable (no se puede editar ni borrar: es un registro del SGC). Mínimo una por año.
- **Auditorías internas** (§9.2): cargá el programa anual (fecha planificada) y ejecutá cada auditoría cargando **hallazgos** tipificados (conforme, observación, NC menor/mayor, oportunidad) con su cláusula. Desde un hallazgo NC, el botón **Generar NC** crea la No Conformidad en NCR/CAPA con origen "auditoría" y las deja vinculadas. Las planificadas vencidas saltan en las alertas del tablero.
- **Competencias** (§7.2): matriz persona × habilidad con nivel (en formación / calificado / experto), fecha, vencimiento y evidencia. Es lo que respalda ante el auditor que quien firmó un signoff estaba calificado. Las calificaciones vencidas o por vencer (30 días) saltan en alertas.

**Modo auditor:** en Configuración → Usuarios podés marcar a un usuario como **Auditor (solo lectura)** — ideal para el auditor de certificación: ve todo el SGC, producción e inventario pero no puede tocar nada (mismo cerrojo doble del Modo Contador, garantizado por la base de datos).

### 10.6 Retención de evidencia

Los registros de calidad —NC, CAPA, documentos controlados, ensayos, calibraciones— **no se pueden borrar** (retención de 10 años, API Q1 4.5). Si algo quedó mal cargado:
- Corregilo editándolo, o
- Cerralo con una observación que explique el error.

Solo el administrador puede eliminar evidencia, por excepción justificada.

---

## 11. Contabilidad

Es el grupo más grande. **La buena noticia:** la mayoría de los asientos se generan **solos** (ventas, compras, cobros, pagos). Acá sobre todo **consultás** y, ocasionalmente, cargás asientos manuales o hacés cierres.

> **Antes de operar contabilidad por primera vez:** configurá la **Imputación contable** (ver [12.3](#123-imputación-contable)). Si no, los asientos automáticos no saben a qué cuentas ir.

### 11.1 Plan de cuentas

La estructura jerárquica de cuentas (partida doble).

- **Expandir / Colapsar** los grupos.
- **+ Nueva cuenta:** **Código** *, **Nombre** *, **Tipo** (Activo / Pasivo / Patrimonio Neto / Ingreso / Gasto / Resultado), **Cuenta padre**, **Imputable** (si se pueden cargar asientos ahí), **Activa**, **Ajustable** (para ajuste por inflación).
- Filtrá por tipo, activa o ajustable.

### 11.2 Asientos contables

Lista de todos los asientos (debe = haber).

**Para cargar un asiento manual:**
1. **+ Nuevo asiento**.
2. **Fecha** *, **Descripción** *, **Comprobante**, **Tipo** (manual / factura / cobro / pago / cierre / ajuste…), **Moneda**.
3. **Líneas:** agregá cuenta + monto en **Debe** o **Haber**. El **total Debe** tiene que ser **igual al total Haber** (si no, no deja guardar).
4. Guardá.

**Estados:** `borrador → confirmado → (anulado)`.
- **Editar / Eliminar:** solo si está en `borrador`.
- **Anular:** genera un asiento inverso (no se borra, se contra-asienta).

> La numeración la pone la base de datos: es correlativa y no se repite.

### 11.3 Cobros y pagos

El lugar para registrar **plata que entra o sale**.

1. Elegí la pestaña: **Cobro de cliente** o **Pago a proveedor**.
2. Completá **Fecha**, **Tercero** (cliente/proveedor), **Monto**, **Moneda** (y **TC** si es en pesos), **Método** (caja / banco / cheque diferido), **Comprobante / recibo**, **Observaciones**.
3. **Registrar.**

El asiento se arma **automáticamente** (caja/banco contra deudores o proveedores) y el cobro se imputa **FIFO** a las facturas más viejas.

**Retenciones sufridas (clave con clientes grandes):** si el cliente te paga **neto de retenciones** (Ganancias, IIBB, SUSS, IVA — YPF y las mineras lo hacen siempre), cargá el **monto cobrado** en Monto y agregá cada certificado con **+ Retención** (impuesto, Nº de certificado, jurisdicción si es IIBB, y monto retenido). El sistema:
- arma el asiento completo: banco + cada retención al debe, deudores por el **total** al haber — la cta. cte. del cliente queda saldada de verdad;
- guarda cada certificado en el registro de **Retenciones sufridas** (exportable para el contador desde Exportables).

**Método "Cheque diferido":** el cobro entra a la cuenta **Cheques en cartera** (no a caja/banco) y se abre el modal para completar número, banco y fecha de pago del cheque. En un pago, sale por **Cheques emitidos**.

### 11.4 Cheques

Cartera de cheques diferidos (propios y de terceros), en ARS o USD. Aparecen en el panel "Para hoy" cuando se acerca la fecha de depósito o pago.

**Ahora los cheques mueven la contabilidad solos** al cambiar el estado:

| Evento | Asiento automático |
|--------|--------------------|
| Recibido → **depositado** | Banco / Cheques en cartera |
| Recibido → **rechazado** | Deudores / Cartera (o Banco si ya estaba depositado) — **la deuda del cliente revive** en la cta. cte. desde la fecha del rechazo |
| Emitido → **debitado** | Cheques emitidos / Banco |
| Emitido → **rechazado** | Cheques emitidos / Proveedores (la deuda al proveedor revive) |

> Para que el circuito cierre, el **alta** contable del cheque la hace **Cobros y pagos** con método "Cheque diferido". Los estados `acreditado`, `endosado` y `anulado` no generan asiento.

### 11.5 Libros y estados contables

Todo de **consulta** (elegís un rango de fechas y mirás):

| Sección | Qué muestra |
|---------|-------------|
| **Libro diario** | Asientos confirmados en orden cronológico |
| **Libro mayor** | Movimientos y saldo acumulado de **una** cuenta |
| **Balance de comprobación** | Sumas y saldos de todas las cuentas (debe = haber) |
| **Estado de resultados** | Ingresos − gastos del período |
| **Balance general** | Activo = Pasivo + Patrimonio Neto |
| **Ratios financieros** | Liquidez, endeudamiento, rentabilidad, actividad |
| **Bimonetario** | Balance en doble columna ARS / USD |
| **Histórico vs Ajustado** | Balance reexpresado por inflación (sin tocar asientos) |
| **Comparativo entre ejercicios** | Saldos de dos fechas y su variación |

En **Exportables** (elegís un mes y descargás CSV, o toda la **carpeta del período** en ZIP): subdiarios de ventas y compras, **IVA ventas** (letra por comprobante, NC en negativo, alícuota), **IVA compras** (formato libro real), **Posición IVA del mes** (débito − crédito − percepciones − retenciones → saldo a pagar o a favor), **Retenciones sufridas** (los certificados del mes, para el contador), mayores, **Valuación de inventario** (foto valorizada del stock a hoy: MP por lote y por material con promedio ponderado, PT e insumos — respaldo de Bienes de Cambio del balance) y plan de cuentas.

### 11.6 Correlatividad

Audita la numeración de asientos: detecta **huecos** o **duplicados**. Revisalo antes de cierres o auditorías.

### 11.7 Conciliación bancaria

1. Definí las **cuentas bancarias**.
2. **Importá el extracto** del banco (CSV/XLS).
3. **Conciliá:** emparejá cada línea del extracto con su asiento. Los no conciliados quedan marcados.

### 11.8 Cierre, períodos y ajuste por inflación

- **Períodos mensuales:** cerrás un mes para que **nadie cargue asientos en él**. Si necesitás corregir, lo reabre el administrador.
- **Índices IPC:** cargá el IPC del INDEC mes a mes (es la misma serie que publica la FACPCE). Es la base para el ajuste por inflación; cuanto más completa, más exacta la anticuación.
- **Ajuste por inflación (RT 54):** elegí el **mes de cierre**, **Calcular preview**, revisá y **Generar asiento**. Cada partida de las cuentas no monetarias se reexpresa por el índice de su mes de origen (anticuación mensual); si ya registraste un ajuste anterior, lo previo a esa fecha se lleva con un solo coeficiente y lo posterior mes a mes. El Capital se ajusta contra **Ajuste de capital** (312000) y la contrapartida es el **RECPAM**. Pasá el mouse por una fila para ver el detalle por mes. Si falta el IPC de algún mes, se usa el anterior y el sistema avisa. Hacé el ajuste **antes** de refundir resultados.
- **Histórico vs Ajustado:** muestra cada cuenta a valor nominal y reexpresada desde cero a la fecha de corte (no cuenta los ajustes ya registrados).
- **Comparativo entre ejercicios:** con **Moneda homogénea** tildado, el período A se lleva a moneda del período B (IPC B / IPC A) para que las cifras sean comparables, como pide la RT 54.
- **Cierre y apertura:** cierre del ejercicio en pasos (refundición de resultados → pasaje a resultados no asignados → cierre patrimonial → apertura). Usá **Calcular preview** antes de **Generar asientos**.
- **Ajustes de cierre RT 54 (antes de refundir):** en la misma página, el panel **Ajustes de cierre RT 54** genera los cinco asientos que pide la norma para Entidades Pequeñas. Cargá el **TC de cierre** y, paso por paso, **Preview** → **Generar asiento** (salen en borrador; confirmalos en Asientos):
  1. **Impuesto a las ganancias:** el importe determinado que te pasa la contadora.
  2. **Previsión para incobrables:** por antigüedad de la cartera (usa el aging de Cta. corriente × TC); ajustá los % por tramo. Ajusta la previsión existente al objetivo (constituye o revierte).
  3. **Provisión vacaciones y cargas s/SAC:** vacaciones devengadas por centro (fábrica / administración) más las contribuciones sobre el SAC ya provisionado.
  4. **Diferencia de cambio:** revalúa al TC de cierre las cuentas monetarias con saldo en dólares (sólo lo registrado en asientos en USD: una factura en pesos no se revalúa).
  5. **Variación de existencias / CMV:** lleva las cuentas de stock a la existencia final (prellenada con la valuación de inventario × TC) y la diferencia es el **costo de los bienes vendidos**.
- **Bienes de uso:** cargá cada activo fijo (tornos, CNC, rodados, instalaciones, herramientas, software) con **fecha de alta**, **valor de origen** en pesos, **valor residual** y **vida útil en meses** (el rubro sugiere las cuentas y la vida útil). La depreciación es lineal por meses: mes de alta completo, mes de baja incluido. En el cierre, **paso 6** del panel RT 54 calcula la depreciación del ejercicio de todos los bienes y genera el asiento (gasto contra amortización acumulada) en borrador. **Baja**: fecha y motivo; el asiento de baja se hace en Asientos. El **Anexo Bienes de uso** (valores de origen, altas, bajas, amortización del ejercicio y acumulada por rubro) se exporta desde Exportables.
- **Estados contables RT 54 (Contabilidad → Estados contables → EECC RT 54):** elegí el ejercicio, cargá el TC de cierre (para el anexo de moneda extranjera) y tocá **Vista previa**: ves el Estado de situación patrimonial por rubro (corriente / no corriente), el Estado de resultados por función y el Flujo de efectivo sintético, con la columna del ejercicio anterior reexpresada a moneda de cierre. **Exportar Excel** baja un libro con carátula, ESP, ER, Evolución del PN, Flujo de efectivo, notas de composición de rubros y los anexos (moneda extranjera, bienes de uso, previsiones, costo de ventas, gastos por naturaleza, partes relacionadas), en el mismo orden que el modelo del Consejo. Corré antes los ajustes de cierre y el ajuste por inflación. Si una cuenta con saldo no tiene rubro, la vista previa lo avisa y el ESP no cuadra hasta que lo asignes.
- **Rubro RT 54:** cada cuenta imputable tiene un rubro (Plan de cuentas → Editar) que define dónde se expone en los estados contables y alimenta el reporte de Ratios.

---

## 12. Configuración

Tres pestañas. Las dos últimas son **solo para el administrador**.

### 12.1 Materiales

El catálogo de tipos de acero / normas que después elegís en barras y certificados.
**+ Nuevo material** → **Material / Norma** *, **Descripción**, **Orden**, **Estado** (activo / inactivo).

### 12.2 Usuarios y permisos (admin)

- Ves y podés **cambiar el código de empresa** (el que usan los nuevos para unirse).
- Listás usuarios, editás su **rol** y **habilitás/deshabilitás módulos** por usuario. La lista cubre todos los módulos del sistema (inventario, producción, compras, ventas, calidad, análisis y contabilidad).

> **Nota técnica:** los permisos por módulo hoy son **visuales** (esconden secciones del menú). No los uses como barrera de seguridad fuerte.

### 12.3 Imputación contable

**Clave para que los asientos automáticos funcionen.** Acá decís qué cuenta contable usar para cada tipo de operación:

- **Ventas:** cuenta de venta, deudores por ventas, IVA débito fiscal, **alícuota de IVA** (21% por defecto), si los precios **incluyen IVA**, y el **punto de venta AFIP** para la facturación electrónica.
- **Compras:** IVA crédito fiscal, proveedores, compra de materia prima / insumos / herramientas, servicios de terceros, y la cuenta puente **GR/IR** (facturas a recibir).
- **Caja y banco:** cuenta de caja (efectivo), cuenta de banco (transferencias), **cheques en cartera** (recibidos) y **cheques emitidos** (a pagar).
- **Retenciones sufridas:** las cuentas de crédito fiscal donde van las retenciones que te aplican los clientes (Ganancias, IIBB, SUSS, IVA). Vienen preconfiguradas con las cuentas del plan de Vitalmet.
- **Stock y ajustes de inventario:** las cuentas de stock (materia prima, producto terminado, insumos) y la cuenta de resultado **AJUSTES DE INVENTARIO** contra la que se asientan las diferencias de ajustes y conteos físicos. Vienen preconfiguradas (114002 / 114001 / 114003 / 421099).
- **Cierre RT 54:** costo de los bienes vendidos (511000), diferencias de cambio (424006), previsión para incobrables (112090) y su gasto (423007), impuesto a las ganancias (425001) y a pagar (213005), provisión vacaciones (214009) y anticipos de clientes (215001). Preconfiguradas por la migración 072; son las que usan los ajustes de cierre.

Completá y tocá **Guardar configuración**. Si dejás un campo en blanco, ese tipo de asiento automático queda desactivado.

---

## 13. Los 4 circuitos completos (lo más importante)

Si entendés estos cuatro circuitos, sabés usar el ERP. Seguilos en orden.

### Circuito A — Vender (de la cotización al cobro)

```
1. Clientes          → cargá el cliente (si no existe)
2. Presupuestos      → + Nuevo presupuesto → cargá ítems → mirá el margen → PDF al cliente
3. Presupuestos      → cuando el cliente acepta: estado = aprobado → botón "Venta"
4. Ventas            → revisá el pedido → estado = entregado → genera Remito (PDF) y Certificado
5. Ventas            → botón "Facturar" ⚡ → AFIP devuelve el CAE → factura en PDF
6. Cobros y Pagos    → "Cobro de cliente" → registrá la plata cuando entra
7. Cuenta corriente  → controlá el saldo y la antigüedad de la deuda
```
*Asientos generados solos:* al facturar (venta) y al cobrar.

### Circuito B — Comprar (de la OC al material liberado)

```
1. Proveedores        → cargá el proveedor; si es material crítico: evaluálo y aprobalo en el AVL
2. Compras → OC       → + Nueva OC → ítems → moneda y TC → estado = enviada/confirmada
                        (el sistema rechaza la OC si el proveedor crítico no está aprobado)
3. Compras → OC       → botón "Recibir" cuando llega la mercadería  (asiento GR/IR)
                        → la materia prima entra EN CUARENTENA
4. Inventario → Cert. MTC      → cargá el MTR con su colada y vinculalo
5. Compras → Inspección        → verificá material + MTR → ✓ Aceptar (o ✕ Rechazar + NC)
6. Compras → OC       → botón "Factura" cuando llega la factura     (3-way match, cancela GR/IR)
7. Cobros y Pagos     → "Pago a proveedor" cuando pagás
```
*Asientos generados solos:* en la recepción (GR/IR), en la factura y en el pago.

### Circuito C — Producir (de la barra al producto)

```
1. Compras            → comprás la barra de acero (Circuito B, con inspección aceptada)
2. Producción → OP    → + Nueva orden → elegí la barra ACEPTADA → metros consumidos → piezas
3. Producción → OP    → Tiempos → aplicá el PQP del producto (o cargá los pasos a mano)
4. Producción         → cronometrá los pasos; en cada HOLD/WITNESS: Calidad firma QC
5. Producción         → botón Ensayo → registrá hidrostático/dimensional/etc. con instrumento calibrado
6. Producción → OP    → estado = completada (solo si no quedan puntos sin firmar)
                        → se descuenta MP y nace el Producto Terminado
7. Análisis → Trazabilidad     → verificá la cadena certificado → colada → barra → OP → PT
```

### Circuito D — Tratar un problema de calidad (NC → CAPA)

```
1. Se detecta el problema   → recepción rechazada, ensayo no conforme o reclamo de cliente
2. Calidad → NCR            → + Nueva NC → origen + vínculos (OP/recepción/venta/ensayo) + descripción
3. Definí la disposición    → retrabajo / reproceso / rechazo / concesión (con justificación) / devolución
4. Si amerita atacar la causa: + Nueva CAPA → causa raíz → acción → responsable → fecha compromiso
5. Implementá la acción     → cargá fecha de implementación
6. Verificá la eficacia     → cargá cómo lo comprobaste + ¿Eficaz? → cerrá la CAPA
7. Cerrá la NC              → (si es de origen cliente, antes marcá "Cliente notificado = Sí")
```
*El sistema no te deja saltear los pasos 3, 6 y 7: son los candados del SGC.*

---

## 14. Reglas de oro y errores comunes

**Hacé siempre:**
- ✅ Cargá **proveedores y clientes primero**; después se eligen solos en los documentos.
- ✅ Vinculá **certificado MTC + OC + colada** en cada barra. Sin eso no hay trazabilidad.
- ✅ La **colada** sale del MTR (heat number). **No** es el número de OC ni el de remito.
- ✅ Ingresá el material por el circuito de compras (OC → Recibir → Inspección), no por carga manual.
- ✅ Configurá la **Imputación contable** antes de operar contabilidad.
- ✅ Revisá la venta **antes** de apretar **Facturar**: con CAE ya no se edita.
- ✅ Esperá el cartelito verde de confirmación después de guardar.
- ✅ Mirá el panel **"Para hoy"** todas las mañanas — ahora también avisa calibraciones, cuarentenas, NC y CAPA.

**Evitá:**
- ❌ Saltear estados (no pases un presupuesto a venta sin aprobarlo, etc.).
- ❌ Forzar un cambio de estado que el sistema rechaza: si el select "vuelve solo", un candado de calidad lo frenó — leé el mensaje rojo, que dice exactamente qué falta.
- ❌ Cargar a mano un asiento que el sistema ya genera solo (ventas, compras, cobros).
- ❌ Cargar asientos en un **período cerrado** (no te va a dejar).
- ❌ Usar un instrumento con la calibración vencida "porque es un ratito". Está bloqueado por algo.
- ❌ Recargar la página a lo bruto si algo no carga: usá el botón **Reintentar** del cartel rojo.

**Errores frecuentes y qué hacer:**

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| No veo un módulo en el menú | Tu usuario no lo tiene habilitado | Pedíselo al administrador (Config → Usuarios) |
| El asiento no me deja guardar | Debe ≠ Haber | Cuadrá las líneas hasta que coincidan |
| "Facturar" da error | Falta config de AFIP o de imputación | Avisá al administrador |
| No puedo editar una venta | Ya tiene CAE | Anulala y hacé una nueva si corresponde |
| No puedo cargar en un mes | El período está cerrado | El admin lo reabre (Contabilidad → Períodos) |
| Cartel rojo arriba | Falló la carga de datos | Tocá **Reintentar** |
| El presupuesto no muestra botón "Venta" | No está en estado `aprobado` | Cambiá el estado primero |
| "AVL: el proveedor no está aprobado…" | OC a proveedor crítico sin aprobar (o reevaluación vencida) | Compras → Proveedores → evaluálo y marcá Aprobado en la sección AVL |
| "La barra está en cuarentena…" | Querés consumir material sin inspección aceptada | Compras → Inspección de entrada → ✓ Aceptar (con MTR cargado) |
| "No se puede aceptar materia prima sin el certificado (MTR)…" | La recepción no tiene certificado vinculado | Cargá el MTC en Inventario → Certificados y vinculalo a la recepción/OC |
| "Hold point sin liberar…" / la OP no pasa a completada | Hay puntos hold/witness sin firma QC | OP → Tiempos → botón **Firmar QC** en el paso pendiente |
| "La NC no se puede cerrar sin disposición" | Falta definir qué se hace con el producto | Editá la NC y cargá la disposición (y justificación si es concesión) |
| "La NC es de origen cliente y la notificación está pendiente" | Cliente sin notificar | Notificalo y marcá "¿Cliente notificado?" = Sí |
| La CAPA no cierra | Falta la verificación de eficacia | Cargá cómo verificaste que la acción funcionó |
| Un instrumento aparece con ⛔ en el ensayo | Calibración vencida o no conforme | Herramientas → **Calibrar** → registrá la calibración conforme |

---

## 15. Preguntas frecuentes

**¿En qué moneda trabaja el sistema?**
En dólares (US$). Solo cheques y la contabilidad bimonetaria manejan pesos con tipo de cambio.

**¿Tengo que cargar los asientos contables a mano?**
No. Las ventas, compras, cobros y pagos generan su asiento automáticamente. Solo cargás asientos manuales para ajustes puntuales.

**¿La factura es la oficial de AFIP?**
Sí: el botón "Facturar" emite la factura electrónica real y trae el CAE. *(Nota: depende de tener el certificado X.509 de AFIP cargado en el servicio de facturación.)*

**¿Cómo sé cuánto me debe un cliente?**
Ventas → **Cuenta corriente**. Muestra saldo y antigüedad de la deuda por cliente.

**¿Cómo rastreo de qué barra (y de qué colada) salió una pieza?**
Análisis → **Trazabilidad** → buscá por lote de PT o por certificado/OC. La colada aparece en las fichas de barra y PT.

**Llegó una barra nueva y no me deja usarla en producción. ¿Por qué?**
Está **en cuarentena**: toda materia prima recibida por OC espera la inspección de entrada. Andá a Compras → Inspección de entrada, verificá material y MTR, y tocá **✓ Aceptar**.

**¿Por qué el sistema me rechazó la OC a un proveedor?**
El proveedor está marcado como **crítico** y no está aprobado en el AVL (o su reevaluación venció). Evaluálo en Compras → Proveedores (sección Calidad — AVL) antes de emitir la OC.

**¿Por qué no puedo cerrar una NC o una CAPA?**
Son los candados del SGC: la NC necesita **disposición** (y notificación al cliente si es de ese origen); la CAPA necesita la **verificación de eficacia**. El mensaje rojo te dice exactamente qué falta.

**¿Puedo borrar una NC / un documento / un ensayo que cargué mal?**
No — la evidencia de calidad se retiene 10 años (API Q1). Corregilo editándolo o cerralo con una observación. Solo el administrador puede eliminarlo por excepción.

**¿Dónde están los procedimientos del sistema de calidad?**
En Calidad → **Documentos**: ahí vive la lista maestra oficial (manual MC-01 y procedimientos PG-01 a PG-16), cada uno con su revisión vigente y su PDF.

**¿Qué hago si me equivoqué en una venta ya facturada?**
No se edita (tiene CAE). **Anulala** (queda el registro) y, si corresponde, cargá una nueva.

**¿Quién administra usuarios y permisos?**
El administrador (Giuliano), en Configuración → Usuarios y permisos. También cambia ahí el código de empresa.

**¿Puedo usarlo desde el celular?**
Sí. El menú se abre con el botón ☰. Está adaptado para pantallas chicas.

---

*Manual de usuario de VitalStock ERP. Ante dudas o errores que no figuran acá, contactá al administrador del sistema.*
