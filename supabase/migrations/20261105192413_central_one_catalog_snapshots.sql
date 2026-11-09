
create table public.central_one_catalog_snapshots (
  id uuid primary key default gen_random_uuid(),
  provider_status integer not null,
  payload jsonb not null,
  fetched_at timestamptz not null default now(),
  fetched_by uuid references auth.users(id)
);

alter table public.central_one_catalog_snapshots enable row level security;
grant select, insert on public.central_one_catalog_snapshots to authenticated;

create policy "central catalog snapshots admin read"
on public.central_one_catalog_snapshots for select to authenticated
using ((select private.is_admin()));

create policy "central catalog snapshots admin insert"
on public.central_one_catalog_snapshots for insert to authenticated
with check ((select private.is_admin()));

create index central_one_catalog_snapshots_fetched_at_idx
on public.central_one_catalog_snapshots (fetched_at desc);
