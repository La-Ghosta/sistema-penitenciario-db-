--
-- PostgreSQL database dump
--

\restrict gbThEpfYDCaslgGUTMTBTeSbPH5PIOiNbvQUvavzj16W0kO0H2vozfxNbbZjqH4

-- Dumped from database version 18.0
-- Dumped by pg_dump version 18.0

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
-- Name: prisional; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA prisional;


ALTER SCHEMA prisional OWNER TO postgres;

--
-- Name: fn_trigger_auditoria_acesso(); Type: FUNCTION; Schema: prisional; Owner: postgres
--

CREATE FUNCTION prisional.fn_trigger_auditoria_acesso() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO auditoria_acesso (id_acesso, acao, dados_anteriores, dados_novos, ip_origem)
    VALUES (
        COALESCE(NEW.id_acesso, OLD.id_acesso),
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
        inet_client_addr()::VARCHAR
    );
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION prisional.fn_trigger_auditoria_acesso() OWNER TO postgres;

--
-- Name: fn_trigger_lotacao_cela(); Type: FUNCTION; Schema: prisional; Owner: postgres
--

CREATE FUNCTION prisional.fn_trigger_lotacao_cela() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cela RECORD;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.id_cela IS NOT NULL THEN
            SELECT * INTO v_cela FROM cela WHERE id_cela = NEW.id_cela;
            IF NOT FOUND THEN RAISE EXCEPTION 'Cela % não existe', NEW.id_cela; END IF;
            IF NOT v_cela.ativa THEN RAISE EXCEPTION 'Cela %/% desativada', v_cela.numero, v_cela.bloco; END IF;
            IF v_cela.ocupacao_atual >= v_cela.capacidade THEN
                RAISE EXCEPTION 'Cela %/% lotada (%/%)', v_cela.numero, v_cela.bloco, v_cela.ocupacao_atual, v_cela.capacidade;
            END IF;
            UPDATE cela SET ocupacao_atual = ocupacao_atual + 1 WHERE id_cela = NEW.id_cela;
        END IF;
        RETURN NEW;
    END IF;
    

    IF TG_OP = 'UPDATE' THEN
        IF OLD.id_cela IS DISTINCT FROM NEW.id_cela THEN
            -- Saiu de uma cela
            IF OLD.id_cela IS NOT NULL THEN
                UPDATE cela SET ocupacao_atual = GREATEST(ocupacao_atual - 1, 0) WHERE id_cela = OLD.id_cela;
            END IF;
            -- Entrou em uma cela
            IF NEW.id_cela IS NOT NULL THEN
                SELECT * INTO v_cela FROM cela WHERE id_cela = NEW.id_cela;
                IF NOT FOUND THEN RAISE EXCEPTION 'Cela % não existe', NEW.id_cela; END IF;
                IF NOT v_cela.ativa THEN RAISE EXCEPTION 'Cela %/% desativada', v_cela.numero, v_cela.bloco; END IF;
                IF v_cela.ocupacao_atual >= v_cela.capacidade THEN
                    RAISE EXCEPTION 'Cela %/% lotada (%/%)', v_cela.numero, v_cela.bloco, v_cela.ocupacao_atual, v_cela.capacidade;
                END IF;
                UPDATE cela SET ocupacao_atual = ocupacao_atual + 1 WHERE id_cela = NEW.id_cela;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    
    IF TG_OP = 'DELETE' THEN
        IF OLD.id_cela IS NOT NULL THEN
            UPDATE cela SET ocupacao_atual = GREATEST(ocupacao_atual - 1, 0) WHERE id_cela = OLD.id_cela;
        END IF;
        RETURN OLD;
    END IF;
    
    RETURN NULL;

END;
$$;


ALTER FUNCTION prisional.fn_trigger_lotacao_cela() OWNER TO postgres;

--
-- Name: fn_verificar_permissao_acesso(integer, integer); Type: FUNCTION; Schema: prisional; Owner: postgres
--

CREATE FUNCTION prisional.fn_verificar_permissao_acesso(p_id_funcionario integer, p_id_cela integer) RETURNS TABLE(permitido boolean, motivo text, nivel_funcionario integer, nivel_cela integer, nome_funcionario character varying, info_cela character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_func  RECORD;
    v_cela  RECORD;
BEGIN
    -- Busca dados do funcionário
    SELECT f.*, c.nome AS cargo_nome, c.nivel AS cargo_nivel, d.nome AS depto_nome
    INTO v_func
    FROM funcionario f
    JOIN cargo c ON f.id_cargo = c.id_cargo
    JOIN departamento d ON f.id_departamento = d.id_departamento
    WHERE f.id_funcionario = p_id_funcionario;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Funcionário não encontrado'::TEXT, 
            NULL::INTEGER, NULL::INTEGER, NULL::VARCHAR, NULL::VARCHAR;
        RETURN;
    END IF;

    -- Busca dados da cela
    SELECT ce.*, d.nome AS depto_nome INTO v_cela
    FROM cela ce JOIN departamento d ON ce.id_departamento = d.id_departamento
    WHERE ce.id_cela = p_id_cela;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Cela não encontrada'::TEXT,
            v_func.cargo_nivel, NULL::INTEGER, v_func.nome::VARCHAR, NULL::VARCHAR;
        RETURN;
    END IF;

    -- Validações
    IF v_func.status IN ('DESLIGADO', 'LICENCA') THEN
        RETURN QUERY SELECT FALSE, FORMAT('Funcionário com status %s', v_func.status)::TEXT,
            v_func.cargo_nivel, v_cela.nivel_seguranca,
            v_func.nome::VARCHAR, FORMAT('%s/%s', v_cela.numero, v_cela.bloco)::VARCHAR;
        RETURN;
    END IF;

    IF NOT v_cela.ativa THEN
        RETURN QUERY SELECT FALSE, 'Cela desativada'::TEXT,
            v_func.cargo_nivel, v_cela.nivel_seguranca,
            v_func.nome::VARCHAR, FORMAT('%s/%s', v_cela.numero, v_cela.bloco)::VARCHAR;
        RETURN;
    END IF;

    IF v_cela.tipo = 'ENFERMARIA' THEN
        IF v_func.depto_nome != 'Saúde' AND NOT (v_func.depto_nome = 'Segurança' AND v_func.cargo_nivel >= 3) THEN
            RETURN QUERY SELECT FALSE, 'Enfermaria: apenas Saúde ou Guarda III+'::TEXT,
                v_func.cargo_nivel, v_cela.nivel_seguranca,
                v_func.nome::VARCHAR, FORMAT('%s/%s', v_cela.numero, v_cela.bloco)::VARCHAR;
            RETURN;
        END IF;
    END IF;

    IF v_cela.tipo = 'SEGURANCA_MAXIMA' AND v_func.cargo_nivel < 3 THEN
        RETURN QUERY SELECT FALSE, FORMAT('Seg. máxima requer nível 3+. Você: %s', v_func.cargo_nivel)::TEXT,
            v_func.cargo_nivel, v_cela.nivel_seguranca,
            v_func.nome::VARCHAR, FORMAT('%s/%s', v_cela.numero, v_cela.bloco)::VARCHAR;
        RETURN;
    END IF;

    IF v_cela.tipo = 'ISOLAMENTO' AND v_func.cargo_nivel < 3 THEN
        RETURN QUERY SELECT FALSE, FORMAT('Isolamento requer nível 3+. Você: %s', v_func.cargo_nivel)::TEXT,
            v_func.cargo_nivel, v_cela.nivel_seguranca,
            v_func.nome::VARCHAR, FORMAT('%s/%s', v_cela.numero, v_cela.bloco)::VARCHAR;
        RETURN;
    END IF;

    IF v_func.cargo_nivel < v_cela.nivel_seguranca THEN
        RETURN QUERY SELECT FALSE, FORMAT('Nível insuficiente. Cargo: %s, Cela: %s', v_func.cargo_nivel, v_cela.nivel_seguranca)::TEXT,
            v_func.cargo_nivel, v_cela.nivel_seguranca,
            v_func.nome::VARCHAR, FORMAT('%s/%s', v_cela.numero, v_cela.bloco)::VARCHAR;
        RETURN;
    END IF;

    -- Sucesso
    RETURN QUERY SELECT TRUE, FORMAT('Acesso liberado para %s', v_func.nome)::TEXT,
        v_func.cargo_nivel, v_cela.nivel_seguranca,
        v_func.nome::VARCHAR, FORMAT('%s/%s (%s)', v_cela.numero, v_cela.bloco, v_cela.tipo)::VARCHAR;
END;
$$;


ALTER FUNCTION prisional.fn_verificar_permissao_acesso(p_id_funcionario integer, p_id_cela integer) OWNER TO postgres;

--
-- Name: sp_registrar_movimentacao_detento(integer, integer, integer, character varying, text); Type: PROCEDURE; Schema: prisional; Owner: postgres
--

CREATE PROCEDURE prisional.sp_registrar_movimentacao_detento(IN p_id_funcionario integer, IN p_id_detento integer, IN p_id_cela_destino integer, IN p_tipo_movimentacao character varying, IN p_observacao text DEFAULT NULL::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_detento      RECORD;
    v_cela_destino RECORD;
    v_permissao    RECORD;
    v_novo_status  VARCHAR(15);
    v_tipo_acesso  VARCHAR(20);
BEGIN
    IF p_tipo_movimentacao NOT IN ('TRANSFERENCIA_INTERNA', 'LIBERACAO', 'ISOLAMENTO', 
                                   'INTERNACAO_ENFERMARIA', 'RETORNO_CELA') THEN
        RAISE EXCEPTION 'Tipo inválido: %', p_tipo_movimentacao;
    END IF;

    SELECT d.*, c.numero AS cela_numero, c.bloco AS cela_bloco INTO v_detento
    FROM detento d LEFT JOIN cela c ON d.id_cela = c.id_cela
    WHERE d.id_detento = p_id_detento;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Detento % não encontrado', p_id_detento;
    END IF;
    
    IF v_detento.status IN ('LIBERADO', 'TRANSFERIDO', 'EVADIDO') THEN
        RAISE EXCEPTION 'Detento % já com status %', v_detento.nome, v_detento.status;
    END IF;

    -- Lógica de Liberação
    IF p_tipo_movimentacao = 'LIBERACAO' THEN
        UPDATE detento SET 
            id_cela = NULL, status = 'LIBERADO', data_saida = CURRENT_DATE,
            observacoes = COALESCE(observacoes || E'\n', '') || 
                          FORMAT('[%s] LIBERAÇÃO: %s', CURRENT_DATE, COALESCE(p_observacao, '-'))
        WHERE id_detento = p_id_detento;
        
        INSERT INTO acesso (id_funcionario, id_cela, id_detento, tipo, status, observacao)
        VALUES (p_id_funcionario, v_detento.id_cela, p_id_detento, 'TRANSFERENCIA', 'APROVADO',
                FORMAT('LIBERAÇÃO. %s', COALESCE(p_observacao, '')));
        
        RAISE NOTICE 'Detento % liberado', v_detento.nome;
        RETURN;
    END IF;

    -- Validação Cela Destino
    IF p_id_cela_destino IS NULL THEN
        RAISE EXCEPTION 'Cela destino obrigatória para %', p_tipo_movimentacao;
    END IF;
    
    SELECT * INTO v_cela_destino FROM cela WHERE id_cela = p_id_cela_destino;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cela destino % não existe', p_id_cela_destino;
    END IF;
    
    IF NOT v_cela_destino.ativa THEN
        RAISE EXCEPTION 'Cela %/% desativada', v_cela_destino.numero, v_cela_destino.bloco;
    END IF;

    -- Verifica Permissão (Chama a função acima)
    SELECT * INTO v_permissao FROM fn_verificar_permissao_acesso(p_id_funcionario, p_id_cela_destino);
    IF NOT v_permissao.permitido THEN
        RAISE EXCEPTION 'Sem permissão: %', v_permissao.motivo;
    END IF;

    -- Verifica Lotação
    IF v_cela_destino.ocupacao_atual >= v_cela_destino.capacidade THEN
        RAISE EXCEPTION 'Cela %/% lotada (%/%)', v_cela_destino.numero, v_cela_destino.bloco,
            v_cela_destino.ocupacao_atual, v_cela_destino.capacidade;
    END IF;

    -- Define novo status
    CASE p_tipo_movimentacao
        WHEN 'ISOLAMENTO' THEN v_novo_status := 'ISOLAMENTO'; v_tipo_acesso := 'TRANSFERENCIA';
        WHEN 'INTERNACAO_ENFERMARIA' THEN v_novo_status := 'ENFERMARIA'; v_tipo_acesso := 'ATENDIMENTO_MEDICO';
        ELSE v_novo_status := 'ATIVO'; v_tipo_acesso := 'TRANSFERENCIA';
    END CASE;

    -- Atualiza Detento
    UPDATE detento SET 
        id_cela = p_id_cela_destino, status = v_novo_status,
        observacoes = COALESCE(observacoes || E'\n', '') || 
                      FORMAT('[%s] %s: %s/%s -> %s/%s. %s', CURRENT_DATE, p_tipo_movimentacao,
                             COALESCE(v_detento.cela_numero, '-'), COALESCE(v_detento.cela_bloco, '-'),
                             v_cela_destino.numero, v_cela_destino.bloco, COALESCE(p_observacao, ''))
    WHERE id_detento = p_id_detento;

    -- Registra Acesso
    INSERT INTO acesso (id_funcionario, id_cela, id_detento, tipo, status, observacao)
    VALUES (p_id_funcionario, p_id_cela_destino, p_id_detento, v_tipo_acesso, 'APROVADO',
            FORMAT('%s: %s/%s -> %s/%s', p_tipo_movimentacao,
                   COALESCE(v_detento.cela_numero, '-'), COALESCE(v_detento.cela_bloco, '-'),
                   v_cela_destino.numero, v_cela_destino.bloco));
    
    RAISE NOTICE 'Detento % movido para %/% (status: %)', 
        v_detento.nome, v_cela_destino.numero, v_cela_destino.bloco, v_novo_status;
END;
$$;


ALTER PROCEDURE prisional.sp_registrar_movimentacao_detento(IN p_id_funcionario integer, IN p_id_detento integer, IN p_id_cela_destino integer, IN p_tipo_movimentacao character varying, IN p_observacao text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: acesso; Type: TABLE; Schema: prisional; Owner: postgres
--

CREATE TABLE prisional.acesso (
    id_acesso integer NOT NULL,
    id_funcionario integer NOT NULL,
    id_cela integer NOT NULL,
    id_detento integer,
    data_hora timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tipo character varying(20) NOT NULL,
    status character varying(15) DEFAULT 'APROVADO'::character varying NOT NULL,
    observacao text,
    CONSTRAINT acesso_status_check CHECK (((status)::text = ANY ((ARRAY['APROVADO'::character varying, 'NEGADO'::character varying, 'PENDENTE'::character varying])::text[]))),
    CONSTRAINT acesso_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['PATRULHA'::character varying, 'VISITA_TECNICA'::character varying, 'ATENDIMENTO_MEDICO'::character varying, 'TRANSFERENCIA'::character varying, 'ESCOLTA'::character varying, 'EMERGENCIA'::character varying, 'REVISTA'::character varying])::text[])))
);


ALTER TABLE prisional.acesso OWNER TO postgres;

--
-- Name: acesso_id_acesso_seq; Type: SEQUENCE; Schema: prisional; Owner: postgres
--

CREATE SEQUENCE prisional.acesso_id_acesso_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE prisional.acesso_id_acesso_seq OWNER TO postgres;

--
-- Name: acesso_id_acesso_seq; Type: SEQUENCE OWNED BY; Schema: prisional; Owner: postgres
--

ALTER SEQUENCE prisional.acesso_id_acesso_seq OWNED BY prisional.acesso.id_acesso;


--
-- Name: auditoria_acesso; Type: TABLE; Schema: prisional; Owner: postgres
--

CREATE TABLE prisional.auditoria_acesso (
    id_auditoria integer NOT NULL,
    id_acesso integer NOT NULL,
    acao character varying(10) NOT NULL,
    data_hora_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usuario_banco character varying(50) DEFAULT CURRENT_USER NOT NULL,
    dados_anteriores jsonb,
    dados_novos jsonb,
    ip_origem character varying(45),
    CONSTRAINT auditoria_acesso_acao_check CHECK (((acao)::text = ANY ((ARRAY['INSERT'::character varying, 'UPDATE'::character varying, 'DELETE'::character varying])::text[])))
);


ALTER TABLE prisional.auditoria_acesso OWNER TO postgres;

--
-- Name: auditoria_acesso_id_auditoria_seq; Type: SEQUENCE; Schema: prisional; Owner: postgres
--

CREATE SEQUENCE prisional.auditoria_acesso_id_auditoria_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE prisional.auditoria_acesso_id_auditoria_seq OWNER TO postgres;

--
-- Name: auditoria_acesso_id_auditoria_seq; Type: SEQUENCE OWNED BY; Schema: prisional; Owner: postgres
--

ALTER SEQUENCE prisional.auditoria_acesso_id_auditoria_seq OWNED BY prisional.auditoria_acesso.id_auditoria;


--
-- Name: cargo; Type: TABLE; Schema: prisional; Owner: postgres
--

CREATE TABLE prisional.cargo (
    id_cargo integer NOT NULL,
    nome character varying(50) NOT NULL,
    nivel integer NOT NULL,
    is_chefia boolean DEFAULT false NOT NULL,
    descricao text,
    CONSTRAINT cargo_nivel_check CHECK (((nivel >= 1) AND (nivel <= 5)))
);


ALTER TABLE prisional.cargo OWNER TO postgres;

--
-- Name: cargo_id_cargo_seq; Type: SEQUENCE; Schema: prisional; Owner: postgres
--

CREATE SEQUENCE prisional.cargo_id_cargo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE prisional.cargo_id_cargo_seq OWNER TO postgres;

--
-- Name: cargo_id_cargo_seq; Type: SEQUENCE OWNED BY; Schema: prisional; Owner: postgres
--

ALTER SEQUENCE prisional.cargo_id_cargo_seq OWNED BY prisional.cargo.id_cargo;


--
-- Name: cela; Type: TABLE; Schema: prisional; Owner: postgres
--

CREATE TABLE prisional.cela (
    id_cela integer NOT NULL,
    numero character varying(10) NOT NULL,
    bloco character varying(5) NOT NULL,
    capacidade integer NOT NULL,
    ocupacao_atual integer DEFAULT 0 NOT NULL,
    nivel_seguranca integer NOT NULL,
    tipo character varying(20) NOT NULL,
    id_departamento integer NOT NULL,
    ativa boolean DEFAULT true NOT NULL,
    CONSTRAINT cela_capacidade_check CHECK (((capacidade > 0) AND (capacidade <= 20))),
    CONSTRAINT cela_nivel_seguranca_check CHECK (((nivel_seguranca >= 1) AND (nivel_seguranca <= 5))),
    CONSTRAINT cela_ocupacao_atual_check CHECK ((ocupacao_atual >= 0)),
    CONSTRAINT cela_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['COMUM'::character varying, 'ISOLAMENTO'::character varying, 'ENFERMARIA'::character varying, 'SEGURANCA_MAXIMA'::character varying, 'PROVISORIA'::character varying])::text[]))),
    CONSTRAINT chk_ocupacao_capacidade CHECK ((ocupacao_atual <= capacidade))
);


ALTER TABLE prisional.cela OWNER TO postgres;

--
-- Name: cela_id_cela_seq; Type: SEQUENCE; Schema: prisional; Owner: postgres
--

CREATE SEQUENCE prisional.cela_id_cela_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE prisional.cela_id_cela_seq OWNER TO postgres;

--
-- Name: cela_id_cela_seq; Type: SEQUENCE OWNED BY; Schema: prisional; Owner: postgres
--

ALTER SEQUENCE prisional.cela_id_cela_seq OWNED BY prisional.cela.id_cela;


--
-- Name: departamento; Type: TABLE; Schema: prisional; Owner: postgres
--

CREATE TABLE prisional.departamento (
    id_departamento integer NOT NULL,
    nome character varying(50) NOT NULL,
    descricao text,
    id_chefe integer,
    CONSTRAINT departamento_nome_check CHECK (((nome)::text = ANY ((ARRAY['Diretoria'::character varying, 'Segurança'::character varying, 'Saúde'::character varying, 'Reabilitação'::character varying, 'Administração'::character varying])::text[])))
);


ALTER TABLE prisional.departamento OWNER TO postgres;

--
-- Name: departamento_id_departamento_seq; Type: SEQUENCE; Schema: prisional; Owner: postgres
--

CREATE SEQUENCE prisional.departamento_id_departamento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE prisional.departamento_id_departamento_seq OWNER TO postgres;

--
-- Name: departamento_id_departamento_seq; Type: SEQUENCE OWNED BY; Schema: prisional; Owner: postgres
--

ALTER SEQUENCE prisional.departamento_id_departamento_seq OWNED BY prisional.departamento.id_departamento;


--
-- Name: detento; Type: TABLE; Schema: prisional; Owner: postgres
--

CREATE TABLE prisional.detento (
    id_detento integer NOT NULL,
    nome character varying(100) NOT NULL,
    cpf character varying(14) NOT NULL,
    data_nascimento date NOT NULL,
    data_entrada date DEFAULT CURRENT_DATE NOT NULL,
    data_saida date,
    status character varying(15) DEFAULT 'ATIVO'::character varying NOT NULL,
    nivel_periculosidade integer DEFAULT 1 NOT NULL,
    id_cela integer,
    regime character varying(15) NOT NULL,
    observacoes text,
    CONSTRAINT chk_cela_status CHECK (((((status)::text = ANY ((ARRAY['LIBERADO'::character varying, 'TRANSFERIDO'::character varying, 'EVADIDO'::character varying])::text[])) AND (id_cela IS NULL)) OR (((status)::text = ANY ((ARRAY['ATIVO'::character varying, 'ISOLAMENTO'::character varying, 'ENFERMARIA'::character varying])::text[])) AND (id_cela IS NOT NULL)))),
    CONSTRAINT chk_data_saida CHECK (((data_saida IS NULL) OR (data_saida >= data_entrada))),
    CONSTRAINT detento_nivel_periculosidade_check CHECK (((nivel_periculosidade >= 1) AND (nivel_periculosidade <= 5))),
    CONSTRAINT detento_regime_check CHECK (((regime)::text = ANY ((ARRAY['FECHADO'::character varying, 'SEMIABERTO'::character varying, 'ABERTO'::character varying])::text[]))),
    CONSTRAINT detento_status_check CHECK (((status)::text = ANY ((ARRAY['ATIVO'::character varying, 'ISOLAMENTO'::character varying, 'ENFERMARIA'::character varying, 'LIBERADO'::character varying, 'TRANSFERIDO'::character varying, 'EVADIDO'::character varying])::text[])))
);


ALTER TABLE prisional.detento OWNER TO postgres;

--
-- Name: detento_id_detento_seq; Type: SEQUENCE; Schema: prisional; Owner: postgres
--

CREATE SEQUENCE prisional.detento_id_detento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE prisional.detento_id_detento_seq OWNER TO postgres;

--
-- Name: detento_id_detento_seq; Type: SEQUENCE OWNED BY; Schema: prisional; Owner: postgres
--

ALTER SEQUENCE prisional.detento_id_detento_seq OWNED BY prisional.detento.id_detento;


--
-- Name: funcionario; Type: TABLE; Schema: prisional; Owner: postgres
--

CREATE TABLE prisional.funcionario (
    id_funcionario integer NOT NULL,
    nome character varying(100) NOT NULL,
    cpf character varying(14) NOT NULL,
    matricula character varying(20) NOT NULL,
    id_cargo integer NOT NULL,
    id_departamento integer NOT NULL,
    turno character varying(10) NOT NULL,
    data_admissao date DEFAULT CURRENT_DATE NOT NULL,
    status character varying(15) DEFAULT 'ATIVO'::character varying NOT NULL,
    email character varying(100),
    telefone character varying(15),
    CONSTRAINT funcionario_status_check CHECK (((status)::text = ANY ((ARRAY['ATIVO'::character varying, 'FERIAS'::character varying, 'LICENCA'::character varying, 'DESLIGADO'::character varying])::text[]))),
    CONSTRAINT funcionario_turno_check CHECK (((turno)::text = ANY ((ARRAY['Manhã'::character varying, 'Tarde'::character varying, 'Noite'::character varying, 'Integral'::character varying])::text[])))
);


ALTER TABLE prisional.funcionario OWNER TO postgres;

--
-- Name: funcionario_id_funcionario_seq; Type: SEQUENCE; Schema: prisional; Owner: postgres
--

CREATE SEQUENCE prisional.funcionario_id_funcionario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE prisional.funcionario_id_funcionario_seq OWNER TO postgres;

--
-- Name: funcionario_id_funcionario_seq; Type: SEQUENCE OWNED BY; Schema: prisional; Owner: postgres
--

ALTER SEQUENCE prisional.funcionario_id_funcionario_seq OWNED BY prisional.funcionario.id_funcionario;


--
-- Name: acesso id_acesso; Type: DEFAULT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.acesso ALTER COLUMN id_acesso SET DEFAULT nextval('prisional.acesso_id_acesso_seq'::regclass);


--
-- Name: auditoria_acesso id_auditoria; Type: DEFAULT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.auditoria_acesso ALTER COLUMN id_auditoria SET DEFAULT nextval('prisional.auditoria_acesso_id_auditoria_seq'::regclass);


--
-- Name: cargo id_cargo; Type: DEFAULT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.cargo ALTER COLUMN id_cargo SET DEFAULT nextval('prisional.cargo_id_cargo_seq'::regclass);


--
-- Name: cela id_cela; Type: DEFAULT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.cela ALTER COLUMN id_cela SET DEFAULT nextval('prisional.cela_id_cela_seq'::regclass);


--
-- Name: departamento id_departamento; Type: DEFAULT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.departamento ALTER COLUMN id_departamento SET DEFAULT nextval('prisional.departamento_id_departamento_seq'::regclass);


--
-- Name: detento id_detento; Type: DEFAULT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.detento ALTER COLUMN id_detento SET DEFAULT nextval('prisional.detento_id_detento_seq'::regclass);


--
-- Name: funcionario id_funcionario; Type: DEFAULT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.funcionario ALTER COLUMN id_funcionario SET DEFAULT nextval('prisional.funcionario_id_funcionario_seq'::regclass);


--
-- Data for Name: acesso; Type: TABLE DATA; Schema: prisional; Owner: postgres
--

INSERT INTO prisional.acesso VALUES (1, 3, 1, NULL, '2024-01-15 08:00:00', 'PATRULHA', 'APROVADO', 'Ronda matinal Bloco A');
INSERT INTO prisional.acesso VALUES (2, 4, 2, NULL, '2024-01-15 08:15:00', 'PATRULHA', 'APROVADO', 'Ronda matinal Bloco A');
INSERT INTO prisional.acesso VALUES (3, 5, 5, NULL, '2024-01-15 14:00:00', 'PATRULHA', 'APROVADO', 'Ronda vespertina Bloco B');
INSERT INTO prisional.acesso VALUES (4, 8, 8, NULL, '2024-01-15 22:00:00', 'PATRULHA', 'APROVADO', 'Ronda noturna seg. máxima');
INSERT INTO prisional.acesso VALUES (5, 10, 13, 18, '2024-01-14 10:00:00', 'ATENDIMENTO_MEDICO', 'APROVADO', 'Consulta TB');
INSERT INTO prisional.acesso VALUES (6, 11, 13, 18, '2024-01-15 09:30:00', 'ATENDIMENTO_MEDICO', 'APROVADO', 'Medicação');
INSERT INTO prisional.acesso VALUES (7, 9, 5, 10, '2024-01-15 11:00:00', 'ATENDIMENTO_MEDICO', 'APROVADO', 'Detento com queixas');
INSERT INTO prisional.acesso VALUES (8, 13, 1, 1, '2024-01-15 14:00:00', 'VISITA_TECNICA', 'APROVADO', 'Acompanhamento psicológico');
INSERT INTO prisional.acesso VALUES (9, 14, 1, 3, '2024-01-15 15:00:00', 'VISITA_TECNICA', 'APROVADO', 'Avaliação progressão');
INSERT INTO prisional.acesso VALUES (10, 3, 11, 17, '2024-01-10 09:00:00', 'TRANSFERENCIA', 'APROVADO', 'Enviado para isolamento');
INSERT INTO prisional.acesso VALUES (11, 8, 13, 18, '2024-01-12 08:00:00', 'TRANSFERENCIA', 'APROVADO', 'Internação enfermaria');
INSERT INTO prisional.acesso VALUES (12, 3, 8, 15, '2024-01-08 10:00:00', 'ESCOLTA', 'APROVADO', 'Audiência no fórum');
INSERT INTO prisional.acesso VALUES (13, 4, 2, NULL, '2024-01-14 06:00:00', 'REVISTA', 'APROVADO', 'Revista geral');
INSERT INTO prisional.acesso VALUES (14, 6, 8, NULL, '2024-01-15 15:00:00', 'PATRULHA', 'NEGADO', 'Guarda I sem acesso Bloco C');
INSERT INTO prisional.acesso VALUES (15, 7, 9, 16, '2024-01-15 20:00:00', 'ATENDIMENTO_MEDICO', 'NEGADO', 'Guarda não faz atendimento');


--
-- Data for Name: auditoria_acesso; Type: TABLE DATA; Schema: prisional; Owner: postgres
--



--
-- Data for Name: cargo; Type: TABLE DATA; Schema: prisional; Owner: postgres
--

INSERT INTO prisional.cargo VALUES (1, 'Guarda I', 1, false, 'Guarda iniciante, acesso básico');
INSERT INTO prisional.cargo VALUES (2, 'Guarda II', 2, false, 'Guarda intermediário');
INSERT INTO prisional.cargo VALUES (3, 'Guarda III', 3, true, 'Guarda sênior, pode chefiar equipe');
INSERT INTO prisional.cargo VALUES (4, 'Enfermeiro', 2, false, 'Profissional de enfermagem');
INSERT INTO prisional.cargo VALUES (5, 'Médico', 3, false, 'Médico plantonista');
INSERT INTO prisional.cargo VALUES (6, 'Médico-Chefe', 4, true, 'Chefe da ala de saúde');
INSERT INTO prisional.cargo VALUES (7, 'Psicólogo', 2, false, 'Atendimento psicológico');
INSERT INTO prisional.cargo VALUES (8, 'Assistente Social', 2, false, 'Acompanhamento social');
INSERT INTO prisional.cargo VALUES (9, 'Coord. Reabilitação', 3, true, 'Coordena programas de ressocialização');
INSERT INTO prisional.cargo VALUES (10, 'Auxiliar Admin.', 1, false, 'Apoio administrativo');
INSERT INTO prisional.cargo VALUES (11, 'Chefe Admin.', 3, true, 'Chefia o setor administrativo');
INSERT INTO prisional.cargo VALUES (12, 'Subdiretor', 4, true, 'Vice-diretor');
INSERT INTO prisional.cargo VALUES (13, 'Diretor Geral', 5, true, 'Autoridade máxima');


--
-- Data for Name: cela; Type: TABLE DATA; Schema: prisional; Owner: postgres
--

INSERT INTO prisional.cela VALUES (1, 'A-101', 'A', 4, 3, 2, 'COMUM', 2, true);
INSERT INTO prisional.cela VALUES (2, 'A-102', 'A', 4, 4, 2, 'COMUM', 2, true);
INSERT INTO prisional.cela VALUES (3, 'A-103', 'A', 4, 2, 2, 'COMUM', 2, true);
INSERT INTO prisional.cela VALUES (4, 'A-104', 'A', 4, 0, 2, 'COMUM', 2, true);
INSERT INTO prisional.cela VALUES (5, 'B-201', 'B', 2, 2, 3, 'COMUM', 2, true);
INSERT INTO prisional.cela VALUES (6, 'B-202', 'B', 2, 1, 3, 'COMUM', 2, true);
INSERT INTO prisional.cela VALUES (7, 'B-203', 'B', 2, 2, 3, 'COMUM', 2, true);
INSERT INTO prisional.cela VALUES (8, 'C-301', 'C', 1, 1, 5, 'SEGURANCA_MAXIMA', 2, true);
INSERT INTO prisional.cela VALUES (9, 'C-302', 'C', 1, 1, 5, 'SEGURANCA_MAXIMA', 2, true);
INSERT INTO prisional.cela VALUES (10, 'C-303', 'C', 1, 0, 5, 'SEGURANCA_MAXIMA', 2, true);
INSERT INTO prisional.cela VALUES (11, 'D-401', 'D', 1, 1, 4, 'ISOLAMENTO', 2, true);
INSERT INTO prisional.cela VALUES (12, 'D-402', 'D', 1, 0, 4, 'ISOLAMENTO', 2, true);
INSERT INTO prisional.cela VALUES (13, 'E-501', 'E', 3, 1, 2, 'ENFERMARIA', 3, true);
INSERT INTO prisional.cela VALUES (14, 'E-502', 'E', 3, 0, 2, 'ENFERMARIA', 3, true);
INSERT INTO prisional.cela VALUES (15, 'F-601', 'F', 6, 3, 1, 'PROVISORIA', 2, true);


--
-- Data for Name: departamento; Type: TABLE DATA; Schema: prisional; Owner: postgres
--

INSERT INTO prisional.departamento VALUES (1, 'Diretoria', 'Direção geral da unidade', 1);
INSERT INTO prisional.departamento VALUES (2, 'Segurança', 'Custódia e vigilância', 3);
INSERT INTO prisional.departamento VALUES (3, 'Saúde', 'Atendimento médico', 9);
INSERT INTO prisional.departamento VALUES (4, 'Reabilitação', 'Programas de ressocialização', 13);
INSERT INTO prisional.departamento VALUES (5, 'Administração', 'Gestão e logística', 16);


--
-- Data for Name: detento; Type: TABLE DATA; Schema: prisional; Owner: postgres
--

INSERT INTO prisional.detento VALUES (1, 'Marcos Vinícius Ferreira', '666.777.888-01', '1985-03-15', '2022-06-10', NULL, 'ATIVO', 2, 1, 'FECHADO', 'Bom comportamento');
INSERT INTO prisional.detento VALUES (2, 'André Luiz Moreira', '666.777.888-02', '1990-07-22', '2021-11-05', NULL, 'ATIVO', 2, 1, 'FECHADO', 'Aguardando progressão');
INSERT INTO prisional.detento VALUES (3, 'José Carlos Nunes', '666.777.888-03', '1978-12-01', '2020-03-18', NULL, 'ATIVO', 1, 1, 'SEMIABERTO', 'Trabalha na cozinha');
INSERT INTO prisional.detento VALUES (4, 'Paulo Roberto Silva', '666.777.888-04', '1988-09-10', '2023-01-20', NULL, 'ATIVO', 2, 2, 'FECHADO', NULL);
INSERT INTO prisional.detento VALUES (5, 'Thiago Mendes Santos', '666.777.888-05', '1995-04-05', '2023-03-15', NULL, 'ATIVO', 2, 2, 'FECHADO', NULL);
INSERT INTO prisional.detento VALUES (6, 'Rafael Oliveira Lima', '666.777.888-06', '1982-06-30', '2022-08-25', NULL, 'ATIVO', 2, 2, 'FECHADO', 'Clube de leitura');
INSERT INTO prisional.detento VALUES (7, 'Lucas Pereira Costa', '666.777.888-07', '1992-01-18', '2022-12-01', NULL, 'ATIVO', 3, 2, 'FECHADO', 'Histórico de brigas');
INSERT INTO prisional.detento VALUES (8, 'Diego Almeida Souza', '666.777.888-08', '1987-11-25', '2021-07-10', NULL, 'ATIVO', 1, 3, 'SEMIABERTO', 'Trabalha na horta');
INSERT INTO prisional.detento VALUES (9, 'Bruno Henrique Ramos', '666.777.888-09', '1993-08-14', '2023-05-20', NULL, 'ATIVO', 2, 3, 'FECHADO', NULL);
INSERT INTO prisional.detento VALUES (10, 'Ricardo Gomes Dias', '666.777.888-10', '1980-02-28', '2019-09-15', NULL, 'ATIVO', 3, 5, 'FECHADO', 'Liderança entre detentos');
INSERT INTO prisional.detento VALUES (11, 'Fábio Martins Rocha', '666.777.888-11', '1975-05-20', '2018-04-10', NULL, 'ATIVO', 3, 5, 'FECHADO', 'Reincidente');
INSERT INTO prisional.detento VALUES (12, 'Eduardo Santos Filho', '666.777.888-12', '1983-10-08', '2022-02-28', NULL, 'ATIVO', 3, 6, 'FECHADO', NULL);
INSERT INTO prisional.detento VALUES (13, 'Marcelo Ribeiro Alves', '666.777.888-13', '1991-12-12', '2021-06-05', NULL, 'ATIVO', 3, 7, 'FECHADO', 'Envolvido em facção');
INSERT INTO prisional.detento VALUES (14, 'Gustavo Lima Pereira', '666.777.888-14', '1986-07-03', '2020-10-20', NULL, 'ATIVO', 3, 7, 'FECHADO', NULL);
INSERT INTO prisional.detento VALUES (15, 'Roberto Carlos Jr.', '666.777.888-15', '1970-04-15', '2015-01-10', NULL, 'ATIVO', 5, 8, 'FECHADO', 'Líder de organização');
INSERT INTO prisional.detento VALUES (16, 'Antônio José Pereira', '666.777.888-16', '1968-09-22', '2016-08-05', NULL, 'ATIVO', 5, 9, 'FECHADO', 'Crimes hediondos');
INSERT INTO prisional.detento VALUES (17, 'Felipe Augusto Ramos', '666.777.888-17', '1994-03-30', '2023-04-01', NULL, 'ISOLAMENTO', 4, 11, 'FECHADO', 'Tentativa de fuga');
INSERT INTO prisional.detento VALUES (18, 'João Pedro Nascimento', '666.777.888-18', '1989-06-18', '2022-05-15', NULL, 'ENFERMARIA', 2, 13, 'FECHADO', 'Tratamento TB');
INSERT INTO prisional.detento VALUES (19, 'Alexandre Moura Santos', '666.777.888-19', '1997-02-14', '2024-01-05', NULL, 'ATIVO', 2, 15, 'FECHADO', 'Aguardando julgamento');
INSERT INTO prisional.detento VALUES (20, 'Vinícius Costa Oliveira', '666.777.888-20', '1999-08-28', '2024-01-10', NULL, 'ATIVO', 1, 15, 'FECHADO', 'Primeira passagem');
INSERT INTO prisional.detento VALUES (21, 'Leonardo Souza Pinto', '666.777.888-21', '1996-11-05', '2024-01-12', NULL, 'ATIVO', 2, 15, 'FECHADO', 'Aguarda transferência');
INSERT INTO prisional.detento VALUES (22, 'Carlos Alberto Reis', '666.777.888-22', '1972-01-20', '2018-03-10', '2023-03-10', 'LIBERADO', 2, NULL, 'FECHADO', 'Pena cumprida');
INSERT INTO prisional.detento VALUES (23, 'Sérgio Matos Lima', '666.777.888-23', '1980-09-15', '2019-07-20', '2023-12-01', 'LIBERADO', 1, NULL, 'SEMIABERTO', 'Progressão concluída');


--
-- Data for Name: funcionario; Type: TABLE DATA; Schema: prisional; Owner: postgres
--

INSERT INTO prisional.funcionario VALUES (1, 'Roberto Carlos Mendes', '111.222.333-01', 'DIR-001', 13, 1, 'Integral', '2015-03-15', 'ATIVO', 'roberto.mendes@pen.gov.br', '(61) 99999-0001');
INSERT INTO prisional.funcionario VALUES (2, 'Ana Paula Silveira', '111.222.333-02', 'DIR-002', 12, 1, 'Integral', '2018-06-01', 'ATIVO', 'ana.silveira@pen.gov.br', '(61) 99999-0002');
INSERT INTO prisional.funcionario VALUES (3, 'João Silva Santos', '222.333.444-01', 'SEG-001', 3, 2, 'Manhã', '2016-02-10', 'ATIVO', 'joao.santos@pen.gov.br', '(61) 98888-0001');
INSERT INTO prisional.funcionario VALUES (4, 'Maria Oliveira Costa', '222.333.444-02', 'SEG-002', 2, 2, 'Manhã', '2019-08-20', 'ATIVO', 'maria.costa@pen.gov.br', '(61) 98888-0002');
INSERT INTO prisional.funcionario VALUES (5, 'Pedro Henrique Lima', '222.333.444-03', 'SEG-003', 2, 2, 'Tarde', '2020-01-15', 'ATIVO', 'pedro.lima@pen.gov.br', '(61) 98888-0003');
INSERT INTO prisional.funcionario VALUES (6, 'Carla Beatriz Rocha', '222.333.444-04', 'SEG-004', 1, 2, 'Tarde', '2022-03-01', 'ATIVO', 'carla.rocha@pen.gov.br', '(61) 98888-0004');
INSERT INTO prisional.funcionario VALUES (7, 'Fernando Alves Pereira', '222.333.444-05', 'SEG-005', 1, 2, 'Noite', '2023-05-10', 'ATIVO', 'fernando.pereira@pen.gov.br', '(61) 98888-0005');
INSERT INTO prisional.funcionario VALUES (8, 'Juliana Martins Souza', '222.333.444-06', 'SEG-006', 3, 2, 'Noite', '2017-11-25', 'ATIVO', 'juliana.souza@pen.gov.br', '(61) 98888-0006');
INSERT INTO prisional.funcionario VALUES (9, 'Dr. Carlos Eduardo Ramos', '333.444.555-01', 'SAU-001', 6, 3, 'Integral', '2014-07-01', 'ATIVO', 'carlos.ramos@pen.gov.br', '(61) 97777-0001');
INSERT INTO prisional.funcionario VALUES (10, 'Dra. Fernanda Gomes', '333.444.555-02', 'SAU-002', 5, 3, 'Manhã', '2019-02-15', 'ATIVO', 'fernanda.gomes@pen.gov.br', '(61) 97777-0002');
INSERT INTO prisional.funcionario VALUES (11, 'Patrícia Santos', '333.444.555-03', 'SAU-003', 4, 3, 'Manhã', '2020-09-01', 'ATIVO', 'patricia.santos@pen.gov.br', '(61) 97777-0003');
INSERT INTO prisional.funcionario VALUES (12, 'Ricardo Oliveira', '333.444.555-04', 'SAU-004', 4, 3, 'Noite', '2021-04-15', 'ATIVO', 'ricardo.enf@pen.gov.br', '(61) 97777-0004');
INSERT INTO prisional.funcionario VALUES (13, 'Dra. Márcia Psicóloga', '444.555.666-01', 'REA-001', 9, 4, 'Integral', '2016-08-10', 'ATIVO', 'marcia.psi@pen.gov.br', '(61) 96666-0001');
INSERT INTO prisional.funcionario VALUES (14, 'Lucas Assistente Social', '444.555.666-02', 'REA-002', 8, 4, 'Manhã', '2020-11-20', 'ATIVO', 'lucas.social@pen.gov.br', '(61) 96666-0002');
INSERT INTO prisional.funcionario VALUES (15, 'Camila Psicóloga', '444.555.666-03', 'REA-003', 7, 4, 'Tarde', '2022-01-10', 'ATIVO', 'camila.psi@pen.gov.br', '(61) 96666-0003');
INSERT INTO prisional.funcionario VALUES (16, 'Sandra Chefe Admin.', '555.666.777-01', 'ADM-001', 11, 5, 'Integral', '2017-05-05', 'ATIVO', 'sandra.admin@pen.gov.br', '(61) 95555-0001');
INSERT INTO prisional.funcionario VALUES (17, 'Bruno Auxiliar', '555.666.777-02', 'ADM-002', 10, 5, 'Manhã', '2021-08-15', 'ATIVO', 'bruno.aux@pen.gov.br', '(61) 95555-0002');
INSERT INTO prisional.funcionario VALUES (18, 'Daniela Auxiliar', '555.666.777-03', 'ADM-003', 10, 5, 'Tarde', '2023-02-01', 'FERIAS', 'daniela.aux@pen.gov.br', '(61) 95555-0003');


--
-- Name: acesso_id_acesso_seq; Type: SEQUENCE SET; Schema: prisional; Owner: postgres
--

SELECT pg_catalog.setval('prisional.acesso_id_acesso_seq', 15, true);


--
-- Name: auditoria_acesso_id_auditoria_seq; Type: SEQUENCE SET; Schema: prisional; Owner: postgres
--

SELECT pg_catalog.setval('prisional.auditoria_acesso_id_auditoria_seq', 1, false);


--
-- Name: cargo_id_cargo_seq; Type: SEQUENCE SET; Schema: prisional; Owner: postgres
--

SELECT pg_catalog.setval('prisional.cargo_id_cargo_seq', 13, true);


--
-- Name: cela_id_cela_seq; Type: SEQUENCE SET; Schema: prisional; Owner: postgres
--

SELECT pg_catalog.setval('prisional.cela_id_cela_seq', 15, true);


--
-- Name: departamento_id_departamento_seq; Type: SEQUENCE SET; Schema: prisional; Owner: postgres
--

SELECT pg_catalog.setval('prisional.departamento_id_departamento_seq', 5, true);


--
-- Name: detento_id_detento_seq; Type: SEQUENCE SET; Schema: prisional; Owner: postgres
--

SELECT pg_catalog.setval('prisional.detento_id_detento_seq', 23, true);


--
-- Name: funcionario_id_funcionario_seq; Type: SEQUENCE SET; Schema: prisional; Owner: postgres
--

SELECT pg_catalog.setval('prisional.funcionario_id_funcionario_seq', 18, true);


--
-- Name: acesso acesso_pkey; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.acesso
    ADD CONSTRAINT acesso_pkey PRIMARY KEY (id_acesso);


--
-- Name: auditoria_acesso auditoria_acesso_pkey; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.auditoria_acesso
    ADD CONSTRAINT auditoria_acesso_pkey PRIMARY KEY (id_auditoria);


--
-- Name: cargo cargo_nome_key; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.cargo
    ADD CONSTRAINT cargo_nome_key UNIQUE (nome);


--
-- Name: cargo cargo_pkey; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.cargo
    ADD CONSTRAINT cargo_pkey PRIMARY KEY (id_cargo);


--
-- Name: cela cela_pkey; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.cela
    ADD CONSTRAINT cela_pkey PRIMARY KEY (id_cela);


--
-- Name: departamento departamento_nome_key; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.departamento
    ADD CONSTRAINT departamento_nome_key UNIQUE (nome);


--
-- Name: departamento departamento_pkey; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.departamento
    ADD CONSTRAINT departamento_pkey PRIMARY KEY (id_departamento);


--
-- Name: detento detento_cpf_key; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.detento
    ADD CONSTRAINT detento_cpf_key UNIQUE (cpf);


--
-- Name: detento detento_pkey; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.detento
    ADD CONSTRAINT detento_pkey PRIMARY KEY (id_detento);


--
-- Name: funcionario funcionario_cpf_key; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.funcionario
    ADD CONSTRAINT funcionario_cpf_key UNIQUE (cpf);


--
-- Name: funcionario funcionario_matricula_key; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.funcionario
    ADD CONSTRAINT funcionario_matricula_key UNIQUE (matricula);


--
-- Name: funcionario funcionario_pkey; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.funcionario
    ADD CONSTRAINT funcionario_pkey PRIMARY KEY (id_funcionario);


--
-- Name: cela uk_cela_numero_bloco; Type: CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.cela
    ADD CONSTRAINT uk_cela_numero_bloco UNIQUE (numero, bloco);


--
-- Name: idx_acesso_data; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_acesso_data ON prisional.acesso USING btree (data_hora);


--
-- Name: idx_acesso_funcionario; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_acesso_funcionario ON prisional.acesso USING btree (id_funcionario);


--
-- Name: idx_auditoria_data; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_auditoria_data ON prisional.auditoria_acesso USING btree (data_hora_registro);


--
-- Name: idx_cela_depto; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_cela_depto ON prisional.cela USING btree (id_departamento);


--
-- Name: idx_detento_cela; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_detento_cela ON prisional.detento USING btree (id_cela);


--
-- Name: idx_detento_status; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_detento_status ON prisional.detento USING btree (status);


--
-- Name: idx_funcionario_cargo; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_funcionario_cargo ON prisional.funcionario USING btree (id_cargo);


--
-- Name: idx_funcionario_depto; Type: INDEX; Schema: prisional; Owner: postgres
--

CREATE INDEX idx_funcionario_depto ON prisional.funcionario USING btree (id_departamento);


--
-- Name: acesso trg_auditoria_acesso; Type: TRIGGER; Schema: prisional; Owner: postgres
--

CREATE TRIGGER trg_auditoria_acesso AFTER INSERT OR DELETE OR UPDATE ON prisional.acesso FOR EACH ROW EXECUTE FUNCTION prisional.fn_trigger_auditoria_acesso();


--
-- Name: detento trg_validar_lotacao_cela; Type: TRIGGER; Schema: prisional; Owner: postgres
--

CREATE TRIGGER trg_validar_lotacao_cela BEFORE INSERT OR DELETE OR UPDATE ON prisional.detento FOR EACH ROW EXECUTE FUNCTION prisional.fn_trigger_lotacao_cela();


--
-- Name: acesso acesso_id_cela_fkey; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.acesso
    ADD CONSTRAINT acesso_id_cela_fkey FOREIGN KEY (id_cela) REFERENCES prisional.cela(id_cela);


--
-- Name: acesso acesso_id_detento_fkey; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.acesso
    ADD CONSTRAINT acesso_id_detento_fkey FOREIGN KEY (id_detento) REFERENCES prisional.detento(id_detento);


--
-- Name: acesso acesso_id_funcionario_fkey; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.acesso
    ADD CONSTRAINT acesso_id_funcionario_fkey FOREIGN KEY (id_funcionario) REFERENCES prisional.funcionario(id_funcionario);


--
-- Name: cela cela_id_departamento_fkey; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.cela
    ADD CONSTRAINT cela_id_departamento_fkey FOREIGN KEY (id_departamento) REFERENCES prisional.departamento(id_departamento);


--
-- Name: detento detento_id_cela_fkey; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.detento
    ADD CONSTRAINT detento_id_cela_fkey FOREIGN KEY (id_cela) REFERENCES prisional.cela(id_cela);


--
-- Name: departamento fk_departamento_chefe; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.departamento
    ADD CONSTRAINT fk_departamento_chefe FOREIGN KEY (id_chefe) REFERENCES prisional.funcionario(id_funcionario);


--
-- Name: funcionario funcionario_id_cargo_fkey; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.funcionario
    ADD CONSTRAINT funcionario_id_cargo_fkey FOREIGN KEY (id_cargo) REFERENCES prisional.cargo(id_cargo);


--
-- Name: funcionario funcionario_id_departamento_fkey; Type: FK CONSTRAINT; Schema: prisional; Owner: postgres
--

ALTER TABLE ONLY prisional.funcionario
    ADD CONSTRAINT funcionario_id_departamento_fkey FOREIGN KEY (id_departamento) REFERENCES prisional.departamento(id_departamento);


--
-- Name: SCHEMA prisional; Type: ACL; Schema: -; Owner: postgres
--

GRANT USAGE ON SCHEMA prisional TO guilherme_alves;
GRANT USAGE ON SCHEMA prisional TO carlos_eduardo;
GRANT USAGE ON SCHEMA prisional TO luan_ayres;
GRANT USAGE ON SCHEMA prisional TO professor;


--
-- Name: FUNCTION fn_trigger_auditoria_acesso(); Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON FUNCTION prisional.fn_trigger_auditoria_acesso() TO guilherme_alves;
GRANT ALL ON FUNCTION prisional.fn_trigger_auditoria_acesso() TO carlos_eduardo;
GRANT ALL ON FUNCTION prisional.fn_trigger_auditoria_acesso() TO luan_ayres;
GRANT ALL ON FUNCTION prisional.fn_trigger_auditoria_acesso() TO professor;


--
-- Name: FUNCTION fn_trigger_lotacao_cela(); Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON FUNCTION prisional.fn_trigger_lotacao_cela() TO guilherme_alves;
GRANT ALL ON FUNCTION prisional.fn_trigger_lotacao_cela() TO carlos_eduardo;
GRANT ALL ON FUNCTION prisional.fn_trigger_lotacao_cela() TO luan_ayres;
GRANT ALL ON FUNCTION prisional.fn_trigger_lotacao_cela() TO professor;


--
-- Name: FUNCTION fn_verificar_permissao_acesso(p_id_funcionario integer, p_id_cela integer); Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON FUNCTION prisional.fn_verificar_permissao_acesso(p_id_funcionario integer, p_id_cela integer) TO guilherme_alves;
GRANT ALL ON FUNCTION prisional.fn_verificar_permissao_acesso(p_id_funcionario integer, p_id_cela integer) TO carlos_eduardo;
GRANT ALL ON FUNCTION prisional.fn_verificar_permissao_acesso(p_id_funcionario integer, p_id_cela integer) TO luan_ayres;
GRANT ALL ON FUNCTION prisional.fn_verificar_permissao_acesso(p_id_funcionario integer, p_id_cela integer) TO professor;


--
-- Name: PROCEDURE sp_registrar_movimentacao_detento(IN p_id_funcionario integer, IN p_id_detento integer, IN p_id_cela_destino integer, IN p_tipo_movimentacao character varying, IN p_observacao text); Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON PROCEDURE prisional.sp_registrar_movimentacao_detento(IN p_id_funcionario integer, IN p_id_detento integer, IN p_id_cela_destino integer, IN p_tipo_movimentacao character varying, IN p_observacao text) TO guilherme_alves;
GRANT ALL ON PROCEDURE prisional.sp_registrar_movimentacao_detento(IN p_id_funcionario integer, IN p_id_detento integer, IN p_id_cela_destino integer, IN p_tipo_movimentacao character varying, IN p_observacao text) TO carlos_eduardo;
GRANT ALL ON PROCEDURE prisional.sp_registrar_movimentacao_detento(IN p_id_funcionario integer, IN p_id_detento integer, IN p_id_cela_destino integer, IN p_tipo_movimentacao character varying, IN p_observacao text) TO luan_ayres;
GRANT ALL ON PROCEDURE prisional.sp_registrar_movimentacao_detento(IN p_id_funcionario integer, IN p_id_detento integer, IN p_id_cela_destino integer, IN p_tipo_movimentacao character varying, IN p_observacao text) TO professor;


--
-- Name: TABLE acesso; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON TABLE prisional.acesso TO guilherme_alves;
GRANT ALL ON TABLE prisional.acesso TO carlos_eduardo;
GRANT ALL ON TABLE prisional.acesso TO luan_ayres;
GRANT SELECT,INSERT,UPDATE ON TABLE prisional.acesso TO professor;


--
-- Name: SEQUENCE acesso_id_acesso_seq; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON SEQUENCE prisional.acesso_id_acesso_seq TO guilherme_alves;
GRANT ALL ON SEQUENCE prisional.acesso_id_acesso_seq TO carlos_eduardo;
GRANT ALL ON SEQUENCE prisional.acesso_id_acesso_seq TO luan_ayres;
GRANT USAGE ON SEQUENCE prisional.acesso_id_acesso_seq TO professor;


--
-- Name: TABLE auditoria_acesso; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON TABLE prisional.auditoria_acesso TO guilherme_alves;
GRANT ALL ON TABLE prisional.auditoria_acesso TO carlos_eduardo;
GRANT ALL ON TABLE prisional.auditoria_acesso TO luan_ayres;
GRANT SELECT,INSERT,UPDATE ON TABLE prisional.auditoria_acesso TO professor;


--
-- Name: SEQUENCE auditoria_acesso_id_auditoria_seq; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON SEQUENCE prisional.auditoria_acesso_id_auditoria_seq TO guilherme_alves;
GRANT ALL ON SEQUENCE prisional.auditoria_acesso_id_auditoria_seq TO carlos_eduardo;
GRANT ALL ON SEQUENCE prisional.auditoria_acesso_id_auditoria_seq TO luan_ayres;
GRANT USAGE ON SEQUENCE prisional.auditoria_acesso_id_auditoria_seq TO professor;


--
-- Name: TABLE cargo; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON TABLE prisional.cargo TO guilherme_alves;
GRANT ALL ON TABLE prisional.cargo TO carlos_eduardo;
GRANT ALL ON TABLE prisional.cargo TO luan_ayres;
GRANT SELECT,INSERT,UPDATE ON TABLE prisional.cargo TO professor;


--
-- Name: SEQUENCE cargo_id_cargo_seq; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON SEQUENCE prisional.cargo_id_cargo_seq TO guilherme_alves;
GRANT ALL ON SEQUENCE prisional.cargo_id_cargo_seq TO carlos_eduardo;
GRANT ALL ON SEQUENCE prisional.cargo_id_cargo_seq TO luan_ayres;
GRANT USAGE ON SEQUENCE prisional.cargo_id_cargo_seq TO professor;


--
-- Name: TABLE cela; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON TABLE prisional.cela TO guilherme_alves;
GRANT ALL ON TABLE prisional.cela TO carlos_eduardo;
GRANT ALL ON TABLE prisional.cela TO luan_ayres;
GRANT SELECT,INSERT,UPDATE ON TABLE prisional.cela TO professor;


--
-- Name: SEQUENCE cela_id_cela_seq; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON SEQUENCE prisional.cela_id_cela_seq TO guilherme_alves;
GRANT ALL ON SEQUENCE prisional.cela_id_cela_seq TO carlos_eduardo;
GRANT ALL ON SEQUENCE prisional.cela_id_cela_seq TO luan_ayres;
GRANT USAGE ON SEQUENCE prisional.cela_id_cela_seq TO professor;


--
-- Name: TABLE departamento; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON TABLE prisional.departamento TO guilherme_alves;
GRANT ALL ON TABLE prisional.departamento TO carlos_eduardo;
GRANT ALL ON TABLE prisional.departamento TO luan_ayres;
GRANT SELECT,INSERT,UPDATE ON TABLE prisional.departamento TO professor;


--
-- Name: SEQUENCE departamento_id_departamento_seq; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON SEQUENCE prisional.departamento_id_departamento_seq TO guilherme_alves;
GRANT ALL ON SEQUENCE prisional.departamento_id_departamento_seq TO carlos_eduardo;
GRANT ALL ON SEQUENCE prisional.departamento_id_departamento_seq TO luan_ayres;
GRANT USAGE ON SEQUENCE prisional.departamento_id_departamento_seq TO professor;


--
-- Name: TABLE detento; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON TABLE prisional.detento TO guilherme_alves;
GRANT ALL ON TABLE prisional.detento TO carlos_eduardo;
GRANT ALL ON TABLE prisional.detento TO luan_ayres;
GRANT SELECT,INSERT,UPDATE ON TABLE prisional.detento TO professor;


--
-- Name: SEQUENCE detento_id_detento_seq; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON SEQUENCE prisional.detento_id_detento_seq TO guilherme_alves;
GRANT ALL ON SEQUENCE prisional.detento_id_detento_seq TO carlos_eduardo;
GRANT ALL ON SEQUENCE prisional.detento_id_detento_seq TO luan_ayres;
GRANT USAGE ON SEQUENCE prisional.detento_id_detento_seq TO professor;


--
-- Name: TABLE funcionario; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON TABLE prisional.funcionario TO guilherme_alves;
GRANT ALL ON TABLE prisional.funcionario TO carlos_eduardo;
GRANT ALL ON TABLE prisional.funcionario TO luan_ayres;
GRANT SELECT,INSERT,UPDATE ON TABLE prisional.funcionario TO professor;


--
-- Name: SEQUENCE funcionario_id_funcionario_seq; Type: ACL; Schema: prisional; Owner: postgres
--

GRANT ALL ON SEQUENCE prisional.funcionario_id_funcionario_seq TO guilherme_alves;
GRANT ALL ON SEQUENCE prisional.funcionario_id_funcionario_seq TO carlos_eduardo;
GRANT ALL ON SEQUENCE prisional.funcionario_id_funcionario_seq TO luan_ayres;
GRANT USAGE ON SEQUENCE prisional.funcionario_id_funcionario_seq TO professor;


--
-- PostgreSQL database dump complete
--

\unrestrict gbThEpfYDCaslgGUTMTBTeSbPH5PIOiNbvQUvavzj16W0kO0H2vozfxNbbZjqH4

