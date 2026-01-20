--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.4

-- Started on 2026-01-20 20:34:44

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
-- TOC entry 910 (class 1247 OID 16489)
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'admin',
    'project_manager',
    'lead',
    'engineer',
    'customer'
);


--
-- TOC entry 275 (class 1255 OID 16544)
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 272 (class 1259 OID 17210)
-- Name: agent_activity_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_activity_logs (
    id integer NOT NULL,
    job_id integer,
    agent_id integer,
    log_level character varying(20) NOT NULL,
    message text NOT NULL,
    context jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 5430 (class 0 OID 0)
-- Dependencies: 272
-- Name: TABLE agent_activity_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.agent_activity_logs IS 'Structured activity logs from agents during job execution.';


--
-- TOC entry 271 (class 1259 OID 17209)
-- Name: agent_activity_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agent_activity_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5431 (class 0 OID 0)
-- Dependencies: 271
-- Name: agent_activity_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agent_activity_logs_id_seq OWNED BY public.agent_activity_logs.id;


--
-- TOC entry 268 (class 1259 OID 17159)
-- Name: agent_command_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_command_history (
    id integer NOT NULL,
    job_id integer,
    project_id integer,
    block_name character varying(255),
    experiment character varying(255),
    action_type character varying(100) NOT NULL,
    command_summary character varying(500) NOT NULL,
    action_payload jsonb NOT NULL,
    status character varying(50) NOT NULL,
    exit_code integer,
    execution_time_ms integer,
    executed_by integer,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    agent_id integer
);


--
-- TOC entry 5432 (class 0 OID 0)
-- Dependencies: 268
-- Name: TABLE agent_command_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.agent_command_history IS 'Audit log of executed commands. Stores structured data, not raw shell commands.';


--
-- TOC entry 267 (class 1259 OID 17158)
-- Name: agent_command_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agent_command_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5433 (class 0 OID 0)
-- Dependencies: 267
-- Name: agent_command_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agent_command_history_id_seq OWNED BY public.agent_command_history.id;


--
-- TOC entry 264 (class 1259 OID 17113)
-- Name: agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents (
    id integer NOT NULL,
    agent_token character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    hostname character varying(255),
    version character varying(50),
    capabilities jsonb,
    is_active boolean DEFAULT true,
    last_heartbeat timestamp without time zone,
    registered_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    registered_by integer,
    metadata jsonb,
    CONSTRAINT agents_token_not_empty CHECK ((length((agent_token)::text) >= 32))
);


--
-- TOC entry 5434 (class 0 OID 0)
-- Dependencies: 264
-- Name: TABLE agents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.agents IS 'Registered agent services that pull jobs from ASI. No SSH credentials stored.';


--
-- TOC entry 222 (class 1259 OID 16500)
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(100) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    full_name character varying(255),
    role public.user_role DEFAULT 'engineer'::public.user_role NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_login timestamp without time zone,
    domain_id integer,
    ipaddress character varying(255),
    port integer,
    ssh_user character varying(255),
    sshpassword_hash character varying(255)
);


--
-- TOC entry 5435 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN users.ipaddress; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.ipaddress IS 'SSH server IP address (admin only)';


--
-- TOC entry 5436 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN users.port; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.port IS 'SSH server port (admin only)';


--
-- TOC entry 5437 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN users.ssh_user; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.ssh_user IS 'SSH username (admin only)';


--
-- TOC entry 5438 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN users.sshpassword_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.sshpassword_hash IS 'Hashed SSH password (admin only)';


--
-- TOC entry 274 (class 1259 OID 17251)
-- Name: agent_command_history_recent; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.agent_command_history_recent AS
 SELECT h.id,
    h.job_id,
    h.project_id,
    h.block_name,
    h.experiment,
    h.action_type,
    h.command_summary,
    h.status,
    h.exit_code,
    h.execution_time_ms,
    u.username AS executed_by_username,
    h.executed_at,
    a.name AS agent_name
   FROM ((public.agent_command_history h
     LEFT JOIN public.users u ON ((h.executed_by = u.id)))
     LEFT JOIN public.agents a ON ((h.agent_id = a.id)))
  ORDER BY h.executed_at DESC;


--
-- TOC entry 270 (class 1259 OID 17189)
-- Name: agent_file_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_file_operations (
    id integer NOT NULL,
    job_id integer,
    operation_type character varying(50) NOT NULL,
    local_path text,
    remote_path text NOT NULL,
    file_size bigint,
    checksum character varying(64),
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    error_message text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    completed_at timestamp without time zone,
    agent_id integer
);


--
-- TOC entry 5439 (class 0 OID 0)
-- Dependencies: 270
-- Name: TABLE agent_file_operations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.agent_file_operations IS 'Tracks file operations (upload/download) between ASI and agents. Agent controls actual file paths.';


--
-- TOC entry 269 (class 1259 OID 17188)
-- Name: agent_file_operations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agent_file_operations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5440 (class 0 OID 0)
-- Dependencies: 269
-- Name: agent_file_operations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agent_file_operations_id_seq OWNED BY public.agent_file_operations.id;


--
-- TOC entry 266 (class 1259 OID 17131)
-- Name: agent_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_jobs (
    id integer NOT NULL,
    project_id integer,
    block_name character varying(255),
    experiment character varying(255),
    action_type character varying(100) NOT NULL,
    action_payload jsonb NOT NULL,
    working_directory text,
    timeout_seconds integer DEFAULT 300,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    assigned_agent_id integer,
    claimed_at timestamp without time zone,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    exit_code integer,
    stdout text,
    stderr text,
    output_files jsonb,
    error_message text,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    priority integer DEFAULT 0,
    metadata jsonb,
    CONSTRAINT agent_jobs_payload_valid CHECK ((action_payload IS NOT NULL)),
    CONSTRAINT agent_jobs_status_valid CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'claimed'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- TOC entry 5441 (class 0 OID 0)
-- Dependencies: 266
-- Name: TABLE agent_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.agent_jobs IS 'Job queue for agent execution. Agents pull jobs via HTTPS. No raw commands stored.';


--
-- TOC entry 265 (class 1259 OID 17130)
-- Name: agent_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agent_jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5442 (class 0 OID 0)
-- Dependencies: 265
-- Name: agent_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agent_jobs_id_seq OWNED BY public.agent_jobs.id;


--
-- TOC entry 273 (class 1259 OID 17247)
-- Name: agent_jobs_pending; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.agent_jobs_pending AS
 SELECT id,
    project_id,
    block_name,
    experiment,
    action_type,
    action_payload,
    working_directory,
    timeout_seconds,
    priority,
    created_at
   FROM public.agent_jobs
  WHERE ((status)::text = 'pending'::text)
  ORDER BY priority DESC, created_at;


--
-- TOC entry 263 (class 1259 OID 17112)
-- Name: agents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agents_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5443 (class 0 OID 0)
-- Dependencies: 263
-- Name: agents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agents_id_seq OWNED BY public.agents.id;


--
-- TOC entry 251 (class 1259 OID 16837)
-- Name: ai_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_summaries (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    summary_text text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 250 (class 1259 OID 16836)
-- Name: ai_summaries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_summaries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5444 (class 0 OID 0)
-- Dependencies: 250
-- Name: ai_summaries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_summaries_id_seq OWNED BY public.ai_summaries.id;


--
-- TOC entry 233 (class 1259 OID 16692)
-- Name: blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocks (
    id integer NOT NULL,
    project_id integer NOT NULL,
    block_name character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 232 (class 1259 OID 16691)
-- Name: blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blocks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5445 (class 0 OID 0)
-- Dependencies: 232
-- Name: blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blocks_id_seq OWNED BY public.blocks.id;


--
-- TOC entry 258 (class 1259 OID 17000)
-- Name: c_report_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.c_report_data (
    id integer NOT NULL,
    check_item_id integer NOT NULL,
    report_path text,
    description text,
    status character varying(50) DEFAULT 'pending'::character varying,
    fix_details text,
    engineer_comments text,
    lead_comments text,
    result_value text,
    signoff_status character varying(50),
    signoff_by integer,
    signoff_at timestamp without time zone,
    csv_data jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 257 (class 1259 OID 16999)
-- Name: c_report_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.c_report_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5446 (class 0 OID 0)
-- Dependencies: 257
-- Name: c_report_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.c_report_data_id_seq OWNED BY public.c_report_data.id;


--
-- TOC entry 260 (class 1259 OID 17022)
-- Name: check_item_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.check_item_approvals (
    id integer NOT NULL,
    check_item_id integer NOT NULL,
    default_approver_id integer,
    assigned_approver_id integer,
    assigned_by_lead_id integer,
    status character varying(50) DEFAULT 'pending'::character varying,
    comments text,
    submitted_at timestamp without time zone,
    approved_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 259 (class 1259 OID 17021)
-- Name: check_item_approvals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.check_item_approvals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5447 (class 0 OID 0)
-- Dependencies: 259
-- Name: check_item_approvals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.check_item_approvals_id_seq OWNED BY public.check_item_approvals.id;


--
-- TOC entry 256 (class 1259 OID 16980)
-- Name: check_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.check_items (
    id integer NOT NULL,
    checklist_id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    check_item_type character varying(100),
    display_order integer DEFAULT 0,
    category character varying(100),
    sub_category character varying(100),
    severity character varying(50),
    bronze character varying(50),
    silver character varying(50),
    gold character varying(50),
    info text,
    evidence text,
    auto_approve boolean DEFAULT false,
    version character varying(50) DEFAULT 'v1'::character varying,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 255 (class 1259 OID 16979)
-- Name: check_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.check_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5448 (class 0 OID 0)
-- Dependencies: 255
-- Name: check_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.check_items_id_seq OWNED BY public.check_items.id;


--
-- TOC entry 254 (class 1259 OID 16947)
-- Name: checklists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checklists (
    id integer NOT NULL,
    block_id integer NOT NULL,
    milestone_id integer,
    name character varying(255) NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying,
    approver_id integer,
    approver_role character varying(50),
    submitted_by integer,
    submitted_at timestamp without time zone,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    metadata jsonb DEFAULT '{}'::jsonb,
    engineer_comments text,
    reviewer_comments text
);


--
-- TOC entry 253 (class 1259 OID 16946)
-- Name: checklists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.checklists_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5449 (class 0 OID 0)
-- Dependencies: 253
-- Name: checklists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.checklists_id_seq OWNED BY public.checklists.id;


--
-- TOC entry 218 (class 1259 OID 16457)
-- Name: chips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chips (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    architecture character varying(100),
    process_node character varying(50),
    status character varying(50) DEFAULT 'design'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer,
    updated_by integer
);


--
-- TOC entry 217 (class 1259 OID 16456)
-- Name: chips_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.chips_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5450 (class 0 OID 0)
-- Dependencies: 217
-- Name: chips_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.chips_id_seq OWNED BY public.chips.id;


--
-- TOC entry 220 (class 1259 OID 16469)
-- Name: designs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.designs (
    id integer NOT NULL,
    chip_id integer,
    name character varying(255) NOT NULL,
    description text,
    design_type character varying(100),
    status character varying(50) DEFAULT 'draft'::character varying,
    metadata jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by integer,
    updated_by integer
);


--
-- TOC entry 219 (class 1259 OID 16468)
-- Name: designs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.designs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5451 (class 0 OID 0)
-- Dependencies: 219
-- Name: designs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.designs_id_seq OWNED BY public.designs.id;


--
-- TOC entry 224 (class 1259 OID 16549)
-- Name: domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domains (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 223 (class 1259 OID 16548)
-- Name: domains_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.domains_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5452 (class 0 OID 0)
-- Dependencies: 223
-- Name: domains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.domains_id_seq OWNED BY public.domains.id;


--
-- TOC entry 245 (class 1259 OID 16792)
-- Name: drv_violations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drv_violations (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    violation_type character varying(50) NOT NULL,
    wns character varying(50),
    tns character varying(50),
    nvp character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 244 (class 1259 OID 16791)
-- Name: drv_violations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.drv_violations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5453 (class 0 OID 0)
-- Dependencies: 244
-- Name: drv_violations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.drv_violations_id_seq OWNED BY public.drv_violations.id;


--
-- TOC entry 243 (class 1259 OID 16777)
-- Name: path_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.path_groups (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    group_type character varying(10) NOT NULL,
    group_name character varying(100) NOT NULL,
    wns character varying(50),
    tns character varying(50),
    nvp character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 242 (class 1259 OID 16776)
-- Name: path_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.path_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5454 (class 0 OID 0)
-- Dependencies: 242
-- Name: path_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.path_groups_id_seq OWNED BY public.path_groups.id;


--
-- TOC entry 249 (class 1259 OID 16822)
-- Name: physical_verification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.physical_verification (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    pv_drc_base character varying(50),
    pv_drc_metal character varying(50),
    pv_drc_antenna character varying(50),
    lvs character varying(50),
    erc character varying(50),
    r2g_lec character varying(50),
    g2g_lec character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 248 (class 1259 OID 16821)
-- Name: physical_verification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.physical_verification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5455 (class 0 OID 0)
-- Dependencies: 248
-- Name: physical_verification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.physical_verification_id_seq OWNED BY public.physical_verification.id;


--
-- TOC entry 247 (class 1259 OID 16807)
-- Name: power_ir_em_checks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.power_ir_em_checks (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    ir_static character varying(50),
    ir_dynamic character varying(50),
    em_power character varying(50),
    em_signal character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 246 (class 1259 OID 16806)
-- Name: power_ir_em_checks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.power_ir_em_checks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5456 (class 0 OID 0)
-- Dependencies: 246
-- Name: power_ir_em_checks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.power_ir_em_checks_id_seq OWNED BY public.power_ir_em_checks.id;


--
-- TOC entry 227 (class 1259 OID 16590)
-- Name: project_domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_domains (
    project_id integer NOT NULL,
    domain_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 226 (class 1259 OID 16574)
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    client character varying(255),
    technology_node character varying(100),
    start_date date,
    target_date date,
    plan text,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 225 (class 1259 OID 16573)
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.projects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5457 (class 0 OID 0)
-- Dependencies: 225
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- TOC entry 262 (class 1259 OID 17054)
-- Name: qms_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qms_audit_log (
    id integer NOT NULL,
    checklist_id integer,
    check_item_id integer,
    action character varying(50) NOT NULL,
    entity_type character varying(50) NOT NULL,
    user_id integer,
    old_value jsonb,
    new_value jsonb,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 261 (class 1259 OID 17053)
-- Name: qms_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.qms_audit_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5458 (class 0 OID 0)
-- Dependencies: 261
-- Name: qms_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.qms_audit_log_id_seq OWNED BY public.qms_audit_log.id;


--
-- TOC entry 235 (class 1259 OID 16708)
-- Name: runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.runs (
    id integer NOT NULL,
    block_id integer NOT NULL,
    experiment character varying(100),
    rtl_tag character varying(100),
    user_name character varying(100),
    run_directory text,
    last_updated timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 234 (class 1259 OID 16707)
-- Name: runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.runs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5459 (class 0 OID 0)
-- Dependencies: 234
-- Name: runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.runs_id_seq OWNED BY public.runs.id;


--
-- TOC entry 241 (class 1259 OID 16762)
-- Name: stage_constraint_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stage_constraint_metrics (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    max_tran_wns character varying(50),
    max_tran_nvp character varying(50),
    max_cap_wns character varying(50),
    max_cap_nvp character varying(50),
    max_fanout_wns character varying(50),
    max_fanout_nvp character varying(50),
    drc_violations character varying(50),
    congestion_hotspot character varying(100),
    noise_violations character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 240 (class 1259 OID 16761)
-- Name: stage_constraint_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stage_constraint_metrics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5460 (class 0 OID 0)
-- Dependencies: 240
-- Name: stage_constraint_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stage_constraint_metrics_id_seq OWNED BY public.stage_constraint_metrics.id;


--
-- TOC entry 239 (class 1259 OID 16747)
-- Name: stage_timing_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stage_timing_metrics (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    internal_r2r_wns character varying(50),
    internal_r2r_tns character varying(50),
    internal_r2r_nvp character varying(50),
    interface_i2r_wns character varying(50),
    interface_i2r_tns character varying(50),
    interface_i2r_nvp character varying(50),
    interface_r2o_wns character varying(50),
    interface_r2o_tns character varying(50),
    interface_r2o_nvp character varying(50),
    interface_i2o_wns character varying(50),
    interface_i2o_tns character varying(50),
    interface_i2o_nvp character varying(50),
    hold_wns character varying(50),
    hold_tns character varying(50),
    hold_nvp character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 238 (class 1259 OID 16746)
-- Name: stage_timing_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stage_timing_metrics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5461 (class 0 OID 0)
-- Dependencies: 238
-- Name: stage_timing_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stage_timing_metrics_id_seq OWNED BY public.stage_timing_metrics.id;


--
-- TOC entry 237 (class 1259 OID 16726)
-- Name: stages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stages (
    id integer NOT NULL,
    run_id integer NOT NULL,
    stage_name character varying(50) NOT NULL,
    "timestamp" timestamp without time zone,
    stage_directory text,
    run_status character varying(50),
    runtime character varying(20),
    memory_usage character varying(50),
    log_errors character varying(50) DEFAULT 0,
    log_warnings character varying(50) DEFAULT 0,
    log_critical character varying(50) DEFAULT 0,
    area character varying(50),
    inst_count character varying(50),
    utilization character varying(50),
    metal_density_max character varying(50),
    min_pulse_width character varying(50),
    min_period character varying(50),
    double_switching character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 236 (class 1259 OID 16725)
-- Name: stages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5462 (class 0 OID 0)
-- Dependencies: 236
-- Name: stages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stages_id_seq OWNED BY public.stages.id;


--
-- TOC entry 252 (class 1259 OID 16928)
-- Name: user_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_projects (
    user_id integer NOT NULL,
    project_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 221 (class 1259 OID 16499)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5463 (class 0 OID 0)
-- Dependencies: 221
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 231 (class 1259 OID 16631)
-- Name: zoho_projects_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.zoho_projects_mapping (
    id integer NOT NULL,
    zoho_project_id character varying(255) NOT NULL,
    local_project_id integer,
    zoho_project_name character varying(255),
    zoho_project_data jsonb,
    synced_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 230 (class 1259 OID 16630)
-- Name: zoho_projects_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.zoho_projects_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5464 (class 0 OID 0)
-- Dependencies: 230
-- Name: zoho_projects_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.zoho_projects_mapping_id_seq OWNED BY public.zoho_projects_mapping.id;


--
-- TOC entry 229 (class 1259 OID 16609)
-- Name: zoho_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.zoho_tokens (
    id integer NOT NULL,
    user_id integer,
    access_token text NOT NULL,
    refresh_token text NOT NULL,
    token_type character varying(50) DEFAULT 'Bearer'::character varying,
    expires_in integer,
    expires_at timestamp without time zone,
    scope text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- TOC entry 228 (class 1259 OID 16608)
-- Name: zoho_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.zoho_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 5465 (class 0 OID 0)
-- Dependencies: 228
-- Name: zoho_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.zoho_tokens_id_seq OWNED BY public.zoho_tokens.id;


--
-- TOC entry 4984 (class 2604 OID 17213)
-- Name: agent_activity_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_activity_logs ALTER COLUMN id SET DEFAULT nextval('public.agent_activity_logs_id_seq'::regclass);


--
-- TOC entry 4979 (class 2604 OID 17162)
-- Name: agent_command_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_command_history ALTER COLUMN id SET DEFAULT nextval('public.agent_command_history_id_seq'::regclass);


--
-- TOC entry 4981 (class 2604 OID 17192)
-- Name: agent_file_operations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_file_operations ALTER COLUMN id SET DEFAULT nextval('public.agent_file_operations_id_seq'::regclass);


--
-- TOC entry 4974 (class 2604 OID 17134)
-- Name: agent_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_jobs ALTER COLUMN id SET DEFAULT nextval('public.agent_jobs_id_seq'::regclass);


--
-- TOC entry 4971 (class 2604 OID 17116)
-- Name: agents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents ALTER COLUMN id SET DEFAULT nextval('public.agents_id_seq'::regclass);


--
-- TOC entry 4945 (class 2604 OID 16840)
-- Name: ai_summaries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_summaries ALTER COLUMN id SET DEFAULT nextval('public.ai_summaries_id_seq'::regclass);


--
-- TOC entry 4921 (class 2604 OID 16695)
-- Name: blocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks ALTER COLUMN id SET DEFAULT nextval('public.blocks_id_seq'::regclass);


--
-- TOC entry 4961 (class 2604 OID 17003)
-- Name: c_report_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.c_report_data ALTER COLUMN id SET DEFAULT nextval('public.c_report_data_id_seq'::regclass);


--
-- TOC entry 4965 (class 2604 OID 17025)
-- Name: check_item_approvals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_item_approvals ALTER COLUMN id SET DEFAULT nextval('public.check_item_approvals_id_seq'::regclass);


--
-- TOC entry 4954 (class 2604 OID 16983)
-- Name: check_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_items ALTER COLUMN id SET DEFAULT nextval('public.check_items_id_seq'::regclass);


--
-- TOC entry 4949 (class 2604 OID 16950)
-- Name: checklists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklists ALTER COLUMN id SET DEFAULT nextval('public.checklists_id_seq'::regclass);


--
-- TOC entry 4892 (class 2604 OID 16460)
-- Name: chips id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chips ALTER COLUMN id SET DEFAULT nextval('public.chips_id_seq'::regclass);


--
-- TOC entry 4896 (class 2604 OID 16472)
-- Name: designs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designs ALTER COLUMN id SET DEFAULT nextval('public.designs_id_seq'::regclass);


--
-- TOC entry 4905 (class 2604 OID 16552)
-- Name: domains id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains ALTER COLUMN id SET DEFAULT nextval('public.domains_id_seq'::regclass);


--
-- TOC entry 4939 (class 2604 OID 16795)
-- Name: drv_violations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drv_violations ALTER COLUMN id SET DEFAULT nextval('public.drv_violations_id_seq'::regclass);


--
-- TOC entry 4937 (class 2604 OID 16780)
-- Name: path_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.path_groups ALTER COLUMN id SET DEFAULT nextval('public.path_groups_id_seq'::regclass);


--
-- TOC entry 4943 (class 2604 OID 16825)
-- Name: physical_verification id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_verification ALTER COLUMN id SET DEFAULT nextval('public.physical_verification_id_seq'::regclass);


--
-- TOC entry 4941 (class 2604 OID 16810)
-- Name: power_ir_em_checks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_ir_em_checks ALTER COLUMN id SET DEFAULT nextval('public.power_ir_em_checks_id_seq'::regclass);


--
-- TOC entry 4909 (class 2604 OID 16577)
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- TOC entry 4969 (class 2604 OID 17057)
-- Name: qms_audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qms_audit_log ALTER COLUMN id SET DEFAULT nextval('public.qms_audit_log_id_seq'::regclass);


--
-- TOC entry 4924 (class 2604 OID 16711)
-- Name: runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runs ALTER COLUMN id SET DEFAULT nextval('public.runs_id_seq'::regclass);


--
-- TOC entry 4935 (class 2604 OID 16765)
-- Name: stage_constraint_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_constraint_metrics ALTER COLUMN id SET DEFAULT nextval('public.stage_constraint_metrics_id_seq'::regclass);


--
-- TOC entry 4933 (class 2604 OID 16750)
-- Name: stage_timing_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_timing_metrics ALTER COLUMN id SET DEFAULT nextval('public.stage_timing_metrics_id_seq'::regclass);


--
-- TOC entry 4927 (class 2604 OID 16729)
-- Name: stages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stages ALTER COLUMN id SET DEFAULT nextval('public.stages_id_seq'::regclass);


--
-- TOC entry 4900 (class 2604 OID 16503)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 4917 (class 2604 OID 16634)
-- Name: zoho_projects_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_projects_mapping ALTER COLUMN id SET DEFAULT nextval('public.zoho_projects_mapping_id_seq'::regclass);


--
-- TOC entry 4913 (class 2604 OID 16612)
-- Name: zoho_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_tokens ALTER COLUMN id SET DEFAULT nextval('public.zoho_tokens_id_seq'::regclass);


--
-- TOC entry 5424 (class 0 OID 17210)
-- Dependencies: 272
-- Data for Name: agent_activity_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_activity_logs (id, job_id, agent_id, log_level, message, context, created_at) FROM stdin;
\.


--
-- TOC entry 5420 (class 0 OID 17159)
-- Dependencies: 268
-- Data for Name: agent_command_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_command_history (id, job_id, project_id, block_name, experiment, action_type, command_summary, action_payload, status, exit_code, execution_time_ms, executed_by, executed_at, agent_id) FROM stdin;
\.


--
-- TOC entry 5422 (class 0 OID 17189)
-- Dependencies: 270
-- Data for Name: agent_file_operations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_file_operations (id, job_id, operation_type, local_path, remote_path, file_size, checksum, status, error_message, created_at, completed_at, agent_id) FROM stdin;
\.


--
-- TOC entry 5418 (class 0 OID 17131)
-- Dependencies: 266
-- Data for Name: agent_jobs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agent_jobs (id, project_id, block_name, experiment, action_type, action_payload, working_directory, timeout_seconds, status, assigned_agent_id, claimed_at, started_at, completed_at, exit_code, stdout, stderr, output_files, error_message, created_by, created_at, priority, metadata) FROM stdin;
\.


--
-- TOC entry 5416 (class 0 OID 17113)
-- Dependencies: 264
-- Data for Name: agents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.agents (id, agent_token, name, description, hostname, version, capabilities, is_active, last_heartbeat, registered_at, registered_by, metadata) FROM stdin;
\.


--
-- TOC entry 5403 (class 0 OID 16837)
-- Dependencies: 251
-- Data for Name: ai_summaries; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ai_summaries (id, stage_id, summary_text, created_at, updated_at) FROM stdin;
97	1178	these stage should be run again	2026-01-12 13:42:57.332984	2026-01-12 13:42:57.332984
\.


--
-- TOC entry 5385 (class 0 OID 16692)
-- Dependencies: 233
-- Data for Name: blocks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.blocks (id, project_id, block_name, created_at, updated_at) FROM stdin;
30	34	aes_cipher_up	2026-01-08 16:33:50.17231	2026-01-08 16:33:50.17231
38	41	aes_cipher_up	2026-01-08 18:20:26.383115	2026-01-08 18:20:26.383115
39	43	aes_cipher_down	2026-01-09 10:53:13.559456	2026-01-09 10:53:13.559456
40	41	gpu_core	2026-01-09 10:53:13.542496	2026-01-09 10:53:13.542496
41	42	aes_cipher_3s	2026-01-09 10:53:13.530524	2026-01-09 10:53:13.530524
42	44	aes_cipher_2s	2026-01-09 10:53:13.541336	2026-01-09 10:53:13.541336
\.


--
-- TOC entry 5410 (class 0 OID 17000)
-- Dependencies: 258
-- Data for Name: c_report_data; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.c_report_data (id, check_item_id, report_path, description, status, fix_details, engineer_comments, lead_comments, result_value, signoff_status, signoff_by, signoff_at, csv_data, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 5412 (class 0 OID 17022)
-- Dependencies: 260
-- Data for Name: check_item_approvals; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.check_item_approvals (id, check_item_id, default_approver_id, assigned_approver_id, assigned_by_lead_id, status, comments, submitted_at, approved_at, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 5408 (class 0 OID 16980)
-- Dependencies: 256
-- Data for Name: check_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.check_items (id, checklist_id, name, description, check_item_type, display_order, category, sub_category, severity, bronze, silver, gold, info, evidence, auto_approve, version, metadata, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 5406 (class 0 OID 16947)
-- Dependencies: 254
-- Data for Name: checklists; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.checklists (id, block_id, milestone_id, name, status, approver_id, approver_role, submitted_by, submitted_at, created_by, created_at, updated_at, metadata, engineer_comments, reviewer_comments) FROM stdin;
\.


--
-- TOC entry 5370 (class 0 OID 16457)
-- Dependencies: 218
-- Data for Name: chips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chips (id, name, description, architecture, process_node, status, created_at, updated_at, created_by, updated_by) FROM stdin;
1	ASI-1000	High-performance processor chip	RISC-V	7nm	production	2025-12-14 13:48:24.251961	2025-12-14 13:48:24.251961	\N	\N
2	ASI-2000	AI accelerator chip	Custom	5nm	design	2025-12-14 13:48:24.251961	2025-12-14 13:48:24.251961	\N	\N
3	ASI-3000	IoT microcontroller	ARM	28nm	testing	2025-12-14 13:48:24.251961	2025-12-14 13:48:24.251961	\N	\N
\.


--
-- TOC entry 5372 (class 0 OID 16469)
-- Dependencies: 220
-- Data for Name: designs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.designs (id, chip_id, name, description, design_type, status, metadata, created_at, updated_at, created_by, updated_by) FROM stdin;
1	1	Core Layout	Main processor core layout design	layout	completed	{"area": "25mm²", "version": "1.0"}	2025-12-14 13:48:24.260738	2025-12-14 13:48:24.260738	\N	\N
2	2	Memory Controller	DDR5 memory controller design	schematic	in_progress	{"area": "10mm²", "version": "0.8"}	2025-12-14 13:48:24.260738	2025-12-14 13:48:24.260738	\N	\N
\.


--
-- TOC entry 5376 (class 0 OID 16549)
-- Dependencies: 224
-- Data for Name: domains; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.domains (id, name, code, description, is_active, created_at, updated_at) FROM stdin;
1	Design Verification	DV	Design Verification (DV) domain for verifying chip designs	t	2025-12-14 15:13:18.124677	2025-12-14 15:13:18.124677
2	Register Transfer Level	RTL	RTL (Register Transfer Level) design domain	t	2025-12-14 15:13:18.124677	2025-12-14 15:13:18.124677
3	Design for Testability	DFT	DFT (Design for Testability) domain for testability features	t	2025-12-14 15:13:18.124677	2025-12-14 15:13:18.124677
4	Physical Design	PHYSICAL	Physical design domain for layout and floorplanning	t	2025-12-14 15:13:18.124677	2025-12-14 15:13:18.124677
5	Analog Layout	ANALOG	Analog layout domain for analog circuit design	t	2025-12-14 15:13:18.124677	2025-12-14 15:13:18.124677
6	pd	PD	Domain: pd	t	2025-12-30 11:11:50.234149	2025-12-30 11:11:50.234149
7	physical domain	PHYSICAL_DOMAIN	Domain: physical domain	t	2025-12-30 11:11:50.24347	2025-12-30 11:11:50.24347
8	physical deisgn	PHYSICAL_DEISGN	Domain: physical deisgn	t	2025-12-30 11:11:50.250123	2025-12-30 11:11:50.250123
9	phyiscal deisgn	PHYISCAL_DEISGN	Domain: phyiscal deisgn	t	2025-12-30 11:11:50.349753	2025-12-30 11:11:50.349753
10	1767004323863	1767004323863	Domain: 1767004323863	t	2025-12-30 11:11:50.257425	2025-12-30 11:11:50.257425
11	design _verification	DESIGN__VERIFICATION	Domain: design _verification	t	2025-12-30 11:34:39.201481	2025-12-30 11:34:39.201481
\.


--
-- TOC entry 5397 (class 0 OID 16792)
-- Dependencies: 245
-- Data for Name: drv_violations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.drv_violations (id, stage_id, violation_type, wns, tns, nvp, created_at) FROM stdin;
2127	1165	max_transition	N/A	N/A	0	2026-01-09 10:53:13.542496
2130	1165	max_capacitance	N/A	N/A	0	2026-01-09 10:53:13.542496
2128	1164	max_transition	N/A	N/A	0	2026-01-09 10:53:13.559456
2131	1164	max_capacitance	N/A	N/A	0	2026-01-09 10:53:13.559456
2132	1164	max_fanout	N/A	N/A	0	2026-01-09 10:53:13.559456
2135	1167	max_transition	N/A	N/A	0	2026-01-09 10:53:13.542496
2066	1123	max_transition	N/A	N/A	0	2026-01-08 16:33:50.17231
2067	1123	max_capacitance	N/A	N/A	0	2026-01-08 16:33:50.17231
2068	1123	max_fanout	N/A	N/A	0	2026-01-08 16:33:50.17231
2136	1167	max_capacitance	N/A	N/A	0	2026-01-09 10:53:13.542496
2137	1167	max_fanout	-220.5	-441	6	2026-01-09 10:53:13.542496
2138	1172	max_transition	N/A	N/A	0	2026-01-09 10:53:13.542496
2139	1172	max_capacitance	N/A	N/A	0	2026-01-09 10:53:13.542496
2140	1172	max_fanout	-220.5	-441	6	2026-01-09 10:53:13.542496
2129	1166	max_transition	N/A	N/A	0	2026-01-09 10:53:13.530524
2133	1166	max_capacitance	N/A	N/A	0	2026-01-09 10:53:13.530524
2134	1166	max_fanout	N/A	N/A	0	2026-01-09 10:53:13.530524
2141	1173	max_transition	N/A	N/A	0	2026-01-09 10:53:13.541336
2144	1173	max_capacitance	N/A	N/A	0	2026-01-09 10:53:13.541336
2146	1173	max_fanout	N/A	N/A	0	2026-01-09 10:53:13.541336
2121	1162	max_transition	N/A	N/A	0	2026-01-08 18:20:26.383115
2122	1162	max_capacitance	N/A	N/A	0	2026-01-08 18:20:26.383115
2123	1162	max_fanout	N/A	N/A	0	2026-01-08 18:20:26.383115
\.


--
-- TOC entry 5395 (class 0 OID 16777)
-- Dependencies: 243
-- Data for Name: path_groups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.path_groups (id, stage_id, group_type, group_name, wns, tns, nvp, created_at) FROM stdin;
2801	1172	setup	reg2reg	5.345	0	0	2026-01-09 10:53:13.542496
2802	1172	setup	in2reg	4.876	0	0	2026-01-09 10:53:13.542496
2803	1172	setup	reg2out	5.123	0	0	2026-01-09 10:53:13.542496
2683	1123	setup	all	7.421	0	0	2026-01-08 16:33:50.17231
2684	1123	setup	cg_enable_group_clk	8.705	0	0	2026-01-08 16:33:50.17231
2685	1123	setup	in2reg	7.463	0	0	2026-01-08 16:33:50.17231
2686	1123	setup	reg2out	7.421	0	0	2026-01-08 16:33:50.17231
2687	1123	setup	reg2reg	8.527	0	0	2026-01-08 16:33:50.17231
2784	1166	setup	all	7.421	0	0	2026-01-09 10:53:13.530524
2787	1166	setup	cg_enable_group_clk	8.705	0	0	2026-01-09 10:53:13.530524
2790	1166	setup	in2reg	7.463	0	0	2026-01-09 10:53:13.530524
2793	1166	setup	reg2out	7.421	0	0	2026-01-09 10:53:13.530524
2795	1166	setup	reg2reg	8.527	0	0	2026-01-09 10:53:13.530524
2804	1173	setup	all	7.421	0	0	2026-01-09 10:53:13.541336
2805	1173	setup	cg_enable_group_clk	8.705	0	0	2026-01-09 10:53:13.541336
2806	1173	setup	in2reg	7.463	0	0	2026-01-09 10:53:13.541336
2808	1173	setup	reg2out	7.421	0	0	2026-01-09 10:53:13.541336
2811	1173	setup	reg2reg	8.527	0	0	2026-01-09 10:53:13.541336
2772	1162	setup	all	7.421	0	0	2026-01-08 18:20:26.383115
2773	1162	setup	cg_enable_group_clk	8.705	0	0	2026-01-08 18:20:26.383115
2774	1162	setup	in2reg	7.463	0	0	2026-01-08 18:20:26.383115
2775	1162	setup	reg2out	7.421	0	0	2026-01-08 18:20:26.383115
2776	1162	setup	reg2reg	8.527	0	0	2026-01-08 18:20:26.383115
2783	1165	setup	all	5.945	0	0	2026-01-09 10:53:13.542496
2786	1165	setup	reg2reg	6.145	0	0	2026-01-09 10:53:13.542496
2789	1165	setup	in2reg	5.678	0	0	2026-01-09 10:53:13.542496
2792	1165	setup	reg2out	5.945	0	0	2026-01-09 10:53:13.542496
2782	1164	setup	all	7.421	0	0	2026-01-09 10:53:13.559456
2785	1164	setup	cg_enable_group_clk	8.705	0	0	2026-01-09 10:53:13.559456
2788	1164	setup	in2reg	7.463	0	0	2026-01-09 10:53:13.559456
2791	1164	setup	reg2out	7.421	0	0	2026-01-09 10:53:13.559456
2794	1164	setup	reg2reg	8.527	0	0	2026-01-09 10:53:13.559456
2796	1167	setup	all	5.234	0	0	2026-01-09 10:53:13.542496
2797	1167	setup	reg2reg	5.456	0	0	2026-01-09 10:53:13.542496
2798	1167	setup	in2reg	4.987	0	0	2026-01-09 10:53:13.542496
2799	1167	setup	reg2out	5.234	0	0	2026-01-09 10:53:13.542496
2800	1172	setup	all	4.876	0	0	2026-01-09 10:53:13.542496
\.


--
-- TOC entry 5401 (class 0 OID 16822)
-- Dependencies: 249
-- Data for Name: physical_verification; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.physical_verification (id, stage_id, pv_drc_base, pv_drc_metal, pv_drc_antenna, lvs, erc, r2g_lec, g2g_lec, created_at) FROM stdin;
1122	1123	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-08 16:33:50.17231
1161	1162	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-08 18:20:26.383115
1163	1165	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1164	1164	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1170	1167	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1166	1168	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1168	1170	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1171	1172	N/A	N/A	N/A	pass	N/A	pass	pass	2026-01-09 10:53:13.542496
1165	1166	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1167	1169	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1169	1171	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1175	1175	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1177	1178	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1173	1173	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
1174	1176	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
1176	1177	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
\.


--
-- TOC entry 5399 (class 0 OID 16807)
-- Dependencies: 247
-- Data for Name: power_ir_em_checks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.power_ir_em_checks (id, stage_id, ir_static, ir_dynamic, em_power, em_signal, created_at) FROM stdin;
1122	1123	N/A	N/A	N/A	N/A	2026-01-08 16:33:50.17231
1161	1162	N/A	N/A	N/A	N/A	2026-01-08 18:20:26.383115
1163	1165	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1164	1164	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1170	1167	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1166	1168	N/A	N/A	N/A	85	2026-01-09 10:53:13.559456
1168	1170	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1171	1172	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1165	1166	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1167	1169	N/A	N/A	N/A	85	2026-01-09 10:53:13.530524
1169	1171	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1175	1175	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1177	1178	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1173	1173	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
1174	1176	N/A	N/A	N/A	85	2026-01-09 10:53:13.541336
1176	1177	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
\.


--
-- TOC entry 5379 (class 0 OID 16590)
-- Dependencies: 227
-- Data for Name: project_domains; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.project_domains (project_id, domain_id, created_at) FROM stdin;
34	7	2026-01-08 16:33:50.17231
41	7	2026-01-08 18:20:26.383115
42	7	2026-01-09 10:53:13.530524
41	4	2026-01-09 10:53:13.542496
43	8	2026-01-09 10:53:13.559456
44	11	2026-01-09 10:53:13.541336
\.


--
-- TOC entry 5378 (class 0 OID 16574)
-- Dependencies: 226
-- Data for Name: projects; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.projects (id, name, client, technology_node, start_date, target_date, plan, created_by, created_at, updated_at) FROM stdin;
34	Ganga	\N	\N	\N	\N	\N	\N	2026-01-08 16:33:50.17231	2026-01-08 16:33:50.17231
41	project1	\N	\N	\N	\N	\N	\N	2026-01-08 18:20:26.383115	2026-01-08 18:20:26.383115
42	proj	\N	\N	\N	\N	\N	\N	2026-01-09 10:53:13.530524	2026-01-09 10:53:13.530524
43	project2	\N	\N	\N	\N	\N	\N	2026-01-09 10:53:13.559456	2026-01-09 10:53:13.559456
44	project3	\N	\N	\N	\N	\N	\N	2026-01-09 10:53:13.541336	2026-01-09 10:53:13.541336
\.


--
-- TOC entry 5414 (class 0 OID 17054)
-- Dependencies: 262
-- Data for Name: qms_audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.qms_audit_log (id, checklist_id, check_item_id, action, entity_type, user_id, old_value, new_value, description, created_at) FROM stdin;
\.


--
-- TOC entry 5387 (class 0 OID 16708)
-- Dependencies: 235
-- Data for Name: runs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.runs (id, block_id, experiment, rtl_tag, user_name, run_directory, last_updated, created_at, updated_at) FROM stdin;
38	38	run2	bronze_v1	rakesh	/proj1/pd/users/testcase/rakesh/proj/flow28nm_dashbrd/aes_cipher_up/bronze_v1/run2/dashboard	2025-12-25 08:02:39	2026-01-08 18:20:26.383115	2026-01-20 20:27:46.880398
30	30	run2	bronze_v1	rakesh	/proj1/pd/users/testcase/rakesh/proj/flow28nm_dashbrd/aes_cipher_up/bronze_v1/run2/dashboard	2025-12-25 08:02:39	2026-01-08 16:33:50.17231	2026-01-08 16:42:44.12437
40	40	run1	bronze_v1	priya	/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/gpu_core/bronze_v1/run1/dashboard	2025-12-24 10:22:18	2026-01-09 10:53:13.542496	2026-01-12 13:42:57.234111
39	39	run2	bronze_v1	bharath	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run2/dashboard	2025-12-24 11:28:47	2026-01-09 10:53:13.559456	2026-01-12 13:42:57.248692
41	41	run5	bronze_v4	Rakesh P	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run2/dashboard	2025-12-24 11:28:47	2026-01-09 10:53:13.530524	2026-01-12 13:42:57.215908
42	42	run4	bronze_v3	Rakesh P	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run2/dashboard	2025-12-24 11:28:47	2026-01-09 10:53:13.541336	2026-01-12 13:42:57.263168
\.


--
-- TOC entry 5393 (class 0 OID 16762)
-- Dependencies: 241
-- Data for Name: stage_constraint_metrics; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.stage_constraint_metrics (id, stage_id, max_tran_wns, max_tran_nvp, max_cap_wns, max_cap_nvp, max_fanout_wns, max_fanout_nvp, drc_violations, congestion_hotspot, noise_violations, created_at) FROM stdin;
1122	1123	N/A	0	N/A	0	N/A	0	N/A	N/A	N/A	2026-01-08 16:33:50.17231
1161	1162	N/A	0	N/A	0	N/A	0	N/A	N/A	N/A	2026-01-08 18:20:26.383115
1164	1165	N/A	0	N/A	0	N/A	0	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1163	1164	N/A	0	N/A	0	N/A	0	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1166	1167	N/A	0	N/A	0	-220.5	6	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1167	1168	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1171	1172	N/A	0	N/A	0	-220.5	6	0	N/A	N/A	2026-01-09 10:53:13.542496
1169	1170	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1165	1166	N/A	0	N/A	0	N/A	0	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1168	1169	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1170	1171	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1175	1175	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1172	1173	N/A	0	N/A	0	N/A	0	N/A	N/A	N/A	2026-01-09 10:53:13.541336
1177	1178	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1174	1176	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
1176	1177	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
\.


--
-- TOC entry 5391 (class 0 OID 16747)
-- Dependencies: 239
-- Data for Name: stage_timing_metrics; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.stage_timing_metrics (id, stage_id, internal_r2r_wns, internal_r2r_tns, internal_r2r_nvp, interface_i2r_wns, interface_i2r_tns, interface_i2r_nvp, interface_r2o_wns, interface_r2o_tns, interface_r2o_nvp, interface_i2o_wns, interface_i2o_tns, interface_i2o_nvp, hold_wns, hold_tns, hold_nvp, created_at) FROM stdin;
1122	1123	8.527	8	-5.2	7.463	4	4.25	7.421	0	-5.6	-5.0	8.4	3.4	N/A	N/A	N/A	2026-01-08 16:33:50.17231
1161	1162	8.527	8	-5.2	7.463	4	4.25	7.421	0	-5.6	-5.0	8.4	3.4	N/A	N/A	N/A	2026-01-08 18:20:26.383115
1164	1165	6.145	0	0	5.678	0	0	5.945	0	0	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1163	1164	8.527	0	0	7.463	0	0	7.421	0	0	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1166	1167	5.456	0	0	4.987	0	0	5.234	0	0	N/A	N/A	0	N/A	N/A	N/A	2026-01-09 10:53:13.542496
1167	1168	0.35	035	N/A	8.5	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1171	1172	5.345	0	0	4.876	0	0	5.123	0	0	N/A	N/A	0	0.018	0	0	2026-01-09 10:53:13.542496
1169	1170	N/A	N/A	N/A	0.5	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.559456
1165	1166	8.527	3.5	-5.5	7.463	0.85	7	7.421	-78	8.5	0.25	-8.6	8.5	8.5	-4.5	4.1	2026-01-09 10:53:13.530524
1168	1169	0.35	035	-8.5	8.5	7.2	7.1	8.6	N/A	7.1	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1170	1171	8.5	-8.6	8.1	0.5	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.530524
1174	1175	9.2	1.2	-0.25	1.5	3.2	4.5	N/A	N/A	6.5	2.5	N/A	1.02	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1172	1173	8.527	0	0	7.463	0	0	7.421	0	0	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
1177	1178	N/A	9.1	N/A	-5.2	-8.6	N/A	N/A	-4.5	N/A	5.6	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.549878
1175	1176	0.35	035	N/A	8.5	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
1176	1177	N/A	N/A	N/A	0.5	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	N/A	2026-01-09 10:53:13.541336
\.


--
-- TOC entry 5389 (class 0 OID 16726)
-- Dependencies: 237
-- Data for Name: stages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.stages (id, run_id, stage_name, "timestamp", stage_directory, run_status, runtime, memory_usage, log_errors, log_warnings, log_critical, area, inst_count, utilization, metal_density_max, min_pulse_width, min_period, double_switching, created_at, updated_at) FROM stdin;
1165	40	syn	2025-12-24 10:22:18	/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/gpu_core/bronze_v1/run1/syn	completed	00:08:51	1,234M	1	45	0	28456.78	45678	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.542496	2026-01-12 13:42:57.234111
1164	39	syn	2025-12-24 11:28:47	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/2/syn	continue_with_error	00:09:36	1,046M	0	75	0	6303.15	9846	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.559456	2026-01-12 13:42:57.248692
1167	40	place	2025-12-24 13:35:42	/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/gpu_core/bronze_v1/run1/pnr/place	completed	00:18:45	1,567M	3	67	1	28467.23	45678	72.1	\N	N/A	N/A	N/A	2026-01-09 10:53:13.542496	2026-01-12 13:42:57.234111
1168	39	init	2025-12-24 17:37:37	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run1/pnr/init	fail	00:00:00	N/A	3	52	0	\N	\N	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.559456	2026-01-12 13:42:57.248692
1172	40	route	2025-12-24 17:28:05	/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/gpu_core/bronze_v1/run1/pnr/route	completed	00:42:18	1,892M	3	156	0	28467.45	45678	72.2	\N	N/A	N/A	N/A	2026-01-09 10:53:13.542496	2026-01-12 13:42:57.234111
1170	39	floorplan	2025-12-24 17:43:04	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run2/pnr/floorplan	fail	00:00:00	N/A	8	127	0	\N	\N	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.559456	2026-01-12 13:42:57.248692
1166	41	syn	2025-12-24 11:28:47	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/2/syn	continue_with_error	00:09:36	1,046M	0	75	0	6303.15	9846	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.530524	2026-01-12 13:42:57.215908
1169	41	init	2025-12-24 17:37:37	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run1/pnr/init	fail	00:00:00	N/A	3	52	0	\N	\N	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.530524	2026-01-12 13:42:57.215908
1171	41	floorplan	2025-12-24 17:43:04	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run2/pnr/floorplan	fail	00:00:00	N/A	8	127	0	\N	\N	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.530524	2026-01-12 13:42:57.215908
1175	38	init	2025-12-25 15:18:08	/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_up/bronze_v1/run2/pnr/init	fail	00:02:44	3924.81M	33	510	1	6303.15	9846	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.549878	2026-01-12 13:42:57.332984
1173	42	syn	2025-12-24 11:28:47	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/2/syn	continue_with_error	00:09:36	1,046M	0	75	0	6303.15	9846	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.541336	2026-01-12 13:42:57.263168
1178	38	floorplan	2025-12-25 15:25:40	/proj1/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_up/bronze_v1/run2/pnr/floorplan	fail	00:02:44	N/A	8	138	0	\N	\N	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.549878	2026-01-12 13:42:57.332984
1176	42	init	2025-12-24 17:37:37	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run1/pnr/init	fail	00:00:00	N/A	3	52	0	\N	\N	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.541336	2026-01-12 13:42:57.263168
1177	42	floorplan	2025-12-24 17:43:04	/proj2/pd/users/testcase/Bharath/proj/flow28nm_dashbrd/aes_cipher_down/bronze_v2/run2/pnr/floorplan	fail	00:00:00	N/A	8	127	0	\N	\N	\N	\N	N/A	N/A	N/A	2026-01-09 10:53:13.541336	2026-01-12 13:42:57.263168
1123	30	syn	2025-12-25 08:02:39	/proj1/pd/users/testcase/rakesh/proj/flow28nm_dashbrd/aes_cipher_up/bronze_v1/run2/syn	continue_with_error	00:08:15	1,045M	0	74	0	6303.15	9846	\N	\N	N/A	N/A	N/A	2026-01-08 16:33:50.17231	2026-01-08 16:42:44.12437
1162	38	syn	2025-12-25 08:02:39	/proj1/pd/users/testcase/rakesh/proj/flow28nm_dashbrd/aes_cipher_up/bronze_v1/run2/syn	continue_with_error	00:08:15	1,045M	0	74	0	6303.15	9846	\N	\N	N/A	N/A	N/A	2026-01-08 18:20:26.383115	2026-01-20 20:27:46.880398
\.


--
-- TOC entry 5404 (class 0 OID 16928)
-- Dependencies: 252
-- Data for Name: user_projects; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_projects (user_id, project_id, created_at) FROM stdin;
12	34	2026-01-13 10:24:56.857727
\.


--
-- TOC entry 5374 (class 0 OID 16500)
-- Dependencies: 222
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, username, email, password_hash, full_name, role, is_active, created_at, updated_at, last_login, domain_id, ipaddress, port, ssh_user, sshpassword_hash) FROM stdin;
1	admin	admin@asi.com	$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy	System Administrator	admin	t	2025-12-14 13:48:31.833965	2025-12-14 13:48:31.833965	\N	\N	\N	\N	\N	\N
2	pm1	pm1@asi.com	$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy	Project Manager 1	project_manager	t	2025-12-14 13:48:31.833965	2025-12-14 13:48:31.833965	\N	\N	\N	\N	\N	\N
3	lead1	lead1@asi.com	$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy	Lead Engineer 1	lead	t	2025-12-14 13:48:31.833965	2025-12-14 13:48:31.833965	\N	\N	\N	\N	\N	\N
4	engineer1	engineer1@asi.com	$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy	Engineer 1	engineer	t	2025-12-14 13:48:31.833965	2025-12-14 13:48:31.833965	\N	\N	\N	\N	\N	\N
5	customer1	customer1@asi.com	$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy	Customer 1	customer	t	2025-12-14 13:48:31.833965	2025-12-14 13:48:31.833965	\N	\N	\N	\N	\N	\N
13	ranjitha.be_zoho	ranjitha.be@sumedhait.com	zoho_oauth_user	Ranjitha BE	engineer	t	2026-01-20 17:18:47.688251	2026-01-20 17:46:39.823235	2026-01-20 17:46:39.823235	\N	\N	\N	\N	\N
6	admin1	admin@1.com	$2a$10$6fuNS9.c5gNt20SsPmmTPO04289kKQcI1wr1QFiCcMt7McQTZSsQC	Admin User	admin	t	2025-12-14 13:48:39.796793	2026-01-20 17:57:11.750644	2026-01-20 17:57:11.750644	\N	\N	\N	\N	\N
7	rakeshkumar	r@1.com	$2a$10$K0wFSVTBswKi7pDgWwE8G.cyy916feF9Ca5RUBXRoRC/tiBNFJQ9u	rakesh	project_manager	t	2025-12-14 15:15:25.393885	2025-12-15 14:59:53.704674	2025-12-15 14:59:53.704674	5	\N	\N	\N	\N
8	sashi.challa_zoho	sashi.challa@sumedhait.com	zoho_oauth_user	Sashikanth	engineer	t	2025-12-23 15:09:33.652887	2025-12-23 18:09:16.181226	2025-12-23 18:09:16.181226	\N	\N	\N	\N	\N
9	rakesh.p_zoho	rakesh.p@sumedhait.com	zoho_oauth_user	Rakesh P	engineer	t	2025-12-23 16:05:11.640264	2026-01-12 13:43:44.866225	2026-01-12 12:24:56.516894	\N	122.123.12	25	rakesh	$2a$10$Fg1rxtaLpUD0mTEa6lmEYuoNnXEiY4YPtjjkK/R3Wi4t1x/5iHRYy
10	ganga.m_zoho	ganga.m@sumedhait.com	zoho_oauth_user	Ganga Lakshmi Mudda	admin	t	2025-12-23 16:29:59.58641	2026-01-12 18:01:30.105937	2025-12-23 16:34:19.117012	\N	852852	85	ganga	$2a$10$Kobmw4bfHQG9iisbD2.YvuLD64lhV2WYbAvuk/nwzCERODGsbBSZK
11	bhavya.s_zoho	bhavya.s@sumedhait.com	zoho_oauth_user	Bhavya Sree	admin	t	2025-12-23 16:35:29.512242	2025-12-23 16:41:04.576487	2025-12-23 16:41:04.576487	\N	\N	\N	\N	\N
12	c	c@1.com	$2a$10$cJteUZL0Ry5xZC/arrsKyO4yWH9CtbnxoRJ8JJoW9wXvJCQKDOv7C	\N	customer	t	2026-01-13 10:24:56.857727	2026-01-13 10:34:51.977692	2026-01-13 10:34:51.977692	\N	\N	\N	\N	\N
\.


--
-- TOC entry 5383 (class 0 OID 16631)
-- Dependencies: 231
-- Data for Name: zoho_projects_mapping; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.zoho_projects_mapping (id, zoho_project_id, local_project_id, zoho_project_name, zoho_project_data, synced_at, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 5381 (class 0 OID 16609)
-- Dependencies: 229
-- Data for Name: zoho_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.zoho_tokens (id, user_id, access_token, refresh_token, token_type, expires_in, expires_at, scope, created_at, updated_at) FROM stdin;
12	10	1000.700c7aa4a092862b863f917bee1e8078.507f1de2243aaa269a4854d640530bb0	1000.9664305cc7d039b3658753e6b0068dd0.ab8c6f7c34cd6d98a58d4a5bc8e306ec	Bearer	3600	2025-12-23 17:34:19.122	AaaServer.profile.read profile email ZohoProjects.projects.READ ZohoProjects.portals.READ ZOHOPEOPLE.forms.ALL ZOHOPEOPLE.employee.ALL	2025-12-23 16:29:59.588985	2025-12-23 16:34:19.123796
16	11	1000.833fd534be1c104c295fbaebf69a1297.30adb6729670116ff4178eb2e051c304	1000.83fbe67538046a451326aef05d87bc7c.ad5bcb51a8c53d2d862f9180557eb862	Bearer	3600	2025-12-23 17:41:04.581	AaaServer.profile.read profile email ZohoProjects.projects.READ ZohoProjects.portals.READ ZOHOPEOPLE.forms.ALL ZOHOPEOPLE.employee.ALL	2025-12-23 16:35:29.517192	2025-12-23 16:41:04.583878
29	8	1000.8124bba0e3ce269af0582ba7bfa2a1f7.5b049630511c653fbde686e5ac5b6ca5	1000.383bf910e983737bcabae35dc7b44582.06a60aea7d047c5dbcf217e3ef3afaae	Bearer	3600	2025-12-23 19:09:16.19	AaaServer.profile.read profile email ZohoProjects.projects.READ ZohoProjects.portals.READ ZOHOPEOPLE.forms.ALL ZOHOPEOPLE.employee.ALL	2025-12-23 18:09:16.193347	2025-12-23 18:09:16.193347
4	9	1000.e85d59a922621bb7b39da9384a8bb855.a99109798731d4593df61da148b84e34	1000.634c5cf09e3219f045ff654eaf73f5bb.bb93eb431f1fceff564ec0fbcc777b6a	Bearer	3600	2026-01-12 13:24:56.541	AaaServer.profile.read profile email ZohoProjects.projects.READ ZohoProjects.portals.READ ZohoProjects.tasks.READ ZohoProjects.tasklists.READ ZOHOPEOPLE.forms.ALL ZOHOPEOPLE.employee.ALL	2025-12-23 16:05:11.646298	2026-01-12 12:24:56.543766
54	13	1000.bb79cc07a43a3af3202a40ea25c1b02b.3fdf8db8a9bab92866435c8a8088b6e8	1000.d2295c6986ec3ac42450051b1d4e141a.aa6f44e3c735f7ca2949419d3fdb9389	Bearer	3600	2026-01-20 18:46:39.847	AaaServer.profile.read profile email ZohoProjects.projects.READ ZohoProjects.portals.READ ZohoProjects.tasks.READ ZohoProjects.tasklists.READ ZOHOPEOPLE.forms.ALL ZOHOPEOPLE.employee.ALL	2026-01-20 17:18:47.719699	2026-01-20 17:46:39.84846
53	6	1000.f4f189db96c0665ad8a516da420942a4.6c7e0a11908a0b6ad759a0c84ea458f5	1000.84bda5387412ef781a0b7f655e42f155.7cd7b9ea2a2da6e2f1261ca6a0d1a506	Bearer	3600	2026-01-20 21:27:55.332	AaaServer.profile.read profile email ZohoProjects.projects.READ ZohoProjects.portals.READ ZohoProjects.tasks.READ ZohoProjects.tasklists.READ ZOHOPEOPLE.forms.ALL ZOHOPEOPLE.employee.ALL	2026-01-19 16:30:31.537984	2026-01-20 20:27:55.33492
\.


--
-- TOC entry 5466 (class 0 OID 0)
-- Dependencies: 271
-- Name: agent_activity_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.agent_activity_logs_id_seq', 1, false);


--
-- TOC entry 5467 (class 0 OID 0)
-- Dependencies: 267
-- Name: agent_command_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.agent_command_history_id_seq', 1, false);


--
-- TOC entry 5468 (class 0 OID 0)
-- Dependencies: 269
-- Name: agent_file_operations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.agent_file_operations_id_seq', 1, false);


--
-- TOC entry 5469 (class 0 OID 0)
-- Dependencies: 265
-- Name: agent_jobs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.agent_jobs_id_seq', 1, false);


--
-- TOC entry 5470 (class 0 OID 0)
-- Dependencies: 263
-- Name: agents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.agents_id_seq', 1, false);


--
-- TOC entry 5471 (class 0 OID 0)
-- Dependencies: 250
-- Name: ai_summaries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.ai_summaries_id_seq', 97, true);


--
-- TOC entry 5472 (class 0 OID 0)
-- Dependencies: 232
-- Name: blocks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.blocks_id_seq', 42, true);


--
-- TOC entry 5473 (class 0 OID 0)
-- Dependencies: 257
-- Name: c_report_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.c_report_data_id_seq', 1, false);


--
-- TOC entry 5474 (class 0 OID 0)
-- Dependencies: 259
-- Name: check_item_approvals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.check_item_approvals_id_seq', 1, false);


--
-- TOC entry 5475 (class 0 OID 0)
-- Dependencies: 255
-- Name: check_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.check_items_id_seq', 1, false);


--
-- TOC entry 5476 (class 0 OID 0)
-- Dependencies: 253
-- Name: checklists_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.checklists_id_seq', 1, false);


--
-- TOC entry 5477 (class 0 OID 0)
-- Dependencies: 217
-- Name: chips_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.chips_id_seq', 3, true);


--
-- TOC entry 5478 (class 0 OID 0)
-- Dependencies: 219
-- Name: designs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.designs_id_seq', 2, true);


--
-- TOC entry 5479 (class 0 OID 0)
-- Dependencies: 223
-- Name: domains_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.domains_id_seq', 11, true);


--
-- TOC entry 5480 (class 0 OID 0)
-- Dependencies: 244
-- Name: drv_violations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.drv_violations_id_seq', 2302, true);


--
-- TOC entry 5481 (class 0 OID 0)
-- Dependencies: 242
-- Name: path_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.path_groups_id_seq', 3069, true);


--
-- TOC entry 5482 (class 0 OID 0)
-- Dependencies: 248
-- Name: physical_verification_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.physical_verification_id_seq', 1262, true);


--
-- TOC entry 5483 (class 0 OID 0)
-- Dependencies: 246
-- Name: power_ir_em_checks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.power_ir_em_checks_id_seq', 1262, true);


--
-- TOC entry 5484 (class 0 OID 0)
-- Dependencies: 225
-- Name: projects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.projects_id_seq', 44, true);


--
-- TOC entry 5485 (class 0 OID 0)
-- Dependencies: 261
-- Name: qms_audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.qms_audit_log_id_seq', 1, false);


--
-- TOC entry 5486 (class 0 OID 0)
-- Dependencies: 234
-- Name: runs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.runs_id_seq', 42, true);


--
-- TOC entry 5487 (class 0 OID 0)
-- Dependencies: 240
-- Name: stage_constraint_metrics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.stage_constraint_metrics_id_seq', 1262, true);


--
-- TOC entry 5488 (class 0 OID 0)
-- Dependencies: 238
-- Name: stage_timing_metrics_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.stage_timing_metrics_id_seq', 1262, true);


--
-- TOC entry 5489 (class 0 OID 0)
-- Dependencies: 236
-- Name: stages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.stages_id_seq', 1263, true);


--
-- TOC entry 5490 (class 0 OID 0)
-- Dependencies: 221
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_id_seq', 13, true);


--
-- TOC entry 5491 (class 0 OID 0)
-- Dependencies: 230
-- Name: zoho_projects_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.zoho_projects_mapping_id_seq', 1, false);


--
-- TOC entry 5492 (class 0 OID 0)
-- Dependencies: 228
-- Name: zoho_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.zoho_tokens_id_seq', 55, true);


--
-- TOC entry 5154 (class 2606 OID 17218)
-- Name: agent_activity_logs agent_activity_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_activity_logs
    ADD CONSTRAINT agent_activity_logs_pkey PRIMARY KEY (id);


--
-- TOC entry 5145 (class 2606 OID 17167)
-- Name: agent_command_history agent_command_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_command_history
    ADD CONSTRAINT agent_command_history_pkey PRIMARY KEY (id);


--
-- TOC entry 5150 (class 2606 OID 17198)
-- Name: agent_file_operations agent_file_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_file_operations
    ADD CONSTRAINT agent_file_operations_pkey PRIMARY KEY (id);


--
-- TOC entry 5139 (class 2606 OID 17142)
-- Name: agent_jobs agent_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_jobs
    ADD CONSTRAINT agent_jobs_pkey PRIMARY KEY (id);


--
-- TOC entry 5132 (class 2606 OID 17124)
-- Name: agents agents_agent_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_agent_token_key UNIQUE (agent_token);


--
-- TOC entry 5134 (class 2606 OID 17122)
-- Name: agents agents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_pkey PRIMARY KEY (id);


--
-- TOC entry 5095 (class 2606 OID 16846)
-- Name: ai_summaries ai_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_summaries
    ADD CONSTRAINT ai_summaries_pkey PRIMARY KEY (id);


--
-- TOC entry 5039 (class 2606 OID 16699)
-- Name: blocks blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_pkey PRIMARY KEY (id);


--
-- TOC entry 5041 (class 2606 OID 16701)
-- Name: blocks blocks_project_id_block_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_project_id_block_name_key UNIQUE (project_id, block_name);


--
-- TOC entry 5117 (class 2606 OID 17010)
-- Name: c_report_data c_report_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.c_report_data
    ADD CONSTRAINT c_report_data_pkey PRIMARY KEY (id);


--
-- TOC entry 5122 (class 2606 OID 17032)
-- Name: check_item_approvals check_item_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_item_approvals
    ADD CONSTRAINT check_item_approvals_pkey PRIMARY KEY (id);


--
-- TOC entry 5110 (class 2606 OID 16993)
-- Name: check_items check_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_items
    ADD CONSTRAINT check_items_pkey PRIMARY KEY (id);


--
-- TOC entry 5102 (class 2606 OID 16958)
-- Name: checklists checklists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklists
    ADD CONSTRAINT checklists_pkey PRIMARY KEY (id);


--
-- TOC entry 4990 (class 2606 OID 16467)
-- Name: chips chips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chips
    ADD CONSTRAINT chips_pkey PRIMARY KEY (id);


--
-- TOC entry 4995 (class 2606 OID 16479)
-- Name: designs designs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designs
    ADD CONSTRAINT designs_pkey PRIMARY KEY (id);


--
-- TOC entry 5013 (class 2606 OID 16563)
-- Name: domains domains_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains
    ADD CONSTRAINT domains_code_key UNIQUE (code);


--
-- TOC entry 5015 (class 2606 OID 16561)
-- Name: domains domains_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains
    ADD CONSTRAINT domains_name_key UNIQUE (name);


--
-- TOC entry 5017 (class 2606 OID 16559)
-- Name: domains domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains
    ADD CONSTRAINT domains_pkey PRIMARY KEY (id);


--
-- TOC entry 5079 (class 2606 OID 16798)
-- Name: drv_violations drv_violations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drv_violations
    ADD CONSTRAINT drv_violations_pkey PRIMARY KEY (id);


--
-- TOC entry 5081 (class 2606 OID 16800)
-- Name: drv_violations drv_violations_stage_id_violation_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drv_violations
    ADD CONSTRAINT drv_violations_stage_id_violation_type_key UNIQUE (stage_id, violation_type);


--
-- TOC entry 5075 (class 2606 OID 16783)
-- Name: path_groups path_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.path_groups
    ADD CONSTRAINT path_groups_pkey PRIMARY KEY (id);


--
-- TOC entry 5077 (class 2606 OID 16785)
-- Name: path_groups path_groups_stage_id_group_type_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.path_groups
    ADD CONSTRAINT path_groups_stage_id_group_type_group_name_key UNIQUE (stage_id, group_type, group_name);


--
-- TOC entry 5091 (class 2606 OID 16828)
-- Name: physical_verification physical_verification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_verification
    ADD CONSTRAINT physical_verification_pkey PRIMARY KEY (id);


--
-- TOC entry 5093 (class 2606 OID 16830)
-- Name: physical_verification physical_verification_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_verification
    ADD CONSTRAINT physical_verification_stage_id_key UNIQUE (stage_id);


--
-- TOC entry 5086 (class 2606 OID 16813)
-- Name: power_ir_em_checks power_ir_em_checks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_ir_em_checks
    ADD CONSTRAINT power_ir_em_checks_pkey PRIMARY KEY (id);


--
-- TOC entry 5088 (class 2606 OID 16815)
-- Name: power_ir_em_checks power_ir_em_checks_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_ir_em_checks
    ADD CONSTRAINT power_ir_em_checks_stage_id_key UNIQUE (stage_id);


--
-- TOC entry 5025 (class 2606 OID 16595)
-- Name: project_domains project_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_domains
    ADD CONSTRAINT project_domains_pkey PRIMARY KEY (project_id, domain_id);


--
-- TOC entry 5022 (class 2606 OID 16583)
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- TOC entry 5130 (class 2606 OID 17062)
-- Name: qms_audit_log qms_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qms_audit_log
    ADD CONSTRAINT qms_audit_log_pkey PRIMARY KEY (id);


--
-- TOC entry 5050 (class 2606 OID 16719)
-- Name: runs runs_block_id_experiment_rtl_tag_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runs
    ADD CONSTRAINT runs_block_id_experiment_rtl_tag_key UNIQUE (block_id, experiment, rtl_tag);


--
-- TOC entry 5052 (class 2606 OID 16717)
-- Name: runs runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runs
    ADD CONSTRAINT runs_pkey PRIMARY KEY (id);


--
-- TOC entry 5068 (class 2606 OID 16768)
-- Name: stage_constraint_metrics stage_constraint_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_constraint_metrics
    ADD CONSTRAINT stage_constraint_metrics_pkey PRIMARY KEY (id);


--
-- TOC entry 5070 (class 2606 OID 16770)
-- Name: stage_constraint_metrics stage_constraint_metrics_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_constraint_metrics
    ADD CONSTRAINT stage_constraint_metrics_stage_id_key UNIQUE (stage_id);


--
-- TOC entry 5063 (class 2606 OID 16753)
-- Name: stage_timing_metrics stage_timing_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_timing_metrics
    ADD CONSTRAINT stage_timing_metrics_pkey PRIMARY KEY (id);


--
-- TOC entry 5065 (class 2606 OID 16755)
-- Name: stage_timing_metrics stage_timing_metrics_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_timing_metrics
    ADD CONSTRAINT stage_timing_metrics_stage_id_key UNIQUE (stage_id);


--
-- TOC entry 5058 (class 2606 OID 16738)
-- Name: stages stages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stages
    ADD CONSTRAINT stages_pkey PRIMARY KEY (id);


--
-- TOC entry 5060 (class 2606 OID 16740)
-- Name: stages stages_run_id_stage_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stages
    ADD CONSTRAINT stages_run_id_stage_name_key UNIQUE (run_id, stage_name);


--
-- TOC entry 5100 (class 2606 OID 16933)
-- Name: user_projects user_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_projects
    ADD CONSTRAINT user_projects_pkey PRIMARY KEY (user_id, project_id);


--
-- TOC entry 5007 (class 2606 OID 16515)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 5009 (class 2606 OID 16511)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 5011 (class 2606 OID 16513)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 5035 (class 2606 OID 16641)
-- Name: zoho_projects_mapping zoho_projects_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_projects_mapping
    ADD CONSTRAINT zoho_projects_mapping_pkey PRIMARY KEY (id);


--
-- TOC entry 5037 (class 2606 OID 16643)
-- Name: zoho_projects_mapping zoho_projects_mapping_zoho_project_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_projects_mapping
    ADD CONSTRAINT zoho_projects_mapping_zoho_project_id_key UNIQUE (zoho_project_id);


--
-- TOC entry 5029 (class 2606 OID 16619)
-- Name: zoho_tokens zoho_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_tokens
    ADD CONSTRAINT zoho_tokens_pkey PRIMARY KEY (id);


--
-- TOC entry 5031 (class 2606 OID 16621)
-- Name: zoho_tokens zoho_tokens_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_tokens
    ADD CONSTRAINT zoho_tokens_user_id_key UNIQUE (user_id);


--
-- TOC entry 5155 (class 1259 OID 17239)
-- Name: idx_agent_activity_logs_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_activity_logs_agent ON public.agent_activity_logs USING btree (agent_id);


--
-- TOC entry 5156 (class 1259 OID 17240)
-- Name: idx_agent_activity_logs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_activity_logs_created_at ON public.agent_activity_logs USING btree (created_at DESC);


--
-- TOC entry 5157 (class 1259 OID 17238)
-- Name: idx_agent_activity_logs_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_activity_logs_job ON public.agent_activity_logs USING btree (job_id);


--
-- TOC entry 5146 (class 1259 OID 17234)
-- Name: idx_agent_command_history_executed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_command_history_executed_at ON public.agent_command_history USING btree (executed_at DESC);


--
-- TOC entry 5147 (class 1259 OID 17233)
-- Name: idx_agent_command_history_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_command_history_project ON public.agent_command_history USING btree (project_id);


--
-- TOC entry 5148 (class 1259 OID 17235)
-- Name: idx_agent_command_history_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_command_history_user ON public.agent_command_history USING btree (executed_by);


--
-- TOC entry 5151 (class 1259 OID 17236)
-- Name: idx_agent_file_operations_job; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_file_operations_job ON public.agent_file_operations USING btree (job_id);


--
-- TOC entry 5152 (class 1259 OID 17237)
-- Name: idx_agent_file_operations_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_file_operations_status ON public.agent_file_operations USING btree (status);


--
-- TOC entry 5140 (class 1259 OID 17231)
-- Name: idx_agent_jobs_assigned_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_jobs_assigned_agent ON public.agent_jobs USING btree (assigned_agent_id) WHERE (assigned_agent_id IS NOT NULL);


--
-- TOC entry 5141 (class 1259 OID 17232)
-- Name: idx_agent_jobs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_jobs_created_at ON public.agent_jobs USING btree (created_at DESC);


--
-- TOC entry 5142 (class 1259 OID 17230)
-- Name: idx_agent_jobs_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_jobs_project ON public.agent_jobs USING btree (project_id);


--
-- TOC entry 5143 (class 1259 OID 17229)
-- Name: idx_agent_jobs_status_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_jobs_status_priority ON public.agent_jobs USING btree (status, priority DESC, created_at) WHERE ((status)::text = 'pending'::text);


--
-- TOC entry 5135 (class 1259 OID 17242)
-- Name: idx_agents_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_active ON public.agents USING btree (is_active) WHERE (is_active = true);


--
-- TOC entry 5136 (class 1259 OID 17243)
-- Name: idx_agents_heartbeat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_heartbeat ON public.agents USING btree (last_heartbeat);


--
-- TOC entry 5137 (class 1259 OID 17241)
-- Name: idx_agents_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_token ON public.agents USING btree (agent_token);


--
-- TOC entry 5096 (class 1259 OID 16872)
-- Name: idx_ai_summaries_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_summaries_stage_id ON public.ai_summaries USING btree (stage_id);


--
-- TOC entry 5042 (class 1259 OID 16853)
-- Name: idx_blocks_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blocks_name ON public.blocks USING btree (block_name);


--
-- TOC entry 5043 (class 1259 OID 16852)
-- Name: idx_blocks_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blocks_project_id ON public.blocks USING btree (project_id);


--
-- TOC entry 5044 (class 1259 OID 16854)
-- Name: idx_blocks_project_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blocks_project_name ON public.blocks USING btree (project_id, block_name);


--
-- TOC entry 5118 (class 1259 OID 17089)
-- Name: idx_c_report_data_check_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_c_report_data_check_item_id ON public.c_report_data USING btree (check_item_id);


--
-- TOC entry 5119 (class 1259 OID 17091)
-- Name: idx_c_report_data_signoff_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_c_report_data_signoff_by ON public.c_report_data USING btree (signoff_by);


--
-- TOC entry 5120 (class 1259 OID 17090)
-- Name: idx_c_report_data_signoff_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_c_report_data_signoff_status ON public.c_report_data USING btree (signoff_status);


--
-- TOC entry 5123 (class 1259 OID 17092)
-- Name: idx_check_item_approvals_check_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_item_approvals_check_item_id ON public.check_item_approvals USING btree (check_item_id);


--
-- TOC entry 5124 (class 1259 OID 17093)
-- Name: idx_check_item_approvals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_item_approvals_status ON public.check_item_approvals USING btree (status);


--
-- TOC entry 5111 (class 1259 OID 17085)
-- Name: idx_check_items_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_category ON public.check_items USING btree (category);


--
-- TOC entry 5112 (class 1259 OID 17084)
-- Name: idx_check_items_checklist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_checklist_id ON public.check_items USING btree (checklist_id);


--
-- TOC entry 5113 (class 1259 OID 17087)
-- Name: idx_check_items_severity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_severity ON public.check_items USING btree (severity);


--
-- TOC entry 5114 (class 1259 OID 17086)
-- Name: idx_check_items_sub_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_sub_category ON public.check_items USING btree (sub_category);


--
-- TOC entry 5115 (class 1259 OID 17088)
-- Name: idx_check_items_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_version ON public.check_items USING btree (version);


--
-- TOC entry 5103 (class 1259 OID 17081)
-- Name: idx_checklists_approver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_approver_id ON public.checklists USING btree (approver_id);


--
-- TOC entry 5104 (class 1259 OID 17078)
-- Name: idx_checklists_block_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_block_id ON public.checklists USING btree (block_id);


--
-- TOC entry 5105 (class 1259 OID 17079)
-- Name: idx_checklists_milestone_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_milestone_id ON public.checklists USING btree (milestone_id);


--
-- TOC entry 5106 (class 1259 OID 17080)
-- Name: idx_checklists_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_status ON public.checklists USING btree (status);


--
-- TOC entry 5107 (class 1259 OID 17083)
-- Name: idx_checklists_submitted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_submitted_at ON public.checklists USING btree (submitted_at);


--
-- TOC entry 5108 (class 1259 OID 17082)
-- Name: idx_checklists_submitted_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_submitted_by ON public.checklists USING btree (submitted_by);


--
-- TOC entry 4991 (class 1259 OID 16540)
-- Name: idx_chips_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chips_created_by ON public.chips USING btree (created_by);


--
-- TOC entry 4992 (class 1259 OID 16485)
-- Name: idx_chips_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chips_status ON public.chips USING btree (status);


--
-- TOC entry 4993 (class 1259 OID 16541)
-- Name: idx_chips_updated_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chips_updated_by ON public.chips USING btree (updated_by);


--
-- TOC entry 4996 (class 1259 OID 16486)
-- Name: idx_designs_chip_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_chip_id ON public.designs USING btree (chip_id);


--
-- TOC entry 4997 (class 1259 OID 16542)
-- Name: idx_designs_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_created_by ON public.designs USING btree (created_by);


--
-- TOC entry 4998 (class 1259 OID 16487)
-- Name: idx_designs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_status ON public.designs USING btree (status);


--
-- TOC entry 4999 (class 1259 OID 16543)
-- Name: idx_designs_updated_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_updated_by ON public.designs USING btree (updated_by);


--
-- TOC entry 5018 (class 1259 OID 16564)
-- Name: idx_domains_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_domains_code ON public.domains USING btree (code);


--
-- TOC entry 5019 (class 1259 OID 16565)
-- Name: idx_domains_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_domains_is_active ON public.domains USING btree (is_active);


--
-- TOC entry 5082 (class 1259 OID 16868)
-- Name: idx_drv_violations_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drv_violations_stage_id ON public.drv_violations USING btree (stage_id);


--
-- TOC entry 5083 (class 1259 OID 16869)
-- Name: idx_drv_violations_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drv_violations_type ON public.drv_violations USING btree (violation_type);


--
-- TOC entry 5071 (class 1259 OID 16867)
-- Name: idx_path_groups_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_path_groups_name ON public.path_groups USING btree (group_name);


--
-- TOC entry 5072 (class 1259 OID 16865)
-- Name: idx_path_groups_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_path_groups_stage_id ON public.path_groups USING btree (stage_id);


--
-- TOC entry 5073 (class 1259 OID 16866)
-- Name: idx_path_groups_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_path_groups_type ON public.path_groups USING btree (group_type);


--
-- TOC entry 5089 (class 1259 OID 16871)
-- Name: idx_physical_verification_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_verification_stage_id ON public.physical_verification USING btree (stage_id);


--
-- TOC entry 5084 (class 1259 OID 16870)
-- Name: idx_power_ir_em_checks_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_power_ir_em_checks_stage_id ON public.power_ir_em_checks USING btree (stage_id);


--
-- TOC entry 5023 (class 1259 OID 16606)
-- Name: idx_project_domains_domain_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_domains_domain_id ON public.project_domains USING btree (domain_id);


--
-- TOC entry 5020 (class 1259 OID 16589)
-- Name: idx_projects_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_projects_created_by ON public.projects USING btree (created_by);


--
-- TOC entry 5125 (class 1259 OID 17095)
-- Name: idx_qms_audit_log_check_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_check_item_id ON public.qms_audit_log USING btree (check_item_id);


--
-- TOC entry 5126 (class 1259 OID 17094)
-- Name: idx_qms_audit_log_checklist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_checklist_id ON public.qms_audit_log USING btree (checklist_id);


--
-- TOC entry 5127 (class 1259 OID 17097)
-- Name: idx_qms_audit_log_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_created_at ON public.qms_audit_log USING btree (created_at);


--
-- TOC entry 5128 (class 1259 OID 17096)
-- Name: idx_qms_audit_log_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_user_id ON public.qms_audit_log USING btree (user_id);


--
-- TOC entry 5045 (class 1259 OID 16855)
-- Name: idx_runs_block_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_block_id ON public.runs USING btree (block_id);


--
-- TOC entry 5046 (class 1259 OID 16856)
-- Name: idx_runs_experiment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_experiment ON public.runs USING btree (experiment);


--
-- TOC entry 5047 (class 1259 OID 16857)
-- Name: idx_runs_rtl_tag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_rtl_tag ON public.runs USING btree (rtl_tag);


--
-- TOC entry 5048 (class 1259 OID 16858)
-- Name: idx_runs_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_user_name ON public.runs USING btree (user_name);


--
-- TOC entry 5066 (class 1259 OID 16864)
-- Name: idx_stage_constraint_metrics_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stage_constraint_metrics_stage_id ON public.stage_constraint_metrics USING btree (stage_id);


--
-- TOC entry 5061 (class 1259 OID 16863)
-- Name: idx_stage_timing_metrics_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stage_timing_metrics_stage_id ON public.stage_timing_metrics USING btree (stage_id);


--
-- TOC entry 5053 (class 1259 OID 16860)
-- Name: idx_stages_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_name ON public.stages USING btree (stage_name);


--
-- TOC entry 5054 (class 1259 OID 16859)
-- Name: idx_stages_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_run_id ON public.stages USING btree (run_id);


--
-- TOC entry 5055 (class 1259 OID 16861)
-- Name: idx_stages_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_status ON public.stages USING btree (run_status);


--
-- TOC entry 5056 (class 1259 OID 16862)
-- Name: idx_stages_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_timestamp ON public.stages USING btree ("timestamp");


--
-- TOC entry 5097 (class 1259 OID 16945)
-- Name: idx_user_projects_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_projects_project_id ON public.user_projects USING btree (project_id);


--
-- TOC entry 5098 (class 1259 OID 16944)
-- Name: idx_user_projects_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_projects_user_id ON public.user_projects USING btree (user_id);


--
-- TOC entry 5000 (class 1259 OID 16572)
-- Name: idx_users_domain_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_domain_id ON public.users USING btree (domain_id);


--
-- TOC entry 5001 (class 1259 OID 16516)
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_email ON public.users USING btree (email);


--
-- TOC entry 5002 (class 1259 OID 16927)
-- Name: idx_users_ipaddress; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_ipaddress ON public.users USING btree (ipaddress) WHERE (ipaddress IS NOT NULL);


--
-- TOC entry 5003 (class 1259 OID 16519)
-- Name: idx_users_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_is_active ON public.users USING btree (is_active);


--
-- TOC entry 5004 (class 1259 OID 16518)
-- Name: idx_users_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_role ON public.users USING btree (role);


--
-- TOC entry 5005 (class 1259 OID 16517)
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_username ON public.users USING btree (username);


--
-- TOC entry 5032 (class 1259 OID 16649)
-- Name: idx_zoho_projects_mapping_local_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_projects_mapping_local_id ON public.zoho_projects_mapping USING btree (local_project_id);


--
-- TOC entry 5033 (class 1259 OID 16650)
-- Name: idx_zoho_projects_mapping_zoho_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_projects_mapping_zoho_id ON public.zoho_projects_mapping USING btree (zoho_project_id);


--
-- TOC entry 5026 (class 1259 OID 16628)
-- Name: idx_zoho_tokens_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_tokens_expires_at ON public.zoho_tokens USING btree (expires_at);


--
-- TOC entry 5027 (class 1259 OID 16627)
-- Name: idx_zoho_tokens_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_tokens_user_id ON public.zoho_tokens USING btree (user_id);


--
-- TOC entry 5217 (class 2620 OID 16876)
-- Name: ai_summaries update_ai_summaries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ai_summaries_updated_at BEFORE UPDATE ON public.ai_summaries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5214 (class 2620 OID 16873)
-- Name: blocks update_blocks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_blocks_updated_at BEFORE UPDATE ON public.blocks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5220 (class 2620 OID 17100)
-- Name: c_report_data update_c_report_data_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_c_report_data_updated_at BEFORE UPDATE ON public.c_report_data FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5221 (class 2620 OID 17101)
-- Name: check_item_approvals update_check_item_approvals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_check_item_approvals_updated_at BEFORE UPDATE ON public.check_item_approvals FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5219 (class 2620 OID 17099)
-- Name: check_items update_check_items_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_check_items_updated_at BEFORE UPDATE ON public.check_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5218 (class 2620 OID 17098)
-- Name: checklists update_checklists_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_checklists_updated_at BEFORE UPDATE ON public.checklists FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5207 (class 2620 OID 16546)
-- Name: chips update_chips_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_chips_updated_at BEFORE UPDATE ON public.chips FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5208 (class 2620 OID 16547)
-- Name: designs update_designs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_designs_updated_at BEFORE UPDATE ON public.designs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5210 (class 2620 OID 16566)
-- Name: domains update_domains_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_domains_updated_at BEFORE UPDATE ON public.domains FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5211 (class 2620 OID 16607)
-- Name: projects update_projects_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5215 (class 2620 OID 16874)
-- Name: runs update_runs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_runs_updated_at BEFORE UPDATE ON public.runs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5216 (class 2620 OID 16875)
-- Name: stages update_stages_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_stages_updated_at BEFORE UPDATE ON public.stages FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5209 (class 2620 OID 16545)
-- Name: users update_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5213 (class 2620 OID 16651)
-- Name: zoho_projects_mapping update_zoho_projects_mapping_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_zoho_projects_mapping_updated_at BEFORE UPDATE ON public.zoho_projects_mapping FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5212 (class 2620 OID 16629)
-- Name: zoho_tokens update_zoho_tokens_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_zoho_tokens_updated_at BEFORE UPDATE ON public.zoho_tokens FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- TOC entry 5205 (class 2606 OID 17224)
-- Name: agent_activity_logs agent_activity_logs_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_activity_logs
    ADD CONSTRAINT agent_activity_logs_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- TOC entry 5206 (class 2606 OID 17219)
-- Name: agent_activity_logs agent_activity_logs_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_activity_logs
    ADD CONSTRAINT agent_activity_logs_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.agent_jobs(id) ON DELETE CASCADE;


--
-- TOC entry 5199 (class 2606 OID 17183)
-- Name: agent_command_history agent_command_history_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_command_history
    ADD CONSTRAINT agent_command_history_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agents(id) ON DELETE SET NULL;


--
-- TOC entry 5200 (class 2606 OID 17178)
-- Name: agent_command_history agent_command_history_executed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_command_history
    ADD CONSTRAINT agent_command_history_executed_by_fkey FOREIGN KEY (executed_by) REFERENCES public.users(id);


--
-- TOC entry 5201 (class 2606 OID 17168)
-- Name: agent_command_history agent_command_history_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_command_history
    ADD CONSTRAINT agent_command_history_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.agent_jobs(id) ON DELETE SET NULL;


--
-- TOC entry 5202 (class 2606 OID 17173)
-- Name: agent_command_history agent_command_history_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_command_history
    ADD CONSTRAINT agent_command_history_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- TOC entry 5203 (class 2606 OID 17204)
-- Name: agent_file_operations agent_file_operations_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_file_operations
    ADD CONSTRAINT agent_file_operations_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agents(id) ON DELETE SET NULL;


--
-- TOC entry 5204 (class 2606 OID 17199)
-- Name: agent_file_operations agent_file_operations_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_file_operations
    ADD CONSTRAINT agent_file_operations_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.agent_jobs(id) ON DELETE CASCADE;


--
-- TOC entry 5196 (class 2606 OID 17148)
-- Name: agent_jobs agent_jobs_assigned_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_jobs
    ADD CONSTRAINT agent_jobs_assigned_agent_id_fkey FOREIGN KEY (assigned_agent_id) REFERENCES public.agents(id) ON DELETE SET NULL;


--
-- TOC entry 5197 (class 2606 OID 17153)
-- Name: agent_jobs agent_jobs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_jobs
    ADD CONSTRAINT agent_jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- TOC entry 5198 (class 2606 OID 17143)
-- Name: agent_jobs agent_jobs_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_jobs
    ADD CONSTRAINT agent_jobs_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- TOC entry 5195 (class 2606 OID 17125)
-- Name: agents agents_registered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_registered_by_fkey FOREIGN KEY (registered_by) REFERENCES public.users(id);


--
-- TOC entry 5178 (class 2606 OID 16847)
-- Name: ai_summaries ai_summaries_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_summaries
    ADD CONSTRAINT ai_summaries_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stages(id) ON DELETE CASCADE;


--
-- TOC entry 5169 (class 2606 OID 16702)
-- Name: blocks blocks_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- TOC entry 5186 (class 2606 OID 17011)
-- Name: c_report_data c_report_data_check_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.c_report_data
    ADD CONSTRAINT c_report_data_check_item_id_fkey FOREIGN KEY (check_item_id) REFERENCES public.check_items(id) ON DELETE CASCADE;


--
-- TOC entry 5187 (class 2606 OID 17016)
-- Name: c_report_data c_report_data_signoff_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.c_report_data
    ADD CONSTRAINT c_report_data_signoff_by_fkey FOREIGN KEY (signoff_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5188 (class 2606 OID 17043)
-- Name: check_item_approvals check_item_approvals_assigned_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_item_approvals
    ADD CONSTRAINT check_item_approvals_assigned_approver_id_fkey FOREIGN KEY (assigned_approver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5189 (class 2606 OID 17048)
-- Name: check_item_approvals check_item_approvals_assigned_by_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_item_approvals
    ADD CONSTRAINT check_item_approvals_assigned_by_lead_id_fkey FOREIGN KEY (assigned_by_lead_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5190 (class 2606 OID 17033)
-- Name: check_item_approvals check_item_approvals_check_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_item_approvals
    ADD CONSTRAINT check_item_approvals_check_item_id_fkey FOREIGN KEY (check_item_id) REFERENCES public.check_items(id) ON DELETE CASCADE;


--
-- TOC entry 5191 (class 2606 OID 17038)
-- Name: check_item_approvals check_item_approvals_default_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_item_approvals
    ADD CONSTRAINT check_item_approvals_default_approver_id_fkey FOREIGN KEY (default_approver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5185 (class 2606 OID 16994)
-- Name: check_items check_items_checklist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_items
    ADD CONSTRAINT check_items_checklist_id_fkey FOREIGN KEY (checklist_id) REFERENCES public.checklists(id) ON DELETE CASCADE;


--
-- TOC entry 5181 (class 2606 OID 16964)
-- Name: checklists checklists_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklists
    ADD CONSTRAINT checklists_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5182 (class 2606 OID 16959)
-- Name: checklists checklists_block_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklists
    ADD CONSTRAINT checklists_block_id_fkey FOREIGN KEY (block_id) REFERENCES public.blocks(id) ON DELETE CASCADE;


--
-- TOC entry 5183 (class 2606 OID 16974)
-- Name: checklists checklists_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklists
    ADD CONSTRAINT checklists_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5184 (class 2606 OID 16969)
-- Name: checklists checklists_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklists
    ADD CONSTRAINT checklists_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5158 (class 2606 OID 16520)
-- Name: chips chips_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chips
    ADD CONSTRAINT chips_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5159 (class 2606 OID 16525)
-- Name: chips chips_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chips
    ADD CONSTRAINT chips_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5160 (class 2606 OID 16480)
-- Name: designs designs_chip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designs
    ADD CONSTRAINT designs_chip_id_fkey FOREIGN KEY (chip_id) REFERENCES public.chips(id) ON DELETE CASCADE;


--
-- TOC entry 5161 (class 2606 OID 16530)
-- Name: designs designs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designs
    ADD CONSTRAINT designs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5162 (class 2606 OID 16535)
-- Name: designs designs_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.designs
    ADD CONSTRAINT designs_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5175 (class 2606 OID 16801)
-- Name: drv_violations drv_violations_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drv_violations
    ADD CONSTRAINT drv_violations_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stages(id) ON DELETE CASCADE;


--
-- TOC entry 5174 (class 2606 OID 16786)
-- Name: path_groups path_groups_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.path_groups
    ADD CONSTRAINT path_groups_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stages(id) ON DELETE CASCADE;


--
-- TOC entry 5177 (class 2606 OID 16831)
-- Name: physical_verification physical_verification_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.physical_verification
    ADD CONSTRAINT physical_verification_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stages(id) ON DELETE CASCADE;


--
-- TOC entry 5176 (class 2606 OID 16816)
-- Name: power_ir_em_checks power_ir_em_checks_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.power_ir_em_checks
    ADD CONSTRAINT power_ir_em_checks_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stages(id) ON DELETE CASCADE;


--
-- TOC entry 5165 (class 2606 OID 16601)
-- Name: project_domains project_domains_domain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_domains
    ADD CONSTRAINT project_domains_domain_id_fkey FOREIGN KEY (domain_id) REFERENCES public.domains(id) ON DELETE CASCADE;


--
-- TOC entry 5166 (class 2606 OID 16596)
-- Name: project_domains project_domains_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_domains
    ADD CONSTRAINT project_domains_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- TOC entry 5164 (class 2606 OID 16584)
-- Name: projects projects_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5192 (class 2606 OID 17107)
-- Name: qms_audit_log qms_audit_log_check_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qms_audit_log
    ADD CONSTRAINT qms_audit_log_check_item_id_fkey FOREIGN KEY (check_item_id) REFERENCES public.check_items(id) ON DELETE SET NULL;


--
-- TOC entry 5193 (class 2606 OID 17102)
-- Name: qms_audit_log qms_audit_log_checklist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qms_audit_log
    ADD CONSTRAINT qms_audit_log_checklist_id_fkey FOREIGN KEY (checklist_id) REFERENCES public.checklists(id) ON DELETE SET NULL;


--
-- TOC entry 5194 (class 2606 OID 17073)
-- Name: qms_audit_log qms_audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qms_audit_log
    ADD CONSTRAINT qms_audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- TOC entry 5170 (class 2606 OID 16720)
-- Name: runs runs_block_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runs
    ADD CONSTRAINT runs_block_id_fkey FOREIGN KEY (block_id) REFERENCES public.blocks(id) ON DELETE CASCADE;


--
-- TOC entry 5173 (class 2606 OID 16771)
-- Name: stage_constraint_metrics stage_constraint_metrics_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_constraint_metrics
    ADD CONSTRAINT stage_constraint_metrics_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stages(id) ON DELETE CASCADE;


--
-- TOC entry 5172 (class 2606 OID 16756)
-- Name: stage_timing_metrics stage_timing_metrics_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stage_timing_metrics
    ADD CONSTRAINT stage_timing_metrics_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES public.stages(id) ON DELETE CASCADE;


--
-- TOC entry 5171 (class 2606 OID 16741)
-- Name: stages stages_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stages
    ADD CONSTRAINT stages_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.runs(id) ON DELETE CASCADE;


--
-- TOC entry 5179 (class 2606 OID 16939)
-- Name: user_projects user_projects_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_projects
    ADD CONSTRAINT user_projects_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- TOC entry 5180 (class 2606 OID 16934)
-- Name: user_projects user_projects_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_projects
    ADD CONSTRAINT user_projects_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 5163 (class 2606 OID 16567)
-- Name: users users_domain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_domain_id_fkey FOREIGN KEY (domain_id) REFERENCES public.domains(id) ON DELETE SET NULL;


--
-- TOC entry 5168 (class 2606 OID 16644)
-- Name: zoho_projects_mapping zoho_projects_mapping_local_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_projects_mapping
    ADD CONSTRAINT zoho_projects_mapping_local_project_id_fkey FOREIGN KEY (local_project_id) REFERENCES public.projects(id) ON DELETE SET NULL;


--
-- TOC entry 5167 (class 2606 OID 16622)
-- Name: zoho_tokens zoho_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.zoho_tokens
    ADD CONSTRAINT zoho_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


-- Completed on 2026-01-20 20:34:45

--
-- PostgreSQL database dump complete
--

