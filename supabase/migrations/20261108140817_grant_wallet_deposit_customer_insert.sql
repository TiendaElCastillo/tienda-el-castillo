-- Allow signed-in customers to create only their own wallet deposit requests.
-- Row-level security and validate_wallet_deposit_request() continue to enforce
-- ownership, pending status, minimums, active payment methods and server-calculated
-- credited_amount, exchange_rate and recipient data. Customers cannot approve,
-- review or alter wallet balances through this grant.
grant insert (user_id, amount, currency, payment_method, status)
on table public.wallet_deposits
to authenticated;
