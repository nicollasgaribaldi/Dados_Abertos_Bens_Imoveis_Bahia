-- =====================================================================
-- DW Bens Imóveis da Bahia: schemas e tabelas (PostgreSQL 16)
-- Executado automaticamente na primeira subida do contêiner
-- (docker-entrypoint-initdb.d) ou manualmente:
--   psql -h localhost -p 5437 -U postgres -d dw_bens_imoveis -f sql/ddl/01_schemas_e_tabelas.sql
-- Idempotente: pode rodar de novo sem erro.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS stg;   -- staging: espelho tipado e padronizado da fonte
CREATE SCHEMA IF NOT EXISTS dw;    -- modelo dimensional (estrela)

-- ---------------------------------------------------------------------
-- STAGING: 1 linha por registro do arquivo (imóvel x exercício)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stg.bens_imoveis (
    numero_patrimonio  INTEGER        NOT NULL,
    exercicio          INTEGER        NOT NULL,
    endereco           VARCHAR(300),
    municipio          VARCHAR(100)   NOT NULL,
    orgao_gestor       VARCHAR(150)   NOT NULL,
    destino            VARCHAR(50)    NOT NULL,
    valor              NUMERIC(18,2),
    dimensoes          NUMERIC(16,2),
    dt_carga           TIMESTAMP      NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- DIMENSÕES (chave substituta sk_* + chave natural única)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.dim_tempo (
    sk_tempo           SERIAL         PRIMARY KEY,
    ano                INTEGER        NOT NULL UNIQUE,
    decada             VARCHAR(10)    NOT NULL,   -- ex.: 1990s
    periodo_monetario  VARCHAR(20)    NOT NULL,   -- 'Pré-Real' (1992-1993) ou 'Real'
    fl_moeda_pre_real  BOOLEAN        NOT NULL,
    fl_ultimo_ano      BOOLEAN        NOT NULL    -- exercício mais recente da carga
);

CREATE TABLE IF NOT EXISTS dw.dim_imovel (
    sk_imovel          SERIAL         PRIMARY KEY,
    numero_patrimonio  INTEGER        NOT NULL UNIQUE,
    endereco           VARCHAR(300),              -- endereço do exercício mais recente
    area_m2_atual      NUMERIC(16,2),             -- área do exercício mais recente
    primeiro_exercicio INTEGER        NOT NULL,
    ultimo_exercicio   INTEGER        NOT NULL,
    fl_ativo_ultimo_ano BOOLEAN       NOT NULL    -- aparece no exercício mais recente?
);

CREATE TABLE IF NOT EXISTS dw.dim_municipio (
    sk_municipio       SERIAL         PRIMARY KEY,
    municipio          VARCHAR(100)   NOT NULL UNIQUE,
    uf                 CHAR(2)        NOT NULL DEFAULT 'BA',
    localizacao_mapa   VARCHAR(120)   NOT NULL,   -- "MUNICÍPIO, Bahia, Brasil" para o mapa do Power BI
    fl_capital         BOOLEAN        NOT NULL,
    fl_regiao_metropolitana BOOLEAN   NOT NULL    -- Região Metropolitana de Salvador (RMS)
);

CREATE TABLE IF NOT EXISTS dw.dim_orgao (
    sk_orgao           SERIAL         PRIMARY KEY,
    orgao_gestor       VARCHAR(150)   NOT NULL UNIQUE,
    area_governo       VARCHAR(40)    NOT NULL    -- agrupamento para análise
);

CREATE TABLE IF NOT EXISTS dw.dim_destino (
    sk_destino         SERIAL         PRIMARY KEY,
    destino            VARCHAR(50)    NOT NULL UNIQUE,
    grupo_destino      VARCHAR(30)    NOT NULL    -- Sem destinação / Em uso / Alienação e receita
);

-- ---------------------------------------------------------------------
-- FATO: snapshot periódico anual
-- Grão: 1 imóvel em 1 exercício. "valor" é SEMIADITIVO:
-- soma entre imóveis no mesmo ano, nunca entre anos.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dw.fato_patrimonio_anual (
    sk_imovel          INTEGER        NOT NULL REFERENCES dw.dim_imovel,
    sk_tempo           INTEGER        NOT NULL REFERENCES dw.dim_tempo,
    sk_municipio       INTEGER        NOT NULL REFERENCES dw.dim_municipio,
    sk_orgao           INTEGER        NOT NULL REFERENCES dw.dim_orgao,
    sk_destino         INTEGER        NOT NULL REFERENCES dw.dim_destino,
    valor              NUMERIC(18,2),
    area_m2            NUMERIC(16,2),
    fl_valor_invalido  BOOLEAN        NOT NULL,   -- valor <= 0
    fl_area_invalida   BOOLEAN        NOT NULL,   -- área nula ou <= 0
    CONSTRAINT pk_fato_patrimonio_anual PRIMARY KEY (sk_imovel, sk_tempo)
);

CREATE INDEX IF NOT EXISTS ix_fato_tempo     ON dw.fato_patrimonio_anual (sk_tempo);
CREATE INDEX IF NOT EXISTS ix_fato_municipio ON dw.fato_patrimonio_anual (sk_municipio);
CREATE INDEX IF NOT EXISTS ix_fato_orgao     ON dw.fato_patrimonio_anual (sk_orgao);
CREATE INDEX IF NOT EXISTS ix_fato_destino   ON dw.fato_patrimonio_anual (sk_destino);
