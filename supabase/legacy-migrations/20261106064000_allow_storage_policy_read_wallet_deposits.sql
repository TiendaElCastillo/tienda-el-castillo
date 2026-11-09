-- Required because the storage.objects INSERT policy also checks wallet_deposits.
-- RLS on wallet_deposits limits authenticated readers to their own rows or admins.
grant select on table public.wallet_deposits to authenticated;
