--Sistema penitenciário



CREATE DATABASE penitenciaria;

CREATE SCHEMA prisional;






-- Tabelas 

SET search_path TO prisional; -- Para evitar ficar mencionando toda vez o prisional na criação

CREATE TABLE cargo (
    id_cargo    SERIAL       PRIMARY KEY,
    nome        VARCHAR(50)  NOT NULL UNIQUE,
    nivel       INTEGER      NOT NULL CHECK (nivel BETWEEN 1 AND 5),
    is_chefia   BOOLEAN      NOT NULL DEFAULT FALSE,
    descricao   TEXT
);



CREATE TABLE departamento (
    id_departamento SERIAL       PRIMARY KEY,
    nome            VARCHAR(50)  NOT NULL UNIQUE 
                    CHECK (nome IN ('Diretoria', 'Segurança', 'Saúde', 'Reabilitação', 'Administração')),
    descricao       TEXT,
    id_chefe        INTEGER   

);



CREATE TABLE funcionario (
    id_funcionario  SERIAL       PRIMARY KEY,
    nome            VARCHAR(100) NOT NULL,
    cpf             VARCHAR(14)  NOT NULL UNIQUE,
    matricula       VARCHAR(20)  NOT NULL UNIQUE,
    id_cargo        INTEGER      NOT NULL REFERENCES cargo(id_cargo),
    id_departamento INTEGER      NOT NULL REFERENCES departamento(id_departamento),
    turno           VARCHAR(10)  NOT NULL CHECK (turno IN ('Manhã', 'Tarde', 'Noite', 'Integral')),
    data_admissao   DATE         NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(15)  NOT NULL DEFAULT 'ATIVO' 
                    CHECK (status IN ('ATIVO', 'FERIAS', 'LICENCA', 'DESLIGADO')),
    email           VARCHAR(100),
    telefone        VARCHAR(15)
);

ALTER TABLE departamento
    ADD CONSTRAINT fk_departamento_chefe
    FOREIGN KEY (id_chefe) REFERENCES funcionario(id_funcionario);



CREATE TABLE cela (
    id_cela         SERIAL       PRIMARY KEY,
    numero          VARCHAR(10)  NOT NULL,
    bloco           VARCHAR(5)   NOT NULL,
    capacidade      INTEGER      NOT NULL CHECK (capacidade > 0 AND capacidade <= 20),
    ocupacao_atual  INTEGER      NOT NULL DEFAULT 0 CHECK (ocupacao_atual >= 0),
    nivel_seguranca INTEGER      NOT NULL CHECK (nivel_seguranca BETWEEN 1 AND 5),
    tipo            VARCHAR(20)  NOT NULL 
                    CHECK (tipo IN ('COMUM', 'ISOLAMENTO', 'ENFERMARIA', 'SEGURANCA_MAXIMA', 'PROVISORIA')),
    id_departamento INTEGER      NOT NULL REFERENCES departamento(id_departamento),
    ativa           BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT uk_cela_numero_bloco UNIQUE (numero, bloco),
    CONSTRAINT chk_ocupacao_capacidade CHECK (ocupacao_atual <= capacidade)
);



CREATE TABLE detento (
    id_detento           SERIAL       PRIMARY KEY,
    nome                 VARCHAR(100) NOT NULL,
    cpf                  VARCHAR(14)  NOT NULL UNIQUE,
    data_nascimento      DATE         NOT NULL,
    data_entrada         DATE         NOT NULL DEFAULT CURRENT_DATE,
    data_saida           DATE,
    status               VARCHAR(15)  NOT NULL DEFAULT 'ATIVO'
                         CHECK (status IN ('ATIVO', 'ISOLAMENTO', 'ENFERMARIA', 'LIBERADO', 'TRANSFERIDO', 'EVADIDO')),
    nivel_periculosidade INTEGER      NOT NULL DEFAULT 1 CHECK (nivel_periculosidade BETWEEN 1 AND 5),
    id_cela              INTEGER      REFERENCES cela(id_cela),
    regime               VARCHAR(15)  NOT NULL CHECK (regime IN ('FECHADO', 'SEMIABERTO', 'ABERTO')),
    observacoes          TEXT,
    CONSTRAINT chk_data_saida CHECK (data_saida IS NULL OR data_saida >= data_entrada),
    CONSTRAINT chk_cela_status CHECK (
        (status IN ('LIBERADO', 'TRANSFERIDO', 'EVADIDO') AND id_cela IS NULL) OR
        (status IN ('ATIVO', 'ISOLAMENTO', 'ENFERMARIA') AND id_cela IS NOT NULL)
    )
);



CREATE TABLE acesso (
    id_acesso       SERIAL       PRIMARY KEY,
    id_funcionario  INTEGER      NOT NULL REFERENCES funcionario(id_funcionario),
    id_cela         INTEGER      NOT NULL REFERENCES cela(id_cela),
    id_detento      INTEGER      REFERENCES detento(id_detento),
    data_hora       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo            VARCHAR(20)  NOT NULL 
                    CHECK (tipo IN ('PATRULHA', 'VISITA_TECNICA', 'ATENDIMENTO_MEDICO', 
                                    'TRANSFERENCIA', 'ESCOLTA', 'EMERGENCIA', 'REVISTA')),
    status          VARCHAR(15)  NOT NULL DEFAULT 'APROVADO'
                    CHECK (status IN ('APROVADO', 'NEGADO', 'PENDENTE')),
    observacao      TEXT
);



CREATE TABLE auditoria_acesso (
    id_auditoria        SERIAL       PRIMARY KEY,
    id_acesso           INTEGER      NOT NULL,
    acao                VARCHAR(10)  NOT NULL CHECK (acao IN ('INSERT', 'UPDATE', 'DELETE')),
    data_hora_registro  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_banco       VARCHAR(50)  NOT NULL DEFAULT CURRENT_USER,
    dados_anteriores    JSONB,
    dados_novos         JSONB,
    ip_origem           VARCHAR(45)
);



--Índices pra melhorar performance 

CREATE INDEX idx_funcionario_cargo ON funcionario(id_cargo);
CREATE INDEX idx_funcionario_depto ON funcionario(id_departamento);
CREATE INDEX idx_cela_depto ON cela(id_departamento);
CREATE INDEX idx_detento_cela ON detento(id_cela);
CREATE INDEX idx_detento_status ON detento(status);
CREATE INDEX idx_acesso_funcionario ON acesso(id_funcionario);
CREATE INDEX idx_acesso_data ON acesso(data_hora);
CREATE INDEX idx_auditoria_data ON auditoria_acesso(data_hora_registro);





-- Cargos do sistema
INSERT INTO cargo (nome, nivel, is_chefia, descricao) VALUES
    ('Guarda I',          1, FALSE, 'Guarda iniciante, acesso básico'),
    ('Guarda II',         2, FALSE, 'Guarda intermediário'),
    ('Guarda III',        3, TRUE,  'Guarda sênior, pode chefiar equipe'),
    ('Enfermeiro',        2, FALSE, 'Profissional de enfermagem'),
    ('Médico',            3, FALSE, 'Médico plantonista'),
    ('Médico-Chefe',      4, TRUE,  'Chefe da ala de saúde'),
    ('Psicólogo',         2, FALSE, 'Atendimento psicológico'),
    ('Assistente Social', 2, FALSE, 'Acompanhamento social'),
    ('Coord. Reabilitação', 3, TRUE, 'Coordena programas de ressocialização'),
    ('Auxiliar Admin.',   1, FALSE, 'Apoio administrativo'),
    ('Chefe Admin.',      3, TRUE,  'Chefia o setor administrativo'),
    ('Subdiretor',        4, TRUE,  'Vice-diretor'),
    ('Diretor Geral',     5, TRUE,  'Autoridade máxima');

-- Departamentos
INSERT INTO departamento (nome, descricao) VALUES
    ('Diretoria',     'Direção geral da unidade'),
    ('Segurança',     'Custódia e vigilância'),
    ('Saúde',         'Atendimento médico'),
    ('Reabilitação',  'Programas de ressocialização'),
    ('Administração', 'Gestão e logística');

-- Funcionários
INSERT INTO funcionario (nome, cpf, matricula, id_cargo, id_departamento, turno, data_admissao, status, email, telefone) VALUES
    ('Roberto Carlos Mendes',    '111.222.333-01', 'DIR-001', 13, 1, 'Integral', '2015-03-15', 'ATIVO', 'roberto.mendes@pen.gov.br', '(61) 99999-0001'),
    ('Ana Paula Silveira',       '111.222.333-02', 'DIR-002', 12, 1, 'Integral', '2018-06-01', 'ATIVO', 'ana.silveira@pen.gov.br', '(61) 99999-0002'),
    ('João Silva Santos',        '222.333.444-01', 'SEG-001', 3, 2, 'Manhã',    '2016-02-10', 'ATIVO', 'joao.santos@pen.gov.br', '(61) 98888-0001'),
    ('Maria Oliveira Costa',     '222.333.444-02', 'SEG-002', 2, 2, 'Manhã',    '2019-08-20', 'ATIVO', 'maria.costa@pen.gov.br', '(61) 98888-0002'),
    ('Pedro Henrique Lima',      '222.333.444-03', 'SEG-003', 2, 2, 'Tarde',    '2020-01-15', 'ATIVO', 'pedro.lima@pen.gov.br', '(61) 98888-0003'),
    ('Carla Beatriz Rocha',      '222.333.444-04', 'SEG-004', 1, 2, 'Tarde',    '2022-03-01', 'ATIVO', 'carla.rocha@pen.gov.br', '(61) 98888-0004'),
    ('Fernando Alves Pereira',   '222.333.444-05', 'SEG-005', 1, 2, 'Noite',    '2023-05-10', 'ATIVO', 'fernando.pereira@pen.gov.br', '(61) 98888-0005'),
    ('Juliana Martins Souza',    '222.333.444-06', 'SEG-006', 3, 2, 'Noite',    '2017-11-25', 'ATIVO', 'juliana.souza@pen.gov.br', '(61) 98888-0006'),
    ('Dr. Carlos Eduardo Ramos', '333.444.555-01', 'SAU-001', 6, 3, 'Integral', '2014-07-01', 'ATIVO', 'carlos.ramos@pen.gov.br', '(61) 97777-0001'),
    ('Dra. Fernanda Gomes',      '333.444.555-02', 'SAU-002', 5, 3, 'Manhã',    '2019-02-15', 'ATIVO', 'fernanda.gomes@pen.gov.br', '(61) 97777-0002'),
    ('Patrícia Santos',          '333.444.555-03', 'SAU-003', 4, 3, 'Manhã',    '2020-09-01', 'ATIVO', 'patricia.santos@pen.gov.br', '(61) 97777-0003'),
    ('Ricardo Oliveira',         '333.444.555-04', 'SAU-004', 4, 3, 'Noite',    '2021-04-15', 'ATIVO', 'ricardo.enf@pen.gov.br', '(61) 97777-0004'),
    ('Dra. Márcia Psicóloga',    '444.555.666-01', 'REA-001', 9, 4, 'Integral', '2016-08-10', 'ATIVO', 'marcia.psi@pen.gov.br', '(61) 96666-0001'),
    ('Lucas Assistente Social',  '444.555.666-02', 'REA-002', 8, 4, 'Manhã',    '2020-11-20', 'ATIVO', 'lucas.social@pen.gov.br', '(61) 96666-0002'),
    ('Camila Psicóloga',         '444.555.666-03', 'REA-003', 7, 4, 'Tarde',    '2022-01-10', 'ATIVO', 'camila.psi@pen.gov.br', '(61) 96666-0003'),
    ('Sandra Chefe Admin.',      '555.666.777-01', 'ADM-001', 11, 5, 'Integral', '2017-05-05', 'ATIVO', 'sandra.admin@pen.gov.br', '(61) 95555-0001'),
    ('Bruno Auxiliar',           '555.666.777-02', 'ADM-002', 10, 5, 'Manhã',    '2021-08-15', 'ATIVO', 'bruno.aux@pen.gov.br', '(61) 95555-0002'),
    ('Daniela Auxiliar',         '555.666.777-03', 'ADM-003', 10, 5, 'Tarde',    '2023-02-01', 'FERIAS', 'daniela.aux@pen.gov.br', '(61) 95555-0003');

-- Define os chefes de cada departamento
UPDATE departamento SET id_chefe = 1  WHERE nome = 'Diretoria';
UPDATE departamento SET id_chefe = 3  WHERE nome = 'Segurança';
UPDATE departamento SET id_chefe = 9  WHERE nome = 'Saúde';
UPDATE departamento SET id_chefe = 13 WHERE nome = 'Reabilitação';
UPDATE departamento SET id_chefe = 16 WHERE nome = 'Administração';

-- Celas
INSERT INTO cela (numero, bloco, capacidade, ocupacao_atual, nivel_seguranca, tipo, id_departamento, ativa) VALUES
    ('A-101', 'A', 4, 3, 2, 'COMUM', 2, TRUE),
    ('A-102', 'A', 4, 4, 2, 'COMUM', 2, TRUE),
    ('A-103', 'A', 4, 2, 2, 'COMUM', 2, TRUE),
    ('A-104', 'A', 4, 0, 2, 'COMUM', 2, TRUE),
    ('B-201', 'B', 2, 2, 3, 'COMUM', 2, TRUE),
    ('B-202', 'B', 2, 1, 3, 'COMUM', 2, TRUE),
    ('B-203', 'B', 2, 2, 3, 'COMUM', 2, TRUE),
    ('C-301', 'C', 1, 1, 5, 'SEGURANCA_MAXIMA', 2, TRUE),
    ('C-302', 'C', 1, 1, 5, 'SEGURANCA_MAXIMA', 2, TRUE),
    ('C-303', 'C', 1, 0, 5, 'SEGURANCA_MAXIMA', 2, TRUE),
    ('D-401', 'D', 1, 1, 4, 'ISOLAMENTO', 2, TRUE),
    ('D-402', 'D', 1, 0, 4, 'ISOLAMENTO', 2, TRUE),
    ('E-501', 'E', 3, 1, 2, 'ENFERMARIA', 3, TRUE),
    ('E-502', 'E', 3, 0, 2, 'ENFERMARIA', 3, TRUE),
    ('F-601', 'F', 6, 3, 1, 'PROVISORIA', 2, TRUE);

-- Detentos (ocupacao_atual já definida nas celas pra bater com os dados)
INSERT INTO detento (nome, cpf, data_nascimento, data_entrada, data_saida, status, nivel_periculosidade, id_cela, regime, observacoes) VALUES
    ('Marcos Vinícius Ferreira',  '666.777.888-01', '1985-03-15', '2022-06-10', NULL, 'ATIVO', 2, 1, 'FECHADO', 'Bom comportamento'),
    ('André Luiz Moreira',        '666.777.888-02', '1990-07-22', '2021-11-05', NULL, 'ATIVO', 2, 1, 'FECHADO', 'Aguardando progressão'),
    ('José Carlos Nunes',         '666.777.888-03', '1978-12-01', '2020-03-18', NULL, 'ATIVO', 1, 1, 'SEMIABERTO', 'Trabalha na cozinha'),
    ('Paulo Roberto Silva',       '666.777.888-04', '1988-09-10', '2023-01-20', NULL, 'ATIVO', 2, 2, 'FECHADO', NULL),
    ('Thiago Mendes Santos',      '666.777.888-05', '1995-04-05', '2023-03-15', NULL, 'ATIVO', 2, 2, 'FECHADO', NULL),
    ('Rafael Oliveira Lima',      '666.777.888-06', '1982-06-30', '2022-08-25', NULL, 'ATIVO', 2, 2, 'FECHADO', 'Clube de leitura'),
    ('Lucas Pereira Costa',       '666.777.888-07', '1992-01-18', '2022-12-01', NULL, 'ATIVO', 3, 2, 'FECHADO', 'Histórico de brigas'),
    ('Diego Almeida Souza',       '666.777.888-08', '1987-11-25', '2021-07-10', NULL, 'ATIVO', 1, 3, 'SEMIABERTO', 'Trabalha na horta'),
    ('Bruno Henrique Ramos',      '666.777.888-09', '1993-08-14', '2023-05-20', NULL, 'ATIVO', 2, 3, 'FECHADO', NULL),
    ('Ricardo Gomes Dias',        '666.777.888-10', '1980-02-28', '2019-09-15', NULL, 'ATIVO', 3, 5, 'FECHADO', 'Liderança entre detentos'),
    ('Fábio Martins Rocha',       '666.777.888-11', '1975-05-20', '2018-04-10', NULL, 'ATIVO', 3, 5, 'FECHADO', 'Reincidente'),
    ('Eduardo Santos Filho',      '666.777.888-12', '1983-10-08', '2022-02-28', NULL, 'ATIVO', 3, 6, 'FECHADO', NULL),
    ('Marcelo Ribeiro Alves',     '666.777.888-13', '1991-12-12', '2021-06-05', NULL, 'ATIVO', 3, 7, 'FECHADO', 'Envolvido em facção'),
    ('Gustavo Lima Pereira',      '666.777.888-14', '1986-07-03', '2020-10-20', NULL, 'ATIVO', 3, 7, 'FECHADO', NULL),
    ('Roberto Carlos Jr.',        '666.777.888-15', '1970-04-15', '2015-01-10', NULL, 'ATIVO', 5, 8, 'FECHADO', 'Líder de organização'),
    ('Antônio José Pereira',      '666.777.888-16', '1968-09-22', '2016-08-05', NULL, 'ATIVO', 5, 9, 'FECHADO', 'Crimes hediondos'),
    ('Felipe Augusto Ramos',      '666.777.888-17', '1994-03-30', '2023-04-01', NULL, 'ISOLAMENTO', 4, 11, 'FECHADO', 'Tentativa de fuga'),
    ('João Pedro Nascimento',     '666.777.888-18', '1989-06-18', '2022-05-15', NULL, 'ENFERMARIA', 2, 13, 'FECHADO', 'Tratamento TB'),
    ('Alexandre Moura Santos',    '666.777.888-19', '1997-02-14', '2024-01-05', NULL, 'ATIVO', 2, 15, 'FECHADO', 'Aguardando julgamento'),
    ('Vinícius Costa Oliveira',   '666.777.888-20', '1999-08-28', '2024-01-10', NULL, 'ATIVO', 1, 15, 'FECHADO', 'Primeira passagem'),
    ('Leonardo Souza Pinto',      '666.777.888-21', '1996-11-05', '2024-01-12', NULL, 'ATIVO', 2, 15, 'FECHADO', 'Aguarda transferência'),
    ('Carlos Alberto Reis',       '666.777.888-22', '1972-01-20', '2018-03-10', '2023-03-10', 'LIBERADO', 2, NULL, 'FECHADO', 'Pena cumprida'),
    ('Sérgio Matos Lima',         '666.777.888-23', '1980-09-15', '2019-07-20', '2023-12-01', 'LIBERADO', 1, NULL, 'SEMIABERTO', 'Progressão concluída');

-- Acessos de exemplo
INSERT INTO acesso (id_funcionario, id_cela, id_detento, data_hora, tipo, status, observacao) VALUES
    (3,  1,  NULL, '2024-01-15 08:00:00', 'PATRULHA', 'APROVADO', 'Ronda matinal Bloco A'),
    (4,  2,  NULL, '2024-01-15 08:15:00', 'PATRULHA', 'APROVADO', 'Ronda matinal Bloco A'),
    (5,  5,  NULL, '2024-01-15 14:00:00', 'PATRULHA', 'APROVADO', 'Ronda vespertina Bloco B'),
    (8,  8,  NULL, '2024-01-15 22:00:00', 'PATRULHA', 'APROVADO', 'Ronda noturna seg. máxima'),
    (10, 13, 18, '2024-01-14 10:00:00', 'ATENDIMENTO_MEDICO', 'APROVADO', 'Consulta TB'),
    (11, 13, 18, '2024-01-15 09:30:00', 'ATENDIMENTO_MEDICO', 'APROVADO', 'Medicação'),
    (9,  5,  10, '2024-01-15 11:00:00', 'ATENDIMENTO_MEDICO', 'APROVADO', 'Detento com queixas'),
    (13, 1,  1,  '2024-01-15 14:00:00', 'VISITA_TECNICA', 'APROVADO', 'Acompanhamento psicológico'),
    (14, 1,  3,  '2024-01-15 15:00:00', 'VISITA_TECNICA', 'APROVADO', 'Avaliação progressão'),
    (3,  11, 17, '2024-01-10 09:00:00', 'TRANSFERENCIA', 'APROVADO', 'Enviado para isolamento'),
    (8,  13, 18, '2024-01-12 08:00:00', 'TRANSFERENCIA', 'APROVADO', 'Internação enfermaria'),
    (3,  8,  15, '2024-01-08 10:00:00', 'ESCOLTA', 'APROVADO', 'Audiência no fórum'),
    (4,  2,  NULL, '2024-01-14 06:00:00', 'REVISTA', 'APROVADO', 'Revista geral'),
    (6,  8,  NULL, '2024-01-15 15:00:00', 'PATRULHA', 'NEGADO', 'Guarda I sem acesso Bloco C'),
    (7,  9,  16, '2024-01-15 20:00:00', 'ATENDIMENTO_MEDICO', 'NEGADO', 'Guarda não faz atendimento');





-- Function
CREATE OR REPLACE FUNCTION fn_verificar_permissao_acesso(
    p_id_funcionario INTEGER,
    p_id_cela INTEGER
)
RETURNS TABLE (
    permitido      BOOLEAN,
    motivo         TEXT,
    nivel_funcionario  INTEGER,
    nivel_cela     INTEGER,
    nome_funcionario   VARCHAR,
    info_cela      VARCHAR
)
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

-- Procedure
CREATE OR REPLACE PROCEDURE sp_registrar_movimentacao_detento(
    IN p_id_funcionario   INTEGER,
    IN p_id_detento       INTEGER,
    IN p_id_cela_destino  INTEGER,
    IN p_tipo_movimentacao VARCHAR(30),
    IN p_observacao       TEXT DEFAULT NULL
)
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


-- TRIGGER 1: Controle de lotação
CREATE FUNCTION fn_trigger_lotacao_cela()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
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

CREATE TRIGGER trg_validar_lotacao_cela
    BEFORE INSERT OR UPDATE OR DELETE ON detento
    FOR EACH ROW EXECUTE FUNCTION fn_trigger_lotacao_cela();


-- TRIGGER 2: Auditoria de acessos

CREATE OR REPLACE FUNCTION fn_trigger_auditoria_acesso()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
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

CREATE TRIGGER trg_auditoria_acesso
    AFTER INSERT OR UPDATE OR DELETE ON acesso
    FOR EACH ROW EXECUTE FUNCTION fn_trigger_auditoria_acesso();





--ROLES E PERMISSÕES

DROP ROLE IF EXISTS guilherme_alves;
DROP ROLE IF EXISTS carlos_eduardo;
DROP ROLE IF EXISTS luan_ayres;
DROP ROLE IF EXISTS professor;

-- Membros do grupo
CREATE ROLE guilherme_alves WITH LOGIN PASSWORD 'guilhermegostade_churros';
CREATE ROLE carlos_eduardo WITH LOGIN PASSWORD 'carlosgostade_bolo';
CREATE ROLE luan_ayres WITH LOGIN PASSWORD 'luangostade_miojo';

-- Professor (SENHA: professorgostade_provas)
CREATE ROLE professor WITH LOGIN PASSWORD 'professorgostade_provas';


GRANT USAGE ON SCHEMA prisional TO guilherme_alves, carlos_eduardo, luan_ayres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA prisional TO guilherme_alves, carlos_eduardo, luan_ayres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA prisional TO guilherme_alves, carlos_eduardo, luan_ayres;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA prisional TO guilherme_alves, carlos_eduardo, luan_ayres;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA prisional TO guilherme_alves, carlos_eduardo, luan_ayres;


GRANT USAGE ON SCHEMA prisional TO professor;


GRANT SELECT ON ALL TABLES IN SCHEMA prisional TO professor;


GRANT INSERT, UPDATE ON funcionario, detento, cela, acesso, auditoria_acesso, cargo, departamento TO professor;


GRANT USAGE ON ALL SEQUENCES IN SCHEMA prisional TO professor;


GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA prisional TO professor;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA prisional TO professor;