-- Historial de migración incremental TEST V11.9 -> Supabase Original.
-- APLICADA en Supabase Original el 2026-11-18 y verificada por la usuaria.
-- NO VOLVER A EJECUTAR: conserva el paso a paso del cambio aplicado.
-- Conserva filas de Original; no importa datos de prueba.
-- Requiere revisión y prueba en una restauración aislada antes de aplicarse.
-- No ejecutar el dump completo de TEST sobre Original.

BEGIN;
SET LOCAL statement_timeout = 0;
SET LOCAL lock_timeout = '10s';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.productos WHERE codigo IS NOT NULL GROUP BY codigo HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Hay códigos de producto duplicados';
  END IF;
  IF EXISTS (SELECT 1 FROM public.aperturas GROUP BY fecha_operativa HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'Hay aperturas duplicadas por fecha operativa';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cierres WHERE transferencia_contada IS NULL OR transferencia_esperada IS NULL) THEN
    RAISE EXCEPTION 'Hay transferencias NULL en cierres';
  END IF;
END $$;

-- 1. Ajustes compatibles con los datos existentes.
ALTER TABLE public.aperturas ADD COLUMN id uuid DEFAULT gen_random_uuid();
ALTER TABLE public.aperturas ALTER COLUMN id SET NOT NULL;
ALTER TABLE public.aperturas DROP CONSTRAINT aperturas_pkey;
ALTER TABLE public.aperturas ADD CONSTRAINT aperturas_pkey PRIMARY KEY (id);
ALTER TABLE public.aperturas ADD CONSTRAINT aperturas_fecha_operativa_key UNIQUE (fecha_operativa);

ALTER TABLE public.ventas ADD COLUMN cliente_id uuid, ADD COLUMN origen_v7 boolean DEFAULT false NOT NULL;
ALTER TABLE public.ventas DROP CONSTRAINT ventas_medio_pago_check;
ALTER TABLE public.ventas DROP CONSTRAINT ventas_metodo_costo_v4_check;
ALTER TABLE public.ventas ADD CONSTRAINT ventas_medio_pago_check CHECK (medio_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'mixto'::text, 'fiado'::text]));

ALTER TABLE public.cierres ALTER COLUMN transferencia_contada SET DEFAULT 0;
ALTER TABLE public.cierres ALTER COLUMN transferencia_contada SET NOT NULL;
ALTER TABLE public.cierres ALTER COLUMN transferencia_esperada SET DEFAULT 0;
ALTER TABLE public.cierres ALTER COLUMN transferencia_esperada SET NOT NULL;
ALTER TABLE public.cierres DROP CONSTRAINT cierres_transferencia_no_negativa;
ALTER TABLE public.cierres ADD CONSTRAINT cierres_transferencia_contada_check CHECK (transferencia_contada >= 0);

ALTER TABLE public.configuracion_v4 ALTER COLUMN id SET DEFAULT 1;
ALTER TABLE public.configuracion_v4 ALTER COLUMN margen_estimado SET DEFAULT 30;
-- Se conserva configuracion_v4.actualizado_en, existente en Original.

-- 2. Tablas nuevas, vacías salvo responsables de configuración.


CREATE TABLE public.auditoria_caja_v11 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fecha_operativa date NOT NULL,
    accion text NOT NULL,
    usuario_id uuid NOT NULL,
    registrado_en timestamp with time zone DEFAULT now() NOT NULL,
    motivo text NOT NULL,
    antes jsonb,
    despues jsonb NOT NULL,
    CONSTRAINT auditoria_caja_v11_accion_check CHECK ((accion = ANY (ARRAY['cierre_atrasado'::text, 'corregir_apertura'::text, 'corregir_cierre'::text]))),
    CONSTRAINT auditoria_caja_v11_motivo_check CHECK ((length(btrim(motivo)) >= 8))
);

CREATE TABLE public.auditoria_stock_v11_9 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    producto_id uuid NOT NULL,
    codigo text,
    producto_nombre text NOT NULL,
    stock_anterior numeric NOT NULL,
    stock_nuevo numeric NOT NULL,
    diferencia numeric NOT NULL,
    motivo text NOT NULL,
    observaciones text,
    usuario_id uuid NOT NULL,
    registrado_en timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.clientes_v7 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL,
    telefono text,
    observaciones text,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    creado_por uuid DEFAULT auth.uid() NOT NULL,
    CONSTRAINT clientes_v7_nombre_check CHECK ((length(btrim(nombre)) > 0))
);

CREATE TABLE public.consumos_personales_v8 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    responsable_id uuid NOT NULL,
    producto_id uuid NOT NULL,
    producto_nombre text NOT NULL,
    cantidad integer NOT NULL,
    costo_unitario numeric(12,2) NOT NULL,
    total numeric(12,2) NOT NULL,
    registrado_por uuid DEFAULT auth.uid() NOT NULL,
    CONSTRAINT consumos_personales_v8_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT consumos_personales_v8_costo_unitario_check CHECK ((costo_unitario >= (0)::numeric)),
    CONSTRAINT consumos_personales_v8_total_check CHECK ((total >= (0)::numeric))
);

CREATE TABLE public.eventos_admin_leidos_v117 (
    evento_id bigint NOT NULL,
    usuario_id uuid NOT NULL,
    leido_en timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.eventos_admin_v117 (
    id bigint NOT NULL,
    tabla text NOT NULL,
    accion text NOT NULL,
    registro_id text,
    usuario_id uuid,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    resumen text NOT NULL,
    anterior jsonb,
    nuevo jsonb
);

CREATE TABLE public.pagos_consumo_v8 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    consumo_id uuid NOT NULL,
    medio_pago text NOT NULL,
    importe numeric(12,2) NOT NULL,
    registrado_por uuid DEFAULT auth.uid() NOT NULL,
    CONSTRAINT pagos_consumo_v8_importe_check CHECK ((importe > (0)::numeric)),
    CONSTRAINT pagos_consumo_v8_medio_pago_check CHECK ((medio_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text])))
);

CREATE TABLE public.pagos_venta_v7 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    venta_id uuid NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    medio_pago text NOT NULL,
    importe numeric NOT NULL,
    observaciones text,
    registrado_por uuid DEFAULT auth.uid() NOT NULL,
    CONSTRAINT pagos_venta_v7_importe_check CHECK ((importe > (0)::numeric)),
    CONSTRAINT pagos_venta_v7_medio_pago_check CHECK ((medio_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text])))
);

CREATE TABLE public.responsables_consumo_v8 (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.eventos_admin_v117 ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME public.eventos_admin_v117_id_seq START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1);

-- Primero claves primarias y únicas; después, claves foráneas entre tablas nuevas.


ALTER TABLE ONLY public.auditoria_caja_v11
    ADD CONSTRAINT auditoria_caja_v11_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.auditoria_stock_v11_9
    ADD CONSTRAINT auditoria_stock_v11_9_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.clientes_v7
    ADD CONSTRAINT clientes_v7_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.consumos_personales_v8
    ADD CONSTRAINT consumos_personales_v8_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.eventos_admin_leidos_v117
    ADD CONSTRAINT eventos_admin_leidos_v117_pkey PRIMARY KEY (evento_id, usuario_id);

ALTER TABLE ONLY public.eventos_admin_v117
    ADD CONSTRAINT eventos_admin_v117_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.pagos_consumo_v8
    ADD CONSTRAINT pagos_consumo_v8_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.pagos_venta_v7
    ADD CONSTRAINT pagos_venta_v7_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.responsables_consumo_v8
    ADD CONSTRAINT responsables_consumo_v8_nombre_key UNIQUE (nombre);

ALTER TABLE ONLY public.responsables_consumo_v8
    ADD CONSTRAINT responsables_consumo_v8_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.clientes_v7
    ADD CONSTRAINT clientes_v7_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES auth.users(id);

ALTER TABLE ONLY public.consumos_personales_v8
    ADD CONSTRAINT consumos_personales_v8_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.productos(id);

ALTER TABLE ONLY public.consumos_personales_v8
    ADD CONSTRAINT consumos_personales_v8_responsable_id_fkey FOREIGN KEY (responsable_id) REFERENCES public.responsables_consumo_v8(id);

ALTER TABLE ONLY public.eventos_admin_leidos_v117
    ADD CONSTRAINT eventos_admin_leidos_v117_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos_admin_v117(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.pagos_consumo_v8
    ADD CONSTRAINT pagos_consumo_v8_consumo_id_fkey FOREIGN KEY (consumo_id) REFERENCES public.consumos_personales_v8(id);

ALTER TABLE ONLY public.pagos_venta_v7
    ADD CONSTRAINT pagos_venta_v7_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES auth.users(id);

ALTER TABLE ONLY public.pagos_venta_v7
    ADD CONSTRAINT pagos_venta_v7_venta_id_fkey FOREIGN KEY (venta_id) REFERENCES public.ventas(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.ventas ADD CONSTRAINT ventas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes_v7(id) ON DELETE RESTRICT;

-- 3. Índices de V11.9.
-- Reemplaza el índice único anterior por el nombre usado en TEST.
DROP INDEX IF EXISTS public.productos_codigo_unico_v5;


CREATE INDEX eventos_admin_v117_fecha_idx ON public.eventos_admin_v117 USING btree (fecha DESC);

CREATE INDEX idx_pagos_venta_v7_fecha ON public.pagos_venta_v7 USING btree (fecha);

CREATE INDEX idx_pagos_venta_v7_venta ON public.pagos_venta_v7 USING btree (venta_id);

CREATE INDEX idx_ventas_cliente_v7 ON public.ventas USING btree (cliente_id);

CREATE UNIQUE INDEX productos_codigo_unico_v61 ON public.productos USING btree (codigo) WHERE (codigo IS NOT NULL);

-- 4. Funciones V11.9.


CREATE OR REPLACE FUNCTION public.abrir_caja(p_efectivo numeric, p_transferencia numeric, p_observaciones text DEFAULT NULL::text) RETURNS date
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  d date := (
    now() AT TIME ZONE 'America/Argentina/Buenos_Aires'
  )::date;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_efectivo IS NULL
     OR p_transferencia IS NULL
     OR p_efectivo < 0
     OR p_transferencia < 0 THEN
    RAISE EXCEPTION 'Saldos inválidos';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cierres
    WHERE fecha_operativa = d
  ) THEN
    RAISE EXCEPTION 'La jornada ya está cerrada';
  END IF;

  INSERT INTO public.aperturas (
    fecha_operativa,
    efectivo_inicial,
    transferencia_inicial,
    observaciones,
    abierto_por
  )
  VALUES (
    d,
    p_efectivo,
    p_transferencia,
    NULLIF(TRIM(p_observaciones), ''),
    auth.uid()
  );

  RETURN d;
END;
$$;

CREATE OR REPLACE FUNCTION public.administrar_caja_v11(p_fecha date, p_accion text, p_efectivo numeric, p_transferencia numeric, p_motivo text, p_clave text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
 d_hoy date := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
 a public.aperturas%ROWTYPE;
 c public.cierres%ROWTYPE;
 antes jsonb;
 despues jsonb;
 venta_e numeric := 0; venta_t numeric := 0;
 gasto_e numeric := 0; gasto_t numeric := 0;
 mov_e numeric := 0; mov_t numeric := 0;
 esperado_e numeric; esperado_t numeric;
 hash_clave text;
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_administrador() OR auth.uid() NOT IN (
   '2d7a4aca-85d5-4da5-bf90-8281b6ae4ff9'::uuid
 ) THEN RAISE EXCEPTION 'Sin autorización para corregir caja'; END IF;
 -- Comprobación de la contraseña en el servidor, no solamente en el HTML.
 -- Supabase Auth almacena contraseñas con hash bcrypt en auth.users.
 SELECT u.encrypted_password INTO hash_clave FROM auth.users u WHERE u.id=auth.uid();
 IF hash_clave IS NULL OR p_clave IS NULL OR length(p_clave)=0 OR
    extensions.crypt(p_clave, hash_clave) IS DISTINCT FROM hash_clave THEN
   RAISE EXCEPTION 'Contraseña incorrecta';
 END IF;
 IF p_fecha IS NULL OR p_fecha > d_hoy THEN RAISE EXCEPTION 'Fecha operativa inválida'; END IF;
 IF p_accion NOT IN ('cierre_atrasado','corregir_apertura','corregir_cierre') OR p_accion IS NULL THEN RAISE EXCEPTION 'Acción inválida'; END IF;
 IF p_efectivo IS NULL OR p_transferencia IS NULL OR p_efectivo < 0 OR p_transferencia < 0 OR
    p_efectivo > 9999999999.99 OR p_transferencia > 9999999999.99 OR
    p_efectivo <> round(p_efectivo,2) OR p_transferencia <> round(p_transferencia,2) THEN
   RAISE EXCEPTION 'Importes inválidos';
 END IF;
 IF length(btrim(coalesce(p_motivo,''))) < 8 THEN RAISE EXCEPTION 'Explicá el motivo (mínimo 8 caracteres)'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(240024);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('planeta24_caja'), pg_catalog.hashtext(p_fecha::text));
 SELECT * INTO a FROM public.aperturas WHERE fecha_operativa=p_fecha FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'No existe apertura para esa jornada'; END IF;
 SELECT * INTO c FROM public.cierres WHERE fecha_operativa=p_fecha FOR UPDATE;
 IF p_accion='cierre_atrasado' THEN
   IF p_fecha >= d_hoy THEN RAISE EXCEPTION 'Para hoy usá Cerrar jornada'; END IF;
   IF FOUND THEN RAISE EXCEPTION 'La jornada ya tiene cierre'; END IF;
 ELSIF p_accion='corregir_cierre' AND NOT FOUND THEN
   RAISE EXCEPTION 'No existe cierre para corregir';
 END IF;

 -- Misma fórmula de cerrar_caja vigente en TEST; fecha argentina de la jornada.
 SELECT coalesce(sum(x.e),0),coalesce(sum(x.t),0) INTO venta_e,venta_t FROM (
  SELECT CASE WHEN v.medio_pago='efectivo' THEN v.total ELSE 0 END e,
         CASE WHEN v.medio_pago='transferencia' THEN v.total ELSE 0 END t
    FROM public.ventas v
   WHERE (v.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date=p_fecha
     AND v.origen_v7=false AND v.medio_pago IN ('efectivo','transferencia') AND v.cliente_id IS NULL
  UNION ALL
  SELECT CASE WHEN p.medio_pago='efectivo' THEN p.importe ELSE 0 END,
         CASE WHEN p.medio_pago='transferencia' THEN p.importe ELSE 0 END
    FROM public.pagos_venta_v7 p
   WHERE (p.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date=p_fecha
 ) x;
 SELECT coalesce(sum(importe) FILTER (WHERE medio_pago='efectivo'),0),
        coalesce(sum(importe) FILTER (WHERE medio_pago='transferencia'),0)
 INTO gasto_e,gasto_t FROM public.gastos
 WHERE (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date=p_fecha;
 SELECT coalesce(sum(CASE WHEN tipo='ingreso' THEN importe WHEN tipo='egreso' THEN -importe ELSE 0 END)
                    FILTER (WHERE medio_pago='efectivo'),0),
        coalesce(sum(CASE WHEN tipo='ingreso' THEN importe WHEN tipo='egreso' THEN -importe ELSE 0 END)
                    FILTER (WHERE medio_pago='transferencia'),0)
 INTO mov_e,mov_t FROM public.movimientos_caja
 WHERE (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date=p_fecha;

 IF p_accion='corregir_apertura' THEN
   antes:=to_jsonb(a);
   UPDATE public.aperturas SET efectivo_inicial=p_efectivo, transferencia_inicial=p_transferencia
    WHERE id=a.id RETURNING to_jsonb(aperturas.*) INTO despues;
   -- Si ya hay cierre, mantener coherencia de sus importes esperados y diferencias generadas.
   IF c.id IS NOT NULL THEN
     UPDATE public.cierres SET
       efectivo_esperado=p_efectivo+venta_e-gasto_e+mov_e,
       transferencia_esperada=p_transferencia+venta_t-gasto_t+mov_t
     WHERE id=c.id;
     despues:=despues || pg_catalog.jsonb_build_object('cierre_anterior',to_jsonb(c),
       'cierre_actualizado',(SELECT to_jsonb(z) FROM public.cierres z WHERE z.id=c.id));
   END IF;
 ELSIF p_accion='cierre_atrasado' THEN
   esperado_e:=a.efectivo_inicial+venta_e-gasto_e+mov_e;
   esperado_t:=a.transferencia_inicial+venta_t-gasto_t+mov_t;
   INSERT INTO public.cierres (fecha_operativa,efectivo_contado,efectivo_esperado,
     transferencia_contada,transferencia_esperada,observaciones,cerrado_por)
   VALUES (p_fecha,p_efectivo,esperado_e,p_transferencia,esperado_t,
     'Cierre atrasado V11: '||btrim(p_motivo),auth.uid())
   RETURNING to_jsonb(cierres.*) INTO despues;
 ELSE
   antes:=to_jsonb(c);
   UPDATE public.cierres SET efectivo_contado=p_efectivo,transferencia_contada=p_transferencia
    WHERE id=c.id RETURNING to_jsonb(cierres.*) INTO despues;
 END IF;
 INSERT INTO public.auditoria_caja_v11(fecha_operativa,accion,usuario_id,motivo,antes,despues)
 VALUES(p_fecha,p_accion,auth.uid(),btrim(p_motivo),antes,despues);
END;
$$;

CREATE OR REPLACE FUNCTION public.ajustar_stock_v11_9(p_producto_id uuid, p_stock_nuevo numeric, p_motivo text, p_observaciones text, p_clave text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  p public.productos%ROWTYPE;
  hash_clave text;
  id_auditoria uuid;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION
      'Solo administradores autorizados pueden ajustar stock';
  END IF;

  SELECT encrypted_password
  INTO hash_clave
  FROM auth.users
  WHERE id = auth.uid();

  IF hash_clave IS NULL
     OR coalesce(p_clave, '') = ''
     OR extensions.crypt(p_clave, hash_clave)
        IS DISTINCT FROM hash_clave THEN
    RAISE EXCEPTION 'Contraseña incorrecta';
  END IF;

  IF p_producto_id IS NULL
     OR p_stock_nuevo IS NULL
     OR p_stock_nuevo < 0
     OR p_stock_nuevo > 100000000
     OR p_stock_nuevo <> trunc(p_stock_nuevo) THEN
    RAISE EXCEPTION
      'Stock inválido: ingresá unidades enteras no negativas';
  END IF;

  IF p_motivo NOT IN (
    'Recuento físico',
    'Faltante',
    'Sobrante',
    'Rotura',
    'Vencimiento',
    'Error de carga',
    'Otro'
  ) THEN
    RAISE EXCEPTION 'Motivo inválido';
  END IF;

  IF p_motivo = 'Otro'
     AND length(btrim(coalesce(p_observaciones, ''))) < 8 THEN
    RAISE EXCEPTION
      'Describí el motivo (mínimo 8 caracteres)';
  END IF;

  SELECT *
  INTO p
  FROM public.productos
  WHERE id = p_producto_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Producto no encontrado';
  END IF;

  IF p.stock IS NULL OR p.stock = p_stock_nuevo THEN
    RAISE EXCEPTION
      'No hay diferencia de stock para ajustar';
  END IF;

  UPDATE public.productos
  SET stock = p_stock_nuevo
  WHERE id = p.id;

  INSERT INTO public.auditoria_stock_v11_9 (
    producto_id,
    codigo,
    producto_nombre,
    stock_anterior,
    stock_nuevo,
    diferencia,
    motivo,
    observaciones,
    usuario_id
  )
  VALUES (
    p.id,
    p.codigo,
    p.nombre,
    p.stock,
    p_stock_nuevo,
    p_stock_nuevo - p.stock,
    p_motivo,
    nullif(btrim(coalesce(p_observaciones, '')), ''),
    auth.uid()
  )
  RETURNING id INTO id_auditoria;

  RETURN id_auditoria;
END;
$$;

DROP FUNCTION public.cerrar_caja(numeric, numeric, text);

CREATE OR REPLACE FUNCTION public.cerrar_caja(p_efectivo_contado numeric, p_transferencia_contada numeric, p_observaciones text DEFAULT NULL::text) RETURNS date
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  d date := (
    now() AT TIME ZONE 'America/Argentina/Buenos_Aires'
  )::date;

  v_apertura record;
  v_efectivo numeric := 0;
  v_transferencia numeric := 0;
  v_gastos_efectivo numeric := 0;
  v_gastos_transferencia numeric := 0;
  v_mov_efectivo numeric := 0;
  v_mov_transferencia numeric := 0;
  v_esperado_efectivo numeric;
  v_esperado_transferencia numeric;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_efectivo_contado IS NULL
     OR p_transferencia_contada IS NULL
     OR p_efectivo_contado < 0
     OR p_transferencia_contada < 0 THEN
    RAISE EXCEPTION 'Importes contados inválidos';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(240024);

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('planeta24_caja'),
    pg_catalog.hashtext(d::text)
  );

  SELECT *
  INTO v_apertura
  FROM public.aperturas
  WHERE fecha_operativa = d;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Primero tenés que abrir la caja';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cierres
    WHERE fecha_operativa = d
  ) THEN
    RAISE EXCEPTION 'La caja ya está cerrada';
  END IF;

  SELECT
    COALESCE(SUM(x.efectivo), 0),
    COALESCE(SUM(x.transferencia), 0)
  INTO v_efectivo, v_transferencia
  FROM (
    SELECT
      CASE WHEN v.medio_pago = 'efectivo'
           THEN v.total ELSE 0 END AS efectivo,
      CASE WHEN v.medio_pago = 'transferencia'
           THEN v.total ELSE 0 END AS transferencia
    FROM public.ventas v
    WHERE (
      v.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'
    )::date = d
      AND v.origen_v7 = false
      AND v.medio_pago IN ('efectivo', 'transferencia')
      AND v.cliente_id IS NULL

    UNION ALL

    SELECT
      CASE WHEN p.medio_pago = 'efectivo'
           THEN p.importe ELSE 0 END,
      CASE WHEN p.medio_pago = 'transferencia'
           THEN p.importe ELSE 0 END
    FROM public.pagos_venta_v7 p
    WHERE (
      p.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'
    )::date = d
  ) x;

  SELECT
    COALESCE(SUM(importe) FILTER (
      WHERE medio_pago = 'efectivo'
    ), 0),
    COALESCE(SUM(importe) FILTER (
      WHERE medio_pago = 'transferencia'
    ), 0)
  INTO v_gastos_efectivo, v_gastos_transferencia
  FROM public.gastos
  WHERE (
    fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'
  )::date = d;

  SELECT
    COALESCE(SUM(
      CASE
        WHEN tipo = 'ingreso' THEN importe
        WHEN tipo = 'egreso' THEN -importe
        ELSE 0
      END
    ) FILTER (WHERE medio_pago = 'efectivo'), 0),
    COALESCE(SUM(
      CASE
        WHEN tipo = 'ingreso' THEN importe
        WHEN tipo = 'egreso' THEN -importe
        ELSE 0
      END
    ) FILTER (WHERE medio_pago = 'transferencia'), 0)
  INTO v_mov_efectivo, v_mov_transferencia
  FROM public.movimientos_caja
  WHERE (
    fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'
  )::date = d;

  v_esperado_efectivo :=
    v_apertura.efectivo_inicial
    + v_efectivo
    - v_gastos_efectivo
    + v_mov_efectivo;

  v_esperado_transferencia :=
    v_apertura.transferencia_inicial
    + v_transferencia
    - v_gastos_transferencia
    + v_mov_transferencia;

  INSERT INTO public.cierres (
    fecha_operativa,
    efectivo_contado,
    efectivo_esperado,
    transferencia_contada,
    transferencia_esperada,
    observaciones,
    cerrado_por
  )
  VALUES (
    d,
    p_efectivo_contado,
    v_esperado_efectivo,
    p_transferencia_contada,
    v_esperado_transferencia,
    p_observaciones,
    auth.uid()
  );

  RETURN d;
END;
$$;

CREATE OR REPLACE FUNCTION public.cobrar_consumo_v8(p_consumo_id uuid, p_importe numeric, p_medio_pago text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE v_total numeric; v_pagado numeric; v_id uuid; v_dia date;
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_administrador() THEN RAISE EXCEPTION 'Sin autorización'; END IF;
 IF p_importe IS NULL OR p_importe<=0 OR p_importe<>round(p_importe,2) THEN RAISE EXCEPTION 'Importe inválido'; END IF;
 IF p_medio_pago IS NULL OR p_medio_pago NOT IN ('efectivo','transferencia') THEN RAISE EXCEPTION 'Medio inválido'; END IF;
 v_dia:=(now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
 PERFORM pg_advisory_xact_lock(hashtext('planeta24_caja'),hashtext(v_dia::text));
 IF EXISTS(SELECT 1 FROM public.cierres WHERE fecha_operativa=v_dia) OR NOT EXISTS(SELECT 1 FROM public.aperturas WHERE fecha_operativa=v_dia) THEN RAISE EXCEPTION 'La caja no está abierta'; END IF;
 SELECT total INTO v_total FROM public.consumos_personales_v8 WHERE id=p_consumo_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Consumo inexistente'; END IF;
 SELECT coalesce(sum(importe),0) INTO v_pagado FROM public.pagos_consumo_v8 WHERE consumo_id=p_consumo_id;
 IF p_importe>v_total-v_pagado THEN RAISE EXCEPTION 'El cobro supera la deuda'; END IF;
 INSERT INTO public.pagos_consumo_v8(consumo_id,medio_pago,importe) VALUES(p_consumo_id,p_medio_pago,p_importe) RETURNING id INTO v_id;
 INSERT INTO public.movimientos_caja(tipo,medio_pago,importe,descripcion) VALUES('ingreso',p_medio_pago,p_importe,'Cobro consumo personal '||p_consumo_id::text);
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.cobrar_fiado_v7(p_venta_id uuid, p_importe numeric, p_medio_pago text, p_observaciones text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_venta record;
  v_cobrado numeric;
  v_pago_id uuid;
  v_dia date;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_venta_id IS NULL
     OR p_importe IS NULL
     OR p_importe <= 0 THEN
    RAISE EXCEPTION 'Importe o venta inválidos';
  END IF;

  IF p_medio_pago IS NULL
     OR p_medio_pago NOT IN (
       'efectivo', 'transferencia'
     ) THEN
    RAISE EXCEPTION 'Medio de pago inválido';
  END IF;

  v_dia := (
    now() AT TIME ZONE
    'America/Argentina/Buenos_Aires'
  )::date;

  -- Mismo bloqueo que usa el cierre V7.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('planeta24_caja'),
    pg_catalog.hashtext(v_dia::text)
  );

  IF EXISTS (
    SELECT 1
    FROM public.cierres
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION 'La caja ya está cerrada';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.aperturas
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION 'Primero tenés que abrir la caja';
  END IF;

  -- Bloquear la venta para evitar cobros
  -- simultáneos que superen la deuda.
  SELECT id, total, cliente_id
  INTO v_venta
  FROM public.ventas
  WHERE id = p_venta_id
  FOR UPDATE;

  IF NOT FOUND OR v_venta.cliente_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró el fiado';
  END IF;

  SELECT COALESCE(SUM(importe), 0)
  INTO v_cobrado
  FROM public.pagos_venta_v7
  WHERE venta_id = p_venta_id;

  IF v_cobrado + p_importe > v_venta.total THEN
    RAISE EXCEPTION
      'El cobro supera el saldo pendiente';
  END IF;

  INSERT INTO public.pagos_venta_v7 (
    venta_id,
    medio_pago,
    importe,
    observaciones,
    registrado_por
  )
  VALUES (
    p_venta_id,
    p_medio_pago,
    p_importe,
    p_observaciones,
    auth.uid()
  )
  RETURNING id INTO v_pago_id;

  RETURN v_pago_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.configurar_margen_v4(p_margen numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_margen IS NULL
     OR p_margen < 0
     OR p_margen > 100 THEN
    RAISE EXCEPTION 'El margen debe estar entre 0 y 100';
  END IF;

  INSERT INTO public.configuracion_v4 (
    id,
    margen_estimado
  )
  VALUES (
    1,
    p_margen
  )
  ON CONFLICT (id)
  DO UPDATE SET
    margen_estimado = EXCLUDED.margen_estimado;
END;
$$;

CREATE OR REPLACE FUNCTION public.crear_cliente_v7(p_nombre text, p_telefono text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_cliente_id uuid;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_nombre IS NULL
     OR length(btrim(p_nombre)) = 0 THEN
    RAISE EXCEPTION 'Ingresá el nombre del cliente';
  END IF;

  IF length(p_nombre) > 150 THEN
    RAISE EXCEPTION 'El nombre es demasiado largo';
  END IF;

  INSERT INTO public.clientes_v7 (
    nombre,
    telefono,
    observaciones,
    creado_por
  )
  VALUES (
    btrim(p_nombre),
    NULLIF(btrim(p_telefono), ''),
    NULLIF(btrim(p_observaciones), ''),
    auth.uid()
  )
  RETURNING id INTO v_cliente_id;

  RETURN v_cliente_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.editar_cliente_v7(p_id uuid, p_nombre text, p_telefono text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_id IS NULL
     OR p_nombre IS NULL
     OR length(btrim(p_nombre)) = 0
     OR length(btrim(p_nombre)) > 150 THEN
    RAISE EXCEPTION 'Ingresá un nombre válido de hasta 150 caracteres';
  END IF;

  IF length(coalesce(p_telefono, '')) > 80
     OR length(coalesce(p_observaciones, '')) > 500 THEN
    RAISE EXCEPTION 'Teléfono u observaciones demasiado largos';
  END IF;

  UPDATE public.clientes_v7
  SET nombre = btrim(p_nombre),
      telefono = nullif(btrim(p_telefono), ''),
      observaciones = nullif(btrim(p_observaciones), '')
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró el cliente';
  END IF;

  RETURN p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.es_administrador() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.administradores a where a.usuario_id = (select auth.uid()));
$$;

CREATE OR REPLACE FUNCTION public.guardar_producto_v7(p_id uuid, p_codigo text, p_nombre text, p_precio numeric, p_costo numeric, p_stock numeric, p_categoria text, p_proveedor text, p_descripcion text, p_stock_minimo numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_id uuid;
  v_codigo text := NULLIF(btrim(p_codigo), '');
  v_nombre text := NULLIF(btrim(p_nombre), '');
BEGIN
  IF auth.uid() IS NULL OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF v_nombre IS NULL OR length(v_nombre) > 250
     OR length(COALESCE(v_codigo,'')) > 80
     OR length(COALESCE(p_categoria,'')) > 250
     OR length(COALESCE(p_proveedor,'')) > 250
     OR length(COALESCE(p_descripcion,'')) > 2000 THEN
    RAISE EXCEPTION 'Datos de producto inválidos';
  END IF;

  IF p_precio IS NULL OR p_costo IS NULL
     OR p_precio < 0 OR p_costo < 0
     OR p_precio > 1000000000 OR p_costo > 1000000000
     OR (p_stock_minimo IS NOT NULL AND (p_stock_minimo < 0 OR p_stock_minimo > 1000000000)) THEN
    RAISE EXCEPTION 'Precio, costo o stock mínimo inválidos';
  END IF;

  IF p_id IS NULL THEN
    IF p_stock IS NULL OR p_stock < 0 OR p_stock > 1000000000 THEN
      RAISE EXCEPTION 'Stock inicial inválido';
    END IF;
    INSERT INTO public.productos
      (codigo,nombre,precio,costo,stock,categoria,proveedor,descripcion,stock_minimo)
    VALUES
      (v_codigo,v_nombre,p_precio,p_costo,p_stock,
       NULLIF(btrim(p_categoria),''),NULLIF(btrim(p_proveedor),''),
       NULLIF(btrim(p_descripcion),''),p_stock_minimo)
    RETURNING id INTO v_id;
  ELSE
    -- El stock nunca se edita por esta función.
    UPDATE public.productos
       SET codigo=v_codigo,
           nombre=v_nombre,
           precio=p_precio,
           costo=p_costo,
           categoria=NULLIF(btrim(p_categoria),''),
           proveedor=NULLIF(btrim(p_proveedor),''),
           descripcion=NULLIF(btrim(p_descripcion),''),
           stock_minimo=p_stock_minimo
     WHERE id=p_id
     RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Producto no encontrado';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.importar_productos_v5(p_productos jsonb) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  item jsonb;
  v_codigo text;
  v_nombre text;
  v_cantidad integer := 0;
  v_total integer;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_productos IS NULL
     OR jsonb_typeof(p_productos) <> 'array' THEN
    RAISE EXCEPTION 'Formato de importación inválido';
  END IF;

  v_total := jsonb_array_length(p_productos);

  IF v_total = 0 OR v_total > 5000 THEN
    RAISE EXCEPTION 'La importación debe contener entre 1 y 5000 productos';
  END IF;

  FOR item IN
    SELECT value FROM jsonb_array_elements(p_productos)
  LOOP
    IF jsonb_typeof(item) <> 'object' THEN
      RAISE EXCEPTION 'Producto inválido en la importación';
    END IF;

    v_codigo := NULLIF(btrim(item->>'codigo'), '');
    v_nombre := NULLIF(btrim(item->>'nombre'), '');

    IF v_codigo IS NULL OR v_nombre IS NULL THEN
      RAISE EXCEPTION 'Todos los productos necesitan código y nombre';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM jsonb_object_keys(item) AS k(clave)
      WHERE clave NOT IN (
        'codigo', 'nombre', 'categoria', 'descripcion',
        'proveedor', 'costo', 'precio', 'stock', 'stock_minimo'
      )
    ) THEN
      RAISE EXCEPTION 'El producto % tiene columnas no permitidas', v_codigo;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM jsonb_each(item) AS e(clave, valor)
      WHERE clave IN (
        'costo', 'precio', 'stock', 'stock_minimo'
      )
      AND (
        jsonb_typeof(valor) <> 'number'
        OR (valor::text)::numeric < 0
      )
    ) THEN
      RAISE EXCEPTION 'Importes o cantidades inválidos para %', v_codigo;
    END IF;

    INSERT INTO public.productos (
      codigo, nombre, categoria, descripcion,
      proveedor, costo, precio, stock, stock_minimo
    )
    VALUES (
      v_codigo,
      v_nombre,
      NULLIF(item->>'categoria', ''),
      NULLIF(item->>'descripcion', ''),
      NULLIF(item->>'proveedor', ''),
      COALESCE((item->>'costo')::numeric, 0),
      COALESCE((item->>'precio')::numeric, 0),
      COALESCE((item->>'stock')::numeric, 0),
      (item->>'stock_minimo')::numeric
    )
    ON CONFLICT (codigo)
      WHERE codigo IS NOT NULL
    DO UPDATE SET
      nombre = EXCLUDED.nombre,
      categoria = CASE
        WHEN item ? 'categoria'
        THEN EXCLUDED.categoria
        ELSE productos.categoria
      END,
      descripcion = CASE
        WHEN item ? 'descripcion'
        THEN EXCLUDED.descripcion
        ELSE productos.descripcion
      END,
      proveedor = CASE
        WHEN item ? 'proveedor'
        THEN EXCLUDED.proveedor
        ELSE productos.proveedor
      END,
      costo = CASE
        WHEN item ? 'costo'
        THEN EXCLUDED.costo
        ELSE productos.costo
      END,
      precio = CASE
        WHEN item ? 'precio'
        THEN EXCLUDED.precio
        ELSE productos.precio
      END,
      stock_minimo = CASE
        WHEN item ? 'stock_minimo'
        THEN EXCLUDED.stock_minimo
        ELSE productos.stock_minimo
      END;

    v_cantidad := v_cantidad + 1;
  END LOOP;

  RETURN v_cantidad;
END;
$$;

CREATE OR REPLACE FUNCTION public.listar_administradores_caja_v11() RETURNS TABLE(usuario_id uuid, correo text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_administrador() THEN
  RAISE EXCEPTION 'Sin autorización';
 END IF;
 RETURN QUERY
 SELECT a.usuario_id, u.email::text
 FROM public.administradores a
 JOIN auth.users u ON u.id = a.usuario_id
 ORDER BY u.email;
END;
$$;

CREATE OR REPLACE FUNCTION public.marcar_venta_v7() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
  -- Identificar ventas registradas desde
  -- la función del carrito V7.
  IF pg_catalog.current_setting(
    'planeta24.venta_carrito_v7',
    true
  ) = 'true'
  OR NEW.medio_pago IN ('mixto', 'fiado')
  OR NEW.cliente_id IS NOT NULL THEN
    NEW.origen_v7 := true;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.proteger_autoria() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
 if tg_op = 'INSERT' then
   if new.registrado_por is distinct from auth.uid() then
     raise exception 'El autor debe ser el usuario autenticado';
   end if;
 elsif new.registrado_por is distinct from old.registrado_por then
   raise exception 'No se puede modificar el autor';
 end if;
 return new;
end; $$;

CREATE OR REPLACE FUNCTION public.registrar_cobro_rapido_mixto_v9(p_total numeric, p_efectivo numeric, p_transferencia numeric, p_nota text DEFAULT NULL::text, p_metodo text DEFAULT 'estimado'::text, p_costo_manual numeric DEFAULT NULL::numeric) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_costo_efectivo numeric;
  v_costo_transferencia numeric;
begin
  if p_total is null or p_total <= 0 or p_efectivo is null or p_transferencia is null
     or p_efectivo <= 0 or p_transferencia <= 0
     or abs(p_total - p_efectivo - p_transferencia) > 0.009 then
    raise exception 'Los dos pagos deben ser positivos y sumar exactamente el total';
  end if;
  if p_metodo not in ('estimado','manual') then
    raise exception 'Método de costo inválido';
  end if;
  if p_metodo = 'manual' and (p_costo_manual is null or p_costo_manual < 0) then
    raise exception 'Ingresá el costo manual';
  end if;
  v_costo_efectivo := case when p_metodo = 'manual' then round(p_costo_manual * p_efectivo / p_total,2) else null end;
  v_costo_transferencia := case when p_metodo = 'manual' then p_costo_manual-v_costo_efectivo else null end;
  perform public.registrar_venta_rapida_v4(
    p_total => p_efectivo,
    p_medio_pago => 'efectivo',
    p_nota => concat(coalesce(p_nota,''),' [Cobro mixto efectivo]'),
    p_metodo => p_metodo,
    p_costo_manual => v_costo_efectivo
  );
  perform public.registrar_venta_rapida_v4(
    p_total => p_transferencia,
    p_medio_pago => 'transferencia',
    p_nota => concat(coalesce(p_nota,''),' [Cobro mixto transferencia]'),
    p_metodo => p_metodo,
    p_costo_manual => v_costo_transferencia
  );
end;
$$;

CREATE OR REPLACE FUNCTION public.registrar_consumo_v8(p_responsable_id uuid, p_producto_id uuid, p_cantidad integer, p_medio_pago text DEFAULT 'adeuda'::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE v_producto record; v_id uuid; v_total numeric(12,2); v_dia date;
BEGIN
 IF auth.uid() IS NULL OR NOT public.es_administrador() THEN RAISE EXCEPTION 'Sin autorización'; END IF;
 IF p_cantidad IS NULL OR p_cantidad<1 OR p_cantidad>1000 THEN RAISE EXCEPTION 'Cantidad inválida'; END IF;
 IF p_medio_pago NOT IN ('efectivo','transferencia','adeuda') OR p_medio_pago IS NULL THEN RAISE EXCEPTION 'Medio de pago inválido'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.responsables_consumo_v8 WHERE id=p_responsable_id AND activo) THEN RAISE EXCEPTION 'Responsable inválido'; END IF;
 v_dia:=(now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
 PERFORM pg_advisory_xact_lock(hashtext('planeta24_caja'),hashtext(v_dia::text));
 IF EXISTS(SELECT 1 FROM public.cierres WHERE fecha_operativa=v_dia) THEN RAISE EXCEPTION 'La caja está cerrada'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.aperturas WHERE fecha_operativa=v_dia) THEN RAISE EXCEPTION 'Primero abrí la caja'; END IF;
 SELECT id,nombre,costo,stock INTO v_producto FROM public.productos WHERE id=p_producto_id AND activo FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Producto inexistente o inactivo'; END IF;
 IF v_producto.stock<p_cantidad THEN RAISE EXCEPTION 'Stock insuficiente'; END IF;
 v_total:=round(v_producto.costo*p_cantidad,2);
 UPDATE public.productos SET stock=stock-p_cantidad WHERE id=p_producto_id;
 INSERT INTO public.consumos_personales_v8(responsable_id,producto_id,producto_nombre,cantidad,costo_unitario,total)
 VALUES(p_responsable_id,p_producto_id,v_producto.nombre,p_cantidad,v_producto.costo,v_total) RETURNING id INTO v_id;
 IF p_medio_pago<>'adeuda' AND v_total>0 THEN
  INSERT INTO public.pagos_consumo_v8(consumo_id,medio_pago,importe) VALUES(v_id,p_medio_pago,v_total);
  INSERT INTO public.movimientos_caja(tipo,medio_pago,importe,descripcion)
  VALUES('ingreso',p_medio_pago,v_total,'Cobro consumo personal '||v_id::text);
 END IF;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.registrar_evento_admin_v117() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
 oldj jsonb := CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END;
 newj jsonb := CASE WHEN TG_OP='DELETE' THEN NULL ELSE to_jsonb(NEW) END;
 actor uuid;
 rowid text;
BEGIN
 -- No guardar datos de autenticación ni contraseñas.
 actor:=auth.uid();
 rowid:=coalesce(newj->>'id',oldj->>'id',newj->>'fecha_operativa',oldj->>'fecha_operativa');
 -- Evitar eventos por actualizaciones sin cambio real.
 IF TG_OP='UPDATE' AND oldj=newj THEN RETURN NEW; END IF;
 INSERT INTO public.eventos_admin_v117(tabla,accion,registro_id,usuario_id,resumen,anterior,nuevo)
 VALUES(TG_TABLE_NAME,TG_OP,rowid,actor,
   TG_TABLE_NAME||' · '||CASE TG_OP WHEN 'INSERT' THEN 'Nuevo registro' WHEN 'UPDATE' THEN 'Modificación' ELSE 'Eliminación' END,
   oldj,newj);
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;$$;

CREATE OR REPLACE FUNCTION public.registrar_gasto_v7(p_concepto text, p_categoria text, p_medio_pago text, p_importe numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_usuario uuid := auth.uid();
  v_dia date := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
  v_gasto_id uuid;
BEGIN
  IF v_usuario IS NULL OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;
  IF p_concepto IS NULL OR length(btrim(p_concepto)) < 3 OR length(p_concepto) > 250 THEN
    RAISE EXCEPTION 'El concepto debe tener entre 3 y 250 caracteres';
  END IF;
  IF p_categoria IS NULL OR p_categoria NOT IN ('operativo','compra_stock','retiro','otro') THEN
    RAISE EXCEPTION 'Categoría inválida';
  END IF;
  IF p_medio_pago IS NULL OR p_medio_pago NOT IN ('efectivo','transferencia') THEN
    RAISE EXCEPTION 'Medio de pago inválido';
  END IF;
  IF p_importe IS NULL OR p_importe <= 0 OR p_importe > 1000000000
     OR round(p_importe, 2) <> p_importe THEN
    RAISE EXCEPTION 'Importe inválido';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('planeta24_caja'),
    pg_catalog.hashtext(v_dia::text)
  );
  IF NOT EXISTS (SELECT 1 FROM public.aperturas WHERE fecha_operativa = v_dia) THEN
    RAISE EXCEPTION 'Primero tenés que abrir la caja';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cierres WHERE fecha_operativa = v_dia) THEN
    RAISE EXCEPTION 'La caja está cerrada: no se pueden registrar gastos';
  END IF;
  INSERT INTO public.gastos (concepto,categoria,medio_pago,importe,registrado_por)
  VALUES (btrim(p_concepto),p_categoria,p_medio_pago,p_importe,v_usuario)
  RETURNING id INTO v_gasto_id;
  RETURN v_gasto_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_movimiento_caja_v7(p_tipo text, p_medio_pago text, p_importe numeric, p_descripcion text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_user uuid := auth.uid();
  v_fecha date := (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
  v_id uuid := gen_random_uuid();
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.administradores WHERE usuario_id = v_user
  ) THEN
    RAISE EXCEPTION 'Acceso denegado: se requiere administrador autenticado';
  END IF;

  IF p_tipo IS NULL OR p_tipo NOT IN ('ingreso','egreso') THEN
    RAISE EXCEPTION 'Tipo inválido: solo ingreso o egreso';
  END IF;
  IF p_medio_pago IS NULL OR p_medio_pago NOT IN ('efectivo','transferencia') THEN
    RAISE EXCEPTION 'Medio de pago inválido';
  END IF;
  IF p_importe IS NULL OR p_importe <= 0 OR p_importe > 1000000000
     OR round(p_importe, 2) <> p_importe THEN
    RAISE EXCEPTION 'Importe inválido: mayor a cero, máximo dos decimales';
  END IF;
  IF p_descripcion IS NULL OR length(btrim(p_descripcion)) < 3 OR length(p_descripcion) > 250 THEN
    RAISE EXCEPTION 'Ingresá una descripción de 3 a 250 caracteres';
  END IF;

  -- Serializa con otras operaciones que utilicen el mismo lock.
  -- Las demás RPC de caja deben usar este lock para garantizar consistencia.
  PERFORM pg_advisory_xact_lock(hashtext('planeta24_caja'), hashtext(v_fecha::text));

  IF NOT EXISTS (SELECT 1 FROM public.aperturas WHERE fecha_operativa = v_fecha) THEN
    RAISE EXCEPTION 'La caja no está abierta hoy';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cierres WHERE fecha_operativa = v_fecha) THEN
    RAISE EXCEPTION 'La caja ya está cerrada';
  END IF;

  INSERT INTO public.movimientos_caja
    (id, fecha, tipo, medio_pago, importe, descripcion, registrado_por)
  VALUES
    (v_id, now(), p_tipo, p_medio_pago, p_importe, btrim(p_descripcion), v_user);

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_venta_carrito_v7(p_items jsonb, p_efectivo numeric DEFAULT 0, p_transferencia numeric DEFAULT 0, p_cliente_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_item jsonb;
  v_producto record;
  v_producto_id uuid;
  v_cantidad numeric;
  v_total numeric := 0;
  v_costo_total numeric := 0;
  v_fiado numeric;
  v_venta_id uuid;
  v_medio_pago text;
  v_ids uuid[];
  v_id uuid;
  v_dia date;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  IF p_items IS NULL
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'El carrito está vacío';
  END IF;

  IF jsonb_array_length(p_items) > 100 THEN
    RAISE EXCEPTION 'Demasiados productos en el carrito';
  END IF;

  IF p_efectivo IS NULL
     OR p_transferencia IS NULL
     OR p_efectivo < 0
     OR p_transferencia < 0 THEN
    RAISE EXCEPTION 'Los pagos no son válidos';
  END IF;

  v_dia := (
    now() AT TIME ZONE
    'America/Argentina/Buenos_Aires'
  )::date;

  -- Bloquear operaciones si la caja está cerrada.
  PERFORM pg_advisory_xact_lock(
    hashtext('planeta24_caja'),
    hashtext(v_dia::text)
  );

  IF EXISTS (
    SELECT 1
    FROM public.cierres
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION 'La caja ya está cerrada';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.aperturas
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION 'Primero tenés que abrir la caja';
  END IF;

  -- Validar formato, cantidades y productos repetidos.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_items) AS e(item)
    WHERE jsonb_typeof(item) <> 'object'
       OR jsonb_typeof(item->'producto_id') <> 'string'
       OR jsonb_typeof(item->'cantidad') <> 'number'
       OR (item->>'cantidad')::numeric <= 0
       OR (item->>'cantidad')::numeric <> 
          trunc((item->>'cantidad')::numeric)
  ) THEN
    RAISE EXCEPTION 'Hay productos o cantidades inválidos';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_items) AS e(item)
    GROUP BY item->>'producto_id'
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Hay productos repetidos en el carrito';
  END IF;

  -- Bloquear productos en orden fijo.
  -- Evita ventas simultáneas con stock insuficiente.
  SELECT array_agg(
    (item->>'producto_id')::uuid
    ORDER BY (item->>'producto_id')::uuid
  )
  INTO v_ids
  FROM jsonb_array_elements(p_items) AS e(item);

  FOREACH v_id IN ARRAY v_ids LOOP
    PERFORM 1
    FROM public.productos
    WHERE id = v_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Producto inexistente';
    END IF;
  END LOOP;

  -- Calcular el total usando precios de la base.
  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(p_items)
  LOOP
    v_producto_id :=
      (v_item->>'producto_id')::uuid;
    v_cantidad :=
      (v_item->>'cantidad')::numeric;

    SELECT id, nombre, precio, costo, stock, activo
    INTO v_producto
    FROM public.productos
    WHERE id = v_producto_id;

    IF NOT v_producto.activo THEN
      RAISE EXCEPTION
        'Producto inactivo: %', v_producto.nombre;
    END IF;

    IF v_producto.stock < v_cantidad THEN
      RAISE EXCEPTION
        'Stock insuficiente: %', v_producto.nombre;
    END IF;

    v_total :=
      v_total + v_producto.precio * v_cantidad;

    v_costo_total :=
      v_costo_total +
      COALESCE(v_producto.costo, 0) * v_cantidad;
  END LOOP;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'El total debe ser mayor a cero';
  END IF;

  IF p_efectivo + p_transferencia > v_total THEN
    RAISE EXCEPTION 'Los pagos superan el total';
  END IF;

  v_fiado :=
    v_total - p_efectivo - p_transferencia;

  IF v_fiado > 0 THEN
    IF p_cliente_id IS NULL THEN
      RAISE EXCEPTION
        'Seleccioná un cliente para el fiado';
    END IF;

    PERFORM 1
    FROM public.clientes_v7
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Cliente inexistente';
    END IF;
  END IF;

  IF v_fiado > 0 AND
     (p_efectivo > 0 OR p_transferencia > 0) THEN
    v_medio_pago := 'mixto';
  ELSIF v_fiado > 0 THEN
    v_medio_pago := 'fiado';
  ELSIF p_efectivo > 0 AND p_transferencia > 0 THEN
    v_medio_pago := 'mixto';
  ELSIF p_efectivo > 0 THEN
    v_medio_pago := 'efectivo';
  ELSE
    v_medio_pago := 'transferencia';
  END IF;

  -- Registrar una sola venta.
  INSERT INTO public.ventas (
      tipo,
      medio_pago,
      total,
      costo_total,
      cliente_id,
      origen_v7,
      registrado_por
    )
    VALUES (
      'productos',
      v_medio_pago,
      v_total,
      v_costo_total,
      p_cliente_id,
      true,
      auth.uid()
    )
  RETURNING id INTO v_venta_id;

  -- Registrar cada producto y descontar stock.
  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(p_items)
  LOOP
    v_producto_id :=
      (v_item->>'producto_id')::uuid;
    v_cantidad :=
      (v_item->>'cantidad')::numeric;

    SELECT nombre, precio, costo
    INTO v_producto
    FROM public.productos
    WHERE id = v_producto_id;

    INSERT INTO public.venta_detalles (
      venta_id,
      producto_id,
      nombre_producto,
      cantidad,
      precio_unitario,
      costo_unitario
    )
    VALUES (
      v_venta_id,
      v_producto_id,
      v_producto.nombre,
      v_cantidad,
      v_producto.precio,
      COALESCE(v_producto.costo, 0)
    );

    UPDATE public.productos
    SET stock = stock - v_cantidad
    WHERE id = v_producto_id;
  END LOOP;

  -- Registrar el efectivo recibido.
  IF p_efectivo > 0 THEN
    INSERT INTO public.pagos_venta_v7 (
      venta_id,
      medio_pago,
      importe,
      registrado_por
    )
    VALUES (
      v_venta_id,
      'efectivo',
      p_efectivo,
      auth.uid()
    );
  END IF;

  -- Registrar la transferencia recibida.
  IF p_transferencia > 0 THEN
    INSERT INTO public.pagos_venta_v7 (
      venta_id,
      medio_pago,
      importe,
      registrado_por
    )
    VALUES (
      v_venta_id,
      'transferencia',
      p_transferencia,
      auth.uid()
    );
  END IF;

  RETURN v_venta_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_venta_producto(p_producto_id uuid, p_cantidad numeric, p_medio_pago text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_producto record;
  v_venta_id uuid;
  v_total numeric;
  v_costo numeric;
  v_dia date := (
    now() AT TIME ZONE 'America/Argentina/Buenos_Aires'
  )::date;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  -- Mismo bloqueo de coordinación usado por el cierre.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('planeta24_caja'),
    pg_catalog.hashtext(v_dia::text)
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.aperturas
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION
      '👽 Primero tenés que abrir la caja';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cierres
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION
      '👽 Caja cerrada: no se pueden registrar ventas';
  END IF;

  IF p_producto_id IS NULL
     OR p_cantidad IS NULL
     OR p_cantidad <= 0
     OR p_cantidad <> trunc(p_cantidad) THEN
    RAISE EXCEPTION 'Producto o cantidad inválidos';
  END IF;

  IF p_medio_pago IS NULL
     OR p_medio_pago NOT IN ('efectivo', 'transferencia') THEN
    RAISE EXCEPTION 'Medio de pago inválido';
  END IF;

  SELECT id, nombre, precio, costo, stock
  INTO v_producto
  FROM public.productos
  WHERE id = p_producto_id
    AND activo = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Producto no encontrado o inactivo';
  END IF;

  IF v_producto.stock < p_cantidad THEN
    RAISE EXCEPTION 'Stock insuficiente';
  END IF;

  v_total := v_producto.precio * p_cantidad;
  v_costo := v_producto.costo * p_cantidad;

  IF v_total <= 0 THEN
    RAISE EXCEPTION 'El total debe ser mayor que cero';
  END IF;

  INSERT INTO public.ventas (
    tipo,
    medio_pago,
    total,
    costo_total,
    metodo_costo_v4,
    registrado_por
  )
  VALUES (
    'productos',
    p_medio_pago,
    v_total,
    v_costo,
    'producto',
    auth.uid()
  )
  RETURNING id INTO v_venta_id;

  INSERT INTO public.venta_detalles (
    venta_id,
    producto_id,
    nombre_producto,
    cantidad,
    precio_unitario,
    costo_unitario
  )
  VALUES (
    v_venta_id,
    v_producto.id,
    v_producto.nombre,
    p_cantidad,
    v_producto.precio,
    v_producto.costo
  );

  UPDATE public.productos
  SET stock = stock - p_cantidad
  WHERE id = p_producto_id;

  RETURN v_venta_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_venta_rapida_v4(p_total numeric, p_medio_pago text, p_nota text DEFAULT NULL::text, p_metodo text DEFAULT 'estimado'::text, p_costo_manual numeric DEFAULT NULL::numeric) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_margen numeric;
  v_costo numeric;
  v_venta_id uuid;
  v_dia date := (
    now() AT TIME ZONE 'America/Argentina/Buenos_Aires'
  )::date;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.es_administrador() THEN
    RAISE EXCEPTION 'Sin autorización';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('planeta24_caja'),
    pg_catalog.hashtext(v_dia::text)
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.aperturas
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION
      '👽 Primero tenés que abrir la caja';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cierres
    WHERE fecha_operativa = v_dia
  ) THEN
    RAISE EXCEPTION
      '👽 Caja cerrada: no se pueden registrar ventas';
  END IF;

  IF p_total IS NULL OR p_total <= 0 THEN
    RAISE EXCEPTION 'El total debe ser mayor que cero';
  END IF;

  IF p_medio_pago IS NULL
     OR p_medio_pago NOT IN ('efectivo', 'transferencia') THEN
    RAISE EXCEPTION 'Medio de pago inválido';
  END IF;

  IF p_metodo IS NULL
     OR p_metodo NOT IN ('estimado', 'manual') THEN
    RAISE EXCEPTION 'Método de costo inválido';
  END IF;

  IF p_metodo = 'manual' THEN
    IF p_costo_manual IS NULL OR p_costo_manual < 0 THEN
      RAISE EXCEPTION 'Costo manual inválido';
    END IF;

    v_costo := p_costo_manual;
  ELSE
    SELECT margen_estimado
    INTO v_margen
    FROM public.configuracion_v4
    WHERE id = 1;

    IF v_margen IS NULL THEN
      RAISE EXCEPTION
        'Falta configurar el margen estimado';
    END IF;

    IF v_margen < 0 OR v_margen > 100 THEN
      RAISE EXCEPTION
        'Margen estimado fuera de rango';
    END IF;

    v_costo := ROUND(
      p_total * (1 - v_margen / 100), 2
    );
  END IF;

  INSERT INTO public.ventas (
    tipo,
    medio_pago,
    total,
    costo_total,
    nota,
    metodo_costo_v4,
    registrado_por
  )
  VALUES (
    'rapida',
    p_medio_pago,
    p_total,
    v_costo,
    p_nota,
    p_metodo,
    auth.uid()
  )
  RETURNING id INTO v_venta_id;

  RETURN v_venta_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resumen_fiados_v7() RETURNS TABLE(venta_id uuid, cliente_id uuid, cliente_nombre text, fecha_venta timestamp with time zone, total_venta numeric, total_cobrado numeric, saldo_pendiente numeric, estado text)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  SELECT
    v.id AS venta_id,
    v.cliente_id,
    c.nombre AS cliente_nombre,
    v.fecha AS fecha_venta,
    v.total AS total_venta,
    COALESCE(p.cobrado, 0) AS total_cobrado,
    GREATEST(
      v.total - COALESCE(p.cobrado, 0),
      0
    ) AS saldo_pendiente,
    CASE
      WHEN COALESCE(p.cobrado, 0) = 0
        THEN 'Pendiente'
      WHEN COALESCE(p.cobrado, 0) < v.total
        THEN 'Pago parcial'
      ELSE 'Pagado'
    END AS estado
  FROM public.ventas v
  JOIN public.clientes_v7 c
    ON c.id = v.cliente_id
  LEFT JOIN (
    SELECT
      venta_id,
      SUM(importe) AS cobrado
    FROM public.pagos_venta_v7
    GROUP BY venta_id
  ) p ON p.venta_id = v.id
  WHERE v.cliente_id IS NOT NULL;
$$;

-- 5. Disparadores.


DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.anotaciones;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.aperturas;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.auditoria_caja_v11;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.auditoria_stock_v11_9;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.cierres;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.clientes_v7;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.configuracion_v4;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.consumos_personales_v8;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.gastos;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.movimientos_caja;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.pagos_consumo_v8;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.pagos_venta_v7;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.productos;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.venta_detalles;

DROP TRIGGER IF EXISTS p24_evento_admin_v117 ON public.ventas;

DROP TRIGGER IF EXISTS proteger_autoria ON public.anotaciones;

DROP TRIGGER IF EXISTS proteger_autoria ON public.gastos;

DROP TRIGGER IF EXISTS proteger_autoria ON public.movimientos_caja;

DROP TRIGGER IF EXISTS proteger_autoria ON public.ventas;

DROP TRIGGER IF EXISTS trg_marcar_venta_v7 ON public.ventas;

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.anotaciones FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.aperturas FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.auditoria_caja_v11 FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT ON public.auditoria_stock_v11_9 FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.cierres FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.clientes_v7 FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.configuracion_v4 FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.consumos_personales_v8 FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.gastos FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.movimientos_caja FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.pagos_consumo_v8 FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.pagos_venta_v7 FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.productos FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.venta_detalles FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER p24_evento_admin_v117 AFTER INSERT OR DELETE OR UPDATE ON public.ventas FOR EACH ROW EXECUTE FUNCTION public.registrar_evento_admin_v117();

CREATE TRIGGER proteger_autoria BEFORE INSERT OR UPDATE ON public.anotaciones FOR EACH ROW EXECUTE FUNCTION public.proteger_autoria();

CREATE TRIGGER proteger_autoria BEFORE INSERT OR UPDATE ON public.gastos FOR EACH ROW EXECUTE FUNCTION public.proteger_autoria();

CREATE TRIGGER proteger_autoria BEFORE INSERT OR UPDATE ON public.movimientos_caja FOR EACH ROW EXECUTE FUNCTION public.proteger_autoria();

CREATE TRIGGER proteger_autoria BEFORE INSERT OR UPDATE ON public.ventas FOR EACH ROW EXECUTE FUNCTION public.proteger_autoria();

CREATE TRIGGER trg_marcar_venta_v7 BEFORE INSERT ON public.ventas FOR EACH ROW EXECUTE FUNCTION public.marcar_venta_v7();

-- 6. Políticas RLS según TEST.


DROP POLICY IF EXISTS admin_select ON public.administradores;

DROP POLICY IF EXISTS admin_insert ON public.anotaciones;

DROP POLICY IF EXISTS admin_select ON public.anotaciones;

DROP POLICY IF EXISTS admin_update ON public.anotaciones;

DROP POLICY IF EXISTS admin_select ON public.aperturas;

DROP POLICY IF EXISTS auditoria_caja_v11_admin_lectura ON public.auditoria_caja_v11;

DROP POLICY IF EXISTS auditoria_stock_admin_select ON public.auditoria_stock_v11_9;

DROP POLICY IF EXISTS admin_insert ON public.cierres;

DROP POLICY IF EXISTS admin_select ON public.cierres;

DROP POLICY IF EXISTS admin_update ON public.cierres;

DROP POLICY IF EXISTS clientes_v7_admin_select ON public.clientes_v7;

DROP POLICY IF EXISTS admin_select ON public.configuracion_v4;

DROP POLICY IF EXISTS v4_config_read ON public.configuracion_v4;

DROP POLICY IF EXISTS consumos_v8_admin_select ON public.consumos_personales_v8;

DROP POLICY IF EXISTS ev_admin_leidos_delete_v117 ON public.eventos_admin_leidos_v117;

DROP POLICY IF EXISTS ev_admin_leidos_insert_v117 ON public.eventos_admin_leidos_v117;

DROP POLICY IF EXISTS ev_admin_leidos_select_v117 ON public.eventos_admin_leidos_v117;

DROP POLICY IF EXISTS ev_admin_lectura_v117 ON public.eventos_admin_v117;

DROP POLICY IF EXISTS admin_insert ON public.gastos;

DROP POLICY IF EXISTS admin_select ON public.gastos;

DROP POLICY IF EXISTS admin_update ON public.gastos;

DROP POLICY IF EXISTS admin_insert ON public.movimientos_caja;

DROP POLICY IF EXISTS admin_select ON public.movimientos_caja;

DROP POLICY IF EXISTS admin_update ON public.movimientos_caja;

DROP POLICY IF EXISTS pagos_v8_admin_select ON public.pagos_consumo_v8;

DROP POLICY IF EXISTS pagos_v7_admin_select ON public.pagos_venta_v7;

DROP POLICY IF EXISTS admin_insert ON public.productos;

DROP POLICY IF EXISTS admin_select ON public.productos;

DROP POLICY IF EXISTS admin_update ON public.productos;

DROP POLICY IF EXISTS responsables_v8_admin_select ON public.responsables_consumo_v8;

DROP POLICY IF EXISTS admin_insert ON public.venta_detalles;

DROP POLICY IF EXISTS admin_select ON public.venta_detalles;

DROP POLICY IF EXISTS admin_update ON public.venta_detalles;

DROP POLICY IF EXISTS admin_insert ON public.ventas;

DROP POLICY IF EXISTS admin_select ON public.ventas;

DROP POLICY IF EXISTS admin_update ON public.ventas;

ALTER TABLE public.administradores ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.anotaciones ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.aperturas ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.auditoria_caja_v11 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.auditoria_stock_v11_9 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.cierres ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.clientes_v7 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.configuracion_v4 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.consumos_personales_v8 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.eventos_admin_leidos_v117 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.eventos_admin_v117 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.gastos ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.movimientos_caja ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.pagos_consumo_v8 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.pagos_venta_v7 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.productos ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.responsables_consumo_v8 ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.venta_detalles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.ventas ENABLE ROW LEVEL SECURITY;

CREATE POLICY admin_insert ON public.anotaciones FOR INSERT TO authenticated WITH CHECK (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.administradores FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.anotaciones FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.aperturas FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.cierres FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.configuracion_v4 FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.gastos FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.movimientos_caja FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.productos FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.venta_detalles FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_select ON public.ventas FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY admin_update ON public.anotaciones FOR UPDATE TO authenticated USING (( SELECT public.es_administrador() AS es_administrador)) WITH CHECK (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY auditoria_caja_v11_admin_lectura ON public.auditoria_caja_v11 FOR SELECT TO authenticated USING (public.es_administrador());

CREATE POLICY auditoria_stock_admin_select ON public.auditoria_stock_v11_9 FOR SELECT TO authenticated USING (public.es_administrador());

CREATE POLICY clientes_v7_admin_select ON public.clientes_v7 FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY consumos_v8_admin_select ON public.consumos_personales_v8 FOR SELECT TO authenticated USING (public.es_administrador());

CREATE POLICY ev_admin_lectura_v117 ON public.eventos_admin_v117 FOR SELECT TO authenticated USING (((( SELECT auth.uid() AS uid) = '2d7a4aca-85d5-4da5-bf90-8281b6ae4ff9'::uuid) AND public.es_administrador()));

CREATE POLICY ev_admin_leidos_delete_v117 ON public.eventos_admin_leidos_v117 FOR DELETE TO authenticated USING (((usuario_id = ( SELECT auth.uid() AS uid)) AND (( SELECT auth.uid() AS uid) = '2d7a4aca-85d5-4da5-bf90-8281b6ae4ff9'::uuid) AND public.es_administrador()));

CREATE POLICY ev_admin_leidos_insert_v117 ON public.eventos_admin_leidos_v117 FOR INSERT TO authenticated WITH CHECK (((usuario_id = ( SELECT auth.uid() AS uid)) AND (( SELECT auth.uid() AS uid) = '2d7a4aca-85d5-4da5-bf90-8281b6ae4ff9'::uuid) AND public.es_administrador()));

CREATE POLICY ev_admin_leidos_select_v117 ON public.eventos_admin_leidos_v117 FOR SELECT TO authenticated USING (((usuario_id = ( SELECT auth.uid() AS uid)) AND (( SELECT auth.uid() AS uid) = '2d7a4aca-85d5-4da5-bf90-8281b6ae4ff9'::uuid) AND public.es_administrador()));

CREATE POLICY pagos_v7_admin_select ON public.pagos_venta_v7 FOR SELECT TO authenticated USING (( SELECT public.es_administrador() AS es_administrador));

CREATE POLICY pagos_v8_admin_select ON public.pagos_consumo_v8 FOR SELECT TO authenticated USING (public.es_administrador());

CREATE POLICY responsables_v8_admin_select ON public.responsables_consumo_v8 FOR SELECT TO authenticated USING (public.es_administrador());

-- 7. Grants: lectura para authenticated; escrituras por RPC,
-- excepto anotaciones y avisos leídos, que el HTML modifica directamente.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT, UPDATE ON public.anotaciones TO authenticated;
GRANT INSERT, DELETE ON public.eventos_admin_leidos_v117 TO authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.proteger_autoria() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.marcar_venta_v7() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.registrar_evento_admin_v117() FROM authenticated;

-- 8. Responsables de configuración; no se copian consumos de TEST.
INSERT INTO public.responsables_consumo_v8 (nombre, activo)
VALUES ('Karen', true), ('Sebastián', true)
ON CONFLICT (nombre) DO UPDATE SET activo = true;

COMMIT;
