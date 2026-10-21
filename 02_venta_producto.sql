-- Ejecutar una vez en SQL Editor de Supabase.
-- Operación atómica: venta, detalle y descuento de stock juntos.
create or replace function public.registrar_venta_producto(
 p_producto_id uuid, p_cantidad numeric, p_medio_pago text
) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare p public.productos%rowtype; v_id uuid;
begin
 if not (select public.es_administrador()) then raise exception 'Acceso no autorizado'; end if;
 if p_cantidad is null or p_cantidad <= 0 or p_medio_pago not in ('efectivo','transferencia') then
   raise exception 'Cantidad o medio de pago inválido';
 end if;
 select * into p from public.productos where id=p_producto_id and activo=true for update;
 if not found then raise exception 'Producto inexistente o inactivo'; end if;
 if p.stock < p_cantidad then raise exception 'Stock insuficiente'; end if;
 insert into public.ventas(tipo,medio_pago,total,costo_total,nota)
 values ('productos',p_medio_pago,p.precio*p_cantidad,p.costo*p_cantidad,p.nombre)
 returning id into v_id;
 insert into public.venta_detalles(venta_id,producto_id,nombre_producto,cantidad,precio_unitario,costo_unitario)
 values(v_id,p.id,p.nombre,p_cantidad,p.precio,p.costo);
 update public.productos set stock=stock-p_cantidad where id=p.id;
 return v_id;
end; $$;
revoke all on function public.registrar_venta_producto(uuid,numeric,text) from public,anon;
grant execute on function public.registrar_venta_producto(uuid,numeric,text) to authenticated;
