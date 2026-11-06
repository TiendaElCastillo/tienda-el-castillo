# Tienda El Castillo — auditoría de seguridad y diseño
**Fecha:** 6 de noviembre de 2026  
**Rama de trabajo:** `work/redesign-audit-20261106`  
**Producción:** la rama `main` y la web publicada no se modificaron durante esta revisión.

## Resumen ejecutivo
Se preparó una nueva capa visual premium y una propuesta de endurecimiento de creación de pedidos. Todo permanece aislado en esta rama. No se aplicaron migraciones a Supabase ni se enviaron pedidos a Central One.

## Diseño preparado
- Identidad visual en azul noche, dorado suave y fondo marfil.
- Cabecera, hero, acciones, tarjetas, precios, navegación inferior, formularios y pie de página con estilo coherente.
- Ajustes responsive para teléfono y tablet.
- Sin fuentes, imágenes ni librerías remotas nuevas.
- Se añadieron únicamente reglas CSS a `index.html`; los cuatro bloques JavaScript permanecen idénticos al original.
- Service Worker elevado a v60 solo en esta rama para invalidar la caché al publicarse.

### Verificaciones estáticas
- La diferencia de `index.html` frente a `main` es solo una nueva hoja de estilos.
- Los bloques JavaScript son idénticos.
- Llaves CSS balanceadas.
- Los recursos sensibles (autenticación, pedidos, comprobantes y llamadas a proveedores) siguen siendo solo de red y no se guardan en caché.
- Cambios todavía no publicados ni comprobados visualmente en el teléfono.

## Seguridad revisada
- RLS está habilitado en las tablas principales expuestas.
- Los pedidos del cliente se limitan a su propia cuenta; el cliente no tiene permiso de UPDATE/DELETE directo en `orders`.
- El disparador de creación recalcula el precio desde el producto activo y fuerza estado pendiente.
- La validación de jugador de Central One comprueba un token ligado al usuario, producto, región e ID, con vencimiento y consumo de un solo uso.
- El bucket `payment-proofs` es privado y admite imágenes JPEG, PNG y WebP hasta 5 MB.
- `submit_payment_proof` comprueba propietario, estado, método de pago, referencia/importe, ruta y existencia del archivo.
- `admin_update_order_status` requiere administrador y restringe los estados/transiciones permitidos.
- Las funciones `central-one-order` y `central-one-player-validate` tienen verificación JWT. La primera exige contexto de administrador. La sincronización de catálogo no usa JWT, pero exige un token privado en la cabecera y vuelve a validarlo en RPC.
- No se encontró el texto de una clave `service_role` ni `CENTRAL_ONE_API_KEY` en el HTML público. La clave anon de Supabase es la clave pública prevista para el cliente.

## Hallazgo de integridad preparado para corregir
El disparador actual de inserción de pedidos restablecía precio, estado, referencia y comprobante, pero no todos los campos internos de confirmación/presentación al proveedor. Un cliente podía intentar enviar un `central_one_order_id` o una clave de idempotencia falsa. Como `claim_central_one_order` consulta primero si existe un ID del proveedor, esos datos podían provocar que el proceso informara que un pedido ya había sido enviado y bloquear una recarga.

Se preparó, solo en esta rama, la migración:
`supabase/migrations/20261106230000_harden_client_supplied_order_metadata.sql`

La migración restablece los campos de confirmación y seguimiento de Central One al insertar un pedido. Conserva deliberadamente `player_id_validation_token` para que el siguiente disparador valide y consuma el token real. **No está aplicada en producción y requiere pruebas antes de ejecutarse.**

## Decisiones de seguridad: no cambiar a ciegas
- Supabase advierte sobre `pg_net` en el esquema `public`, pero el trabajo programado de sincronización utiliza `net.http_post`. No mover la extensión sin migrar y probar primero la tarea.
- Supabase advierte sobre dos funciones `SECURITY DEFINER` ejecutables por `authenticated`. Sus cuerpos hacen controles de propietario/administrador; no revocar permisos sin revisar las llamadas del sitio.
- La protección contra contraseñas filtradas aparece desactivada en Auth. Revisar la opción en el panel y el plan antes de activarla.
- Algunas funciones privadas del proceso de sincronización se pueden ejecutar con el rol anon, pero exigen el token secreto antes de escribir o cambiar el catálogo. No retirar esos permisos sin rediseñar la sincronización.
- Los avisos de claves foráneas sin índice y de índices no usados son recomendaciones de rendimiento; no borrar índices automáticamente.
- La billetera de clientes fue desactivada deliberadamente por una migración anterior (`temporarily_disable_customer_wallet`). No se deben conceder permisos para reactivarla sin una decisión expresa y pruebas separadas.

## UX pendiente importante
Cuando un visitante no tiene sesión, la página abre el formulario de inicio de sesión/registro y no el catálogo público. A futuro se puede estudiar una experiencia donde el visitante vea juegos y paquetes antes de iniciar sesión, manteniendo obligatoria la cuenta al realizar el pedido. Este cambio afecta al flujo de autenticación y checkout; no se incluyó en la capa CSS.

## Pruebas pendientes antes de publicar
1. Ver el diseño en un teléfono real (ancho pequeño, tablet y escritorio si está disponible).
2. Comprobar navegación, botones, tarjetas, formularios, checkout y panel admin.
3. Probar inicio de sesión, registro, validación de jugador y envío de comprobante con una cuenta de prueba, sin generar compras reales.
4. Probar la migración de metadatos en una base de desarrollo antes de aplicarla a producción.
5. Mantener las pruebas reales de compra Central One aplazadas hasta que el propietario las solicite.

**Regla:** no fusionar ni aplicar cambios solo porque pasen una revisión estática. Primero revisar visualmente y probar los flujos afectados.

## Segunda pasada visual — 6 de noviembre de 2026
Se añadió una segunda capa CSS, todavía en la misma rama de trabajo:
- Registro e inicio de sesión: jerarquía más clara, campos y foco visibles, botones y tabs más coherentes con la identidad azul noche/dorado.
- Checkout: pasos, opciones de pago, resumen, comprobante, consentimiento y mensajes con una presentación más unificada.
- Visor de comprobantes: cabecera oscura, referencia de transferencia destacada y fondo de imagen neutral.
- Administración: navegación, filtros, tarjetas de pedidos, controles y mensajes con el mismo lenguaje visual.
- Service Worker actualizado a v61 para que, al publicar, los teléfonos descarguen la nueva portada.

La petición del propietario es mantener el acceso obligatorio. No se hizo público el catálogo ni se modificó el requisito de iniciar sesión/crear cuenta para acceder. La validación de sesión, registro, login y cierre de sesión permanece intacta.

### Comprobación de esta segunda pasada
- Los cuatro bloques JavaScript del `index.html` son idénticos a `main`.
- El contenido añadido en esta pasada es CSS; no se cambiaron las funciones de registro, login, checkout, pedidos ni administración.
- CSS balanceado por conteo de llaves; no se añadieron fuentes, librerías ni imágenes externas.
- Las llamadas de autenticación, base de datos, comprobantes y proveedor siguen fuera de caché (solo red).
- La rama sigue sin fusionar ni publicar. La verificación visual en navegador/teléfono continúa pendiente.
