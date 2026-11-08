-- Allow signed-in customers to read their wallet ledger through the existing RLS policy.
-- No insert, update, or delete privileges are granted to browser clients.
grant select on table public.wallet_transactions to authenticated;
