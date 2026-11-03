--
-- PostgreSQL database dump
--

\restrict zejQbaZa13euiTWWOGyD7sKNW3gqB65n8U3ltEeSNvnQCjL9JKdGmQcchjEJGJ7

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg13+2)
-- Dumped by pg_dump version 18.3 (Homebrew)

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
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: fn_sync_account_password_to_user(); Type: FUNCTION; Schema: public; Owner: stories
--

CREATE FUNCTION public.fn_sync_account_password_to_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.provider_id = 'credential' AND NEW.password IS NOT NULL THEN
        UPDATE ta_user SET password = NEW.password
        WHERE pk_user = NEW.fk_user AND password IS DISTINCT FROM NEW.password;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_sync_account_password_to_user() OWNER TO stories;

--
-- Name: fn_sync_user_password_to_account(); Type: FUNCTION; Schema: public; Owner: stories
--

CREATE FUNCTION public.fn_sync_user_password_to_account() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.password IS NULL OR NEW.password = '' THEN
        RETURN NEW;
    END IF;
    INSERT INTO ta_account (fk_user, account_id, provider_id, password)
    VALUES (NEW.pk_user, NEW.pk_user::text, 'credential', NEW.password)
    ON CONFLICT (fk_user, provider_id) DO UPDATE
        SET password = EXCLUDED.password, updated_at = CURRENT_TIMESTAMP
        WHERE ta_account.password IS DISTINCT FROM EXCLUDED.password;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_sync_user_password_to_account() OWNER TO stories;

--
-- Name: lower_text_array(text[]); Type: FUNCTION; Schema: public; Owner: stories
--

CREATE FUNCTION public.lower_text_array(input text[]) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT ARRAY(
    SELECT LOWER(x)
    FROM unnest(input) AS x
  );
$$;


ALTER FUNCTION public.lower_text_array(input text[]) OWNER TO stories;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: analysis_jobs; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.analysis_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    id_file text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    progress_percent integer DEFAULT 0 NOT NULL,
    result_json jsonb,
    error text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    CONSTRAINT analysis_jobs_progress_percent_check CHECK (((progress_percent >= 0) AND (progress_percent <= 100))),
    CONSTRAINT analysis_jobs_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'RUNNING'::text, 'COMPLETED'::text, 'FAILED'::text])))
);


ALTER TABLE public.analysis_jobs OWNER TO stories;

--
-- Name: ta_account; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_account (
    pk_account integer NOT NULL,
    id integer GENERATED ALWAYS AS (pk_account) STORED,
    fk_user integer NOT NULL,
    account_id character varying NOT NULL,
    provider_id character varying NOT NULL,
    access_token text,
    refresh_token text,
    id_token text,
    access_token_expires_at timestamp with time zone,
    refresh_token_expires_at timestamp with time zone,
    scope text,
    password text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.ta_account OWNER TO stories;

--
-- Name: ta_account_pk_account_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_account_pk_account_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_account_pk_account_seq OWNER TO stories;

--
-- Name: ta_account_pk_account_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_account_pk_account_seq OWNED BY public.ta_account.pk_account;


--
-- Name: ta_category; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_category (
    pk_category integer NOT NULL,
    name character varying NOT NULL,
    user_id integer,
    fk_main_category integer
);


ALTER TABLE public.ta_category OWNER TO stories;

--
-- Name: ta_category_pk_category_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_category_pk_category_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_category_pk_category_seq OWNER TO stories;

--
-- Name: ta_category_pk_category_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_category_pk_category_seq OWNED BY public.ta_category.pk_category;


--
-- Name: ta_flow_pk_flow_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_flow_pk_flow_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.ta_flow_pk_flow_seq OWNER TO stories;

--
-- Name: ta_flow; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_flow (
    pk_flow integer DEFAULT nextval('public.ta_flow_pk_flow_seq'::regclass) NOT NULL,
    name character varying NOT NULL,
    flow jsonb DEFAULT '{}'::jsonb,
    fk_user integer
);


ALTER TABLE public.ta_flow OWNER TO stories;

--
-- Name: ta_folder; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_folder (
    pk_folder integer NOT NULL,
    name character varying NOT NULL,
    user_id integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.ta_folder OWNER TO stories;

--
-- Name: ta_folder_pk_folder_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_folder_pk_folder_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_folder_pk_folder_seq OWNER TO stories;

--
-- Name: ta_folder_pk_folder_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_folder_pk_folder_seq OWNED BY public.ta_folder.pk_folder;


--
-- Name: ta_permission; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_permission (
    pk_permission integer NOT NULL,
    fk_from_user integer,
    category character varying NOT NULL,
    permission jsonb DEFAULT '{}'::jsonb,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.ta_permission OWNER TO stories;

--
-- Name: ta_permission_pk_permission_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_permission_pk_permission_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_permission_pk_permission_seq OWNER TO stories;

--
-- Name: ta_permission_pk_permission_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_permission_pk_permission_seq OWNED BY public.ta_permission.pk_permission;


--
-- Name: ta_policy; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_policy (
    pk_policy integer NOT NULL,
    resource text NOT NULL,
    name text NOT NULL,
    condition jsonb NOT NULL
);


ALTER TABLE public.ta_policy OWNER TO stories;

--
-- Name: ta_policy_pk_policy_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_policy_pk_policy_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_policy_pk_policy_seq OWNER TO stories;

--
-- Name: ta_policy_pk_policy_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_policy_pk_policy_seq OWNED BY public.ta_policy.pk_policy;


--
-- Name: ta_role; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_role (
    pk_role integer NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.ta_role OWNER TO stories;

--
-- Name: ta_role_pk_role_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_role_pk_role_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_role_pk_role_seq OWNER TO stories;

--
-- Name: ta_role_pk_role_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_role_pk_role_seq OWNED BY public.ta_role.pk_role;


--
-- Name: ta_role_policy; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_role_policy (
    fk_role integer NOT NULL,
    fk_policy integer NOT NULL
);


ALTER TABLE public.ta_role_policy OWNER TO stories;

--
-- Name: ta_session; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_session (
    token character varying(255),
    fk_user integer,
    started_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    invalid boolean DEFAULT false,
    pk_session integer NOT NULL,
    id integer GENERATED ALWAYS AS (pk_session) STORED,
    expires_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    ip_address character varying,
    user_agent character varying
);


ALTER TABLE public.ta_session OWNER TO stories;

--
-- Name: ta_session_pk_session_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_session_pk_session_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_session_pk_session_seq OWNER TO stories;

--
-- Name: ta_session_pk_session_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_session_pk_session_seq OWNED BY public.ta_session.pk_session;


--
-- Name: ta_signed_in; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_signed_in (
    token character(64) NOT NULL,
    started timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ended timestamp with time zone
);


ALTER TABLE public.ta_signed_in OWNER TO stories;

--
-- Name: ta_story_pk_story_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_story_pk_story_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.ta_story_pk_story_seq OWNER TO stories;

--
-- Name: ta_story; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_story (
    pk_story integer DEFAULT nextval('public.ta_story_pk_story_seq'::regclass) NOT NULL,
    name character varying NOT NULL,
    status character varying NOT NULL,
    summary character varying,
    user_id integer,
    fk_flow integer,
    story_type character varying DEFAULT 'story'::character varying,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    content_type character varying(10) DEFAULT 'Senda'::character varying NOT NULL,
    fk_folder integer
);


ALTER TABLE public.ta_story OWNER TO stories;

--
-- Name: ta_student; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_student (
    pk_student integer NOT NULL,
    firstname character varying NOT NULL,
    lastname character varying NOT NULL,
    email character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    password character varying NOT NULL,
    activated boolean DEFAULT false,
    student_type character varying NOT NULL,
    status character varying DEFAULT ''::character varying
);


ALTER TABLE public.ta_student OWNER TO stories;

--
-- Name: ta_student_pk_student_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_student_pk_student_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_student_pk_student_seq OWNER TO stories;

--
-- Name: ta_student_pk_student_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_student_pk_student_seq OWNED BY public.ta_student.pk_student;


--
-- Name: ta_tracking_pk_tracking_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_tracking_pk_tracking_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.ta_tracking_pk_tracking_seq OWNER TO stories;

--
-- Name: ta_tracking; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_tracking (
    pk_tracking integer DEFAULT nextval('public.ta_tracking_pk_tracking_seq'::regclass) NOT NULL,
    images character varying[],
    videos character varying[],
    roles character varying[],
    summary character varying,
    description character varying,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fk_status character varying,
    fk_story integer,
    float_value double precision DEFAULT '0'::double precision,
    amount_spent money DEFAULT '$0.00'::money,
    fk_story_tips integer,
    "position" public.geometry(Point,4326),
    label character varying(50),
    fk_story_sub integer,
    meta_order character varying,
    tags character varying[] DEFAULT '{}'::character varying[]
);


ALTER TABLE public.ta_tracking OWNER TO stories;

--
-- Name: ta_user_pk_user_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_user_pk_user_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 2147483647
    CACHE 1;


ALTER SEQUENCE public.ta_user_pk_user_seq OWNER TO stories;

--
-- Name: ta_user; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_user (
    pk_user integer DEFAULT nextval('public.ta_user_pk_user_seq'::regclass) NOT NULL,
    firstname character varying NOT NULL,
    lastname character varying NOT NULL,
    email character varying NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    account_type character varying NOT NULL,
    password character varying NOT NULL,
    activated boolean DEFAULT false,
    status character varying DEFAULT ''::character varying,
    name character varying,
    username character varying(255) DEFAULT ''::character varying NOT NULL,
    id integer GENERATED ALWAYS AS (pk_user) STORED,
    image character varying,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.ta_user OWNER TO stories;

--
-- Name: ta_user_policy; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_user_policy (
    pk_user_policy integer NOT NULL,
    fk_user integer,
    fk_policy integer
);


ALTER TABLE public.ta_user_policy OWNER TO stories;

--
-- Name: ta_user_policy_pk_user_policy_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_user_policy_pk_user_policy_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_user_policy_pk_user_policy_seq OWNER TO stories;

--
-- Name: ta_user_policy_pk_user_policy_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_user_policy_pk_user_policy_seq OWNED BY public.ta_user_policy.pk_user_policy;


--
-- Name: ta_user_relationship; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_user_relationship (
    pk_user_relationship integer NOT NULL,
    fk_follower_id integer NOT NULL,
    fk_followed_id integer NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(30) DEFAULT 'Requested'::character varying,
    CONSTRAINT no_self_follow CHECK ((fk_follower_id <> fk_followed_id))
);


ALTER TABLE public.ta_user_relationship OWNER TO stories;

--
-- Name: ta_user_relationships_pk_user_relationships_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_user_relationships_pk_user_relationships_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_user_relationships_pk_user_relationships_seq OWNER TO stories;

--
-- Name: ta_user_relationships_pk_user_relationships_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_user_relationships_pk_user_relationships_seq OWNED BY public.ta_user_relationship.pk_user_relationship;


--
-- Name: ta_user_role; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_user_role (
    fk_user integer NOT NULL,
    fk_role integer NOT NULL
);


ALTER TABLE public.ta_user_role OWNER TO stories;

--
-- Name: ta_verification; Type: TABLE; Schema: public; Owner: stories
--

CREATE TABLE public.ta_verification (
    pk_verification integer NOT NULL,
    id integer GENERATED ALWAYS AS (pk_verification) STORED,
    identifier character varying NOT NULL,
    value text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.ta_verification OWNER TO stories;

--
-- Name: ta_verification_pk_verification_seq; Type: SEQUENCE; Schema: public; Owner: stories
--

CREATE SEQUENCE public.ta_verification_pk_verification_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ta_verification_pk_verification_seq OWNER TO stories;

--
-- Name: ta_verification_pk_verification_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: stories
--

ALTER SEQUENCE public.ta_verification_pk_verification_seq OWNED BY public.ta_verification.pk_verification;


--
-- Name: ta_account pk_account; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_account ALTER COLUMN pk_account SET DEFAULT nextval('public.ta_account_pk_account_seq'::regclass);


--
-- Name: ta_category pk_category; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_category ALTER COLUMN pk_category SET DEFAULT nextval('public.ta_category_pk_category_seq'::regclass);


--
-- Name: ta_folder pk_folder; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_folder ALTER COLUMN pk_folder SET DEFAULT nextval('public.ta_folder_pk_folder_seq'::regclass);


--
-- Name: ta_permission pk_permission; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_permission ALTER COLUMN pk_permission SET DEFAULT nextval('public.ta_permission_pk_permission_seq'::regclass);


--
-- Name: ta_policy pk_policy; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_policy ALTER COLUMN pk_policy SET DEFAULT nextval('public.ta_policy_pk_policy_seq'::regclass);


--
-- Name: ta_role pk_role; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_role ALTER COLUMN pk_role SET DEFAULT nextval('public.ta_role_pk_role_seq'::regclass);


--
-- Name: ta_session pk_session; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_session ALTER COLUMN pk_session SET DEFAULT nextval('public.ta_session_pk_session_seq'::regclass);


--
-- Name: ta_student pk_student; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_student ALTER COLUMN pk_student SET DEFAULT nextval('public.ta_student_pk_student_seq'::regclass);


--
-- Name: ta_user_policy pk_user_policy; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_policy ALTER COLUMN pk_user_policy SET DEFAULT nextval('public.ta_user_policy_pk_user_policy_seq'::regclass);


--
-- Name: ta_user_relationship pk_user_relationship; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_relationship ALTER COLUMN pk_user_relationship SET DEFAULT nextval('public.ta_user_relationships_pk_user_relationships_seq'::regclass);


--
-- Name: ta_verification pk_verification; Type: DEFAULT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_verification ALTER COLUMN pk_verification SET DEFAULT nextval('public.ta_verification_pk_verification_seq'::regclass);


--
-- Data for Name: analysis_jobs; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.analysis_jobs (id, id_file, status, progress_percent, result_json, error, created_at, updated_at, started_at, finished_at) FROM stdin;
a58764f7-649e-4168-a8e9-66aafba6158e	file-1181902411016659	FAILED	0	\N	service restarted while job was running	2026-11-03 00:08:10.082077+00	2026-11-03 00:09:48.993462+00	2026-11-03 00:08:10.084726+00	2026-11-03 00:09:48.993462+00
c501fe44-6e20-4e25-acc9-f77d1251f637	file-27841547915521014	COMPLETED	100	{"status": "ok", "ticket": 257}		2026-11-01 22:42:07.030242+00	2026-11-01 22:46:41.954461+00	2026-11-01 22:42:07.046668+00	2026-11-01 22:46:41.954461+00
f9f917dc-b115-4224-b4c2-3ddc04bcddc4	file-1819840482454875	FAILED	80	\N	step 5 (storeplaces): adding tips: new_step_tips for "Paris": yaml: unmarshal errors:\n  line 3: cannot unmarshal !!str `Eiffel ...` into []string	2026-11-03 13:44:13.557479+00	2026-11-03 13:49:36.243617+00	2026-11-03 13:44:13.578148+00	2026-11-03 13:49:36.243617+00
b7458b4f-81ef-490c-8988-e334de4370a0	file-27841547915521014	FAILED	20	\N	service restarted while job was running	2026-11-01 23:06:49.148541+00	2026-11-01 23:27:06.316896+00	2026-11-01 23:06:49.164628+00	2026-11-01 23:27:06.316896+00
13f60416-f80d-42eb-834b-9ec38712777d	file-27841547915521014	FAILED	0	\N	step 1 (places): Muse API error (404 Not Found): {"error":{"code":"file_not_found","message":"No file found with id 'file-27841547915521014'.","param":null,"type":"invalid_request_error"}}	2026-11-01 23:27:23.469201+00	2026-11-01 23:27:24.527218+00	2026-11-01 23:27:23.478553+00	2026-11-01 23:27:24.527218+00
e27f69dd-86b6-4e5c-bfa6-51983e6c869d	file-1889548392401248	COMPLETED	100	{"status": "ok", "ticket": 261}		2026-11-03 00:15:46.0762+00	2026-11-03 00:20:11.82389+00	2026-11-03 00:15:46.085953+00	2026-11-03 00:20:11.82389+00
4b45104d-086f-442a-a949-0231956576ad	file-1127577896318162	COMPLETED	100	{"status": "ok", "ticket": 258}		2026-11-01 23:28:44.48991+00	2026-11-01 23:33:21.791821+00	2026-11-01 23:28:44.492125+00	2026-11-01 23:33:21.791821+00
912f0372-8840-4628-86ab-1fc93eef1b26	video-paris-001	COMPLETED	100	{"steps": [], "id_file": "video-paris-001", "summary": "analysis completed for video-paris-001", "created_by": "tratrack-analysis-service"}		2026-11-01 17:44:00.783327+00	2026-11-01 17:44:03.808963+00	2026-11-01 17:44:00.800635+00	2026-11-01 17:44:03.808963+00
6749e4a5-3e45-49ae-8a20-3f2769360dbd	file-2647527832338186	FAILED	0	\N	step 1 (places): Muse API error (404 Not Found): {"error":{"code":"file_not_found","message":"No file found with id 'file-2647527832338186'.","param":null,"type":"invalid_request_error"}}	2026-11-02 23:00:34.630862+00	2026-11-02 23:00:35.798986+00	2026-11-02 23:00:34.648559+00	2026-11-02 23:00:35.798986+00
884d9853-3451-405d-bdb0-3a02c28da14f	file-2647527832338186	COMPLETED	100	{"status": "ok", "ticket": 259}		2026-11-02 23:01:06.13926+00	2026-11-02 23:05:59.259876+00	2026-11-02 23:01:06.156006+00	2026-11-02 23:05:59.259876+00
79af5e4c-0f39-4d01-b909-d36f81866c2f	file-942778488703853	COMPLETED	100	{"status": "ok", "ticket": 266}		2026-11-03 22:36:46.348059+00	2026-11-03 22:41:16.038475+00	2026-11-03 22:36:46.364263+00	2026-11-03 22:41:16.038475+00
83a8f120-b7c3-49ff-bf2c-889c4c362b6e	file-1629621555574250	FAILED	20	\N	service restarted while job was running	2026-11-02 23:42:22.935305+00	2026-11-02 23:54:22.550935+00	2026-11-02 23:42:22.951606+00	2026-11-02 23:54:22.550935+00
aab7ad29-de9b-40ac-a750-3a5bd51f4eb6	file-1127844193440669	FAILED	80	\N	step 5 (storeplaces): creating story: cannot create duplicate objects	2026-11-03 01:47:21.063916+00	2026-11-03 01:51:31.131959+00	2026-11-03 01:47:21.083046+00	2026-11-03 01:51:31.131959+00
7dff536d-cf94-4ef0-b495-66b5fcba42d1	file-1675257200692905	FAILED	80	\N	step 5 (storeplaces): creating story: cannot create duplicate objects	2026-11-02 23:54:47.351325+00	2026-11-03 00:00:36.791863+00	2026-11-02 23:54:47.361136+00	2026-11-03 00:00:36.791863+00
22951563-2780-48ff-aaf3-b8d9988b5ffa	120344	COMPLETED	100	{"steps": [], "id_file": "120344", "summary": "analysis completed for 120344", "created_by": "tratrack-analysis-service"}		2026-11-01 19:35:12.873764+00	2026-11-01 19:40:12.93524+00	2026-11-01 19:35:12.889381+00	2026-11-01 19:40:12.93524+00
5b9f1e18-4780-47ae-b2c8-ab1d7f14a047	file-1127092339789260	COMPLETED	100	{"status": "ok", "ticket": 262}		2026-11-03 01:54:31.221154+00	2026-11-03 01:59:57.529397+00	2026-11-03 01:54:31.236498+00	2026-11-03 01:59:57.529397+00
bbaad791-f18e-4398-b64b-e6cdf5e3d585	file-1181902411016659	COMPLETED	100	{"status": "ok", "ticket": 260}		2026-11-03 00:02:22.402711+00	2026-11-03 00:07:31.752758+00	2026-11-03 00:02:22.417345+00	2026-11-03 00:07:31.752758+00
530a1120-d081-4339-a62f-22e5193a51af	file-27841547915521014	COMPLETED	100	{"name": "Best Things To Do In Paris", "places": [{"id": 1, "name": "Eiffel Tower", "tags": ["landmark", "iconic", "historic", "architecture", "views", "panoramic", "photography"], "tips": ["An iconic symbol of Parisian elegance", "Admire the iron lattice structure from below", "Ride the elevator up the tower legs", "Visit the crowded observation deck for panoramic city views", "See the tower from the Seine River with tour boats"], "spent": 180, "location": "(48.8584,2.2945)", "end_seconds": 67, "start_seconds": 0}, {"id": 2, "name": "Arc de Triomphe", "spent": 60, "location": "(48.8738,2.2950)", "end_seconds": 22, "start_seconds": 18}, {"id": 3, "name": "Notre Dame", "tags": ["cathedral", "gothic", "historic", "landmark", "architecture", "religious", "iconic"], "tips": ["Admire the twin towers and large rose window from below", "Stunning Gothic architecture", "Popular square in front filled with tourists", "Three grand carved entrance portals with detailed statues", "Photo spot with pink roses framing the cathedral", "Interior with high vaulted nave, pews and stained-glass windows"], "spent": 60, "location": "(48.8530,2.3499)", "end_seconds": 116, "start_seconds": 28}, {"id": 4, "name": "The Louvre Museum", "tags": ["museum", "art", "historic", "landmark", "iconic", "crowded", "cultural"], "tips": ["Described as a treasure trove of artistic masterpieces", "Iconic glass pyramid entrance in front of historic palace buildings", "Explore long galleries lined with large paintings", "Walk through halls with sculptures and statues", "See the famous Mona Lisa painting", "Expect large crowds inside, especially around popular artworks", "Check links in the description below for more information"], "spent": 180, "location": "(48.8606,2.3376)", "end_seconds": 95, "start_seconds": 68}, {"id": 5, "name": "The Seine River", "tags": ["river", "cruise", "boat", "scenic", "views", "relaxing", "landmark"], "tips": ["The Seine River winds gracefully through Paris", "Take an open-deck sightseeing boat tour on the river", "See large river cruise ships moored along the banks", "View the Eiffel Tower from the water with boats passing", "See Notre Dame from the river"], "spent": 60, "location": "(48.8566,2.3522)", "end_seconds": 141, "start_seconds": 117}, {"id": 6, "name": "Sacre Coeur", "tags": ["basilica", "landmark", "historic", "religious", "architecture", "views", "montmartre"], "tips": ["Perched atop Montmartre", "White-domed basilica with distinctive domes and stone facade", "Offers panoramic views over Paris from its hilltop position", "Popular spot to gather on the steps, terrace and lawns below"], "spent": 90, "location": "(48.8867,2.3431)", "end_seconds": 169, "start_seconds": 141}, {"id": 7, "name": "Montmartre", "tags": ["basilica", "landmark", "architecture", "views", "panoramic", "mosaics", "statues"], "tips": ["Perched atop Montmartre", "Climb the steps of this basilica for panoramic views of Paris", "Features gleaming white domes and striking design", "Head up here to really appreciate the architecture", "Offers breathtaking panoramic views of the city", "You can head inside the basilica itself to see the intricate mosaics and majestic statues"], "spent": 120, "location": "(48.8869,2.3417)", "end_seconds": 160, "start_seconds": 143}, {"id": 8, "name": "Musee d'Orsay", "tags": ["museum", "art", "historic", "architecture", "culture", "landmark", "clock"], "tips": ["A collection of 19th and early 20th-century art"], "spent": 120, "location": "(48.8600,2.3266)", "end_seconds": 176, "start_seconds": 170}], "summary": "A Creative Travel Guide to the best things to do in Paris for the Paris 2024 Olympics, featuring the Eiffel Tower, Louvre Museum, Notre Dame, Seine River cruise, Sacre Coeur in Montmartre and Musee d'Orsay."}		2026-11-01 22:24:53.194966+00	2026-11-01 22:30:01.624881+00	2026-11-01 22:24:53.21043+00	2026-11-01 22:30:01.624881+00
f0080c8a-2441-42a9-9d16-498051ed40b7	file-1129577826659819	FAILED	80	\N	step 5 (storeplaces): adding tips: new_step_tips for "Eiffel Tower": yaml: unmarshal errors:\n  line 3: cannot unmarshal !!str `An icon...` into []string	2026-11-03 13:35:27.392436+00	2026-11-03 13:39:48.504988+00	2026-11-03 13:35:27.408788+00	2026-11-03 13:39:48.504988+00
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: ta_account; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_account (pk_account, fk_user, account_id, provider_id, access_token, refresh_token, id_token, access_token_expires_at, refresh_token_expires_at, scope, password, created_at, updated_at) FROM stdin;
4	2	2	credential	\N	\N	\N	\N	\N	\N	$2a$10$4D6iCZU7.tzo96rC362OCuPaXvt703nMl5TGMzTqEr5NTkJTLbhti	2026-10-18 20:33:45.638525+00	2026-10-18 20:33:45.638525+00
\.


--
-- Data for Name: ta_category; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_category (pk_category, name, user_id, fk_main_category) FROM stdin;
2	Bills	2	1
3	Restaurant	2	1
4	Cafe	2	1
5	Entertaiment	2	1
6	Family	2	1
7	Education	2	1
8	Home	2	1
9	Health	2	1
10	Books	2	1
11	Market	2	1
\.


--
-- Data for Name: ta_flow; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_flow (pk_flow, name, flow, fk_user) FROM stdin;
\.


--
-- Data for Name: ta_folder; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_folder (pk_folder, name, user_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: ta_permission; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_permission (pk_permission, fk_from_user, category, permission, updated_at) FROM stdin;
1	2	admin	{"can_edit": true, "can_delete": false}	2025-06-06 02:30:38.1065+00
\.


--
-- Data for Name: ta_policy; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_policy (pk_policy, resource, name, condition) FROM stdin;
5	flows	basic	{"action": "add_flow_step", "permises": {"execute": "is _owner"}}
12	flow	add_flow_step	[{"ticket": 215}, {"ticket": 210}, {"ticket": 205}, {"ticket": 193}, {"ticket": 198}, {"ticket": 201}, {"ticket": 222}, {"ticket": 223}, {"ticket": 227}, {"ticket": 228}, {"ticket": 233}, {"ticket": 234}, {"ticket": 235}, {"ticket": 236}, {"ticket": 237}, {"ticket": 238}, {"ticket": 239}, {"ticket": 240}, {"ticket": 241}, {"ticket": 242}, {"ticket": 243}, {"ticket": 244}, {"ticket": 245}, {"ticket": 246}, {"ticket": 247}, {"ticket": 248}, {"ticket": 249}, {"ticket": 250}, {"ticket": 251}, {"ticket": 252}, {"ticket": 253}, {"ticket": 254}, {"ticket": 255}, {"ticket": 256}, {"ticket": 257}, {"ticket": 258}, {"ticket": 259}, {"ticket": 260}, {"ticket": 261}, {"ticket": 262}, {"ticket": 263}, {"ticket": 264}, {"ticket": 266}]
\.


--
-- Data for Name: ta_role; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_role (pk_role, name) FROM stdin;
1	admin
2	user
\.


--
-- Data for Name: ta_role_policy; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_role_policy (fk_role, fk_policy) FROM stdin;
\.


--
-- Data for Name: ta_session; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_session (token, fk_user, started_at, invalid, pk_session, expires_at, updated_at, ip_address, user_agent) FROM stdin;
\.


--
-- Data for Name: ta_signed_in; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_signed_in (token, started, ended) FROM stdin;
\.


--
-- Data for Name: ta_story; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_story (pk_story, name, status, summary, user_id, fk_flow, story_type, updated_at, content_type, fk_folder) FROM stdin;
\.


--
-- Data for Name: ta_student; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_student (pk_student, firstname, lastname, email, created_at, password, activated, student_type, status) FROM stdin;
4	Victor	Bravo	victor@doitall.work	2025-06-26 01:00:15.815226	mipass	\N	Admin	
2	Marcelo Rafael	Bravo	marcelo@doitall.work	2025-06-26 00:59:49.135684	mipass	\N	Admin	
\.


--
-- Data for Name: ta_tracking; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_tracking (pk_tracking, images, videos, roles, summary, description, updated_at, fk_status, fk_story, float_value, amount_spent, fk_story_tips, "position", label, fk_story_sub, meta_order, tags) FROM stdin;
\.


--
-- Data for Name: ta_user; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_user (pk_user, firstname, lastname, email, created_at, account_type, password, activated, status, name, username, image, updated_at) FROM stdin;
2	vbravo	vbravo	victorrbravo@gmail.com	2023-12-15 16:04:54.320521	admin	$2a$10$4D6iCZU7.tzo96rC362OCuPaXvt703nMl5TGMzTqEr5NTkJTLbhti	t		\N	v2	\N	2026-10-18 20:33:45.638525
\.


--
-- Data for Name: ta_user_policy; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_user_policy (pk_user_policy, fk_user, fk_policy) FROM stdin;
5	2	5
\.


--
-- Data for Name: ta_user_relationship; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_user_relationship (pk_user_relationship, fk_follower_id, fk_followed_id, updated_at, status) FROM stdin;
\.


--
-- Data for Name: ta_user_role; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_user_role (fk_user, fk_role) FROM stdin;
\.


--
-- Data for Name: ta_verification; Type: TABLE DATA; Schema: public; Owner: stories
--

COPY public.ta_verification (pk_verification, identifier, value, expires_at, created_at, updated_at) FROM stdin;
\.


--
-- Name: ta_account_pk_account_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_account_pk_account_seq', 11, true);


--
-- Name: ta_category_pk_category_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_category_pk_category_seq', 11, true);


--
-- Name: ta_flow_pk_flow_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_flow_pk_flow_seq', 282, true);


--
-- Name: ta_folder_pk_folder_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_folder_pk_folder_seq', 1, false);


--
-- Name: ta_permission_pk_permission_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_permission_pk_permission_seq', 1, true);


--
-- Name: ta_policy_pk_policy_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_policy_pk_policy_seq', 12, true);


--
-- Name: ta_role_pk_role_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_role_pk_role_seq', 2, true);


--
-- Name: ta_session_pk_session_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_session_pk_session_seq', 44, true);


--
-- Name: ta_story_pk_story_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_story_pk_story_seq', 272, true);


--
-- Name: ta_student_pk_student_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_student_pk_student_seq', 4, true);


--
-- Name: ta_tracking_pk_tracking_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_tracking_pk_tracking_seq', 4472, true);


--
-- Name: ta_user_pk_user_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_user_pk_user_seq', 50, true);


--
-- Name: ta_user_policy_pk_user_policy_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_user_policy_pk_user_policy_seq', 6, true);


--
-- Name: ta_user_relationships_pk_user_relationships_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_user_relationships_pk_user_relationships_seq', 11, true);


--
-- Name: ta_verification_pk_verification_seq; Type: SEQUENCE SET; Schema: public; Owner: stories
--

SELECT pg_catalog.setval('public.ta_verification_pk_verification_seq', 1, false);


--
-- Name: analysis_jobs analysis_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.analysis_jobs
    ADD CONSTRAINT analysis_jobs_pkey PRIMARY KEY (id);


--
-- Name: ta_story story_status_unique; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_story
    ADD CONSTRAINT story_status_unique UNIQUE (pk_story, status);


--
-- Name: ta_account ta_account_id_key; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_account
    ADD CONSTRAINT ta_account_id_key UNIQUE (id);


--
-- Name: ta_account ta_account_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_account
    ADD CONSTRAINT ta_account_pkey PRIMARY KEY (pk_account);


--
-- Name: ta_account ta_account_user_provider_key; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_account
    ADD CONSTRAINT ta_account_user_provider_key UNIQUE (fk_user, provider_id);


--
-- Name: ta_category ta_category_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_category
    ADD CONSTRAINT ta_category_pkey PRIMARY KEY (pk_category);


--
-- Name: ta_flow ta_flow_name_key; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_flow
    ADD CONSTRAINT ta_flow_name_key UNIQUE (name);


--
-- Name: ta_flow ta_flow_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_flow
    ADD CONSTRAINT ta_flow_pkey PRIMARY KEY (pk_flow);


--
-- Name: ta_folder ta_folder_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_folder
    ADD CONSTRAINT ta_folder_pkey PRIMARY KEY (pk_folder);


--
-- Name: ta_permission ta_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_permission
    ADD CONSTRAINT ta_permission_pkey PRIMARY KEY (pk_permission);


--
-- Name: ta_policy ta_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_policy
    ADD CONSTRAINT ta_policy_pkey PRIMARY KEY (pk_policy);


--
-- Name: ta_role ta_role_name_key; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_role
    ADD CONSTRAINT ta_role_name_key UNIQUE (name);


--
-- Name: ta_role ta_role_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_role
    ADD CONSTRAINT ta_role_pkey PRIMARY KEY (pk_role);


--
-- Name: ta_role_policy ta_role_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_role_policy
    ADD CONSTRAINT ta_role_policy_pkey PRIMARY KEY (fk_role, fk_policy);


--
-- Name: ta_session ta_session_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_session
    ADD CONSTRAINT ta_session_pkey PRIMARY KEY (pk_session);


--
-- Name: ta_signed_in ta_signed_in_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_signed_in
    ADD CONSTRAINT ta_signed_in_pkey PRIMARY KEY (token);


--
-- Name: ta_story ta_story_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_story
    ADD CONSTRAINT ta_story_pkey PRIMARY KEY (pk_story);


--
-- Name: ta_student ta_student_email_key; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_student
    ADD CONSTRAINT ta_student_email_key UNIQUE (email);


--
-- Name: ta_student ta_student_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_student
    ADD CONSTRAINT ta_student_pkey PRIMARY KEY (pk_student);


--
-- Name: ta_tracking ta_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_tracking
    ADD CONSTRAINT ta_tracking_pkey PRIMARY KEY (pk_tracking);


--
-- Name: ta_user ta_user_email_key; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user
    ADD CONSTRAINT ta_user_email_key UNIQUE (email);


--
-- Name: ta_user ta_user_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user
    ADD CONSTRAINT ta_user_pkey PRIMARY KEY (pk_user);


--
-- Name: ta_user_policy ta_user_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_policy
    ADD CONSTRAINT ta_user_policy_pkey PRIMARY KEY (pk_user_policy);


--
-- Name: ta_user_relationship ta_user_relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_relationship
    ADD CONSTRAINT ta_user_relationships_pkey PRIMARY KEY (pk_user_relationship);


--
-- Name: ta_user_role ta_user_role_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_role
    ADD CONSTRAINT ta_user_role_pkey PRIMARY KEY (fk_user, fk_role);


--
-- Name: ta_verification ta_verification_id_key; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_verification
    ADD CONSTRAINT ta_verification_id_key UNIQUE (id);


--
-- Name: ta_verification ta_verification_pkey; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_verification
    ADD CONSTRAINT ta_verification_pkey PRIMARY KEY (pk_verification);


--
-- Name: ta_tracking tracking_status_unique; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_tracking
    ADD CONSTRAINT tracking_status_unique UNIQUE (fk_story, fk_status);


--
-- Name: ta_story unique_name; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_story
    ADD CONSTRAINT unique_name UNIQUE (user_id, name);


--
-- Name: ta_policy unique_name_condition; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_policy
    ADD CONSTRAINT unique_name_condition UNIQUE (name, condition);


--
-- Name: ta_user_relationship unique_relationship; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_relationship
    ADD CONSTRAINT unique_relationship UNIQUE (fk_follower_id, fk_followed_id);


--
-- Name: ta_user unique_username; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user
    ADD CONSTRAINT unique_username UNIQUE (username);


--
-- Name: ta_user_policy uq_user_policy; Type: CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_policy
    ADD CONSTRAINT uq_user_policy UNIQUE (fk_user, fk_policy);


--
-- Name: idx_analysis_jobs_last_result; Type: INDEX; Schema: public; Owner: stories
--

CREATE INDEX idx_analysis_jobs_last_result ON public.analysis_jobs USING btree (finished_at DESC) WHERE (status = 'COMPLETED'::text);


--
-- Name: idx_analysis_jobs_status; Type: INDEX; Schema: public; Owner: stories
--

CREATE INDEX idx_analysis_jobs_status ON public.analysis_jobs USING btree (status, created_at DESC);


--
-- Name: story_status; Type: INDEX; Schema: public; Owner: stories
--

CREATE INDEX story_status ON public.ta_tracking USING btree (fk_story, fk_status);


--
-- Name: ta_session_fk_user_idx; Type: INDEX; Schema: public; Owner: stories
--

CREATE INDEX ta_session_fk_user_idx ON public.ta_session USING btree (fk_user);


--
-- Name: ta_session_id_key; Type: INDEX; Schema: public; Owner: stories
--

CREATE UNIQUE INDEX ta_session_id_key ON public.ta_session USING btree (id);


--
-- Name: ta_session_token_idx; Type: INDEX; Schema: public; Owner: stories
--

CREATE INDEX ta_session_token_idx ON public.ta_session USING btree (token);


--
-- Name: ta_user_id_key; Type: INDEX; Schema: public; Owner: stories
--

CREATE UNIQUE INDEX ta_user_id_key ON public.ta_user USING btree (id);


--
-- Name: ta_verification_identifier_idx; Type: INDEX; Schema: public; Owner: stories
--

CREATE INDEX ta_verification_identifier_idx ON public.ta_verification USING btree (identifier);


--
-- Name: tracking_story; Type: INDEX; Schema: public; Owner: stories
--

CREATE INDEX tracking_story ON public.ta_tracking USING btree (fk_story);


--
-- Name: ta_account tg_ta_account_password_sync; Type: TRIGGER; Schema: public; Owner: stories
--

CREATE TRIGGER tg_ta_account_password_sync AFTER INSERT OR UPDATE OF password ON public.ta_account FOR EACH ROW EXECUTE FUNCTION public.fn_sync_account_password_to_user();


--
-- Name: ta_user tg_ta_user_password_sync; Type: TRIGGER; Schema: public; Owner: stories
--

CREATE TRIGGER tg_ta_user_password_sync AFTER INSERT OR UPDATE OF password ON public.ta_user FOR EACH ROW EXECUTE FUNCTION public.fn_sync_user_password_to_account();


--
-- Name: ta_flow fk_user; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_flow
    ADD CONSTRAINT fk_user FOREIGN KEY (fk_user) REFERENCES public.ta_user(pk_user);


--
-- Name: ta_account ta_account_fk_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_account
    ADD CONSTRAINT ta_account_fk_user_fkey FOREIGN KEY (fk_user) REFERENCES public.ta_user(pk_user) ON DELETE CASCADE;


--
-- Name: ta_category ta_category_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_category
    ADD CONSTRAINT ta_category_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.ta_user(pk_user);


--
-- Name: ta_folder ta_folder_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_folder
    ADD CONSTRAINT ta_folder_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.ta_user(pk_user);


--
-- Name: ta_permission ta_permission_fk_from_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_permission
    ADD CONSTRAINT ta_permission_fk_from_user_fkey FOREIGN KEY (fk_from_user) REFERENCES public.ta_user(pk_user);


--
-- Name: ta_role_policy ta_role_policy_fk_policy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_role_policy
    ADD CONSTRAINT ta_role_policy_fk_policy_fkey FOREIGN KEY (fk_policy) REFERENCES public.ta_policy(pk_policy) ON DELETE CASCADE;


--
-- Name: ta_role_policy ta_role_policy_fk_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_role_policy
    ADD CONSTRAINT ta_role_policy_fk_role_fkey FOREIGN KEY (fk_role) REFERENCES public.ta_role(pk_role) ON DELETE CASCADE;


--
-- Name: ta_session ta_session_fk_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_session
    ADD CONSTRAINT ta_session_fk_user_fkey FOREIGN KEY (fk_user) REFERENCES public.ta_user(pk_user);


--
-- Name: ta_story ta_story_fk_folder_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_story
    ADD CONSTRAINT ta_story_fk_folder_fkey FOREIGN KEY (fk_folder) REFERENCES public.ta_folder(pk_folder);


--
-- Name: ta_story ta_story_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_story
    ADD CONSTRAINT ta_story_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.ta_user(pk_user);


--
-- Name: ta_tracking ta_tracking_fk_story_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_tracking
    ADD CONSTRAINT ta_tracking_fk_story_fkey FOREIGN KEY (fk_story) REFERENCES public.ta_story(pk_story);


--
-- Name: ta_tracking ta_tracking_fk_story_sub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_tracking
    ADD CONSTRAINT ta_tracking_fk_story_sub_fkey FOREIGN KEY (fk_story_sub) REFERENCES public.ta_story(pk_story);


--
-- Name: ta_tracking ta_tracking_fk_story_tips_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_tracking
    ADD CONSTRAINT ta_tracking_fk_story_tips_fkey FOREIGN KEY (fk_story_tips) REFERENCES public.ta_story(pk_story);


--
-- Name: ta_user_policy ta_user_policy_fk_policy_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_policy
    ADD CONSTRAINT ta_user_policy_fk_policy_fkey FOREIGN KEY (fk_policy) REFERENCES public.ta_policy(pk_policy);


--
-- Name: ta_user_policy ta_user_policy_fk_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_policy
    ADD CONSTRAINT ta_user_policy_fk_user_fkey FOREIGN KEY (fk_user) REFERENCES public.ta_user(pk_user);


--
-- Name: ta_user_relationship ta_user_relationships_fk_followed_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_relationship
    ADD CONSTRAINT ta_user_relationships_fk_followed_id_fkey FOREIGN KEY (fk_followed_id) REFERENCES public.ta_user(pk_user) ON DELETE CASCADE;


--
-- Name: ta_user_relationship ta_user_relationships_fk_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_relationship
    ADD CONSTRAINT ta_user_relationships_fk_follower_id_fkey FOREIGN KEY (fk_follower_id) REFERENCES public.ta_user(pk_user) ON DELETE CASCADE;


--
-- Name: ta_user_role ta_user_role_fk_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_role
    ADD CONSTRAINT ta_user_role_fk_role_fkey FOREIGN KEY (fk_role) REFERENCES public.ta_role(pk_role) ON DELETE CASCADE;


--
-- Name: ta_user_role ta_user_role_fk_user_fkey; Type: FK CONSTRAINT; Schema: public; Owner: stories
--

ALTER TABLE ONLY public.ta_user_role
    ADD CONSTRAINT ta_user_role_fk_user_fkey FOREIGN KEY (fk_user) REFERENCES public.ta_user(pk_user) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict zejQbaZa13euiTWWOGyD7sKNW3gqB65n8U3ltEeSNvnQCjL9JKdGmQcchjEJGJ7

