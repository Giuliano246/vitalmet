# Manual de usuario — VitalStock ERP (Vitalmet SA)

> Guía práctica para usar el ERP correctamente. Está pensada para que **cualquier persona** —aunque nunca haya tocado el sistema— pueda cargar datos, seguir el circuito completo y no romper nada.

**Acceso:** https://erp.vitalmetsa.com
**Empresa:** Vitalmet SA — Perú 246, Villa Martelli, Buenos Aires
**Versión del manual:** Junio 2026

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
10. [Contabilidad](#10-contabilidad)
11. [Configuración](#11-configuración)
12. [Los 3 circuitos completos (lo más importante)](#12-los-3-circuitos-completos-lo-más-importante)
13. [Reglas de oro y errores comunes](#13-reglas-de-oro-y-errores-comunes)
14. [Preguntas frecuentes](#14-preguntas-frecuentes)

---

## 1. Antes de empezar: conceptos clave

Leé esto una vez. Te ahorra el 90% de los problemas.

- **Moneda base: dólares (US$).** Casi todo el sistema trabaja en dólares. Las excepciones son la **contabilidad bimonetaria** y los **cheques**, que pueden ir en pesos (ARS) con su tipo de cambio.
- **Cada cosa tiene un "estado".** Presupuestos, ventas, órdenes de compra y asientos pasan por etapas (borrador → enviado → aprobado, etc.). El estado decide qué podés hacer con el documento. **No saltees estados.**
- **Todo lo que mueve plata genera un asiento contable automático.** Cuando facturás una venta, recibís mercadería o registrás un cobro, el sistema arma el asiento solo. No tenés que cargarlo a mano.
- **Trazabilidad de punta a punta.** Cada producto terminado se puede rastrear hacia atrás hasta la barra de acero y su certificado MTC. Por eso es importante vincular bien las cosas al cargarlas.
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

A la izquierda tenés el **menú lateral** con 8 grandes grupos. Al entrar a un grupo, arriba aparecen **pestañas** con sus secciones.

| Grupo | Qué contiene |
|-------|--------------|
| **Métricas** | Tablero de inicio con indicadores y alertas del día |
| **Inventario** | Materia prima, Productos terminados, Certificados MTC, Insumos, Herramientas |
| **Producción** | Órdenes de producción |
| **Compras** | Órdenes de compra, Proveedores, Facturas recibidas |
| **Ventas** | Presupuestos, Ventas, Clientes, Cuenta corriente |
| **Análisis** | Costos y rentabilidad, Trazabilidad |
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
  - Cheques por depositar o pagar.
  - Materiales por debajo del stock mínimo.
  - Órdenes de compra con entrega vencida.
  - Facturas de clientes vencidas.

> Cuando hay pendientes, aparece un **globito de alerta** sobre "Métricas" en el menú. Revisalo todas las mañanas.

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
   - **Metros mínimo** (umbral para que salte la alerta de reposición)
   - **Certificado MTC vinculado** (elegí el certificado de calidad de esa barra)
   - **Observaciones**
3. Guardá.

> **Importante:** vinculá siempre el **certificado MTC** y la **OC**. Eso es lo que permite la trazabilidad y los reclamos de calidad.

**Buscar:** por tipo, OC o lote. Las barras por debajo del mínimo aparecen marcadas.

### 5.2 Productos terminados (PT)

Stock de piezas listas para vender.

**Para cargar un PT a mano:**
1. **+ Nuevo PT**.
2. Completá **Lote PT** (`PT-2024-001`) *, **Pieza** (ej.: "Válvula esclusa") *, **Descripción** (ej.: "DN50 PN16 AISI 316"), **Cantidad** *, **Costo unitario US$**.
3. Si la pieza salió de una barra, vinculá la **Barra origen** (así se mantiene la trazabilidad).
4. Guardá.

**Para cargar muchos PT de golpe:**
1. **Importar Excel**.
2. Descargá la plantilla, completala (mínimo: Lote, Pieza, Cantidad) y subila (`.xlsx` o `.csv`).

> Normalmente los PT se generan **solos** al completar una orden de producción (ver [Producción](#6-producción)). La carga manual es para casos puntuales.

### 5.3 Certificados MTC

Los certificados de calidad (Mill Test Certificate) de cada material.

**Para cargar uno:**
1. **+ Nuevo certificado**.
2. Completá **Nº cert.** *, **Proveedor** *, **Material** *, **Nº OC**, **Metros certificados** *, **Fecha**.
3. Subí el **PDF** del certificado.
4. Asociá las **barras** que cubre.
5. Guardá.

> El PDF queda guardado en el sistema; se descarga cuando lo abrís.

### 5.4 Insumos

Consumibles: lubricantes, soldadura, limpieza, etc.

**Para cargar:** **+ Nuevo insumo** → **Código** *, **Nombre** *, **Categoría**, **Stock** *, **Unidad**, **Mínimo stock**, **Último precio**, **Proveedor**. Guardá.

### 5.5 Herramientas

Insertos, mechas, hojas, instrumentos.

**Para cargar:** **+ Nueva herramienta** → **Código** *, **Nombre** *, **Cantidad** *, **Estado** (en uso / desgastada / reparación / inactiva), **Ubicación**, **Precio compra**, **Fecha compra**, **Proveedor**. Guardá.

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

**Qué pasa al completar la OP:**
- Se **descuenta** la materia prima consumida.
- Se **genera el producto terminado** (PT) con su lote.
- Queda armada la cadena de trazabilidad: certificado → barra → OP → PT.

---

## 7. Compras

El grupo **Compras** tiene 3 pestañas: **Órdenes de compra**, **Proveedores** y **Facturas recibidas**.

> El circuito de compras funciona con **triple coincidencia (3-way match)**: Orden de compra → Recepción de mercadería → Factura del proveedor. El sistema controla que las tres cosas coincidan antes de dar por buena la deuda.

### 7.1 Proveedores

Cargalos primero, así después podés elegirlos en la OC.

**Para cargar:** **+ Nuevo proveedor** → **Razón social** *, **CUIT**, **Contacto**, **Teléfono**, **Email**, **Condición de pago** (ej.: "30 días FF"), **Dirección**, **Observaciones**. Guardá.

En la tabla ves cuántas OCs tiene y la **deuda en USD**.

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
2. Registrá lo que llegó.
3. Esto genera automáticamente el asiento de **GR/IR** ("mercadería recibida, factura por llegar").

**Registrar la factura del proveedor:**
1. Tocá **Factura** sobre la OC (o cargala desde "Facturas recibidas").
2. Completá **Nº factura** (ej.: `A-0001-00012345`), **Fecha**, **Vencimiento**, **Moneda**, **Neto**, **IVA** (el **Total** se calcula solo).
3. El sistema **concilia** la factura contra la recepción (3-way match) y arma el asiento que cancela el GR/IR.

> Cuando la OC tiene recepción **y** factura, su estado pasa a `facturada`.

### 7.3 Facturas recibidas

Lista de todas las facturas de proveedores. Acá ves la columna **Match** (si coincide con su recepción) y el **Asiento** generado. No se cargan sueltas: salen de una OC con recepción.

---

## 8. Ventas

El grupo **Ventas** tiene 4 pestañas: **Presupuestos**, **Ventas**, **Clientes** y **Cuenta corriente**. El circuito natural es:

```
Presupuesto → (aprobado) → Venta → (entregado) → Facturar (AFIP) → Cobro
```

### 8.1 Clientes

**Para cargar:** **+ Nuevo cliente** → **Razón social** *, **CUIT**, **Contacto**, **Teléfono**, **Email**, **Dirección**, **Notas**. Guardá.

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
- **Fechas de entrega** (desde / hasta).
- **Condiciones comerciales:** lista de precios, condición de pago (Contado, 15/30/60/90 días, etc.), vendedor, % bonificación.
- **Ítems:** pieza, descripción, cantidad, precio, descuento.

**Ciclo de vida:**

```
pendiente entrega → entregado → facturado
```

**Acciones sobre cada venta:**
- **Remito** 🚚 — genera el remito (PDF) para despachar.
- **Certificado** ✔ — genera el certificado de conformidad (PDF).
- **Facturar** ⚡ (botón verde) — **emite la factura electrónica en AFIP**. Llama al servicio de facturación, obtiene el **CAE** (Código de Autorización Electrónica) y devuelve la factura en PDF. La venta pasa a `facturado` y se genera el asiento de venta automáticamente.
- **CAE** — una vez facturada, este botón te deja ver/descargar la factura.
- **Anular** — da de baja la venta (queda registro de auditoría).
- **Excel** — exporta el listado.

> **Ojo:** una vez que la venta tiene **CAE**, no se puede editar (lo bloquea el sistema). Revisá bien **antes** de facturar.

### 8.4 Cuenta corriente

Muestra cuánto te debe cada cliente y desde hace cuánto.

- **Cargos:** ventas facturadas o entregadas (los pedidos pendientes de entrega **no** cuentan).
- **Cobrado:** lo que se registró en "Cobros y Pagos".
- **Saldo** y **aging** (antigüedad): columnas **Al día**, **1-30**, **31-60**, **61-90**, **+90 días**.
- La imputación es **FIFO**: los cobros se aplican primero a las facturas más viejas.

Tocá un cliente para ver el detalle por factura. Exportás con **Excel**.

---

## 9. Análisis (costos y trazabilidad)

### 9.1 Costos y rentabilidad

Calcula el costo real de cada pieza y su margen.

1. Configurá una vez: **Tarifa operario (USD/h)** y **Overhead %** (gastos indirectos: luz, alquiler…). Tocá **Guardar config**.
2. Tocá **↻ Recalcular**.
3. La tabla muestra, por pieza: costo de material, costo de tiempo, overhead, costo total, precio de venta promedio y **margen** (USD y %).

### 9.2 Trazabilidad

Dos buscadores:
- **Por pieza / lote PT:** te muestra el origen (PT ← OP ← barra ← certificado).
- **Por certificado / OC:** te muestra hacia adelante (certificado → barra → OP → PT → venta).

Sirve para reclamos de calidad y auditorías: con un número rastreás toda la cadena.

---

## 10. Contabilidad

Es el grupo más grande. **La buena noticia:** la mayoría de los asientos se generan **solos** (ventas, compras, cobros, pagos). Acá sobre todo **consultás** y, ocasionalmente, cargás asientos manuales o hacés cierres.

> **Antes de operar contabilidad por primera vez:** configurá la **Imputación contable** (ver [11.3](#113-imputación-contable)). Si no, los asientos automáticos no saben a qué cuentas ir.

### 10.1 Plan de cuentas

La estructura jerárquica de cuentas (partida doble).

- **Expandir / Colapsar** los grupos.
- **+ Nueva cuenta:** **Código** *, **Nombre** *, **Tipo** (Activo / Pasivo / Patrimonio Neto / Ingreso / Gasto / Resultado), **Cuenta padre**, **Imputable** (si se pueden cargar asientos ahí), **Activa**, **Ajustable** (para ajuste por inflación).
- Filtrá por tipo, activa o ajustable.

### 10.2 Asientos contables

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

### 10.3 Cobros y pagos

El lugar para registrar **plata que entra o sale**.

1. Elegí la pestaña: **Cobro de cliente** o **Pago a proveedor**.
2. Completá **Fecha**, **Tercero** (cliente/proveedor), **Monto**, **Moneda** (y **TC** si es en pesos), **Método** (caja / banco), **Comprobante / recibo**, **Observaciones**.
3. **Registrar.**

El asiento se arma **automáticamente** (caja/banco contra deudores o proveedores) y el cobro se imputa **FIFO** a las facturas más viejas.

### 10.4 Cheques

Cartera de cheques diferidos (propios y de terceros), en ARS o USD. Aparecen en el panel "Para hoy" cuando se acerca la fecha de depósito o pago.

### 10.5 Libros y estados contables

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

### 10.6 Correlatividad

Audita la numeración de asientos: detecta **huecos** o **duplicados**. Revisalo antes de cierres o auditorías.

### 10.7 Conciliación bancaria

1. Definí las **cuentas bancarias**.
2. **Importá el extracto** del banco (CSV/XLS).
3. **Conciliá:** emparejá cada línea del extracto con su asiento. Los no conciliados quedan marcados.

### 10.8 Cierre, períodos y ajuste por inflación

- **Períodos mensuales:** cerrás un mes para que **nadie cargue asientos en él**. Si necesitás corregir, lo reabre el administrador.
- **Índices IPC:** cargá el IPC del INDEC mes a mes. Es la base para el ajuste por inflación.
- **Ajuste por inflación (RT 6):** elegí el período, **Calcular preview**, revisá y **Generar asiento** (reexpresa las cuentas no monetarias contra RECPAM). Necesitás al menos 2 meses de IPC cargados.
- **Cierre y apertura:** cierre del ejercicio en pasos (refundición de resultados → pasaje a resultados no asignados → cierre patrimonial → apertura). Usá **Calcular preview** antes de **Generar asientos**.

---

## 11. Configuración

Tres pestañas. Las dos últimas son **solo para el administrador**.

### 11.1 Materiales

El catálogo de tipos de acero / normas que después elegís en barras y certificados.
**+ Nuevo material** → **Material / Norma** *, **Descripción**, **Orden**, **Estado** (activo / inactivo).

### 11.2 Usuarios y permisos (admin)

- Ves y podés **cambiar el código de empresa** (el que usan los nuevos para unirse).
- Listás usuarios, editás su **rol** y **habilitás/deshabilitás módulos** por usuario.

> **Nota técnica:** los permisos por módulo hoy son **visuales** (esconden secciones del menú). No los uses como barrera de seguridad fuerte.

### 11.3 Imputación contable

**Clave para que los asientos automáticos funcionen.** Acá decís qué cuenta contable usar para cada tipo de operación:

- **Ventas:** cuenta de venta, deudores por ventas, IVA débito fiscal, **alícuota de IVA** (21% por defecto), y si los precios **incluyen IVA**.
- **Compras:** IVA crédito fiscal, proveedores, compra de materia prima / insumos / herramientas, servicios de terceros, y la cuenta puente **GR/IR** (facturas a recibir).
- **Caja y banco:** cuenta de caja (efectivo) y cuenta de banco (transferencias).

Completá y tocá **Guardar configuración**. Si dejás un campo en blanco, ese tipo de asiento automático queda desactivado.

---

## 12. Los 3 circuitos completos (lo más importante)

Si entendés estos tres circuitos, sabés usar el ERP. Seguilos en orden.

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

### Circuito B — Comprar (de la OC a la deuda)

```
1. Proveedores        → cargá el proveedor (si no existe)
2. Compras → OC       → + Nueva OC → ítems → moneda y TC → estado = enviada/confirmada
3. Compras → OC       → botón "Recibir" cuando llega la mercadería  (asiento GR/IR)
4. Compras → OC       → botón "Factura" cuando llega la factura     (3-way match, cancela GR/IR)
5. Cobros y Pagos     → "Pago a proveedor" cuando pagás
```
*Asientos generados solos:* en la recepción (GR/IR), en la factura y en el pago.

### Circuito C — Producir (de la barra al producto)

```
1. Compras            → comprás la barra de acero (Circuito B)
2. Inventario → Cert. MTC      → cargá el certificado de calidad y su PDF
3. Inventario → Materia prima  → cargá la barra y vinculá certificado + OC
4. Producción → OP    → + Nueva orden → elegí la barra → metros consumidos → cantidad de piezas
5. Producción → OP    → estado = completada → se descuenta MP y nace el Producto Terminado
6. Análisis → Trazabilidad     → verificá la cadena certificado → barra → OP → PT
```

---

## 13. Reglas de oro y errores comunes

**Hacé siempre:**
- ✅ Cargá **proveedores y clientes primero**; después se eligen solos en los documentos.
- ✅ Vinculá **certificado MTC + OC** en cada barra. Sin eso no hay trazabilidad.
- ✅ Configurá la **Imputación contable** antes de operar contabilidad.
- ✅ Revisá la venta **antes** de apretar **Facturar**: con CAE ya no se edita.
- ✅ Esperá el cartelito verde de confirmación después de guardar.
- ✅ Mirá el panel **"Para hoy"** todas las mañanas.

**Evitá:**
- ❌ Saltear estados (no pases un presupuesto a venta sin aprobarlo, etc.).
- ❌ Cargar a mano un asiento que el sistema ya genera solo (ventas, compras, cobros).
- ❌ Cargar asientos en un **período cerrado** (no te va a dejar).
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

---

## 14. Preguntas frecuentes

**¿En qué moneda trabaja el sistema?**
En dólares (US$). Solo cheques y la contabilidad bimonetaria manejan pesos con tipo de cambio.

**¿Tengo que cargar los asientos contables a mano?**
No. Las ventas, compras, cobros y pagos generan su asiento automáticamente. Solo cargás asientos manuales para ajustes puntuales.

**¿La factura es la oficial de AFIP?**
Sí: el botón "Facturar" emite la factura electrónica real y trae el CAE. *(Nota: depende de tener el certificado X.509 de AFIP cargado en el servicio de facturación.)*

**¿Cómo sé cuánto me debe un cliente?**
Ventas → **Cuenta corriente**. Muestra saldo y antigüedad de la deuda por cliente.

**¿Cómo rastreo de qué barra salió una pieza?**
Análisis → **Trazabilidad** → buscá por lote de PT o por certificado/OC.

**¿Qué hago si me equivoqué en una venta ya facturada?**
No se edita (tiene CAE). **Anulala** (queda el registro) y, si corresponde, cargá una nueva.

**¿Quién administra usuarios y permisos?**
El administrador (Giuliano), en Configuración → Usuarios y permisos. También cambia ahí el código de empresa.

**¿Puedo usarlo desde el celular?**
Sí. El menú se abre con el botón ☰. Está adaptado para pantallas chicas.

---

*Manual de usuario de VitalStock ERP. Ante dudas o errores que no figuran acá, contactá al administrador del sistema.*
