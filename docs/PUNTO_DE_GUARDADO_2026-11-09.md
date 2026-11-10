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



## Actualización de continuidad — 10 de noviembre de 2026
Últimas correcciones publicadas después del punto de guardado original:
- `78ba859de0a56dde6084593145b71b9c2e68db11` — evita el desplazamiento horizontal de la página en móvil y corrige el arte/las imágenes de las tarjetas de producto.
- `cdddbebb57dff963e269fe367c3df8d3e93c1387` — añade reloj visible para el tiempo de espera de pedidos y evita controles antifraude inapropiados en el panel.
- `45881262949507129ea896c83c96f28fc7519068` — corrige el contraste de botones secundarios del panel admin (texto visible sobre fondos claros).
- `9d81f00694adf109911a09ef6538a4ce0306dbb5` — renueva caché del service worker a `el-castillo-shell-v108` y actualiza CSS admin a `?v=30`.
- `ad2c907504d8632801fe429fcc5f2869952f1604` — mantiene el reloj durante revisión del pago y durante la etapa de recarga, con cronometraje de cada etapa desde su propio evento.

### Reloj de seguimiento del cliente
- En `payment_review`: muestra “Tiempo en revisión”, cuenta desde el evento de “Comprobante recibido” (si falta ese evento, usa `created_at`).
- En `processing`: cambia a “Tiempo de recarga” y cuenta desde el evento “Pago confirmado” (con los campos de confirmación como respaldo).
- Muestra “Acreditación: 1–30 min” como orientación, no como garantía ni confirmación automática del pago.
- Cuenta minutos y segundos cada segundo.
- A partir de 30 minutos muestra aviso de demora y recomienda escribir desde Mensajes; no indica que se haya completado el pago o la entrega.
- Se oculta al pasar a entrega completada o a un estado final de incidencia.
- Se verificó mediante compilación de scripts JavaScript y pruebas de la generación del contador para revisión, recarga y entrega completada.

### Ajuste del panel antifraude y causa encontrada
- El pedido de prueba que se revisó estaba asociado a un perfil cuyo rol es `admin`, no `customer`. Por eso la RPC antifraude rechazó correctamente la advertencia con “No se encontró una cuenta de cliente válida”.
- El error era de interfaz: el panel mostraba controles de cliente para el perfil de administración.
- Ahora el panel consulta `profiles(id, role)` y solo presenta las acciones de advertencia/bloqueo cuando el titular tiene rol `customer`.
- Para cuentas `admin` muestra una nota explicativa y oculta las acciones antifraude de cliente. Si no se puede verificar el rol, también oculta esas acciones por seguridad.
- No se debilitó la función RPC ni se autorizó bloquear/advertir cuentas administrativas.
- Se añadieron estilos específicos para que los botones secundarios y desactivados del panel sigan teniendo contraste y se lean sobre fondos claros.
- No se modificaron tablas, políticas RLS, funciones SQL, precios, catálogo ni estados de pedidos.

### Verificación de publicación
- El workflow de Pages asociado a `9d81f00694adf109911a09ef6538a4ce0306dbb5` terminó con éxito en build y deploy.
- El commit `ad2c907504d8632801fe429fcc5f2869952f1604` amplía el contador por etapa; su workflow se debe revisar al retomar para confirmar el último despliegue.
- La inspección visual directa desde el Redmi sigue pendiente. Tras actualizar la página, pedir una captura de “Mis pedidos” en revisión/recarga y otra del panel admin en un pedido de un cliente real.


## Auditoría de seguridad de envíos a Central One — 10 de noviembre de 2026
Objetivo: comprobar que una compra de prueba, un pedido rechazado o una solicitud no autorizada no pueda consumir saldo del proveedor.

### Resultado
- No se encontró un envío automático desde el frontend: la única llamada `requestCentralOneOrder("submit", orderId)` está dentro de `authorizeCentralOneOrder()`, que exige perfil admin y una confirmación explícita del navegador titulada “AUTORIZAR RECARGA REAL”.
- La confirmación explica que se creará una orden real y se usará saldo prepago. También exige verificar pago, paquete, región e ID.
- La Edge Function `central-one-order` valida el token contra Supabase Auth y comprueba el rol `admin` en `profiles` antes de aceptar acciones.
- La función SQL `claim_central_one_order` exige estado local `processing`; para pagos directos exige comprobante, fecha de confirmación y que el administrador autenticado sea quien confirmó el pago. Para billetera exige pago registrado.
- También exige validación del jugador vigente, producto/proveedor activo y stock, región coincidente y esquema de destino admitido.
- La función de claim solo puede ejecutarse por `service_role`; se confirmó que `anon` y `authenticated` no tienen permiso EXECUTE. La finalización también queda restringida a `service_role`.
- La Edge Function usa una clave de idempotencia estable por pedido y envía `Idempotency-Key` al proveedor; los reintentos no crean deliberadamente una nueva clave.
- Los errores de preflight de catálogo, margen o saldo detienen la solicitud antes del POST y quedan marcados como bloqueados localmente.
- La acción de refrescar consulta el estado del pedido existente; no es el flujo de creación.

### Estado real de los pedidos consultados
- Pedido de prueba `EC-EF361F02F9`: `rejected`, `central_one_status=not_submitted`, sin ID de orden Central One, sin request ID y sin pago confirmado. No hay indicio de que se haya enviado o consumido saldo.
- Otros pedidos recientes consultados también no muestran órdenes del proveedor registradas.
- Recuento actual en base de datos al auditar: 0 pedidos esperando autorización, 0 órdenes Central One creadas y 0 envíos ambiguos (`submitting`/`unknown`).

### Conclusión y riesgo residual
- El rechazo de un pedido de prueba lo deja fuera de la condición `processing`; por tanto, la función de claim lo rechaza y no llama a Central One.
- Un pedido solo puede usar saldo del proveedor después de que un administrador pulse el botón de autorización real y acepte la confirmación explícita, además de cumplir las validaciones de pago y jugador.
- Riesgo residual: el sistema no distingue semánticamente “pedido de prueba” de “pedido real”. Si un administrador confirma manualmente como pagado un pedido de prueba y luego autoriza conscientemente la recarga, el backend lo trataría como real. Se recomienda valorar un interruptor general de “Bloquear envíos reales a Central One” para las sesiones de pruebas; debe estar activado por defecto cuando se quiera probar y solo el administrador puede desactivarlo antes de procesar pedidos reales.
- No se realizaron llamadas POST a Central One, no se crearon pedidos de proveedor, no se alteró saldo, no se cambiaron datos ni estados de pedidos y no se modificaron migraciones durante esta auditoría.
- Supabase Security Advisor: un aviso pendiente de nivel WARN: “Leaked Password Protection Disabled”. Activar protección contra contraseñas comprometidas desde Auth > Password Security cuando se continúe la configuración.


## Renovación visual mobile-first — 10 de noviembre de 2026
Objetivo solicitado: que la tienda se vea como una plataforma de recargas profesional y esté diseñada primero para compradores que navegan desde teléfonos.

### Cambios publicados en la interfaz
- `310305ca65e3bade74a20b5b4dda001aa33cf066` — nueva portada mobile-first: mensaje principal más corto, CTA principal, acceso a «Cómo comprar», compartir tienda, barra informativa con los dos juegos y beneficios resumidos.
- `b7b73c204dc645095032f2f5074e40d4f5cedb74` — refinamiento móvil de acceso/registro, selección de juegos, detalle del juego, métodos de pago y checkout.
- `aef96f977334f1e184ca1609b2ad0b48ec955ea1` — ajuste final para alinear «Cómo comprar» y «Compartir» en dos botones equilibrados en el banner móvil.
- `8fdf27a90da66ca03679f62220f99038e5025864` — actualiza caché del service worker a `el-castillo-shell-v109` para refrescar la versión de la tienda en dispositivos móviles.

### Dirección visual
- Conserva el logo original del castillo.
- Paleta azul noche, índigo y violeta con acentos lavanda, superficies claras y tarjetas suaves.
- La portada comunica rápidamente que se ofrecen Free Fire y Mobile Legends: Bang Bang Global.
- El catálogo prioriza dos tarjetas de juego en móvil; los paquetes destacados mantienen precios por método y un botón de acción amplio.
- Se unificó la presentación del acceso, catálogo, detalle del juego y checkout para evitar que la compra parezca una página distinta.
- Se reforzaron tamaños táctiles, márgenes y adaptación para pantallas de 320–430 px; también hay ajustes específicos para móviles muy estrechos de hasta 340–360 px.
- Se conservaron la búsqueda, los IDs del DOM, handlers, checkout, pagos, validación de jugador, orden de productos, regiones, panel admin y toda la lógica de negocio.
- No se añadieron dependencias externas, bibliotecas ni imágenes pesadas; se reutilizan imágenes locales existentes.

### Verificaciones realizadas
- Los scripts JavaScript inline pasaron comprobación sintáctica.
- Las etiquetas `<style>` están equilibradas.
- Los dos nuevos bloques CSS están balanceados en llaves.
- Se verificó que permanecen los IDs clave de portada, juegos, checkout, búsqueda y navegación.
- La publicación de la portada inicial tuvo build y deploy exitosos para `310305ca65e3bade74a20b5b4dda001aa33cf066`; los cambios posteriores actualizaron la portada de nuevo y deben comprobarse en el workflow final correspondiente.
- Pendiente: inspección visual real desde un teléfono Android de 320–430 px. El código no permite confirmar por sí solo cómo se ve en la pantalla física.

### Próxima revisión manual recomendada
1. Abrir la página en el teléfono y recargarla con conexión activa para recibir la nueva versión.
2. Revisar encabezado, banner y botones.
3. Comprobar que ambas tarjetas de juegos tienen buena escala e imágenes.
4. Abrir un paquete de Free Fire y uno de Mobile Legends Global.
5. Comprobar métodos de pago, formulario de ID y resumen de compra sin enviar un pago real.
6. Abrir «Mis pedidos» y el panel admin, verificando que botones y textos sigan visibles.
