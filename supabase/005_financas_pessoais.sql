-- Caderno de Gastos — migração 005: Módulo de Finanças Pessoais
-- Executar no SQL Editor do Supabase APÓS a migração 004

-- =====================================================================
-- TABELA: lancamentos_financeiros
-- Representa todas as linhas da planilha (entradas e saídas)
-- =====================================================================
CREATE TABLE IF NOT EXISTS lancamentos_financeiros (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carteira_id     UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  descricao       TEXT NOT NULL,
  tipo            TEXT NOT NULL CHECK (tipo IN ('entrada', 'saida')),
  categoria       TEXT NOT NULL DEFAULT 'outros',
  recorrencia     TEXT NOT NULL DEFAULT 'fixo'
                  CHECK (recorrencia IN ('fixo', 'variavel', 'unico', 'parcelado')),
  valor_padrao    NUMERIC(12, 2) NOT NULL DEFAULT 0,
  parcelas_total  INT,
  parcela_atual   INT,
  mes_inicio      INT NOT NULL DEFAULT 1,
  ano_inicio      INT NOT NULL,
  mes_fim         INT,
  ano_fim         INT,
  ordem           INT NOT NULL DEFAULT 0,
  ativo           BOOLEAN NOT NULL DEFAULT TRUE,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- TABELA: lancamento_valores_mes
-- Valor real de cada lançamento em cada mês/ano
-- =====================================================================
CREATE TABLE IF NOT EXISTS lancamento_valores_mes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lancamento_id UUID NOT NULL REFERENCES lancamentos_financeiros(id) ON DELETE CASCADE,
  mes           INT NOT NULL CHECK (mes BETWEEN 1 AND 12),
  ano           INT NOT NULL,
  valor         NUMERIC(12, 2) NOT NULL DEFAULT 0,
  observacao    TEXT,
  realizado     BOOLEAN NOT NULL DEFAULT FALSE,
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(lancamento_id, mes, ano)
);

-- =====================================================================
-- TABELA: saldo_inicial
-- Saldo da conta no início de cada ano
-- =====================================================================
CREATE TABLE IF NOT EXISTS saldo_inicial (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carteira_id UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  mes         INT NOT NULL CHECK (mes BETWEEN 1 AND 12),
  ano         INT NOT NULL,
  valor       NUMERIC(12, 2) NOT NULL DEFAULT 0,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(carteira_id, mes, ano)
);

-- =====================================================================
-- TABELA: config_financeira
-- Configurações gerais (cheque especial, etc.)
-- =====================================================================
CREATE TABLE IF NOT EXISTS config_financeira (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carteira_id UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  chave       TEXT NOT NULL,
  valor       TEXT NOT NULL,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(carteira_id, chave)
);

-- =====================================================================
-- ÍNDICES
-- =====================================================================
CREATE INDEX IF NOT EXISTS idx_lanc_carteira    ON lancamentos_financeiros(carteira_id);
CREATE INDEX IF NOT EXISTS idx_lanc_tipo        ON lancamentos_financeiros(tipo);
CREATE INDEX IF NOT EXISTS idx_lanc_ativo       ON lancamentos_financeiros(ativo);
CREATE INDEX IF NOT EXISTS idx_valmes_lancamento ON lancamento_valores_mes(lancamento_id);
CREATE INDEX IF NOT EXISTS idx_valmes_periodo   ON lancamento_valores_mes(ano, mes);
CREATE INDEX IF NOT EXISTS idx_saldo_carteira   ON saldo_inicial(carteira_id, ano, mes);

-- =====================================================================
-- RLS
-- =====================================================================
ALTER TABLE lancamentos_financeiros ENABLE ROW LEVEL SECURITY;
ALTER TABLE lancamento_valores_mes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE saldo_inicial           ENABLE ROW LEVEL SECURITY;
ALTER TABLE config_financeira       ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members access lancamentos"
  ON lancamentos_financeiros FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

CREATE POLICY "Members access valores_mes"
  ON lancamento_valores_mes FOR ALL TO authenticated
  USING (lancamento_id IN (
    SELECT id FROM lancamentos_financeiros
    WHERE carteira_id IN (SELECT auth_carteiras())
  ))
  WITH CHECK (lancamento_id IN (
    SELECT id FROM lancamentos_financeiros
    WHERE carteira_id IN (SELECT auth_carteiras())
  ));

CREATE POLICY "Members access saldo_inicial"
  ON saldo_inicial FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

CREATE POLICY "Members access config_financeira"
  ON config_financeira FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

-- =====================================================================
-- REALTIME
-- =====================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE lancamentos_financeiros;
ALTER PUBLICATION supabase_realtime ADD TABLE lancamento_valores_mes;
ALTER PUBLICATION supabase_realtime ADD TABLE saldo_inicial;
