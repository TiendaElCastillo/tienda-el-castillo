# Tienda El Castillo — revisión de continuidad, seguridad y presentación

**Fecha:** 13 de noviembre de 2026  
**Rama base:** `main` en `197aa8330683c43735f28ae08f9e026b2e0c8368`  
**Rama de este informe:** `work/continuity-audit-20261113`  
**Supabase:** `Tienda-El-Castillo` (`kfllglkfncebpknnugnx`)

## Resumen

- Supabase está `ACTIVE_HEALTHY`; el asesor de salud no devuelve hallazgos.
- El acceso obligatorio se conserva en el código y en los permisos de lectura del catálogo/métodos de pago.
- Se confirma un problema de integridad en la creación de pedidos: campos internos de Central One aún pueden venir del cliente y no se limpian en el trigger actual.
- La billetera de clientes **no está desactivada en el estado actual**: la interfaz y las rutas de depósito/compra siguen presentes y tienen permisos/RPC activos. No se modificó nada.
- No hubo navegador visual disponible. No se hicieron pruebas visuales ni flujos de compra reales.
- No se modificaron `main`, Supabase, precios, permisos, estados, datos ni funciones; no se enviaron pedidos a Central One.

## Repositorio y ramas

- `main`: commit `197aa8330683c43735f28ae08f9e026b2e0c8368` (10 nov 2026).
- `work/redesign-audit-20261106`: commit `6a043b212a072f665e61b9e639d25353363f1982`; está **19 commits por delante y 293 por detrás** de `main`. No es seguro fusionarla ni continuar desde ella sin reconstruirla.
- Otras ramas de trabajo también están atrasadas: `visual-refresh-2026-11-09` (67 detrás) y `ux/experience-safety-improvements` (219 detrás).
- La protección de rama de `main` aparece desactivada y sin comprobaciones obligatorias.
- El informe del 6 nov y la migración antigua siguen en la rama de trabajo, no en producción. La migración antigua no debe aplicarse tal cual: apunta a `public.validate_order_request()`, mientras la función actual está en `private`, y usa el nombre antiguo de la billetera.

## Acceso obligatorio

Comprobación estática positiva:
- El formulario de acceso/registro aparece en el HTML inicial y el contenedor `#store` empieza oculto.
- `start()` consulta la sesión; sin sesión muestra autenticación y oculta tienda, cabecera y navegación.
- `showView()` bloquea las vistas de tienda si `currentUser` no existe.
- Los roles `anon` no tienen permiso de lectura sobre `products` ni `payment_methods`; los permisos de lectura de catálogo/métodos están limitados a usuarios autenticados y las políticas RLS siguen activas.

Esto confirma el diseño del control, no sustituye una prueba real de registro/login.

## Hallazgo prioritario: metadatos de Central One en pedidos

La tabla `orders` conserva INSERT para `authenticated`, y los permisos de columna permiten insertar campos como `central_one_order_id`, `central_one_idempotency_key`, `central_one_submitted_at`, `central_one_status` y `central_one_response`.

El trigger actual `private.validate_order_request()` recalcula producto/precio y limpia varios campos de pago, pero **no limpia esos campos internos de Central One**. El trigger `private.enforce_provider_player_validation()` valida y consume el token de jugador, pero tampoco los limpia.

Además, `public.claim_central_one_order()` devuelve `already_submitted` inmediatamente cuando `central_one_order_id` ya tiene valor. Por tanto, un cliente autenticado podría insertar metadatos falsos y bloquear o falsear la fase de envío del pedido.

La propuesta del 6 nov pretendía limpiar esos campos, pero no está aplicada y quedó obsoleta frente al esquema actual. Requiere una migración nueva, adaptada a la función `private` actual y pruebas en una base de desarrollo antes de cualquier aplicación en producción.

## Hallazgo prioritario: billetera de clientes

El estado actual contradice la instrucción de mantenerla desactivada:
- `index.html` contiene una billetera personal, asistente de depósitos e historial.
- El checkout ofrece `Saldo de Tienda El Castillo` a usuarios autenticados cuando el producto tiene precio USDT; los 58 productos publicados tienen precio USDT.
- `wallet_deposits` permite INSERT de las columnas necesarias a `authenticated`, con política RLS para depósitos propios pendientes.
- `public.create_wallet_order()` (cinco argumentos) está disponible para `authenticated` y llama a `private.create_wallet_order()`, que es `SECURITY DEFINER` y realiza el cargo del saldo.
- La base consultada tiene 0 depósitos y 0 movimientos de billetera; eso no significa que el flujo esté deshabilitado.

No se reactivó ni modificó la billetera. Hace falta una decisión explícita del propietario para deshabilitar de forma coordinada la interfaz, las funciones y los permisos sin afectar pedidos normales.

## Seguridad Supabase

- Estado del proyecto: `ACTIVE_HEALTHY`; PostgreSQL 17.11.
- RLS está habilitado en las tablas revisadas de `public`, `private` y `storage`.
- `payment-proofs` es privado; límite 5 MB; JPEG, PNG y WebP.
- `player_id_validations` tiene RLS sin acceso directo de cliente; el trigger valida usuario, producto, región, hash del ID, expiración y consumo de un solo uso.
- Los campos de coste de productos no tienen permiso SELECT para el cliente; el catálogo se limita a ofertas publicadas/disponibles.
- Las funciones públicas `claim_central_one_order`, `finish_central_one_order` y `refund_wallet_order_after_provider_refund` están limitadas a `service_role`; `rls_auto_enable` queda para `postgres`. Los helpers privados incluyen funciones SECURITY DEFINER y deben mantenerse bajo revisión de permisos.
- Edge Functions activas: `central-one-read` v6 (JWT), `central-one-sync` v8 (sin JWT, pero exige `x-sync-token` y valida el token mediante RPC), `central-one-player-validate` v7 (JWT) y `central-one-order` v20 (JWT y contexto de administrador).
- El HTML público no contiene `service_role` ni `CENTRAL_ONE_API_KEY`; la clave pública anon de Supabase sí aparece, como corresponde. Las claves privadas se leen desde variables de entorno de Edge Functions.
- `pg_net` está en el esquema `extensions`.
- Security Advisor: una advertencia, protección contra contraseñas filtradas desactivada. No se cambió. [Documentación de Supabase](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
- Performance Advisor: 18 índices marcados como no usados (INFO); no se borró ninguno.

## Service Worker, rendimiento y accesibilidad

- `sw.js` de `main` usa caché `shell-v116`.
- La navegación usa red primero y conserva una copia local como respaldo. Autenticación, lecturas/escrituras de base de datos, pedidos, comprobantes y proveedor quedan fuera de caché; se permite caché para el SDK de Supabase y recursos gráficos estáticos.
- El HTML principal pesa 432,754 bytes. No se midieron tiempos reales ni rendimiento bajo limitación de red.
- Hallazgo de accesibilidad: el viewport usa `maximum-scale=1` y `user-scalable=no`, lo que impide ampliar la página con gestos. Propuesta: retirar esas restricciones y probar en móvil.
- El CSS contempla `focus-visible` y `prefers-reduced-motion`, pero no se verificó con lector de pantalla ni navegación real por teclado.

## Migraciones: diferencia entre repositorio y base de datos

La base registra 61 migraciones; el árbol de `main` contiene 57 archivos. No están en el repositorio principal estas tres migraciones del 12 nov:
- `20261112142116_hide_payment_and_provider_details_from_public_catalog`
- `20261112142617_limit_public_payment_method_columns`
- `20261112150037_require_authenticated_catalog_and_payment_reads`

También hay diferencias de nombre/versión entre algunos archivos y el historial aplicado de 9–10 nov. No se reconstruyeron ni reejecutaron migraciones; hay que reconciliar el historial y los archivos fuente antes de futuras publicaciones.

## Configuración leída (sin cambios)

- Métodos activos: Transferencia CUP, Saldo móvil y USDT.
- Precios: tasa 1160 CUP/USD; 360 unidades de saldo móvil; coste configurado 1200 CUP; margen 35%; redondeo 10 CUP.
- Catálogo: 485 productos, 394 activos y 58 publicados/disponibles.
- Pedidos existentes: 1; depósitos de billetera: 0; movimientos de billetera: 0.

## Pendientes antes de cualquier publicación

1. Corregir y probar el reset de metadatos internos de Central One en una base de desarrollo.
2. Resolver explícitamente el estado deseado de la billetera y deshabilitarla de forma coordinada si esa sigue siendo la decisión.
3. Reconciliar las tres migraciones del 12 nov y los nombres/versiones discrepantes con los archivos del repositorio.
4. Retirar la restricción de zoom móvil en una rama de trabajo actualizada.
5. Revisar la protección de contraseñas filtradas y la protección de `main`.
6. Probar visualmente y funcionalmente registro, checkout, pagos, comprobantes y administración en móvil y escritorio. No se hizo esta semana.

**Resultado:** informe documental aislado. Sin cambios de aplicación, migraciones, permisos, precios, datos ni despliegues.
