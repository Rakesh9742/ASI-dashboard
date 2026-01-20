--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.4

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE user_role AS ENUM (
    'admin',
    'project_manager',
    'lead',
    'engineer',
    'customer'
);


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION update_updated_at_column() RETURNS trigger
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
-- Name: ai_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE ai_summaries (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    summary_text text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: ai_summaries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE ai_summaries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_summaries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE ai_summaries_id_seq OWNED BY ai_summaries.id;


--
-- Name: blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE blocks (
    id integer NOT NULL,
    project_id integer NOT NULL,
    block_name character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE blocks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE blocks_id_seq OWNED BY blocks.id;


--
-- Name: c_report_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE c_report_data (
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
-- Name: c_report_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE c_report_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: c_report_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE c_report_data_id_seq OWNED BY c_report_data.id;


--
-- Name: check_item_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE check_item_approvals (
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
-- Name: check_item_approvals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE check_item_approvals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: check_item_approvals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE check_item_approvals_id_seq OWNED BY check_item_approvals.id;


--
-- Name: check_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE check_items (
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
-- Name: check_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE check_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: check_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE check_items_id_seq OWNED BY check_items.id;


--
-- Name: checklists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE checklists (
    id integer NOT NULL,
    block_id integer NOT NULL,
    milestone_id integer,
    name character varying(255) NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying,
    approver_id integer,
    approver_role character varying(50),
    submitted_by integer,
    submitted_at timestamp without time zone,
    engineer_comments text,
    reviewer_comments text,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    metadata jsonb DEFAULT '{}'::jsonb
);


--
-- Name: checklists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE checklists_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: checklists_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE checklists_id_seq OWNED BY checklists.id;


--
-- Name: chips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE chips (
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
-- Name: chips_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE chips_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: chips_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE chips_id_seq OWNED BY chips.id;


--
-- Name: designs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE designs (
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
-- Name: designs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE designs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: designs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE designs_id_seq OWNED BY designs.id;


--
-- Name: domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE domains (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(50) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: domains_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE domains_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: domains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE domains_id_seq OWNED BY domains.id;


--
-- Name: drv_violations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE drv_violations (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    violation_type character varying(50) NOT NULL,
    wns character varying(50),
    tns character varying(50),
    nvp character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: drv_violations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE drv_violations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: drv_violations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE drv_violations_id_seq OWNED BY drv_violations.id;


--
-- Name: path_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE path_groups (
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
-- Name: path_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE path_groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: path_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE path_groups_id_seq OWNED BY path_groups.id;


--
-- Name: physical_verification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE physical_verification (
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
-- Name: physical_verification_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE physical_verification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: physical_verification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE physical_verification_id_seq OWNED BY physical_verification.id;


--
-- Name: power_ir_em_checks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE power_ir_em_checks (
    id integer NOT NULL,
    stage_id integer NOT NULL,
    ir_static character varying(50),
    ir_dynamic character varying(50),
    em_power character varying(50),
    em_signal character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: power_ir_em_checks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE power_ir_em_checks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: power_ir_em_checks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE power_ir_em_checks_id_seq OWNED BY power_ir_em_checks.id;


--
-- Name: project_domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE project_domains (
    project_id integer NOT NULL,
    domain_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE projects (
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
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE projects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE projects_id_seq OWNED BY projects.id;


--
-- Name: qms_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE qms_audit_log (
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
-- Name: qms_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE qms_audit_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: qms_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE qms_audit_log_id_seq OWNED BY qms_audit_log.id;


--
-- Name: runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE runs (
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
-- Name: runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE runs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE runs_id_seq OWNED BY runs.id;


--
-- Name: stage_constraint_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE stage_constraint_metrics (
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
-- Name: stage_constraint_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE stage_constraint_metrics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stage_constraint_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE stage_constraint_metrics_id_seq OWNED BY stage_constraint_metrics.id;


--
-- Name: stage_timing_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE stage_timing_metrics (
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
-- Name: stage_timing_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE stage_timing_metrics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stage_timing_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE stage_timing_metrics_id_seq OWNED BY stage_timing_metrics.id;


--
-- Name: stages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE stages (
    id integer NOT NULL,
    run_id integer NOT NULL,
    stage_name character varying(50) NOT NULL,
    "timestamp" timestamp without time zone,
    stage_directory text,
    run_status character varying(50),
    runtime character varying(20),
    memory_usage character varying(50),
    log_errors character varying(50) DEFAULT '0'::character varying,
    log_warnings character varying(50) DEFAULT '0'::character varying,
    log_critical character varying(50) DEFAULT '0'::character varying,
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
-- Name: stages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE stages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE stages_id_seq OWNED BY stages.id;


--
-- Name: user_projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE user_projects (
    user_id integer NOT NULL,
    project_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE users (
    id integer NOT NULL,
    username character varying(100) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    full_name character varying(255),
    role user_role DEFAULT 'engineer'::user_role NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_login timestamp without time zone,
    ipaddress character varying(255),
    port integer,
    ssh_user character varying(255),
    sshpassword_hash character varying(255),
    domain_id integer
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: zoho_projects_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE zoho_projects_mapping (
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
-- Name: zoho_projects_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE zoho_projects_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: zoho_projects_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE zoho_projects_mapping_id_seq OWNED BY zoho_projects_mapping.id;


--
-- Name: zoho_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE zoho_tokens (
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
-- Name: zoho_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE zoho_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: zoho_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE zoho_tokens_id_seq OWNED BY zoho_tokens.id;


--
-- Name: ai_summaries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY ai_summaries ALTER COLUMN id SET DEFAULT nextval('ai_summaries_id_seq'::regclass);


--
-- Name: blocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY blocks ALTER COLUMN id SET DEFAULT nextval('blocks_id_seq'::regclass);


--
-- Name: c_report_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY c_report_data ALTER COLUMN id SET DEFAULT nextval('c_report_data_id_seq'::regclass);


--
-- Name: check_item_approvals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_item_approvals ALTER COLUMN id SET DEFAULT nextval('check_item_approvals_id_seq'::regclass);


--
-- Name: check_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_items ALTER COLUMN id SET DEFAULT nextval('check_items_id_seq'::regclass);


--
-- Name: checklists id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY checklists ALTER COLUMN id SET DEFAULT nextval('checklists_id_seq'::regclass);


--
-- Name: chips id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY chips ALTER COLUMN id SET DEFAULT nextval('chips_id_seq'::regclass);


--
-- Name: designs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY designs ALTER COLUMN id SET DEFAULT nextval('designs_id_seq'::regclass);


--
-- Name: domains id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY domains ALTER COLUMN id SET DEFAULT nextval('domains_id_seq'::regclass);


--
-- Name: drv_violations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY drv_violations ALTER COLUMN id SET DEFAULT nextval('drv_violations_id_seq'::regclass);


--
-- Name: path_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY path_groups ALTER COLUMN id SET DEFAULT nextval('path_groups_id_seq'::regclass);


--
-- Name: physical_verification id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY physical_verification ALTER COLUMN id SET DEFAULT nextval('physical_verification_id_seq'::regclass);


--
-- Name: power_ir_em_checks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY power_ir_em_checks ALTER COLUMN id SET DEFAULT nextval('power_ir_em_checks_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY projects ALTER COLUMN id SET DEFAULT nextval('projects_id_seq'::regclass);


--
-- Name: qms_audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY qms_audit_log ALTER COLUMN id SET DEFAULT nextval('qms_audit_log_id_seq'::regclass);


--
-- Name: runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs ALTER COLUMN id SET DEFAULT nextval('runs_id_seq'::regclass);


--
-- Name: stage_constraint_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_constraint_metrics ALTER COLUMN id SET DEFAULT nextval('stage_constraint_metrics_id_seq'::regclass);


--
-- Name: stage_timing_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_timing_metrics ALTER COLUMN id SET DEFAULT nextval('stage_timing_metrics_id_seq'::regclass);


--
-- Name: stages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY stages ALTER COLUMN id SET DEFAULT nextval('stages_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: zoho_projects_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_projects_mapping ALTER COLUMN id SET DEFAULT nextval('zoho_projects_mapping_id_seq'::regclass);


--
-- Name: zoho_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_tokens ALTER COLUMN id SET DEFAULT nextval('zoho_tokens_id_seq'::regclass);


--
-- Name: ai_summaries ai_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ai_summaries
    ADD CONSTRAINT ai_summaries_pkey PRIMARY KEY (id);


--
-- Name: blocks blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY blocks
    ADD CONSTRAINT blocks_pkey PRIMARY KEY (id);


--
-- Name: blocks blocks_project_id_block_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY blocks
    ADD CONSTRAINT blocks_project_id_block_name_key UNIQUE (project_id, block_name);


--
-- Name: c_report_data c_report_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY c_report_data
    ADD CONSTRAINT c_report_data_pkey PRIMARY KEY (id);


--
-- Name: check_item_approvals check_item_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_item_approvals
    ADD CONSTRAINT check_item_approvals_pkey PRIMARY KEY (id);


--
-- Name: check_items check_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_items
    ADD CONSTRAINT check_items_pkey PRIMARY KEY (id);


--
-- Name: checklists checklists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY checklists
    ADD CONSTRAINT checklists_pkey PRIMARY KEY (id);


--
-- Name: chips chips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY chips
    ADD CONSTRAINT chips_pkey PRIMARY KEY (id);


--
-- Name: designs designs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY designs
    ADD CONSTRAINT designs_pkey PRIMARY KEY (id);


--
-- Name: domains domains_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY domains
    ADD CONSTRAINT domains_code_key UNIQUE (code);


--
-- Name: domains domains_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY domains
    ADD CONSTRAINT domains_name_key UNIQUE (name);


--
-- Name: domains domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY domains
    ADD CONSTRAINT domains_pkey PRIMARY KEY (id);


--
-- Name: drv_violations drv_violations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY drv_violations
    ADD CONSTRAINT drv_violations_pkey PRIMARY KEY (id);


--
-- Name: drv_violations drv_violations_stage_id_violation_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY drv_violations
    ADD CONSTRAINT drv_violations_stage_id_violation_type_key UNIQUE (stage_id, violation_type);


--
-- Name: path_groups path_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY path_groups
    ADD CONSTRAINT path_groups_pkey PRIMARY KEY (id);


--
-- Name: path_groups path_groups_stage_id_group_type_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY path_groups
    ADD CONSTRAINT path_groups_stage_id_group_type_group_name_key UNIQUE (stage_id, group_type, group_name);


--
-- Name: physical_verification physical_verification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY physical_verification
    ADD CONSTRAINT physical_verification_pkey PRIMARY KEY (id);


--
-- Name: physical_verification physical_verification_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY physical_verification
    ADD CONSTRAINT physical_verification_stage_id_key UNIQUE (stage_id);


--
-- Name: power_ir_em_checks power_ir_em_checks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY power_ir_em_checks
    ADD CONSTRAINT power_ir_em_checks_pkey PRIMARY KEY (id);


--
-- Name: power_ir_em_checks power_ir_em_checks_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY power_ir_em_checks
    ADD CONSTRAINT power_ir_em_checks_stage_id_key UNIQUE (stage_id);


--
-- Name: project_domains project_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_domains
    ADD CONSTRAINT project_domains_pkey PRIMARY KEY (project_id, domain_id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: qms_audit_log qms_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY qms_audit_log
    ADD CONSTRAINT qms_audit_log_pkey PRIMARY KEY (id);


--
-- Name: runs runs_block_id_experiment_rtl_tag_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs
    ADD CONSTRAINT runs_block_id_experiment_rtl_tag_key UNIQUE (block_id, experiment, rtl_tag);


--
-- Name: runs runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs
    ADD CONSTRAINT runs_pkey PRIMARY KEY (id);


--
-- Name: stage_constraint_metrics stage_constraint_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_constraint_metrics
    ADD CONSTRAINT stage_constraint_metrics_pkey PRIMARY KEY (id);


--
-- Name: stage_constraint_metrics stage_constraint_metrics_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_constraint_metrics
    ADD CONSTRAINT stage_constraint_metrics_stage_id_key UNIQUE (stage_id);


--
-- Name: stage_timing_metrics stage_timing_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_timing_metrics
    ADD CONSTRAINT stage_timing_metrics_pkey PRIMARY KEY (id);


--
-- Name: stage_timing_metrics stage_timing_metrics_stage_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_timing_metrics
    ADD CONSTRAINT stage_timing_metrics_stage_id_key UNIQUE (stage_id);


--
-- Name: stages stages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stages
    ADD CONSTRAINT stages_pkey PRIMARY KEY (id);


--
-- Name: stages stages_run_id_stage_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stages
    ADD CONSTRAINT stages_run_id_stage_name_key UNIQUE (run_id, stage_name);


--
-- Name: user_projects user_projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_projects
    ADD CONSTRAINT user_projects_pkey PRIMARY KEY (user_id, project_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: zoho_projects_mapping zoho_projects_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_projects_mapping
    ADD CONSTRAINT zoho_projects_mapping_pkey PRIMARY KEY (id);


--
-- Name: zoho_projects_mapping zoho_projects_mapping_zoho_project_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_projects_mapping
    ADD CONSTRAINT zoho_projects_mapping_zoho_project_id_key UNIQUE (zoho_project_id);


--
-- Name: zoho_tokens zoho_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_tokens
    ADD CONSTRAINT zoho_tokens_pkey PRIMARY KEY (id);


--
-- Name: zoho_tokens zoho_tokens_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_tokens
    ADD CONSTRAINT zoho_tokens_user_id_key UNIQUE (user_id);


--
-- Name: idx_ai_summaries_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_summaries_stage_id ON ai_summaries USING btree (stage_id);


--
-- Name: idx_blocks_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blocks_name ON blocks USING btree (block_name);


--
-- Name: idx_blocks_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blocks_project_id ON blocks USING btree (project_id);


--
-- Name: idx_blocks_project_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blocks_project_name ON blocks USING btree (project_id, block_name);


--
-- Name: idx_c_report_data_check_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_c_report_data_check_item_id ON c_report_data USING btree (check_item_id);


--
-- Name: idx_c_report_data_signoff_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_c_report_data_signoff_by ON c_report_data USING btree (signoff_by);


--
-- Name: idx_c_report_data_signoff_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_c_report_data_signoff_status ON c_report_data USING btree (signoff_status);


--
-- Name: idx_check_item_approvals_check_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_item_approvals_check_item_id ON check_item_approvals USING btree (check_item_id);


--
-- Name: idx_check_item_approvals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_item_approvals_status ON check_item_approvals USING btree (status);


--
-- Name: idx_check_items_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_category ON check_items USING btree (category);


--
-- Name: idx_check_items_checklist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_checklist_id ON check_items USING btree (checklist_id);


--
-- Name: idx_check_items_severity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_severity ON check_items USING btree (severity);


--
-- Name: idx_check_items_sub_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_sub_category ON check_items USING btree (sub_category);


--
-- Name: idx_check_items_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_check_items_version ON check_items USING btree (version);


--
-- Name: idx_checklists_approver_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_approver_id ON checklists USING btree (approver_id);


--
-- Name: idx_checklists_block_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_block_id ON checklists USING btree (block_id);


--
-- Name: idx_checklists_milestone_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_milestone_id ON checklists USING btree (milestone_id);


--
-- Name: idx_checklists_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_status ON checklists USING btree (status);


--
-- Name: idx_checklists_submitted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_submitted_at ON checklists USING btree (submitted_at);


--
-- Name: idx_checklists_submitted_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklists_submitted_by ON checklists USING btree (submitted_by);


--
-- Name: idx_chips_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chips_created_by ON chips USING btree (created_by);


--
-- Name: idx_chips_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chips_status ON chips USING btree (status);


--
-- Name: idx_chips_updated_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chips_updated_by ON chips USING btree (updated_by);


--
-- Name: idx_designs_chip_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_chip_id ON designs USING btree (chip_id);


--
-- Name: idx_designs_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_created_by ON designs USING btree (created_by);


--
-- Name: idx_designs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_status ON designs USING btree (status);


--
-- Name: idx_designs_updated_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_designs_updated_by ON designs USING btree (updated_by);


--
-- Name: idx_domains_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_domains_code ON domains USING btree (code);


--
-- Name: idx_domains_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_domains_is_active ON domains USING btree (is_active);


--
-- Name: idx_drv_violations_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drv_violations_stage_id ON drv_violations USING btree (stage_id);


--
-- Name: idx_drv_violations_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drv_violations_type ON drv_violations USING btree (violation_type);


--
-- Name: idx_path_groups_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_path_groups_name ON path_groups USING btree (group_name);


--
-- Name: idx_path_groups_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_path_groups_stage_id ON path_groups USING btree (stage_id);


--
-- Name: idx_path_groups_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_path_groups_type ON path_groups USING btree (group_type);


--
-- Name: idx_physical_verification_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_physical_verification_stage_id ON physical_verification USING btree (stage_id);


--
-- Name: idx_power_ir_em_checks_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_power_ir_em_checks_stage_id ON power_ir_em_checks USING btree (stage_id);


--
-- Name: idx_project_domains_domain_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_domains_domain_id ON project_domains USING btree (domain_id);


--
-- Name: idx_projects_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_projects_created_by ON projects USING btree (created_by);


--
-- Name: idx_qms_audit_log_check_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_check_item_id ON qms_audit_log USING btree (check_item_id);


--
-- Name: idx_qms_audit_log_checklist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_checklist_id ON qms_audit_log USING btree (checklist_id);


--
-- Name: idx_qms_audit_log_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_created_at ON qms_audit_log USING btree (created_at);


--
-- Name: idx_qms_audit_log_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qms_audit_log_user_id ON qms_audit_log USING btree (user_id);


--
-- Name: idx_runs_block_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_block_id ON runs USING btree (block_id);


--
-- Name: idx_runs_experiment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_experiment ON runs USING btree (experiment);


--
-- Name: idx_runs_rtl_tag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_rtl_tag ON runs USING btree (rtl_tag);


--
-- Name: idx_runs_user_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runs_user_name ON runs USING btree (user_name);


--
-- Name: idx_stage_constraint_metrics_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stage_constraint_metrics_stage_id ON stage_constraint_metrics USING btree (stage_id);


--
-- Name: idx_stage_timing_metrics_stage_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stage_timing_metrics_stage_id ON stage_timing_metrics USING btree (stage_id);


--
-- Name: idx_stages_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_name ON stages USING btree (stage_name);


--
-- Name: idx_stages_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_run_id ON stages USING btree (run_id);


--
-- Name: idx_stages_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_status ON stages USING btree (run_status);


--
-- Name: idx_stages_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stages_timestamp ON stages USING btree ("timestamp");


--
-- Name: idx_user_projects_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_projects_project_id ON user_projects USING btree (project_id);


--
-- Name: idx_user_projects_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_projects_user_id ON user_projects USING btree (user_id);


--
-- Name: idx_users_domain_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_domain_id ON users USING btree (domain_id);


--
-- Name: idx_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_email ON users USING btree (email);


--
-- Name: idx_users_ipaddress; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_ipaddress ON users USING btree (ipaddress) WHERE (ipaddress IS NOT NULL);


--
-- Name: idx_users_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_is_active ON users USING btree (is_active);


--
-- Name: idx_users_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_role ON users USING btree (role);


--
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_username ON users USING btree (username);


--
-- Name: idx_zoho_projects_mapping_local_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_projects_mapping_local_id ON zoho_projects_mapping USING btree (local_project_id);


--
-- Name: idx_zoho_projects_mapping_zoho_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_projects_mapping_zoho_id ON zoho_projects_mapping USING btree (zoho_project_id);


--
-- Name: idx_zoho_tokens_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_tokens_expires_at ON zoho_tokens USING btree (expires_at);


--
-- Name: idx_zoho_tokens_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_zoho_tokens_user_id ON zoho_tokens USING btree (user_id);


--
-- Name: ai_summaries update_ai_summaries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ai_summaries_updated_at BEFORE UPDATE ON ai_summaries FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: blocks update_blocks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_blocks_updated_at BEFORE UPDATE ON blocks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: c_report_data update_c_report_data_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_c_report_data_updated_at BEFORE UPDATE ON c_report_data FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: check_item_approvals update_check_item_approvals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_check_item_approvals_updated_at BEFORE UPDATE ON check_item_approvals FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: check_items update_check_items_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_check_items_updated_at BEFORE UPDATE ON check_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: checklists update_checklists_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_checklists_updated_at BEFORE UPDATE ON checklists FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: chips update_chips_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_chips_updated_at BEFORE UPDATE ON chips FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: designs update_designs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_designs_updated_at BEFORE UPDATE ON designs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: domains update_domains_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_domains_updated_at BEFORE UPDATE ON domains FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: projects update_projects_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: runs update_runs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_runs_updated_at BEFORE UPDATE ON runs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: stages update_stages_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_stages_updated_at BEFORE UPDATE ON stages FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: users update_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: zoho_projects_mapping update_zoho_projects_mapping_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_zoho_projects_mapping_updated_at BEFORE UPDATE ON zoho_projects_mapping FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: zoho_tokens update_zoho_tokens_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_zoho_tokens_updated_at BEFORE UPDATE ON zoho_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


--
-- Name: ai_summaries ai_summaries_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY ai_summaries
    ADD CONSTRAINT ai_summaries_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES stages(id) ON DELETE CASCADE;


--
-- Name: blocks blocks_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY blocks
    ADD CONSTRAINT blocks_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;


--
-- Name: c_report_data c_report_data_check_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY c_report_data
    ADD CONSTRAINT c_report_data_check_item_id_fkey FOREIGN KEY (check_item_id) REFERENCES check_items(id) ON DELETE CASCADE;


--
-- Name: c_report_data c_report_data_signoff_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY c_report_data
    ADD CONSTRAINT c_report_data_signoff_by_fkey FOREIGN KEY (signoff_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: check_item_approvals check_item_approvals_assigned_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_item_approvals
    ADD CONSTRAINT check_item_approvals_assigned_approver_id_fkey FOREIGN KEY (assigned_approver_id) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: check_item_approvals check_item_approvals_assigned_by_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_item_approvals
    ADD CONSTRAINT check_item_approvals_assigned_by_lead_id_fkey FOREIGN KEY (assigned_by_lead_id) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: check_item_approvals check_item_approvals_check_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_item_approvals
    ADD CONSTRAINT check_item_approvals_check_item_id_fkey FOREIGN KEY (check_item_id) REFERENCES check_items(id) ON DELETE CASCADE;


--
-- Name: check_item_approvals check_item_approvals_default_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_item_approvals
    ADD CONSTRAINT check_item_approvals_default_approver_id_fkey FOREIGN KEY (default_approver_id) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: check_items check_items_checklist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY check_items
    ADD CONSTRAINT check_items_checklist_id_fkey FOREIGN KEY (checklist_id) REFERENCES checklists(id) ON DELETE CASCADE;


--
-- Name: checklists checklists_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY checklists
    ADD CONSTRAINT checklists_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: checklists checklists_block_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY checklists
    ADD CONSTRAINT checklists_block_id_fkey FOREIGN KEY (block_id) REFERENCES blocks(id) ON DELETE CASCADE;


--
-- Name: checklists checklists_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY checklists
    ADD CONSTRAINT checklists_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: checklists checklists_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY checklists
    ADD CONSTRAINT checklists_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: chips chips_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY chips
    ADD CONSTRAINT chips_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: chips chips_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY chips
    ADD CONSTRAINT chips_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: designs designs_chip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY designs
    ADD CONSTRAINT designs_chip_id_fkey FOREIGN KEY (chip_id) REFERENCES chips(id) ON DELETE CASCADE;


--
-- Name: designs designs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY designs
    ADD CONSTRAINT designs_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: designs designs_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY designs
    ADD CONSTRAINT designs_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: drv_violations drv_violations_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY drv_violations
    ADD CONSTRAINT drv_violations_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES stages(id) ON DELETE CASCADE;


--
-- Name: path_groups path_groups_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY path_groups
    ADD CONSTRAINT path_groups_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES stages(id) ON DELETE CASCADE;


--
-- Name: physical_verification physical_verification_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY physical_verification
    ADD CONSTRAINT physical_verification_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES stages(id) ON DELETE CASCADE;


--
-- Name: power_ir_em_checks power_ir_em_checks_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY power_ir_em_checks
    ADD CONSTRAINT power_ir_em_checks_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES stages(id) ON DELETE CASCADE;


--
-- Name: project_domains project_domains_domain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_domains
    ADD CONSTRAINT project_domains_domain_id_fkey FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE;


--
-- Name: project_domains project_domains_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY project_domains
    ADD CONSTRAINT project_domains_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;


--
-- Name: projects projects_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY projects
    ADD CONSTRAINT projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: qms_audit_log qms_audit_log_check_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY qms_audit_log
    ADD CONSTRAINT qms_audit_log_check_item_id_fkey FOREIGN KEY (check_item_id) REFERENCES check_items(id) ON DELETE SET NULL;


--
-- Name: qms_audit_log qms_audit_log_checklist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY qms_audit_log
    ADD CONSTRAINT qms_audit_log_checklist_id_fkey FOREIGN KEY (checklist_id) REFERENCES checklists(id) ON DELETE SET NULL;


--
-- Name: qms_audit_log qms_audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY qms_audit_log
    ADD CONSTRAINT qms_audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: runs runs_block_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY runs
    ADD CONSTRAINT runs_block_id_fkey FOREIGN KEY (block_id) REFERENCES blocks(id) ON DELETE CASCADE;


--
-- Name: stage_constraint_metrics stage_constraint_metrics_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_constraint_metrics
    ADD CONSTRAINT stage_constraint_metrics_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES stages(id) ON DELETE CASCADE;


--
-- Name: stage_timing_metrics stage_timing_metrics_stage_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stage_timing_metrics
    ADD CONSTRAINT stage_timing_metrics_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES stages(id) ON DELETE CASCADE;


--
-- Name: stages stages_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY stages
    ADD CONSTRAINT stages_run_id_fkey FOREIGN KEY (run_id) REFERENCES runs(id) ON DELETE CASCADE;


--
-- Name: user_projects user_projects_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_projects
    ADD CONSTRAINT user_projects_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE;


--
-- Name: user_projects user_projects_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_projects
    ADD CONSTRAINT user_projects_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: users users_domain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_domain_id_fkey FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE SET NULL;


--
-- Name: zoho_projects_mapping zoho_projects_mapping_local_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_projects_mapping
    ADD CONSTRAINT zoho_projects_mapping_local_project_id_fkey FOREIGN KEY (local_project_id) REFERENCES projects(id) ON DELETE SET NULL;


--
-- Name: zoho_tokens zoho_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY zoho_tokens
    ADD CONSTRAINT zoho_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

