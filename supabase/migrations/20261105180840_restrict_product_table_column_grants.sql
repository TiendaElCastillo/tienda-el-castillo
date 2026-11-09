revoke select, insert, update on public.products from anon, authenticated;
grant select (id,game,name,description,amount,price_transfer,price_mobile,price_usdt,active,created_at) on public.products to anon, authenticated;
grant insert (game,name,description,amount,price_transfer,price_mobile,price_usdt,active) on public.products to authenticated;
grant update (game,name,description,amount,price_transfer,price_mobile,price_usdt,active) on public.products to authenticated;