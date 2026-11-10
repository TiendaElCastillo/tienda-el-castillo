# Punto de guardado — Tienda El Castillo 🏰
**Fecha:** 9 de noviembre de 2026  
**Propósito:** continuidad del proyecto para retomar el trabajo sin perder decisiones ni contexto.

## 1. Estado técnico conocido
- Repositorio: `TiendaElCastillo/tienda-el-castillo`
- Rama: `main`
- Web publicada: https://tiendaelcastillo.github.io/tienda-el-castillo/
- Proyecto Supabase: `Tienda-El-Castillo`
- Referencia del proyecto: `kfllglkfncebpknnugnx`
- Región Supabase: `us-east-2`
- Arquitectura conocida: frontend HTML/CSS/JavaScript estático en GitHub Pages; Supabase para autenticación, datos y funciones.
- Último HEAD comprobado antes de este punto de guardado: `a7b39256dd8106bd7732bf3551acd9bd92f5d078`.
- Este documento es un registro de continuidad; no modifica la lógica de la tienda.

## 2. Preferencias y límites de trabajo
- El usuario trabaja principalmente desde un teléfono Android Redmi Note 13 y tiene acceso muy limitado a PC.
- Explicar las acciones de forma sencilla y paso a paso, sin exigir terminal ni ordenador.
- Priorizar opciones gratuitas y evitar contratar hosting, servidores o suscripciones si no son imprescindibles.
- Mantener la web ligera y rápida para conexiones lentas, cortes de internet y electricidad.
- No cambiar el logo original sin permiso.
- No añadir productos al catálogo aprobado sin autorización.
- No afirmar que algo está terminado, desplegado o probado si no se verificó.
- Distinguir entre revisión de código, despliegue confirmado y prueba visual/funcional real desde un teléfono.
- No publicar cambios de código en `main` sin autorización clara. Una petición explícita de implementar o guardar sí autoriza el alcance solicitado, pero no cambios adicionales.
- Mantener continuidad: consultar este documento y el historial antes de repetir tareas o tomar decisiones.

## 3. Objetivo comercial
Construir una tienda cubana de recargas y productos digitales bajo la marca **Tienda El Castillo 🏰**, sencilla, confiable, visualmente moderna y preparada para automatización futura con Central One.
- Empezar con operación manual segura y evolucionar a automatización.
- Propuesta competitiva: precios atractivos sin sacrificar margen; objetivo orientativo de margen 35% o más cuando sea viable.
- Clientes con cuenta, historial de pedidos y códigos únicos de seguimiento.
- Panel de administración para controlar catálogo, precios, pedidos y operaciones.
- Pagos previstos: transferencia CUP (Transfermóvil/EnZona), saldo móvil y USDT manual.
- La billetera interna tiene mínimo de depósito de 1 USD. Contexto más reciente: tasa de referencia 1160 CUP por USD y USDT 1:1; acreditación manual después de revisar y aprobar el depósito. Confirmar la tasa vigente antes de mostrarla o usarla.
- Central One: cuenta creada; integración API futura. Las credenciales nunca deben estar en el frontend; la integración debe realizarse desde una función segura del servidor.

## 4. Catálogo y reglas
- Catálogo aprobado: Free Fire y Mobile Legends: Bang Bang Global.
- Para MLBB hay una whitelist de 11 productos aprobados. IDs de diamantes conocidos: `[55, 172, 275, 565, 706, 2195, 3688]`, además de listas separadas de pases/membresías.
- No incorporar productos nuevos de MLBB sin autorización expresa.
- Blood Strike está en evaluación; investigar demanda antes de decidir si se incorpora.
- Las imágenes deben ser oficiales/originales y corresponder exactamente al producto, región y paquete. Evitar arte genérico o imágenes anticuadas.
- Mantener fallback de imágenes locales para conexiones deficientes.
- Los nombres, cantidades, regiones y precios visibles deben coincidir con el producto realmente entregado.

## 5. Cambios recientes conocidos
Historial de commits de referencia:
- `7679b4980ea7c175726dcf56b8bf94be358340f1` — diseño.
- `b7a4cadd9da7f8dd196b4f8b0446c6e3f4e3d88a` — imágenes del catálogo.
- `6363b1f28ff2e3d94009252f1c2e8f71a58340b1` — optimización del logo.
- `fb9cafefd80cce797f1a2a0315b1944811d9cadc` — fallback local de imágenes.
- `66e56345013bcadf14d27e57c21e3e29bef4e92c` — logout, previews públicos, guards de autenticación y copia.
- `e313636ea2461b2b5a425502ac0e54f836becd6b` — seguimiento de pedidos y regiones de juegos.
- `fe09ad30f80103ba39678864eaba6d6bb408a52f` — pulido visual general.
- `139acbf9ac38a1c4df1282692c9416dd7e128b39` — buscador y tarjetas destacadas.
- `5a3594eef481756737528c0a787acd22e7faf3b9` — correcciones de búsqueda móvil y grid de destacados.
- `c14b49f013e36f150efb86f0d5b08547d97c128e` — microdetalles visuales en `index.html`.
- `9f79347259f4c315f137c0259aa6c3330f7b8001` — armonización CSS del panel admin.
- `5c8d696b848ed5f06da277e3275eca7209e3bff0` — shimmer del catálogo.
- `a7b39256dd8106bd7732bf3551acd9bd92f5d078` — respeta `prefers-reduced-motion` para el shimmer.

### Último pulido visual
- Jerarquía y acentos visuales de títulos de sección.
- Tarjetas, sombras y estados hover refinados.
- Botones con gradiente azul sobrio.
- Insignias de disponibilidad y región.
- Presentación de precios.
- Checkout stepper y navegación inferior con estado activo más claro.
- Footer, estados vacíos y toast de alerta de pago refinados.
- Brillo sutil en espacios de carga del catálogo.
- Respeto a `prefers-reduced-motion`.
- CSS del panel admin armonizado con la tienda pública.
- Sin librerías externas ni imágenes pesadas añadidas; sin cambios intencionales en lógica comercial o catálogo.

### Buscador y destacados
En `index.html` se conoce esta funcionalidad:
- `productSearch`, `clearProductSearch` y `productSearchMeta`.
- Búsqueda por tokens y sinónimos: FF → Free Fire; MLBB/ML → Mobile Legends; diamond/diamonds → diamantes; pass/passes → pase; weekly → semanal; membership → membresía; giftcards → gift card.
- Busca en juego, nombre, descripción, cantidad, región del proveedor y métodos de pago.
- Categorías FF/MLBB y gift cards.
- Excluye paquetes inactivos, ocultos o level-up.
- Ranking por coincidencia exacta, substring, juego y tokens.
- Botón para borrar búsqueda y contador de resultados.
- Tarjetas destacadas con grid responsive: 3 columnas en escritorio, 2 en tamaño intermedio y 1 en móvil.
- Revisar esta lógica antes de modificarla para no reintroducir errores.

## 6. Incidente crítico que debe guiar las próximas pruebas
Se reportó una compra desde el teléfono de un familiar: el cliente introdujo su ID de jugador, la verificación no cargó y aun así pudo continuar al flujo de pago y transfirió dinero. Esto no debe volver a ocurrir.
**Regla obligatoria:** si el ID no está verificado de forma válida, el proceso debe bloquear continuar, crear instrucciones de pago o confirmar el pedido. Un error de red, timeout, respuesta vacía o fallo del proveedor nunca debe tratarse como verificación exitosa.

## 7. Próxima tarea acordada: auditoría técnica del proceso de compra
Comenzar por recuperar el estado real de `main` y revisar el código actual, sin asumir que los archivos siguen iguales a los commits históricos.
Mapear el recorrido completo:
1. Selección de juego y paquete.
2. Introducción y verificación del ID y región.
3. Cálculo y presentación del precio.
4. Selección del método de pago.
5. Creación del pedido y código único.
6. Instrucciones de pago y envío de comprobante.
7. Revisión y aprobación manual.
8. Entrega/recarga.
9. Actualización del estado, aviso e historial del cliente.

### Lista de seguridad para auditar
- Un ID sin verificación válida nunca puede avanzar.
- Validar en servidor producto, región, cantidad y precio; no confiar en valores enviados por el navegador.
- Evitar pedidos duplicados por doble toque, reintentos, recarga de página o mala conexión.
- Diferenciar claramente pedido creado, pago pendiente de revisión, pago aprobado, procesando, entregado, rechazado y reembolsado si aplica.
- Un comprobante enviado o una revisión pendiente nunca equivalen a pago confirmado.
- Revisar RLS y permisos: el cliente solo consulta sus pedidos y crea pedidos propios; solo el administrador puede cambiar estados sensibles y aprobar pagos.
- Guardar trazabilidad de cambios administrativos.
- Diseñar reintentos idempotentes para evitar recargas dobles.
- Gestionar timeout/offline sin perder pedidos ni afirmar falsamente que se pagó.
- Mostrar instrucciones exactas de pago y confirmar que el destino corresponde al método seleccionado.
- No exponer claves o secretos de Central One en JavaScript público.
- Preparar integración futura desde Edge Function/servidor con validación, idempotencia y registro de respuesta.

## 8. Otras prioridades después de la auditoría
1. Corregir los hallazgos críticos de seguridad y fiabilidad.
2. Mejorar estados, seguimiento e historial del cliente.
3. Probar el flujo real desde más de un teléfono Android, incluidos casos de mala conexión.
4. Fortalecer el panel admin: pedidos, pagos pendientes, precios, catálogo, alertas y registro de operaciones.
5. Optimizar rendimiento, recuperación ante cortes y mensajes de error.
6. Integrar Central One de forma segura cuando el flujo manual sea fiable.
7. Añadir promociones configurables y otras funciones comerciales.

## 9. Supabase: precauciones
- Antes de cualquier tarea que toque Supabase, leer la skill `skills://plugins/supabase/supabase/skill.md`.
- Si se revisan o escriben SQL, tablas, políticas o índices, leer también `supabase-postgres-best-practices`.
- Un cambio previo conocido corrigió permisos de `public.products`: SELECT para anon/authenticated e INSERT/UPDATE/DELETE para authenticated, conservando las políticas RLS existentes. No asumir que esos permisos son suficientes para el sistema actual: auditar políticas completas y privilegios reales antes de cambiar nada.
- No ejecutar migraciones o cambios de producción sin explicar el alcance y verificar el estado actual.

## 10. Primera acción al retomar
1. Leer este documento.
2. Consultar el HEAD real de `main` y los archivos actuales.
3. Leer la skill de Supabase si se va a inspeccionar esa parte.
4. Empezar la auditoría técnica del checkout, priorizando el bloqueo de ID no verificado.
5. Presentar hallazgos por severidad (crítico/alto/medio/bajo), explicar riesgos y proponer correcciones sin alterar catálogo ni precios aprobados.
6. Verificar cada corrección y comunicar con precisión qué se comprobó y qué no.

**Nota de verificación:** el HEAD `a7b39256dd8106bd7732bf3551acd9bd92f5d078` fue consultado en GitHub antes de crear este documento. En la última revisión histórica no se pudo confirmar el resultado de GitHub Actions ni una inspección visual real desde un teléfono; por tanto, el despliegue de Pages debe verificarse al retomar.
