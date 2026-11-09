create or replace function public.validate_order_request()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
 selected_product public.products%rowtype;
 final_price numeric;
begin
 if auth.uid() is null or new.user_id is distinct from auth.uid() then
  raise exception 'No autorizado para crear este pedido.';
 end if;
 if new.product_id is null then raise exception 'Selecciona un producto válido.'; end if;
 if new.player_id is null or length(btrim(new.player_id))<3 or length(btrim(new.player_id))>64 then
  raise exception 'El ID del jugador debe tener entre 3 y 64 caracteres.';
 end if;
 select * into selected_product from public.products where id=new.product_id and active=true;
 if not found then raise exception 'El producto ya no está disponible.'; end if;
 if coalesce(new.payment_source,'direct')='wallet' then
  if new.payment_method<>'Billetera CUP' then raise exception 'Método de billetera no válido.'; end if;
  final_price:=selected_product.price_transfer;
 elsif coalesce(new.payment_source,'direct')='direct' then
  if not exists(select 1 from public.payment_methods pm where pm.name=new.payment_method and pm.active=true) then
   raise exception 'El método de pago no está activo.';
  end if;
  case new.payment_method
   when 'Transferencia CUP' then final_price:=selected_product.price_transfer;
   when 'Saldo móvil' then final_price:=selected_product.price_mobile;
   when 'USDT' then final_price:=selected_product.price_usdt;
   else raise exception 'Método de pago no válido.';
  end case;
 else
  raise exception 'Origen de pago no válido.';
 end if;
 if final_price is null or final_price<=0 then raise exception 'Este producto no tiene precio para ese método de pago.'; end if;
 new.game:=selected_product.game;
 new.package_name:=selected_product.name;
 new.price:=final_price;
 new.status:='pending';
 new.order_code:='EC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 new.player_id:=btrim(new.player_id);
 new.player_name:=nullif(btrim(coalesce(new.player_name,'')),'');
 new.payment_reference:=null;
 new.admin_notes:=null;
 new.created_at:=now();
 new.payment_source:=coalesce(new.payment_source,'direct');
 new.proof_path:=null;
 new.paid_at:=null;
 return new;
end;
$$;