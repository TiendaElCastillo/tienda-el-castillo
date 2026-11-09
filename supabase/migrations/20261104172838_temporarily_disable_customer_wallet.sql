
revoke all privileges on table public.wallet_deposits, public.wallet_transactions
from anon, authenticated;

revoke execute on function public.create_wallet_order(uuid, text, text)
from public, anon, authenticated;

revoke execute on function public.submit_wallet_deposit_proof(uuid, text, text)
from public, anon, authenticated;

revoke execute on function public.admin_review_wallet_deposit(uuid, boolean, text)
from public, anon, authenticated;

revoke execute on function private.wallet_balance(uuid, text)
from public, anon, authenticated;
