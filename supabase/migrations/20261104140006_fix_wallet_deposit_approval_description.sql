create or replace function public.admin_review_wallet_deposit(
 p_deposit_id uuid,
 p_approve boolean,
 p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_deposit public.wallet_deposits%rowtype;
begin
 if not private.is_admin() then raise exception 'No autorizado.'; end if;
 select * into v_deposit from public.wallet_deposits where id=p_deposit_id for update;
 if not found then raise exception 'Depósito no encontrado.'; end if;
 if v_deposit.status<>'payment_review' or v_deposit.proof_path is null then
  raise exception 'El depósito todavía no tiene comprobante para revisar.';
 end if;
 if p_approve then
  insert into public.wallet_transactions(user_id,kind,amount,currency,description)
  values(v_deposit.user_id,'deposit',v_deposit.amount,'CUP','Depósito aprobado por Tienda El Castillo');
  update public.wallet_deposits set status='approved',admin_notes=nullif(trim(coalesce(p_note,'')),''),reviewed_at=now() where id=p_deposit_id;
 else
  update public.wallet_deposits set status='rejected',admin_notes=nullif(trim(coalesce(p_note,'')),''),reviewed_at=now() where id=p_deposit_id;
 end if;
 return jsonb_build_object('deposit_id',p_deposit_id,'status',case when p_approve then 'approved' else 'rejected' end);
end;
$$;
revoke all on function public.admin_review_wallet_deposit(uuid,boolean,text) from public,anon;
grant execute on function public.admin_review_wallet_deposit(uuid,boolean,text) to authenticated;