DROP POLICY IF EXISTS "Productos: lectura pública activos" ON public.products;
CREATE POLICY "Productos: lectura pública ofertas publicadas"
ON public.products
FOR SELECT
TO anon
USING (
  active IS TRUE
  AND storefront_visible IS TRUE
  AND provider_status = 'active'
  AND provider_in_stock IS TRUE
);

DROP POLICY IF EXISTS "Productos: lectura autenticados" ON public.products;
CREATE POLICY "Productos: lectura autenticados publicados o admin"
ON public.products
FOR SELECT
TO authenticated
USING (
  (
    active IS TRUE
    AND storefront_visible IS TRUE
    AND provider_status = 'active'
    AND provider_in_stock IS TRUE
  )
  OR (SELECT private.is_admin() AS is_admin)
);
