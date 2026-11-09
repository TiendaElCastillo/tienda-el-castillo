
create table public.pricing_settings (
  id integer primary key default 1 check (id = 1),
  usdt_cup_rate numeric(12,2) not null default 1200 check (usdt_cup_rate > 0),
  mobile_credit_units integer not null default 360 check (mobile_credit_units > 0),
  mobile_cost_cup numeric(12,2) not null default 2000 check (mobile_cost_cup > 0),
  markup_percent numeric(7,2) not null default 35 check (markup_percent >= 0),
  rounding_cup integer not null default 10 check (rounding_cup > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create table public.pricing_rate_history (
  id uuid primary key default gen_random_uuid(),
  usdt_cup_rate numeric(12,2) not null check (usdt_cup_rate > 0),
  mobile_credit_units integer not null check (mobile_credit_units > 0),
  mobile_cost_cup numeric(12,2) not null check (mobile_cost_cup > 0),
  markup_percent numeric(7,2) not null check (markup_percent >= 0),
  rounding_cup integer not null check (rounding_cup > 0),
  changed_at timestamptz not null default now(),
  changed_by uuid references auth.users(id),
  note text
);

alter table public.pricing_settings enable row level security;
alter table public.pricing_rate_history enable row level security;

grant select, insert, update on public.pricing_settings to authenticated;
grant select, insert on public.pricing_rate_history to authenticated;

create policy "pricing settings admin read"
on public.pricing_settings for select to authenticated
using ((select private.is_admin()));

create policy "pricing settings admin insert"
on public.pricing_settings for insert to authenticated
with check ((select private.is_admin()));

create policy "pricing settings admin update"
on public.pricing_settings for update to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

create policy "pricing history admin read"
on public.pricing_rate_history for select to authenticated
using ((select private.is_admin()));

create policy "pricing history admin insert"
on public.pricing_rate_history for insert to authenticated
with check ((select private.is_admin()));

create function public.log_pricing_settings_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.pricing_rate_history (
    usdt_cup_rate,
    mobile_credit_units,
    mobile_cost_cup,
    markup_percent,
    rounding_cup,
    changed_at,
    changed_by,
    note
  ) values (
    new.usdt_cup_rate,
    new.mobile_credit_units,
    new.mobile_cost_cup,
    new.markup_percent,
    new.rounding_cup,
    now(),
    auth.uid(),
    case when tg_op = 'INSERT' then 'Configuración inicial' else 'Cambio de configuración' end
  );
  return new;
end;
$$;

revoke all on function public.log_pricing_settings_history() from public, anon, authenticated;

create trigger pricing_settings_history_after_change
after insert or update on public.pricing_settings
for each row execute function public.log_pricing_settings_history();

insert into public.pricing_settings (
  id, usdt_cup_rate, mobile_credit_units, mobile_cost_cup,
  markup_percent, rounding_cup
) values (1, 1200, 360, 2000, 35, 10)
on conflict (id) do nothing;
