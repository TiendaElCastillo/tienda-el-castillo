# Tienda El Castillo — DESARROLLO

Este es el taller de desarrollo de la tienda. **No es la web de compras que usan los clientes.**

## Uso

- Aquí se preparan mejoras, rediseños, correcciones y nuevas funciones.
- No compartir la dirección antigua de GitHub Pages con clientes.
- No realizar compras reales, depósitos ni recargas de prueba.
- Al probar esta rama, las llamadas del navegador van al Supabase de desarrollo que figura más abajo.
- La versión de producción solo se actualiza tras revisar el cambio y preparar un PR en el repositorio oficial.
- Los datos de prueba deben ser ficticios. Nunca importar clientes, pedidos, comprobantes, saldos, teléfonos ni identificadores reales.

## Separación de entornos

| Uso | GitHub | Supabase |
|---|---|---|
| Compras de clientes / producción | `TiendaElCastillo/tiendaelcastillo.github.io` — `main` | `Tienda-El-Castillo` — `kfllglkfncebpknnugnx` |
| Taller de desarrollo / pruebas | `TiendaElCastillo/tienda-el-castillo` — `main` y ramas de trabajo | `Tienda-El-Castillo-Pruebas` — `kmotmgpzmeooznyymcxl` |

## Supabase de desarrollo

- URL: `https://kmotmgpzmeooznyymcxl.supabase.co`
- Proyecto: `Tienda-El-Castillo-Pruebas`
- Región: `us-east-2`
- Estado inicial comprobado: `ACTIVE_HEALTHY`
- La base se creó vacía y sin copiar datos del proyecto de producción.
- **Estado del esquema:** el proyecto contiene una base mínima aislada para probar reseñas verificadas, con perfiles, pedidos ficticios y políticas específicas. No es una copia completa de producción ni permite probar el checkout real.
- Las pruebas hechas hasta ahora son de base de datos/RLS y moderación; la interfaz de reseñas todavía no está integrada.
- No probar pedidos, pagos, billetera, comprobantes ni recargas. No hay funciones del proveedor ni secretos reales configurados.
- El informe de pruebas está en `docs/REVIEWS_TEST_REPORT_2026-11-23.md`.
- No configurar secretos reales del proveedor en este proyecto. Las funciones de prueba deben usar datos ficticios y servicios simulados.

## Reglas de seguridad

- No introducir claves privilegiadas, service-role keys, tokens del proveedor ni datos de clientes en el repositorio público.
- La clave incluida en el navegador es una clave pública de desarrollo, limitada por RLS; nunca sustituirla por una clave privada.
- No usar nunca el identificador de Supabase de producción en este repositorio de desarrollo.
- Antes de transferir una mejora a producción, comparar el código contra el repositorio oficial actual; este taller contiene una versión anterior de la tienda y no debe copiarse entero sobre producción.
