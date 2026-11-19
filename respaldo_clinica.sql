--
-- PostgreSQL database dump
--

\restrict 8qWajgTFkqEL7o5F0qAgEnHHvl50QYmWC7jDegl2nPTTrCE99JUeqO0BUtHlrr1

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

-- Started on 2026-11-19 15:52:36

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 2 (class 3079 OID 17855)
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- TOC entry 5528 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- TOC entry 381 (class 1255 OID 16695)
-- Name: agenda_diaria(integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.agenda_diaria(p_id_medico integer, p_fecha date) RETURNS TABLE(id_cita integer, hora time without time zone, paciente text, consultorio character varying, motivo character varying, estado character varying)
    LANGUAGE sql STABLE
    AS $$
    SELECT c.id_cita, c.hora,
           p.nombres || ' ' || p.apellidos,
           k.numero, c.motivo, c.estado
    FROM cita c
    JOIN paciente p    ON p.id_paciente = c.id_paciente
    JOIN consultorio k ON k.id_consultorio = c.id_consultorio
    WHERE c.id_medico = p_id_medico
      AND c.fecha = p_fecha
      AND c.estado <> 'Cancelada'
    ORDER BY c.hora;
$$;


ALTER FUNCTION public.agenda_diaria(p_id_medico integer, p_fecha date) OWNER TO postgres;

--
-- TOC entry 412 (class 1255 OID 18655)
-- Name: atender_cita(integer, text, text, numeric, character varying, jsonb, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.atender_cita(IN p_id_cita integer, IN p_diagnostico text, IN p_observaciones text, IN p_valor_servicios numeric, IN p_metodo_pago character varying DEFAULT 'Efectivo'::character varying, IN p_formula jsonb DEFAULT NULL::jsonb, IN p_codigo_cie10 character varying DEFAULT NULL::character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_estado      VARCHAR;
    v_id_historia INTEGER;
    v_valor_med   NUMERIC(12,2) := 0;
BEGIN
    SELECT estado INTO v_estado
    FROM cita WHERE id_cita = p_id_cita FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cita % no existe', p_id_cita;
    END IF;
    IF v_estado <> 'Programada' THEN
        RAISE EXCEPTION 'La cita % está %; solo se atienden citas Programadas',
                        p_id_cita, v_estado;
    END IF;

    UPDATE cita SET estado = 'Atendida' WHERE id_cita = p_id_cita;

    INSERT INTO historia_clinica (id_cita, diagnostico, observaciones, codigo_cie10)
    VALUES (p_id_cita, p_diagnostico, p_observaciones, p_codigo_cie10)
    RETURNING id_historia INTO v_id_historia;

    IF p_formula IS NOT NULL AND jsonb_array_length(p_formula) > 0 THEN
        INSERT INTO formula_medica
            (id_historia, id_medicamento, dosis, frecuencia, duracion_dias, cantidad)
        SELECT v_id_historia, f.id_medicamento, f.dosis, f.frecuencia,
               f.duracion_dias, COALESCE(f.cantidad, 1)
        FROM jsonb_to_recordset(p_formula)
             AS f(id_medicamento INTEGER, dosis TEXT, frecuencia TEXT,
                  duracion_dias INTEGER, cantidad INTEGER);

        SELECT COALESCE(SUM(fm.cantidad * m.precio_unitario), 0)
        INTO v_valor_med
        FROM formula_medica fm
        JOIN medicamento m ON m.id_medicamento = fm.id_medicamento
        WHERE fm.id_historia = v_id_historia;
    END IF;

    INSERT INTO factura (id_cita, valor_servicios, valor_medicamentos, metodo_pago)
    VALUES (p_id_cita, p_valor_servicios, v_valor_med, p_metodo_pago);
END $$;


ALTER PROCEDURE public.atender_cita(IN p_id_cita integer, IN p_diagnostico text, IN p_observaciones text, IN p_valor_servicios numeric, IN p_metodo_pago character varying, IN p_formula jsonb, IN p_codigo_cie10 character varying) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 227 (class 1259 OID 17665)
-- Name: medico; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.medico (
    id_medico integer NOT NULL,
    documento character varying(20) NOT NULL,
    nombres character varying(100) NOT NULL,
    apellidos character varying(100) NOT NULL,
    registro_profesional character varying(30) NOT NULL,
    telefono character varying(20) NOT NULL,
    correo character varying(120) NOT NULL,
    id_especialidad integer NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    tipo_documento character varying(3) NOT NULL,
    CONSTRAINT medico_correo_check CHECK (((correo)::text ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text))
);


ALTER TABLE public.medico OWNER TO postgres;

--
-- TOC entry 471 (class 1255 OID 17831)
-- Name: buscar_medico(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.buscar_medico(p_texto text) RETURNS SETOF public.medico
    LANGUAGE sql STABLE
    AS $$
    SELECT *
    FROM medico
    WHERE documento = p_texto
       OR (nombres || ' ' || apellidos) ILIKE '%' || p_texto || '%'
    ORDER BY apellidos, nombres;
$$;


ALTER FUNCTION public.buscar_medico(p_texto text) OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 17634)
-- Name: paciente; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.paciente (
    id_paciente integer NOT NULL,
    documento character varying(20) NOT NULL,
    nombres character varying(100) NOT NULL,
    apellidos character varying(100) NOT NULL,
    fecha_nacimiento date NOT NULL,
    telefono character varying(20),
    correo character varying(120),
    id_eps integer,
    tipo_documento character varying(3) NOT NULL,
    tipo_vinculacion character varying(12) DEFAULT 'EPS'::character varying NOT NULL,
    CONSTRAINT paciente_correo_check CHECK (((correo)::text ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text)),
    CONSTRAINT paciente_fecha_nacimiento_check CHECK ((fecha_nacimiento >= '1900-01-01'::date)),
    CONSTRAINT paciente_vinculacion_eps_chk CHECK ((((tipo_vinculacion)::text = 'PARTICULAR'::text) = (id_eps IS NULL)))
);


ALTER TABLE public.paciente OWNER TO postgres;

--
-- TOC entry 280 (class 1255 OID 17830)
-- Name: buscar_paciente(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.buscar_paciente(p_texto text) RETURNS SETOF public.paciente
    LANGUAGE sql STABLE
    AS $$
    SELECT *
    FROM paciente
    WHERE documento = p_texto
       OR (nombres || ' ' || apellidos) ILIKE '%' || p_texto || '%'
    ORDER BY apellidos, nombres;
$$;


ALTER FUNCTION public.buscar_paciente(p_texto text) OWNER TO postgres;

--
-- TOC entry 457 (class 1255 OID 16699)
-- Name: cancelar_cita(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancelar_cita(IN p_id_cita integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE cita SET estado = 'Cancelada'
    WHERE id_cita = p_id_cita AND estado = 'Programada';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cita % no existe o no está Programada', p_id_cita;
    END IF;
END $$;


ALTER PROCEDURE public.cancelar_cita(IN p_id_cita integer) OWNER TO postgres;

--
-- TOC entry 291 (class 1255 OID 18694)
-- Name: consultorios_libres(date, time without time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.consultorios_libres(p_fecha date, p_hora time without time zone, p_duracion_min integer DEFAULT 30) RETURNS TABLE(id_consultorio integer, numero character varying, piso smallint)
    LANGUAGE sql STABLE
    AS $$
SELECT k.id_consultorio, k.numero, k.piso
FROM consultorio k
WHERE k.disponible
  AND NOT EXISTS (SELECT 1 FROM cita c
                  WHERE c.id_consultorio = k.id_consultorio
                    AND c.fecha = p_fecha
                    AND c.estado <> 'Cancelada'
                    AND c.hora < p_hora + make_interval(mins => p_duracion_min)
                    AND c.hora_fin > p_hora)
ORDER BY k.piso, k.numero;
$$;


ALTER FUNCTION public.consultorios_libres(p_fecha date, p_hora time without time zone, p_duracion_min integer) OWNER TO postgres;

--
-- TOC entry 431 (class 1255 OID 16697)
-- Name: facturas_pendientes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.facturas_pendientes() RETURNS TABLE(id_factura integer, paciente text, documento character varying, valor_total numeric, fecha_emision timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT f.id_factura,
           p.nombres || ' ' || p.apellidos,
           p.documento,
           f.valor_total,
           f.fecha_emision
    FROM factura f
    JOIN cita c     ON c.id_cita = f.id_cita
    JOIN paciente p ON p.id_paciente = c.id_paciente
    WHERE f.estado = 'Pendiente'
    ORDER BY f.fecha_emision;
$$;


ALTER FUNCTION public.facturas_pendientes() OWNER TO postgres;

--
-- TOC entry 424 (class 1255 OID 16687)
-- Name: fn_validar_cita(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_cita() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado <> 'Programada' THEN
            RAISE EXCEPTION 'Toda cita nueva debe crearse en estado Programada';
        END IF;
    ELSE
        IF OLD.estado <> NEW.estado AND OLD.estado <> 'Programada' THEN
            RAISE EXCEPTION 'La cita % ya está % y no puede cambiar de estado',
                OLD.id_cita, OLD.estado;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' OR NEW.id_medico <> OLD.id_medico THEN
        IF NOT EXISTS (SELECT 1 FROM medico
                       WHERE id_medico = NEW.id_medico AND activo) THEN
            RAISE EXCEPTION 'El médico % no está activo', NEW.id_medico;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' OR NEW.id_consultorio <> OLD.id_consultorio THEN
        IF NOT EXISTS (SELECT 1 FROM consultorio
                       WHERE id_consultorio = NEW.id_consultorio AND disponible) THEN
            RAISE EXCEPTION 'El consultorio % no está disponible', NEW.id_consultorio;
        END IF;
    END IF;

    RETURN NEW;
END $$;


ALTER FUNCTION public.fn_validar_cita() OWNER TO postgres;

--
-- TOC entry 338 (class 1255 OID 16689)
-- Name: fn_validar_historia(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_historia() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cita
                   WHERE id_cita = NEW.id_cita AND estado = 'Atendida') THEN
        RAISE EXCEPTION 'La historia clínica solo se registra para citas Atendidas';
    END IF;
    RETURN NEW;
END $$;


ALTER FUNCTION public.fn_validar_historia() OWNER TO postgres;

--
-- TOC entry 330 (class 1255 OID 18691)
-- Name: fn_validar_horario_cita(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_horario_cita() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_fin time := NEW.hora + make_interval(mins => NEW.duracion_min);
BEGIN
    IF NEW.estado = 'Cancelada' THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE'
       AND (NEW.id_medico, NEW.fecha, NEW.hora, NEW.duracion_min)
           IS NOT DISTINCT FROM
           (OLD.id_medico, OLD.fecha, OLD.hora, OLD.duracion_min) THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (SELECT 1
                   FROM horario_medico h
                   WHERE h.id_medico  = NEW.id_medico
                     AND h.dia_semana = EXTRACT(ISODOW FROM NEW.fecha)
                     AND NEW.hora >= h.hora_inicio
                     AND v_fin > NEW.hora
                     AND v_fin <= h.hora_fin) THEN
        RAISE EXCEPTION
            'La cita (% de % a %) queda fuera del horario de atención del médico %',
            NEW.fecha, NEW.hora, v_fin, NEW.id_medico;
    END IF;

    RETURN NEW;
END $$;


ALTER FUNCTION public.fn_validar_horario_cita() OWNER TO postgres;

--
-- TOC entry 272 (class 1255 OID 16696)
-- Name: historia_paciente(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.historia_paciente(p_id_paciente integer) RETURNS TABLE(fecha_registro timestamp with time zone, fecha_cita date, medico text, diagnostico text, observaciones text, medicamentos text)
    LANGUAGE sql STABLE
    AS $$
    SELECT h.fecha_registro, c.fecha,
           m.nombres || ' ' || m.apellidos,
           h.diagnostico, h.observaciones,
           (SELECT string_agg(md.nombre || ' ' || md.concentracion || ' - ' ||
                              f.dosis || ', ' || f.frecuencia || ', ' ||
                              f.duracion_dias || ' días', '; ')
            FROM formula_medica f
            JOIN medicamento md ON md.id_medicamento = f.id_medicamento
            WHERE f.id_historia = h.id_historia)
    FROM historia_clinica h
    JOIN cita c   ON c.id_cita = h.id_cita
    JOIN medico m ON m.id_medico = c.id_medico
    WHERE c.id_paciente = p_id_paciente
    ORDER BY h.fecha_registro;
$$;


ALTER FUNCTION public.historia_paciente(p_id_paciente integer) OWNER TO postgres;

--
-- TOC entry 296 (class 1255 OID 17334)
-- Name: marcar_inasistencia(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.marcar_inasistencia(IN p_id_cita integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_fecha   DATE;
    v_hora    TIME;
    v_estado  VARCHAR;
BEGIN
    SELECT fecha, hora, estado INTO v_fecha, v_hora, v_estado
    FROM cita WHERE id_cita = p_id_cita;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cita % no existe', p_id_cita;
    END IF;
    IF v_estado <> 'Programada' THEN
        RAISE EXCEPTION 'La cita % está %; solo una cita Programada puede marcarse Inasistida',
            p_id_cita, v_estado;
    END IF;
    IF (v_fecha + v_hora) > LOCALTIMESTAMP THEN
        RAISE EXCEPTION 'La cita % aún no ha ocurrido, no puede marcarse Inasistida', p_id_cita;
    END IF;

    UPDATE cita SET estado = 'Inasistida' WHERE id_cita = p_id_cita;
END $$;


ALTER PROCEDURE public.marcar_inasistencia(IN p_id_cita integer) OWNER TO postgres;

--
-- TOC entry 293 (class 1255 OID 18693)
-- Name: medicos_libres(date, time without time zone, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.medicos_libres(p_fecha date, p_hora time without time zone, p_duracion_min integer DEFAULT 30) RETURNS TABLE(id_medico integer, nombre_medico text, registro_profesional character varying, especialidad character varying)
    LANGUAGE sql STABLE
    AS $$
SELECT m.id_medico,
       m.nombres || ' ' || m.apellidos,
       m.registro_profesional,
       e.nombre
FROM medico m
JOIN especialidad e ON e.id_especialidad = m.id_especialidad
WHERE m.activo
  AND EXISTS (SELECT 1 FROM horario_medico h
              WHERE h.id_medico  = m.id_medico
                AND h.dia_semana = EXTRACT(ISODOW FROM p_fecha)
                AND p_hora >= h.hora_inicio
                AND p_hora + make_interval(mins => p_duracion_min) <= h.hora_fin)
  AND NOT EXISTS (SELECT 1 FROM cita c
                  WHERE c.id_medico = m.id_medico
                    AND c.fecha = p_fecha
                    AND c.estado <> 'Cancelada'
                    AND c.hora < p_hora + make_interval(mins => p_duracion_min)
                    AND c.hora_fin > p_hora)
ORDER BY m.apellidos, m.nombres;
$$;


ALTER FUNCTION public.medicos_libres(p_fecha date, p_hora time without time zone, p_duracion_min integer) OWNER TO postgres;

--
-- TOC entry 342 (class 1255 OID 16700)
-- Name: registrar_pago(integer, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.registrar_pago(IN p_id_factura integer, IN p_metodo_pago character varying DEFAULT NULL::character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    UPDATE factura
    SET estado      = 'Pagada',
        fecha_pago  = now(),
        metodo_pago = COALESCE(p_metodo_pago, metodo_pago)
    WHERE id_factura = p_id_factura AND estado = 'Pendiente';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe o ya está Pagada', p_id_factura;
    END IF;
END $$;


ALTER PROCEDURE public.registrar_pago(IN p_id_factura integer, IN p_metodo_pago character varying) OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 18638)
-- Name: cie10; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cie10 (
    codigo character varying(5) NOT NULL,
    descripcion character varying(300) NOT NULL,
    categoria character varying(3) GENERATED ALWAYS AS ("left"((codigo)::text, 3)) STORED,
    activo boolean DEFAULT true NOT NULL
);


ALTER TABLE public.cie10 OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 17704)
-- Name: cita; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cita (
    id_cita integer NOT NULL,
    id_paciente integer NOT NULL,
    id_medico integer NOT NULL,
    id_consultorio integer NOT NULL,
    fecha date NOT NULL,
    hora time without time zone NOT NULL,
    motivo character varying(255) NOT NULL,
    estado character varying(10) DEFAULT 'Programada'::character varying NOT NULL,
    duracion_min smallint DEFAULT 30 NOT NULL,
    hora_fin time without time zone GENERATED ALWAYS AS ((hora + make_interval(mins => (duracion_min)::integer))) STORED,
    CONSTRAINT cita_duracion_chk CHECK (((duracion_min >= 10) AND (duracion_min <= 240))),
    CONSTRAINT cita_estado_check CHECK (((estado)::text = ANY ((ARRAY['Programada'::character varying, 'Atendida'::character varying, 'Cancelada'::character varying, 'Inasistida'::character varying])::text[]))),
    CONSTRAINT cita_fin_mismo_dia_chk CHECK ((hora_fin > hora))
);


ALTER TABLE public.cita OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 17703)
-- Name: cita_id_cita_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.cita ALTER COLUMN id_cita ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.cita_id_cita_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 229 (class 1259 OID 17691)
-- Name: consultorio; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.consultorio (
    id_consultorio integer NOT NULL,
    numero character varying(10) NOT NULL,
    piso smallint NOT NULL,
    disponible boolean DEFAULT true NOT NULL
);


ALTER TABLE public.consultorio OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 17690)
-- Name: consultorio_id_consultorio_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.consultorio ALTER COLUMN id_consultorio ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.consultorio_id_consultorio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 221 (class 1259 OID 17624)
-- Name: eps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.eps (
    id_eps integer NOT NULL,
    nombre character varying(100) NOT NULL
);


ALTER TABLE public.eps OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 17623)
-- Name: eps_id_eps_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.eps ALTER COLUMN id_eps ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.eps_id_eps_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 225 (class 1259 OID 17655)
-- Name: especialidad; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.especialidad (
    id_especialidad integer NOT NULL,
    nombre character varying(80) NOT NULL
);


ALTER TABLE public.especialidad OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 17654)
-- Name: especialidad_id_especialidad_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.especialidad ALTER COLUMN id_especialidad ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.especialidad_id_especialidad_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 238 (class 1259 OID 17796)
-- Name: factura; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.factura (
    id_factura integer NOT NULL,
    id_cita integer NOT NULL,
    valor_servicios numeric(12,2) NOT NULL,
    valor_medicamentos numeric(12,2) DEFAULT 0 NOT NULL,
    valor_total numeric(12,2) GENERATED ALWAYS AS ((valor_servicios + valor_medicamentos)) STORED,
    metodo_pago character varying(15) NOT NULL,
    estado character varying(10) DEFAULT 'Pendiente'::character varying NOT NULL,
    fecha_emision timestamp with time zone DEFAULT now() NOT NULL,
    fecha_pago timestamp with time zone,
    CONSTRAINT factura_check CHECK ((((estado)::text = 'Pagada'::text) = (fecha_pago IS NOT NULL))),
    CONSTRAINT factura_estado_check CHECK (((estado)::text = ANY ((ARRAY['Pendiente'::character varying, 'Pagada'::character varying])::text[]))),
    CONSTRAINT factura_metodo_pago_check CHECK (((metodo_pago)::text = ANY ((ARRAY['Efectivo'::character varying, 'Tarjeta'::character varying, 'Transferencia'::character varying])::text[]))),
    CONSTRAINT factura_valor_medicamentos_check CHECK ((valor_medicamentos >= (0)::numeric)),
    CONSTRAINT factura_valor_servicios_check CHECK ((valor_servicios >= (0)::numeric))
);


ALTER TABLE public.factura OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 17795)
-- Name: factura_id_factura_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.factura ALTER COLUMN id_factura ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.factura_id_factura_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 236 (class 1259 OID 17771)
-- Name: formula_medica; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.formula_medica (
    id_historia integer NOT NULL,
    id_medicamento integer NOT NULL,
    dosis character varying(100) NOT NULL,
    frecuencia character varying(100) NOT NULL,
    duracion_dias smallint NOT NULL,
    cantidad smallint DEFAULT 1 NOT NULL,
    CONSTRAINT formula_medica_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT formula_medica_duracion_dias_check CHECK ((duracion_dias > 0))
);


ALTER TABLE public.formula_medica OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 17737)
-- Name: historia_clinica; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.historia_clinica (
    id_historia integer NOT NULL,
    id_cita integer NOT NULL,
    diagnostico text NOT NULL,
    observaciones text,
    fecha_registro timestamp with time zone DEFAULT now() NOT NULL,
    codigo_cie10 character varying(5)
);


ALTER TABLE public.historia_clinica OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 17736)
-- Name: historia_clinica_id_historia_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.historia_clinica ALTER COLUMN id_historia ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.historia_clinica_id_historia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 244 (class 1259 OID 18671)
-- Name: horario_medico; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.horario_medico (
    id_horario integer NOT NULL,
    id_medico integer NOT NULL,
    dia_semana smallint NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fin time without time zone NOT NULL,
    CONSTRAINT horario_medico_dia_semana_check CHECK (((dia_semana >= 1) AND (dia_semana <= 7))),
    CONSTRAINT horario_medico_rango_chk CHECK ((hora_fin > hora_inicio))
);


ALTER TABLE public.horario_medico OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 18670)
-- Name: horario_medico_id_horario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.horario_medico ALTER COLUMN id_horario ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.horario_medico_id_horario_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 235 (class 1259 OID 17757)
-- Name: medicamento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.medicamento (
    id_medicamento integer NOT NULL,
    nombre character varying(120) NOT NULL,
    presentacion character varying(60) NOT NULL,
    concentracion character varying(40) NOT NULL,
    precio_unitario numeric(12,2) DEFAULT 0 NOT NULL,
    CONSTRAINT medicamento_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric))
);


ALTER TABLE public.medicamento OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 17756)
-- Name: medicamento_id_medicamento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.medicamento ALTER COLUMN id_medicamento ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.medicamento_id_medicamento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 226 (class 1259 OID 17664)
-- Name: medico_id_medico_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.medico ALTER COLUMN id_medico ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.medico_id_medico_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 222 (class 1259 OID 17633)
-- Name: paciente_id_paciente_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.paciente ALTER COLUMN id_paciente ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.paciente_id_paciente_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 245 (class 1259 OID 18695)
-- Name: tipo_documento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_documento (
    codigo character varying(3) NOT NULL,
    nombre character varying(60) NOT NULL
);


ALTER TABLE public.tipo_documento OWNER TO postgres;

--
-- TOC entry 246 (class 1259 OID 18716)
-- Name: tipo_vinculacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_vinculacion (
    codigo character varying(12) NOT NULL,
    nombre character varying(80) NOT NULL
);


ALTER TABLE public.tipo_vinculacion OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 18656)
-- Name: v_agenda_diaria; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_agenda_diaria AS
 SELECT c.id_cita,
    c.fecha,
    c.hora,
    c.hora_fin,
    c.duracion_min,
    c.estado,
    p.documento AS documento_paciente,
    (((p.nombres)::text || ' '::text) || (p.apellidos)::text) AS paciente,
    (((m.nombres)::text || ' '::text) || (m.apellidos)::text) AS medico,
    e.nombre AS especialidad,
    k.numero AS consultorio,
    k.piso
   FROM ((((public.cita c
     JOIN public.paciente p ON ((p.id_paciente = c.id_paciente)))
     JOIN public.medico m ON ((m.id_medico = c.id_medico)))
     JOIN public.especialidad e ON ((e.id_especialidad = m.id_especialidad)))
     JOIN public.consultorio k ON ((k.id_consultorio = c.id_consultorio)));


ALTER VIEW public.v_agenda_diaria OWNER TO postgres;

--
-- TOC entry 247 (class 1259 OID 18731)
-- Name: v_paciente_aseguradora; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_paciente_aseguradora AS
 SELECT p.id_paciente,
    p.tipo_documento,
    p.documento,
    p.nombres,
    p.apellidos,
    p.tipo_vinculacion,
    COALESCE(e.nombre, 'Particular'::character varying) AS aseguradora
   FROM (public.paciente p
     LEFT JOIN public.eps e ON ((e.id_eps = p.id_eps)));


ALTER VIEW public.v_paciente_aseguradora OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 18661)
-- Name: v_resumen_atencion_clinica; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_resumen_atencion_clinica AS
 SELECT c.id_cita,
    c.fecha,
    c.hora,
    c.estado,
    (((p.nombres)::text || ' '::text) || (p.apellidos)::text) AS paciente,
    (((m.nombres)::text || ' '::text) || (m.apellidos)::text) AS medico,
    h.diagnostico,
    h.codigo_cie10,
    cie.descripcion AS descripcion_cie10,
    f.valor_servicios,
    f.valor_medicamentos,
    (COALESCE(f.valor_servicios, (0)::numeric) + COALESCE(f.valor_medicamentos, (0)::numeric)) AS total_factura,
    f.metodo_pago
   FROM (((((public.cita c
     JOIN public.paciente p ON ((p.id_paciente = c.id_paciente)))
     JOIN public.medico m ON ((m.id_medico = c.id_medico)))
     LEFT JOIN public.historia_clinica h ON ((h.id_cita = c.id_cita)))
     LEFT JOIN public.cie10 cie ON (((cie.codigo)::text = (h.codigo_cie10)::text)))
     LEFT JOIN public.factura f ON ((f.id_cita = c.id_cita)));


ALTER VIEW public.v_resumen_atencion_clinica OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 17850)
-- Name: v_resumen_medicos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_resumen_medicos AS
 SELECT medico.id_medico,
    medico.documento,
    medico.nombres,
    medico.apellidos,
    especialidad.nombre AS especialidad,
    medico.registro_profesional,
    COALESCE(medico.telefono, 'Sin teléfono registrado'::character varying) AS telefono,
    medico.correo,
        CASE
            WHEN (medico.activo = true) THEN 'Activo'::text
            ELSE 'Inactivo'::text
        END AS estado_medico
   FROM (public.medico
     LEFT JOIN public.especialidad ON ((especialidad.id_especialidad = medico.id_especialidad)));


ALTER VIEW public.v_resumen_medicos OWNER TO postgres;

--
-- TOC entry 5518 (class 0 OID 18638)
-- Dependencies: 240
-- Data for Name: cie10; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cie10 (codigo, descripcion, activo) FROM stdin;
Z000	Examen médico general	t
J069	Infección aguda de las vías respiratorias superiores, no especificada	t
M791	Mialgia	t
J304	Rinitis alérgica, no especificada	t
J029	Faringitis aguda, no especificada	t
G442	Cefalea debida a tensión	t
A09X	Diarrea y gastroenteritis de presunto origen infeccioso	t
E119	Diabetes mellitus tipo 2, sin mención de complicación	t
I10X	Hipertensión esencial (primaria)	t
R509	Fiebre, no especificada	t
H669	Otitis media, no especificada	t
K297	Gastritis, no especificada	t
J00X	Rinofaringitis aguda [resfriado común]	t
\.


--
-- TOC entry 5510 (class 0 OID 17704)
-- Dependencies: 231
-- Data for Name: cita; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cita (id_cita, id_paciente, id_medico, id_consultorio, fecha, hora, motivo, estado, duracion_min) FROM stdin;
1	1	1	1	2026-10-19	08:00:00	Dolor de pecho / Chequeo cardíaco	Atendida	30
2	2	1	2	2026-10-19	09:00:00	Control de presión arterial	Atendida	30
3	3	2	1	2026-10-19	09:00:00	Consulta pediátrica	Cancelada	30
4	1	2	1	2026-10-19	09:00:00	Reagendada tras cancelación	Programada	30
7	3	1	3	2026-10-14	14:00:00	Chequeo general	Programada	30
5	1	1	1	2026-10-17	10:00:00	Control	Inasistida	30
6	2	2	2	2026-10-16	11:00:00	Dolor de espalda	Inasistida	30
8	1	2	1	2026-10-07	09:00:00	Fiebre	Inasistida	30
9	45	1	1	2026-09-04	08:30:00	Dolor abdominal	Atendida	30
10	163	1	1	2026-09-04	10:00:00	Dolor de cabeza	Atendida	30
11	64	1	1	2026-09-04	10:30:00	Dolor muscular	Atendida	30
12	7	1	1	2026-09-04	11:00:00	Mareo	Atendida	30
13	162	4	2	2026-09-04	08:30:00	Dolor de oído	Atendida	30
14	92	4	2	2026-09-04	10:00:00	Alergia en la piel	Atendida	30
15	142	4	2	2026-09-04	10:30:00	Malestar general	Atendida	30
16	192	4	2	2026-09-04	11:00:00	Dolor abdominal	Atendida	30
17	98	9	3	2026-09-04	08:00:00	Náuseas y vómito	Atendida	30
18	188	9	3	2026-09-04	10:30:00	Control general	Atendida	30
19	114	9	3	2026-09-04	11:00:00	Control de presión arterial	Inasistida	30
20	118	10	3	2026-09-04	14:30:00	Dolor muscular	Atendida	30
21	184	10	3	2026-09-04	17:00:00	Dolor de oído	Atendida	30
22	60	12	7	2026-09-04	14:00:00	Tos persistente	Atendida	30
23	11	12	7	2026-09-04	16:00:00	Control de diabetes	Atendida	30
24	168	12	7	2026-09-04	16:30:00	Náuseas y vómito	Atendida	30
25	136	13	8	2026-09-04	08:30:00	Dolor de oído	Atendida	30
26	75	13	8	2026-09-04	09:30:00	Control de presión arterial	Atendida	30
27	131	13	8	2026-09-04	10:30:00	Chequeo médico	Atendida	30
28	133	14	8	2026-09-04	14:00:00	Dolor de cabeza	Atendida	30
29	51	14	8	2026-09-04	15:00:00	Alergia en la piel	Atendida	30
30	91	14	8	2026-09-04	16:30:00	Malestar general	Atendida	30
31	105	14	8	2026-09-04	17:30:00	Tos persistente	Atendida	30
32	155	15	9	2026-09-04	08:00:00	Chequeo médico	Atendida	30
33	109	15	9	2026-09-04	10:00:00	Control de diabetes	Atendida	30
34	143	15	9	2026-09-04	10:30:00	Malestar general	Inasistida	30
35	166	16	9	2026-09-04	15:00:00	Malestar general	Atendida	30
36	136	16	9	2026-09-04	15:30:00	Control de presión arterial	Atendida	30
37	130	17	10	2026-09-04	08:30:00	Tos persistente	Inasistida	30
38	101	17	10	2026-09-04	09:00:00	Dolor abdominal	Cancelada	30
39	108	17	10	2026-09-04	10:30:00	Dolor de cabeza	Inasistida	30
40	31	17	10	2026-09-04	11:00:00	Dolor de garganta	Inasistida	30
41	78	17	10	2026-09-04	11:30:00	Control general	Cancelada	30
42	218	18	10	2026-09-04	14:30:00	Dolor de oído	Inasistida	30
43	98	18	10	2026-09-04	15:30:00	Chequeo médico	Atendida	30
44	192	19	13	2026-09-04	09:00:00	Alergia en la piel	Inasistida	30
45	164	19	13	2026-09-04	10:00:00	Náuseas y vómito	Atendida	30
46	77	20	13	2026-09-04	16:00:00	Mareo	Atendida	30
47	86	20	13	2026-09-04	17:00:00	Malestar general	Atendida	30
48	45	1	1	2026-09-07	08:00:00	Náuseas y vómito	Atendida	30
49	186	2	1	2026-09-07	15:30:00	Tos persistente	Inasistida	30
50	199	4	2	2026-09-07	11:00:00	Control de presión arterial	Atendida	30
51	11	5	2	2026-09-07	15:00:00	Dolor de cabeza	Atendida	30
52	138	9	3	2026-09-07	08:30:00	Dolor de cabeza	Atendida	30
53	215	9	3	2026-09-07	11:00:00	Dolor de cabeza	Atendida	30
54	177	10	3	2026-09-07	15:00:00	Dolor lumbar	Atendida	30
55	35	10	3	2026-09-07	15:30:00	Dolor de oído	Atendida	30
56	198	10	3	2026-09-07	16:30:00	Dolor abdominal	Cancelada	30
57	188	11	7	2026-09-07	11:30:00	Dolor lumbar	Atendida	30
58	224	13	8	2026-09-07	09:30:00	Dolor de cabeza	Atendida	30
59	14	15	9	2026-09-07	08:00:00	Dolor de oído	Atendida	30
60	7	15	9	2026-09-07	10:00:00	Dolor lumbar	Inasistida	30
61	218	16	9	2026-09-07	17:30:00	Control de presión arterial	Atendida	30
62	130	17	10	2026-09-07	09:30:00	Chequeo médico	Atendida	30
63	216	18	10	2026-09-07	14:00:00	Dolor de cabeza	Inasistida	30
64	171	18	10	2026-09-07	14:30:00	Dolor de garganta	Atendida	30
65	143	18	10	2026-09-07	15:00:00	Dolor muscular	Atendida	30
66	180	18	10	2026-09-07	16:00:00	Dolor de garganta	Atendida	30
67	170	18	10	2026-09-07	17:30:00	Tos persistente	Inasistida	30
68	68	19	13	2026-09-07	08:30:00	Control de diabetes	Atendida	30
69	215	19	13	2026-09-07	09:30:00	Gripe	Inasistida	30
70	210	20	13	2026-09-07	16:30:00	Náuseas y vómito	Atendida	30
71	157	2	1	2026-09-08	14:30:00	Fiebre	Inasistida	30
72	81	2	1	2026-09-08	15:30:00	Control de presión arterial	Atendida	30
73	153	2	1	2026-09-08	16:00:00	Dolor muscular	Cancelada	30
74	135	4	2	2026-09-08	09:00:00	Dolor de garganta	Atendida	30
75	93	4	2	2026-09-08	10:30:00	Dolor de garganta	Atendida	30
76	137	5	2	2026-09-08	14:00:00	Dolor muscular	Atendida	30
77	13	9	3	2026-09-08	10:30:00	Tos persistente	Atendida	30
78	205	9	3	2026-09-08	11:00:00	Dolor abdominal	Atendida	30
79	9	10	3	2026-09-08	15:00:00	Chequeo médico	Atendida	30
80	27	10	3	2026-09-08	16:00:00	Fiebre	Atendida	30
81	147	11	7	2026-09-08	08:00:00	Control de diabetes	Atendida	30
82	127	12	7	2026-09-08	14:30:00	Dolor muscular	Atendida	30
83	34	12	7	2026-09-08	15:30:00	Fiebre	Atendida	30
84	186	13	8	2026-09-08	08:30:00	Malestar general	Atendida	30
85	78	13	8	2026-09-08	11:30:00	Tos persistente	Atendida	30
86	219	14	8	2026-09-08	14:00:00	Fiebre	Atendida	30
87	219	16	9	2026-09-08	14:00:00	Dolor muscular	Atendida	30
88	120	16	9	2026-09-08	14:30:00	Control general	Atendida	30
89	105	16	9	2026-09-08	16:30:00	Dolor de garganta	Inasistida	30
90	95	17	10	2026-09-08	11:00:00	Control de diabetes	Atendida	30
91	148	18	10	2026-09-08	15:30:00	Control general	Atendida	30
92	143	18	10	2026-09-08	17:30:00	Alergia en la piel	Atendida	30
93	61	19	13	2026-09-08	09:00:00	Control de presión arterial	Atendida	30
94	47	19	13	2026-09-08	09:30:00	Dolor de oído	Atendida	30
95	44	19	13	2026-09-08	10:00:00	Malestar general	Atendida	30
96	145	20	13	2026-09-08	14:30:00	Chequeo médico	Atendida	30
97	72	20	13	2026-09-08	16:30:00	Malestar general	Atendida	30
98	84	1	1	2026-09-09	08:30:00	Fiebre	Atendida	30
99	216	1	1	2026-09-09	10:00:00	Gripe	Atendida	30
100	41	2	1	2026-09-09	14:30:00	Dolor muscular	Cancelada	30
101	123	2	1	2026-09-09	15:30:00	Dolor de oído	Atendida	30
102	181	2	1	2026-09-09	17:30:00	Alergia en la piel	Atendida	30
103	65	4	2	2026-09-09	08:00:00	Dolor de garganta	Atendida	30
104	78	4	2	2026-09-09	11:30:00	Control general	Atendida	30
105	31	5	2	2026-09-09	14:30:00	Dolor de oído	Cancelada	30
106	67	5	2	2026-09-09	15:00:00	Dolor abdominal	Atendida	30
107	165	9	3	2026-09-09	09:00:00	Dolor de garganta	Atendida	30
108	132	9	3	2026-09-09	11:00:00	Dolor de garganta	Atendida	30
109	214	10	3	2026-09-09	16:30:00	Control general	Inasistida	30
110	54	11	7	2026-09-09	08:30:00	Dolor muscular	Atendida	30
111	193	11	7	2026-09-09	11:30:00	Control de presión arterial	Atendida	30
112	96	12	7	2026-09-09	17:00:00	Dolor muscular	Atendida	30
113	93	13	8	2026-09-09	11:00:00	Dolor lumbar	Atendida	30
114	124	14	8	2026-09-09	14:30:00	Tos persistente	Atendida	30
115	3	14	8	2026-09-09	16:30:00	Chequeo médico	Atendida	30
116	148	14	8	2026-09-09	17:00:00	Alergia en la piel	Atendida	30
117	40	15	9	2026-09-09	10:00:00	Náuseas y vómito	Atendida	30
118	82	15	9	2026-09-09	11:30:00	Gripe	Inasistida	30
119	199	16	9	2026-09-09	14:30:00	Dolor abdominal	Atendida	30
120	123	17	10	2026-09-09	09:30:00	Control de presión arterial	Atendida	30
121	118	20	13	2026-09-09	16:00:00	Náuseas y vómito	Atendida	30
122	206	1	1	2026-09-10	09:30:00	Dolor lumbar	Atendida	30
123	37	2	1	2026-09-10	14:00:00	Fiebre	Atendida	30
124	74	2	1	2026-09-10	17:00:00	Gripe	Atendida	30
125	46	5	2	2026-09-10	14:00:00	Malestar general	Atendida	30
126	200	5	2	2026-09-10	14:30:00	Dolor muscular	Atendida	30
127	34	5	2	2026-09-10	16:00:00	Gripe	Atendida	30
128	171	5	2	2026-09-10	17:00:00	Control de diabetes	Atendida	30
129	209	9	3	2026-09-10	11:00:00	Tos persistente	Atendida	30
130	164	10	3	2026-09-10	14:30:00	Dolor muscular	Atendida	30
131	191	11	7	2026-09-10	09:00:00	Dolor de cabeza	Cancelada	30
132	189	14	8	2026-09-10	15:00:00	Gripe	Atendida	30
133	222	14	8	2026-09-10	15:30:00	Malestar general	Atendida	30
134	25	14	8	2026-09-10	16:00:00	Gripe	Atendida	30
135	41	15	9	2026-09-10	08:00:00	Dolor lumbar	Cancelada	30
136	205	15	9	2026-09-10	09:30:00	Gripe	Atendida	30
137	119	15	9	2026-09-10	10:00:00	Mareo	Atendida	30
138	48	15	9	2026-09-10	11:30:00	Náuseas y vómito	Atendida	30
139	207	16	9	2026-09-10	14:00:00	Malestar general	Atendida	30
140	137	16	9	2026-09-10	15:00:00	Náuseas y vómito	Atendida	30
141	28	16	9	2026-09-10	15:30:00	Dolor de garganta	Atendida	30
142	115	16	9	2026-09-10	16:00:00	Fiebre	Atendida	30
143	127	17	10	2026-09-10	10:00:00	Alergia en la piel	Atendida	30
144	113	17	10	2026-09-10	10:30:00	Náuseas y vómito	Atendida	30
145	22	19	13	2026-09-10	08:00:00	Dolor de oído	Atendida	30
146	68	19	13	2026-09-10	08:30:00	Control de diabetes	Atendida	30
147	23	19	13	2026-09-10	09:00:00	Alergia en la piel	Atendida	30
148	118	19	13	2026-09-10	09:30:00	Fiebre	Atendida	30
149	42	19	13	2026-09-10	10:00:00	Dolor de garganta	Atendida	30
150	127	19	13	2026-09-10	10:30:00	Dolor de cabeza	Atendida	30
151	95	19	13	2026-09-10	11:30:00	Fiebre	Atendida	30
152	127	1	1	2026-09-11	10:30:00	Chequeo médico	Atendida	30
153	222	1	1	2026-09-11	11:00:00	Fiebre	Atendida	30
154	33	2	1	2026-09-11	16:00:00	Dolor muscular	Inasistida	30
155	208	2	1	2026-09-11	17:30:00	Tos persistente	Atendida	30
156	89	4	2	2026-09-11	09:00:00	Alergia en la piel	Atendida	30
157	124	5	2	2026-09-11	17:00:00	Tos persistente	Inasistida	30
158	209	5	2	2026-09-11	17:30:00	Dolor de oído	Atendida	30
159	68	9	3	2026-09-11	10:00:00	Dolor de oído	Atendida	30
160	61	11	7	2026-09-11	08:00:00	Dolor de oído	Atendida	30
161	127	12	7	2026-09-11	17:30:00	Control general	Atendida	30
162	111	13	8	2026-09-11	09:30:00	Dolor lumbar	Atendida	30
163	35	13	8	2026-09-11	10:00:00	Alergia en la piel	Atendida	30
164	140	15	9	2026-09-11	08:30:00	Control de diabetes	Cancelada	30
165	198	15	9	2026-09-11	11:30:00	Malestar general	Atendida	30
166	34	16	9	2026-09-11	14:30:00	Control de diabetes	Inasistida	30
167	77	16	9	2026-09-11	15:00:00	Dolor de cabeza	Atendida	30
168	122	16	9	2026-09-11	17:30:00	Dolor de cabeza	Atendida	30
169	176	17	10	2026-09-11	08:30:00	Dolor lumbar	Atendida	30
170	210	17	10	2026-09-11	09:30:00	Dolor abdominal	Atendida	30
171	150	19	13	2026-09-11	08:00:00	Dolor muscular	Atendida	30
172	47	19	13	2026-09-11	10:00:00	Control de presión arterial	Atendida	30
173	92	19	13	2026-09-11	10:30:00	Tos persistente	Atendida	30
174	36	1	1	2026-09-14	09:00:00	Control de presión arterial	Atendida	30
175	75	1	1	2026-09-14	10:30:00	Gripe	Atendida	30
176	9	2	1	2026-09-14	15:00:00	Alergia en la piel	Atendida	30
177	48	2	1	2026-09-14	17:00:00	Fiebre	Atendida	30
178	225	4	2	2026-09-14	08:00:00	Malestar general	Atendida	30
179	89	4	2	2026-09-14	08:30:00	Control de diabetes	Atendida	30
180	66	5	2	2026-09-14	16:30:00	Control de diabetes	Inasistida	30
181	73	9	3	2026-09-14	10:00:00	Dolor de oído	Atendida	30
182	164	9	3	2026-09-14	11:30:00	Dolor de oído	Cancelada	30
183	39	10	3	2026-09-14	16:30:00	Alergia en la piel	Cancelada	30
184	97	10	3	2026-09-14	17:00:00	Tos persistente	Cancelada	30
185	98	11	7	2026-09-14	10:00:00	Dolor abdominal	Atendida	30
186	84	12	7	2026-09-14	14:00:00	Alergia en la piel	Atendida	30
187	196	12	7	2026-09-14	14:30:00	Tos persistente	Cancelada	30
188	212	12	7	2026-09-14	16:30:00	Dolor muscular	Inasistida	30
189	72	12	7	2026-09-14	17:00:00	Gripe	Atendida	30
190	35	13	8	2026-09-14	08:30:00	Alergia en la piel	Atendida	30
191	157	14	8	2026-09-14	15:00:00	Dolor de oído	Atendida	30
192	209	14	8	2026-09-14	15:30:00	Control general	Atendida	30
193	82	15	9	2026-09-14	08:00:00	Tos persistente	Atendida	30
194	194	16	9	2026-09-14	16:30:00	Mareo	Atendida	30
195	120	19	13	2026-09-14	08:00:00	Control de diabetes	Atendida	30
196	136	19	13	2026-09-14	11:30:00	Náuseas y vómito	Atendida	30
197	212	20	13	2026-09-14	16:00:00	Chequeo médico	Atendida	30
198	191	1	1	2026-09-15	08:00:00	Gripe	Atendida	30
199	39	1	1	2026-09-15	08:30:00	Malestar general	Atendida	30
200	8	1	1	2026-09-15	10:00:00	Dolor de oído	Atendida	30
201	79	1	1	2026-09-15	11:30:00	Tos persistente	Cancelada	30
202	223	2	1	2026-09-15	14:30:00	Dolor abdominal	Atendida	30
203	222	2	1	2026-09-15	16:00:00	Control de diabetes	Atendida	30
204	121	4	2	2026-09-15	09:30:00	Dolor abdominal	Atendida	30
205	80	5	2	2026-09-15	14:00:00	Dolor de cabeza	Atendida	30
206	148	5	2	2026-09-15	14:30:00	Control de diabetes	Atendida	30
207	193	5	2	2026-09-15	16:00:00	Dolor de cabeza	Atendida	30
208	9	5	2	2026-09-15	17:00:00	Dolor lumbar	Atendida	30
209	132	9	3	2026-09-15	08:30:00	Alergia en la piel	Atendida	30
210	223	9	3	2026-09-15	09:30:00	Tos persistente	Atendida	30
211	60	9	3	2026-09-15	10:30:00	Gripe	Atendida	30
212	161	10	3	2026-09-15	14:00:00	Alergia en la piel	Atendida	30
213	55	10	3	2026-09-15	16:30:00	Malestar general	Atendida	30
214	68	11	7	2026-09-15	08:30:00	Dolor de cabeza	Cancelada	30
215	55	12	7	2026-09-15	16:30:00	Fiebre	Atendida	30
216	184	13	8	2026-09-15	08:30:00	Alergia en la piel	Atendida	30
217	106	13	8	2026-09-15	10:00:00	Mareo	Atendida	30
218	18	13	8	2026-09-15	11:00:00	Gripe	Atendida	30
219	13	13	8	2026-09-15	11:30:00	Dolor de garganta	Cancelada	30
220	200	14	8	2026-09-15	14:30:00	Mareo	Atendida	30
221	215	14	8	2026-09-15	16:30:00	Control de diabetes	Cancelada	30
222	149	15	9	2026-09-15	10:00:00	Dolor abdominal	Atendida	30
223	25	16	9	2026-09-15	17:00:00	Dolor lumbar	Atendida	30
224	151	17	10	2026-09-15	08:00:00	Dolor abdominal	Atendida	30
225	148	17	10	2026-09-15	09:00:00	Fiebre	Atendida	30
226	84	17	10	2026-09-15	09:30:00	Dolor abdominal	Atendida	30
227	52	17	10	2026-09-15	10:30:00	Tos persistente	Inasistida	30
228	54	18	10	2026-09-15	17:30:00	Chequeo médico	Atendida	30
229	104	20	13	2026-09-15	15:30:00	Chequeo médico	Cancelada	30
230	122	2	1	2026-09-16	15:30:00	Control general	Atendida	30
231	30	5	2	2026-09-16	14:00:00	Control general	Atendida	30
232	214	9	3	2026-09-16	08:30:00	Gripe	Atendida	30
233	128	11	7	2026-09-16	09:30:00	Dolor abdominal	Atendida	30
234	114	12	7	2026-09-16	14:30:00	Dolor lumbar	Atendida	30
235	113	12	7	2026-09-16	15:00:00	Gripe	Atendida	30
236	39	12	7	2026-09-16	17:30:00	Mareo	Atendida	30
237	198	13	8	2026-09-16	10:30:00	Control de diabetes	Atendida	30
238	212	14	8	2026-09-16	17:00:00	Control de diabetes	Atendida	30
239	149	15	9	2026-09-16	10:00:00	Dolor abdominal	Atendida	30
240	143	16	9	2026-09-16	14:00:00	Dolor de garganta	Atendida	30
241	65	16	9	2026-09-16	15:30:00	Malestar general	Atendida	30
242	216	16	9	2026-09-16	16:00:00	Control de presión arterial	Atendida	30
243	117	16	9	2026-09-16	16:30:00	Control de diabetes	Atendida	30
244	144	18	10	2026-09-16	14:00:00	Dolor de cabeza	Inasistida	30
245	201	18	10	2026-09-16	15:30:00	Dolor abdominal	Atendida	30
246	71	19	13	2026-09-16	08:00:00	Mareo	Atendida	30
247	102	20	13	2026-09-16	16:00:00	Dolor abdominal	Atendida	30
248	123	20	13	2026-09-16	17:00:00	Alergia en la piel	Atendida	30
249	178	1	1	2026-09-17	10:30:00	Náuseas y vómito	Cancelada	30
250	158	1	1	2026-09-17	11:00:00	Fiebre	Atendida	30
251	49	1	1	2026-09-17	11:30:00	Dolor abdominal	Atendida	30
252	98	2	1	2026-09-17	14:00:00	Dolor lumbar	Atendida	30
253	159	2	1	2026-09-17	15:30:00	Dolor abdominal	Atendida	30
254	176	2	1	2026-09-17	16:30:00	Chequeo médico	Atendida	30
255	166	4	2	2026-09-17	08:00:00	Dolor de garganta	Atendida	30
256	116	4	2	2026-09-17	10:30:00	Gripe	Atendida	30
257	85	5	2	2026-09-17	14:30:00	Chequeo médico	Atendida	30
258	122	9	3	2026-09-17	09:00:00	Náuseas y vómito	Atendida	30
259	223	9	3	2026-09-17	10:00:00	Alergia en la piel	Atendida	30
260	64	9	3	2026-09-17	11:00:00	Control de presión arterial	Atendida	30
261	205	10	3	2026-09-17	16:00:00	Malestar general	Cancelada	30
262	13	10	3	2026-09-17	17:30:00	Náuseas y vómito	Atendida	30
263	131	11	7	2026-09-17	11:00:00	Control general	Inasistida	30
264	145	12	7	2026-09-17	16:00:00	Dolor de cabeza	Atendida	30
265	195	12	7	2026-09-17	17:00:00	Náuseas y vómito	Inasistida	30
266	99	15	9	2026-09-17	10:30:00	Control general	Atendida	30
267	43	15	9	2026-09-17	11:00:00	Gripe	Inasistida	30
268	202	15	9	2026-09-17	11:30:00	Gripe	Atendida	30
269	13	16	9	2026-09-17	16:00:00	Fiebre	Atendida	30
270	54	16	9	2026-09-17	16:30:00	Control de diabetes	Atendida	30
271	71	18	10	2026-09-17	15:00:00	Gripe	Atendida	30
272	225	18	10	2026-09-17	15:30:00	Control de presión arterial	Atendida	30
273	27	18	10	2026-09-17	16:30:00	Dolor de garganta	Atendida	30
274	101	19	13	2026-09-17	08:00:00	Náuseas y vómito	Atendida	30
275	74	19	13	2026-09-17	10:30:00	Dolor de garganta	Atendida	30
276	174	20	13	2026-09-17	14:30:00	Control de diabetes	Atendida	30
277	2	20	13	2026-09-17	15:30:00	Fiebre	Cancelada	30
278	10	1	1	2026-09-18	09:30:00	Fiebre	Atendida	30
279	156	1	1	2026-09-18	10:00:00	Gripe	Atendida	30
280	98	2	1	2026-09-18	14:00:00	Náuseas y vómito	Atendida	30
281	183	2	1	2026-09-18	15:30:00	Dolor muscular	Atendida	30
282	78	4	2	2026-09-18	11:00:00	Control general	Atendida	30
283	140	5	2	2026-09-18	14:30:00	Dolor lumbar	Atendida	30
284	104	5	2	2026-09-18	15:30:00	Mareo	Atendida	30
285	35	5	2	2026-09-18	16:00:00	Chequeo médico	Atendida	30
286	202	5	2	2026-09-18	17:00:00	Control general	Atendida	30
287	48	9	3	2026-09-18	10:00:00	Fiebre	Atendida	30
288	99	9	3	2026-09-18	10:30:00	Dolor de garganta	Inasistida	30
289	133	10	3	2026-09-18	17:00:00	Dolor abdominal	Atendida	30
290	9	11	7	2026-09-18	10:30:00	Control general	Atendida	30
291	50	12	7	2026-09-18	15:30:00	Dolor de cabeza	Atendida	30
292	183	13	8	2026-09-18	11:00:00	Gripe	Atendida	30
293	101	14	8	2026-09-18	14:00:00	Mareo	Atendida	30
294	152	14	8	2026-09-18	14:30:00	Dolor muscular	Atendida	30
295	134	14	8	2026-09-18	16:00:00	Alergia en la piel	Atendida	30
296	161	15	9	2026-09-18	09:30:00	Control de diabetes	Inasistida	30
297	24	16	9	2026-09-18	15:00:00	Control de diabetes	Atendida	30
298	81	17	10	2026-09-18	09:00:00	Dolor lumbar	Atendida	30
299	67	18	10	2026-09-18	14:00:00	Dolor de garganta	Inasistida	30
300	141	18	10	2026-09-18	14:30:00	Dolor muscular	Inasistida	30
301	3	20	13	2026-09-18	14:00:00	Náuseas y vómito	Atendida	30
302	82	20	13	2026-09-18	15:30:00	Dolor muscular	Atendida	30
303	209	20	13	2026-09-18	16:00:00	Fiebre	Atendida	30
304	178	1	1	2026-09-21	10:00:00	Mareo	Inasistida	30
305	150	2	1	2026-09-21	14:00:00	Mareo	Atendida	30
306	70	2	1	2026-09-21	14:30:00	Dolor de garganta	Atendida	30
307	214	4	2	2026-09-21	08:00:00	Malestar general	Cancelada	30
308	58	4	2	2026-09-21	09:30:00	Fiebre	Atendida	30
309	72	4	2	2026-09-21	11:30:00	Mareo	Atendida	30
310	67	5	2	2026-09-21	14:30:00	Dolor lumbar	Atendida	30
311	43	5	2	2026-09-21	16:00:00	Gripe	Atendida	30
312	191	5	2	2026-09-21	17:00:00	Dolor lumbar	Atendida	30
313	118	9	3	2026-09-21	08:00:00	Alergia en la piel	Atendida	30
314	187	9	3	2026-09-21	11:30:00	Chequeo médico	Cancelada	30
315	208	10	3	2026-09-21	15:00:00	Dolor de oído	Atendida	30
316	177	11	7	2026-09-21	08:30:00	Alergia en la piel	Cancelada	30
317	64	12	7	2026-09-21	14:30:00	Malestar general	Inasistida	30
318	130	12	7	2026-09-21	16:30:00	Control de presión arterial	Atendida	30
319	63	13	8	2026-09-21	10:30:00	Dolor de cabeza	Cancelada	30
320	59	14	8	2026-09-21	15:30:00	Dolor lumbar	Atendida	30
321	77	15	9	2026-09-21	08:00:00	Alergia en la piel	Atendida	30
322	69	16	9	2026-09-21	15:30:00	Mareo	Atendida	30
323	150	16	9	2026-09-21	16:30:00	Dolor de cabeza	Atendida	30
324	125	17	10	2026-09-21	09:30:00	Control general	Cancelada	30
325	101	17	10	2026-09-21	11:30:00	Tos persistente	Atendida	30
326	16	19	13	2026-09-21	10:00:00	Chequeo médico	Atendida	30
327	163	1	1	2026-09-22	08:30:00	Náuseas y vómito	Atendida	30
328	22	1	1	2026-09-22	09:00:00	Dolor abdominal	Atendida	30
329	79	1	1	2026-09-22	11:00:00	Control de diabetes	Atendida	30
330	90	1	1	2026-09-22	11:30:00	Control de diabetes	Atendida	30
331	76	4	2	2026-09-22	11:30:00	Náuseas y vómito	Atendida	30
332	27	5	2	2026-09-22	15:00:00	Náuseas y vómito	Cancelada	30
333	193	5	2	2026-09-22	17:00:00	Chequeo médico	Atendida	30
334	132	9	3	2026-09-22	09:30:00	Gripe	Atendida	30
335	141	9	3	2026-09-22	10:00:00	Control general	Atendida	30
336	187	10	3	2026-09-22	16:00:00	Náuseas y vómito	Cancelada	30
337	99	11	7	2026-09-22	09:30:00	Alergia en la piel	Inasistida	30
338	127	11	7	2026-09-22	11:00:00	Malestar general	Atendida	30
339	24	12	7	2026-09-22	15:00:00	Mareo	Cancelada	30
340	211	13	8	2026-09-22	08:00:00	Dolor de garganta	Atendida	30
341	36	13	8	2026-09-22	11:00:00	Tos persistente	Atendida	30
342	173	14	8	2026-09-22	15:00:00	Control general	Atendida	30
343	39	14	8	2026-09-22	16:00:00	Gripe	Atendida	30
344	219	14	8	2026-09-22	16:30:00	Dolor muscular	Atendida	30
345	221	14	8	2026-09-22	17:00:00	Dolor muscular	Atendida	30
346	219	15	9	2026-09-22	09:30:00	Control de presión arterial	Cancelada	30
347	114	15	9	2026-09-22	11:00:00	Náuseas y vómito	Atendida	30
348	136	16	9	2026-09-22	14:30:00	Chequeo médico	Atendida	30
349	121	17	10	2026-09-22	08:00:00	Dolor de oído	Atendida	30
350	90	18	10	2026-09-22	14:00:00	Alergia en la piel	Inasistida	30
351	197	18	10	2026-09-22	15:30:00	Dolor abdominal	Cancelada	30
352	188	19	13	2026-09-22	10:00:00	Dolor de cabeza	Atendida	30
353	106	19	13	2026-09-22	10:30:00	Dolor muscular	Inasistida	30
354	94	19	13	2026-09-22	11:30:00	Gripe	Atendida	30
355	108	1	1	2026-09-23	10:00:00	Dolor de oído	Atendida	30
356	101	5	2	2026-09-23	14:00:00	Gripe	Atendida	30
357	125	5	2	2026-09-23	17:30:00	Fiebre	Atendida	30
358	212	10	3	2026-09-23	16:00:00	Control general	Atendida	30
359	144	10	3	2026-09-23	17:00:00	Dolor de garganta	Atendida	30
360	156	10	3	2026-09-23	17:30:00	Fiebre	Atendida	30
361	141	11	7	2026-09-23	09:30:00	Chequeo médico	Atendida	30
362	13	11	7	2026-09-23	11:30:00	Gripe	Atendida	30
363	83	12	7	2026-09-23	17:30:00	Dolor de garganta	Atendida	30
364	46	13	8	2026-09-23	11:00:00	Chequeo médico	Atendida	30
365	28	14	8	2026-09-23	14:00:00	Mareo	Atendida	30
366	125	14	8	2026-09-23	17:00:00	Mareo	Inasistida	30
367	79	15	9	2026-09-23	08:00:00	Dolor lumbar	Atendida	30
368	27	15	9	2026-09-23	09:30:00	Control de presión arterial	Atendida	30
369	206	15	9	2026-09-23	10:30:00	Chequeo médico	Atendida	30
370	81	15	9	2026-09-23	11:00:00	Control general	Atendida	30
371	151	16	9	2026-09-23	14:00:00	Fiebre	Atendida	30
372	159	16	9	2026-09-23	14:30:00	Dolor abdominal	Atendida	30
373	66	16	9	2026-09-23	15:00:00	Control de diabetes	Atendida	30
374	91	17	10	2026-09-23	11:00:00	Tos persistente	Atendida	30
375	102	19	13	2026-09-23	10:00:00	Dolor lumbar	Atendida	30
376	157	19	13	2026-09-23	11:00:00	Dolor de oído	Atendida	30
377	215	20	13	2026-09-23	16:30:00	Dolor abdominal	Atendida	30
378	212	20	13	2026-09-23	17:00:00	Chequeo médico	Atendida	30
379	82	2	1	2026-09-24	15:30:00	Dolor lumbar	Atendida	30
380	30	2	1	2026-09-24	16:00:00	Dolor de oído	Inasistida	30
381	198	2	1	2026-09-24	17:00:00	Alergia en la piel	Atendida	30
382	196	4	2	2026-09-24	11:00:00	Mareo	Inasistida	30
383	80	9	3	2026-09-24	11:00:00	Dolor de garganta	Atendida	30
384	221	10	3	2026-09-24	16:30:00	Dolor de oído	Atendida	30
385	138	10	3	2026-09-24	17:30:00	Control de diabetes	Atendida	30
386	141	11	7	2026-09-24	08:00:00	Alergia en la piel	Atendida	30
387	157	11	7	2026-09-24	08:30:00	Dolor de cabeza	Atendida	30
388	54	12	7	2026-09-24	16:30:00	Dolor abdominal	Atendida	30
389	219	13	8	2026-09-24	08:00:00	Fiebre	Atendida	30
390	150	13	8	2026-09-24	09:00:00	Malestar general	Atendida	30
391	174	13	8	2026-09-24	10:00:00	Dolor muscular	Atendida	30
392	82	14	8	2026-09-24	16:00:00	Alergia en la piel	Atendida	30
393	123	17	10	2026-09-24	09:00:00	Tos persistente	Atendida	30
394	159	17	10	2026-09-24	10:30:00	Alergia en la piel	Atendida	30
395	190	18	10	2026-09-24	14:00:00	Dolor de garganta	Atendida	30
396	40	18	10	2026-09-24	16:00:00	Dolor de cabeza	Atendida	30
397	178	1	1	2026-09-25	08:30:00	Chequeo médico	Atendida	30
398	68	2	1	2026-09-25	16:30:00	Fiebre	Atendida	30
399	41	4	2	2026-09-25	08:00:00	Chequeo médico	Atendida	30
400	134	4	2	2026-09-25	09:30:00	Control general	Atendida	30
401	119	5	2	2026-09-25	15:00:00	Dolor de oído	Atendida	30
402	17	5	2	2026-09-25	16:00:00	Tos persistente	Atendida	30
403	35	9	3	2026-09-25	08:00:00	Dolor de garganta	Atendida	30
404	106	9	3	2026-09-25	08:30:00	Dolor lumbar	Atendida	30
405	224	10	3	2026-09-25	15:00:00	Dolor abdominal	Atendida	30
406	116	10	3	2026-09-25	17:00:00	Dolor lumbar	Atendida	30
407	161	11	7	2026-09-25	09:00:00	Tos persistente	Atendida	30
408	207	11	7	2026-09-25	10:00:00	Náuseas y vómito	Atendida	30
409	147	12	7	2026-09-25	17:30:00	Dolor lumbar	Inasistida	30
410	99	13	8	2026-09-25	08:30:00	Malestar general	Atendida	30
411	49	14	8	2026-09-25	15:30:00	Fiebre	Atendida	30
412	61	14	8	2026-09-25	16:30:00	Dolor lumbar	Inasistida	30
413	163	14	8	2026-09-25	17:30:00	Tos persistente	Atendida	30
414	218	15	9	2026-09-25	11:00:00	Dolor de oído	Cancelada	30
415	134	15	9	2026-09-25	11:30:00	Alergia en la piel	Atendida	30
416	71	16	9	2026-09-25	14:00:00	Fiebre	Inasistida	30
417	172	17	10	2026-09-25	08:00:00	Malestar general	Atendida	30
418	84	17	10	2026-09-25	09:00:00	Dolor lumbar	Inasistida	30
419	70	17	10	2026-09-25	11:30:00	Fiebre	Atendida	30
420	98	18	10	2026-09-25	14:30:00	Control de presión arterial	Atendida	30
421	199	18	10	2026-09-25	15:00:00	Dolor muscular	Atendida	30
422	163	18	10	2026-09-25	16:00:00	Chequeo médico	Atendida	30
423	115	19	13	2026-09-25	08:00:00	Dolor de garganta	Atendida	30
424	70	19	13	2026-09-25	08:30:00	Dolor de oído	Inasistida	30
425	69	19	13	2026-09-25	11:30:00	Malestar general	Atendida	30
426	186	20	13	2026-09-25	16:30:00	Control de presión arterial	Inasistida	30
427	99	1	1	2026-09-28	09:00:00	Control de diabetes	Cancelada	30
428	7	1	1	2026-09-28	09:30:00	Fiebre	Cancelada	30
429	174	2	1	2026-09-28	15:00:00	Control general	Atendida	30
430	98	2	1	2026-09-28	16:30:00	Chequeo médico	Atendida	30
431	99	2	1	2026-09-28	17:30:00	Dolor abdominal	Atendida	30
432	184	4	2	2026-09-28	10:30:00	Control de diabetes	Atendida	30
433	169	4	2	2026-09-28	11:30:00	Malestar general	Atendida	30
434	8	5	2	2026-09-28	14:00:00	Náuseas y vómito	Atendida	30
435	203	5	2	2026-09-28	15:00:00	Tos persistente	Atendida	30
436	172	5	2	2026-09-28	16:30:00	Fiebre	Atendida	30
437	44	9	3	2026-09-28	08:00:00	Alergia en la piel	Atendida	30
438	146	9	3	2026-09-28	09:30:00	Alergia en la piel	Atendida	30
439	106	10	3	2026-09-28	16:30:00	Malestar general	Atendida	30
440	114	10	3	2026-09-28	17:00:00	Alergia en la piel	Atendida	30
441	51	12	7	2026-09-28	14:00:00	Náuseas y vómito	Atendida	30
442	110	14	8	2026-09-28	15:00:00	Alergia en la piel	Atendida	30
443	112	14	8	2026-09-28	15:30:00	Gripe	Atendida	30
444	15	14	8	2026-09-28	17:00:00	Dolor abdominal	Inasistida	30
445	99	15	9	2026-09-28	10:30:00	Fiebre	Atendida	30
446	84	16	9	2026-09-28	15:30:00	Alergia en la piel	Atendida	30
447	177	17	10	2026-09-28	08:00:00	Mareo	Inasistida	30
448	53	17	10	2026-09-28	09:30:00	Control de presión arterial	Atendida	30
449	86	17	10	2026-09-28	10:30:00	Mareo	Atendida	30
450	189	17	10	2026-09-28	11:00:00	Mareo	Atendida	30
451	9	19	13	2026-09-28	11:30:00	Dolor muscular	Atendida	30
452	163	1	1	2026-09-29	09:00:00	Tos persistente	Atendida	30
453	112	1	1	2026-09-29	09:30:00	Fiebre	Atendida	30
454	135	1	1	2026-09-29	10:30:00	Mareo	Atendida	30
455	29	1	1	2026-09-29	11:00:00	Dolor abdominal	Atendida	30
456	173	2	1	2026-09-29	14:30:00	Dolor lumbar	Atendida	30
457	107	4	2	2026-09-29	08:00:00	Dolor lumbar	Atendida	30
458	53	4	2	2026-09-29	10:30:00	Mareo	Atendida	30
459	64	5	2	2026-09-29	14:30:00	Control de presión arterial	Atendida	30
460	37	5	2	2026-09-29	16:30:00	Malestar general	Atendida	30
461	225	5	2	2026-09-29	17:30:00	Náuseas y vómito	Atendida	30
462	184	10	3	2026-09-29	17:30:00	Alergia en la piel	Atendida	30
463	165	11	7	2026-09-29	09:00:00	Chequeo médico	Atendida	30
464	24	11	7	2026-09-29	09:30:00	Dolor abdominal	Atendida	30
465	31	12	7	2026-09-29	14:00:00	Control general	Atendida	30
466	17	14	8	2026-09-29	14:00:00	Dolor de oído	Atendida	30
467	136	14	8	2026-09-29	16:00:00	Malestar general	Atendida	30
468	221	15	9	2026-09-29	08:30:00	Control de presión arterial	Atendida	30
469	91	15	9	2026-09-29	09:00:00	Dolor de oído	Atendida	30
470	143	16	9	2026-09-29	17:00:00	Control de presión arterial	Atendida	30
471	98	16	9	2026-09-29	17:30:00	Dolor muscular	Atendida	30
472	29	17	10	2026-09-29	09:30:00	Control de diabetes	Atendida	30
473	188	17	10	2026-09-29	10:30:00	Malestar general	Atendida	30
474	3	18	10	2026-09-29	16:00:00	Dolor abdominal	Atendida	30
475	57	19	13	2026-09-29	08:00:00	Control de presión arterial	Atendida	30
476	86	19	13	2026-09-29	10:00:00	Mareo	Atendida	30
477	203	19	13	2026-09-29	10:30:00	Dolor de cabeza	Atendida	30
478	2	20	13	2026-09-29	16:00:00	Náuseas y vómito	Atendida	30
479	21	20	13	2026-09-29	16:30:00	Tos persistente	Cancelada	30
480	11	1	1	2026-09-30	08:30:00	Tos persistente	Atendida	30
481	203	1	1	2026-09-30	10:30:00	Mareo	Atendida	30
482	156	1	1	2026-09-30	11:30:00	Tos persistente	Atendida	30
483	96	2	1	2026-09-30	14:30:00	Gripe	Cancelada	30
484	22	2	1	2026-09-30	17:00:00	Tos persistente	Atendida	30
485	70	4	2	2026-09-30	08:30:00	Náuseas y vómito	Cancelada	30
486	42	4	2	2026-09-30	10:30:00	Alergia en la piel	Atendida	30
487	132	5	2	2026-09-30	16:00:00	Dolor lumbar	Atendida	30
488	206	9	3	2026-09-30	08:30:00	Dolor lumbar	Atendida	30
489	225	10	3	2026-09-30	15:30:00	Control de diabetes	Atendida	30
490	130	10	3	2026-09-30	16:30:00	Fiebre	Atendida	30
491	42	10	3	2026-09-30	17:30:00	Dolor de garganta	Atendida	30
492	78	11	7	2026-09-30	09:30:00	Dolor muscular	Atendida	30
493	157	12	7	2026-09-30	15:30:00	Mareo	Atendida	30
494	38	12	7	2026-09-30	16:30:00	Fiebre	Atendida	30
495	69	13	8	2026-09-30	08:00:00	Control de diabetes	Atendida	30
496	153	13	8	2026-09-30	09:30:00	Control general	Cancelada	30
497	103	13	8	2026-09-30	10:00:00	Malestar general	Atendida	30
498	141	14	8	2026-09-30	14:30:00	Dolor lumbar	Atendida	30
499	25	14	8	2026-09-30	16:00:00	Dolor abdominal	Inasistida	30
500	52	15	9	2026-09-30	11:30:00	Fiebre	Atendida	30
501	85	17	10	2026-09-30	10:30:00	Control de diabetes	Cancelada	30
502	172	17	10	2026-09-30	11:30:00	Dolor muscular	Inasistida	30
503	46	18	10	2026-09-30	15:30:00	Control de presión arterial	Atendida	30
504	169	18	10	2026-09-30	16:00:00	Chequeo médico	Atendida	30
505	183	18	10	2026-09-30	16:30:00	Dolor muscular	Atendida	30
506	70	19	13	2026-09-30	10:30:00	Dolor lumbar	Inasistida	30
507	118	19	13	2026-09-30	11:00:00	Chequeo médico	Atendida	30
508	186	20	13	2026-09-30	14:30:00	Chequeo médico	Atendida	30
509	82	1	1	2026-10-01	08:30:00	Dolor de oído	Atendida	30
510	117	1	1	2026-10-01	11:00:00	Control de presión arterial	Atendida	30
511	116	1	1	2026-10-01	11:30:00	Náuseas y vómito	Inasistida	30
512	187	2	1	2026-10-01	15:00:00	Dolor abdominal	Atendida	30
513	191	4	2	2026-10-01	10:30:00	Alergia en la piel	Inasistida	30
514	125	9	3	2026-10-01	09:00:00	Chequeo médico	Atendida	30
515	178	9	3	2026-10-01	10:30:00	Dolor de oído	Atendida	30
516	95	10	3	2026-10-01	16:00:00	Tos persistente	Inasistida	30
517	167	10	3	2026-10-01	17:00:00	Náuseas y vómito	Inasistida	30
518	88	11	7	2026-10-01	09:30:00	Dolor de oído	Inasistida	30
519	151	11	7	2026-10-01	11:00:00	Control de diabetes	Atendida	30
520	15	12	7	2026-10-01	15:00:00	Fiebre	Atendida	30
521	179	12	7	2026-10-01	15:30:00	Dolor de oído	Atendida	30
522	95	12	7	2026-10-01	17:30:00	Alergia en la piel	Atendida	30
523	87	13	8	2026-10-01	08:00:00	Control de diabetes	Atendida	30
524	14	13	8	2026-10-01	09:00:00	Náuseas y vómito	Inasistida	30
525	195	14	8	2026-10-01	16:30:00	Control general	Atendida	30
526	139	15	9	2026-10-01	08:30:00	Dolor de oído	Atendida	30
527	83	15	9	2026-10-01	10:30:00	Dolor abdominal	Atendida	30
528	187	17	10	2026-10-01	11:00:00	Dolor de garganta	Atendida	30
529	34	17	10	2026-10-01	11:30:00	Dolor muscular	Inasistida	30
530	11	18	10	2026-10-01	14:00:00	Dolor de cabeza	Atendida	30
531	1	18	10	2026-10-01	15:30:00	Mareo	Atendida	30
532	204	18	10	2026-10-01	16:00:00	Náuseas y vómito	Inasistida	30
533	33	19	13	2026-10-01	08:30:00	Dolor muscular	Cancelada	30
534	43	20	13	2026-10-01	14:30:00	Control de diabetes	Inasistida	30
535	56	20	13	2026-10-01	16:30:00	Dolor abdominal	Atendida	30
536	169	20	13	2026-10-01	17:00:00	Dolor de oído	Atendida	30
537	124	1	1	2026-10-02	08:30:00	Malestar general	Atendida	30
538	221	2	1	2026-10-02	14:00:00	Alergia en la piel	Cancelada	30
539	142	4	2	2026-10-02	08:00:00	Alergia en la piel	Atendida	30
540	158	4	2	2026-10-02	11:00:00	Tos persistente	Atendida	30
541	139	5	2	2026-10-02	16:30:00	Chequeo médico	Atendida	30
542	58	9	3	2026-10-02	09:00:00	Malestar general	Atendida	30
543	28	11	7	2026-10-02	08:00:00	Dolor lumbar	Inasistida	30
544	68	11	7	2026-10-02	08:30:00	Dolor de garganta	Atendida	30
545	117	11	7	2026-10-02	10:00:00	Control de diabetes	Atendida	30
546	175	12	7	2026-10-02	14:30:00	Control de diabetes	Atendida	30
547	90	13	8	2026-10-02	11:30:00	Control de presión arterial	Atendida	30
548	144	14	8	2026-10-02	15:00:00	Chequeo médico	Atendida	30
549	139	14	8	2026-10-02	16:30:00	Tos persistente	Atendida	30
550	167	15	9	2026-10-02	11:30:00	Control de diabetes	Atendida	30
551	214	16	9	2026-10-02	15:00:00	Dolor de garganta	Inasistida	30
552	216	16	9	2026-10-02	17:30:00	Control de presión arterial	Atendida	30
553	49	17	10	2026-10-02	08:30:00	Dolor de cabeza	Atendida	30
554	202	18	10	2026-10-02	15:00:00	Control de diabetes	Atendida	30
555	91	18	10	2026-10-02	15:30:00	Gripe	Cancelada	30
556	125	18	10	2026-10-02	17:00:00	Náuseas y vómito	Cancelada	30
557	188	19	13	2026-10-02	08:30:00	Dolor de oído	Cancelada	30
558	63	19	13	2026-10-02	10:30:00	Dolor de garganta	Atendida	30
559	198	20	13	2026-10-02	15:00:00	Control de presión arterial	Atendida	30
560	117	20	13	2026-10-02	16:30:00	Control general	Atendida	30
561	200	1	1	2026-10-05	10:00:00	Gripe	Atendida	30
562	66	2	1	2026-10-05	14:00:00	Náuseas y vómito	Atendida	30
563	57	2	1	2026-10-05	15:00:00	Control de presión arterial	Inasistida	30
564	174	4	2	2026-10-05	08:00:00	Dolor lumbar	Cancelada	30
565	41	4	2	2026-10-05	10:30:00	Dolor de garganta	Inasistida	30
566	82	4	2	2026-10-05	11:30:00	Náuseas y vómito	Atendida	30
567	223	5	2	2026-10-05	14:30:00	Control general	Atendida	30
568	213	5	2	2026-10-05	15:30:00	Alergia en la piel	Atendida	30
569	155	9	3	2026-10-05	09:30:00	Dolor muscular	Atendida	30
570	176	9	3	2026-10-05	10:30:00	Dolor de garganta	Atendida	30
571	118	10	3	2026-10-05	16:30:00	Control de presión arterial	Atendida	30
572	23	11	7	2026-10-05	08:30:00	Gripe	Atendida	30
573	159	11	7	2026-10-05	09:30:00	Control de presión arterial	Atendida	30
574	211	11	7	2026-10-05	10:30:00	Dolor de garganta	Atendida	30
575	155	12	7	2026-10-05	17:30:00	Control de diabetes	Atendida	30
576	224	13	8	2026-10-05	11:30:00	Dolor de oído	Atendida	30
577	223	15	9	2026-10-05	09:30:00	Dolor abdominal	Atendida	30
578	123	16	9	2026-10-05	14:30:00	Dolor lumbar	Atendida	30
579	147	16	9	2026-10-05	15:00:00	Dolor de cabeza	Atendida	30
580	75	17	10	2026-10-05	08:30:00	Control general	Atendida	30
581	114	19	13	2026-10-05	10:30:00	Dolor de garganta	Atendida	30
582	29	19	13	2026-10-05	11:00:00	Malestar general	Inasistida	30
583	68	20	13	2026-10-05	15:00:00	Control general	Atendida	30
584	209	2	1	2026-10-06	16:00:00	Dolor abdominal	Cancelada	30
585	89	4	2	2026-10-06	08:00:00	Dolor lumbar	Atendida	30
586	51	4	2	2026-10-06	10:00:00	Control general	Atendida	30
587	149	4	2	2026-10-06	10:30:00	Alergia en la piel	Atendida	30
588	177	4	2	2026-10-06	11:30:00	Dolor lumbar	Atendida	30
589	90	5	2	2026-10-06	16:30:00	Dolor de cabeza	Atendida	30
590	182	9	3	2026-10-06	08:00:00	Dolor de oído	Atendida	30
591	134	10	3	2026-10-06	14:00:00	Dolor abdominal	Inasistida	30
592	81	12	7	2026-10-06	15:00:00	Dolor de oído	Atendida	30
593	26	12	7	2026-10-06	16:00:00	Mareo	Cancelada	30
594	207	12	7	2026-10-06	17:00:00	Dolor lumbar	Atendida	30
595	121	13	8	2026-10-06	11:00:00	Gripe	Inasistida	30
596	9	17	10	2026-10-06	08:00:00	Alergia en la piel	Atendida	30
597	145	17	10	2026-10-06	09:30:00	Malestar general	Atendida	30
598	73	18	10	2026-10-06	15:00:00	Dolor abdominal	Atendida	30
599	96	18	10	2026-10-06	16:30:00	Chequeo médico	Atendida	30
600	35	18	10	2026-10-06	17:30:00	Náuseas y vómito	Atendida	30
601	217	19	13	2026-10-06	09:00:00	Dolor abdominal	Atendida	30
602	154	19	13	2026-10-06	10:30:00	Chequeo médico	Atendida	30
603	187	20	13	2026-10-06	15:30:00	Dolor lumbar	Atendida	30
604	32	1	1	2026-10-07	08:30:00	Alergia en la piel	Cancelada	30
605	76	2	1	2026-10-07	15:00:00	Dolor de oído	Atendida	30
606	123	2	1	2026-10-07	16:00:00	Alergia en la piel	Atendida	30
607	74	2	1	2026-10-07	17:00:00	Gripe	Atendida	30
608	8	4	2	2026-10-07	11:00:00	Alergia en la piel	Atendida	30
609	198	10	3	2026-10-07	15:30:00	Fiebre	Atendida	30
610	23	10	3	2026-10-07	16:30:00	Malestar general	Atendida	30
611	183	11	7	2026-10-07	08:30:00	Dolor de garganta	Cancelada	30
612	107	11	7	2026-10-07	11:00:00	Dolor abdominal	Inasistida	30
613	190	12	7	2026-10-07	15:00:00	Náuseas y vómito	Cancelada	30
614	106	12	7	2026-10-07	17:00:00	Control de diabetes	Atendida	30
615	112	13	8	2026-10-07	09:00:00	Control de diabetes	Atendida	30
616	104	14	8	2026-10-07	16:30:00	Alergia en la piel	Atendida	30
617	210	15	9	2026-10-07	08:00:00	Fiebre	Atendida	30
618	201	16	9	2026-10-07	16:00:00	Tos persistente	Atendida	30
619	88	16	9	2026-10-07	16:30:00	Dolor muscular	Atendida	30
620	139	17	10	2026-10-07	09:30:00	Dolor abdominal	Cancelada	30
621	225	17	10	2026-10-07	10:30:00	Malestar general	Cancelada	30
622	203	18	10	2026-10-07	16:30:00	Dolor lumbar	Inasistida	30
623	139	19	13	2026-10-07	11:30:00	Fiebre	Atendida	30
624	104	20	13	2026-10-07	14:00:00	Tos persistente	Atendida	30
625	60	20	13	2026-10-07	14:30:00	Gripe	Atendida	30
626	69	1	1	2026-10-08	08:30:00	Mareo	Atendida	30
627	142	1	1	2026-10-08	09:00:00	Náuseas y vómito	Atendida	30
628	145	4	2	2026-10-08	08:00:00	Dolor de garganta	Atendida	30
629	179	4	2	2026-10-08	08:30:00	Dolor de garganta	Atendida	30
630	133	4	2	2026-10-08	09:00:00	Dolor de oído	Atendida	30
631	127	4	2	2026-10-08	10:30:00	Dolor abdominal	Atendida	30
632	146	5	2	2026-10-08	17:30:00	Gripe	Atendida	30
633	68	11	7	2026-10-08	11:30:00	Dolor lumbar	Atendida	30
634	79	12	7	2026-10-08	17:00:00	Mareo	Atendida	30
635	131	12	7	2026-10-08	17:30:00	Chequeo médico	Atendida	30
636	140	13	8	2026-10-08	11:30:00	Mareo	Atendida	30
637	186	14	8	2026-10-08	15:00:00	Dolor de cabeza	Atendida	30
638	81	15	9	2026-10-08	09:00:00	Mareo	Atendida	30
639	62	16	9	2026-10-08	14:30:00	Control general	Atendida	30
640	184	16	9	2026-10-08	16:00:00	Dolor abdominal	Atendida	30
641	189	16	9	2026-10-08	17:00:00	Tos persistente	Atendida	30
642	96	17	10	2026-10-08	09:00:00	Dolor abdominal	Atendida	30
643	64	18	10	2026-10-08	14:30:00	Control de diabetes	Inasistida	30
644	121	18	10	2026-10-08	17:30:00	Tos persistente	Atendida	30
645	21	19	13	2026-10-08	10:30:00	Dolor lumbar	Atendida	30
646	108	20	13	2026-10-08	15:00:00	Gripe	Atendida	30
647	186	20	13	2026-10-08	15:30:00	Fiebre	Atendida	30
648	142	2	1	2026-10-09	17:00:00	Dolor de cabeza	Atendida	30
649	12	4	2	2026-10-09	11:00:00	Fiebre	Atendida	30
650	200	4	2	2026-10-09	11:30:00	Control de diabetes	Atendida	30
651	181	5	2	2026-10-09	14:00:00	Tos persistente	Atendida	30
652	98	5	2	2026-10-09	15:30:00	Control general	Atendida	30
653	61	10	3	2026-10-09	16:00:00	Dolor lumbar	Atendida	30
654	162	12	7	2026-10-09	14:30:00	Tos persistente	Atendida	30
655	111	13	8	2026-10-09	08:30:00	Dolor de cabeza	Atendida	30
656	49	14	8	2026-10-09	17:00:00	Control de presión arterial	Inasistida	30
657	159	15	9	2026-10-09	09:30:00	Control de presión arterial	Atendida	30
658	211	15	9	2026-10-09	10:00:00	Control de diabetes	Atendida	30
659	114	15	9	2026-10-09	11:30:00	Tos persistente	Atendida	30
660	215	16	9	2026-10-09	15:30:00	Dolor abdominal	Atendida	30
661	207	16	9	2026-10-09	17:30:00	Náuseas y vómito	Atendida	30
662	8	18	10	2026-10-09	14:00:00	Malestar general	Atendida	30
663	218	19	13	2026-10-09	08:00:00	Dolor de oído	Inasistida	30
664	23	19	13	2026-10-09	09:00:00	Control de presión arterial	Cancelada	30
665	132	19	13	2026-10-09	10:30:00	Fiebre	Atendida	30
666	223	20	13	2026-10-09	17:30:00	Gripe	Inasistida	30
667	131	4	2	2026-10-12	08:30:00	Dolor de garganta	Atendida	30
668	218	5	2	2026-10-12	14:00:00	Control de diabetes	Inasistida	30
669	199	5	2	2026-10-12	15:30:00	Dolor muscular	Cancelada	30
670	150	9	3	2026-10-12	08:30:00	Dolor de cabeza	Atendida	30
671	85	9	3	2026-10-12	09:00:00	Control general	Atendida	30
672	123	10	3	2026-10-12	15:00:00	Dolor de oído	Atendida	30
673	63	11	7	2026-10-12	09:00:00	Dolor de oído	Atendida	30
674	72	12	7	2026-10-12	14:30:00	Dolor lumbar	Atendida	30
675	219	12	7	2026-10-12	16:30:00	Fiebre	Atendida	30
676	49	13	8	2026-10-12	08:30:00	Mareo	Inasistida	30
677	73	15	9	2026-10-12	08:30:00	Dolor muscular	Atendida	30
678	51	15	9	2026-10-12	09:00:00	Control de diabetes	Cancelada	30
679	55	15	9	2026-10-12	09:30:00	Dolor abdominal	Atendida	30
680	58	15	9	2026-10-12	10:30:00	Malestar general	Atendida	30
681	75	17	10	2026-10-12	10:00:00	Malestar general	Atendida	30
682	35	18	10	2026-10-12	15:30:00	Chequeo médico	Atendida	30
683	203	18	10	2026-10-12	16:30:00	Dolor de garganta	Atendida	30
684	147	18	10	2026-10-12	17:00:00	Control de diabetes	Atendida	30
685	29	19	13	2026-10-12	08:00:00	Mareo	Atendida	30
686	147	19	13	2026-10-12	10:00:00	Dolor muscular	Inasistida	30
687	49	19	13	2026-10-12	11:00:00	Malestar general	Atendida	30
688	32	19	13	2026-10-12	11:30:00	Dolor lumbar	Atendida	30
689	30	20	13	2026-10-12	17:30:00	Control general	Atendida	30
690	7	1	1	2026-10-13	08:30:00	Control general	Atendida	30
691	106	1	1	2026-10-13	10:30:00	Control general	Atendida	30
692	62	2	1	2026-10-13	15:30:00	Mareo	Atendida	30
693	164	4	2	2026-10-13	09:00:00	Malestar general	Atendida	30
694	24	4	2	2026-10-13	09:30:00	Control de presión arterial	Atendida	30
695	214	4	2	2026-10-13	10:30:00	Náuseas y vómito	Atendida	30
696	28	4	2	2026-10-13	11:00:00	Dolor lumbar	Atendida	30
697	121	4	2	2026-10-13	11:30:00	Mareo	Atendida	30
698	110	5	2	2026-10-13	14:30:00	Náuseas y vómito	Inasistida	30
699	173	5	2	2026-10-13	16:00:00	Dolor abdominal	Cancelada	30
700	216	5	2	2026-10-13	16:30:00	Control general	Atendida	30
701	188	10	3	2026-10-13	14:00:00	Control general	Atendida	30
702	50	11	7	2026-10-13	08:30:00	Dolor lumbar	Atendida	30
703	36	11	7	2026-10-13	11:30:00	Dolor muscular	Atendida	30
704	51	12	7	2026-10-13	14:30:00	Control de diabetes	Atendida	30
705	73	12	7	2026-10-13	17:00:00	Fiebre	Inasistida	30
706	157	13	8	2026-10-13	08:00:00	Control de diabetes	Atendida	30
707	107	13	8	2026-10-13	08:30:00	Dolor de oído	Atendida	30
708	115	13	8	2026-10-13	10:00:00	Gripe	Atendida	30
709	151	13	8	2026-10-13	11:30:00	Dolor de oído	Inasistida	30
710	53	14	8	2026-10-13	16:00:00	Alergia en la piel	Atendida	30
711	166	15	9	2026-10-13	08:00:00	Dolor de garganta	Atendida	30
712	81	15	9	2026-10-13	10:00:00	Control de diabetes	Inasistida	30
713	139	16	9	2026-10-13	14:00:00	Dolor lumbar	Atendida	30
714	142	17	10	2026-10-13	10:00:00	Dolor de cabeza	Cancelada	30
715	81	18	10	2026-10-13	14:30:00	Chequeo médico	Atendida	30
716	149	20	13	2026-10-13	15:00:00	Control de diabetes	Atendida	30
717	117	1	1	2026-10-14	10:00:00	Control de diabetes	Cancelada	30
718	190	2	1	2026-10-14	14:30:00	Náuseas y vómito	Atendida	30
719	193	2	1	2026-10-14	16:00:00	Malestar general	Atendida	30
720	40	2	1	2026-10-14	17:30:00	Alergia en la piel	Atendida	30
721	50	4	2	2026-10-14	08:30:00	Chequeo médico	Atendida	30
722	20	5	2	2026-10-14	14:00:00	Chequeo médico	Cancelada	30
723	191	5	2	2026-10-14	15:30:00	Gripe	Atendida	30
724	206	9	3	2026-10-14	10:00:00	Dolor de garganta	Atendida	30
726	118	10	3	2026-10-14	15:30:00	Chequeo médico	Atendida	30
727	9	11	7	2026-10-14	08:30:00	Dolor de garganta	Atendida	30
728	116	11	7	2026-10-14	09:30:00	Mareo	Atendida	30
729	94	12	7	2026-10-14	14:00:00	Control de diabetes	Atendida	30
730	14	12	7	2026-10-14	16:00:00	Control de presión arterial	Atendida	30
731	119	13	8	2026-10-14	08:30:00	Control de diabetes	Atendida	30
732	213	14	8	2026-10-14	15:30:00	Dolor de garganta	Atendida	30
733	166	15	9	2026-10-14	09:30:00	Dolor de oído	Inasistida	30
734	175	16	9	2026-10-14	15:00:00	Tos persistente	Atendida	30
735	140	16	9	2026-10-14	17:30:00	Tos persistente	Inasistida	30
736	181	17	10	2026-10-14	11:00:00	Fiebre	Inasistida	30
737	108	18	10	2026-10-14	17:00:00	Dolor lumbar	Atendida	30
738	136	19	13	2026-10-14	08:30:00	Malestar general	Atendida	30
739	141	20	13	2026-10-14	15:00:00	Dolor de garganta	Atendida	30
740	97	20	13	2026-10-14	17:30:00	Tos persistente	Atendida	30
741	192	1	1	2026-10-15	09:30:00	Náuseas y vómito	Inasistida	30
742	2	1	1	2026-10-15	11:30:00	Náuseas y vómito	Atendida	30
743	17	2	1	2026-10-15	15:30:00	Gripe	Atendida	30
744	65	2	1	2026-10-15	16:30:00	Control general	Atendida	30
745	202	2	1	2026-10-15	17:00:00	Control de presión arterial	Atendida	30
746	112	2	1	2026-10-15	17:30:00	Fiebre	Atendida	30
747	32	4	2	2026-10-15	08:00:00	Control de presión arterial	Atendida	30
748	122	4	2	2026-10-15	08:30:00	Chequeo médico	Atendida	30
749	87	4	2	2026-10-15	09:30:00	Mareo	Atendida	30
750	113	4	2	2026-10-15	11:00:00	Control de presión arterial	Atendida	30
751	41	5	2	2026-10-15	15:00:00	Dolor de oído	Atendida	30
752	138	5	2	2026-10-15	16:00:00	Gripe	Atendida	30
753	54	5	2	2026-10-15	17:30:00	Gripe	Atendida	30
754	106	9	3	2026-10-15	08:00:00	Dolor abdominal	Cancelada	30
755	113	9	3	2026-10-15	10:30:00	Dolor de garganta	Atendida	30
756	49	9	3	2026-10-15	11:30:00	Fiebre	Atendida	30
757	21	10	3	2026-10-15	15:00:00	Mareo	Cancelada	30
758	58	10	3	2026-10-15	16:30:00	Tos persistente	Atendida	30
759	196	11	7	2026-10-15	08:30:00	Control de presión arterial	Atendida	30
760	97	13	8	2026-10-15	09:30:00	Dolor de garganta	Atendida	30
761	208	13	8	2026-10-15	10:00:00	Fiebre	Atendida	30
762	93	13	8	2026-10-15	11:30:00	Chequeo médico	Inasistida	30
763	106	14	8	2026-10-15	15:30:00	Dolor muscular	Atendida	30
764	76	15	9	2026-10-15	08:00:00	Dolor de oído	Cancelada	30
765	24	16	9	2026-10-15	14:00:00	Alergia en la piel	Atendida	30
766	188	16	9	2026-10-15	15:00:00	Gripe	Atendida	30
767	125	17	10	2026-10-15	10:00:00	Alergia en la piel	Atendida	30
768	99	17	10	2026-10-15	11:00:00	Tos persistente	Atendida	30
769	164	18	10	2026-10-15	16:30:00	Control general	Atendida	30
770	40	19	13	2026-10-15	10:30:00	Malestar general	Atendida	30
771	211	20	13	2026-10-15	14:30:00	Alergia en la piel	Atendida	30
772	151	20	13	2026-10-15	16:30:00	Dolor muscular	Atendida	30
773	37	20	13	2026-10-15	17:30:00	Control general	Atendida	30
774	143	1	1	2026-10-16	08:00:00	Control general	Atendida	30
775	130	1	1	2026-10-16	09:30:00	Control de presión arterial	Atendida	30
776	46	2	1	2026-10-16	15:00:00	Mareo	Atendida	30
777	54	2	1	2026-10-16	17:00:00	Dolor lumbar	Atendida	30
778	24	4	2	2026-10-16	09:00:00	Malestar general	Atendida	30
779	2	4	2	2026-10-16	10:00:00	Dolor de oído	Atendida	30
781	35	9	3	2026-10-16	09:00:00	Tos persistente	Atendida	30
782	116	9	3	2026-10-16	09:30:00	Mareo	Atendida	30
783	110	10	3	2026-10-16	14:00:00	Chequeo médico	Atendida	30
784	12	10	3	2026-10-16	14:30:00	Dolor lumbar	Cancelada	30
785	145	11	7	2026-10-16	09:00:00	Dolor de cabeza	Atendida	30
786	88	11	7	2026-10-16	11:30:00	Chequeo médico	Atendida	30
787	73	12	7	2026-10-16	17:00:00	Náuseas y vómito	Atendida	30
788	36	13	8	2026-10-16	08:30:00	Fiebre	Atendida	30
789	209	14	8	2026-10-16	17:00:00	Dolor abdominal	Atendida	30
790	207	14	8	2026-10-16	17:30:00	Dolor muscular	Atendida	30
791	162	15	9	2026-10-16	11:00:00	Dolor lumbar	Inasistida	30
792	15	16	9	2026-10-16	14:00:00	Dolor de garganta	Atendida	30
793	142	16	9	2026-10-16	14:30:00	Fiebre	Inasistida	30
794	27	18	10	2026-10-16	15:00:00	Dolor de oído	Atendida	30
795	141	18	10	2026-10-16	16:30:00	Control general	Atendida	30
796	172	19	13	2026-10-16	09:00:00	Chequeo médico	Atendida	30
797	205	20	13	2026-10-16	16:30:00	Mareo	Atendida	30
798	159	4	2	2026-10-19	10:30:00	Chequeo médico	Programada	30
799	62	5	2	2026-10-19	16:00:00	Dolor lumbar	Programada	30
800	179	5	2	2026-10-19	17:00:00	Chequeo médico	Programada	30
801	77	5	2	2026-10-19	17:30:00	Gripe	Programada	30
802	144	9	3	2026-10-19	08:00:00	Tos persistente	Atendida	30
803	176	10	3	2026-10-19	15:30:00	Dolor muscular	Programada	30
804	37	10	3	2026-10-19	17:30:00	Dolor de cabeza	Programada	30
805	126	11	7	2026-10-19	10:30:00	Dolor de oído	Programada	30
806	169	12	7	2026-10-19	14:30:00	Alergia en la piel	Cancelada	30
807	187	12	7	2026-10-19	15:30:00	Alergia en la piel	Programada	30
808	113	12	7	2026-10-19	17:00:00	Dolor de garganta	Programada	30
809	82	14	8	2026-10-19	17:00:00	Dolor de oído	Programada	30
810	137	16	9	2026-10-19	14:00:00	Náuseas y vómito	Programada	30
811	223	17	10	2026-10-19	08:30:00	Control general	Programada	30
812	150	18	10	2026-10-19	15:00:00	Mareo	Programada	30
813	107	18	10	2026-10-19	16:30:00	Dolor muscular	Programada	30
814	192	19	13	2026-10-19	08:30:00	Dolor abdominal	Programada	30
815	69	19	13	2026-10-19	09:00:00	Control de presión arterial	Programada	30
816	161	19	13	2026-10-19	09:30:00	Malestar general	Programada	30
817	215	19	13	2026-10-19	10:00:00	Control general	Programada	30
818	152	19	13	2026-10-19	11:00:00	Dolor lumbar	Programada	30
819	128	19	13	2026-10-19	11:30:00	Dolor abdominal	Programada	30
820	23	20	13	2026-10-19	14:30:00	Dolor lumbar	Programada	30
821	36	1	1	2026-10-20	08:30:00	Tos persistente	Programada	30
822	153	2	1	2026-10-20	15:00:00	Fiebre	Programada	30
823	183	5	2	2026-10-20	14:30:00	Chequeo médico	Programada	30
824	96	5	2	2026-10-20	15:00:00	Mareo	Programada	30
825	37	5	2	2026-10-20	15:30:00	Control general	Cancelada	30
826	181	5	2	2026-10-20	16:00:00	Dolor de garganta	Cancelada	30
827	71	9	3	2026-10-20	08:30:00	Control general	Programada	30
828	134	9	3	2026-10-20	09:30:00	Dolor de oído	Programada	30
829	140	10	3	2026-10-20	15:00:00	Control de diabetes	Programada	30
830	38	10	3	2026-10-20	15:30:00	Dolor de cabeza	Cancelada	30
831	114	10	3	2026-10-20	17:00:00	Dolor de garganta	Programada	30
832	51	11	7	2026-10-20	08:30:00	Control de diabetes	Programada	30
833	42	13	8	2026-10-20	08:30:00	Dolor de cabeza	Programada	30
834	55	13	8	2026-10-20	09:00:00	Control de diabetes	Programada	30
835	76	13	8	2026-10-20	09:30:00	Dolor muscular	Programada	30
836	56	13	8	2026-10-20	10:00:00	Dolor de oído	Cancelada	30
837	71	14	8	2026-10-20	17:30:00	Control general	Programada	30
838	204	16	9	2026-10-20	14:00:00	Chequeo médico	Programada	30
839	208	16	9	2026-10-20	16:30:00	Mareo	Programada	30
840	94	16	9	2026-10-20	17:30:00	Control de diabetes	Programada	30
841	145	20	13	2026-10-20	16:00:00	Control de diabetes	Programada	30
842	23	20	13	2026-10-20	17:00:00	Dolor de oído	Programada	30
843	212	1	1	2026-10-21	09:00:00	Control general	Programada	30
844	79	5	2	2026-10-21	15:00:00	Control de diabetes	Programada	30
845	125	9	3	2026-10-21	11:30:00	Control general	Programada	30
846	70	10	3	2026-10-21	17:00:00	Dolor muscular	Programada	30
847	207	10	3	2026-10-21	17:30:00	Dolor de cabeza	Programada	30
848	99	11	7	2026-10-21	08:00:00	Control de diabetes	Programada	30
849	41	11	7	2026-10-21	10:30:00	Dolor de cabeza	Programada	30
850	62	11	7	2026-10-21	11:30:00	Control de diabetes	Programada	30
851	131	12	7	2026-10-21	15:30:00	Chequeo médico	Programada	30
852	138	12	7	2026-10-21	16:00:00	Dolor abdominal	Programada	30
853	195	12	7	2026-10-21	16:30:00	Dolor lumbar	Cancelada	30
854	225	13	8	2026-10-21	09:30:00	Malestar general	Programada	30
855	195	14	8	2026-10-21	14:30:00	Tos persistente	Programada	30
856	48	15	9	2026-10-21	10:30:00	Náuseas y vómito	Programada	30
857	7	16	9	2026-10-21	14:30:00	Dolor lumbar	Programada	30
858	186	16	9	2026-10-21	15:00:00	Tos persistente	Programada	30
859	184	16	9	2026-10-21	17:00:00	Náuseas y vómito	Programada	30
860	139	16	9	2026-10-21	17:30:00	Control de diabetes	Programada	30
861	192	17	10	2026-10-21	09:30:00	Malestar general	Programada	30
862	185	18	10	2026-10-21	15:00:00	Dolor abdominal	Programada	30
863	191	18	10	2026-10-21	16:00:00	Dolor de oído	Programada	30
864	177	19	13	2026-10-21	09:30:00	Dolor abdominal	Programada	30
865	217	19	13	2026-10-21	10:00:00	Dolor de cabeza	Cancelada	30
866	121	20	13	2026-10-21	14:00:00	Náuseas y vómito	Programada	30
867	171	20	13	2026-10-21	15:00:00	Control de presión arterial	Programada	30
868	186	1	1	2026-10-22	08:00:00	Control general	Programada	30
869	105	1	1	2026-10-22	08:30:00	Chequeo médico	Programada	30
870	134	1	1	2026-10-22	09:00:00	Dolor abdominal	Programada	30
871	203	1	1	2026-10-22	10:30:00	Control de presión arterial	Programada	30
872	39	2	1	2026-10-22	16:00:00	Dolor muscular	Programada	30
873	47	10	3	2026-10-22	14:30:00	Dolor lumbar	Programada	30
874	13	10	3	2026-10-22	17:30:00	Alergia en la piel	Programada	30
875	200	11	7	2026-10-22	09:00:00	Control de presión arterial	Programada	30
876	36	11	7	2026-10-22	09:30:00	Control de presión arterial	Programada	30
877	116	12	7	2026-10-22	16:00:00	Control de diabetes	Programada	30
878	176	12	7	2026-10-22	17:30:00	Dolor lumbar	Programada	30
879	170	14	8	2026-10-22	14:30:00	Control de diabetes	Programada	30
880	29	14	8	2026-10-22	15:00:00	Gripe	Programada	30
881	194	14	8	2026-10-22	15:30:00	Náuseas y vómito	Programada	30
882	162	14	8	2026-10-22	17:30:00	Tos persistente	Programada	30
883	55	15	9	2026-10-22	08:30:00	Dolor de oído	Programada	30
884	183	16	9	2026-10-22	16:00:00	Dolor de garganta	Programada	30
885	99	17	10	2026-10-22	09:00:00	Chequeo médico	Programada	30
886	101	17	10	2026-10-22	11:00:00	Control de diabetes	Programada	30
887	218	18	10	2026-10-22	14:30:00	Dolor muscular	Programada	30
888	60	18	10	2026-10-22	15:00:00	Malestar general	Programada	30
889	224	19	13	2026-10-22	10:00:00	Control de presión arterial	Programada	30
890	134	20	13	2026-10-22	14:00:00	Dolor de garganta	Programada	30
891	149	20	13	2026-10-22	16:30:00	Control general	Programada	30
892	177	20	13	2026-10-22	17:00:00	Dolor muscular	Programada	30
893	187	20	13	2026-10-22	17:30:00	Dolor de oído	Programada	30
894	202	1	1	2026-10-23	08:00:00	Chequeo médico	Programada	30
895	87	1	1	2026-10-23	08:30:00	Náuseas y vómito	Programada	30
896	106	1	1	2026-10-23	11:00:00	Mareo	Programada	30
897	174	2	1	2026-10-23	16:00:00	Dolor de garganta	Programada	30
898	178	4	2	2026-10-23	08:00:00	Dolor abdominal	Cancelada	30
899	29	9	3	2026-10-23	09:30:00	Dolor muscular	Programada	30
900	113	9	3	2026-10-23	10:30:00	Control general	Programada	30
901	28	11	7	2026-10-23	08:00:00	Alergia en la piel	Programada	30
902	35	12	7	2026-10-23	16:30:00	Malestar general	Programada	30
903	153	13	8	2026-10-23	08:30:00	Dolor de cabeza	Programada	30
904	75	13	8	2026-10-23	10:00:00	Dolor de cabeza	Programada	30
905	216	13	8	2026-10-23	10:30:00	Dolor de garganta	Programada	30
906	76	14	8	2026-10-23	14:00:00	Control de presión arterial	Programada	30
907	71	14	8	2026-10-23	15:30:00	Dolor muscular	Programada	30
908	157	16	9	2026-10-23	14:30:00	Control de presión arterial	Programada	30
909	158	16	9	2026-10-23	15:30:00	Chequeo médico	Programada	30
910	205	16	9	2026-10-23	17:30:00	Malestar general	Programada	30
911	217	17	10	2026-10-23	11:00:00	Gripe	Programada	30
912	74	17	10	2026-10-23	11:30:00	Gripe	Programada	30
913	63	20	13	2026-10-23	15:30:00	Gripe	Programada	30
914	217	20	13	2026-10-23	16:30:00	Dolor muscular	Programada	30
915	1	1	1	2026-10-26	08:00:00	Control general	Programada	30
916	170	1	1	2026-10-26	10:00:00	Mareo	Programada	30
917	161	2	1	2026-10-26	15:30:00	Dolor abdominal	Programada	30
918	189	4	2	2026-10-26	08:00:00	Dolor muscular	Programada	30
919	3	4	2	2026-10-26	08:30:00	Control de presión arterial	Programada	30
920	141	4	2	2026-10-26	10:30:00	Fiebre	Programada	30
921	36	5	2	2026-10-26	15:00:00	Malestar general	Programada	30
922	15	9	3	2026-10-26	09:30:00	Fiebre	Programada	30
923	53	10	3	2026-10-26	14:00:00	Tos persistente	Programada	30
924	51	11	7	2026-10-26	09:00:00	Dolor lumbar	Cancelada	30
925	58	11	7	2026-10-26	09:30:00	Dolor de cabeza	Programada	30
926	186	14	8	2026-10-26	15:00:00	Dolor de cabeza	Programada	30
927	58	14	8	2026-10-26	16:00:00	Chequeo médico	Programada	30
928	198	15	9	2026-10-26	09:30:00	Tos persistente	Programada	30
929	186	15	9	2026-10-26	11:00:00	Control de diabetes	Programada	30
930	164	16	9	2026-10-26	15:00:00	Alergia en la piel	Programada	30
931	200	16	9	2026-10-26	16:00:00	Control de diabetes	Programada	30
932	28	17	10	2026-10-26	08:00:00	Malestar general	Programada	30
933	100	17	10	2026-10-26	10:30:00	Dolor de cabeza	Programada	30
934	50	17	10	2026-10-26	11:30:00	Malestar general	Programada	30
935	35	19	13	2026-10-26	08:00:00	Chequeo médico	Programada	30
936	105	19	13	2026-10-26	09:00:00	Dolor de garganta	Programada	30
937	139	19	13	2026-10-26	10:00:00	Dolor de cabeza	Cancelada	30
938	48	19	13	2026-10-26	10:30:00	Dolor de oído	Programada	30
939	74	19	13	2026-10-26	11:00:00	Dolor de cabeza	Programada	30
940	66	20	13	2026-10-26	15:00:00	Dolor muscular	Programada	30
941	156	1	1	2026-10-27	08:00:00	Mareo	Programada	30
942	26	1	1	2026-10-27	10:00:00	Control general	Programada	30
943	96	2	1	2026-10-27	15:30:00	Dolor de oído	Programada	30
944	214	5	2	2026-10-27	14:00:00	Control general	Cancelada	30
945	39	5	2	2026-10-27	16:30:00	Dolor de cabeza	Programada	30
946	29	5	2	2026-10-27	17:00:00	Gripe	Programada	30
947	51	10	3	2026-10-27	14:30:00	Dolor de cabeza	Programada	30
948	188	10	3	2026-10-27	16:30:00	Dolor de oído	Programada	30
949	134	11	7	2026-10-27	08:30:00	Dolor de oído	Programada	30
950	188	11	7	2026-10-27	09:00:00	Fiebre	Programada	30
951	18	12	7	2026-10-27	14:00:00	Alergia en la piel	Programada	30
952	123	12	7	2026-10-27	14:30:00	Dolor lumbar	Programada	30
953	111	12	7	2026-10-27	15:30:00	Fiebre	Programada	30
954	1	13	8	2026-10-27	10:00:00	Control de presión arterial	Programada	30
955	53	13	8	2026-10-27	10:30:00	Dolor de garganta	Programada	30
956	3	13	8	2026-10-27	11:00:00	Alergia en la piel	Programada	30
957	133	14	8	2026-10-27	15:00:00	Dolor lumbar	Programada	30
958	136	14	8	2026-10-27	16:00:00	Alergia en la piel	Programada	30
959	138	14	8	2026-10-27	16:30:00	Dolor muscular	Programada	30
960	99	15	9	2026-10-27	08:30:00	Malestar general	Programada	30
961	81	17	10	2026-10-27	10:30:00	Gripe	Programada	30
962	44	17	10	2026-10-27	11:00:00	Mareo	Programada	30
963	150	18	10	2026-10-27	15:00:00	Fiebre	Programada	30
964	198	19	13	2026-10-27	09:30:00	Chequeo médico	Programada	30
965	139	19	13	2026-10-27	10:30:00	Alergia en la piel	Programada	30
966	174	20	13	2026-10-27	14:00:00	Dolor lumbar	Programada	30
967	132	20	13	2026-10-27	15:00:00	Dolor de garganta	Programada	30
968	216	20	13	2026-10-27	17:30:00	Fiebre	Programada	30
969	12	1	1	2026-10-28	08:30:00	Náuseas y vómito	Programada	30
970	72	1	1	2026-10-28	10:00:00	Control de presión arterial	Programada	30
971	211	1	1	2026-10-28	11:00:00	Mareo	Programada	30
972	25	1	1	2026-10-28	11:30:00	Mareo	Programada	30
973	80	2	1	2026-10-28	15:00:00	Fiebre	Programada	30
974	192	9	3	2026-10-28	08:00:00	Tos persistente	Programada	30
975	108	9	3	2026-10-28	09:00:00	Alergia en la piel	Programada	30
976	71	9	3	2026-10-28	09:30:00	Dolor muscular	Programada	30
977	223	9	3	2026-10-28	11:00:00	Mareo	Programada	30
978	140	10	3	2026-10-28	14:00:00	Mareo	Programada	30
979	98	12	7	2026-10-28	16:00:00	Control de presión arterial	Programada	30
980	152	12	7	2026-10-28	16:30:00	Malestar general	Programada	30
981	55	12	7	2026-10-28	17:00:00	Control general	Programada	30
982	42	13	8	2026-10-28	08:30:00	Alergia en la piel	Programada	30
983	19	13	8	2026-10-28	10:30:00	Dolor de oído	Programada	30
984	224	14	8	2026-10-28	14:30:00	Alergia en la piel	Cancelada	30
985	48	14	8	2026-10-28	16:00:00	Dolor lumbar	Programada	30
986	100	15	9	2026-10-28	09:00:00	Mareo	Cancelada	30
987	220	15	9	2026-10-28	09:30:00	Control general	Programada	30
988	94	16	9	2026-10-28	15:00:00	Náuseas y vómito	Cancelada	30
989	170	16	9	2026-10-28	15:30:00	Malestar general	Programada	30
990	108	17	10	2026-10-28	09:00:00	Mareo	Programada	30
991	206	19	13	2026-10-28	08:30:00	Dolor abdominal	Programada	30
992	95	19	13	2026-10-28	11:30:00	Dolor lumbar	Cancelada	30
993	203	20	13	2026-10-28	17:00:00	Dolor lumbar	Programada	30
994	10	20	13	2026-10-28	17:30:00	Fiebre	Programada	30
995	91	2	1	2026-10-29	14:30:00	Mareo	Programada	30
996	98	2	1	2026-10-29	15:00:00	Dolor de garganta	Programada	30
997	117	2	1	2026-10-29	17:30:00	Náuseas y vómito	Programada	30
998	177	5	2	2026-10-29	15:00:00	Dolor abdominal	Programada	30
999	64	5	2	2026-10-29	15:30:00	Dolor de oído	Programada	30
1000	17	9	3	2026-10-29	08:00:00	Dolor de oído	Cancelada	30
1001	193	9	3	2026-10-29	09:30:00	Dolor abdominal	Programada	30
1002	26	9	3	2026-10-29	10:00:00	Fiebre	Programada	30
1003	49	9	3	2026-10-29	11:00:00	Náuseas y vómito	Programada	30
1004	191	10	3	2026-10-29	16:30:00	Chequeo médico	Programada	30
1005	201	10	3	2026-10-29	17:00:00	Dolor de cabeza	Programada	30
1006	38	11	7	2026-10-29	08:00:00	Chequeo médico	Programada	30
1007	112	12	7	2026-10-29	15:30:00	Dolor de cabeza	Programada	30
1008	178	13	8	2026-10-29	08:00:00	Control de diabetes	Programada	30
1009	104	13	8	2026-10-29	09:30:00	Gripe	Programada	30
1010	119	13	8	2026-10-29	10:00:00	Malestar general	Cancelada	30
1011	46	14	8	2026-10-29	17:00:00	Malestar general	Programada	30
1012	48	15	9	2026-10-29	08:00:00	Control de presión arterial	Programada	30
1013	68	15	9	2026-10-29	09:00:00	Náuseas y vómito	Programada	30
1014	47	17	10	2026-10-29	08:00:00	Dolor de cabeza	Programada	30
1015	192	18	10	2026-10-29	14:30:00	Mareo	Cancelada	30
1016	9	18	10	2026-10-29	15:00:00	Tos persistente	Programada	30
1017	25	18	10	2026-10-29	16:00:00	Malestar general	Programada	30
1018	21	19	13	2026-10-29	08:00:00	Dolor de garganta	Programada	30
1019	98	19	13	2026-10-29	08:30:00	Dolor lumbar	Programada	30
1020	180	19	13	2026-10-29	10:00:00	Dolor abdominal	Cancelada	30
1021	83	20	13	2026-10-29	15:30:00	Control de diabetes	Cancelada	30
1022	1	20	13	2026-10-29	17:00:00	Control de diabetes	Cancelada	30
1023	171	1	1	2026-10-30	09:30:00	Malestar general	Programada	30
1024	25	1	1	2026-10-30	11:00:00	Alergia en la piel	Programada	30
1025	68	2	1	2026-10-30	14:30:00	Tos persistente	Programada	30
1026	133	2	1	2026-10-30	17:30:00	Fiebre	Programada	30
1027	188	4	2	2026-10-30	09:30:00	Tos persistente	Programada	30
1028	79	5	2	2026-10-30	15:00:00	Náuseas y vómito	Programada	30
1029	87	5	2	2026-10-30	17:00:00	Dolor de oído	Programada	30
1030	115	5	2	2026-10-30	17:30:00	Malestar general	Programada	30
1031	159	9	3	2026-10-30	09:30:00	Dolor de cabeza	Programada	30
1032	15	10	3	2026-10-30	15:00:00	Control de diabetes	Cancelada	30
1033	205	10	3	2026-10-30	16:00:00	Control de presión arterial	Programada	30
1034	37	10	3	2026-10-30	17:00:00	Gripe	Programada	30
1035	208	10	3	2026-10-30	17:30:00	Dolor de oído	Programada	30
1036	92	11	7	2026-10-30	08:00:00	Náuseas y vómito	Programada	30
1037	100	12	7	2026-10-30	14:00:00	Fiebre	Programada	30
1038	66	12	7	2026-10-30	14:30:00	Dolor abdominal	Programada	30
1039	32	12	7	2026-10-30	16:30:00	Malestar general	Cancelada	30
1040	117	13	8	2026-10-30	09:30:00	Dolor de cabeza	Programada	30
1041	63	13	8	2026-10-30	10:00:00	Fiebre	Programada	30
1042	151	15	9	2026-10-30	11:00:00	Dolor lumbar	Programada	30
1043	87	17	10	2026-10-30	09:30:00	Mareo	Programada	30
1044	147	17	10	2026-10-30	11:00:00	Mareo	Programada	30
1045	191	18	10	2026-10-30	15:00:00	Mareo	Programada	30
1046	18	19	13	2026-10-30	09:30:00	Alergia en la piel	Programada	30
1047	88	19	13	2026-10-30	10:00:00	Control de diabetes	Programada	30
1048	161	20	13	2026-10-30	16:30:00	Control general	Programada	30
1049	124	20	13	2026-10-30	17:00:00	Dolor lumbar	Programada	30
1050	100	1	1	2026-11-02	08:30:00	Alergia en la piel	Programada	30
1051	218	2	1	2026-11-02	15:00:00	Alergia en la piel	Cancelada	30
1052	152	4	2	2026-11-02	08:00:00	Control de diabetes	Programada	30
1053	85	4	2	2026-11-02	08:30:00	Control general	Programada	30
1054	158	5	2	2026-11-02	15:00:00	Dolor lumbar	Programada	30
1055	183	5	2	2026-11-02	17:00:00	Fiebre	Programada	30
1056	49	9	3	2026-11-02	08:00:00	Fiebre	Programada	30
1057	187	9	3	2026-11-02	09:00:00	Control de diabetes	Programada	30
1058	123	9	3	2026-11-02	11:30:00	Náuseas y vómito	Cancelada	30
1059	128	10	3	2026-11-02	15:30:00	Control de presión arterial	Cancelada	30
1060	202	10	3	2026-11-02	16:30:00	Náuseas y vómito	Programada	30
1061	225	12	7	2026-11-02	17:30:00	Mareo	Programada	30
1062	136	13	8	2026-11-02	09:00:00	Gripe	Programada	30
1063	143	13	8	2026-11-02	10:30:00	Malestar general	Programada	30
1064	177	14	8	2026-11-02	14:30:00	Malestar general	Programada	30
1065	80	15	9	2026-11-02	11:00:00	Gripe	Programada	30
1066	22	15	9	2026-11-02	11:30:00	Dolor lumbar	Programada	30
1067	72	16	9	2026-11-02	14:00:00	Gripe	Programada	30
1068	43	16	9	2026-11-02	14:30:00	Alergia en la piel	Programada	30
1069	109	17	10	2026-11-02	10:00:00	Mareo	Programada	30
1070	118	17	10	2026-11-02	10:30:00	Dolor de oído	Programada	30
1071	82	18	10	2026-11-02	14:30:00	Dolor abdominal	Programada	30
1072	49	18	10	2026-11-02	16:30:00	Dolor lumbar	Programada	30
1073	203	19	13	2026-11-02	10:00:00	Dolor de cabeza	Programada	30
\.


--
-- TOC entry 5508 (class 0 OID 17691)
-- Dependencies: 229
-- Data for Name: consultorio; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.consultorio (id_consultorio, numero, piso, disponible) FROM stdin;
1	101	1	t
2	102	1	t
3	201	2	t
4	202	2	f
7	103	1	t
8	104	1	t
9	105	1	t
10	106	1	t
13	203	2	t
14	204	2	t
15	301	3	t
16	302	3	t
\.


--
-- TOC entry 5500 (class 0 OID 17624)
-- Dependencies: 221
-- Data for Name: eps; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.eps (id_eps, nombre) FROM stdin;
1	Nueva EPS
2	Sanitas
3	Sura
4	Coosalud
5	Asmet Salud
11	Emssanar
12	Salud Total
13	Famisanar
14	Compensar
15	Mutual Ser
\.


--
-- TOC entry 5504 (class 0 OID 17655)
-- Dependencies: 225
-- Data for Name: especialidad; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.especialidad (id_especialidad, nombre) FROM stdin;
1	Medicina General
2	Pediatría
3	Cardiología
4	Dermatología
5	Ortopedia
6	Neurología
7	Ginecología
\.


--
-- TOC entry 5517 (class 0 OID 17796)
-- Dependencies: 238
-- Data for Name: factura; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.factura (id_factura, id_cita, valor_servicios, valor_medicamentos, metodo_pago, estado, fecha_emision, fecha_pago) FROM stdin;
2	2	45000.00	0.00	Efectivo	Pendiente	2026-10-19 08:20:20.822208-05	\N
1	1	60000.00	4500.00	Tarjeta	Pagada	2026-10-19 08:20:20.822208-05	2026-10-19 08:20:20.822208-05
253	312	145000.00	0.00	Tarjeta	Pagada	2026-09-21 17:30:00-05	2026-09-21 17:40:00-05
642	802	55000.00	11700.00	Transferencia	Pagada	2026-10-19 08:23:56.760768-05	2026-10-19 08:23:56.760768-05
3	9	55000.00	9600.00	Transferencia	Pagada	2026-09-04 09:00:00-05	2026-09-04 09:10:00-05
4	10	75000.00	20100.00	Transferencia	Pagada	2026-09-04 10:30:00-05	2026-09-04 10:40:00-05
5	11	55000.00	19400.00	Tarjeta	Pagada	2026-09-04 11:00:00-05	2026-09-04 11:10:00-05
6	12	75000.00	24500.00	Efectivo	Pendiente	2026-09-04 11:30:00-05	\N
7	13	67000.00	17100.00	Efectivo	Pagada	2026-09-04 09:00:00-05	2026-09-04 09:10:00-05
8	14	115000.00	5950.00	Tarjeta	Pagada	2026-09-04 10:30:00-05	2026-09-04 10:40:00-05
9	15	90000.00	3900.00	Tarjeta	Pagada	2026-09-04 11:00:00-05	2026-09-04 11:10:00-05
10	16	75000.00	0.00	Transferencia	Pagada	2026-09-04 11:30:00-05	2026-09-04 11:40:00-05
11	17	55000.00	0.00	Transferencia	Pagada	2026-09-04 08:30:00-05	2026-09-04 08:40:00-05
12	18	75000.00	3300.00	Efectivo	Pagada	2026-09-04 11:00:00-05	2026-09-04 11:10:00-05
13	20	55000.00	0.00	Transferencia	Pagada	2026-09-04 15:00:00-05	2026-09-04 15:10:00-05
14	21	55000.00	7700.00	Transferencia	Pagada	2026-09-04 17:30:00-05	2026-09-04 17:40:00-05
15	22	55000.00	0.00	Efectivo	Pendiente	2026-09-04 14:30:00-05	\N
16	23	55000.00	20000.00	Efectivo	Pagada	2026-09-04 16:30:00-05	2026-09-04 16:40:00-05
17	24	75000.00	12300.00	Transferencia	Pagada	2026-09-04 17:00:00-05	2026-09-04 17:10:00-05
18	25	75000.00	9600.00	Tarjeta	Pagada	2026-09-04 09:00:00-05	2026-09-04 09:10:00-05
19	26	75000.00	3600.00	Tarjeta	Pagada	2026-09-04 10:00:00-05	2026-09-04 10:10:00-05
20	27	145000.00	13500.00	Transferencia	Pendiente	2026-09-04 11:00:00-05	\N
21	28	90000.00	19500.00	Transferencia	Pagada	2026-09-04 14:30:00-05	2026-09-04 14:40:00-05
22	29	90000.00	5400.00	Tarjeta	Pendiente	2026-09-04 15:30:00-05	\N
23	30	67000.00	12150.00	Tarjeta	Pagada	2026-09-04 17:00:00-05	2026-09-04 17:10:00-05
24	31	55000.00	16000.00	Efectivo	Pagada	2026-09-04 18:00:00-05	2026-09-04 18:10:00-05
25	32	55000.00	0.00	Tarjeta	Pendiente	2026-09-04 08:30:00-05	\N
26	33	115000.00	12300.00	Efectivo	Pagada	2026-09-04 10:30:00-05	2026-09-04 10:40:00-05
27	35	75000.00	27500.00	Tarjeta	Pagada	2026-09-04 15:30:00-05	2026-09-04 15:40:00-05
28	36	90000.00	0.00	Efectivo	Pagada	2026-09-04 16:00:00-05	2026-09-04 16:10:00-05
29	43	55000.00	0.00	Transferencia	Pagada	2026-09-04 16:00:00-05	2026-09-04 16:10:00-05
30	45	145000.00	1800.00	Efectivo	Pagada	2026-09-04 10:30:00-05	2026-09-04 10:40:00-05
31	46	55000.00	0.00	Efectivo	Pagada	2026-09-04 16:30:00-05	2026-09-04 16:40:00-05
32	47	75000.00	7500.00	Tarjeta	Pagada	2026-09-04 17:30:00-05	2026-09-04 17:40:00-05
33	48	55000.00	3600.00	Tarjeta	Pagada	2026-09-07 08:30:00-05	2026-09-07 08:40:00-05
34	50	55000.00	0.00	Transferencia	Pagada	2026-09-07 11:30:00-05	2026-09-07 11:40:00-05
35	51	55000.00	5500.00	Tarjeta	Pagada	2026-09-07 15:30:00-05	2026-09-07 15:40:00-05
36	52	115000.00	0.00	Efectivo	Pendiente	2026-09-07 09:00:00-05	\N
37	53	55000.00	0.00	Efectivo	Pagada	2026-09-07 11:30:00-05	2026-09-07 11:40:00-05
38	54	75000.00	10500.00	Transferencia	Pendiente	2026-09-07 15:30:00-05	\N
39	55	67000.00	9900.00	Transferencia	Pagada	2026-09-07 16:00:00-05	2026-09-07 16:10:00-05
40	57	67000.00	13800.00	Transferencia	Pagada	2026-09-07 12:00:00-05	2026-09-07 12:10:00-05
41	58	55000.00	1800.00	Efectivo	Pagada	2026-09-07 10:00:00-05	2026-09-07 10:10:00-05
42	59	145000.00	22050.00	Transferencia	Pendiente	2026-09-07 08:30:00-05	\N
43	61	115000.00	0.00	Transferencia	Pagada	2026-09-07 18:00:00-05	2026-09-07 18:10:00-05
44	62	75000.00	1500.00	Transferencia	Pagada	2026-09-07 10:00:00-05	2026-09-07 10:10:00-05
45	64	55000.00	10100.00	Transferencia	Pagada	2026-09-07 15:00:00-05	2026-09-07 15:10:00-05
46	65	55000.00	0.00	Transferencia	Pagada	2026-09-07 15:30:00-05	2026-09-07 15:40:00-05
47	66	90000.00	20600.00	Efectivo	Pagada	2026-09-07 16:30:00-05	2026-09-07 16:40:00-05
48	68	115000.00	0.00	Efectivo	Pagada	2026-09-07 09:00:00-05	2026-09-07 09:10:00-05
49	70	67000.00	0.00	Transferencia	Pagada	2026-09-07 17:00:00-05	2026-09-07 17:10:00-05
50	72	55000.00	0.00	Efectivo	Pagada	2026-09-08 16:00:00-05	2026-09-08 16:10:00-05
51	74	115000.00	2400.00	Efectivo	Pagada	2026-09-08 09:30:00-05	2026-09-08 09:40:00-05
52	75	90000.00	0.00	Efectivo	Pagada	2026-09-08 11:00:00-05	2026-09-08 11:10:00-05
53	76	55000.00	27300.00	Tarjeta	Pagada	2026-09-08 14:30:00-05	2026-09-08 14:40:00-05
54	77	55000.00	0.00	Tarjeta	Pagada	2026-09-08 11:00:00-05	2026-09-08 11:10:00-05
55	78	75000.00	0.00	Efectivo	Pagada	2026-09-08 11:30:00-05	2026-09-08 11:40:00-05
56	79	55000.00	5200.00	Tarjeta	Pagada	2026-09-08 15:30:00-05	2026-09-08 15:40:00-05
57	80	55000.00	18000.00	Transferencia	Pagada	2026-09-08 16:30:00-05	2026-09-08 16:40:00-05
58	81	115000.00	0.00	Transferencia	Pagada	2026-09-08 08:30:00-05	2026-09-08 08:40:00-05
59	82	75000.00	14400.00	Efectivo	Pagada	2026-09-08 15:00:00-05	2026-09-08 15:10:00-05
60	83	90000.00	9900.00	Tarjeta	Pagada	2026-09-08 16:00:00-05	2026-09-08 16:10:00-05
61	84	67000.00	7500.00	Tarjeta	Pagada	2026-09-08 09:00:00-05	2026-09-08 09:10:00-05
62	85	75000.00	11000.00	Efectivo	Pagada	2026-09-08 12:00:00-05	2026-09-08 12:10:00-05
63	86	115000.00	0.00	Efectivo	Pagada	2026-09-08 14:30:00-05	2026-09-08 14:40:00-05
64	87	55000.00	0.00	Tarjeta	Pagada	2026-09-08 14:30:00-05	2026-09-08 14:40:00-05
65	88	115000.00	0.00	Tarjeta	Pagada	2026-09-08 15:00:00-05	2026-09-08 15:10:00-05
66	90	90000.00	0.00	Efectivo	Pagada	2026-09-08 11:30:00-05	2026-09-08 11:40:00-05
67	91	67000.00	19300.00	Tarjeta	Pagada	2026-09-08 16:00:00-05	2026-09-08 16:10:00-05
68	92	90000.00	9500.00	Tarjeta	Pagada	2026-09-08 18:00:00-05	2026-09-08 18:10:00-05
69	93	75000.00	0.00	Tarjeta	Pagada	2026-09-08 09:30:00-05	2026-09-08 09:40:00-05
70	94	67000.00	12300.00	Tarjeta	Pagada	2026-09-08 10:00:00-05	2026-09-08 10:10:00-05
71	95	115000.00	14100.00	Tarjeta	Pagada	2026-09-08 10:30:00-05	2026-09-08 10:40:00-05
72	96	55000.00	7250.00	Efectivo	Pagada	2026-09-08 15:00:00-05	2026-09-08 15:10:00-05
73	97	67000.00	3150.00	Tarjeta	Pagada	2026-09-08 17:00:00-05	2026-09-08 17:10:00-05
74	98	55000.00	12900.00	Transferencia	Pagada	2026-09-09 09:00:00-05	2026-09-09 09:10:00-05
75	99	55000.00	0.00	Efectivo	Pagada	2026-09-09 10:30:00-05	2026-09-09 10:40:00-05
76	101	67000.00	5550.00	Transferencia	Pagada	2026-09-09 16:00:00-05	2026-09-09 16:10:00-05
77	102	55000.00	0.00	Efectivo	Pagada	2026-09-09 18:00:00-05	2026-09-09 18:10:00-05
78	103	75000.00	4650.00	Tarjeta	Pagada	2026-09-09 08:30:00-05	2026-09-09 08:40:00-05
79	104	55000.00	3600.00	Tarjeta	Pagada	2026-09-09 12:00:00-05	2026-09-09 12:10:00-05
80	106	90000.00	11750.00	Tarjeta	Pagada	2026-09-09 15:30:00-05	2026-09-09 15:40:00-05
81	107	75000.00	5350.00	Tarjeta	Pagada	2026-09-09 09:30:00-05	2026-09-09 09:40:00-05
82	108	90000.00	0.00	Efectivo	Pagada	2026-09-09 11:30:00-05	2026-09-09 11:40:00-05
83	110	55000.00	900.00	Transferencia	Pagada	2026-09-09 09:00:00-05	2026-09-09 09:10:00-05
84	111	55000.00	2100.00	Transferencia	Pagada	2026-09-09 12:00:00-05	2026-09-09 12:10:00-05
85	112	55000.00	10950.00	Efectivo	Pagada	2026-09-09 17:30:00-05	2026-09-09 17:40:00-05
86	113	75000.00	10800.00	Tarjeta	Pendiente	2026-09-09 11:30:00-05	\N
87	114	55000.00	9000.00	Tarjeta	Pagada	2026-09-09 15:00:00-05	2026-09-09 15:10:00-05
88	115	55000.00	0.00	Efectivo	Pagada	2026-09-09 17:00:00-05	2026-09-09 17:10:00-05
89	116	75000.00	15000.00	Efectivo	Pendiente	2026-09-09 17:30:00-05	\N
90	117	67000.00	0.00	Transferencia	Pagada	2026-09-09 10:30:00-05	2026-09-09 10:40:00-05
91	119	67000.00	2850.00	Transferencia	Pagada	2026-09-09 15:00:00-05	2026-09-09 15:10:00-05
92	120	55000.00	0.00	Transferencia	Pagada	2026-09-09 10:00:00-05	2026-09-09 10:10:00-05
93	121	55000.00	7700.00	Transferencia	Pagada	2026-09-09 16:30:00-05	2026-09-09 16:40:00-05
94	122	67000.00	0.00	Efectivo	Pagada	2026-09-10 10:00:00-05	2026-09-10 10:10:00-05
95	123	55000.00	23600.00	Efectivo	Pagada	2026-09-10 14:30:00-05	2026-09-10 14:40:00-05
96	124	115000.00	12600.00	Efectivo	Pendiente	2026-09-10 17:30:00-05	\N
97	125	115000.00	7500.00	Efectivo	Pagada	2026-09-10 14:30:00-05	2026-09-10 14:40:00-05
98	126	90000.00	3600.00	Transferencia	Pagada	2026-09-10 15:00:00-05	2026-09-10 15:10:00-05
99	127	75000.00	1500.00	Efectivo	Pagada	2026-09-10 16:30:00-05	2026-09-10 16:40:00-05
100	128	55000.00	1800.00	Tarjeta	Pagada	2026-09-10 17:30:00-05	2026-09-10 17:40:00-05
101	129	145000.00	7350.00	Tarjeta	Pagada	2026-09-10 11:30:00-05	2026-09-10 11:40:00-05
102	130	75000.00	4200.00	Efectivo	Pagada	2026-09-10 15:00:00-05	2026-09-10 15:10:00-05
103	132	55000.00	15600.00	Efectivo	Pagada	2026-09-10 15:30:00-05	2026-09-10 15:40:00-05
104	133	75000.00	13500.00	Transferencia	Pagada	2026-09-10 16:00:00-05	2026-09-10 16:10:00-05
105	134	115000.00	0.00	Tarjeta	Pendiente	2026-09-10 16:30:00-05	\N
106	136	145000.00	16800.00	Transferencia	Pendiente	2026-09-10 10:00:00-05	\N
107	137	55000.00	6500.00	Efectivo	Pagada	2026-09-10 10:30:00-05	2026-09-10 10:40:00-05
108	138	55000.00	9600.00	Efectivo	Pagada	2026-09-10 12:00:00-05	2026-09-10 12:10:00-05
109	139	115000.00	7950.00	Transferencia	Pagada	2026-09-10 14:30:00-05	2026-09-10 14:40:00-05
110	140	75000.00	1200.00	Tarjeta	Pagada	2026-09-10 15:30:00-05	2026-09-10 15:40:00-05
111	141	55000.00	0.00	Transferencia	Pagada	2026-09-10 16:00:00-05	2026-09-10 16:10:00-05
112	142	55000.00	21600.00	Tarjeta	Pendiente	2026-09-10 16:30:00-05	\N
113	143	55000.00	2100.00	Tarjeta	Pagada	2026-09-10 10:30:00-05	2026-09-10 10:40:00-05
114	144	115000.00	25500.00	Tarjeta	Pendiente	2026-09-10 11:00:00-05	\N
115	145	67000.00	12500.00	Efectivo	Pagada	2026-09-10 08:30:00-05	2026-09-10 08:40:00-05
116	146	90000.00	0.00	Transferencia	Pendiente	2026-09-10 09:00:00-05	\N
117	147	75000.00	1500.00	Transferencia	Pagada	2026-09-10 09:30:00-05	2026-09-10 09:40:00-05
118	148	115000.00	9600.00	Tarjeta	Pagada	2026-09-10 10:00:00-05	2026-09-10 10:10:00-05
119	149	90000.00	4500.00	Transferencia	Pagada	2026-09-10 10:30:00-05	2026-09-10 10:40:00-05
120	150	75000.00	5400.00	Tarjeta	Pagada	2026-09-10 11:00:00-05	2026-09-10 11:10:00-05
121	151	115000.00	0.00	Efectivo	Pagada	2026-09-10 12:00:00-05	2026-09-10 12:10:00-05
122	152	55000.00	38000.00	Transferencia	Pagada	2026-09-11 11:00:00-05	2026-09-11 11:10:00-05
123	153	55000.00	12900.00	Transferencia	Pagada	2026-09-11 11:30:00-05	2026-09-11 11:40:00-05
124	155	90000.00	15000.00	Tarjeta	Pagada	2026-09-11 18:00:00-05	2026-09-11 18:10:00-05
125	156	67000.00	9800.00	Transferencia	Pagada	2026-09-11 09:30:00-05	2026-09-11 09:40:00-05
126	158	75000.00	11400.00	Transferencia	Pagada	2026-09-11 18:00:00-05	2026-09-11 18:10:00-05
127	159	90000.00	2700.00	Efectivo	Pagada	2026-09-11 10:30:00-05	2026-09-11 10:40:00-05
128	160	55000.00	1350.00	Tarjeta	Pagada	2026-09-11 08:30:00-05	2026-09-11 08:40:00-05
129	161	115000.00	46250.00	Transferencia	Pagada	2026-09-11 18:00:00-05	2026-09-11 18:10:00-05
130	162	145000.00	9300.00	Tarjeta	Pagada	2026-09-11 10:00:00-05	2026-09-11 10:10:00-05
131	163	67000.00	5400.00	Transferencia	Pagada	2026-09-11 10:30:00-05	2026-09-11 10:40:00-05
132	165	75000.00	1500.00	Transferencia	Pagada	2026-09-11 12:00:00-05	2026-09-11 12:10:00-05
133	167	115000.00	1800.00	Transferencia	Pagada	2026-09-11 15:30:00-05	2026-09-11 15:40:00-05
134	168	145000.00	2100.00	Tarjeta	Pagada	2026-09-11 18:00:00-05	2026-09-11 18:10:00-05
135	169	90000.00	8700.00	Transferencia	Pagada	2026-09-11 09:00:00-05	2026-09-11 09:10:00-05
136	170	90000.00	5100.00	Transferencia	Pagada	2026-09-11 10:00:00-05	2026-09-11 10:10:00-05
137	171	115000.00	11700.00	Transferencia	Pagada	2026-09-11 08:30:00-05	2026-09-11 08:40:00-05
138	172	115000.00	17400.00	Transferencia	Pagada	2026-09-11 10:30:00-05	2026-09-11 10:40:00-05
139	173	55000.00	6600.00	Tarjeta	Pagada	2026-09-11 11:00:00-05	2026-09-11 11:10:00-05
140	174	145000.00	10550.00	Tarjeta	Pagada	2026-09-14 09:30:00-05	2026-09-14 09:40:00-05
141	175	115000.00	14000.00	Transferencia	Pagada	2026-09-14 11:00:00-05	2026-09-14 11:10:00-05
142	176	55000.00	42000.00	Transferencia	Pagada	2026-09-14 15:30:00-05	2026-09-14 15:40:00-05
143	177	90000.00	7500.00	Transferencia	Pagada	2026-09-14 17:30:00-05	2026-09-14 17:40:00-05
144	178	67000.00	0.00	Efectivo	Pagada	2026-09-14 08:30:00-05	2026-09-14 08:40:00-05
145	179	145000.00	23000.00	Tarjeta	Pagada	2026-09-14 09:00:00-05	2026-09-14 09:10:00-05
146	181	75000.00	0.00	Tarjeta	Pagada	2026-09-14 10:30:00-05	2026-09-14 10:40:00-05
147	185	55000.00	1200.00	Tarjeta	Pagada	2026-09-14 10:30:00-05	2026-09-14 10:40:00-05
148	186	75000.00	6100.00	Transferencia	Pagada	2026-09-14 14:30:00-05	2026-09-14 14:40:00-05
149	189	145000.00	2700.00	Transferencia	Pagada	2026-09-14 17:30:00-05	2026-09-14 17:40:00-05
150	190	67000.00	1200.00	Tarjeta	Pagada	2026-09-14 09:00:00-05	2026-09-14 09:10:00-05
151	191	75000.00	10250.00	Efectivo	Pagada	2026-09-14 15:30:00-05	2026-09-14 15:40:00-05
152	192	55000.00	10500.00	Efectivo	Pagada	2026-09-14 16:00:00-05	2026-09-14 16:10:00-05
153	193	75000.00	9000.00	Efectivo	Pagada	2026-09-14 08:30:00-05	2026-09-14 08:40:00-05
154	194	55000.00	18700.00	Efectivo	Pagada	2026-09-14 17:00:00-05	2026-09-14 17:10:00-05
155	195	115000.00	6300.00	Tarjeta	Pagada	2026-09-14 08:30:00-05	2026-09-14 08:40:00-05
156	196	145000.00	3900.00	Transferencia	Pendiente	2026-09-14 12:00:00-05	\N
157	197	55000.00	4200.00	Transferencia	Pagada	2026-09-14 16:30:00-05	2026-09-14 16:40:00-05
158	198	90000.00	9950.00	Tarjeta	Pagada	2026-09-15 08:30:00-05	2026-09-15 08:40:00-05
159	199	55000.00	14000.00	Transferencia	Pagada	2026-09-15 09:00:00-05	2026-09-15 09:10:00-05
160	200	55000.00	18500.00	Efectivo	Pagada	2026-09-15 10:30:00-05	2026-09-15 10:40:00-05
161	202	90000.00	0.00	Efectivo	Pendiente	2026-09-15 15:00:00-05	\N
162	203	67000.00	750.00	Transferencia	Pagada	2026-09-15 16:30:00-05	2026-09-15 16:40:00-05
163	204	115000.00	7500.00	Tarjeta	Pendiente	2026-09-15 10:00:00-05	\N
164	205	55000.00	0.00	Transferencia	Pagada	2026-09-15 14:30:00-05	2026-09-15 14:40:00-05
165	206	145000.00	0.00	Efectivo	Pagada	2026-09-15 15:00:00-05	2026-09-15 15:10:00-05
166	207	145000.00	11750.00	Efectivo	Pagada	2026-09-15 16:30:00-05	2026-09-15 16:40:00-05
167	208	75000.00	0.00	Tarjeta	Pagada	2026-09-15 17:30:00-05	2026-09-15 17:40:00-05
168	209	90000.00	1800.00	Tarjeta	Pagada	2026-09-15 09:00:00-05	2026-09-15 09:10:00-05
169	210	115000.00	0.00	Efectivo	Pagada	2026-09-15 10:00:00-05	2026-09-15 10:10:00-05
170	211	145000.00	9500.00	Tarjeta	Pagada	2026-09-15 11:00:00-05	2026-09-15 11:10:00-05
171	212	115000.00	0.00	Efectivo	Pendiente	2026-09-15 14:30:00-05	\N
172	213	55000.00	18000.00	Efectivo	Pendiente	2026-09-15 17:00:00-05	\N
173	215	55000.00	5700.00	Tarjeta	Pagada	2026-09-15 17:00:00-05	2026-09-15 17:10:00-05
174	216	55000.00	3000.00	Efectivo	Pagada	2026-09-15 09:00:00-05	2026-09-15 09:10:00-05
175	217	115000.00	0.00	Tarjeta	Pagada	2026-09-15 10:30:00-05	2026-09-15 10:40:00-05
176	218	55000.00	15500.00	Tarjeta	Pagada	2026-09-15 11:30:00-05	2026-09-15 11:40:00-05
177	220	75000.00	0.00	Tarjeta	Pendiente	2026-09-15 15:00:00-05	\N
178	222	55000.00	3150.00	Transferencia	Pagada	2026-09-15 10:30:00-05	2026-09-15 10:40:00-05
179	223	145000.00	4500.00	Efectivo	Pagada	2026-09-15 17:30:00-05	2026-09-15 17:40:00-05
180	224	75000.00	12900.00	Tarjeta	Pagada	2026-09-15 08:30:00-05	2026-09-15 08:40:00-05
181	225	75000.00	12650.00	Transferencia	Pagada	2026-09-15 09:30:00-05	2026-09-15 09:40:00-05
182	226	75000.00	6500.00	Tarjeta	Pagada	2026-09-15 10:00:00-05	2026-09-15 10:10:00-05
183	228	75000.00	11150.00	Tarjeta	Pagada	2026-09-15 18:00:00-05	2026-09-15 18:10:00-05
184	230	55000.00	10500.00	Transferencia	Pagada	2026-09-16 16:00:00-05	2026-09-16 16:10:00-05
185	231	55000.00	27200.00	Tarjeta	Pagada	2026-09-16 14:30:00-05	2026-09-16 14:40:00-05
186	232	90000.00	0.00	Transferencia	Pagada	2026-09-16 09:00:00-05	2026-09-16 09:10:00-05
187	233	145000.00	16000.00	Tarjeta	Pendiente	2026-09-16 10:00:00-05	\N
188	234	55000.00	0.00	Transferencia	Pendiente	2026-09-16 15:00:00-05	\N
189	235	145000.00	6600.00	Transferencia	Pagada	2026-09-16 15:30:00-05	2026-09-16 15:40:00-05
190	236	75000.00	10600.00	Efectivo	Pagada	2026-09-16 18:00:00-05	2026-09-16 18:10:00-05
191	237	145000.00	13500.00	Tarjeta	Pagada	2026-09-16 11:00:00-05	2026-09-16 11:10:00-05
192	238	55000.00	1200.00	Efectivo	Pendiente	2026-09-16 17:30:00-05	\N
193	239	90000.00	8400.00	Tarjeta	Pagada	2026-09-16 10:30:00-05	2026-09-16 10:40:00-05
194	240	55000.00	8400.00	Transferencia	Pagada	2026-09-16 14:30:00-05	2026-09-16 14:40:00-05
195	241	67000.00	1500.00	Tarjeta	Pagada	2026-09-16 16:00:00-05	2026-09-16 16:10:00-05
196	242	90000.00	11300.00	Transferencia	Pagada	2026-09-16 16:30:00-05	2026-09-16 16:40:00-05
197	243	115000.00	3900.00	Tarjeta	Pagada	2026-09-16 17:00:00-05	2026-09-16 17:10:00-05
198	245	90000.00	7200.00	Tarjeta	Pagada	2026-09-16 16:00:00-05	2026-09-16 16:10:00-05
199	246	75000.00	0.00	Tarjeta	Pagada	2026-09-16 08:30:00-05	2026-09-16 08:40:00-05
200	247	55000.00	12450.00	Transferencia	Pendiente	2026-09-16 16:30:00-05	\N
201	248	55000.00	0.00	Efectivo	Pagada	2026-09-16 17:30:00-05	2026-09-16 17:40:00-05
202	250	145000.00	1500.00	Tarjeta	Pagada	2026-09-17 11:30:00-05	2026-09-17 11:40:00-05
203	251	90000.00	7500.00	Efectivo	Pagada	2026-09-17 12:00:00-05	2026-09-17 12:10:00-05
204	252	145000.00	4500.00	Efectivo	Pagada	2026-09-17 14:30:00-05	2026-09-17 14:40:00-05
205	253	115000.00	5100.00	Tarjeta	Pagada	2026-09-17 16:00:00-05	2026-09-17 16:10:00-05
206	254	55000.00	17800.00	Efectivo	Pagada	2026-09-17 17:00:00-05	2026-09-17 17:10:00-05
207	255	55000.00	6600.00	Tarjeta	Pagada	2026-09-17 08:30:00-05	2026-09-17 08:40:00-05
208	256	145000.00	4050.00	Efectivo	Pagada	2026-09-17 11:00:00-05	2026-09-17 11:10:00-05
209	257	115000.00	0.00	Tarjeta	Pendiente	2026-09-17 15:00:00-05	\N
210	258	55000.00	4500.00	Transferencia	Pagada	2026-09-17 09:30:00-05	2026-09-17 09:40:00-05
211	259	75000.00	12000.00	Tarjeta	Pendiente	2026-09-17 10:30:00-05	\N
212	260	55000.00	8700.00	Transferencia	Pagada	2026-09-17 11:30:00-05	2026-09-17 11:40:00-05
213	262	67000.00	0.00	Tarjeta	Pendiente	2026-09-17 18:00:00-05	\N
214	264	90000.00	0.00	Efectivo	Pagada	2026-09-17 16:30:00-05	2026-09-17 16:40:00-05
215	266	115000.00	17900.00	Efectivo	Pagada	2026-09-17 11:00:00-05	2026-09-17 11:10:00-05
216	268	145000.00	0.00	Tarjeta	Pagada	2026-09-17 12:00:00-05	2026-09-17 12:10:00-05
217	269	115000.00	12900.00	Transferencia	Pagada	2026-09-17 16:30:00-05	2026-09-17 16:40:00-05
218	270	75000.00	9300.00	Transferencia	Pagada	2026-09-17 17:00:00-05	2026-09-17 17:10:00-05
219	271	75000.00	0.00	Transferencia	Pendiente	2026-09-17 15:30:00-05	\N
220	272	55000.00	1500.00	Efectivo	Pagada	2026-09-17 16:00:00-05	2026-09-17 16:10:00-05
221	273	115000.00	21000.00	Transferencia	Pendiente	2026-09-17 17:00:00-05	\N
222	274	75000.00	0.00	Efectivo	Pendiente	2026-09-17 08:30:00-05	\N
223	275	55000.00	4050.00	Efectivo	Pagada	2026-09-17 11:00:00-05	2026-09-17 11:10:00-05
224	276	90000.00	20600.00	Transferencia	Pagada	2026-09-17 15:00:00-05	2026-09-17 15:10:00-05
225	278	55000.00	12900.00	Efectivo	Pagada	2026-09-18 10:00:00-05	2026-09-18 10:10:00-05
226	279	115000.00	9500.00	Transferencia	Pendiente	2026-09-18 10:30:00-05	\N
227	280	115000.00	46100.00	Tarjeta	Pagada	2026-09-18 14:30:00-05	2026-09-18 14:40:00-05
228	281	145000.00	17100.00	Efectivo	Pagada	2026-09-18 16:00:00-05	2026-09-18 16:10:00-05
229	282	75000.00	3300.00	Tarjeta	Pendiente	2026-09-18 11:30:00-05	\N
230	283	55000.00	4350.00	Transferencia	Pendiente	2026-09-18 15:00:00-05	\N
231	284	55000.00	5400.00	Efectivo	Pagada	2026-09-18 16:00:00-05	2026-09-18 16:10:00-05
232	285	55000.00	3900.00	Efectivo	Pagada	2026-09-18 16:30:00-05	2026-09-18 16:40:00-05
233	286	115000.00	8000.00	Transferencia	Pagada	2026-09-18 17:30:00-05	2026-09-18 17:40:00-05
234	287	55000.00	0.00	Tarjeta	Pendiente	2026-09-18 10:30:00-05	\N
235	289	67000.00	9000.00	Transferencia	Pendiente	2026-09-18 17:30:00-05	\N
236	290	115000.00	9600.00	Transferencia	Pagada	2026-09-18 11:00:00-05	2026-09-18 11:10:00-05
237	291	115000.00	17900.00	Tarjeta	Pendiente	2026-09-18 16:00:00-05	\N
238	292	55000.00	4500.00	Transferencia	Pagada	2026-09-18 11:30:00-05	2026-09-18 11:40:00-05
239	293	145000.00	23200.00	Efectivo	Pagada	2026-09-18 14:30:00-05	2026-09-18 14:40:00-05
240	294	55000.00	1650.00	Transferencia	Pagada	2026-09-18 15:00:00-05	2026-09-18 15:10:00-05
241	295	55000.00	17100.00	Tarjeta	Pagada	2026-09-18 16:30:00-05	2026-09-18 16:40:00-05
242	297	115000.00	0.00	Efectivo	Pagada	2026-09-18 15:30:00-05	2026-09-18 15:40:00-05
243	298	115000.00	10400.00	Transferencia	Pagada	2026-09-18 09:30:00-05	2026-09-18 09:40:00-05
244	301	75000.00	0.00	Transferencia	Pagada	2026-09-18 14:30:00-05	2026-09-18 14:40:00-05
245	302	67000.00	7500.00	Efectivo	Pagada	2026-09-18 16:00:00-05	2026-09-18 16:10:00-05
246	303	75000.00	2700.00	Transferencia	Pagada	2026-09-18 16:30:00-05	2026-09-18 16:40:00-05
247	305	115000.00	3150.00	Tarjeta	Pagada	2026-09-21 14:30:00-05	2026-09-21 14:40:00-05
248	306	145000.00	0.00	Efectivo	Pagada	2026-09-21 15:00:00-05	2026-09-21 15:10:00-05
249	308	67000.00	15600.00	Tarjeta	Pagada	2026-09-21 10:00:00-05	2026-09-21 10:10:00-05
250	309	115000.00	3700.00	Tarjeta	Pagada	2026-09-21 12:00:00-05	2026-09-21 12:10:00-05
251	310	90000.00	0.00	Transferencia	Pagada	2026-09-21 15:00:00-05	2026-09-21 15:10:00-05
252	311	55000.00	10000.00	Transferencia	Pagada	2026-09-21 16:30:00-05	2026-09-21 16:40:00-05
254	313	55000.00	0.00	Efectivo	Pagada	2026-09-21 08:30:00-05	2026-09-21 08:40:00-05
255	315	75000.00	1200.00	Efectivo	Pagada	2026-09-21 15:30:00-05	2026-09-21 15:40:00-05
256	318	67000.00	8000.00	Tarjeta	Pagada	2026-09-21 17:00:00-05	2026-09-21 17:10:00-05
257	320	90000.00	0.00	Efectivo	Pagada	2026-09-21 16:00:00-05	2026-09-21 16:10:00-05
258	321	55000.00	0.00	Tarjeta	Pagada	2026-09-21 08:30:00-05	2026-09-21 08:40:00-05
259	322	55000.00	0.00	Transferencia	Pagada	2026-09-21 16:00:00-05	2026-09-21 16:10:00-05
260	323	55000.00	0.00	Transferencia	Pagada	2026-09-21 17:00:00-05	2026-09-21 17:10:00-05
261	325	67000.00	12300.00	Tarjeta	Pagada	2026-09-21 12:00:00-05	2026-09-21 12:10:00-05
262	326	75000.00	12800.00	Tarjeta	Pagada	2026-09-21 10:30:00-05	2026-09-21 10:40:00-05
263	327	145000.00	17000.00	Transferencia	Pendiente	2026-09-22 09:00:00-05	\N
264	328	67000.00	8250.00	Transferencia	Pagada	2026-09-22 09:30:00-05	2026-09-22 09:40:00-05
265	329	115000.00	5400.00	Transferencia	Pagada	2026-09-22 11:30:00-05	2026-09-22 11:40:00-05
266	330	75000.00	0.00	Transferencia	Pagada	2026-09-22 12:00:00-05	2026-09-22 12:10:00-05
267	331	75000.00	0.00	Efectivo	Pagada	2026-09-22 12:00:00-05	2026-09-22 12:10:00-05
268	333	115000.00	0.00	Efectivo	Pendiente	2026-09-22 17:30:00-05	\N
269	334	115000.00	2500.00	Efectivo	Pagada	2026-09-22 10:00:00-05	2026-09-22 10:10:00-05
270	335	55000.00	0.00	Efectivo	Pagada	2026-09-22 10:30:00-05	2026-09-22 10:40:00-05
271	338	55000.00	0.00	Transferencia	Pagada	2026-09-22 11:30:00-05	2026-09-22 11:40:00-05
272	340	55000.00	3000.00	Tarjeta	Pagada	2026-09-22 08:30:00-05	2026-09-22 08:40:00-05
273	341	55000.00	6150.00	Tarjeta	Pagada	2026-09-22 11:30:00-05	2026-09-22 11:40:00-05
274	342	67000.00	4900.00	Efectivo	Pagada	2026-09-22 15:30:00-05	2026-09-22 15:40:00-05
275	343	115000.00	0.00	Transferencia	Pagada	2026-09-22 16:30:00-05	2026-09-22 16:40:00-05
276	344	75000.00	1800.00	Efectivo	Pagada	2026-09-22 17:00:00-05	2026-09-22 17:10:00-05
277	345	75000.00	11900.00	Tarjeta	Pagada	2026-09-22 17:30:00-05	2026-09-22 17:40:00-05
278	347	55000.00	14700.00	Efectivo	Pagada	2026-09-22 11:30:00-05	2026-09-22 11:40:00-05
279	348	55000.00	6300.00	Efectivo	Pendiente	2026-09-22 15:00:00-05	\N
280	349	55000.00	6900.00	Transferencia	Pagada	2026-09-22 08:30:00-05	2026-09-22 08:40:00-05
281	352	90000.00	0.00	Tarjeta	Pendiente	2026-09-22 10:30:00-05	\N
282	354	90000.00	51400.00	Tarjeta	Pagada	2026-09-22 12:00:00-05	2026-09-22 12:10:00-05
283	355	55000.00	11400.00	Efectivo	Pagada	2026-09-23 10:30:00-05	2026-09-23 10:40:00-05
284	356	75000.00	15900.00	Transferencia	Pendiente	2026-09-23 14:30:00-05	\N
285	357	75000.00	1050.00	Transferencia	Pagada	2026-09-23 18:00:00-05	2026-09-23 18:10:00-05
286	358	55000.00	3600.00	Efectivo	Pendiente	2026-09-23 16:30:00-05	\N
287	359	55000.00	0.00	Transferencia	Pagada	2026-09-23 17:30:00-05	2026-09-23 17:40:00-05
288	360	55000.00	41000.00	Tarjeta	Pagada	2026-09-23 18:00:00-05	2026-09-23 18:10:00-05
289	361	67000.00	0.00	Transferencia	Pagada	2026-09-23 10:00:00-05	2026-09-23 10:10:00-05
290	362	55000.00	3450.00	Tarjeta	Pagada	2026-09-23 12:00:00-05	2026-09-23 12:10:00-05
291	363	55000.00	18000.00	Tarjeta	Pagada	2026-09-23 18:00:00-05	2026-09-23 18:10:00-05
292	364	67000.00	2700.00	Tarjeta	Pendiente	2026-09-23 11:30:00-05	\N
293	365	115000.00	21500.00	Transferencia	Pagada	2026-09-23 14:30:00-05	2026-09-23 14:40:00-05
294	367	75000.00	11100.00	Tarjeta	Pendiente	2026-09-23 08:30:00-05	\N
295	368	55000.00	3900.00	Tarjeta	Pagada	2026-09-23 10:00:00-05	2026-09-23 10:10:00-05
296	369	55000.00	6600.00	Tarjeta	Pendiente	2026-09-23 11:00:00-05	\N
297	370	115000.00	4900.00	Efectivo	Pagada	2026-09-23 11:30:00-05	2026-09-23 11:40:00-05
298	371	55000.00	11000.00	Transferencia	Pagada	2026-09-23 14:30:00-05	2026-09-23 14:40:00-05
299	372	90000.00	26500.00	Tarjeta	Pagada	2026-09-23 15:00:00-05	2026-09-23 15:10:00-05
300	373	67000.00	0.00	Tarjeta	Pagada	2026-09-23 15:30:00-05	2026-09-23 15:40:00-05
301	374	55000.00	23600.00	Tarjeta	Pagada	2026-09-23 11:30:00-05	2026-09-23 11:40:00-05
302	375	75000.00	7650.00	Tarjeta	Pendiente	2026-09-23 10:30:00-05	\N
303	376	90000.00	15500.00	Transferencia	Pagada	2026-09-23 11:30:00-05	2026-09-23 11:40:00-05
304	377	55000.00	3450.00	Transferencia	Pendiente	2026-09-23 17:00:00-05	\N
305	378	55000.00	7500.00	Tarjeta	Pagada	2026-09-23 17:30:00-05	2026-09-23 17:40:00-05
306	379	115000.00	11000.00	Tarjeta	Pagada	2026-09-24 16:00:00-05	2026-09-24 16:10:00-05
307	381	90000.00	14100.00	Efectivo	Pagada	2026-09-24 17:30:00-05	2026-09-24 17:40:00-05
308	383	67000.00	0.00	Tarjeta	Pagada	2026-09-24 11:30:00-05	2026-09-24 11:40:00-05
309	384	55000.00	0.00	Tarjeta	Pagada	2026-09-24 17:00:00-05	2026-09-24 17:10:00-05
310	385	145000.00	0.00	Tarjeta	Pagada	2026-09-24 18:00:00-05	2026-09-24 18:10:00-05
311	386	55000.00	20900.00	Transferencia	Pagada	2026-09-24 08:30:00-05	2026-09-24 08:40:00-05
312	387	115000.00	11000.00	Efectivo	Pagada	2026-09-24 09:00:00-05	2026-09-24 09:10:00-05
313	388	67000.00	24300.00	Efectivo	Pagada	2026-09-24 17:00:00-05	2026-09-24 17:10:00-05
314	389	67000.00	16700.00	Tarjeta	Pagada	2026-09-24 08:30:00-05	2026-09-24 08:40:00-05
315	390	55000.00	43100.00	Tarjeta	Pagada	2026-09-24 09:30:00-05	2026-09-24 09:40:00-05
316	391	55000.00	0.00	Efectivo	Pagada	2026-09-24 10:30:00-05	2026-09-24 10:40:00-05
317	392	115000.00	16500.00	Transferencia	Pagada	2026-09-24 16:30:00-05	2026-09-24 16:40:00-05
318	393	75000.00	14100.00	Transferencia	Pagada	2026-09-24 09:30:00-05	2026-09-24 09:40:00-05
319	394	75000.00	17600.00	Tarjeta	Pagada	2026-09-24 11:00:00-05	2026-09-24 11:10:00-05
320	395	55000.00	49300.00	Tarjeta	Pagada	2026-09-24 14:30:00-05	2026-09-24 14:40:00-05
321	396	55000.00	0.00	Tarjeta	Pagada	2026-09-24 16:30:00-05	2026-09-24 16:40:00-05
322	397	115000.00	11000.00	Efectivo	Pendiente	2026-09-25 09:00:00-05	\N
323	398	55000.00	49700.00	Transferencia	Pagada	2026-09-25 17:00:00-05	2026-09-25 17:10:00-05
324	399	145000.00	2100.00	Tarjeta	Pagada	2026-09-25 08:30:00-05	2026-09-25 08:40:00-05
325	400	75000.00	15300.00	Tarjeta	Pagada	2026-09-25 10:00:00-05	2026-09-25 10:10:00-05
326	401	145000.00	27500.00	Transferencia	Pagada	2026-09-25 15:30:00-05	2026-09-25 15:40:00-05
327	402	75000.00	11100.00	Transferencia	Pagada	2026-09-25 16:30:00-05	2026-09-25 16:40:00-05
328	403	55000.00	9900.00	Tarjeta	Pagada	2026-09-25 08:30:00-05	2026-09-25 08:40:00-05
329	404	55000.00	1500.00	Efectivo	Pagada	2026-09-25 09:00:00-05	2026-09-25 09:10:00-05
330	405	67000.00	1800.00	Transferencia	Pagada	2026-09-25 15:30:00-05	2026-09-25 15:40:00-05
331	406	90000.00	6900.00	Transferencia	Pagada	2026-09-25 17:30:00-05	2026-09-25 17:40:00-05
332	407	55000.00	19400.00	Transferencia	Pagada	2026-09-25 09:30:00-05	2026-09-25 09:40:00-05
333	408	55000.00	0.00	Efectivo	Pagada	2026-09-25 10:30:00-05	2026-09-25 10:40:00-05
334	410	55000.00	9500.00	Efectivo	Pendiente	2026-09-25 09:00:00-05	\N
335	411	75000.00	13400.00	Transferencia	Pendiente	2026-09-25 16:00:00-05	\N
336	413	67000.00	750.00	Efectivo	Pagada	2026-09-25 18:00:00-05	2026-09-25 18:10:00-05
337	415	75000.00	0.00	Tarjeta	Pagada	2026-09-25 12:00:00-05	2026-09-25 12:10:00-05
338	417	55000.00	5700.00	Transferencia	Pagada	2026-09-25 08:30:00-05	2026-09-25 08:40:00-05
339	419	55000.00	9300.00	Transferencia	Pagada	2026-09-25 12:00:00-05	2026-09-25 12:10:00-05
340	420	55000.00	9900.00	Tarjeta	Pagada	2026-09-25 15:00:00-05	2026-09-25 15:10:00-05
341	421	90000.00	4000.00	Tarjeta	Pagada	2026-09-25 15:30:00-05	2026-09-25 15:40:00-05
342	422	90000.00	4500.00	Tarjeta	Pendiente	2026-09-25 16:30:00-05	\N
343	423	55000.00	11750.00	Efectivo	Pagada	2026-09-25 08:30:00-05	2026-09-25 08:40:00-05
344	425	115000.00	0.00	Transferencia	Pagada	2026-09-25 12:00:00-05	2026-09-25 12:10:00-05
345	429	55000.00	52100.00	Tarjeta	Pagada	2026-09-28 15:30:00-05	2026-09-28 15:40:00-05
346	430	75000.00	17900.00	Tarjeta	Pagada	2026-09-28 17:00:00-05	2026-09-28 17:10:00-05
347	431	90000.00	0.00	Transferencia	Pagada	2026-09-28 18:00:00-05	2026-09-28 18:10:00-05
348	432	145000.00	16100.00	Transferencia	Pagada	2026-09-28 11:00:00-05	2026-09-28 11:10:00-05
349	433	75000.00	1500.00	Tarjeta	Pagada	2026-09-28 12:00:00-05	2026-09-28 12:10:00-05
350	434	90000.00	7500.00	Tarjeta	Pendiente	2026-09-28 14:30:00-05	\N
351	435	55000.00	27500.00	Tarjeta	Pagada	2026-09-28 15:30:00-05	2026-09-28 15:40:00-05
352	436	115000.00	0.00	Efectivo	Pagada	2026-09-28 17:00:00-05	2026-09-28 17:10:00-05
353	437	90000.00	13250.00	Efectivo	Pagada	2026-09-28 08:30:00-05	2026-09-28 08:40:00-05
354	438	55000.00	6600.00	Transferencia	Pagada	2026-09-28 10:00:00-05	2026-09-28 10:10:00-05
355	439	67000.00	0.00	Transferencia	Pendiente	2026-09-28 17:00:00-05	\N
356	440	90000.00	9150.00	Efectivo	Pagada	2026-09-28 17:30:00-05	2026-09-28 17:40:00-05
357	441	55000.00	18000.00	Tarjeta	Pagada	2026-09-28 14:30:00-05	2026-09-28 14:40:00-05
358	442	55000.00	0.00	Efectivo	Pagada	2026-09-28 15:30:00-05	2026-09-28 15:40:00-05
359	443	75000.00	7950.00	Transferencia	Pagada	2026-09-28 16:00:00-05	2026-09-28 16:10:00-05
360	445	115000.00	0.00	Tarjeta	Pagada	2026-09-28 11:00:00-05	2026-09-28 11:10:00-05
361	446	55000.00	25900.00	Efectivo	Pagada	2026-09-28 16:00:00-05	2026-09-28 16:10:00-05
362	448	67000.00	3900.00	Efectivo	Pagada	2026-09-28 10:00:00-05	2026-09-28 10:10:00-05
363	449	55000.00	6300.00	Efectivo	Pagada	2026-09-28 11:00:00-05	2026-09-28 11:10:00-05
364	450	75000.00	3900.00	Efectivo	Pagada	2026-09-28 11:30:00-05	2026-09-28 11:40:00-05
365	451	67000.00	1650.00	Tarjeta	Pagada	2026-09-28 12:00:00-05	2026-09-28 12:10:00-05
366	452	75000.00	2250.00	Efectivo	Pagada	2026-09-29 09:30:00-05	2026-09-29 09:40:00-05
367	453	67000.00	11750.00	Efectivo	Pagada	2026-09-29 10:00:00-05	2026-09-29 10:10:00-05
368	454	67000.00	0.00	Efectivo	Pagada	2026-09-29 11:00:00-05	2026-09-29 11:10:00-05
369	455	67000.00	0.00	Transferencia	Pagada	2026-09-29 11:30:00-05	2026-09-29 11:40:00-05
370	456	67000.00	8250.00	Transferencia	Pendiente	2026-09-29 15:00:00-05	\N
371	457	55000.00	0.00	Efectivo	Pagada	2026-09-29 08:30:00-05	2026-09-29 08:40:00-05
372	458	55000.00	6600.00	Tarjeta	Pagada	2026-09-29 11:00:00-05	2026-09-29 11:10:00-05
373	459	115000.00	20400.00	Transferencia	Pagada	2026-09-29 15:00:00-05	2026-09-29 15:10:00-05
374	460	55000.00	0.00	Tarjeta	Pagada	2026-09-29 17:00:00-05	2026-09-29 17:10:00-05
375	461	115000.00	6500.00	Efectivo	Pagada	2026-09-29 18:00:00-05	2026-09-29 18:10:00-05
376	462	115000.00	3900.00	Transferencia	Pagada	2026-09-29 18:00:00-05	2026-09-29 18:10:00-05
377	463	55000.00	2400.00	Tarjeta	Pagada	2026-09-29 09:30:00-05	2026-09-29 09:40:00-05
378	464	55000.00	9900.00	Tarjeta	Pendiente	2026-09-29 10:00:00-05	\N
379	465	145000.00	0.00	Tarjeta	Pagada	2026-09-29 14:30:00-05	2026-09-29 14:40:00-05
380	466	90000.00	0.00	Tarjeta	Pagada	2026-09-29 14:30:00-05	2026-09-29 14:40:00-05
381	467	55000.00	0.00	Transferencia	Pagada	2026-09-29 16:30:00-05	2026-09-29 16:40:00-05
382	468	90000.00	21000.00	Efectivo	Pagada	2026-09-29 09:00:00-05	2026-09-29 09:10:00-05
383	469	145000.00	1050.00	Efectivo	Pagada	2026-09-29 09:30:00-05	2026-09-29 09:40:00-05
384	470	115000.00	2400.00	Efectivo	Pagada	2026-09-29 17:30:00-05	2026-09-29 17:40:00-05
385	471	55000.00	17500.00	Tarjeta	Pagada	2026-09-29 18:00:00-05	2026-09-29 18:10:00-05
386	472	90000.00	4200.00	Tarjeta	Pagada	2026-09-29 10:00:00-05	2026-09-29 10:10:00-05
387	473	145000.00	0.00	Tarjeta	Pagada	2026-09-29 11:00:00-05	2026-09-29 11:10:00-05
388	474	75000.00	13500.00	Transferencia	Pagada	2026-09-29 16:30:00-05	2026-09-29 16:40:00-05
389	475	67000.00	0.00	Transferencia	Pendiente	2026-09-29 08:30:00-05	\N
390	476	145000.00	7500.00	Efectivo	Pagada	2026-09-29 10:30:00-05	2026-09-29 10:40:00-05
391	477	67000.00	11100.00	Transferencia	Pagada	2026-09-29 11:00:00-05	2026-09-29 11:10:00-05
392	478	55000.00	0.00	Efectivo	Pagada	2026-09-29 16:30:00-05	2026-09-29 16:40:00-05
393	480	145000.00	4500.00	Transferencia	Pagada	2026-09-30 09:00:00-05	2026-09-30 09:10:00-05
394	481	55000.00	0.00	Tarjeta	Pagada	2026-09-30 11:00:00-05	2026-09-30 11:10:00-05
395	482	55000.00	8250.00	Tarjeta	Pagada	2026-09-30 12:00:00-05	2026-09-30 12:10:00-05
396	484	115000.00	0.00	Transferencia	Pagada	2026-09-30 17:30:00-05	2026-09-30 17:40:00-05
397	486	67000.00	22250.00	Efectivo	Pagada	2026-09-30 11:00:00-05	2026-09-30 11:10:00-05
398	487	67000.00	6600.00	Transferencia	Pagada	2026-09-30 16:30:00-05	2026-09-30 16:40:00-05
399	488	145000.00	2700.00	Tarjeta	Pendiente	2026-09-30 09:00:00-05	\N
400	489	55000.00	11400.00	Tarjeta	Pendiente	2026-09-30 16:00:00-05	\N
401	490	75000.00	0.00	Tarjeta	Pendiente	2026-09-30 17:00:00-05	\N
402	491	67000.00	2700.00	Tarjeta	Pagada	2026-09-30 18:00:00-05	2026-09-30 18:10:00-05
403	492	145000.00	0.00	Tarjeta	Pagada	2026-09-30 10:00:00-05	2026-09-30 10:10:00-05
404	493	115000.00	6900.00	Efectivo	Pagada	2026-09-30 16:00:00-05	2026-09-30 16:10:00-05
405	494	115000.00	7200.00	Tarjeta	Pagada	2026-09-30 17:00:00-05	2026-09-30 17:10:00-05
406	495	67000.00	4200.00	Tarjeta	Pendiente	2026-09-30 08:30:00-05	\N
407	497	90000.00	0.00	Tarjeta	Pagada	2026-09-30 10:30:00-05	2026-09-30 10:40:00-05
408	498	55000.00	10100.00	Tarjeta	Pagada	2026-09-30 15:00:00-05	2026-09-30 15:10:00-05
409	500	75000.00	42500.00	Efectivo	Pagada	2026-09-30 12:00:00-05	2026-09-30 12:10:00-05
410	503	75000.00	14000.00	Efectivo	Pagada	2026-09-30 16:00:00-05	2026-09-30 16:10:00-05
411	504	145000.00	7500.00	Efectivo	Pagada	2026-09-30 16:30:00-05	2026-09-30 16:40:00-05
412	505	55000.00	39800.00	Tarjeta	Pagada	2026-09-30 17:00:00-05	2026-09-30 17:10:00-05
413	507	75000.00	3300.00	Transferencia	Pendiente	2026-09-30 11:30:00-05	\N
414	508	55000.00	4650.00	Transferencia	Pagada	2026-09-30 15:00:00-05	2026-09-30 15:10:00-05
415	509	75000.00	29400.00	Efectivo	Pagada	2026-10-01 09:00:00-05	2026-10-01 09:10:00-05
416	510	145000.00	0.00	Tarjeta	Pendiente	2026-10-01 11:30:00-05	\N
417	512	75000.00	1500.00	Tarjeta	Pagada	2026-10-01 15:30:00-05	2026-10-01 15:40:00-05
418	514	75000.00	11000.00	Tarjeta	Pendiente	2026-10-01 09:30:00-05	\N
419	515	55000.00	17400.00	Efectivo	Pagada	2026-10-01 11:00:00-05	2026-10-01 11:10:00-05
420	519	55000.00	5100.00	Transferencia	Pagada	2026-10-01 11:30:00-05	2026-10-01 11:40:00-05
421	520	115000.00	5400.00	Efectivo	Pagada	2026-10-01 15:30:00-05	2026-10-01 15:40:00-05
422	521	90000.00	11000.00	Efectivo	Pagada	2026-10-01 16:00:00-05	2026-10-01 16:10:00-05
423	522	55000.00	4500.00	Transferencia	Pagada	2026-10-01 18:00:00-05	2026-10-01 18:10:00-05
424	523	67000.00	40850.00	Tarjeta	Pagada	2026-10-01 08:30:00-05	2026-10-01 08:40:00-05
425	525	145000.00	20700.00	Tarjeta	Pagada	2026-10-01 17:00:00-05	2026-10-01 17:10:00-05
426	526	55000.00	9500.00	Transferencia	Pagada	2026-10-01 09:00:00-05	2026-10-01 09:10:00-05
427	527	115000.00	0.00	Tarjeta	Pendiente	2026-10-01 11:00:00-05	\N
428	528	55000.00	7200.00	Tarjeta	Pagada	2026-10-01 11:30:00-05	2026-10-01 11:40:00-05
429	530	55000.00	0.00	Tarjeta	Pagada	2026-10-01 14:30:00-05	2026-10-01 14:40:00-05
430	531	67000.00	3750.00	Efectivo	Pagada	2026-10-01 16:00:00-05	2026-10-01 16:10:00-05
431	535	55000.00	8100.00	Efectivo	Pagada	2026-10-01 17:00:00-05	2026-10-01 17:10:00-05
432	536	55000.00	0.00	Efectivo	Pagada	2026-10-01 17:30:00-05	2026-10-01 17:40:00-05
433	537	67000.00	3300.00	Efectivo	Pagada	2026-10-02 09:00:00-05	2026-10-02 09:10:00-05
434	539	55000.00	0.00	Tarjeta	Pagada	2026-10-02 08:30:00-05	2026-10-02 08:40:00-05
435	540	115000.00	2500.00	Efectivo	Pagada	2026-10-02 11:30:00-05	2026-10-02 11:40:00-05
436	541	90000.00	8750.00	Efectivo	Pendiente	2026-10-02 17:00:00-05	\N
437	542	75000.00	3300.00	Efectivo	Pagada	2026-10-02 09:30:00-05	2026-10-02 09:40:00-05
438	544	145000.00	2400.00	Tarjeta	Pagada	2026-10-02 09:00:00-05	2026-10-02 09:10:00-05
439	545	75000.00	0.00	Transferencia	Pagada	2026-10-02 10:30:00-05	2026-10-02 10:40:00-05
440	546	145000.00	7500.00	Efectivo	Pagada	2026-10-02 15:00:00-05	2026-10-02 15:10:00-05
441	547	55000.00	9000.00	Efectivo	Pagada	2026-10-02 12:00:00-05	2026-10-02 12:10:00-05
442	548	67000.00	10200.00	Tarjeta	Pendiente	2026-10-02 15:30:00-05	\N
443	549	145000.00	10900.00	Transferencia	Pagada	2026-10-02 17:00:00-05	2026-10-02 17:10:00-05
444	550	145000.00	9000.00	Efectivo	Pagada	2026-10-02 12:00:00-05	2026-10-02 12:10:00-05
445	552	55000.00	13900.00	Efectivo	Pagada	2026-10-02 18:00:00-05	2026-10-02 18:10:00-05
446	553	145000.00	20300.00	Tarjeta	Pagada	2026-10-02 09:00:00-05	2026-10-02 09:10:00-05
447	554	75000.00	2700.00	Transferencia	Pagada	2026-10-02 15:30:00-05	2026-10-02 15:40:00-05
448	558	75000.00	11100.00	Tarjeta	Pendiente	2026-10-02 11:00:00-05	\N
449	559	55000.00	16800.00	Tarjeta	Pagada	2026-10-02 15:30:00-05	2026-10-02 15:40:00-05
450	560	115000.00	11000.00	Transferencia	Pagada	2026-10-02 17:00:00-05	2026-10-02 17:10:00-05
451	561	90000.00	19100.00	Transferencia	Pagada	2026-10-05 10:30:00-05	2026-10-05 10:40:00-05
452	562	55000.00	20400.00	Efectivo	Pagada	2026-10-05 14:30:00-05	2026-10-05 14:40:00-05
453	566	55000.00	3600.00	Efectivo	Pagada	2026-10-05 12:00:00-05	2026-10-05 12:10:00-05
454	567	115000.00	6900.00	Efectivo	Pagada	2026-10-05 15:00:00-05	2026-10-05 15:10:00-05
455	568	145000.00	0.00	Transferencia	Pagada	2026-10-05 16:00:00-05	2026-10-05 16:10:00-05
456	569	55000.00	11700.00	Efectivo	Pagada	2026-10-05 10:00:00-05	2026-10-05 10:10:00-05
457	570	90000.00	14100.00	Tarjeta	Pagada	2026-10-05 11:00:00-05	2026-10-05 11:10:00-05
458	571	55000.00	8100.00	Transferencia	Pendiente	2026-10-05 17:00:00-05	\N
459	572	145000.00	750.00	Tarjeta	Pagada	2026-10-05 09:00:00-05	2026-10-05 09:10:00-05
460	573	90000.00	3600.00	Efectivo	Pagada	2026-10-05 10:00:00-05	2026-10-05 10:10:00-05
461	574	55000.00	19700.00	Transferencia	Pagada	2026-10-05 11:00:00-05	2026-10-05 11:10:00-05
462	575	90000.00	0.00	Tarjeta	Pagada	2026-10-05 18:00:00-05	2026-10-05 18:10:00-05
463	576	55000.00	20400.00	Transferencia	Pagada	2026-10-05 12:00:00-05	2026-10-05 12:10:00-05
464	577	67000.00	7500.00	Efectivo	Pagada	2026-10-05 10:00:00-05	2026-10-05 10:10:00-05
465	578	75000.00	2850.00	Tarjeta	Pagada	2026-10-05 15:00:00-05	2026-10-05 15:10:00-05
466	579	55000.00	0.00	Tarjeta	Pagada	2026-10-05 15:30:00-05	2026-10-05 15:40:00-05
467	580	55000.00	23900.00	Efectivo	Pagada	2026-10-05 09:00:00-05	2026-10-05 09:10:00-05
468	581	90000.00	0.00	Tarjeta	Pagada	2026-10-05 11:00:00-05	2026-10-05 11:10:00-05
469	583	75000.00	4500.00	Efectivo	Pagada	2026-10-05 15:30:00-05	2026-10-05 15:40:00-05
470	585	55000.00	3000.00	Transferencia	Pagada	2026-10-06 08:30:00-05	2026-10-06 08:40:00-05
471	586	75000.00	8750.00	Tarjeta	Pendiente	2026-10-06 10:30:00-05	\N
472	587	55000.00	2100.00	Tarjeta	Pagada	2026-10-06 11:00:00-05	2026-10-06 11:10:00-05
473	588	55000.00	0.00	Efectivo	Pagada	2026-10-06 12:00:00-05	2026-10-06 12:10:00-05
474	589	90000.00	7850.00	Transferencia	Pagada	2026-10-06 17:00:00-05	2026-10-06 17:10:00-05
475	590	67000.00	13500.00	Efectivo	Pagada	2026-10-06 08:30:00-05	2026-10-06 08:40:00-05
476	592	55000.00	12500.00	Transferencia	Pendiente	2026-10-06 15:30:00-05	\N
477	594	90000.00	10500.00	Transferencia	Pendiente	2026-10-06 17:30:00-05	\N
478	596	115000.00	17300.00	Tarjeta	Pagada	2026-10-06 08:30:00-05	2026-10-06 08:40:00-05
479	597	75000.00	54200.00	Tarjeta	Pagada	2026-10-06 10:00:00-05	2026-10-06 10:10:00-05
480	598	145000.00	8400.00	Efectivo	Pagada	2026-10-06 15:30:00-05	2026-10-06 15:40:00-05
481	599	90000.00	18900.00	Tarjeta	Pagada	2026-10-06 17:00:00-05	2026-10-06 17:10:00-05
482	600	75000.00	1200.00	Transferencia	Pagada	2026-10-06 18:00:00-05	2026-10-06 18:10:00-05
483	601	115000.00	0.00	Tarjeta	Pagada	2026-10-06 09:30:00-05	2026-10-06 09:40:00-05
484	602	55000.00	40500.00	Efectivo	Pagada	2026-10-06 11:00:00-05	2026-10-06 11:10:00-05
485	603	115000.00	0.00	Efectivo	Pagada	2026-10-06 16:00:00-05	2026-10-06 16:10:00-05
486	605	90000.00	2700.00	Transferencia	Pagada	2026-10-07 15:30:00-05	2026-10-07 15:40:00-05
487	606	55000.00	0.00	Tarjeta	Pendiente	2026-10-07 16:30:00-05	\N
488	607	90000.00	15900.00	Efectivo	Pagada	2026-10-07 17:30:00-05	2026-10-07 17:40:00-05
489	608	145000.00	750.00	Efectivo	Pagada	2026-10-07 11:30:00-05	2026-10-07 11:40:00-05
490	609	55000.00	0.00	Efectivo	Pagada	2026-10-07 16:00:00-05	2026-10-07 16:10:00-05
491	610	55000.00	0.00	Transferencia	Pendiente	2026-10-07 17:00:00-05	\N
492	614	75000.00	13200.00	Tarjeta	Pagada	2026-10-07 17:30:00-05	2026-10-07 17:40:00-05
493	615	115000.00	0.00	Efectivo	Pagada	2026-10-07 09:30:00-05	2026-10-07 09:40:00-05
494	616	145000.00	12150.00	Tarjeta	Pagada	2026-10-07 17:00:00-05	2026-10-07 17:10:00-05
495	617	55000.00	46400.00	Tarjeta	Pendiente	2026-10-07 08:30:00-05	\N
496	618	55000.00	0.00	Efectivo	Pendiente	2026-10-07 16:30:00-05	\N
497	619	115000.00	3600.00	Transferencia	Pagada	2026-10-07 17:00:00-05	2026-10-07 17:10:00-05
498	623	55000.00	11000.00	Transferencia	Pagada	2026-10-07 12:00:00-05	2026-10-07 12:10:00-05
499	624	55000.00	12000.00	Tarjeta	Pagada	2026-10-07 14:30:00-05	2026-10-07 14:40:00-05
500	625	55000.00	9100.00	Efectivo	Pagada	2026-10-07 15:00:00-05	2026-10-07 15:10:00-05
501	626	67000.00	0.00	Tarjeta	Pagada	2026-10-08 09:00:00-05	2026-10-08 09:10:00-05
502	627	55000.00	2100.00	Transferencia	Pagada	2026-10-08 09:30:00-05	2026-10-08 09:40:00-05
503	628	75000.00	0.00	Efectivo	Pagada	2026-10-08 08:30:00-05	2026-10-08 08:40:00-05
504	629	145000.00	4200.00	Transferencia	Pagada	2026-10-08 09:00:00-05	2026-10-08 09:10:00-05
505	630	55000.00	18000.00	Efectivo	Pagada	2026-10-08 09:30:00-05	2026-10-08 09:40:00-05
506	631	55000.00	19200.00	Efectivo	Pagada	2026-10-08 11:00:00-05	2026-10-08 11:10:00-05
507	632	55000.00	8700.00	Transferencia	Pagada	2026-10-08 18:00:00-05	2026-10-08 18:10:00-05
508	633	75000.00	12800.00	Tarjeta	Pendiente	2026-10-08 12:00:00-05	\N
509	634	90000.00	11250.00	Tarjeta	Pagada	2026-10-08 17:30:00-05	2026-10-08 17:40:00-05
510	635	55000.00	0.00	Transferencia	Pagada	2026-10-08 18:00:00-05	2026-10-08 18:10:00-05
511	636	145000.00	0.00	Tarjeta	Pagada	2026-10-08 12:00:00-05	2026-10-08 12:10:00-05
512	637	75000.00	8400.00	Transferencia	Pendiente	2026-10-08 15:30:00-05	\N
513	638	145000.00	1500.00	Tarjeta	Pagada	2026-10-08 09:30:00-05	2026-10-08 09:40:00-05
514	639	55000.00	25000.00	Efectivo	Pagada	2026-10-08 15:00:00-05	2026-10-08 15:10:00-05
515	640	115000.00	5400.00	Transferencia	Pagada	2026-10-08 16:30:00-05	2026-10-08 16:40:00-05
516	641	55000.00	12300.00	Transferencia	Pagada	2026-10-08 17:30:00-05	2026-10-08 17:40:00-05
517	642	67000.00	4500.00	Transferencia	Pendiente	2026-10-08 09:30:00-05	\N
518	644	55000.00	0.00	Transferencia	Pagada	2026-10-08 18:00:00-05	2026-10-08 18:10:00-05
519	645	55000.00	11400.00	Efectivo	Pagada	2026-10-08 11:00:00-05	2026-10-08 11:10:00-05
520	646	115000.00	4500.00	Transferencia	Pagada	2026-10-08 15:30:00-05	2026-10-08 15:40:00-05
521	647	67000.00	9300.00	Efectivo	Pagada	2026-10-08 16:00:00-05	2026-10-08 16:10:00-05
522	648	55000.00	1200.00	Transferencia	Pagada	2026-10-09 17:30:00-05	2026-10-09 17:40:00-05
523	649	55000.00	0.00	Efectivo	Pagada	2026-10-09 11:30:00-05	2026-10-09 11:40:00-05
524	650	115000.00	0.00	Tarjeta	Pagada	2026-10-09 12:00:00-05	2026-10-09 12:10:00-05
525	651	115000.00	0.00	Transferencia	Pagada	2026-10-09 14:30:00-05	2026-10-09 14:40:00-05
526	652	67000.00	9300.00	Transferencia	Pagada	2026-10-09 16:00:00-05	2026-10-09 16:10:00-05
527	653	90000.00	11900.00	Efectivo	Pagada	2026-10-09 16:30:00-05	2026-10-09 16:40:00-05
528	654	55000.00	3750.00	Tarjeta	Pagada	2026-10-09 15:00:00-05	2026-10-09 15:10:00-05
529	655	145000.00	5700.00	Efectivo	Pagada	2026-10-09 09:00:00-05	2026-10-09 09:10:00-05
530	657	67000.00	0.00	Efectivo	Pagada	2026-10-09 10:00:00-05	2026-10-09 10:10:00-05
531	658	75000.00	4800.00	Transferencia	Pendiente	2026-10-09 10:30:00-05	\N
532	659	55000.00	0.00	Transferencia	Pagada	2026-10-09 12:00:00-05	2026-10-09 12:10:00-05
533	660	55000.00	0.00	Tarjeta	Pagada	2026-10-09 16:00:00-05	2026-10-09 16:10:00-05
534	661	115000.00	6600.00	Tarjeta	Pagada	2026-10-09 18:00:00-05	2026-10-09 18:10:00-05
535	662	75000.00	10050.00	Transferencia	Pagada	2026-10-09 14:30:00-05	2026-10-09 14:40:00-05
536	665	55000.00	3000.00	Transferencia	Pendiente	2026-10-09 11:00:00-05	\N
537	667	90000.00	11000.00	Transferencia	Pagada	2026-10-12 09:00:00-05	2026-10-12 09:10:00-05
538	670	55000.00	12000.00	Tarjeta	Pagada	2026-10-12 09:00:00-05	2026-10-12 09:10:00-05
539	671	145000.00	12000.00	Transferencia	Pagada	2026-10-12 09:30:00-05	2026-10-12 09:40:00-05
540	672	75000.00	11300.00	Transferencia	Pagada	2026-10-12 15:30:00-05	2026-10-12 15:40:00-05
541	673	67000.00	11000.00	Transferencia	Pagada	2026-10-12 09:30:00-05	2026-10-12 09:40:00-05
542	674	90000.00	0.00	Transferencia	Pagada	2026-10-12 15:00:00-05	2026-10-12 15:10:00-05
543	675	115000.00	16500.00	Transferencia	Pagada	2026-10-12 17:00:00-05	2026-10-12 17:10:00-05
544	677	55000.00	0.00	Efectivo	Pagada	2026-10-12 09:00:00-05	2026-10-12 09:10:00-05
545	679	55000.00	24500.00	Efectivo	Pagada	2026-10-12 10:00:00-05	2026-10-12 10:10:00-05
546	680	67000.00	16000.00	Transferencia	Pendiente	2026-10-12 11:00:00-05	\N
547	681	75000.00	0.00	Tarjeta	Pagada	2026-10-12 10:30:00-05	2026-10-12 10:40:00-05
548	682	55000.00	12000.00	Tarjeta	Pagada	2026-10-12 16:00:00-05	2026-10-12 16:10:00-05
549	683	55000.00	26000.00	Tarjeta	Pagada	2026-10-12 17:00:00-05	2026-10-12 17:10:00-05
550	684	145000.00	0.00	Transferencia	Pendiente	2026-10-12 17:30:00-05	\N
551	685	75000.00	10500.00	Transferencia	Pagada	2026-10-12 08:30:00-05	2026-10-12 08:40:00-05
552	687	75000.00	15500.00	Efectivo	Pagada	2026-10-12 11:30:00-05	2026-10-12 11:40:00-05
553	688	55000.00	8550.00	Tarjeta	Pagada	2026-10-12 12:00:00-05	2026-10-12 12:10:00-05
554	689	55000.00	2400.00	Tarjeta	Pagada	2026-10-12 18:00:00-05	2026-10-12 18:10:00-05
555	690	55000.00	12900.00	Transferencia	Pendiente	2026-10-13 09:00:00-05	\N
556	691	55000.00	0.00	Efectivo	Pagada	2026-10-13 11:00:00-05	2026-10-13 11:10:00-05
557	692	145000.00	1350.00	Tarjeta	Pagada	2026-10-13 16:00:00-05	2026-10-13 16:10:00-05
558	693	145000.00	0.00	Tarjeta	Pagada	2026-10-13 09:30:00-05	2026-10-13 09:40:00-05
559	694	75000.00	0.00	Efectivo	Pagada	2026-10-13 10:00:00-05	2026-10-13 10:10:00-05
560	695	75000.00	27500.00	Tarjeta	Pagada	2026-10-13 11:00:00-05	2026-10-13 11:10:00-05
561	696	75000.00	2850.00	Transferencia	Pagada	2026-10-13 11:30:00-05	2026-10-13 11:40:00-05
562	697	145000.00	0.00	Efectivo	Pagada	2026-10-13 12:00:00-05	2026-10-13 12:10:00-05
563	700	55000.00	2100.00	Transferencia	Pagada	2026-10-13 17:00:00-05	2026-10-13 17:10:00-05
564	701	55000.00	3000.00	Transferencia	Pagada	2026-10-13 14:30:00-05	2026-10-13 14:40:00-05
565	702	55000.00	12900.00	Efectivo	Pendiente	2026-10-13 09:00:00-05	\N
566	703	75000.00	18600.00	Transferencia	Pagada	2026-10-13 12:00:00-05	2026-10-13 12:10:00-05
567	704	90000.00	0.00	Efectivo	Pendiente	2026-10-13 15:00:00-05	\N
568	706	145000.00	25400.00	Efectivo	Pagada	2026-10-13 08:30:00-05	2026-10-13 08:40:00-05
569	707	55000.00	11400.00	Efectivo	Pendiente	2026-10-13 09:00:00-05	\N
570	708	90000.00	21200.00	Transferencia	Pagada	2026-10-13 10:30:00-05	2026-10-13 10:40:00-05
571	710	115000.00	6600.00	Transferencia	Pagada	2026-10-13 16:30:00-05	2026-10-13 16:40:00-05
572	711	145000.00	0.00	Transferencia	Pagada	2026-10-13 08:30:00-05	2026-10-13 08:40:00-05
573	713	145000.00	0.00	Tarjeta	Pagada	2026-10-13 14:30:00-05	2026-10-13 14:40:00-05
574	715	67000.00	9900.00	Efectivo	Pendiente	2026-10-13 15:00:00-05	\N
575	716	55000.00	33600.00	Tarjeta	Pagada	2026-10-13 15:30:00-05	2026-10-13 15:40:00-05
576	718	90000.00	15750.00	Transferencia	Pagada	2026-10-14 15:00:00-05	2026-10-14 15:10:00-05
577	719	75000.00	0.00	Efectivo	Pagada	2026-10-14 16:30:00-05	2026-10-14 16:40:00-05
578	720	67000.00	24100.00	Efectivo	Pagada	2026-10-14 18:00:00-05	2026-10-14 18:10:00-05
579	721	115000.00	9500.00	Transferencia	Pagada	2026-10-14 09:00:00-05	2026-10-14 09:10:00-05
580	723	145000.00	1500.00	Transferencia	Pendiente	2026-10-14 16:00:00-05	\N
581	724	115000.00	3900.00	Transferencia	Pagada	2026-10-14 10:30:00-05	2026-10-14 10:40:00-05
582	726	90000.00	3600.00	Transferencia	Pendiente	2026-10-14 16:00:00-05	\N
583	727	67000.00	14500.00	Efectivo	Pendiente	2026-10-14 09:00:00-05	\N
584	728	55000.00	4500.00	Tarjeta	Pagada	2026-10-14 10:00:00-05	2026-10-14 10:10:00-05
585	729	115000.00	0.00	Transferencia	Pagada	2026-10-14 14:30:00-05	2026-10-14 14:40:00-05
586	730	55000.00	7700.00	Tarjeta	Pagada	2026-10-14 16:30:00-05	2026-10-14 16:40:00-05
587	731	55000.00	0.00	Tarjeta	Pagada	2026-10-14 09:00:00-05	2026-10-14 09:10:00-05
588	732	115000.00	3300.00	Transferencia	Pagada	2026-10-14 16:00:00-05	2026-10-14 16:10:00-05
589	734	55000.00	0.00	Efectivo	Pagada	2026-10-14 15:30:00-05	2026-10-14 15:40:00-05
590	737	75000.00	0.00	Transferencia	Pendiente	2026-10-14 17:30:00-05	\N
591	738	55000.00	1350.00	Tarjeta	Pagada	2026-10-14 09:00:00-05	2026-10-14 09:10:00-05
592	739	115000.00	45200.00	Transferencia	Pagada	2026-10-14 15:30:00-05	2026-10-14 15:40:00-05
593	740	67000.00	0.00	Transferencia	Pendiente	2026-10-14 18:00:00-05	\N
594	742	55000.00	1200.00	Tarjeta	Pagada	2026-10-15 12:00:00-05	2026-10-15 12:10:00-05
595	743	90000.00	32100.00	Tarjeta	Pagada	2026-10-15 16:00:00-05	2026-10-15 16:10:00-05
596	744	55000.00	14400.00	Tarjeta	Pagada	2026-10-15 17:00:00-05	2026-10-15 17:10:00-05
597	745	145000.00	1200.00	Transferencia	Pagada	2026-10-15 17:30:00-05	2026-10-15 17:40:00-05
598	746	75000.00	0.00	Tarjeta	Pagada	2026-10-15 18:00:00-05	2026-10-15 18:10:00-05
599	747	90000.00	11900.00	Transferencia	Pagada	2026-10-15 08:30:00-05	2026-10-15 08:40:00-05
600	748	75000.00	0.00	Efectivo	Pagada	2026-10-15 09:00:00-05	2026-10-15 09:10:00-05
601	749	90000.00	12650.00	Tarjeta	Pagada	2026-10-15 10:00:00-05	2026-10-15 10:10:00-05
602	750	55000.00	4350.00	Transferencia	Pagada	2026-10-15 11:30:00-05	2026-10-15 11:40:00-05
603	751	67000.00	4500.00	Efectivo	Pagada	2026-10-15 15:30:00-05	2026-10-15 15:40:00-05
604	752	75000.00	6700.00	Efectivo	Pagada	2026-10-15 16:30:00-05	2026-10-15 16:40:00-05
605	753	145000.00	14000.00	Efectivo	Pagada	2026-10-15 18:00:00-05	2026-10-15 18:10:00-05
606	755	145000.00	2500.00	Tarjeta	Pagada	2026-10-15 11:00:00-05	2026-10-15 11:10:00-05
607	756	115000.00	7250.00	Transferencia	Pagada	2026-10-15 12:00:00-05	2026-10-15 12:10:00-05
608	758	145000.00	9000.00	Efectivo	Pagada	2026-10-15 17:00:00-05	2026-10-15 17:10:00-05
609	759	90000.00	12900.00	Tarjeta	Pagada	2026-10-15 09:00:00-05	2026-10-15 09:10:00-05
610	760	55000.00	0.00	Efectivo	Pagada	2026-10-15 10:00:00-05	2026-10-15 10:10:00-05
611	761	115000.00	12900.00	Efectivo	Pagada	2026-10-15 10:30:00-05	2026-10-15 10:40:00-05
612	763	55000.00	0.00	Transferencia	Pagada	2026-10-15 16:00:00-05	2026-10-15 16:10:00-05
613	765	75000.00	8300.00	Tarjeta	Pagada	2026-10-15 14:30:00-05	2026-10-15 14:40:00-05
614	766	55000.00	0.00	Tarjeta	Pagada	2026-10-15 15:30:00-05	2026-10-15 15:40:00-05
615	767	55000.00	3900.00	Efectivo	Pendiente	2026-10-15 10:30:00-05	\N
616	768	55000.00	0.00	Tarjeta	Pagada	2026-10-15 11:30:00-05	2026-10-15 11:40:00-05
617	769	90000.00	9000.00	Tarjeta	Pagada	2026-10-15 17:00:00-05	2026-10-15 17:10:00-05
618	770	115000.00	14850.00	Transferencia	Pendiente	2026-10-15 11:00:00-05	\N
619	771	90000.00	1350.00	Transferencia	Pagada	2026-10-15 15:00:00-05	2026-10-15 15:10:00-05
620	772	55000.00	12000.00	Tarjeta	Pendiente	2026-10-15 17:00:00-05	\N
621	773	115000.00	0.00	Tarjeta	Pagada	2026-10-15 18:00:00-05	2026-10-15 18:10:00-05
622	774	90000.00	0.00	Efectivo	Pagada	2026-10-16 08:30:00-05	2026-10-16 08:40:00-05
623	775	75000.00	0.00	Tarjeta	Pendiente	2026-10-16 10:00:00-05	\N
624	776	115000.00	7800.00	Tarjeta	Pagada	2026-10-16 15:30:00-05	2026-10-16 15:40:00-05
625	777	115000.00	0.00	Tarjeta	Pagada	2026-10-16 17:30:00-05	2026-10-16 17:40:00-05
626	778	67000.00	750.00	Tarjeta	Pagada	2026-10-16 09:30:00-05	2026-10-16 09:40:00-05
627	779	67000.00	0.00	Transferencia	Pagada	2026-10-16 10:30:00-05	2026-10-16 10:40:00-05
628	781	67000.00	0.00	Tarjeta	Pagada	2026-10-16 09:30:00-05	2026-10-16 09:40:00-05
629	782	75000.00	17600.00	Tarjeta	Pagada	2026-10-16 10:00:00-05	2026-10-16 10:10:00-05
630	783	55000.00	0.00	Tarjeta	Pagada	2026-10-16 14:30:00-05	2026-10-16 14:40:00-05
631	785	55000.00	0.00	Transferencia	Pagada	2026-10-16 09:30:00-05	2026-10-16 09:40:00-05
632	786	55000.00	3900.00	Tarjeta	Pagada	2026-10-16 12:00:00-05	2026-10-16 12:10:00-05
633	787	145000.00	1800.00	Tarjeta	Pagada	2026-10-16 17:30:00-05	2026-10-16 17:40:00-05
634	788	67000.00	27500.00	Efectivo	Pagada	2026-10-16 09:00:00-05	2026-10-16 09:10:00-05
635	789	115000.00	11000.00	Efectivo	Pagada	2026-10-16 17:30:00-05	2026-10-16 17:40:00-05
636	790	55000.00	0.00	Transferencia	Pagada	2026-10-16 18:00:00-05	2026-10-16 18:10:00-05
637	792	115000.00	3000.00	Efectivo	Pagada	2026-10-16 14:30:00-05	2026-10-16 14:40:00-05
638	794	55000.00	18600.00	Tarjeta	Pagada	2026-10-16 15:30:00-05	2026-10-16 15:40:00-05
639	795	90000.00	0.00	Efectivo	Pagada	2026-10-16 17:00:00-05	2026-10-16 17:10:00-05
640	796	55000.00	2400.00	Efectivo	Pagada	2026-10-16 09:30:00-05	2026-10-16 09:40:00-05
641	797	55000.00	10000.00	Tarjeta	Pagada	2026-10-16 17:00:00-05	2026-10-16 17:10:00-05
\.


--
-- TOC entry 5515 (class 0 OID 17771)
-- Dependencies: 236
-- Data for Name: formula_medica; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.formula_medica (id_historia, id_medicamento, dosis, frecuencia, duracion_dias, cantidad) FROM stdin;
1	1	500 mg	cada 8 horas	3	9
3	22	1 tableta	cada 24 horas	3	3
4	44	1 sobre	cada 24 horas	3	3
4	2	1 cápsula	cada 24 horas	3	3
4	45	5 ml	cada 24 horas	3	1
5	43	2 inhalaciones	cada 24 horas	3	1
5	12	1 tableta	cada 24 horas	3	3
5	2	1 cápsula	cada 24 horas	3	3
6	22	1 tableta	cada 24 horas	3	3
6	68	1 tableta	cada 24 horas	3	3
6	43	2 inhalaciones	cada 24 horas	3	1
7	8	1 tableta	cada 24 horas	3	3
7	18	1 tableta	cada 24 horas	3	3
7	25	1 tableta	cada 24 horas	3	3
8	56	1 tableta	cada 24 horas	3	3
8	40	1 tableta	cada 24 horas	3	3
8	29	Dosis indicada	cada 24 horas	3	1
9	21	1 tableta	cada 24 horas	3	3
12	5	1 tableta	cada 24 horas	3	3
12	57	1 tableta	cada 24 horas	3	3
14	57	1 tableta	cada 24 horas	3	3
14	72	Aplicar capa fina	cada 24 horas	3	1
16	45	5 ml	cada 24 horas	3	1
16	9	5 ml	cada 24 horas	3	1
16	1	1 tableta	cada 24 horas	3	3
17	12	1 tableta	cada 24 horas	3	3
17	70	1 tableta	cada 24 horas	3	3
17	45	5 ml	cada 24 horas	3	1
18	22	1 tableta	cada 24 horas	3	3
19	54	1 tableta	cada 24 horas	3	3
19	14	1 tableta	cada 24 horas	3	3
20	19	1 tableta	cada 24 horas	3	3
21	73	Aplicar capa fina	cada 24 horas	3	1
21	41	1 tableta	cada 24 horas	3	3
22	37	1 tableta	cada 24 horas	3	3
22	30	1 cápsula	cada 24 horas	3	3
22	23	1 cápsula	cada 24 horas	3	3
23	18	1 tableta	cada 24 horas	3	3
23	55	1 tableta	cada 24 horas	3	3
24	29	Dosis indicada	cada 24 horas	3	1
24	42	1 tableta	cada 24 horas	3	3
24	45	5 ml	cada 24 horas	3	1
26	8	1 tableta	cada 24 horas	3	3
26	51	Aplicar capa fina	cada 24 horas	3	1
26	48	Dosis indicada	cada 24 horas	3	1
27	9	5 ml	cada 24 horas	3	1
27	63	1 cápsula	cada 24 horas	3	3
27	6	5 ml	cada 24 horas	3	1
30	69	1 tableta	cada 24 horas	3	3
32	6	5 ml	cada 24 horas	3	1
33	2	1 cápsula	cada 24 horas	3	3
35	48	Dosis indicada	cada 24 horas	3	1
35	1	1 tableta	cada 24 horas	3	3
35	70	1 tableta	cada 24 horas	3	3
38	44	1 sobre	cada 24 horas	3	3
38	33	1 cápsula	cada 24 horas	3	3
38	30	1 cápsula	cada 24 horas	3	3
39	34	1 sobre	cada 24 horas	3	3
39	20	1 cápsula	cada 24 horas	3	3
40	22	1 tableta	cada 24 horas	3	3
40	23	1 cápsula	cada 24 horas	3	3
40	15	1 tableta	cada 24 horas	3	3
41	12	1 tableta	cada 24 horas	3	3
42	73	Aplicar capa fina	cada 24 horas	3	1
42	55	1 tableta	cada 24 horas	3	3
42	8	1 tableta	cada 24 horas	3	3
44	41	1 tableta	cada 24 horas	3	3
45	49	Aplicar capa fina	cada 24 horas	3	1
45	30	1 cápsula	cada 24 horas	3	3
45	68	1 tableta	cada 24 horas	3	3
47	11	1 tableta	cada 24 horas	3	3
47	28	1 cápsula	cada 24 horas	3	3
47	17	5 ml	cada 24 horas	3	1
51	25	1 tableta	cada 24 horas	3	3
53	63	1 cápsula	cada 24 horas	3	3
53	18	1 tableta	cada 24 horas	3	3
53	65	1 tableta	cada 24 horas	3	3
56	1	1 tableta	cada 24 horas	3	3
56	48	Dosis indicada	cada 24 horas	3	1
56	30	1 cápsula	cada 24 horas	3	3
57	73	Aplicar capa fina	cada 24 horas	3	1
59	63	1 cápsula	cada 24 horas	3	3
59	21	1 tableta	cada 24 horas	3	3
60	20	1 cápsula	cada 24 horas	3	3
60	71	Aplicar capa fina	cada 24 horas	3	1
60	54	1 tableta	cada 24 horas	3	3
61	34	1 sobre	cada 24 horas	3	3
61	24	1 tableta	cada 24 horas	3	3
62	11	1 tableta	cada 24 horas	3	3
62	49	Aplicar capa fina	cada 24 horas	3	1
67	47	1 tableta	cada 24 horas	3	3
67	39	5 ml	cada 24 horas	3	1
67	72	Aplicar capa fina	cada 24 horas	3	1
68	9	5 ml	cada 24 horas	3	1
70	22	1 tableta	cada 24 horas	3	3
70	36	1 tableta	cada 24 horas	3	3
70	37	1 tableta	cada 24 horas	3	3
71	52	1 tableta	cada 24 horas	3	3
71	55	1 tableta	cada 24 horas	3	3
71	13	Aplicar capa fina	cada 24 horas	3	1
72	72	Aplicar capa fina	cada 24 horas	3	1
72	61	1 tableta	cada 24 horas	3	3
73	25	1 tableta	cada 24 horas	3	3
73	55	1 tableta	cada 24 horas	3	3
74	6	5 ml	cada 24 horas	3	1
74	65	1 tableta	cada 24 horas	3	3
76	26	1 cápsula	cada 24 horas	3	3
76	57	1 tableta	cada 24 horas	3	3
76	61	1 tableta	cada 24 horas	3	3
78	26	1 cápsula	cada 24 horas	3	3
78	53	1 tableta	cada 24 horas	3	3
79	2	1 cápsula	cada 24 horas	3	3
80	61	1 tableta	cada 24 horas	3	3
80	9	5 ml	cada 24 horas	3	1
80	70	1 tableta	cada 24 horas	3	3
81	48	Dosis indicada	cada 24 horas	3	1
81	61	1 tableta	cada 24 horas	3	3
81	10	1 tableta	cada 24 horas	3	3
83	68	1 tableta	cada 24 horas	3	3
84	59	1 tableta	cada 24 horas	3	3
85	59	1 tableta	cada 24 horas	3	3
85	52	1 tableta	cada 24 horas	3	3
85	50	Aplicar capa fina	cada 24 horas	3	1
86	31	1 tableta	cada 24 horas	3	3
86	11	1 tableta	cada 24 horas	3	3
86	56	1 tableta	cada 24 horas	3	3
87	45	5 ml	cada 24 horas	3	1
89	44	1 sobre	cada 24 horas	3	3
89	46	1 tableta	cada 24 horas	3	3
91	10	1 tableta	cada 24 horas	3	3
91	58	1 tableta	cada 24 horas	3	3
93	36	1 tableta	cada 24 horas	3	3
93	72	Aplicar capa fina	cada 24 horas	3	1
95	17	5 ml	cada 24 horas	3	1
95	63	1 cápsula	cada 24 horas	3	3
95	59	1 tableta	cada 24 horas	3	3
96	66	1 tableta	cada 24 horas	3	3
96	18	1 tableta	cada 24 horas	3	3
97	50	Aplicar capa fina	cada 24 horas	3	1
98	68	1 tableta	cada 24 horas	3	3
98	32	1 tableta	cada 24 horas	3	3
99	41	1 tableta	cada 24 horas	3	3
100	33	1 cápsula	cada 24 horas	3	3
101	35	1 tableta	cada 24 horas	3	3
101	55	1 tableta	cada 24 horas	3	3
102	57	1 tableta	cada 24 horas	3	3
102	10	1 tableta	cada 24 horas	3	3
102	54	1 tableta	cada 24 horas	3	3
103	14	1 tableta	cada 24 horas	3	3
103	45	5 ml	cada 24 horas	3	1
103	21	1 tableta	cada 24 horas	3	3
104	19	1 tableta	cada 24 horas	3	3
106	18	1 tableta	cada 24 horas	3	3
106	31	1 tableta	cada 24 horas	3	3
107	51	Aplicar capa fina	cada 24 horas	3	1
108	59	1 tableta	cada 24 horas	3	3
108	64	1 tableta	cada 24 horas	3	3
109	35	1 tableta	cada 24 horas	3	3
109	67	1 tableta	cada 24 horas	3	3
109	55	1 tableta	cada 24 horas	3	3
110	66	1 tableta	cada 24 horas	3	3
112	13	Aplicar capa fina	cada 24 horas	3	1
112	22	1 tableta	cada 24 horas	3	3
113	5	1 tableta	cada 24 horas	3	3
114	64	1 tableta	cada 24 horas	3	3
114	73	Aplicar capa fina	cada 24 horas	3	1
115	49	Aplicar capa fina	cada 24 horas	3	1
115	42	1 tableta	cada 24 horas	3	3
117	70	1 tableta	cada 24 horas	3	3
118	59	1 tableta	cada 24 horas	3	3
118	6	5 ml	cada 24 horas	3	1
119	42	1 tableta	cada 24 horas	3	3
120	31	1 tableta	cada 24 horas	3	3
122	62	Dosis indicada	cada 24 horas	3	1
123	63	1 cápsula	cada 24 horas	3	3
123	60	1 tableta	cada 24 horas	3	3
123	70	1 tableta	cada 24 horas	3	3
124	56	1 tableta	cada 24 horas	3	3
124	18	1 tableta	cada 24 horas	3	3
124	36	1 tableta	cada 24 horas	3	3
125	33	1 cápsula	cada 24 horas	3	3
125	41	1 tableta	cada 24 horas	3	3
125	51	Aplicar capa fina	cada 24 horas	3	1
126	18	1 tableta	cada 24 horas	3	3
127	60	1 tableta	cada 24 horas	3	3
127	69	1 tableta	cada 24 horas	3	3
128	52	1 tableta	cada 24 horas	3	3
129	44	1 sobre	cada 24 horas	3	3
129	62	Dosis indicada	cada 24 horas	3	1
129	58	1 tableta	cada 24 horas	3	3
130	25	1 tableta	cada 24 horas	3	3
130	2	1 cápsula	cada 24 horas	3	3
130	8	1 tableta	cada 24 horas	3	3
131	65	1 tableta	cada 24 horas	3	3
132	37	1 tableta	cada 24 horas	3	3
133	69	1 tableta	cada 24 horas	3	3
134	24	1 tableta	cada 24 horas	3	3
135	35	1 tableta	cada 24 horas	3	3
135	24	1 tableta	cada 24 horas	3	3
136	33	1 cápsula	cada 24 horas	3	3
136	37	1 tableta	cada 24 horas	3	3
136	69	1 tableta	cada 24 horas	3	3
137	32	1 tableta	cada 24 horas	3	3
137	35	1 tableta	cada 24 horas	3	3
137	3	1 tableta	cada 24 horas	3	3
138	43	2 inhalaciones	cada 24 horas	3	1
138	29	Dosis indicada	cada 24 horas	3	1
138	68	1 tableta	cada 24 horas	3	3
139	35	1 tableta	cada 24 horas	3	3
140	12	1 tableta	cada 24 horas	3	3
140	49	Aplicar capa fina	cada 24 horas	3	1
140	55	1 tableta	cada 24 horas	3	3
141	38	5 ml	cada 24 horas	3	1
142	62	Dosis indicada	cada 24 horas	3	1
142	70	1 tableta	cada 24 horas	3	3
142	48	Dosis indicada	cada 24 horas	3	1
143	44	1 sobre	cada 24 horas	3	3
145	13	Aplicar capa fina	cada 24 horas	3	1
145	9	5 ml	cada 24 horas	3	1
145	41	1 tableta	cada 24 horas	3	3
147	30	1 cápsula	cada 24 horas	3	3
148	48	Dosis indicada	cada 24 horas	3	1
148	26	1 cápsula	cada 24 horas	3	3
149	32	1 tableta	cada 24 horas	3	3
150	66	1 tableta	cada 24 horas	3	3
151	27	Dosis indicada	cada 24 horas	3	1
151	55	1 tableta	cada 24 horas	3	3
152	63	1 cápsula	cada 24 horas	3	3
153	45	5 ml	cada 24 horas	3	1
154	51	Aplicar capa fina	cada 24 horas	3	1
154	36	1 tableta	cada 24 horas	3	3
154	17	5 ml	cada 24 horas	3	1
155	60	1 tableta	cada 24 horas	3	3
155	2	1 cápsula	cada 24 horas	3	3
155	47	1 tableta	cada 24 horas	3	3
156	8	1 tableta	cada 24 horas	3	3
156	67	1 tableta	cada 24 horas	3	3
157	24	1 tableta	cada 24 horas	3	3
157	10	1 tableta	cada 24 horas	3	3
158	40	1 tableta	cada 24 horas	3	3
158	49	Aplicar capa fina	cada 24 horas	3	1
158	68	1 tableta	cada 24 horas	3	3
159	43	2 inhalaciones	cada 24 horas	3	1
160	9	5 ml	cada 24 horas	3	1
160	44	1 sobre	cada 24 horas	3	3
160	15	1 tableta	cada 24 horas	3	3
162	58	1 tableta	cada 24 horas	3	3
163	6	5 ml	cada 24 horas	3	1
166	39	5 ml	cada 24 horas	3	1
166	58	1 tableta	cada 24 horas	3	3
168	12	1 tableta	cada 24 horas	3	3
170	27	Dosis indicada	cada 24 horas	3	1
172	44	1 sobre	cada 24 horas	3	3
172	63	1 cápsula	cada 24 horas	3	3
173	10	1 tableta	cada 24 horas	3	3
173	2	1 cápsula	cada 24 horas	3	3
174	59	1 tableta	cada 24 horas	3	3
174	68	1 tableta	cada 24 horas	3	3
176	17	5 ml	cada 24 horas	3	1
176	71	Aplicar capa fina	cada 24 horas	3	1
178	24	1 tableta	cada 24 horas	3	3
178	40	1 tableta	cada 24 horas	3	3
179	36	1 tableta	cada 24 horas	3	3
179	8	1 tableta	cada 24 horas	3	3
180	56	1 tableta	cada 24 horas	3	3
180	63	1 cápsula	cada 24 horas	3	3
181	59	1 tableta	cada 24 horas	3	3
181	27	Dosis indicada	cada 24 horas	3	1
181	40	1 tableta	cada 24 horas	3	3
182	51	Aplicar capa fina	cada 24 horas	3	1
183	9	5 ml	cada 24 horas	3	1
183	60	1 tableta	cada 24 horas	3	3
183	61	1 tableta	cada 24 horas	3	3
184	63	1 cápsula	cada 24 horas	3	3
185	18	1 tableta	cada 24 horas	3	3
185	33	1 cápsula	cada 24 horas	3	3
185	43	2 inhalaciones	cada 24 horas	3	1
187	48	Dosis indicada	cada 24 horas	3	1
187	19	1 tableta	cada 24 horas	3	3
189	35	1 tableta	cada 24 horas	3	3
190	32	1 tableta	cada 24 horas	3	3
190	29	Dosis indicada	cada 24 horas	3	1
190	31	1 tableta	cada 24 horas	3	3
191	19	1 tableta	cada 24 horas	3	3
192	66	1 tableta	cada 24 horas	3	3
193	50	Aplicar capa fina	cada 24 horas	3	1
193	60	1 tableta	cada 24 horas	3	3
194	60	1 tableta	cada 24 horas	3	3
194	50	Aplicar capa fina	cada 24 horas	3	1
195	1	1 tableta	cada 24 horas	3	3
196	69	1 tableta	cada 24 horas	3	3
196	27	Dosis indicada	cada 24 horas	3	1
197	21	1 tableta	cada 24 horas	3	3
198	47	1 tableta	cada 24 horas	3	3
198	31	1 tableta	cada 24 horas	3	3
200	18	1 tableta	cada 24 horas	3	3
200	53	1 tableta	cada 24 horas	3	3
202	41	1 tableta	cada 24 horas	3	3
203	11	1 tableta	cada 24 horas	3	3
203	20	1 cápsula	cada 24 horas	3	3
204	20	1 cápsula	cada 24 horas	3	3
205	26	1 cápsula	cada 24 horas	3	3
205	15	1 tableta	cada 24 horas	3	3
206	27	Dosis indicada	cada 24 horas	3	1
206	69	1 tableta	cada 24 horas	3	3
206	72	Aplicar capa fina	cada 24 horas	3	1
207	28	1 cápsula	cada 24 horas	3	3
208	52	1 tableta	cada 24 horas	3	3
208	32	1 tableta	cada 24 horas	3	3
210	5	1 tableta	cada 24 horas	3	3
210	1	1 tableta	cada 24 horas	3	3
210	60	1 tableta	cada 24 horas	3	3
211	13	Aplicar capa fina	cada 24 horas	3	1
212	6	5 ml	cada 24 horas	3	1
212	36	1 tableta	cada 24 horas	3	3
215	37	1 tableta	cada 24 horas	3	3
215	65	1 tableta	cada 24 horas	3	3
215	17	5 ml	cada 24 horas	3	1
217	44	1 sobre	cada 24 horas	3	3
217	11	1 tableta	cada 24 horas	3	3
217	56	1 tableta	cada 24 horas	3	3
218	15	1 tableta	cada 24 horas	3	3
218	66	1 tableta	cada 24 horas	3	3
218	28	1 cápsula	cada 24 horas	3	3
220	1	1 tableta	cada 24 horas	3	3
221	73	Aplicar capa fina	cada 24 horas	3	1
221	11	1 tableta	cada 24 horas	3	3
223	55	1 tableta	cada 24 horas	3	3
223	8	1 tableta	cada 24 horas	3	3
224	38	5 ml	cada 24 horas	3	1
224	28	1 cápsula	cada 24 horas	3	3
225	18	1 tableta	cada 24 horas	3	3
225	15	1 tableta	cada 24 horas	3	3
226	27	Dosis indicada	cada 24 horas	3	1
227	46	1 tableta	cada 24 horas	3	3
227	67	1 tableta	cada 24 horas	3	3
227	62	Dosis indicada	cada 24 horas	3	1
228	28	1 cápsula	cada 24 horas	3	3
228	48	Dosis indicada	cada 24 horas	3	1
228	49	Aplicar capa fina	cada 24 horas	3	1
229	8	1 tableta	cada 24 horas	3	3
230	26	1 cápsula	cada 24 horas	3	3
230	61	1 tableta	cada 24 horas	3	3
231	34	1 sobre	cada 24 horas	3	3
232	23	1 cápsula	cada 24 horas	3	3
232	30	1 cápsula	cada 24 horas	3	3
233	49	Aplicar capa fina	cada 24 horas	3	1
235	42	1 tableta	cada 24 horas	3	3
235	71	Aplicar capa fina	cada 24 horas	3	1
236	22	1 tableta	cada 24 horas	3	3
237	56	1 tableta	cada 24 horas	3	3
237	71	Aplicar capa fina	cada 24 horas	3	1
237	17	5 ml	cada 24 horas	3	1
238	71	Aplicar capa fina	cada 24 horas	3	1
239	39	5 ml	cada 24 horas	3	1
239	27	Dosis indicada	cada 24 horas	3	1
239	14	1 tableta	cada 24 horas	3	3
240	58	1 tableta	cada 24 horas	3	3
240	60	1 tableta	cada 24 horas	3	3
241	19	1 tableta	cada 24 horas	3	3
241	14	1 tableta	cada 24 horas	3	3
241	68	1 tableta	cada 24 horas	3	3
243	51	Aplicar capa fina	cada 24 horas	3	1
243	33	1 cápsula	cada 24 horas	3	3
243	24	1 tableta	cada 24 horas	3	3
245	50	Aplicar capa fina	cada 24 horas	3	1
246	60	1 tableta	cada 24 horas	3	3
246	33	1 cápsula	cada 24 horas	3	3
247	55	1 tableta	cada 24 horas	3	3
247	3	1 tableta	cada 24 horas	3	3
249	25	1 tableta	cada 24 horas	3	3
249	13	Aplicar capa fina	cada 24 horas	3	1
249	57	1 tableta	cada 24 horas	3	3
250	29	Dosis indicada	cada 24 horas	3	1
250	30	1 cápsula	cada 24 horas	3	3
252	6	5 ml	cada 24 horas	3	1
252	29	Dosis indicada	cada 24 horas	3	1
255	36	1 tableta	cada 24 horas	3	3
256	49	Aplicar capa fina	cada 24 horas	3	1
261	69	1 tableta	cada 24 horas	3	3
261	63	1 cápsula	cada 24 horas	3	3
262	39	5 ml	cada 24 horas	3	1
262	12	1 tableta	cada 24 horas	3	3
263	49	Aplicar capa fina	cada 24 horas	3	1
263	45	5 ml	cada 24 horas	3	1
264	61	1 tableta	cada 24 horas	3	3
264	44	1 sobre	cada 24 horas	3	3
265	34	1 sobre	cada 24 horas	3	3
269	48	Dosis indicada	cada 24 horas	3	1
272	11	1 tableta	cada 24 horas	3	3
273	40	1 tableta	cada 24 horas	3	3
273	36	1 tableta	cada 24 horas	3	3
273	21	1 tableta	cada 24 horas	3	3
274	29	Dosis indicada	cada 24 horas	3	1
274	25	1 tableta	cada 24 horas	3	3
276	12	1 tableta	cada 24 horas	3	3
277	27	Dosis indicada	cada 24 horas	3	1
277	56	1 tableta	cada 24 horas	3	3
278	13	Aplicar capa fina	cada 24 horas	3	1
278	32	1 tableta	cada 24 horas	3	3
279	8	1 tableta	cada 24 horas	3	3
279	11	1 tableta	cada 24 horas	3	3
280	10	1 tableta	cada 24 horas	3	3
280	21	1 tableta	cada 24 horas	3	3
280	60	1 tableta	cada 24 horas	3	3
282	9	5 ml	cada 24 horas	3	1
282	62	Dosis indicada	cada 24 horas	3	1
282	21	1 tableta	cada 24 horas	3	3
283	46	1 tableta	cada 24 horas	3	3
283	25	1 tableta	cada 24 horas	3	3
283	1	1 tableta	cada 24 horas	3	3
284	21	1 tableta	cada 24 horas	3	3
284	13	Aplicar capa fina	cada 24 horas	3	1
285	53	1 tableta	cada 24 horas	3	3
286	57	1 tableta	cada 24 horas	3	3
286	3	1 tableta	cada 24 horas	3	3
288	62	Dosis indicada	cada 24 horas	3	1
288	59	1 tableta	cada 24 horas	3	3
288	54	1 tableta	cada 24 horas	3	3
290	52	1 tableta	cada 24 horas	3	3
290	59	1 tableta	cada 24 horas	3	3
291	73	Aplicar capa fina	cada 24 horas	3	1
292	14	1 tableta	cada 24 horas	3	3
293	19	1 tableta	cada 24 horas	3	3
293	37	1 tableta	cada 24 horas	3	3
293	51	Aplicar capa fina	cada 24 horas	3	1
294	31	1 tableta	cada 24 horas	3	3
294	66	1 tableta	cada 24 horas	3	3
294	20	1 cápsula	cada 24 horas	3	3
295	23	1 cápsula	cada 24 horas	3	3
295	66	1 tableta	cada 24 horas	3	3
296	35	1 tableta	cada 24 horas	3	3
297	25	1 tableta	cada 24 horas	3	3
297	48	Dosis indicada	cada 24 horas	3	1
298	39	5 ml	cada 24 horas	3	1
299	15	1 tableta	cada 24 horas	3	3
299	43	2 inhalaciones	cada 24 horas	3	1
299	17	5 ml	cada 24 horas	3	1
301	22	1 tableta	cada 24 horas	3	3
301	43	2 inhalaciones	cada 24 horas	3	1
302	55	1 tableta	cada 24 horas	3	3
302	15	1 tableta	cada 24 horas	3	3
302	65	1 tableta	cada 24 horas	3	3
303	8	1 tableta	cada 24 horas	3	3
303	27	Dosis indicada	cada 24 horas	3	1
303	23	1 cápsula	cada 24 horas	3	3
304	3	1 tableta	cada 24 horas	3	3
304	53	1 tableta	cada 24 horas	3	3
305	6	5 ml	cada 24 horas	3	1
306	39	5 ml	cada 24 horas	3	1
307	44	1 sobre	cada 24 horas	3	3
307	28	1 cápsula	cada 24 horas	3	3
311	46	1 tableta	cada 24 horas	3	3
311	17	5 ml	cada 24 horas	3	1
311	25	1 tableta	cada 24 horas	3	3
312	17	5 ml	cada 24 horas	3	1
313	2	1 cápsula	cada 24 horas	3	3
313	73	Aplicar capa fina	cada 24 horas	3	1
313	32	1 tableta	cada 24 horas	3	3
314	38	5 ml	cada 24 horas	3	1
314	23	1 cápsula	cada 24 horas	3	3
315	26	1 cápsula	cada 24 horas	3	3
315	62	Dosis indicada	cada 24 horas	3	1
315	1	1 tableta	cada 24 horas	3	3
317	30	1 cápsula	cada 24 horas	3	3
317	19	1 tableta	cada 24 horas	3	3
317	33	1 cápsula	cada 24 horas	3	3
318	63	1 cápsula	cada 24 horas	3	3
318	36	1 tableta	cada 24 horas	3	3
318	56	1 tableta	cada 24 horas	3	3
319	45	5 ml	cada 24 horas	3	1
319	72	Aplicar capa fina	cada 24 horas	3	1
319	59	1 tableta	cada 24 horas	3	3
320	69	1 tableta	cada 24 horas	3	3
320	27	Dosis indicada	cada 24 horas	3	1
320	62	Dosis indicada	cada 24 horas	3	1
322	17	5 ml	cada 24 horas	3	1
323	66	1 tableta	cada 24 horas	3	3
323	62	Dosis indicada	cada 24 horas	3	1
323	63	1 cápsula	cada 24 horas	3	3
324	59	1 tableta	cada 24 horas	3	3
325	48	Dosis indicada	cada 24 horas	3	1
325	33	1 cápsula	cada 24 horas	3	3
325	39	5 ml	cada 24 horas	3	1
326	13	Aplicar capa fina	cada 24 horas	3	1
326	15	1 tableta	cada 24 horas	3	3
326	43	2 inhalaciones	cada 24 horas	3	1
327	5	1 tableta	cada 24 horas	3	3
327	45	5 ml	cada 24 horas	3	1
328	64	1 tableta	cada 24 horas	3	3
328	56	1 tableta	cada 24 horas	3	3
329	37	1 tableta	cada 24 horas	3	3
330	33	1 cápsula	cada 24 horas	3	3
331	70	1 tableta	cada 24 horas	3	3
331	65	1 tableta	cada 24 horas	3	3
332	22	1 tableta	cada 24 horas	3	3
332	12	1 tableta	cada 24 horas	3	3
332	49	Aplicar capa fina	cada 24 horas	3	1
334	27	Dosis indicada	cada 24 horas	3	1
335	3	1 tableta	cada 24 horas	3	3
335	17	5 ml	cada 24 horas	3	1
336	55	1 tableta	cada 24 horas	3	3
338	25	1 tableta	cada 24 horas	3	3
338	8	1 tableta	cada 24 horas	3	3
339	21	1 tableta	cada 24 horas	3	3
339	65	1 tableta	cada 24 horas	3	3
340	20	1 cápsula	cada 24 horas	3	3
340	31	1 tableta	cada 24 horas	3	3
341	41	1 tableta	cada 24 horas	3	3
341	48	Dosis indicada	cada 24 horas	3	1
342	71	Aplicar capa fina	cada 24 horas	3	1
343	17	5 ml	cada 24 horas	3	1
343	55	1 tableta	cada 24 horas	3	3
345	59	1 tableta	cada 24 horas	3	3
345	62	Dosis indicada	cada 24 horas	3	1
345	13	Aplicar capa fina	cada 24 horas	3	1
346	72	Aplicar capa fina	cada 24 horas	3	1
346	18	1 tableta	cada 24 horas	3	3
348	17	5 ml	cada 24 horas	3	1
348	11	1 tableta	cada 24 horas	3	3
348	5	1 tableta	cada 24 horas	3	3
349	70	1 tableta	cada 24 horas	3	3
350	46	1 tableta	cada 24 horas	3	3
351	13	Aplicar capa fina	cada 24 horas	3	1
351	45	5 ml	cada 24 horas	3	1
351	72	Aplicar capa fina	cada 24 horas	3	1
353	49	Aplicar capa fina	cada 24 horas	3	1
353	21	1 tableta	cada 24 horas	3	3
353	52	1 tableta	cada 24 horas	3	3
354	54	1 tableta	cada 24 horas	3	3
354	3	1 tableta	cada 24 horas	3	3
354	8	1 tableta	cada 24 horas	3	3
356	61	1 tableta	cada 24 horas	3	3
356	54	1 tableta	cada 24 horas	3	3
356	50	Aplicar capa fina	cada 24 horas	3	1
357	73	Aplicar capa fina	cada 24 horas	3	1
359	71	Aplicar capa fina	cada 24 horas	3	1
359	40	1 tableta	cada 24 horas	3	3
359	25	1 tableta	cada 24 horas	3	3
361	13	Aplicar capa fina	cada 24 horas	3	1
361	18	1 tableta	cada 24 horas	3	3
361	29	Dosis indicada	cada 24 horas	3	1
362	21	1 tableta	cada 24 horas	3	3
363	11	1 tableta	cada 24 horas	3	3
363	57	1 tableta	cada 24 horas	3	3
363	24	1 tableta	cada 24 horas	3	3
364	69	1 tableta	cada 24 horas	3	3
364	24	1 tableta	cada 24 horas	3	3
365	40	1 tableta	cada 24 horas	3	3
365	67	1 tableta	cada 24 horas	3	3
366	1	1 tableta	cada 24 horas	3	3
366	55	1 tableta	cada 24 horas	3	3
367	61	1 tableta	cada 24 horas	3	3
367	17	5 ml	cada 24 horas	3	1
370	6	5 ml	cada 24 horas	3	1
370	58	1 tableta	cada 24 horas	3	3
372	28	1 cápsula	cada 24 horas	3	3
373	70	1 tableta	cada 24 horas	3	3
373	18	1 tableta	cada 24 horas	3	3
373	64	1 tableta	cada 24 horas	3	3
375	72	Aplicar capa fina	cada 24 horas	3	1
376	30	1 cápsula	cada 24 horas	3	3
376	32	1 tableta	cada 24 horas	3	3
377	56	1 tableta	cada 24 horas	3	3
378	65	1 tableta	cada 24 horas	3	3
378	71	Aplicar capa fina	cada 24 horas	3	1
382	22	1 tableta	cada 24 horas	3	3
382	18	1 tableta	cada 24 horas	3	3
383	40	1 tableta	cada 24 horas	3	3
384	56	1 tableta	cada 24 horas	3	3
385	39	5 ml	cada 24 horas	3	1
385	72	Aplicar capa fina	cada 24 horas	3	1
386	37	1 tableta	cada 24 horas	3	3
386	68	1 tableta	cada 24 horas	3	3
386	12	1 tableta	cada 24 horas	3	3
388	71	Aplicar capa fina	cada 24 horas	3	1
388	64	1 tableta	cada 24 horas	3	3
388	1	1 tableta	cada 24 horas	3	3
390	46	1 tableta	cada 24 horas	3	3
391	44	1 sobre	cada 24 horas	3	3
391	59	1 tableta	cada 24 horas	3	3
391	37	1 tableta	cada 24 horas	3	3
393	71	Aplicar capa fina	cada 24 horas	3	1
395	61	1 tableta	cada 24 horas	3	3
395	64	1 tableta	cada 24 horas	3	3
397	43	2 inhalaciones	cada 24 horas	3	1
397	6	5 ml	cada 24 horas	3	1
397	61	1 tableta	cada 24 horas	3	3
398	20	1 cápsula	cada 24 horas	3	3
398	5	1 tableta	cada 24 horas	3	3
399	14	1 tableta	cada 24 horas	3	3
400	18	1 tableta	cada 24 horas	3	3
402	23	1 cápsula	cada 24 horas	3	3
404	12	1 tableta	cada 24 horas	3	3
404	1	1 tableta	cada 24 horas	3	3
404	26	1 cápsula	cada 24 horas	3	3
405	20	1 cápsula	cada 24 horas	3	3
405	32	1 tableta	cada 24 horas	3	3
406	25	1 tableta	cada 24 horas	3	3
406	12	1 tableta	cada 24 horas	3	3
408	5	1 tableta	cada 24 horas	3	3
408	49	Aplicar capa fina	cada 24 horas	3	1
409	62	Dosis indicada	cada 24 horas	3	1
409	3	1 tableta	cada 24 horas	3	3
409	59	1 tableta	cada 24 horas	3	3
410	38	5 ml	cada 24 horas	3	1
411	6	5 ml	cada 24 horas	3	1
412	33	1 cápsula	cada 24 horas	3	3
412	62	Dosis indicada	cada 24 horas	3	1
413	41	1 tableta	cada 24 horas	3	3
413	69	1 tableta	cada 24 horas	3	3
414	2	1 cápsula	cada 24 horas	3	3
414	53	1 tableta	cada 24 horas	3	3
415	63	1 cápsula	cada 24 horas	3	3
415	6	5 ml	cada 24 horas	3	1
415	18	1 tableta	cada 24 horas	3	3
417	70	1 tableta	cada 24 horas	3	3
418	39	5 ml	cada 24 horas	3	1
419	19	1 tableta	cada 24 horas	3	3
419	14	1 tableta	cada 24 horas	3	3
419	30	1 cápsula	cada 24 horas	3	3
420	21	1 tableta	cada 24 horas	3	3
420	66	1 tableta	cada 24 horas	3	3
421	36	1 tableta	cada 24 horas	3	3
421	1	1 tableta	cada 24 horas	3	3
421	14	1 tableta	cada 24 horas	3	3
422	39	5 ml	cada 24 horas	3	1
423	42	1 tableta	cada 24 horas	3	3
424	12	1 tableta	cada 24 horas	3	3
424	62	Dosis indicada	cada 24 horas	3	1
424	53	1 tableta	cada 24 horas	3	3
425	64	1 tableta	cada 24 horas	3	3
425	22	1 tableta	cada 24 horas	3	3
425	2	1 cápsula	cada 24 horas	3	3
426	27	Dosis indicada	cada 24 horas	3	1
428	30	1 cápsula	cada 24 horas	3	3
428	56	1 tableta	cada 24 horas	3	3
428	2	1 cápsula	cada 24 horas	3	3
430	70	1 tableta	cada 24 horas	3	3
430	57	1 tableta	cada 24 horas	3	3
430	40	1 tableta	cada 24 horas	3	3
431	15	1 tableta	cada 24 horas	3	3
431	34	1 sobre	cada 24 horas	3	3
431	66	1 tableta	cada 24 horas	3	3
433	10	1 tableta	cada 24 horas	3	3
433	36	1 tableta	cada 24 horas	3	3
435	29	Dosis indicada	cada 24 horas	3	1
436	58	1 tableta	cada 24 horas	3	3
436	51	Aplicar capa fina	cada 24 horas	3	1
436	70	1 tableta	cada 24 horas	3	3
437	59	1 tableta	cada 24 horas	3	3
437	57	1 tableta	cada 24 horas	3	3
438	54	1 tableta	cada 24 horas	3	3
438	41	1 tableta	cada 24 horas	3	3
440	6	5 ml	cada 24 horas	3	1
441	67	1 tableta	cada 24 horas	3	3
441	31	1 tableta	cada 24 horas	3	3
441	11	1 tableta	cada 24 horas	3	3
442	50	Aplicar capa fina	cada 24 horas	3	1
442	23	1 cápsula	cada 24 horas	3	3
443	12	1 tableta	cada 24 horas	3	3
443	28	1 cápsula	cada 24 horas	3	3
443	29	Dosis indicada	cada 24 horas	3	1
444	45	5 ml	cada 24 horas	3	1
445	63	1 cápsula	cada 24 horas	3	3
445	48	Dosis indicada	cada 24 horas	3	1
445	60	1 tableta	cada 24 horas	3	3
446	38	5 ml	cada 24 horas	3	1
446	23	1 cápsula	cada 24 horas	3	3
446	26	1 cápsula	cada 24 horas	3	3
447	32	1 tableta	cada 24 horas	3	3
448	35	1 tableta	cada 24 horas	3	3
448	14	1 tableta	cada 24 horas	3	3
448	12	1 tableta	cada 24 horas	3	3
449	46	1 tableta	cada 24 horas	3	3
449	64	1 tableta	cada 24 horas	3	3
449	47	1 tableta	cada 24 horas	3	3
450	39	5 ml	cada 24 horas	3	1
451	22	1 tableta	cada 24 horas	3	3
451	27	Dosis indicada	cada 24 horas	3	1
452	45	5 ml	cada 24 horas	3	1
452	18	1 tableta	cada 24 horas	3	3
453	26	1 cápsula	cada 24 horas	3	3
454	3	1 tableta	cada 24 horas	3	3
454	14	1 tableta	cada 24 horas	3	3
454	69	1 tableta	cada 24 horas	3	3
456	48	Dosis indicada	cada 24 horas	3	1
456	49	Aplicar capa fina	cada 24 horas	3	1
456	66	1 tableta	cada 24 horas	3	3
457	35	1 tableta	cada 24 horas	3	3
457	50	Aplicar capa fina	cada 24 horas	3	1
458	20	1 cápsula	cada 24 horas	3	3
458	15	1 tableta	cada 24 horas	3	3
458	59	1 tableta	cada 24 horas	3	3
459	55	1 tableta	cada 24 horas	3	3
460	2	1 cápsula	cada 24 horas	3	3
461	30	1 cápsula	cada 24 horas	3	3
461	44	1 sobre	cada 24 horas	3	3
461	17	5 ml	cada 24 horas	3	1
463	73	Aplicar capa fina	cada 24 horas	3	1
463	25	1 tableta	cada 24 horas	3	3
464	32	1 tableta	cada 24 horas	3	3
464	8	1 tableta	cada 24 horas	3	3
464	70	1 tableta	cada 24 horas	3	3
465	52	1 tableta	cada 24 horas	3	3
465	37	1 tableta	cada 24 horas	3	3
467	34	1 sobre	cada 24 horas	3	3
467	43	2 inhalaciones	cada 24 horas	3	1
467	20	1 cápsula	cada 24 horas	3	3
469	67	1 tableta	cada 24 horas	3	3
469	25	1 tableta	cada 24 horas	3	3
469	15	1 tableta	cada 24 horas	3	3
470	11	1 tableta	cada 24 horas	3	3
471	49	Aplicar capa fina	cada 24 horas	3	1
471	61	1 tableta	cada 24 horas	3	3
472	59	1 tableta	cada 24 horas	3	3
474	52	1 tableta	cada 24 horas	3	3
474	72	Aplicar capa fina	cada 24 horas	3	1
475	21	1 tableta	cada 24 horas	3	3
475	22	1 tableta	cada 24 horas	3	3
476	49	Aplicar capa fina	cada 24 horas	3	1
476	71	Aplicar capa fina	cada 24 horas	3	1
477	63	1 cápsula	cada 24 horas	3	3
478	36	1 tableta	cada 24 horas	3	3
478	43	2 inhalaciones	cada 24 horas	3	1
478	24	1 tableta	cada 24 horas	3	3
479	19	1 tableta	cada 24 horas	3	3
479	62	Dosis indicada	cada 24 horas	3	1
479	32	1 tableta	cada 24 horas	3	3
480	32	1 tableta	cada 24 horas	3	3
480	25	1 tableta	cada 24 horas	3	3
480	8	1 tableta	cada 24 horas	3	3
481	46	1 tableta	cada 24 horas	3	3
481	18	1 tableta	cada 24 horas	3	3
482	66	1 tableta	cada 24 horas	3	3
484	29	Dosis indicada	cada 24 horas	3	1
484	62	Dosis indicada	cada 24 horas	3	1
486	32	1 tableta	cada 24 horas	3	3
488	35	1 tableta	cada 24 horas	3	3
488	31	1 tableta	cada 24 horas	3	3
488	21	1 tableta	cada 24 horas	3	3
489	55	1 tableta	cada 24 horas	3	3
492	42	1 tableta	cada 24 horas	3	3
492	30	1 cápsula	cada 24 horas	3	3
492	44	1 sobre	cada 24 horas	3	3
494	68	1 tableta	cada 24 horas	3	3
494	61	1 tableta	cada 24 horas	3	3
494	63	1 cápsula	cada 24 horas	3	3
495	35	1 tableta	cada 24 horas	3	3
495	62	Dosis indicada	cada 24 horas	3	1
495	47	1 tableta	cada 24 horas	3	3
497	26	1 cápsula	cada 24 horas	3	3
498	17	5 ml	cada 24 horas	3	1
499	63	1 cápsula	cada 24 horas	3	3
499	1	1 tableta	cada 24 horas	3	3
500	30	1 cápsula	cada 24 horas	3	3
500	48	Dosis indicada	cada 24 horas	3	1
500	65	1 tableta	cada 24 horas	3	3
502	10	1 tableta	cada 24 horas	3	3
504	41	1 tableta	cada 24 horas	3	3
504	69	1 tableta	cada 24 horas	3	3
504	68	1 tableta	cada 24 horas	3	3
505	73	Aplicar capa fina	cada 24 horas	3	1
506	19	1 tableta	cada 24 horas	3	3
506	2	1 cápsula	cada 24 horas	3	3
506	5	1 tableta	cada 24 horas	3	3
507	46	1 tableta	cada 24 horas	3	3
507	57	1 tableta	cada 24 horas	3	3
508	39	5 ml	cada 24 horas	3	1
508	61	1 tableta	cada 24 horas	3	3
508	40	1 tableta	cada 24 horas	3	3
509	53	1 tableta	cada 24 horas	3	3
509	32	1 tableta	cada 24 horas	3	3
509	46	1 tableta	cada 24 horas	3	3
512	35	1 tableta	cada 24 horas	3	3
512	69	1 tableta	cada 24 horas	3	3
513	37	1 tableta	cada 24 horas	3	3
514	46	1 tableta	cada 24 horas	3	3
514	51	Aplicar capa fina	cada 24 horas	3	1
514	39	5 ml	cada 24 horas	3	1
515	31	1 tableta	cada 24 horas	3	3
516	54	1 tableta	cada 24 horas	3	3
516	69	1 tableta	cada 24 horas	3	3
516	22	1 tableta	cada 24 horas	3	3
517	54	1 tableta	cada 24 horas	3	3
517	2	1 cápsula	cada 24 horas	3	3
519	54	1 tableta	cada 24 horas	3	3
519	63	1 cápsula	cada 24 horas	3	3
520	42	1 tableta	cada 24 horas	3	3
521	12	1 tableta	cada 24 horas	3	3
521	6	5 ml	cada 24 horas	3	1
522	36	1 tableta	cada 24 horas	3	3
526	34	1 sobre	cada 24 horas	3	3
526	21	1 tableta	cada 24 horas	3	3
527	56	1 tableta	cada 24 horas	3	3
527	49	Aplicar capa fina	cada 24 horas	3	1
527	41	1 tableta	cada 24 horas	3	3
528	66	1 tableta	cada 24 horas	3	3
528	1	1 tableta	cada 24 horas	3	3
528	40	1 tableta	cada 24 horas	3	3
529	56	1 tableta	cada 24 horas	3	3
529	8	1 tableta	cada 24 horas	3	3
531	8	1 tableta	cada 24 horas	3	3
531	1	1 tableta	cada 24 horas	3	3
534	28	1 cápsula	cada 24 horas	3	3
535	70	1 tableta	cada 24 horas	3	3
535	40	1 tableta	cada 24 horas	3	3
535	46	1 tableta	cada 24 horas	3	3
536	66	1 tableta	cada 24 horas	3	3
536	12	1 tableta	cada 24 horas	3	3
537	27	Dosis indicada	cada 24 horas	3	1
537	37	1 tableta	cada 24 horas	3	3
538	63	1 cápsula	cada 24 horas	3	3
538	70	1 tableta	cada 24 horas	3	3
539	13	Aplicar capa fina	cada 24 horas	3	1
540	51	Aplicar capa fina	cada 24 horas	3	1
540	41	1 tableta	cada 24 horas	3	3
540	8	1 tableta	cada 24 horas	3	3
541	17	5 ml	cada 24 horas	3	1
543	38	5 ml	cada 24 horas	3	1
543	48	Dosis indicada	cada 24 horas	3	1
545	18	1 tableta	cada 24 horas	3	3
545	28	1 cápsula	cada 24 horas	3	3
545	51	Aplicar capa fina	cada 24 horas	3	1
546	27	Dosis indicada	cada 24 horas	3	1
546	72	Aplicar capa fina	cada 24 horas	3	1
548	13	Aplicar capa fina	cada 24 horas	3	1
549	63	1 cápsula	cada 24 horas	3	3
549	39	5 ml	cada 24 horas	3	1
549	20	1 cápsula	cada 24 horas	3	3
551	70	1 tableta	cada 24 horas	3	3
551	45	5 ml	cada 24 horas	3	1
552	38	5 ml	cada 24 horas	3	1
552	41	1 tableta	cada 24 horas	3	3
553	68	1 tableta	cada 24 horas	3	3
553	40	1 tableta	cada 24 horas	3	3
553	35	1 tableta	cada 24 horas	3	3
554	56	1 tableta	cada 24 horas	3	3
555	30	1 cápsula	cada 24 horas	3	3
555	36	1 tableta	cada 24 horas	3	3
555	63	1 cápsula	cada 24 horas	3	3
557	52	1 tableta	cada 24 horas	3	3
560	29	Dosis indicada	cada 24 horas	3	1
560	17	5 ml	cada 24 horas	3	1
560	38	5 ml	cada 24 horas	3	1
561	61	1 tableta	cada 24 horas	3	3
561	5	1 tableta	cada 24 horas	3	3
563	5	1 tableta	cada 24 horas	3	3
564	11	1 tableta	cada 24 horas	3	3
565	22	1 tableta	cada 24 horas	3	3
565	5	1 tableta	cada 24 horas	3	3
565	57	1 tableta	cada 24 horas	3	3
566	57	1 tableta	cada 24 horas	3	3
566	34	1 sobre	cada 24 horas	3	3
566	13	Aplicar capa fina	cada 24 horas	3	1
568	47	1 tableta	cada 24 horas	3	3
568	22	1 tableta	cada 24 horas	3	3
568	38	5 ml	cada 24 horas	3	1
569	1	1 tableta	cada 24 horas	3	3
569	71	Aplicar capa fina	cada 24 horas	3	1
569	65	1 tableta	cada 24 horas	3	3
570	45	5 ml	cada 24 horas	3	1
570	32	1 tableta	cada 24 horas	3	3
570	9	5 ml	cada 24 horas	3	1
571	28	1 cápsula	cada 24 horas	3	3
574	8	1 tableta	cada 24 horas	3	3
574	28	1 cápsula	cada 24 horas	3	3
575	59	1 tableta	cada 24 horas	3	3
575	19	1 tableta	cada 24 horas	3	3
575	73	Aplicar capa fina	cada 24 horas	3	1
576	1	1 tableta	cada 24 horas	3	3
576	19	1 tableta	cada 24 horas	3	3
576	61	1 tableta	cada 24 horas	3	3
578	26	1 cápsula	cada 24 horas	3	3
578	29	Dosis indicada	cada 24 horas	3	1
578	73	Aplicar capa fina	cada 24 horas	3	1
579	9	5 ml	cada 24 horas	3	1
580	37	1 tableta	cada 24 horas	3	3
581	47	1 tableta	cada 24 horas	3	3
581	24	1 tableta	cada 24 horas	3	3
582	26	1 cápsula	cada 24 horas	3	3
583	72	Aplicar capa fina	cada 24 horas	3	1
583	49	Aplicar capa fina	cada 24 horas	3	1
584	42	1 tableta	cada 24 horas	3	3
586	51	Aplicar capa fina	cada 24 horas	3	1
586	66	1 tableta	cada 24 horas	3	3
588	23	1 cápsula	cada 24 horas	3	3
588	67	1 tableta	cada 24 horas	3	3
591	52	1 tableta	cada 24 horas	3	3
592	28	1 cápsula	cada 24 horas	3	3
592	62	Dosis indicada	cada 24 horas	3	1
592	67	1 tableta	cada 24 horas	3	3
594	36	1 tableta	cada 24 horas	3	3
595	35	1 tableta	cada 24 horas	3	3
595	50	Aplicar capa fina	cada 24 horas	3	1
595	73	Aplicar capa fina	cada 24 horas	3	1
596	68	1 tableta	cada 24 horas	3	3
596	19	1 tableta	cada 24 horas	3	3
597	57	1 tableta	cada 24 horas	3	3
599	25	1 tableta	cada 24 horas	3	3
599	9	5 ml	cada 24 horas	3	1
601	54	1 tableta	cada 24 horas	3	3
601	55	1 tableta	cada 24 horas	3	3
601	17	5 ml	cada 24 horas	3	1
602	52	1 tableta	cada 24 horas	3	3
602	70	1 tableta	cada 24 horas	3	3
602	37	1 tableta	cada 24 horas	3	3
603	68	1 tableta	cada 24 horas	3	3
603	59	1 tableta	cada 24 horas	3	3
603	1	1 tableta	cada 24 horas	3	3
604	48	Dosis indicada	cada 24 horas	3	1
604	47	1 tableta	cada 24 horas	3	3
604	56	1 tableta	cada 24 horas	3	3
605	43	2 inhalaciones	cada 24 horas	3	1
606	48	Dosis indicada	cada 24 horas	3	1
607	58	1 tableta	cada 24 horas	3	3
607	72	Aplicar capa fina	cada 24 horas	3	1
608	45	5 ml	cada 24 horas	3	1
609	37	1 tableta	cada 24 horas	3	3
609	18	1 tableta	cada 24 horas	3	3
611	45	5 ml	cada 24 horas	3	1
611	11	1 tableta	cada 24 horas	3	3
611	54	1 tableta	cada 24 horas	3	3
613	72	Aplicar capa fina	cada 24 horas	3	1
613	12	1 tableta	cada 24 horas	3	3
615	25	1 tableta	cada 24 horas	3	3
615	41	1 tableta	cada 24 horas	3	3
617	45	5 ml	cada 24 horas	3	1
618	69	1 tableta	cada 24 horas	3	3
618	53	1 tableta	cada 24 horas	3	3
618	13	Aplicar capa fina	cada 24 horas	3	1
619	52	1 tableta	cada 24 horas	3	3
620	65	1 tableta	cada 24 horas	3	3
620	32	1 tableta	cada 24 horas	3	3
620	21	1 tableta	cada 24 horas	3	3
624	21	1 tableta	cada 24 horas	3	3
624	56	1 tableta	cada 24 horas	3	3
624	37	1 tableta	cada 24 horas	3	3
626	55	1 tableta	cada 24 horas	3	3
629	38	5 ml	cada 24 horas	3	1
629	26	1 cápsula	cada 24 horas	3	3
632	32	1 tableta	cada 24 horas	3	3
632	36	1 tableta	cada 24 horas	3	3
633	12	1 tableta	cada 24 horas	3	3
634	19	1 tableta	cada 24 horas	3	3
634	43	2 inhalaciones	cada 24 horas	3	1
635	17	5 ml	cada 24 horas	3	1
637	56	1 tableta	cada 24 horas	3	3
637	67	1 tableta	cada 24 horas	3	3
638	20	1 cápsula	cada 24 horas	3	3
638	46	1 tableta	cada 24 horas	3	3
638	28	1 cápsula	cada 24 horas	3	3
640	25	1 tableta	cada 24 horas	3	3
641	48	Dosis indicada	cada 24 horas	3	1
641	6	5 ml	cada 24 horas	3	1
642	28	1 cápsula	cada 24 horas	3	3
642	33	1 cápsula	cada 24 horas	3	3
642	8	1 tableta	cada 24 horas	3	3
\.


--
-- TOC entry 5512 (class 0 OID 17737)
-- Dependencies: 233
-- Data for Name: historia_clinica; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.historia_clinica (id_historia, id_cita, diagnostico, observaciones, fecha_registro, codigo_cie10) FROM stdin;
2	2	Control normal	\N	2026-10-19 08:20:20.822208-05	\N
1	1	Cefalea tensional	Reposo e hidratación	2026-10-19 08:20:20.822208-05	G442
14	21	Gastritis	Evitar la automedicación	2026-09-04 17:25:00-05	K297
15	22	Gastroenteritis aguda	Se ordenan exámenes de laboratorio	2026-09-04 14:25:00-05	A09X
17	24	Gastritis	Actividad física moderada	2026-09-04 16:55:00-05	K297
18	25	Infección respiratoria aguda	Dieta blanda por 3 días	2026-09-04 08:55:00-05	J069
22	29	Faringoamigdalitis	Control en 8 días	2026-09-04 15:25:00-05	J029
23	30	Control general sin hallazgos	Actividad física moderada	2026-09-04 16:55:00-05	Z000
24	31	Diabetes mellitus tipo 2 en control	Evitar la automedicación	2026-09-04 17:55:00-05	E119
25	32	Gastritis	Evitar la automedicación	2026-09-04 08:25:00-05	K297
26	33	Control general sin hallazgos	Regresar si persisten los síntomas	2026-09-04 10:25:00-05	Z000
27	35	Hipertensión arterial en control	Actividad física moderada	2026-09-04 15:25:00-05	I10X
28	36	Hipertensión arterial en control	\N	2026-09-04 15:55:00-05	I10X
29	43	Otitis media	\N	2026-09-04 15:55:00-05	H669
31	46	Síndrome febril	Evitar la automedicación	2026-09-04 16:25:00-05	R509
32	47	Síndrome febril	Se ordenan exámenes de laboratorio	2026-09-04 17:25:00-05	R509
34	50	Rinitis alérgica	\N	2026-09-07 11:25:00-05	J304
35	51	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-09-07 15:25:00-05	J069
36	52	Mialgia	Actividad física moderada	2026-09-07 08:55:00-05	M791
37	53	Faringoamigdalitis	\N	2026-09-07 11:25:00-05	J029
38	54	Mialgia	Dieta blanda por 3 días	2026-09-07 15:25:00-05	M791
39	55	Faringoamigdalitis	Control en 8 días	2026-09-07 15:55:00-05	J029
40	57	Diabetes mellitus tipo 2 en control	Reposo e hidratación	2026-09-07 11:55:00-05	E119
41	58	Síndrome febril	\N	2026-09-07 09:55:00-05	R509
42	59	Diabetes mellitus tipo 2 en control	Actividad física moderada	2026-09-07 08:25:00-05	E119
43	61	Otitis media	Se ordenan exámenes de laboratorio	2026-09-07 17:55:00-05	H669
44	62	Faringoamigdalitis	Evitar la automedicación	2026-09-07 09:55:00-05	J029
45	64	Otitis media	Reposo e hidratación	2026-09-07 14:55:00-05	H669
46	65	Rinofaringitis aguda	Dieta blanda por 3 días	2026-09-07 15:25:00-05	J00X
47	66	Hipertensión arterial en control	Se ordenan exámenes de laboratorio	2026-09-07 16:25:00-05	I10X
48	68	Cefalea tensional	Actividad física moderada	2026-09-07 08:55:00-05	G442
49	70	Mialgia	\N	2026-09-07 16:55:00-05	M791
50	72	Mialgia	Actividad física moderada	2026-09-08 15:55:00-05	M791
51	74	Cefalea tensional	Actividad física moderada	2026-09-08 09:25:00-05	G442
52	75	Rinitis alérgica	Control en 8 días	2026-09-08 10:55:00-05	J304
53	76	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-08 14:25:00-05	J029
54	77	Rinofaringitis aguda	\N	2026-09-08 10:55:00-05	J00X
55	78	Infección respiratoria aguda	\N	2026-09-08 11:25:00-05	J069
56	79	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-09-08 15:25:00-05	E119
57	80	Gastritis	\N	2026-09-08 16:25:00-05	K297
58	81	Síndrome febril	\N	2026-09-08 08:25:00-05	R509
59	82	Infección respiratoria aguda	Regresar si persisten los síntomas	2026-09-08 14:55:00-05	J069
60	83	Rinitis alérgica	Regresar si persisten los síntomas	2026-09-08 15:55:00-05	J304
61	84	Cefalea tensional	\N	2026-09-08 08:55:00-05	G442
62	85	Control general sin hallazgos	Evitar la automedicación	2026-09-08 11:55:00-05	Z000
63	86	Cefalea tensional	\N	2026-09-08 14:25:00-05	G442
64	87	Rinitis alérgica	Evitar la automedicación	2026-09-08 14:25:00-05	J304
65	88	Gastritis	\N	2026-09-08 14:55:00-05	K297
67	91	Gastroenteritis aguda	Dieta blanda por 3 días	2026-09-08 15:55:00-05	A09X
69	93	Gastritis	Se ordenan exámenes de laboratorio	2026-09-08 09:25:00-05	K297
70	94	Otitis media	Evitar la automedicación	2026-09-08 09:55:00-05	H669
71	95	Faringoamigdalitis	Actividad física moderada	2026-09-08 10:25:00-05	J029
72	96	Diabetes mellitus tipo 2 en control	Actividad física moderada	2026-09-08 14:55:00-05	E119
73	97	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-09-08 16:55:00-05	E119
74	98	Cefalea tensional	\N	2026-09-09 08:55:00-05	G442
75	99	Rinofaringitis aguda	Reposo e hidratación	2026-09-09 10:25:00-05	J00X
76	101	Rinofaringitis aguda	\N	2026-09-09 15:55:00-05	J00X
78	103	Gastroenteritis aguda	Control en 8 días	2026-09-09 08:25:00-05	A09X
79	104	Gastritis	Dieta blanda por 3 días	2026-09-09 11:55:00-05	K297
80	106	Infección respiratoria aguda	Dieta blanda por 3 días	2026-09-09 15:25:00-05	J069
82	108	Infección respiratoria aguda	Evitar la automedicación	2026-09-09 11:25:00-05	J069
83	110	Control general sin hallazgos	\N	2026-09-09 08:55:00-05	Z000
84	111	Cefalea tensional	Reposo e hidratación	2026-09-09 11:55:00-05	G442
85	112	Diabetes mellitus tipo 2 en control	Dieta blanda por 3 días	2026-09-09 17:25:00-05	E119
86	113	Rinitis alérgica	Dieta blanda por 3 días	2026-09-09 11:25:00-05	J304
87	114	Mialgia	Regresar si persisten los síntomas	2026-09-09 14:55:00-05	M791
89	116	Gastroenteritis aguda	Evitar la automedicación	2026-09-09 17:25:00-05	A09X
90	117	Mialgia	\N	2026-09-09 10:25:00-05	M791
92	120	Gastroenteritis aguda	Regresar si persisten los síntomas	2026-09-09 09:55:00-05	A09X
93	121	Infección respiratoria aguda	\N	2026-09-09 16:25:00-05	J069
94	122	Gastritis	Se ordenan exámenes de laboratorio	2026-09-10 09:55:00-05	K297
95	123	Faringoamigdalitis	Reposo e hidratación	2026-09-10 14:25:00-05	J029
96	124	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-10 17:25:00-05	J029
98	126	Faringoamigdalitis	\N	2026-09-10 14:55:00-05	J029
99	127	Cefalea tensional	Evitar la automedicación	2026-09-10 16:25:00-05	G442
100	128	Hipertensión arterial en control	\N	2026-09-10 17:25:00-05	I10X
101	129	Otitis media	Regresar si persisten los síntomas	2026-09-10 11:25:00-05	H669
103	132	Faringoamigdalitis	\N	2026-09-10 15:25:00-05	J029
104	133	Control general sin hallazgos	Dieta blanda por 3 días	2026-09-10 15:55:00-05	Z000
105	134	Gastritis	Evitar la automedicación	2026-09-10 16:25:00-05	K297
106	136	Rinitis alérgica	Control en 8 días	2026-09-10 09:55:00-05	J304
107	137	Síndrome febril	\N	2026-09-10 10:25:00-05	R509
108	138	Rinitis alérgica	Dieta blanda por 3 días	2026-09-10 11:55:00-05	J304
3	9	Dermatitis alérgica	\N	2026-09-04 08:55:00-05	\N
109	139	Infección respiratoria aguda	Regresar si persisten los síntomas	2026-09-10 14:25:00-05	J069
110	140	Diabetes mellitus tipo 2 en control	\N	2026-09-10 15:25:00-05	E119
111	141	Diabetes mellitus tipo 2 en control	\N	2026-09-10 15:55:00-05	E119
112	142	Control general sin hallazgos	Se ordenan exámenes de laboratorio	2026-09-10 16:25:00-05	Z000
114	144	Infección respiratoria aguda	Reposo e hidratación	2026-09-10 10:55:00-05	J069
115	145	Gastroenteritis aguda	Dieta blanda por 3 días	2026-09-10 08:25:00-05	A09X
116	146	Faringoamigdalitis	Evitar la automedicación	2026-09-10 08:55:00-05	J029
119	149	Gastroenteritis aguda	Regresar si persisten los síntomas	2026-09-10 10:25:00-05	A09X
120	150	Cefalea tensional	Control en 8 días	2026-09-10 10:55:00-05	G442
122	152	Síndrome febril	Control en 8 días	2026-09-11 10:55:00-05	R509
124	155	Gastritis	\N	2026-09-11 17:55:00-05	K297
125	156	Faringoamigdalitis	Se ordenan exámenes de laboratorio	2026-09-11 09:25:00-05	J029
126	158	Rinitis alérgica	Control en 8 días	2026-09-11 17:55:00-05	J304
128	160	Gastritis	Dieta blanda por 3 días	2026-09-11 08:25:00-05	K297
129	161	Rinofaringitis aguda	Evitar la automedicación	2026-09-11 17:55:00-05	J00X
130	162	Hipertensión arterial en control	Actividad física moderada	2026-09-11 09:55:00-05	I10X
131	163	Mialgia	\N	2026-09-11 10:25:00-05	M791
132	165	Rinofaringitis aguda	Actividad física moderada	2026-09-11 11:55:00-05	J00X
133	167	Infección respiratoria aguda	Actividad física moderada	2026-09-11 15:25:00-05	J069
134	168	Hipertensión arterial en control	Actividad física moderada	2026-09-11 17:55:00-05	I10X
135	169	Mialgia	\N	2026-09-11 08:55:00-05	M791
137	171	Faringoamigdalitis	Evitar la automedicación	2026-09-11 08:25:00-05	J029
138	172	Faringoamigdalitis	Reposo e hidratación	2026-09-11 10:25:00-05	J029
139	173	Otitis media	\N	2026-09-11 10:55:00-05	H669
140	174	Faringoamigdalitis	Dieta blanda por 3 días	2026-09-14 09:25:00-05	J029
141	175	Infección respiratoria aguda	\N	2026-09-14 10:55:00-05	J069
142	176	Síndrome febril	Control en 8 días	2026-09-14 15:25:00-05	R509
143	177	Síndrome febril	Regresar si persisten los síntomas	2026-09-14 17:25:00-05	R509
144	178	Gastritis	Regresar si persisten los síntomas	2026-09-14 08:25:00-05	K297
145	179	Rinofaringitis aguda	Control en 8 días	2026-09-14 08:55:00-05	J00X
147	185	Rinitis alérgica	Regresar si persisten los síntomas	2026-09-14 10:25:00-05	J304
148	186	Control general sin hallazgos	Se ordenan exámenes de laboratorio	2026-09-14 14:25:00-05	Z000
150	190	Mialgia	\N	2026-09-14 08:55:00-05	M791
152	192	Control general sin hallazgos	Actividad física moderada	2026-09-14 15:55:00-05	Z000
153	193	Rinitis alérgica	Regresar si persisten los síntomas	2026-09-14 08:25:00-05	J304
154	194	Cefalea tensional	Reposo e hidratación	2026-09-14 16:55:00-05	G442
156	196	Síndrome febril	\N	2026-09-14 11:55:00-05	R509
157	197	Hipertensión arterial en control	Dieta blanda por 3 días	2026-09-14 16:25:00-05	I10X
158	198	Control general sin hallazgos	Regresar si persisten los síntomas	2026-09-15 08:25:00-05	Z000
159	199	Cefalea tensional	Actividad física moderada	2026-09-15 08:55:00-05	G442
161	202	Otitis media	Control en 8 días	2026-09-15 14:55:00-05	H669
162	203	Cefalea tensional	Regresar si persisten los síntomas	2026-09-15 16:25:00-05	G442
163	204	Control general sin hallazgos	Reposo e hidratación	2026-09-15 09:55:00-05	Z000
164	205	Mialgia	Reposo e hidratación	2026-09-15 14:25:00-05	M791
165	206	Gastroenteritis aguda	\N	2026-09-15 14:55:00-05	A09X
168	209	Rinofaringitis aguda	Actividad física moderada	2026-09-15 08:55:00-05	J00X
169	210	Mialgia	Reposo e hidratación	2026-09-15 09:55:00-05	M791
172	213	Hipertensión arterial en control	Control en 8 días	2026-09-15 16:55:00-05	I10X
173	215	Rinitis alérgica	Evitar la automedicación	2026-09-15 16:55:00-05	J304
174	216	Síndrome febril	Dieta blanda por 3 días	2026-09-15 08:55:00-05	R509
264	328	Faringoamigdalitis	\N	2026-09-22 09:25:00-05	J029
175	217	Rinitis alérgica	Control en 8 días	2026-09-15 10:25:00-05	J304
176	218	Faringoamigdalitis	Reposo e hidratación	2026-09-15 11:25:00-05	J029
177	220	Gastritis	Evitar la automedicación	2026-09-15 14:55:00-05	K297
178	222	Rinofaringitis aguda	Actividad física moderada	2026-09-15 10:25:00-05	J00X
179	223	Faringoamigdalitis	\N	2026-09-15 17:25:00-05	J029
180	224	Diabetes mellitus tipo 2 en control	\N	2026-09-15 08:25:00-05	E119
181	225	Otitis media	Regresar si persisten los síntomas	2026-09-15 09:25:00-05	H669
182	226	Hipertensión arterial en control	Dieta blanda por 3 días	2026-09-15 09:55:00-05	I10X
183	228	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-09-15 17:55:00-05	J069
184	230	Rinofaringitis aguda	Reposo e hidratación	2026-09-16 15:55:00-05	J00X
185	231	Mialgia	Se ordenan exámenes de laboratorio	2026-09-16 14:25:00-05	M791
188	234	Otitis media	Actividad física moderada	2026-09-16 14:55:00-05	H669
189	235	Faringoamigdalitis	\N	2026-09-16 15:25:00-05	J029
190	236	Gastritis	Actividad física moderada	2026-09-16 17:55:00-05	K297
191	237	Mialgia	\N	2026-09-16 10:55:00-05	M791
192	238	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-09-16 17:25:00-05	J069
195	241	Gastritis	Control en 8 días	2026-09-16 15:55:00-05	K297
196	242	Hipertensión arterial en control	Reposo e hidratación	2026-09-16 16:25:00-05	I10X
198	245	Otitis media	\N	2026-09-16 15:55:00-05	H669
199	246	Síndrome febril	Regresar si persisten los síntomas	2026-09-16 08:25:00-05	R509
200	247	Control general sin hallazgos	Se ordenan exámenes de laboratorio	2026-09-16 16:25:00-05	Z000
201	248	Cefalea tensional	Actividad física moderada	2026-09-16 17:25:00-05	G442
202	250	Mialgia	Evitar la automedicación	2026-09-17 11:25:00-05	M791
203	251	Hipertensión arterial en control	Evitar la automedicación	2026-09-17 11:55:00-05	I10X
204	252	Gastritis	Evitar la automedicación	2026-09-17 14:25:00-05	K297
205	253	Gastroenteritis aguda	Se ordenan exámenes de laboratorio	2026-09-17 15:55:00-05	A09X
206	254	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-09-17 16:55:00-05	E119
207	255	Mialgia	Evitar la automedicación	2026-09-17 08:25:00-05	M791
208	256	Rinofaringitis aguda	Actividad física moderada	2026-09-17 10:55:00-05	J00X
211	259	Síndrome febril	\N	2026-09-17 10:25:00-05	R509
212	260	Hipertensión arterial en control	Actividad física moderada	2026-09-17 11:25:00-05	I10X
214	264	Cefalea tensional	Evitar la automedicación	2026-09-17 16:25:00-05	G442
215	266	Hipertensión arterial en control	Evitar la automedicación	2026-09-17 10:55:00-05	I10X
216	268	Rinofaringitis aguda	Reposo e hidratación	2026-09-17 11:55:00-05	J00X
217	269	Mialgia	Regresar si persisten los síntomas	2026-09-17 16:25:00-05	M791
218	270	Gastritis	Evitar la automedicación	2026-09-17 16:55:00-05	K297
219	271	Control general sin hallazgos	Actividad física moderada	2026-09-17 15:25:00-05	Z000
220	272	Síndrome febril	Dieta blanda por 3 días	2026-09-17 15:55:00-05	R509
221	273	Hipertensión arterial en control	Dieta blanda por 3 días	2026-09-17 16:55:00-05	I10X
222	274	Hipertensión arterial en control	Reposo e hidratación	2026-09-17 08:25:00-05	I10X
223	275	Rinofaringitis aguda	Actividad física moderada	2026-09-17 10:55:00-05	J00X
224	276	Hipertensión arterial en control	Se ordenan exámenes de laboratorio	2026-09-17 14:55:00-05	I10X
225	278	Rinitis alérgica	\N	2026-09-18 09:55:00-05	J304
226	279	Síndrome febril	Se ordenan exámenes de laboratorio	2026-09-18 10:25:00-05	R509
229	282	Diabetes mellitus tipo 2 en control	Dieta blanda por 3 días	2026-09-18 11:25:00-05	E119
230	283	Hipertensión arterial en control	Control en 8 días	2026-09-18 14:55:00-05	I10X
231	284	Control general sin hallazgos	\N	2026-09-18 15:55:00-05	Z000
233	286	Otitis media	Regresar si persisten los síntomas	2026-09-18 17:25:00-05	H669
234	287	Otitis media	Dieta blanda por 3 días	2026-09-18 10:25:00-05	H669
235	289	Rinofaringitis aguda	\N	2026-09-18 17:25:00-05	J00X
237	291	Control general sin hallazgos	\N	2026-09-18 15:55:00-05	Z000
239	293	Otitis media	\N	2026-09-18 14:25:00-05	H669
240	294	Gastritis	Regresar si persisten los síntomas	2026-09-18 14:55:00-05	K297
242	297	Infección respiratoria aguda	Reposo e hidratación	2026-09-18 15:25:00-05	J069
244	301	Gastritis	Se ordenan exámenes de laboratorio	2026-09-18 14:25:00-05	K297
245	302	Cefalea tensional	Actividad física moderada	2026-09-18 15:55:00-05	G442
247	305	Gastroenteritis aguda	Regresar si persisten los síntomas	2026-09-21 14:25:00-05	A09X
248	306	Infección respiratoria aguda	Actividad física moderada	2026-09-21 14:55:00-05	J069
249	308	Gastritis	Actividad física moderada	2026-09-21 09:55:00-05	K297
250	309	Gastroenteritis aguda	Regresar si persisten los síntomas	2026-09-21 11:55:00-05	A09X
251	310	Síndrome febril	Actividad física moderada	2026-09-21 14:55:00-05	R509
253	312	Infección respiratoria aguda	\N	2026-09-21 17:25:00-05	J069
255	315	Síndrome febril	Evitar la automedicación	2026-09-21 15:25:00-05	R509
257	320	Cefalea tensional	Regresar si persisten los síntomas	2026-09-21 15:55:00-05	G442
258	321	Gastroenteritis aguda	Se ordenan exámenes de laboratorio	2026-09-21 08:25:00-05	A09X
259	322	Control general sin hallazgos	Reposo e hidratación	2026-09-21 15:55:00-05	Z000
260	323	Diabetes mellitus tipo 2 en control	Dieta blanda por 3 días	2026-09-21 16:55:00-05	E119
261	325	Control general sin hallazgos	Evitar la automedicación	2026-09-21 11:55:00-05	Z000
263	327	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-22 08:55:00-05	J029
265	329	Gastritis	\N	2026-09-22 11:25:00-05	K297
266	330	Otitis media	\N	2026-09-22 11:55:00-05	H669
267	331	Mialgia	Evitar la automedicación	2026-09-22 11:55:00-05	M791
269	334	Otitis media	Evitar la automedicación	2026-09-22 09:55:00-05	H669
270	335	Infección respiratoria aguda	Dieta blanda por 3 días	2026-09-22 10:25:00-05	J069
271	338	Infección respiratoria aguda	Evitar la automedicación	2026-09-22 11:25:00-05	J069
273	341	Faringoamigdalitis	\N	2026-09-22 11:25:00-05	J029
274	342	Gastroenteritis aguda	Dieta blanda por 3 días	2026-09-22 15:25:00-05	A09X
275	343	Infección respiratoria aguda	Evitar la automedicación	2026-09-22 16:25:00-05	J069
276	344	Faringoamigdalitis	Control en 8 días	2026-09-22 16:55:00-05	J029
277	345	Control general sin hallazgos	\N	2026-09-22 17:25:00-05	Z000
278	347	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-09-22 11:25:00-05	E119
279	348	Gastritis	Regresar si persisten los síntomas	2026-09-22 14:55:00-05	K297
280	349	Hipertensión arterial en control	Se ordenan exámenes de laboratorio	2026-09-22 08:25:00-05	I10X
281	352	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-09-22 10:25:00-05	J069
282	354	Cefalea tensional	Reposo e hidratación	2026-09-22 11:55:00-05	G442
283	355	Cefalea tensional	\N	2026-09-23 10:25:00-05	G442
284	356	Cefalea tensional	Control en 8 días	2026-09-23 14:25:00-05	G442
285	357	Rinitis alérgica	\N	2026-09-23 17:55:00-05	J304
288	360	Gastroenteritis aguda	\N	2026-09-23 17:55:00-05	A09X
289	361	Gastritis	\N	2026-09-23 09:55:00-05	K297
290	362	Mialgia	Regresar si persisten los síntomas	2026-09-23 11:55:00-05	M791
291	363	Síndrome febril	Dieta blanda por 3 días	2026-09-23 17:55:00-05	R509
292	364	Rinofaringitis aguda	\N	2026-09-23 11:25:00-05	J00X
293	365	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-09-23 14:25:00-05	J00X
296	369	Gastritis	Evitar la automedicación	2026-09-23 10:55:00-05	K297
297	370	Síndrome febril	\N	2026-09-23 11:25:00-05	R509
298	371	Síndrome febril	\N	2026-09-23 14:25:00-05	R509
299	372	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-09-23 14:55:00-05	J00X
301	374	Faringoamigdalitis	Control en 8 días	2026-09-23 11:25:00-05	J029
302	375	Hipertensión arterial en control	Se ordenan exámenes de laboratorio	2026-09-23 10:25:00-05	I10X
303	376	Gastritis	Actividad física moderada	2026-09-23 11:25:00-05	K297
304	377	Rinitis alérgica	Dieta blanda por 3 días	2026-09-23 16:55:00-05	J304
305	378	Control general sin hallazgos	\N	2026-09-23 17:25:00-05	Z000
306	379	Otitis media	\N	2026-09-24 15:55:00-05	H669
307	381	Síndrome febril	Regresar si persisten los síntomas	2026-09-24 17:25:00-05	R509
308	383	Cefalea tensional	Dieta blanda por 3 días	2026-09-24 11:25:00-05	G442
309	384	Hipertensión arterial en control	Se ordenan exámenes de laboratorio	2026-09-24 16:55:00-05	I10X
310	385	Diabetes mellitus tipo 2 en control	Actividad física moderada	2026-09-24 17:55:00-05	E119
312	387	Gastroenteritis aguda	Control en 8 días	2026-09-24 08:55:00-05	A09X
313	388	Cefalea tensional	Dieta blanda por 3 días	2026-09-24 16:55:00-05	G442
314	389	Control general sin hallazgos	Reposo e hidratación	2026-09-24 08:25:00-05	Z000
315	390	Rinitis alérgica	Reposo e hidratación	2026-09-24 09:25:00-05	J304
316	391	Hipertensión arterial en control	Dieta blanda por 3 días	2026-09-24 10:25:00-05	I10X
317	392	Control general sin hallazgos	\N	2026-09-24 16:25:00-05	Z000
286	358	Mialgia	\N	2026-09-23 16:25:00-05	M791
318	393	Cefalea tensional	Control en 8 días	2026-09-24 09:25:00-05	G442
319	394	Hipertensión arterial en control	\N	2026-09-24 10:55:00-05	I10X
322	397	Control general sin hallazgos	Evitar la automedicación	2026-09-25 08:55:00-05	Z000
323	398	Rinitis alérgica	\N	2026-09-25 16:55:00-05	J304
324	399	Otitis media	\N	2026-09-25 08:25:00-05	H669
326	401	Síndrome febril	\N	2026-09-25 15:25:00-05	R509
328	403	Cefalea tensional	\N	2026-09-25 08:25:00-05	G442
329	404	Cefalea tensional	Control en 8 días	2026-09-25 08:55:00-05	G442
330	405	Diabetes mellitus tipo 2 en control	Dieta blanda por 3 días	2026-09-25 15:25:00-05	E119
331	406	Control general sin hallazgos	\N	2026-09-25 17:25:00-05	Z000
332	407	Gastroenteritis aguda	Actividad física moderada	2026-09-25 09:25:00-05	A09X
334	410	Rinitis alérgica	Regresar si persisten los síntomas	2026-09-25 08:55:00-05	J304
335	411	Hipertensión arterial en control	\N	2026-09-25 15:55:00-05	I10X
336	413	Rinitis alérgica	Reposo e hidratación	2026-09-25 17:55:00-05	J304
337	415	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-09-25 11:55:00-05	E119
338	417	Faringoamigdalitis	Dieta blanda por 3 días	2026-09-25 08:25:00-05	J029
339	419	Gastroenteritis aguda	Se ordenan exámenes de laboratorio	2026-09-25 11:55:00-05	A09X
340	420	Gastroenteritis aguda	Reposo e hidratación	2026-09-25 14:55:00-05	A09X
341	421	Síndrome febril	Se ordenan exámenes de laboratorio	2026-09-25 15:25:00-05	R509
342	422	Cefalea tensional	\N	2026-09-25 16:25:00-05	G442
343	423	Diabetes mellitus tipo 2 en control	\N	2026-09-25 08:25:00-05	E119
344	425	Cefalea tensional	Se ordenan exámenes de laboratorio	2026-09-25 11:55:00-05	G442
345	429	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-09-28 15:25:00-05	E119
346	430	Diabetes mellitus tipo 2 en control	Control en 8 días	2026-09-28 16:55:00-05	E119
349	433	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-09-28 11:55:00-05	J00X
350	434	Gastroenteritis aguda	Evitar la automedicación	2026-09-28 14:25:00-05	A09X
351	435	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-28 15:25:00-05	J029
352	436	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-09-28 16:55:00-05	E119
353	437	Diabetes mellitus tipo 2 en control	Reposo e hidratación	2026-09-28 08:25:00-05	E119
354	438	Rinitis alérgica	Dieta blanda por 3 días	2026-09-28 09:55:00-05	J304
355	439	Gastroenteritis aguda	Actividad física moderada	2026-09-28 16:55:00-05	A09X
356	440	Mialgia	Evitar la automedicación	2026-09-28 17:25:00-05	M791
357	441	Diabetes mellitus tipo 2 en control	\N	2026-09-28 14:25:00-05	E119
358	442	Diabetes mellitus tipo 2 en control	\N	2026-09-28 15:25:00-05	E119
359	443	Otitis media	Se ordenan exámenes de laboratorio	2026-09-28 15:55:00-05	H669
360	445	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-28 10:55:00-05	J029
361	446	Control general sin hallazgos	Reposo e hidratación	2026-09-28 15:55:00-05	Z000
362	448	Rinitis alérgica	Se ordenan exámenes de laboratorio	2026-09-28 09:55:00-05	J304
364	450	Control general sin hallazgos	Reposo e hidratación	2026-09-28 11:25:00-05	Z000
365	451	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-09-28 11:55:00-05	J00X
366	452	Control general sin hallazgos	Actividad física moderada	2026-09-29 09:25:00-05	Z000
368	454	Control general sin hallazgos	Actividad física moderada	2026-09-29 10:55:00-05	Z000
369	455	Mialgia	Evitar la automedicación	2026-09-29 11:25:00-05	M791
370	456	Mialgia	Reposo e hidratación	2026-09-29 14:55:00-05	M791
371	457	Hipertensión arterial en control	Actividad física moderada	2026-09-29 08:25:00-05	I10X
372	458	Gastroenteritis aguda	Control en 8 días	2026-09-29 10:55:00-05	A09X
373	459	Gastritis	Regresar si persisten los síntomas	2026-09-29 14:55:00-05	K297
374	460	Cefalea tensional	Regresar si persisten los síntomas	2026-09-29 16:55:00-05	G442
375	461	Otitis media	\N	2026-09-29 17:55:00-05	H669
376	462	Mialgia	\N	2026-09-29 17:55:00-05	M791
377	463	Rinitis alérgica	Actividad física moderada	2026-09-29 09:25:00-05	J304
378	464	Mialgia	Actividad física moderada	2026-09-29 09:55:00-05	M791
379	465	Cefalea tensional	Control en 8 días	2026-09-29 14:25:00-05	G442
380	466	Gastritis	\N	2026-09-29 14:25:00-05	K297
381	467	Faringoamigdalitis	Dieta blanda por 3 días	2026-09-29 16:25:00-05	J029
382	468	Cefalea tensional	\N	2026-09-29 08:55:00-05	G442
384	470	Rinitis alérgica	Reposo e hidratación	2026-09-29 17:25:00-05	J304
387	473	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-29 10:55:00-05	J029
388	474	Otitis media	\N	2026-09-29 16:25:00-05	H669
389	475	Rinofaringitis aguda	Evitar la automedicación	2026-09-29 08:25:00-05	J00X
390	476	Gastritis	Actividad física moderada	2026-09-29 10:25:00-05	K297
392	478	Rinofaringitis aguda	\N	2026-09-29 16:25:00-05	J00X
393	480	Síndrome febril	\N	2026-09-30 08:55:00-05	R509
394	481	Gastritis	Dieta blanda por 3 días	2026-09-30 10:55:00-05	K297
395	482	Diabetes mellitus tipo 2 en control	Dieta blanda por 3 días	2026-09-30 11:55:00-05	E119
396	484	Control general sin hallazgos	Se ordenan exámenes de laboratorio	2026-09-30 17:25:00-05	Z000
398	487	Rinofaringitis aguda	Actividad física moderada	2026-09-30 16:25:00-05	J00X
399	488	Rinitis alérgica	\N	2026-09-30 08:55:00-05	J304
400	489	Rinofaringitis aguda	Control en 8 días	2026-09-30 15:55:00-05	J00X
401	490	Gastroenteritis aguda	Actividad física moderada	2026-09-30 16:55:00-05	A09X
402	491	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-09-30 17:55:00-05	E119
403	492	Cefalea tensional	\N	2026-09-30 09:55:00-05	G442
405	494	Control general sin hallazgos	Regresar si persisten los síntomas	2026-09-30 16:55:00-05	Z000
406	495	Cefalea tensional	Regresar si persisten los síntomas	2026-09-30 08:25:00-05	G442
407	497	Gastroenteritis aguda	\N	2026-09-30 10:25:00-05	A09X
408	498	Faringoamigdalitis	\N	2026-09-30 14:55:00-05	J029
409	500	Rinofaringitis aguda	\N	2026-09-30 11:55:00-05	J00X
410	503	Otitis media	Se ordenan exámenes de laboratorio	2026-09-30 15:55:00-05	H669
411	504	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-09-30 16:25:00-05	E119
412	505	Hipertensión arterial en control	Regresar si persisten los síntomas	2026-09-30 16:55:00-05	I10X
413	507	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-30 11:25:00-05	J029
415	509	Gastroenteritis aguda	\N	2026-10-01 08:55:00-05	A09X
416	510	Cefalea tensional	Evitar la automedicación	2026-10-01 11:25:00-05	G442
417	512	Mialgia	\N	2026-10-01 15:25:00-05	M791
419	515	Rinofaringitis aguda	Reposo e hidratación	2026-10-01 10:55:00-05	J00X
420	519	Control general sin hallazgos	Evitar la automedicación	2026-10-01 11:25:00-05	Z000
421	520	Control general sin hallazgos	Control en 8 días	2026-10-01 15:25:00-05	Z000
423	522	Rinofaringitis aguda	\N	2026-10-01 17:55:00-05	J00X
425	525	Gastroenteritis aguda	Se ordenan exámenes de laboratorio	2026-10-01 16:55:00-05	A09X
426	526	Faringoamigdalitis	Dieta blanda por 3 días	2026-10-01 08:55:00-05	J029
427	527	Rinofaringitis aguda	Reposo e hidratación	2026-10-01 10:55:00-05	J00X
428	528	Mialgia	Control en 8 días	2026-10-01 11:25:00-05	M791
429	530	Gastroenteritis aguda	Se ordenan exámenes de laboratorio	2026-10-01 14:25:00-05	A09X
430	531	Gastritis	Dieta blanda por 3 días	2026-10-01 15:55:00-05	K297
432	536	Gastritis	Reposo e hidratación	2026-10-01 17:25:00-05	K297
433	537	Otitis media	Regresar si persisten los síntomas	2026-10-02 08:55:00-05	H669
434	539	Faringoamigdalitis	Control en 8 días	2026-10-02 08:25:00-05	J029
435	540	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-10-02 11:25:00-05	E119
436	541	Cefalea tensional	Regresar si persisten los síntomas	2026-10-02 16:55:00-05	G442
437	542	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-10-02 09:25:00-05	J00X
438	544	Gastroenteritis aguda	Dieta blanda por 3 días	2026-10-02 08:55:00-05	A09X
439	545	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-10-02 10:25:00-05	E119
440	546	Hipertensión arterial en control	\N	2026-10-02 14:55:00-05	I10X
441	547	Cefalea tensional	\N	2026-10-02 11:55:00-05	G442
442	548	Cefalea tensional	Evitar la automedicación	2026-10-02 15:25:00-05	G442
445	552	Mialgia	Actividad física moderada	2026-10-02 17:55:00-05	M791
446	553	Gastritis	Dieta blanda por 3 días	2026-10-02 08:55:00-05	K297
447	554	Otitis media	Actividad física moderada	2026-10-02 15:25:00-05	H669
448	558	Otitis media	Dieta blanda por 3 días	2026-10-02 10:55:00-05	H669
449	559	Faringoamigdalitis	Actividad física moderada	2026-10-02 15:25:00-05	J029
451	561	Gastritis	Se ordenan exámenes de laboratorio	2026-10-05 10:25:00-05	K297
452	562	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-10-05 14:25:00-05	J069
453	566	Control general sin hallazgos	Actividad física moderada	2026-10-05 11:55:00-05	Z000
454	567	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-10-05 14:55:00-05	E119
455	568	Diabetes mellitus tipo 2 en control	\N	2026-10-05 15:55:00-05	E119
457	570	Diabetes mellitus tipo 2 en control	Reposo e hidratación	2026-10-05 10:55:00-05	E119
458	571	Gastroenteritis aguda	\N	2026-10-05 16:55:00-05	A09X
460	573	Rinofaringitis aguda	Reposo e hidratación	2026-10-05 09:55:00-05	J00X
461	574	Diabetes mellitus tipo 2 en control	Actividad física moderada	2026-10-05 10:55:00-05	E119
462	575	Infección respiratoria aguda	\N	2026-10-05 17:55:00-05	J069
463	576	Hipertensión arterial en control	Control en 8 días	2026-10-05 11:55:00-05	I10X
464	577	Gastroenteritis aguda	Actividad física moderada	2026-10-05 09:55:00-05	A09X
465	578	Síndrome febril	\N	2026-10-05 14:55:00-05	R509
466	579	Rinitis alérgica	Control en 8 días	2026-10-05 15:25:00-05	J304
467	580	Infección respiratoria aguda	Dieta blanda por 3 días	2026-10-05 08:55:00-05	J069
468	581	Hipertensión arterial en control	Actividad física moderada	2026-10-05 10:55:00-05	I10X
470	585	Otitis media	Se ordenan exámenes de laboratorio	2026-10-06 08:25:00-05	H669
471	586	Gastritis	Actividad física moderada	2026-10-06 10:25:00-05	K297
472	587	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-10-06 10:55:00-05	E119
474	589	Gastritis	Dieta blanda por 3 días	2026-10-06 16:55:00-05	K297
475	590	Diabetes mellitus tipo 2 en control	Evitar la automedicación	2026-10-06 08:25:00-05	E119
477	594	Infección respiratoria aguda	Evitar la automedicación	2026-10-06 17:25:00-05	J069
480	598	Rinitis alérgica	\N	2026-10-06 15:25:00-05	J304
481	599	Gastroenteritis aguda	Evitar la automedicación	2026-10-06 16:55:00-05	A09X
483	601	Hipertensión arterial en control	Dieta blanda por 3 días	2026-10-06 09:25:00-05	I10X
484	602	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-10-06 10:55:00-05	J069
485	603	Gastroenteritis aguda	Evitar la automedicación	2026-10-06 15:55:00-05	A09X
486	605	Infección respiratoria aguda	Evitar la automedicación	2026-10-07 15:25:00-05	J069
487	606	Infección respiratoria aguda	Evitar la automedicación	2026-10-07 16:25:00-05	J069
488	607	Diabetes mellitus tipo 2 en control	Dieta blanda por 3 días	2026-10-07 17:25:00-05	E119
489	608	Rinitis alérgica	Reposo e hidratación	2026-10-07 11:25:00-05	J304
490	609	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-10-07 15:55:00-05	J00X
491	610	Cefalea tensional	Control en 8 días	2026-10-07 16:55:00-05	G442
492	614	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-10-07 17:25:00-05	E119
497	619	Rinofaringitis aguda	Actividad física moderada	2026-10-07 16:55:00-05	J00X
498	623	Rinofaringitis aguda	Control en 8 días	2026-10-07 11:55:00-05	J00X
499	624	Síndrome febril	\N	2026-10-07 14:25:00-05	R509
500	625	Control general sin hallazgos	Control en 8 días	2026-10-07 14:55:00-05	Z000
501	626	Control general sin hallazgos	Regresar si persisten los síntomas	2026-10-08 08:55:00-05	Z000
502	627	Gastroenteritis aguda	\N	2026-10-08 09:25:00-05	A09X
503	628	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-10-08 08:25:00-05	E119
504	629	Hipertensión arterial en control	\N	2026-10-08 08:55:00-05	I10X
505	630	Rinofaringitis aguda	Actividad física moderada	2026-10-08 09:25:00-05	J00X
506	631	Gastritis	Dieta blanda por 3 días	2026-10-08 10:55:00-05	K297
507	632	Cefalea tensional	Regresar si persisten los síntomas	2026-10-08 17:55:00-05	G442
508	633	Diabetes mellitus tipo 2 en control	Reposo e hidratación	2026-10-08 11:55:00-05	E119
509	634	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-10-08 17:25:00-05	E119
510	635	Infección respiratoria aguda	Actividad física moderada	2026-10-08 17:55:00-05	J069
511	636	Gastroenteritis aguda	Regresar si persisten los síntomas	2026-10-08 11:55:00-05	A09X
512	637	Faringoamigdalitis	\N	2026-10-08 15:25:00-05	J029
513	638	Gastritis	Dieta blanda por 3 días	2026-10-08 09:25:00-05	K297
514	639	Hipertensión arterial en control	Reposo e hidratación	2026-10-08 14:55:00-05	I10X
516	641	Rinitis alérgica	\N	2026-10-08 17:25:00-05	J304
517	642	Síndrome febril	\N	2026-10-08 09:25:00-05	R509
518	644	Otitis media	Reposo e hidratación	2026-10-08 17:55:00-05	H669
519	645	Cefalea tensional	Actividad física moderada	2026-10-08 10:55:00-05	G442
521	647	Síndrome febril	\N	2026-10-08 15:55:00-05	R509
522	648	Hipertensión arterial en control	Evitar la automedicación	2026-10-09 17:25:00-05	I10X
523	649	Hipertensión arterial en control	\N	2026-10-09 11:25:00-05	I10X
524	650	Gastritis	Reposo e hidratación	2026-10-09 11:55:00-05	K297
525	651	Cefalea tensional	Actividad física moderada	2026-10-09 14:25:00-05	G442
526	652	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-10-09 15:55:00-05	E119
527	653	Cefalea tensional	Evitar la automedicación	2026-10-09 16:25:00-05	G442
529	655	Síndrome febril	Actividad física moderada	2026-10-09 08:55:00-05	R509
530	657	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-10-09 09:55:00-05	J00X
531	658	Rinitis alérgica	Dieta blanda por 3 días	2026-10-09 10:25:00-05	J304
532	659	Cefalea tensional	Actividad física moderada	2026-10-09 11:55:00-05	G442
533	660	Rinitis alérgica	\N	2026-10-09 15:55:00-05	J304
534	661	Gastritis	Se ordenan exámenes de laboratorio	2026-10-09 17:55:00-05	K297
536	665	Gastritis	\N	2026-10-09 10:55:00-05	K297
537	667	Otitis media	\N	2026-10-12 08:55:00-05	H669
538	670	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-10-12 08:55:00-05	J069
539	671	Control general sin hallazgos	\N	2026-10-12 09:25:00-05	Z000
540	672	Faringoamigdalitis	Reposo e hidratación	2026-10-12 15:25:00-05	J029
541	673	Otitis media	Actividad física moderada	2026-10-12 09:25:00-05	H669
542	674	Infección respiratoria aguda	\N	2026-10-12 14:55:00-05	J069
544	677	Otitis media	Evitar la automedicación	2026-10-12 08:55:00-05	H669
545	679	Infección respiratoria aguda	\N	2026-10-12 09:55:00-05	J069
546	680	Hipertensión arterial en control	Reposo e hidratación	2026-10-12 10:55:00-05	I10X
547	681	Otitis media	Evitar la automedicación	2026-10-12 10:25:00-05	H669
548	682	Faringoamigdalitis	Reposo e hidratación	2026-10-12 15:55:00-05	J029
549	683	Diabetes mellitus tipo 2 en control	Evitar la automedicación	2026-10-12 16:55:00-05	E119
550	684	Control general sin hallazgos	Control en 8 días	2026-10-12 17:25:00-05	Z000
551	685	Diabetes mellitus tipo 2 en control	Actividad física moderada	2026-10-12 08:25:00-05	E119
552	687	Rinitis alérgica	Se ordenan exámenes de laboratorio	2026-10-12 11:25:00-05	J304
553	688	Cefalea tensional	Reposo e hidratación	2026-10-12 11:55:00-05	G442
554	689	Otitis media	Dieta blanda por 3 días	2026-10-12 17:55:00-05	H669
555	690	Síndrome febril	Evitar la automedicación	2026-10-13 08:55:00-05	R509
556	691	Diabetes mellitus tipo 2 en control	Regresar si persisten los síntomas	2026-10-13 10:55:00-05	E119
557	692	Otitis media	Se ordenan exámenes de laboratorio	2026-10-13 15:55:00-05	H669
558	693	Rinitis alérgica	Evitar la automedicación	2026-10-13 09:25:00-05	J304
559	694	Otitis media	Dieta blanda por 3 días	2026-10-13 09:55:00-05	H669
560	695	Síndrome febril	Reposo e hidratación	2026-10-13 10:55:00-05	R509
561	696	Gastroenteritis aguda	Evitar la automedicación	2026-10-13 11:25:00-05	A09X
562	697	Hipertensión arterial en control	Regresar si persisten los síntomas	2026-10-13 11:55:00-05	I10X
563	700	Cefalea tensional	Reposo e hidratación	2026-10-13 16:55:00-05	G442
564	701	Rinofaringitis aguda	Reposo e hidratación	2026-10-13 14:25:00-05	J00X
565	702	Diabetes mellitus tipo 2 en control	Evitar la automedicación	2026-10-13 08:55:00-05	E119
566	703	Faringoamigdalitis	Control en 8 días	2026-10-13 11:55:00-05	J029
567	704	Faringoamigdalitis	Se ordenan exámenes de laboratorio	2026-10-13 14:55:00-05	J029
568	706	Síndrome febril	Evitar la automedicación	2026-10-13 08:25:00-05	R509
569	707	Rinitis alérgica	Regresar si persisten los síntomas	2026-10-13 08:55:00-05	J304
570	708	Rinitis alérgica	Evitar la automedicación	2026-10-13 10:25:00-05	J304
571	710	Síndrome febril	\N	2026-10-13 16:25:00-05	R509
572	711	Rinitis alérgica	\N	2026-10-13 08:25:00-05	J304
573	713	Otitis media	Reposo e hidratación	2026-10-13 14:25:00-05	H669
574	715	Rinitis alérgica	Evitar la automedicación	2026-10-13 14:55:00-05	J304
575	716	Faringoamigdalitis	Regresar si persisten los síntomas	2026-10-13 15:25:00-05	J029
576	718	Cefalea tensional	\N	2026-10-14 14:55:00-05	G442
577	719	Hipertensión arterial en control	Dieta blanda por 3 días	2026-10-14 16:25:00-05	I10X
579	721	Otitis media	Se ordenan exámenes de laboratorio	2026-10-14 08:55:00-05	H669
580	723	Diabetes mellitus tipo 2 en control	Control en 8 días	2026-10-14 15:55:00-05	E119
581	724	Rinitis alérgica	Actividad física moderada	2026-10-14 10:25:00-05	J304
583	727	Cefalea tensional	Control en 8 días	2026-10-14 08:55:00-05	G442
584	728	Síndrome febril	Control en 8 días	2026-10-14 09:55:00-05	R509
585	729	Mialgia	Reposo e hidratación	2026-10-14 14:25:00-05	M791
587	731	Mialgia	\N	2026-10-14 08:55:00-05	M791
588	732	Otitis media	Regresar si persisten los síntomas	2026-10-14 15:55:00-05	H669
590	737	Gastritis	Dieta blanda por 3 días	2026-10-14 17:25:00-05	K297
591	738	Rinofaringitis aguda	Regresar si persisten los síntomas	2026-10-14 08:55:00-05	J00X
592	739	Rinofaringitis aguda	Actividad física moderada	2026-10-14 15:25:00-05	J00X
593	740	Control general sin hallazgos	\N	2026-10-14 17:55:00-05	Z000
596	744	Mialgia	Actividad física moderada	2026-10-15 16:55:00-05	M791
597	745	Rinofaringitis aguda	Se ordenan exámenes de laboratorio	2026-10-15 17:25:00-05	J00X
599	747	Gastroenteritis aguda	Regresar si persisten los síntomas	2026-10-15 08:25:00-05	A09X
602	750	Mialgia	Actividad física moderada	2026-10-15 11:25:00-05	M791
603	751	Otitis media	Regresar si persisten los síntomas	2026-10-15 15:25:00-05	H669
604	752	Otitis media	Dieta blanda por 3 días	2026-10-15 16:25:00-05	H669
605	753	Otitis media	Dieta blanda por 3 días	2026-10-15 17:55:00-05	H669
606	755	Síndrome febril	Actividad física moderada	2026-10-15 10:55:00-05	R509
607	756	Gastroenteritis aguda	Se ordenan exámenes de laboratorio	2026-10-15 11:55:00-05	A09X
608	758	Diabetes mellitus tipo 2 en control	Se ordenan exámenes de laboratorio	2026-10-15 16:55:00-05	E119
609	759	Hipertensión arterial en control	Reposo e hidratación	2026-10-15 08:55:00-05	I10X
610	760	Infección respiratoria aguda	Evitar la automedicación	2026-10-15 09:55:00-05	J069
611	761	Gastritis	Regresar si persisten los síntomas	2026-10-15 10:25:00-05	K297
612	763	Rinofaringitis aguda	\N	2026-10-15 15:55:00-05	J00X
613	765	Síndrome febril	Dieta blanda por 3 días	2026-10-15 14:25:00-05	R509
615	767	Mialgia	Dieta blanda por 3 días	2026-10-15 10:25:00-05	M791
616	768	Gastroenteritis aguda	Actividad física moderada	2026-10-15 11:25:00-05	A09X
617	769	Gastroenteritis aguda	\N	2026-10-15 16:55:00-05	A09X
618	770	Síndrome febril	Actividad física moderada	2026-10-15 10:55:00-05	R509
619	771	Síndrome febril	Dieta blanda por 3 días	2026-10-15 14:55:00-05	R509
620	772	Rinitis alérgica	Actividad física moderada	2026-10-15 16:55:00-05	J304
621	773	Rinitis alérgica	Evitar la automedicación	2026-10-15 17:55:00-05	J304
622	774	Cefalea tensional	Dieta blanda por 3 días	2026-10-16 08:25:00-05	G442
642	802	Síndrome febril	\N	2026-10-19 08:23:56.760768-05	R509
4	10	Mialgia	Dieta blanda por 3 días	2026-09-04 10:25:00-05	M791
5	11	Rinitis alérgica	Regresar si persisten los síntomas	2026-09-04 10:55:00-05	J304
7	13	Síndrome febril	\N	2026-09-04 08:55:00-05	R509
8	14	Cefalea tensional	Evitar la automedicación	2026-09-04 10:25:00-05	G442
9	15	Control general sin hallazgos	Regresar si persisten los síntomas	2026-09-04 10:55:00-05	Z000
10	16	Faringoamigdalitis	Regresar si persisten los síntomas	2026-09-04 11:25:00-05	J029
11	17	Gastritis	Dieta blanda por 3 días	2026-09-04 08:25:00-05	K297
12	18	Otitis media	Reposo e hidratación	2026-09-04 10:55:00-05	H669
13	20	Infección respiratoria aguda	\N	2026-09-04 14:55:00-05	J069
6	12	Infección de vías urinarias	Reposo e hidratación	2026-09-04 11:25:00-05	\N
16	23	Dermatitis alérgica	Actividad física moderada	2026-09-04 16:25:00-05	\N
19	26	Dermatitis alérgica	Evitar la automedicación	2026-09-04 09:55:00-05	\N
20	27	Infección de vías urinarias	Dieta blanda por 3 días	2026-09-04 10:55:00-05	\N
21	28	Infección de vías urinarias	Dieta blanda por 3 días	2026-09-04 14:25:00-05	\N
30	45	Dermatitis alérgica	Reposo e hidratación	2026-09-04 10:25:00-05	\N
33	48	Dermatitis alérgica	Se ordenan exámenes de laboratorio	2026-09-07 08:25:00-05	\N
66	90	Dermatitis alérgica	\N	2026-09-08 11:25:00-05	\N
68	92	Lumbalgia mecánica	Evitar la automedicación	2026-09-08 17:55:00-05	\N
77	102	Infección de vías urinarias	Control en 8 días	2026-09-09 17:55:00-05	\N
81	107	Infección de vías urinarias	Reposo e hidratación	2026-09-09 09:25:00-05	\N
88	115	Infección de vías urinarias	Dieta blanda por 3 días	2026-09-09 16:55:00-05	\N
91	119	Dermatitis alérgica	\N	2026-09-09 14:55:00-05	\N
97	125	Infección de vías urinarias	\N	2026-09-10 14:25:00-05	\N
102	130	Lumbalgia mecánica	\N	2026-09-10 14:55:00-05	\N
113	143	Infección de vías urinarias	Evitar la automedicación	2026-09-10 10:25:00-05	\N
117	147	Lumbalgia mecánica	\N	2026-09-10 09:25:00-05	\N
118	148	Infección de vías urinarias	Dieta blanda por 3 días	2026-09-10 09:55:00-05	\N
121	151	Lumbalgia mecánica	\N	2026-09-10 11:55:00-05	\N
123	153	Dermatitis alérgica	Control en 8 días	2026-09-11 11:25:00-05	\N
127	159	Lumbalgia mecánica	Dieta blanda por 3 días	2026-09-11 10:25:00-05	\N
136	170	Lumbalgia mecánica	Control en 8 días	2026-09-11 09:55:00-05	\N
146	181	Infección de vías urinarias	\N	2026-09-14 10:25:00-05	\N
149	189	Infección de vías urinarias	Reposo e hidratación	2026-09-14 17:25:00-05	\N
151	191	Dermatitis alérgica	Control en 8 días	2026-09-14 15:25:00-05	\N
155	195	Lumbalgia mecánica	Reposo e hidratación	2026-09-14 08:25:00-05	\N
160	200	Dermatitis alérgica	\N	2026-09-15 10:25:00-05	\N
166	207	Dermatitis alérgica	\N	2026-09-15 16:25:00-05	\N
167	208	Dermatitis alérgica	Dieta blanda por 3 días	2026-09-15 17:25:00-05	\N
170	211	Infección de vías urinarias	Evitar la automedicación	2026-09-15 10:55:00-05	\N
171	212	Infección de vías urinarias	Regresar si persisten los síntomas	2026-09-15 14:25:00-05	\N
186	232	Lumbalgia mecánica	\N	2026-09-16 08:55:00-05	\N
187	233	Infección de vías urinarias	Control en 8 días	2026-09-16 09:55:00-05	\N
193	239	Dermatitis alérgica	Evitar la automedicación	2026-09-16 10:25:00-05	\N
194	240	Lumbalgia mecánica	Reposo e hidratación	2026-09-16 14:25:00-05	\N
197	243	Infección de vías urinarias	Evitar la automedicación	2026-09-16 16:55:00-05	\N
209	257	Lumbalgia mecánica	Control en 8 días	2026-09-17 14:55:00-05	\N
210	258	Lumbalgia mecánica	\N	2026-09-17 09:25:00-05	\N
213	262	Dermatitis alérgica	Dieta blanda por 3 días	2026-09-17 17:55:00-05	\N
227	280	Lumbalgia mecánica	Se ordenan exámenes de laboratorio	2026-09-18 14:25:00-05	\N
228	281	Infección de vías urinarias	\N	2026-09-18 15:55:00-05	\N
232	285	Lumbalgia mecánica	Regresar si persisten los síntomas	2026-09-18 16:25:00-05	\N
236	290	Lumbalgia mecánica	\N	2026-09-18 10:55:00-05	\N
238	292	Dermatitis alérgica	Dieta blanda por 3 días	2026-09-18 11:25:00-05	\N
241	295	Dermatitis alérgica	Actividad física moderada	2026-09-18 16:25:00-05	\N
243	298	Lumbalgia mecánica	\N	2026-09-18 09:25:00-05	\N
246	303	Lumbalgia mecánica	\N	2026-09-18 16:25:00-05	\N
252	311	Infección de vías urinarias	Evitar la automedicación	2026-09-21 16:25:00-05	\N
254	313	Dermatitis alérgica	Se ordenan exámenes de laboratorio	2026-09-21 08:25:00-05	\N
256	318	Infección de vías urinarias	\N	2026-09-21 16:55:00-05	\N
262	326	Lumbalgia mecánica	Regresar si persisten los síntomas	2026-09-21 10:25:00-05	\N
268	333	Lumbalgia mecánica	Control en 8 días	2026-09-22 17:25:00-05	\N
272	340	Infección de vías urinarias	Actividad física moderada	2026-09-22 08:25:00-05	\N
287	359	Dermatitis alérgica	Evitar la automedicación	2026-09-23 17:25:00-05	\N
294	367	Infección de vías urinarias	Regresar si persisten los síntomas	2026-09-23 08:25:00-05	\N
295	368	Dermatitis alérgica	Dieta blanda por 3 días	2026-09-23 09:55:00-05	\N
300	373	Dermatitis alérgica	Evitar la automedicación	2026-09-23 15:25:00-05	\N
311	386	Dermatitis alérgica	Evitar la automedicación	2026-09-24 08:25:00-05	\N
320	395	Lumbalgia mecánica	Regresar si persisten los síntomas	2026-09-24 14:25:00-05	\N
321	396	Lumbalgia mecánica	Evitar la automedicación	2026-09-24 16:25:00-05	\N
325	400	Lumbalgia mecánica	\N	2026-09-25 09:55:00-05	\N
327	402	Dermatitis alérgica	Se ordenan exámenes de laboratorio	2026-09-25 16:25:00-05	\N
333	408	Dermatitis alérgica	Se ordenan exámenes de laboratorio	2026-09-25 10:25:00-05	\N
347	431	Infección de vías urinarias	Control en 8 días	2026-09-28 17:55:00-05	\N
348	432	Infección de vías urinarias	Control en 8 días	2026-09-28 10:55:00-05	\N
363	449	Lumbalgia mecánica	Se ordenan exámenes de laboratorio	2026-09-28 10:55:00-05	\N
367	453	Dermatitis alérgica	Actividad física moderada	2026-09-29 09:55:00-05	\N
383	469	Lumbalgia mecánica	\N	2026-09-29 09:25:00-05	\N
385	471	Infección de vías urinarias	Evitar la automedicación	2026-09-29 17:55:00-05	\N
386	472	Lumbalgia mecánica	Evitar la automedicación	2026-09-29 09:55:00-05	\N
391	477	Lumbalgia mecánica	Reposo e hidratación	2026-09-29 10:55:00-05	\N
397	486	Dermatitis alérgica	Se ordenan exámenes de laboratorio	2026-09-30 10:55:00-05	\N
404	493	Lumbalgia mecánica	Regresar si persisten los síntomas	2026-09-30 15:55:00-05	\N
414	508	Infección de vías urinarias	Regresar si persisten los síntomas	2026-09-30 14:55:00-05	\N
418	514	Lumbalgia mecánica	\N	2026-10-01 09:25:00-05	\N
422	521	Lumbalgia mecánica	Dieta blanda por 3 días	2026-10-01 15:55:00-05	\N
424	523	Lumbalgia mecánica	Dieta blanda por 3 días	2026-10-01 08:25:00-05	\N
431	535	Infección de vías urinarias	\N	2026-10-01 16:55:00-05	\N
443	549	Dermatitis alérgica	\N	2026-10-02 16:55:00-05	\N
444	550	Dermatitis alérgica	\N	2026-10-02 11:55:00-05	\N
450	560	Lumbalgia mecánica	Dieta blanda por 3 días	2026-10-02 16:55:00-05	\N
456	569	Lumbalgia mecánica	Dieta blanda por 3 días	2026-10-05 09:55:00-05	\N
459	572	Lumbalgia mecánica	Dieta blanda por 3 días	2026-10-05 08:55:00-05	\N
469	583	Dermatitis alérgica	Dieta blanda por 3 días	2026-10-05 15:25:00-05	\N
473	588	Dermatitis alérgica	Evitar la automedicación	2026-10-06 11:55:00-05	\N
476	592	Lumbalgia mecánica	Actividad física moderada	2026-10-06 15:25:00-05	\N
478	596	Dermatitis alérgica	Regresar si persisten los síntomas	2026-10-06 08:25:00-05	\N
479	597	Infección de vías urinarias	Regresar si persisten los síntomas	2026-10-06 09:55:00-05	\N
482	600	Dermatitis alérgica	Control en 8 días	2026-10-06 17:55:00-05	\N
493	615	Lumbalgia mecánica	Control en 8 días	2026-10-07 09:25:00-05	\N
494	616	Dermatitis alérgica	Evitar la automedicación	2026-10-07 16:55:00-05	\N
495	617	Lumbalgia mecánica	Control en 8 días	2026-10-07 08:25:00-05	\N
496	618	Lumbalgia mecánica	Se ordenan exámenes de laboratorio	2026-10-07 16:25:00-05	\N
515	640	Infección de vías urinarias	Evitar la automedicación	2026-10-08 16:25:00-05	\N
520	646	Infección de vías urinarias	Evitar la automedicación	2026-10-08 15:25:00-05	\N
528	654	Dermatitis alérgica	Dieta blanda por 3 días	2026-10-09 14:55:00-05	\N
543	675	Dermatitis alérgica	Actividad física moderada	2026-10-12 16:55:00-05	\N
578	720	Infección de vías urinarias	Control en 8 días	2026-10-14 17:55:00-05	\N
582	726	Infección de vías urinarias	Reposo e hidratación	2026-10-14 15:55:00-05	\N
586	730	Infección de vías urinarias	Regresar si persisten los síntomas	2026-10-14 16:25:00-05	\N
589	734	Lumbalgia mecánica	Dieta blanda por 3 días	2026-10-14 15:25:00-05	\N
594	742	Dermatitis alérgica	Control en 8 días	2026-10-15 11:55:00-05	\N
595	743	Dermatitis alérgica	Dieta blanda por 3 días	2026-10-15 15:55:00-05	\N
598	746	Dermatitis alérgica	Actividad física moderada	2026-10-15 17:55:00-05	\N
600	748	Lumbalgia mecánica	Se ordenan exámenes de laboratorio	2026-10-15 08:55:00-05	\N
601	749	Dermatitis alérgica	Dieta blanda por 3 días	2026-10-15 09:55:00-05	\N
614	766	Infección de vías urinarias	Actividad física moderada	2026-10-15 15:25:00-05	\N
535	662	Gastritis	\N	2026-10-09 14:25:00-05	K297
634	788	Infección de vías urinarias	\N	2026-10-16 08:55:00-05	\N
638	794	Dermatitis alérgica	Evitar la automedicación	2026-10-16 15:25:00-05	\N
623	775	Rinofaringitis aguda	Reposo e hidratación	2026-10-16 09:55:00-05	J00X
624	776	Gastritis	Evitar la automedicación	2026-10-16 15:25:00-05	K297
625	777	Cefalea tensional	Se ordenan exámenes de laboratorio	2026-10-16 17:25:00-05	G442
626	778	Mialgia	Evitar la automedicación	2026-10-16 09:25:00-05	M791
627	779	Rinitis alérgica	\N	2026-10-16 10:25:00-05	J304
628	781	Gastritis	Control en 8 días	2026-10-16 09:25:00-05	K297
629	782	Infección respiratoria aguda	Se ordenan exámenes de laboratorio	2026-10-16 09:55:00-05	J069
630	783	Hipertensión arterial en control	\N	2026-10-16 14:25:00-05	I10X
631	785	Cefalea tensional	Control en 8 días	2026-10-16 09:25:00-05	G442
632	786	Cefalea tensional	Reposo e hidratación	2026-10-16 11:55:00-05	G442
633	787	Síndrome febril	\N	2026-10-16 17:25:00-05	R509
635	789	Faringoamigdalitis	Regresar si persisten los síntomas	2026-10-16 17:25:00-05	J029
636	790	Mialgia	Se ordenan exámenes de laboratorio	2026-10-16 17:55:00-05	M791
637	792	Cefalea tensional	Reposo e hidratación	2026-10-16 14:25:00-05	G442
639	795	Síndrome febril	\N	2026-10-16 16:55:00-05	R509
640	796	Infección respiratoria aguda	Control en 8 días	2026-10-16 09:25:00-05	J069
641	797	Síndrome febril	Dieta blanda por 3 días	2026-10-16 16:55:00-05	R509
\.


--
-- TOC entry 5520 (class 0 OID 18671)
-- Dependencies: 244
-- Data for Name: horario_medico; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.horario_medico (id_horario, id_medico, dia_semana, hora_inicio, hora_fin) FROM stdin;
1	1	1	08:00:00	12:00:00
2	1	1	14:00:00	18:00:00
3	1	2	08:00:00	12:00:00
4	1	2	14:00:00	18:00:00
5	1	3	08:00:00	12:00:00
6	1	3	14:00:00	18:00:00
7	1	4	08:00:00	12:00:00
8	1	4	14:00:00	18:00:00
9	1	5	08:00:00	12:00:00
10	1	5	14:00:00	18:00:00
11	2	1	08:00:00	12:00:00
12	2	1	14:00:00	18:00:00
13	2	2	08:00:00	12:00:00
14	2	2	14:00:00	18:00:00
15	2	3	08:00:00	12:00:00
16	2	3	14:00:00	18:00:00
17	2	4	08:00:00	12:00:00
18	2	4	14:00:00	18:00:00
19	2	5	08:00:00	12:00:00
20	2	5	14:00:00	18:00:00
21	4	1	08:00:00	12:00:00
22	4	1	14:00:00	18:00:00
23	4	2	08:00:00	12:00:00
24	4	2	14:00:00	18:00:00
25	4	3	08:00:00	12:00:00
26	4	3	14:00:00	18:00:00
27	4	4	08:00:00	12:00:00
28	4	4	14:00:00	18:00:00
29	4	5	08:00:00	12:00:00
30	4	5	14:00:00	18:00:00
31	5	1	08:00:00	12:00:00
32	5	1	14:00:00	18:00:00
33	5	2	08:00:00	12:00:00
34	5	2	14:00:00	18:00:00
35	5	3	08:00:00	12:00:00
36	5	3	14:00:00	18:00:00
37	5	4	08:00:00	12:00:00
38	5	4	14:00:00	18:00:00
39	5	5	08:00:00	12:00:00
40	5	5	14:00:00	18:00:00
41	9	1	08:00:00	12:00:00
42	9	1	14:00:00	18:00:00
43	9	2	08:00:00	12:00:00
44	9	2	14:00:00	18:00:00
45	9	3	08:00:00	12:00:00
46	9	3	14:00:00	18:00:00
47	9	4	08:00:00	12:00:00
48	9	4	14:00:00	18:00:00
49	9	5	08:00:00	12:00:00
50	9	5	14:00:00	18:00:00
51	10	1	08:00:00	12:00:00
52	10	1	14:00:00	18:00:00
53	10	2	08:00:00	12:00:00
54	10	2	14:00:00	18:00:00
55	10	3	08:00:00	12:00:00
56	10	3	14:00:00	18:00:00
57	10	4	08:00:00	12:00:00
58	10	4	14:00:00	18:00:00
59	10	5	08:00:00	12:00:00
60	10	5	14:00:00	18:00:00
61	11	1	08:00:00	12:00:00
62	11	1	14:00:00	18:00:00
63	11	2	08:00:00	12:00:00
64	11	2	14:00:00	18:00:00
65	11	3	08:00:00	12:00:00
66	11	3	14:00:00	18:00:00
67	11	4	08:00:00	12:00:00
68	11	4	14:00:00	18:00:00
69	11	5	08:00:00	12:00:00
70	11	5	14:00:00	18:00:00
71	12	1	08:00:00	12:00:00
72	12	1	14:00:00	18:00:00
73	12	2	08:00:00	12:00:00
74	12	2	14:00:00	18:00:00
75	12	3	08:00:00	12:00:00
76	12	3	14:00:00	18:00:00
77	12	4	08:00:00	12:00:00
78	12	4	14:00:00	18:00:00
79	12	5	08:00:00	12:00:00
80	12	5	14:00:00	18:00:00
81	13	1	08:00:00	12:00:00
82	13	1	14:00:00	18:00:00
83	13	2	08:00:00	12:00:00
84	13	2	14:00:00	18:00:00
85	13	3	08:00:00	12:00:00
86	13	3	14:00:00	18:00:00
87	13	4	08:00:00	12:00:00
88	13	4	14:00:00	18:00:00
89	13	5	08:00:00	12:00:00
90	13	5	14:00:00	18:00:00
91	14	1	08:00:00	12:00:00
92	14	1	14:00:00	18:00:00
93	14	2	08:00:00	12:00:00
94	14	2	14:00:00	18:00:00
95	14	3	08:00:00	12:00:00
96	14	3	14:00:00	18:00:00
97	14	4	08:00:00	12:00:00
98	14	4	14:00:00	18:00:00
99	14	5	08:00:00	12:00:00
100	14	5	14:00:00	18:00:00
101	15	1	08:00:00	12:00:00
102	15	1	14:00:00	18:00:00
103	15	2	08:00:00	12:00:00
104	15	2	14:00:00	18:00:00
105	15	3	08:00:00	12:00:00
106	15	3	14:00:00	18:00:00
107	15	4	08:00:00	12:00:00
108	15	4	14:00:00	18:00:00
109	15	5	08:00:00	12:00:00
110	15	5	14:00:00	18:00:00
111	16	1	08:00:00	12:00:00
112	16	1	14:00:00	18:00:00
113	16	2	08:00:00	12:00:00
114	16	2	14:00:00	18:00:00
115	16	3	08:00:00	12:00:00
116	16	3	14:00:00	18:00:00
117	16	4	08:00:00	12:00:00
118	16	4	14:00:00	18:00:00
119	16	5	08:00:00	12:00:00
120	16	5	14:00:00	18:00:00
121	17	1	08:00:00	12:00:00
122	17	1	14:00:00	18:00:00
123	17	2	08:00:00	12:00:00
124	17	2	14:00:00	18:00:00
125	17	3	08:00:00	12:00:00
126	17	3	14:00:00	18:00:00
127	17	4	08:00:00	12:00:00
128	17	4	14:00:00	18:00:00
129	17	5	08:00:00	12:00:00
130	17	5	14:00:00	18:00:00
131	18	1	08:00:00	12:00:00
132	18	1	14:00:00	18:00:00
133	18	2	08:00:00	12:00:00
134	18	2	14:00:00	18:00:00
135	18	3	08:00:00	12:00:00
136	18	3	14:00:00	18:00:00
137	18	4	08:00:00	12:00:00
138	18	4	14:00:00	18:00:00
139	18	5	08:00:00	12:00:00
140	18	5	14:00:00	18:00:00
141	19	1	08:00:00	12:00:00
142	19	1	14:00:00	18:00:00
143	19	2	08:00:00	12:00:00
144	19	2	14:00:00	18:00:00
145	19	3	08:00:00	12:00:00
146	19	3	14:00:00	18:00:00
147	19	4	08:00:00	12:00:00
148	19	4	14:00:00	18:00:00
149	19	5	08:00:00	12:00:00
150	19	5	14:00:00	18:00:00
151	20	1	08:00:00	12:00:00
152	20	1	14:00:00	18:00:00
153	20	2	08:00:00	12:00:00
154	20	2	14:00:00	18:00:00
155	20	3	08:00:00	12:00:00
156	20	3	14:00:00	18:00:00
157	20	4	08:00:00	12:00:00
158	20	4	14:00:00	18:00:00
159	20	5	08:00:00	12:00:00
160	20	5	14:00:00	18:00:00
\.


--
-- TOC entry 5514 (class 0 OID 17757)
-- Dependencies: 235
-- Data for Name: medicamento; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medicamento (id_medicamento, nombre, presentacion, concentracion, precio_unitario) FROM stdin;
1	Acetaminofén	Tableta	500 mg	500.00
2	Amoxicilina	Cápsula	500 mg	1200.00
3	Ibuprofeno	Tableta	400 mg	800.00
5	Acetaminofén	Tableta	1 g	700.00
6	Acetaminofén	Jarabe	150 mg/5 ml	7500.00
8	Ibuprofeno	Tableta	600 mg	1100.00
9	Ibuprofeno	Suspensión	100 mg/5 ml	9500.00
10	Naproxeno	Tableta	250 mg	700.00
11	Naproxeno	Tableta	500 mg	1000.00
12	Diclofenaco	Tableta	50 mg	600.00
13	Diclofenaco	Gel tópico	1 %	12000.00
14	Ketorolaco	Tableta	10 mg	900.00
15	Dipirona	Tableta	500 mg	500.00
17	Amoxicilina	Suspensión	250 mg/5 ml	11000.00
18	Amoxicilina + Ácido clavulánico	Tableta	875 mg/125 mg	3800.00
19	Azitromicina	Tableta	500 mg	4500.00
20	Cefalexina	Cápsula	500 mg	1500.00
21	Ciprofloxacino	Tableta	500 mg	1300.00
22	Claritromicina	Tableta	500 mg	3200.00
23	Doxiciclina	Cápsula	100 mg	900.00
24	Metronidazol	Tableta	500 mg	700.00
25	Trimetoprim + Sulfametoxazol	Tableta	160 mg/800 mg	800.00
26	Nitrofurantoína	Cápsula	100 mg	1200.00
27	Penicilina G benzatínica	Vial	1.200.000 UI	9500.00
28	Clindamicina	Cápsula	300 mg	2200.00
29	Gentamicina	Ampolla	80 mg	2500.00
30	Omeprazol	Cápsula	20 mg	400.00
31	Esomeprazol	Tableta	40 mg	1800.00
32	Hioscina	Tableta	10 mg	900.00
33	Loperamida	Cápsula	2 mg	600.00
34	Sales de rehidratación oral	Sobre	27,9 g	1800.00
35	Ondansetrón	Tableta	8 mg	2200.00
36	Metoclopramida	Tableta	10 mg	400.00
37	Simeticona	Tableta masticable	80 mg	500.00
38	Lactulosa	Jarabe	66,7 %	14000.00
39	Hidróxido de aluminio + magnesio	Suspensión	200 mg/200 mg/5 ml	11000.00
40	Loratadina	Tableta	10 mg	350.00
41	Cetirizina	Tableta	10 mg	500.00
42	Desloratadina	Tableta	5 mg	1500.00
43	Salbutamol	Inhalador	100 mcg/dosis	14000.00
44	Acetilcisteína	Sobre	600 mg	2500.00
45	Ambroxol	Jarabe	30 mg/5 ml	9000.00
46	Montelukast	Tableta	10 mg	2500.00
47	Prednisona	Tableta	20 mg	600.00
48	Dexametasona	Ampolla	4 mg/ml	2500.00
49	Betametasona	Crema tópica	0,05 %	8000.00
50	Hidrocortisona	Crema tópica	1 %	7500.00
51	Solución salina nasal	Solución	0,9 %	6500.00
52	Losartán	Tableta	50 mg	450.00
53	Enalapril	Tableta	20 mg	350.00
54	Amlodipino	Tableta	5 mg	300.00
55	Hidroclorotiazida	Tableta	25 mg	250.00
56	Atorvastatina	Tableta	20 mg	800.00
57	Metformina	Tableta	850 mg	400.00
58	Glibenclamida	Tableta	5 mg	250.00
59	Levotiroxina	Tableta	100 mcg	700.00
60	Furosemida	Tableta	40 mg	300.00
61	Ácido acetilsalicílico	Tableta	100 mg	250.00
62	Insulina NPH	Vial	100 UI/ml	38000.00
63	Fluconazol	Cápsula	150 mg	3500.00
64	Albendazol	Tableta	400 mg	2500.00
65	Ivermectina	Tableta	6 mg	1800.00
66	Vitamina C	Tableta	500 mg	400.00
67	Ácido fólico	Tableta	1 mg	200.00
68	Sulfato ferroso	Tableta	300 mg	300.00
69	Calcio + Vitamina D	Tableta	600 mg/400 UI	600.00
70	Complejo B	Tableta	B1 + B6 + B12	500.00
71	Cloruro de sodio	Solución	0,9 % x 500 ml	4500.00
72	Clotrimazol	Crema tópica	1 %	6500.00
73	Mupirocina	Pomada	2 %	18000.00
\.


--
-- TOC entry 5506 (class 0 OID 17665)
-- Dependencies: 227
-- Data for Name: medico; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medico (id_medico, documento, nombres, apellidos, registro_profesional, telefono, correo, id_especialidad, activo, tipo_documento) FROM stdin;
1	10101010	Carlos	Pérez	RM-0001	3001112233	cperez@clinica.co	3	t	CC
2	20202020	Marcela	Gómez	RM-0002	3004445566	mgomez@clinica.co	2	t	CC
3	30303030	Julián	Rivera	RM-0003	3007778899	jrivera@clinica.co	1	f	CC
4	40404040	Andrea	Morales	RM-0004	3008889900	amorales@clinica.co	4	t	CC
5	50505050	Roberto	Mendoza	RM-0005	3002223344	rmendoza@clinica.co	5	t	CC
9	1061386634	Valentina	Muelas Chávez	RM-1001	3514018867	valentina.muelas@clinica.co	1	t	CC
10	1061167218	Juan	Rodríguez Dagua	RM-1002	3212136765	juan.rodriguez@clinica.co	1	t	CC
11	1061085404	Yuliana	Gutiérrez Realpe	RM-1003	3209144448	yuliana.gutierrez@clinica.co	1	t	CC
12	1061086202	Luisa	Rodríguez Peña	RM-1004	3122426930	luisa.rodriguez@clinica.co	1	t	CC
13	1061575988	Santiago	Rodríguez Vargas	RM-1005	3218771772	santiago.rodriguez@clinica.co	1	t	CC
14	1061390930	Jorge	García Valencia	RM-1006	3043040733	jorge.garcia@clinica.co	1	t	CC
15	1061392539	Valentina	Hernández Ante	RM-1007	3247733866	valentina.hernandez@clinica.co	1	t	CC
16	1061675048	Rosa	Trochez Collazos	RM-1008	3522126500	rosa.trochez@clinica.co	1	t	CC
17	1061437514	Sandra	Restrepo Gutiérrez	RM-1009	3242129692	sandra.restrepo@clinica.co	1	t	CC
18	1061351896	Brayan	Duque Guerrero	RM-1010	3013933225	brayan.duque@clinica.co	1	t	CC
19	1061873613	Carolina	Paz Martínez	RM-1011	3242891734	carolina.paz@clinica.co	1	t	CC
20	1061003701	David	Valencia Vargas	RM-1012	3240310832	david.valencia@clinica.co	1	t	CC
21	1061566598	Karen	Chávez Gutiérrez	RM-1013	3520760400	karen.chavez@clinica.co	1	f	CC
\.


--
-- TOC entry 5502 (class 0 OID 17634)
-- Dependencies: 223
-- Data for Name: paciente; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.paciente (id_paciente, documento, nombres, apellidos, fecha_nacimiento, telefono, correo, id_eps, tipo_documento, tipo_vinculacion) FROM stdin;
1	1002003001	Laura	Muñoz	1998-04-12	3101234567	laura@mail.com	1	CC	EPS
2	1002003002	Andrés	Ruiz	1985-09-30	3109876543	andres@mail.com	2	CC	EPS
3	1002003003	Sofía	Castro	2001-01-22	3112223344	\N	3	CC	EPS
7	1139986987	Rosa	Cortés Pérez	2015-04-26	3109114170	\N	5	TI	EPS
8	1055681518	Jhon	Rojas Quintero	1958-07-25	3205576169	jhon.rojas59@hotmail.com	1	CC	EPS
9	1197684697	Miguel	Dagua Duque	2013-10-04	3108196727	miguel.dagua74@gmail.com	2	TI	EPS
10	1084864887	Miguel	Collazos Medina	1978-02-10	3124002978	\N	3	CC	EPS
11	1078768045	Edwin	Gómez Peña	1979-07-25	3232671475	edwin.gomez57@gmail.com	5	CC	EPS
12	1098193319	Martha María	Hernández García	1976-06-24	3210599728	martha.hernandez35@yahoo.es	5	CC	EPS
13	1016229486	Carolina	Peña Realpe	1962-01-29	3501610550	carolina.pena67@gmail.com	11	CC	EPS
14	1117799229	Alejandra Yesenia	Chávez Gutiérrez	2017-12-29	3108603208	alejandra.chavez80@outlook.com	2	TI	EPS
15	1070283822	Luis	Duque Cortés	1952-11-29	3506425247	luis.duque50@gmail.com	2	CC	EPS
16	1071884133	Martha Juliana	Gutiérrez Solarte	1979-03-31	3542052589	martha.gutierrez59@gmail.com	5	CC	EPS
17	1039494821	Diego Óscar	Obando Duque	1986-12-17	3511052185	\N	1	CC	EPS
18	1010646001	Camila Johana	Díaz Gómez	1958-12-23	3227990659	camila.diaz16@hotmail.com	1	CC	EPS
19	1058464506	Tatiana	Medina Sánchez	1997-08-02	3221465908	\N	2	CC	EPS
20	1091102859	Alejandro	Restrepo Sánchez	1950-07-18	3126663632	alejandro.restrepo4@hotmail.com	3	CC	EPS
21	1064230048	Laura	Zúñiga Medina	1985-10-12	3018084585	laura.zuniga41@hotmail.com	1	CC	EPS
22	1038265384	María	Muñoz Narváez	1941-03-25	3547943262	maria.munoz48@gmail.com	2	CC	EPS
23	1060214584	María	Trochez Ante	1982-12-10	3240668828	maria.trochez3@gmail.com	4	CC	EPS
24	1040932448	Andrea	Mosquera Obando	1959-06-15	3047658280	andrea.mosquera50@gmail.com	1	CC	EPS
25	1005154382	Yuliana Laura	Sánchez Realpe	1995-11-26	3231164941	yuliana.sanchez17@gmail.com	1	CC	EPS
26	1079511174	Viviana Sandra	Muñoz Ante	1968-03-06	3227652373	viviana.munoz22@gmail.com	2	CC	EPS
27	1196327926	Wilson	Valencia Bermúdez	2010-08-10	3522843528	wilson.valencia41@gmail.com	2	TI	EPS
28	1008565178	Óscar Álvaro	Salazar Quintero	1971-11-02	3032048425	oscar.salazar46@outlook.com	5	CC	EPS
29	1175003145	Cristian	Dagua Narváez	2012-05-17	3208380125	cristian.dagua59@gmail.com	4	TI	EPS
30	1096898210	Álvaro David	Cardona Ortiz	1943-07-24	3135555974	alvaro.cardona6@outlook.com	1	CC	EPS
31	1020754735	Johana	Martínez Cortés	1979-12-17	3031884791	johana.martinez39@outlook.com	1	CC	EPS
32	1055218248	Gustavo	Paz Gutiérrez	1995-04-06	3107336882	gustavo.paz81@outlook.com	1	CC	EPS
33	1085568983	Ángela	Cardona Paz	1948-04-06	3119004422	angela.cardona91@yahoo.es	15	CC	EPS
34	1020226978	Yuliana	Ramírez Collazos	1951-02-05	3241762528	\N	2	CC	EPS
35	1045028316	María Stephany	Fernández Cardona	1998-08-30	3515286675	maria.fernandez22@gmail.com	2	CC	EPS
36	1071331159	Ricardo	Chávez Obando	1990-06-03	3516082445	ricardo.chavez23@gmail.com	1	CC	EPS
37	1072128357	Alejandra	Jiménez Ante	1967-10-10	3221775888	alejandra.jimenez7@yahoo.es	13	CC	EPS
38	1087916979	Óscar Santiago	Fernández Martínez	1942-04-20	3101612840	oscar.fernandez20@gmail.com	12	CC	EPS
39	1052473573	Jorge	Solarte Sánchez	2001-09-16	3519273197	jorge.solarte41@yahoo.es	3	CC	EPS
40	1008724385	Samuel	Paz Rojas	1970-07-07	3248281953	samuel.paz95@outlook.com	5	CC	EPS
41	1016603304	David	Dagua Sánchez	2007-12-05	3221420381	\N	1	CC	EPS
42	1180370412	Andrés	Peña Collazos	2011-06-10	3034182889	andres.pena27@hotmail.com	1	TI	EPS
43	1086713006	Viviana	Zúñiga Valencia	1956-06-24	3113283856	viviana.zuniga57@gmail.com	5	CC	EPS
44	1029837252	Luisa	Rodríguez Valencia	1942-09-01	3507695851	luisa.rodriguez18@gmail.com	1	CC	EPS
45	1034999248	Carlos	Muñoz Sánchez	1969-11-04	3139137298	carlos.munoz44@gmail.com	13	CC	EPS
46	1042640794	Samuel Sebastián	García Orozco	1983-04-27	3039113571	\N	3	CC	EPS
47	1144796745	Óscar	Chávez Restrepo	2020-05-08	3013463521	\N	1	RC	EPS
48	1039848864	Carolina	Cortés Zúñiga	1971-05-27	3209342692	carolina.cortes32@outlook.com	1	CC	EPS
49	1040985846	Marcela	Medina López	1990-11-21	3226830686	marcela.medina66@yahoo.es	2	CC	EPS
50	1096501332	Liliana	Dagua Muñoz	1986-03-03	3138350811	liliana.dagua61@outlook.com	15	CC	EPS
51	1116354011	Gloria Stephany	Salazar Solarte	2025-02-18	3531138759	\N	5	RC	EPS
52	1118621076	Daniela Andrea	Chávez Collazos	2021-04-10	3507751062	\N	1	RC	EPS
53	1015202994	Camila Yuliana	Solarte Muñoz	1974-02-03	3206199456	camila.solarte14@outlook.com	5	CC	EPS
54	1040894874	Ricardo Gustavo	Vargas Solarte	1973-08-05	3515844419	ricardo.vargas27@hotmail.com	5	CC	EPS
55	1015669796	Isabella	Mosquera Peña	1964-07-19	3545965056	isabella.mosquera56@hotmail.com	11	CC	EPS
56	1070904880	Nicolás	García Ocampo	1973-01-30	3220330132	nicolas.garcia56@hotmail.com	2	CC	EPS
57	1019889042	Liliana	Orozco Zúñiga	1976-12-02	3001960278	liliana.orozco30@outlook.com	1	CC	EPS
58	1073064248	Fernando	Ocampo Obando	1996-09-06	3546772041	fernando.ocampo92@outlook.com	1	CC	EPS
59	1035240137	Iván Álvaro	Solarte Orozco	1949-07-10	3029148335	ivan.solarte51@hotmail.com	14	CC	EPS
60	1013785222	Yesenia	Sánchez Trochez	1984-10-04	3247533257	yesenia.sanchez88@hotmail.com	1	CC	EPS
61	1180853470	Carolina	Ruiz Dagua	2024-01-17	3531341461	\N	1	RC	EPS
62	1061338005	Lucía Valentina	González Ruiz	2003-11-09	3528930597	lucia.gonzalez13@hotmail.com	2	CC	EPS
63	1055384885	Jhon	López Salazar	1994-06-01	3006709072	\N	4	CC	EPS
64	1151413633	Samuel	Cardona Cortés	2013-05-05	3000875262	samuel.cardona59@gmail.com	14	TI	EPS
65	1168631665	Ricardo Iván	Ruiz Cerón	2009-09-01	3525358134	\N	5	TI	EPS
66	1077044104	Tatiana Sara	Ortiz Orozco	1972-06-12	3206886561	\N	11	CC	EPS
67	1059534940	Ángela Valentina	Solarte Ramírez	1958-03-04	3527818244	angela.solarte73@gmail.com	13	CC	EPS
68	1068080100	Juliana	Hernández Orozco	1969-03-20	3210070091	\N	1	CC	EPS
69	1130570304	Valentina Andrea	Paz Castro	2023-01-26	3036114635	valentina.paz62@yahoo.es	3	RC	EPS
70	1100403004	María Diana	Realpe Muñoz	2021-01-03	3037155293	maria.realpe97@gmail.com	3	RC	EPS
71	1008129770	Santiago	Ramírez Bermúdez	1975-07-05	3149239813	\N	11	CC	EPS
72	1118615812	Valentina	Paz Medina	2013-03-26	3027067554	\N	12	TI	EPS
73	1016768259	Johana Gloria	Moreno Trochez	1965-08-02	3121726436	johana.moreno71@hotmail.com	11	CC	EPS
74	1092082422	Andrea	Díaz Campo	1938-03-25	3130950601	andrea.diaz18@hotmail.com	3	CC	EPS
75	1041517801	Sandra	Obando Chávez	1936-12-25	3545637827	sandra.obando44@gmail.com	12	CC	EPS
76	1096121385	Sofía	Ramírez Pérez	1997-10-01	3118696953	sofia.ramirez6@outlook.com	1	CC	EPS
77	1155013510	Carolina	Bolaños Quintero	2014-02-23	3033717112	\N	15	TI	EPS
78	1085098680	Óscar Edwin	González Bermúdez	1966-05-23	3106103022	\N	2	CC	EPS
79	1111482941	Luisa Luisa	García Ocampo	2023-09-21	3209082386	\N	15	RC	EPS
80	1012223863	Jorge	Ocampo Dagua	1947-11-06	3020542468	jorge.ocampo60@yahoo.es	4	CC	EPS
81	1076412974	Fernando	Gómez Ramírez	2003-11-07	3231393605	fernando.gomez52@outlook.com	3	CC	EPS
82	1096056433	Lucía	Ocampo Collazos	1936-12-18	3547710996	lucia.ocampo87@outlook.com	5	CC	EPS
83	1103720568	Lucía	Mejía Ortiz	2008-05-14	3035689651	lucia.mejia54@gmail.com	3	CC	EPS
84	1020396220	Yesenia	Paz Obando	1983-01-04	3219711009	yesenia.paz57@yahoo.es	3	CC	EPS
85	1082207016	Viviana	Rodríguez Rodríguez	1951-10-18	3222782062	\N	1	CC	EPS
86	1066432316	Ángela Tatiana	Bolaños Chávez	1960-07-04	3021534479	angela.bolanos58@outlook.com	5	CC	EPS
87	1121899033	Esteban	Cortés Valencia	2013-04-28	3546922713	esteban.cortes94@gmail.com	3	TI	EPS
88	1050295292	Natalia Ángela	Arias Paz	1944-02-23	3239837176	natalia.arias22@hotmail.com	2	CC	EPS
89	1145011459	Johana Sofía	Cardona Cerón	2016-03-23	3046584500	\N	2	TI	EPS
90	1148101331	Ángela	Gutiérrez Sánchez	2017-03-11	3020837819	\N	3	TI	EPS
91	1095444615	Martha María	González López	1946-04-16	3142102549	martha.gonzalez63@hotmail.com	2	CC	EPS
92	1121889049	Andrés	Orozco Dagua	2011-01-29	3117336979	andres.orozco10@gmail.com	11	TI	EPS
93	1047448059	Paola	Gutiérrez Ruiz	1948-08-30	3525856252	paola.gutierrez65@yahoo.es	1	CC	EPS
94	1186340561	Johana	Cerón González	2025-03-11	3216698143	johana.ceron47@outlook.com	1	RC	EPS
95	1007477763	Tatiana	Hernández Jiménez	1955-11-23	3040441861	tatiana.hernandez67@yahoo.es	5	CC	EPS
96	1069563143	Mateo	Cortés Gómez	1940-02-12	3226180756	\N	5	CC	EPS
97	1066412202	Natalia	Torres Peña	1961-01-22	3240257978	natalia.torres71@hotmail.com	2	CC	EPS
98	1049996179	Viviana	Realpe Paz	1981-11-26	3530554836	viviana.realpe41@hotmail.com	4	CC	EPS
99	1031624487	Yuliana	Paz Realpe	1966-05-27	3134032019	yuliana.paz34@outlook.com	4	CC	EPS
100	1057505807	Luisa	Orozco López	1954-05-06	3225791016	\N	3	CC	EPS
101	1083271745	Felipe	Rojas Arias	2001-12-23	3215115937	\N	15	CC	EPS
102	1047147323	Mauricio Esteban	Narváez Bolaños	2007-11-26	3531327440	mauricio.narvaez48@hotmail.com	1	CC	EPS
103	1082431433	Sofía	Bermúdez Jiménez	1951-07-08	3141495744	sofia.bermudez66@gmail.com	13	CC	EPS
104	1071252042	Johana	Ibarra Quintero	1951-03-11	3516958359	johana.ibarra11@gmail.com	11	CC	EPS
105	1152865946	Felipe	González López	2025-05-10	3100071465	felipe.gonzalez12@hotmail.com	15	RC	EPS
106	1034888302	Jairo	Vargas Peña	1951-03-18	3049823384	jairo.vargas33@hotmail.com	5	CC	EPS
107	1006192275	Karen	Fernández Cardona	2006-03-30	3124744519	karen.fernandez40@hotmail.com	4	CC	EPS
108	1159392981	Héctor	Dagua Restrepo	2014-05-07	3147303752	hector.dagua92@gmail.com	3	TI	EPS
109	1060518376	Cristian	Gutiérrez Paz	1982-10-23	3127537073	cristian.gutierrez31@hotmail.com	5	CC	EPS
110	1127732644	María	Zúñiga Ibarra	2022-04-05	3540431041	maria.zuniga38@outlook.com	15	RC	EPS
111	1115216576	Gloria Carolina	Díaz Mosquera	2021-04-13	3130581885	gloria.diaz85@hotmail.com	14	RC	EPS
112	1090770913	Isabella	Trochez Díaz	1988-09-23	3506016967	\N	3	CC	EPS
113	1083768917	Ricardo	Chávez Mejía	1976-08-24	3014236596	\N	5	CC	EPS
114	1075474154	Brayan Iván	Medina Obando	1958-03-14	3523663044	brayan.medina28@gmail.com	5	CC	EPS
115	1031782054	Daniela Rosa	Trochez Trochez	1957-01-29	3111687078	daniela.trochez74@hotmail.com	1	CC	EPS
116	1017367512	Fernando Alejandro	Trochez Cortés	2002-03-28	3125565174	\N	14	CC	EPS
117	1012026627	Sebastián	Ante Martínez	1940-08-23	3536971697	sebastian.ante54@gmail.com	3	CC	EPS
118	1019840993	Jorge	Zúñiga Campo	2006-10-17	3547496224	\N	13	CC	EPS
119	1048078269	María Paula	Sánchez Bolaños	1985-06-12	3524025219	maria.sanchez5@hotmail.com	2	CC	EPS
120	1165351904	Alejandra	Muñoz Zúñiga	2017-06-04	3017504997	alejandra.munoz58@yahoo.es	15	TI	EPS
121	1162492170	Daniel	Guerrero Ramírez	2022-06-20	3229284522	daniel.guerrero94@yahoo.es	4	RC	EPS
122	1135197604	Karen	Salazar Gómez	2023-06-04	3511683995	karen.salazar71@gmail.com	1	RC	EPS
123	1004810352	Paola	Cerón Vargas	1942-12-17	3005029775	paola.ceron58@yahoo.es	3	CC	EPS
124	1010810232	Rosa	Zúñiga Hernández	1939-03-31	3237123762	rosa.zuniga8@gmail.com	3	CC	EPS
125	1120453316	Rafael	Ante Cortés	2019-01-17	3213760012	rafael.ante13@yahoo.es	2	TI	EPS
126	1020559328	Valentina	Ibarra Cerón	1946-04-27	3004657612	valentina.ibarra64@gmail.com	5	CC	EPS
127	1013811462	Iván	Ramírez Gómez	1987-06-07	3117163392	ivan.ramirez44@gmail.com	11	CC	EPS
128	1092442143	Paola Valentina	Díaz Campo	1962-05-24	3511083579	paola.diaz41@gmail.com	14	CC	EPS
129	1055211116	Esteban Héctor	Castro López	1989-09-09	3201567216	esteban.castro71@gmail.com	5	CC	EPS
130	1116844558	Miguel Felipe	Medina Pérez	2021-10-14	3230834098	miguel.medina82@hotmail.com	1	RC	EPS
131	1119070147	Yesenia Yesenia	Orozco González	2012-06-26	3020491805	yesenia.orozco75@yahoo.es	5	TI	EPS
132	1096520034	Mateo Andrés	González Campo	1945-04-29	3120764152	mateo.gonzalez20@hotmail.com	1	CC	EPS
133	1036562001	Alejandra	Rodríguez Mosquera	1956-09-09	3523070015	\N	1	CC	EPS
134	1072717224	Jhon	Pérez García	1944-08-21	3240452931	\N	11	CC	EPS
135	1026440818	Santiago Carlos	García Peña	1993-10-30	3036132496	santiago.garcia81@hotmail.com	1	CC	EPS
136	1095179464	Cristian	Peña Paz	1987-06-19	3532575509	cristian.pena15@gmail.com	11	CC	EPS
137	1093529750	Diana Mariana	Ruiz Ocampo	1960-07-03	3220514381	diana.ruiz26@outlook.com	14	CC	EPS
138	1040751228	Gloria Camila	Martínez Castro	2001-06-26	3540363454	gloria.martinez93@yahoo.es	2	CC	EPS
139	1072130516	Andrea	Realpe Mosquera	2001-06-21	3037650526	\N	5	CC	EPS
140	1069965386	Daniela	López Moreno	1957-07-11	3545834275	daniela.lopez25@gmail.com	3	CC	EPS
141	1049602372	Edwin	Bolaños Medina	1954-08-14	3503178571	\N	5	CC	EPS
142	1078552285	Nicolás Miguel	Zúñiga Realpe	1960-01-16	3112693109	\N	5	CC	EPS
143	1077521621	Camila	García Cardona	1948-06-13	3123999959	camila.garcia93@hotmail.com	3	CC	EPS
144	1105548958	Claudia	Bermúdez Torres	2018-10-26	3506258966	claudia.bermudez17@gmail.com	1	TI	EPS
145	1035349368	Héctor	Collazos Bolaños	1942-11-11	3006417359	hector.collazos96@outlook.com	11	CC	EPS
146	1081881206	Rosa	Ibarra Ante	1999-08-03	3000524900	rosa.ibarra79@gmail.com	3	CC	EPS
147	1092410804	Natalia Andrea	Mejía Muñoz	1938-07-21	3246071964	natalia.mejia97@outlook.com	2	CC	EPS
148	1145314530	Rosa	Pérez Solarte	2014-11-07	3101740554	rosa.perez39@hotmail.com	1	TI	EPS
149	1004687901	Andrea	Ruiz Díaz	1997-03-23	3027897948	\N	1	CC	EPS
150	1068416859	Claudia Gloria	Narváez Sánchez	1985-12-01	3528991979	claudia.narvaez30@gmail.com	1	CC	EPS
151	1098658461	Sofía Stephany	Jiménez Bermúdez	1965-04-01	3012785381	sofia.jimenez26@outlook.com	11	CC	EPS
152	1098604014	Esteban	Jiménez Collazos	1972-06-10	3502415743	\N	13	CC	EPS
153	1083419032	Andrés Jhon	López Bermúdez	1991-06-21	3123298968	andres.lopez75@gmail.com	1	CC	EPS
154	1070575540	Sofía Marcela	Gómez Ramírez	2000-12-06	3033929239	sofia.gomez89@yahoo.es	15	CC	EPS
155	1090574719	Mariana	Paz Ante	1939-07-24	3248509342	mariana.paz71@outlook.com	1	CC	EPS
156	1073592846	Carlos Héctor	Ortiz González	1983-07-20	3539262701	carlos.ortiz10@gmail.com	11	CC	EPS
157	1046512292	Alejandra	Trochez Duque	1960-10-03	3033621841	alejandra.trochez80@outlook.com	1	CC	EPS
158	1060802223	Jairo	Gutiérrez Gómez	1982-03-31	3205434425	jairo.gutierrez41@hotmail.com	12	CC	EPS
159	1094321445	Juliana Yesenia	Cortés Pérez	1948-08-27	3142328377	\N	2	CC	EPS
160	1028222849	Rosa	Ante Hernández	1951-09-06	3235239035	rosa.ante85@outlook.com	1	CC	EPS
161	1084543383	Rafael Óscar	Chávez Fernández	1940-01-02	3034413207	rafael.chavez66@gmail.com	11	CC	EPS
162	1088961784	Diana	Quintero López	1962-07-17	3230654268	diana.quintero11@hotmail.com	5	CC	EPS
163	1017591150	Viviana Diana	Pérez Muelas	1970-06-08	3111114549	viviana.perez4@outlook.com	1	CC	EPS
164	1071816473	Héctor	Duque Mejía	1996-07-01	3212984446	hector.duque51@yahoo.es	5	CC	EPS
165	1062013914	Diana	Mosquera García	1936-09-28	3007832633	diana.mosquera20@gmail.com	5	CC	EPS
166	1048076134	Esteban	Collazos Salazar	1971-04-07	3206557285	esteban.collazos57@outlook.com	13	CC	EPS
167	1077634488	Samuel	Medina Cerón	1993-12-19	3121863544	samuel.medina96@gmail.com	1	CC	EPS
168	1129430304	Ángela	Castro Castro	2024-09-13	3515720710	angela.castro16@hotmail.com	11	RC	EPS
169	1030461866	Mariana	Díaz Paz	1936-03-02	3133549264	mariana.diaz41@gmail.com	2	CC	EPS
170	1054771274	Yuliana	Díaz Pérez	1995-06-27	3012985888	yuliana.diaz19@gmail.com	14	CC	EPS
171	1032594893	Wilson Gustavo	Zúñiga Ramírez	1985-02-24	3235258324	wilson.zuniga38@hotmail.com	4	CC	EPS
172	1068424915	Iván Ricardo	Duque Peña	1978-06-01	3041906377	\N	11	CC	EPS
173	1049335455	Tatiana Yesenia	Torres Ocampo	1970-10-05	3513745926	tatiana.torres24@outlook.com	1	CC	EPS
174	1085153482	Sara	Mosquera Obando	1953-11-04	3149429873	sara.mosquera88@hotmail.com	3	CC	EPS
175	1002292002	Alejandro	Díaz Ante	1994-08-06	3227850421	alejandro.diaz72@outlook.com	13	CC	EPS
176	1073927100	Alejandro	Realpe Ocampo	1988-08-14	3238350406	alejandro.realpe16@outlook.com	11	CC	EPS
177	1006863037	Sandra	Valencia Ramírez	1959-03-19	3005981341	sandra.valencia34@yahoo.es	2	CC	EPS
178	1124932796	Diana	Rojas Bermúdez	2012-11-14	3236337557	\N	1	TI	EPS
179	1024132483	Alejandra Yuliana	Gutiérrez Cortés	1992-10-26	3207834241	\N	11	CC	EPS
180	1025540537	Ángela	Vargas Chávez	1981-04-08	3120944074	angela.vargas3@hotmail.com	5	CC	EPS
181	1005017141	Isabella	Ruiz González	1964-09-24	3004494255	\N	3	CC	EPS
182	1083708396	Martha	Gómez Sánchez	1973-05-16	3519958470	martha.gomez19@yahoo.es	4	CC	EPS
183	1051557604	Iván Julián	Arias Ramírez	1959-06-04	3217751519	\N	5	CC	EPS
184	1078593226	Samuel	Narváez Vargas	1978-05-01	3120847238	samuel.narvaez15@hotmail.com	5	CC	EPS
185	1134312559	Isabella	Ocampo Valencia	2015-05-24	3119777976	\N	1	TI	EPS
186	1022567218	Liliana	Ruiz Collazos	1998-12-03	3120299335	liliana.ruiz3@outlook.com	1	CC	EPS
187	1065001853	Alejandra	Chávez Ruiz	1968-07-03	3009112799	alejandra.chavez78@outlook.com	11	CC	EPS
188	1071786561	Karen Natalia	Rojas Martínez	1969-08-10	3114551272	karen.rojas55@outlook.com	1	CC	EPS
189	1070874074	Laura	Muñoz Ramírez	1965-09-21	3142857239	laura.munoz92@yahoo.es	14	CC	EPS
190	1101340457	Diana Camila	Mejía Quintero	2019-09-20	3227067780	diana.mejia67@outlook.com	4	TI	EPS
191	1000349976	Gloria	Gómez Sánchez	1983-10-15	3239151750	\N	1	CC	EPS
192	1124366745	Héctor	Sánchez Ibarra	2008-11-14	3518204728	hector.sanchez86@gmail.com	4	CC	EPS
193	1097246376	Viviana	García Rojas	1987-11-08	3210427720	\N	2	CC	EPS
194	1003517043	Felipe Iván	Restrepo Jiménez	1944-10-20	3108011250	felipe.restrepo65@outlook.com	2	CC	EPS
195	1082808864	Iván	Muñoz Medina	1938-06-08	3515231806	ivan.munoz47@gmail.com	1	CC	EPS
196	1042061766	Rafael Luis	Narváez Moreno	1980-08-07	3240617641	rafael.narvaez24@hotmail.com	11	CC	EPS
197	1131155126	Johana	Ante Ibarra	2014-01-09	3118795229	johana.ante34@yahoo.es	3	TI	EPS
198	1128842062	Samuel	Arias Narváez	2018-02-26	3231111257	samuel.arias33@gmail.com	2	TI	EPS
199	1042120808	Marcela Isabella	Ante Muelas	1967-04-20	3530744018	marcela.ante17@gmail.com	2	CC	EPS
200	1194009492	Johana	Rodríguez Díaz	2010-06-15	3537634060	johana.rodriguez94@gmail.com	4	TI	EPS
201	1028790059	Jorge	Obando Collazos	1995-05-28	3045295415	jorge.obando56@hotmail.com	2	CC	EPS
202	1102393207	Tatiana Diana	Narváez Hernández	2022-01-02	3232660394	tatiana.narvaez56@gmail.com	3	RC	EPS
203	1019325827	Brayan Juan	Gómez Salazar	1993-08-28	3027839425	\N	11	CC	EPS
204	1059350351	Brayan	Chávez Ibarra	1987-06-21	3008958781	\N	5	CC	EPS
205	1022527040	Sandra	Bermúdez Martínez	1968-03-20	3221495054	sandra.bermudez33@hotmail.com	5	CC	EPS
206	1032832669	Diego Alejandro	Rodríguez Restrepo	2005-12-14	3139112352	diego.rodriguez60@hotmail.com	5	CC	EPS
207	1064494915	Sofía	Trochez Cerón	1967-09-20	3135678224	sofia.trochez78@outlook.com	1	CC	EPS
208	1111208311	Óscar Daniel	Realpe Martínez	2016-04-29	3116164471	oscar.realpe40@gmail.com	5	TI	EPS
209	1074457860	Juliana Andrea	Collazos Campo	1961-05-18	3147218438	juliana.collazos52@hotmail.com	12	CC	EPS
210	1017214965	Jorge	Bolaños Realpe	1973-03-27	3101259138	jorge.bolanos83@outlook.com	5	CC	EPS
211	1083488510	Luis	Hernández Díaz	1966-05-31	3230211974	luis.hernandez51@hotmail.com	1	CC	EPS
212	1055565846	Iván	Cortés Moreno	2000-10-01	3224869252	ivan.cortes24@gmail.com	11	CC	EPS
213	1155313089	Viviana Natalia	Gómez Paz	2016-12-16	3502113161	\N	5	TI	EPS
214	1113869413	Martha	Campo Solarte	2021-02-09	3034050116	\N	1	RC	EPS
215	1050259256	Julián Juan	Trochez Orozco	1998-10-07	3220554763	\N	5	CC	EPS
216	1035105557	Stephany	Dagua Peña	1999-10-18	3237104219	stephany.dagua90@gmail.com	1	CC	EPS
217	1143848714	Juliana	Collazos Guerrero	2019-02-07	3047302165	juliana.collazos49@outlook.com	12	TI	EPS
218	1000243714	Sandra	Valencia Ramírez	1985-06-30	3125407432	\N	2	CC	EPS
219	1092789512	Diego	Realpe Fernández	1993-01-19	3004979980	\N	1	CC	EPS
220	1003471072	Diana	Valencia Chávez	1938-02-13	3000631973	diana.valencia15@gmail.com	13	CC	EPS
221	1123754061	Mariana	Ortiz Gómez	2019-03-11	3030049745	mariana.ortiz55@yahoo.es	5	TI	EPS
222	1081872226	Héctor Jorge	Martínez Zúñiga	1943-03-09	3019365569	hector.martinez86@gmail.com	2	CC	EPS
223	1014346130	Alejandro	Zúñiga Orozco	1990-08-05	3530091729	alejandro.zuniga26@outlook.com	3	CC	EPS
224	1059586070	Viviana	Obando Pérez	1975-10-24	3249808352	viviana.obando14@yahoo.es	11	CC	EPS
225	1095401710	Liliana Marcela	Ocampo Rojas	1974-02-18	3241425105	liliana.ocampo90@hotmail.com	1	CC	EPS
226	1043397743	Rafael	Muelas Trochez	1999-02-02	3232203627	rafael.muelas98@yahoo.es	4	CC	EPS
\.


--
-- TOC entry 5521 (class 0 OID 18695)
-- Dependencies: 245
-- Data for Name: tipo_documento; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_documento (codigo, nombre) FROM stdin;
CC	Cédula de ciudadanía
TI	Tarjeta de identidad
CE	Cédula de extranjería
RC	Registro civil
PA	Pasaporte
PT	Permiso por protección temporal
PE	Permiso especial de permanencia
\.


--
-- TOC entry 5522 (class 0 OID 18716)
-- Dependencies: 246
-- Data for Name: tipo_vinculacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_vinculacion (codigo, nombre) FROM stdin;
EPS	Afiliado a una EPS
PARTICULAR	Particular (paga directamente, sin EPS)
\.


--
-- TOC entry 5549 (class 0 OID 0)
-- Dependencies: 230
-- Name: cita_id_cita_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cita_id_cita_seq', 1073, true);


--
-- TOC entry 5550 (class 0 OID 0)
-- Dependencies: 228
-- Name: consultorio_id_consultorio_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.consultorio_id_consultorio_seq', 16, true);


--
-- TOC entry 5551 (class 0 OID 0)
-- Dependencies: 220
-- Name: eps_id_eps_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.eps_id_eps_seq', 15, true);


--
-- TOC entry 5552 (class 0 OID 0)
-- Dependencies: 224
-- Name: especialidad_id_especialidad_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.especialidad_id_especialidad_seq', 8, true);


--
-- TOC entry 5553 (class 0 OID 0)
-- Dependencies: 237
-- Name: factura_id_factura_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.factura_id_factura_seq', 642, true);


--
-- TOC entry 5554 (class 0 OID 0)
-- Dependencies: 232
-- Name: historia_clinica_id_historia_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.historia_clinica_id_historia_seq', 642, true);


--
-- TOC entry 5555 (class 0 OID 0)
-- Dependencies: 243
-- Name: horario_medico_id_horario_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.horario_medico_id_horario_seq', 160, true);


--
-- TOC entry 5556 (class 0 OID 0)
-- Dependencies: 234
-- Name: medicamento_id_medicamento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.medicamento_id_medicamento_seq', 73, true);


--
-- TOC entry 5557 (class 0 OID 0)
-- Dependencies: 226
-- Name: medico_id_medico_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.medico_id_medico_seq', 21, true);


--
-- TOC entry 5558 (class 0 OID 0)
-- Dependencies: 222
-- Name: paciente_id_paciente_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.paciente_id_paciente_seq', 226, true);


--
-- TOC entry 5318 (class 2606 OID 18647)
-- Name: cie10 cie10_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cie10
    ADD CONSTRAINT cie10_pkey PRIMARY KEY (codigo);


--
-- TOC entry 5291 (class 2606 OID 17718)
-- Name: cita cita_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cita
    ADD CONSTRAINT cita_pkey PRIMARY KEY (id_cita);


--
-- TOC entry 5293 (class 2606 OID 18597)
-- Name: cita cita_sin_cruce_consultorio; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cita
    ADD CONSTRAINT cita_sin_cruce_consultorio EXCLUDE USING gist (id_consultorio WITH =, tsrange((fecha + hora), (fecha + hora_fin), '[)'::text) WITH &&) WHERE (((estado)::text <> 'Cancelada'::text));


--
-- TOC entry 5295 (class 2606 OID 18595)
-- Name: cita cita_sin_cruce_medico; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cita
    ADD CONSTRAINT cita_sin_cruce_medico EXCLUDE USING gist (id_medico WITH =, tsrange((fecha + hora), (fecha + hora_fin), '[)'::text) WITH &&) WHERE (((estado)::text <> 'Cancelada'::text));


--
-- TOC entry 5287 (class 2606 OID 17702)
-- Name: consultorio consultorio_numero_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consultorio
    ADD CONSTRAINT consultorio_numero_key UNIQUE (numero);


--
-- TOC entry 5289 (class 2606 OID 17700)
-- Name: consultorio consultorio_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consultorio
    ADD CONSTRAINT consultorio_pkey PRIMARY KEY (id_consultorio);


--
-- TOC entry 5269 (class 2606 OID 17632)
-- Name: eps eps_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eps
    ADD CONSTRAINT eps_nombre_key UNIQUE (nombre);


--
-- TOC entry 5271 (class 2606 OID 17630)
-- Name: eps eps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eps
    ADD CONSTRAINT eps_pkey PRIMARY KEY (id_eps);


--
-- TOC entry 5277 (class 2606 OID 17663)
-- Name: especialidad especialidad_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidad
    ADD CONSTRAINT especialidad_nombre_key UNIQUE (nombre);


--
-- TOC entry 5279 (class 2606 OID 17661)
-- Name: especialidad especialidad_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidad
    ADD CONSTRAINT especialidad_pkey PRIMARY KEY (id_especialidad);


--
-- TOC entry 5313 (class 2606 OID 17818)
-- Name: factura factura_id_cita_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT factura_id_cita_key UNIQUE (id_cita);


--
-- TOC entry 5315 (class 2606 OID 17816)
-- Name: factura factura_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT factura_pkey PRIMARY KEY (id_factura);


--
-- TOC entry 5310 (class 2606 OID 17784)
-- Name: formula_medica formula_medica_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.formula_medica
    ADD CONSTRAINT formula_medica_pkey PRIMARY KEY (id_historia, id_medicamento);


--
-- TOC entry 5301 (class 2606 OID 17750)
-- Name: historia_clinica historia_clinica_id_cita_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historia_clinica
    ADD CONSTRAINT historia_clinica_id_cita_key UNIQUE (id_cita);


--
-- TOC entry 5303 (class 2606 OID 17748)
-- Name: historia_clinica historia_clinica_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historia_clinica
    ADD CONSTRAINT historia_clinica_pkey PRIMARY KEY (id_historia);


--
-- TOC entry 5321 (class 2606 OID 18682)
-- Name: horario_medico horario_medico_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.horario_medico
    ADD CONSTRAINT horario_medico_pkey PRIMARY KEY (id_horario);


--
-- TOC entry 5323 (class 2606 OID 18684)
-- Name: horario_medico horario_medico_sin_cruce; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.horario_medico
    ADD CONSTRAINT horario_medico_sin_cruce EXCLUDE USING gist (id_medico WITH =, dia_semana WITH =, tsrange(('2000-01-01'::date + hora_inicio), ('2000-01-01'::date + hora_fin), '[)'::text) WITH &&);


--
-- TOC entry 5306 (class 2606 OID 17770)
-- Name: medicamento medicamento_nombre_presentacion_concentracion_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicamento
    ADD CONSTRAINT medicamento_nombre_presentacion_concentracion_key UNIQUE (nombre, presentacion, concentracion);


--
-- TOC entry 5308 (class 2606 OID 17768)
-- Name: medicamento medicamento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicamento
    ADD CONSTRAINT medicamento_pkey PRIMARY KEY (id_medicamento);


--
-- TOC entry 5281 (class 2606 OID 17682)
-- Name: medico medico_documento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_documento_key UNIQUE (documento);


--
-- TOC entry 5283 (class 2606 OID 17680)
-- Name: medico medico_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_pkey PRIMARY KEY (id_medico);


--
-- TOC entry 5285 (class 2606 OID 17684)
-- Name: medico medico_registro_profesional_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_registro_profesional_key UNIQUE (registro_profesional);


--
-- TOC entry 5273 (class 2606 OID 17648)
-- Name: paciente paciente_documento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_documento_key UNIQUE (documento);


--
-- TOC entry 5275 (class 2606 OID 17646)
-- Name: paciente paciente_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_pkey PRIMARY KEY (id_paciente);


--
-- TOC entry 5326 (class 2606 OID 18703)
-- Name: tipo_documento tipo_documento_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_documento
    ADD CONSTRAINT tipo_documento_nombre_key UNIQUE (nombre);


--
-- TOC entry 5328 (class 2606 OID 18701)
-- Name: tipo_documento tipo_documento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_documento
    ADD CONSTRAINT tipo_documento_pkey PRIMARY KEY (codigo);


--
-- TOC entry 5330 (class 2606 OID 18722)
-- Name: tipo_vinculacion tipo_vinculacion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_vinculacion
    ADD CONSTRAINT tipo_vinculacion_pkey PRIMARY KEY (codigo);


--
-- TOC entry 5319 (class 1259 OID 18648)
-- Name: idx_cie10_categoria; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cie10_categoria ON public.cie10 USING btree (categoria);


--
-- TOC entry 5296 (class 1259 OID 17824)
-- Name: idx_cita_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cita_fecha ON public.cita USING btree (fecha);


--
-- TOC entry 5297 (class 1259 OID 17825)
-- Name: idx_cita_paciente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cita_paciente ON public.cita USING btree (id_paciente);


--
-- TOC entry 5316 (class 1259 OID 17827)
-- Name: idx_factura_pendiente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_factura_pendiente ON public.factura USING btree (fecha_emision) WHERE ((estado)::text = 'Pendiente'::text);


--
-- TOC entry 5311 (class 1259 OID 17826)
-- Name: idx_formula_medicamento; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_formula_medicamento ON public.formula_medica USING btree (id_medicamento);


--
-- TOC entry 5304 (class 1259 OID 18654)
-- Name: idx_historia_cie10; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_historia_cie10 ON public.historia_clinica USING btree (codigo_cie10);


--
-- TOC entry 5324 (class 1259 OID 18690)
-- Name: idx_horario_medico; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_horario_medico ON public.horario_medico USING btree (id_medico, dia_semana);


--
-- TOC entry 5298 (class 1259 OID 17735)
-- Name: uq_cita_consultorio_horario; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_cita_consultorio_horario ON public.cita USING btree (id_consultorio, fecha, hora) WHERE ((estado)::text <> 'Cancelada'::text);


--
-- TOC entry 5299 (class 1259 OID 17734)
-- Name: uq_cita_medico_horario; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_cita_medico_horario ON public.cita USING btree (id_medico, fecha, hora) WHERE ((estado)::text <> 'Cancelada'::text);


--
-- TOC entry 5345 (class 2620 OID 17828)
-- Name: cita trg_validar_cita; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_cita BEFORE INSERT OR UPDATE OF estado, id_medico, id_consultorio ON public.cita FOR EACH ROW EXECUTE FUNCTION public.fn_validar_cita();


--
-- TOC entry 5347 (class 2620 OID 17829)
-- Name: historia_clinica trg_validar_historia; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_historia BEFORE INSERT ON public.historia_clinica FOR EACH ROW EXECUTE FUNCTION public.fn_validar_historia();


--
-- TOC entry 5346 (class 2620 OID 18692)
-- Name: cita trg_validar_horario_cita; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_horario_cita BEFORE INSERT OR UPDATE OF id_medico, fecha, hora, duracion_min ON public.cita FOR EACH ROW EXECUTE FUNCTION public.fn_validar_horario_cita();


--
-- TOC entry 5336 (class 2606 OID 17729)
-- Name: cita cita_id_consultorio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cita
    ADD CONSTRAINT cita_id_consultorio_fkey FOREIGN KEY (id_consultorio) REFERENCES public.consultorio(id_consultorio);


--
-- TOC entry 5337 (class 2606 OID 17724)
-- Name: cita cita_id_medico_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cita
    ADD CONSTRAINT cita_id_medico_fkey FOREIGN KEY (id_medico) REFERENCES public.medico(id_medico);


--
-- TOC entry 5338 (class 2606 OID 17719)
-- Name: cita cita_id_paciente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cita
    ADD CONSTRAINT cita_id_paciente_fkey FOREIGN KEY (id_paciente) REFERENCES public.paciente(id_paciente);


--
-- TOC entry 5343 (class 2606 OID 17819)
-- Name: factura factura_id_cita_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT factura_id_cita_fkey FOREIGN KEY (id_cita) REFERENCES public.cita(id_cita);


--
-- TOC entry 5341 (class 2606 OID 17785)
-- Name: formula_medica formula_medica_id_historia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.formula_medica
    ADD CONSTRAINT formula_medica_id_historia_fkey FOREIGN KEY (id_historia) REFERENCES public.historia_clinica(id_historia);


--
-- TOC entry 5342 (class 2606 OID 17790)
-- Name: formula_medica formula_medica_id_medicamento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.formula_medica
    ADD CONSTRAINT formula_medica_id_medicamento_fkey FOREIGN KEY (id_medicamento) REFERENCES public.medicamento(id_medicamento);


--
-- TOC entry 5339 (class 2606 OID 18649)
-- Name: historia_clinica historia_clinica_codigo_cie10_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historia_clinica
    ADD CONSTRAINT historia_clinica_codigo_cie10_fkey FOREIGN KEY (codigo_cie10) REFERENCES public.cie10(codigo);


--
-- TOC entry 5340 (class 2606 OID 17751)
-- Name: historia_clinica historia_clinica_id_cita_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historia_clinica
    ADD CONSTRAINT historia_clinica_id_cita_fkey FOREIGN KEY (id_cita) REFERENCES public.cita(id_cita);


--
-- TOC entry 5344 (class 2606 OID 18685)
-- Name: horario_medico horario_medico_id_medico_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.horario_medico
    ADD CONSTRAINT horario_medico_id_medico_fkey FOREIGN KEY (id_medico) REFERENCES public.medico(id_medico);


--
-- TOC entry 5334 (class 2606 OID 17685)
-- Name: medico medico_id_especialidad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_id_especialidad_fkey FOREIGN KEY (id_especialidad) REFERENCES public.especialidad(id_especialidad);


--
-- TOC entry 5335 (class 2606 OID 18709)
-- Name: medico medico_tipo_documento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_tipo_documento_fkey FOREIGN KEY (tipo_documento) REFERENCES public.tipo_documento(codigo);


--
-- TOC entry 5331 (class 2606 OID 17649)
-- Name: paciente paciente_id_eps_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_id_eps_fkey FOREIGN KEY (id_eps) REFERENCES public.eps(id_eps);


--
-- TOC entry 5332 (class 2606 OID 18704)
-- Name: paciente paciente_tipo_documento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_tipo_documento_fkey FOREIGN KEY (tipo_documento) REFERENCES public.tipo_documento(codigo);


--
-- TOC entry 5333 (class 2606 OID 18725)
-- Name: paciente paciente_tipo_vinculacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.paciente
    ADD CONSTRAINT paciente_tipo_vinculacion_fkey FOREIGN KEY (tipo_vinculacion) REFERENCES public.tipo_vinculacion(codigo);


--
-- TOC entry 5529 (class 0 OID 0)
-- Dependencies: 381
-- Name: FUNCTION agenda_diaria(p_id_medico integer, p_fecha date); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.agenda_diaria(p_id_medico integer, p_fecha date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.agenda_diaria(p_id_medico integer, p_fecha date) TO rol_administrador;
GRANT ALL ON FUNCTION public.agenda_diaria(p_id_medico integer, p_fecha date) TO rol_recepcionista;
GRANT ALL ON FUNCTION public.agenda_diaria(p_id_medico integer, p_fecha date) TO rol_medico;


--
-- TOC entry 5530 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE medico; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.medico TO rol_administrador;
GRANT SELECT ON TABLE public.medico TO rol_recepcionista;
GRANT SELECT ON TABLE public.medico TO rol_medico;


--
-- TOC entry 5531 (class 0 OID 0)
-- Dependencies: 471
-- Name: FUNCTION buscar_medico(p_texto text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.buscar_medico(p_texto text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.buscar_medico(p_texto text) TO rol_administrador;
GRANT ALL ON FUNCTION public.buscar_medico(p_texto text) TO rol_recepcionista;


--
-- TOC entry 5532 (class 0 OID 0)
-- Dependencies: 223
-- Name: TABLE paciente; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.paciente TO rol_administrador;
GRANT SELECT,INSERT,UPDATE ON TABLE public.paciente TO rol_recepcionista;
GRANT SELECT ON TABLE public.paciente TO rol_medico;


--
-- TOC entry 5533 (class 0 OID 0)
-- Dependencies: 280
-- Name: FUNCTION buscar_paciente(p_texto text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.buscar_paciente(p_texto text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.buscar_paciente(p_texto text) TO rol_administrador;
GRANT ALL ON FUNCTION public.buscar_paciente(p_texto text) TO rol_recepcionista;
GRANT ALL ON FUNCTION public.buscar_paciente(p_texto text) TO rol_medico;


--
-- TOC entry 5534 (class 0 OID 0)
-- Dependencies: 457
-- Name: PROCEDURE cancelar_cita(IN p_id_cita integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON PROCEDURE public.cancelar_cita(IN p_id_cita integer) FROM PUBLIC;
GRANT ALL ON PROCEDURE public.cancelar_cita(IN p_id_cita integer) TO rol_administrador;
GRANT ALL ON PROCEDURE public.cancelar_cita(IN p_id_cita integer) TO rol_recepcionista;


--
-- TOC entry 5535 (class 0 OID 0)
-- Dependencies: 431
-- Name: FUNCTION facturas_pendientes(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.facturas_pendientes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.facturas_pendientes() TO rol_administrador;
GRANT ALL ON FUNCTION public.facturas_pendientes() TO rol_recepcionista;
GRANT ALL ON FUNCTION public.facturas_pendientes() TO rol_contador;


--
-- TOC entry 5536 (class 0 OID 0)
-- Dependencies: 424
-- Name: FUNCTION fn_validar_cita(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fn_validar_cita() FROM PUBLIC;
GRANT ALL ON FUNCTION public.fn_validar_cita() TO rol_administrador;


--
-- TOC entry 5537 (class 0 OID 0)
-- Dependencies: 338
-- Name: FUNCTION fn_validar_historia(); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.fn_validar_historia() FROM PUBLIC;
GRANT ALL ON FUNCTION public.fn_validar_historia() TO rol_administrador;


--
-- TOC entry 5538 (class 0 OID 0)
-- Dependencies: 272
-- Name: FUNCTION historia_paciente(p_id_paciente integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.historia_paciente(p_id_paciente integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.historia_paciente(p_id_paciente integer) TO rol_administrador;
GRANT ALL ON FUNCTION public.historia_paciente(p_id_paciente integer) TO rol_medico;


--
-- TOC entry 5539 (class 0 OID 0)
-- Dependencies: 296
-- Name: PROCEDURE marcar_inasistencia(IN p_id_cita integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON PROCEDURE public.marcar_inasistencia(IN p_id_cita integer) FROM PUBLIC;
GRANT ALL ON PROCEDURE public.marcar_inasistencia(IN p_id_cita integer) TO rol_administrador;
GRANT ALL ON PROCEDURE public.marcar_inasistencia(IN p_id_cita integer) TO rol_recepcionista;


--
-- TOC entry 5540 (class 0 OID 0)
-- Dependencies: 342
-- Name: PROCEDURE registrar_pago(IN p_id_factura integer, IN p_metodo_pago character varying); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON PROCEDURE public.registrar_pago(IN p_id_factura integer, IN p_metodo_pago character varying) FROM PUBLIC;
GRANT ALL ON PROCEDURE public.registrar_pago(IN p_id_factura integer, IN p_metodo_pago character varying) TO rol_administrador;
GRANT ALL ON PROCEDURE public.registrar_pago(IN p_id_factura integer, IN p_metodo_pago character varying) TO rol_recepcionista;


--
-- TOC entry 5541 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE cita; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cita TO rol_administrador;
GRANT SELECT,INSERT,UPDATE ON TABLE public.cita TO rol_recepcionista;
GRANT SELECT ON TABLE public.cita TO rol_medico;


--
-- TOC entry 5542 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE consultorio; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.consultorio TO rol_administrador;
GRANT SELECT ON TABLE public.consultorio TO rol_recepcionista;
GRANT SELECT ON TABLE public.consultorio TO rol_medico;


--
-- TOC entry 5543 (class 0 OID 0)
-- Dependencies: 221
-- Name: TABLE eps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.eps TO rol_administrador;
GRANT SELECT ON TABLE public.eps TO rol_recepcionista;
GRANT SELECT ON TABLE public.eps TO rol_medico;


--
-- TOC entry 5544 (class 0 OID 0)
-- Dependencies: 225
-- Name: TABLE especialidad; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.especialidad TO rol_administrador;
GRANT SELECT ON TABLE public.especialidad TO rol_recepcionista;
GRANT SELECT ON TABLE public.especialidad TO rol_medico;


--
-- TOC entry 5545 (class 0 OID 0)
-- Dependencies: 238
-- Name: TABLE factura; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.factura TO rol_administrador;
GRANT SELECT ON TABLE public.factura TO rol_contador;


--
-- TOC entry 5546 (class 0 OID 0)
-- Dependencies: 236
-- Name: TABLE formula_medica; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.formula_medica TO rol_administrador;
GRANT SELECT ON TABLE public.formula_medica TO rol_medico;


--
-- TOC entry 5547 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE historia_clinica; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.historia_clinica TO rol_administrador;
GRANT SELECT ON TABLE public.historia_clinica TO rol_medico;


--
-- TOC entry 5548 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE medicamento; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.medicamento TO rol_administrador;
GRANT SELECT ON TABLE public.medicamento TO rol_medico;


-- Completed on 2026-11-19 15:52:37

--
-- PostgreSQL database dump complete
--

\unrestrict 8qWajgTFkqEL7o5F0qAgEnHHvl50QYmWC7jDegl2nPTTrCE99JUeqO0BUtHlrr1

