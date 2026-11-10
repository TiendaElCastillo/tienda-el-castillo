# Tienda El Castillo — DESARROLLO

Este es el taller de desarrollo de la tienda.

## Uso

- Aquí se preparan mejoras, rediseños, correcciones y nuevas funciones.
- No compartir la dirección antigua de GitHub Pages con clientes.
- No realizar pruebas de pedidos, comprobantes, billetera, pagos ni recargas mientras este código siga conectado al Supabase de producción.
- Antes de probar operaciones que escriban datos, crear y configurar un proyecto Supabase de staging independiente.
- Cuando una versión esté terminada y probada, se revisa y se copia a `TiendaElCastillo/tiendaelcastillo.github.io`, el repositorio de producción.

## Separación de entornos

- Producción: `TiendaElCastillo/tiendaelcastillo.github.io`
- Desarrollo: `TiendaElCastillo/tienda-el-castillo`

No introducir aquí secretos de Supabase ni claves de proveedor. Las claves privilegiadas solo deben existir en secretos del backend.
