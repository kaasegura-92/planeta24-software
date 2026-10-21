-- PLANETA 24 V4 - ejecutar una vez en Supabase SQL Editor.
-- No elimina ventas, productos ni cierres anteriores.

alter table public.ventas
  add column if not exists metodo_costo_v4 text;

-- Para registros anteriores, solo clasificar como producto cuando hay costo.
update public.ventas set metodo_costo_v4='producto'
where tipo='productos' and costo_total is not null and metodo_costo_v4 is null;

alter table public.ventas drop constraint if exists ventas_metodo_costo_v4_check;
alter table public.ventas add constraint ventas_metodo_costo_v4_check
  check (metodo_costo_v4 is null or metodo_costo_v4 in ('producto','manual','estimado'));

create table if not exists public.configuracion_v4 (
  id integer primary key check (id=1),
  margen_estimado numeric(5,2) not null check (margen_estimado between 0 and 100),
  actualizado_en timestamptz not null default now()
);
insert into public.configuracion_v4(id,margen_estimado)
values (1,30) on conflict(id) do nothing;

alter table public.configuracion_v4 enable row level security;
drop policy if exists v4_config_read on public.configuracion_v4;
create policy v4_config_read on public.configuracion_v4
for select to authenticated using ((select public.es_administrador()));
-- Las modificaciones se hacen solo a través de la función validada.
revoke all on public.configuracion_v4 from anon;
grant select on public.configuracion_v4 to authenticated;
revoke insert, update, delete on public.configuracion_v4 from authenticated;

create or replace function public.configurar_margen_v4(p_margen numeric)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_administrador() then raise exception 'Sin autorización'; end if;
  if p_margen is null or p_margen < 0 or p_margen > 100 then
    raise exception 'El margen debe estar entre 0 y 100';
  end if;
  insert into public.configuracion_v4(id,margen_estimado,actualizado_en)
  values(1,round(p_margen,2),now())
  on conflict(id) do update set margen_estimado=excluded.margen_estimado, actualizado_en=now();
end; $$;

create or replace function public.registrar_venta_rapida_v4(
  p_total numeric,
  p_medio_pago text,
  p_nota text default null,
  p_metodo text default 'estimado',
  p_costo_manual numeric default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_costo numeric(12,2);
  v_margen numeric(5,2);
  v_id uuid;
begin
  if not public.es_administrador() then raise exception 'Sin autorización'; end if;
  if p_total is null or p_total <= 0 or p_total > 9999999999.99 then raise exception 'Importe inválido'; end if;
  if p_medio_pago not in ('efectivo','transferencia') or p_medio_pago is null then raise exception 'Medio de pago inválido'; end if;
  if p_metodo not in ('manual','estimado') or p_metodo is null then raise exception 'Método inválido'; end if;
  if p_metodo='manual' then
    if p_costo_manual is null or p_costo_manual < 0 or p_costo_manual > p_total*1000 then
      raise exception 'Costo manual inválido';
    end if;
    v_costo:=round(p_costo_manual,2);
  else
    select margen_estimado into v_margen from public.configuracion_v4 where id=1;
    if v_margen is null then raise exception 'Falta configuración V4'; end if;
    v_costo:=round(p_total*(1-v_margen/100),2);
  end if;
  insert into public.ventas(tipo,total,medio_pago,nota,costo_total,metodo_costo_v4,registrado_por)
  values('rapida',round(p_total,2),p_medio_pago,nullif(trim(p_nota),''),v_costo,p_metodo,auth.uid())
  returning id into v_id;
  return v_id;
end; $$;

revoke all on function public.configurar_margen_v4(numeric) from public,anon;
revoke all on function public.registrar_venta_rapida_v4(numeric,text,text,text,numeric) from public,anon;
grant execute on function public.configurar_margen_v4(numeric) to authenticated;
grant execute on function public.registrar_venta_rapida_v4(numeric,text,text,text,numeric) to authenticated;
