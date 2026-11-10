CREATE POLICY product_costs_backend_only
ON private.product_costs
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
