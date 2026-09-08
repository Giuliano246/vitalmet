# VitalStock — interfaz operativa

## Dirección

Espacio de trabajo para administración y producción metalmecánica. Se conserva la identidad Hierro y Ámbar en oscuro y Oficina Técnica en claro. La prioridad es localizar tareas, leer registros y completar formularios con menos esfuerzo.

## Implementación

Los tokens de color y las reglas originales están en index.html. ui-workspace.css se carga después y define la capa compartida: navegación, encabezados, tablas, formularios, modales y adaptación móvil. No agregar dependencias ni CDNs para extender este sistema.

- IBM Plex Sans para interfaz; IBM Plex Mono para códigos y cifras.
- Barra superior con ubicación actual, búsqueda existente y selector de densidad.
- Navegación lateral de 232 px; cajón móvil a partir de 768 px.
- Títulos de 26 px en escritorio y 23 px en móvil; campos de 16 px en móvil para evitar zoom al enfocar.
- Tablas con encabezados fijos y desplazamiento propio. Filas de densidad cómoda (12 px verticales) o compacta (7 px), persistida en vitalstock-density.
- Pestañas horizontales desplazables; subpestañas con distribución flexible.
- Colores semánticos, foco visible, preferencia de movimiento reducido y permisos existentes conservados.

## Verificación y límites

267 tests existentes aprobados y sintaxis del script validada. Revisión visual local de inventario vacío en escritorio y móvil y formulario de barra en modo claro; sin datos ni escrituras de producción. Detector de ui-workspace.css sin hallazgos. Revisión directa, no independiente.

Esta entrega modifica la interfaz compartida de index.html; planta.html conserva su interfaz especializada. No constituye una auditoría completa de todos los flujos ni de accesibilidad. Antes de publicar, verificar con sesión real las pantallas de alta densidad y los permisos de cada rol. No se realizó deploy.
