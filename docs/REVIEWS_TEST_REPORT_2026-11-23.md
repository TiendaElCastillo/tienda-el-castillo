# Reseñas verificadas — informe de pruebas del entorno aislado

**Fecha:** 23 de noviembre de 2026  
**Repositorio:** `TiendaElCastillo/tienda-el-castillo` (taller de desarrollo)  
**Supabase:** `Tienda-El-Castillo-Pruebas` · `kmotmgpzmeooznyymcxl`  
**Producción:** sin cambios de base de datos ni de código de reseñas durante estas pruebas.

## Decisión de producto

- Sin foro, chat, respuestas ni comunicación entre clientes.
- Una valoración de 1 a 5 estrellas y un comentario por pedido elegible.
- Elegibilidad basada en el pedido del mismo cliente, cuyo estado de tienda y estado confirmado por el proveedor sean `completed`.
- Publicación automática después de la validación del servidor.
- Mostrar el nombre registrado (`profiles.full_name`) en la opinión; pedir consentimiento explícito antes de enviarla.
- No mostrar correo, UID/Zone ID, teléfono, referencia de pago, folio ni datos de comprobantes.
- Administración puede ocultar, restaurar o retirar una opinión; solo las visibles y no retiradas cuentan en el promedio.
- Sin enlaces ni datos de contacto dentro de los comentarios.

## Modelo mínimo preparado en la base de pruebas

- `public.profiles`: perfil ficticio de prueba con nombre registrado y rol.
- `public.orders`: estructura mínima ficticia para probar propiedad y estados de pedido.
- `public.store_reviews`: tabla de opiniones, estrella 1–5, comentario, nombre copiado del perfil, juego/paquete copiados del pedido, aceptación del nombre público y controles internos de moderación.
- `public.store_reviews_public`: vista pública que excluye `user_id`, `order_id`, correo, teléfono y comprobante.
- `public.store_review_summary` y `public.store_review_summary_by_game`: conteo y media calculados exclusivamente sobre la vista de opiniones visibles.
- Trigger privado `private.validate_store_review_submission()`: comprueba sesión, consentimiento, longitud, enlaces/contactos, pedido propio y completo, nombre registrado y límite de frecuencia.
- RPC de consulta privada `my_store_review_status`.
- RPC de Administración `admin_list_store_reviews` y `admin_moderate_store_review`.
- La lógica privilegiada vive en `private`; las funciones expuestas son envoltorios `SECURITY INVOKER` y verifican permisos mediante ayudantes privados.

## Pruebas ejecutadas

| Caso | Resultado |
|---|---|
| Pedido propio con ambos estados `completed` | Permitió publicar |
| Nombre público | Copiado por el trigger desde el perfil |
| Pedido pendiente | Rechazado |
| Pedido fallido | Rechazado |
| Pedido de otro cliente | Rechazado |
| Consentimiento ausente | Rechazado |
| Lectura directa de columnas privadas | Denegada |
| Cliente consulta bandeja de Administración | Denegado |
| Comentario con teléfono | Rechazado |
| Comentario con enlace/correo | Protegido por validación del trigger |
| Administración consulta su bandeja | Permitido |
| Administración oculta una opinión | Deja de aparecer en la vista pública |
| Administración restaura una opinión | Vuelve a aparecer |
| Administración retira una opinión | Deja de aparecer y no cuenta en el resumen |
| Promedio por juego | Se calcula solo con opiniones visibles |

Los datos de estas pruebas son ficticios y se guardaron solo en Supabase de pruebas. No son opiniones auténticas ni se muestran en la tienda real.

## Restricciones y asuntos no terminados

- Este esquema es una **base mínima para las pruebas de reseñas**, no una réplica del esquema de producción.
- La interfaz de cliente, las estrellas, el consentimiento visible, la lista pública y la pestaña de Administración aún no están integrados.
- El taller de GitHub es una versión anterior del front-end; no se debe copiar entero al repositorio de producción.
- No hay cuentas reales de clientes ni contraseñas de clientes en el entorno de prueba.
- No hay funciones del proveedor, tareas programadas ni secretos del proveedor configurados en la base de pruebas.
- Se detectó una migración histórica del taller que programa una sincronización hacia la URL de producción. Debe permanecer excluida del proyecto de pruebas.
- Todavía no se creó ni aplicó ninguna migración de reseñas en el Supabase de producción.
- Antes de producción se debe adaptar el SQL a las tablas, RLS, roles, estados reales y funciones actuales; revisar permisos y asesores; conectar la UI al front-end actual y realizar pruebas de integración aisladas.
- La protección contra contraseñas filtradas aparece como aviso pendiente del asesor de seguridad. No fue activada ni modificada durante estas pruebas.

## Criterio para publicar en producción

No desplegar hasta que:

1. La interfaz del cliente muestre el formulario solo cuando la recarga esté confirmada como entregada.
2. El cliente acepte de forma inequívoca que su nombre registrado y el comentario serán públicos.
3. El servidor vuelva a comprobar la propiedad del pedido y ambos estados `completed`.
4. Administración pueda ocultar, restaurar y retirar reseñas.
5. La vista pública no exponga datos privados.
6. Los promedios excluyan opiniones ocultas/retiradas.
7. Pruebas de regresión confirmen que pagos, Wallet, pedidos y entrega no cambiaron.
8. El propietario revise visualmente la experiencia en Android antes del PR hacia producción.
