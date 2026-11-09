create index if not exists customer_account_controls_blocked_by_idx
  on private.customer_account_controls(blocked_by);
create index if not exists customer_security_events_actor_id_idx
  on private.customer_security_events(actor_id);
create index if not exists customer_security_events_order_id_idx
  on private.customer_security_events(order_id);
create index if not exists customer_security_events_user_id_idx
  on private.customer_security_events(user_id);