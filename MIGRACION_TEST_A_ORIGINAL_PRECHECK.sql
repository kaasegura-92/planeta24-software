-- PRECHECK DE SOLO LECTURA
-- Base destino esperada: Supabase Original (bcsmfvlbroufxgsvjxpw)
-- Fecha del respaldo comparado: 2026-11-18
-- Este archivo NO migra ni modifica datos. Revisar resultados antes del SQL de migración.

-- 1) Filas que se preservarán en las tablas de negocio existentes.
SELECT 'productos' AS tabla, count(*) AS filas FROM public.productos
UNION ALL SELECT 'ventas', count(*) FROM public.ventas
UNION ALL SELECT 'venta_detalles', count(*) FROM public.venta_detalles
UNION ALL SELECT 'aperturas', count(*) FROM public.aperturas
UNION ALL SELECT 'cierres', count(*) FROM public.cierres
UNION ALL SELECT 'gastos', count(*) FROM public.gastos
UNION ALL SELECT 'movimientos_caja', count(*) FROM public.movimientos_caja
ORDER BY tabla;

-- 2) Estos NULL deben corregirse antes de establecer NOT NULL en los campos de transferencia.
SELECT count(*) AS cierres_con_transferencias_null
FROM public.cierres
WHERE transferencia_contada IS NULL OR transferencia_esperada IS NULL;

-- 3) El nuevo índice único de códigos no puede crearse si devuelve filas.
SELECT codigo, count(*) AS repeticiones
FROM public.productos
WHERE codigo IS NOT NULL
GROUP BY codigo
HAVING count(*) > 1
ORDER BY codigo;

-- 4) Verificar valores existentes que deben seguir siendo válidos con el esquema TEST.
SELECT 'ventas.medio_pago' AS campo, medio_pago AS valor, count(*) AS filas
FROM public.ventas
GROUP BY medio_pago
UNION ALL
SELECT 'ventas.tipo', tipo, count(*)
FROM public.ventas
GROUP BY tipo
ORDER BY campo, valor;

-- 5) Duplicados por fecha operativa (la fecha debe seguir siendo única tras migrar aperturas).
SELECT fecha_operativa, count(*) AS repeticiones
FROM public.aperturas
GROUP BY fecha_operativa
HAVING count(*) > 1
ORDER BY fecha_operativa;

-- 6) Funciones y políticas actuales para comparar con el respaldo de Original.
SELECT p.proname AS funcion, pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid) AS retorno
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY p.proname, argumentos;

SELECT schemaname, tablename, policyname, roles, cmd
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 7) Permisos SQL de tabla concedidos a los roles de la API de Supabase.
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'service_role')
ORDER BY table_name, grantee, privilege_type;

-- 8) Permisos de ejecución de las funciones públicas.
SELECT grantee, routine_name, privilege_type
FROM information_schema.role_routine_grants
WHERE specific_schema = 'public'
  AND grantee IN ('anon', 'authenticated', 'service_role')
ORDER BY routine_name, grantee, privilege_type;
