-- Caderno de Gastos — schema inicial para Supabase
-- Executar no SQL Editor do Supabase (Database → SQL Editor → New query)

-- =====================================================================
-- TABELAS
-- =====================================================================

CREATE TABLE IF NOT EXISTS viagens (
  id              TEXT PRIMARY KEY,
  nome            TEXT NOT NULL,
  inicio          DATE,
  fim             DATE,
  orcamento_debito   NUMERIC(12, 2) NOT NULL DEFAULT 0,
  orcamento_credito  NUMERIC(12, 2) NOT NULL DEFAULT 0,
  arquivada       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS gastos (
  id              TEXT PRIMARY KEY,
  viagem_id       TEXT REFERENCES viagens(id) ON DELETE SET NULL,
  scope           TEXT NOT NULL DEFAULT 'viagem',  -- 'viagem' | 'pessoal'
  data            TIMESTAMPTZ NOT NULL,
  data_gasto      DATE NOT NULL,
  local           TEXT NOT NULL DEFAULT '',
  item            TEXT NOT NULL DEFAULT '',
  estabelecimento TEXT,
  maps_link       TEXT,
  gps             TEXT,
  valor           NUMERIC(12, 2) NOT NULL DEFAULT 0,
  tipo            TEXT NOT NULL DEFAULT 'debito',  -- 'debito' | 'credito'
  categoria       TEXT NOT NULL DEFAULT 'outros',
  status_remocao  TEXT NOT NULL DEFAULT '',        -- '' | 'pendente' | 'aprovado'
  solicitado_por  TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ajustes (
  id              TEXT PRIMARY KEY,
  data            TIMESTAMPTZ NOT NULL,
  tipo            TEXT NOT NULL,  -- 'debito' | 'credito'
  valor_antes     NUMERIC(12, 2) NOT NULL DEFAULT 0,
  valor_depois    NUMERIC(12, 2) NOT NULL DEFAULT 0,
  motivo          TEXT NOT NULL DEFAULT '',
  por             TEXT NOT NULL DEFAULT '',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================================
-- ÍNDICES
-- =====================================================================

CREATE INDEX IF NOT EXISTS gastos_viagem_id_idx  ON gastos (viagem_id);
CREATE INDEX IF NOT EXISTS gastos_data_gasto_idx ON gastos (data_gasto);
CREATE INDEX IF NOT EXISTS gastos_tipo_idx       ON gastos (tipo);
CREATE INDEX IF NOT EXISTS ajustes_data_idx      ON ajustes (data);

-- =====================================================================
-- ROW LEVEL SECURITY
-- Todos os usuários autenticados têm acesso completo — app compartilhado
-- =====================================================================

ALTER TABLE viagens ENABLE ROW LEVEL SECURITY;
ALTER TABLE gastos  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ajustes ENABLE ROW LEVEL SECURITY;

-- Viagens
CREATE POLICY "Authenticated users can read viagens"
  ON viagens FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert viagens"
  ON viagens FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can update viagens"
  ON viagens FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can delete viagens"
  ON viagens FOR DELETE TO authenticated USING (true);

-- Gastos
CREATE POLICY "Authenticated users can read gastos"
  ON gastos FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert gastos"
  ON gastos FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can update gastos"
  ON gastos FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can delete gastos"
  ON gastos FOR DELETE TO authenticated USING (true);

-- Ajustes
CREATE POLICY "Authenticated users can read ajustes"
  ON ajustes FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert ajustes"
  ON ajustes FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can update ajustes"
  ON ajustes FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Authenticated users can delete ajustes"
  ON ajustes FOR DELETE TO authenticated USING (true);

-- =====================================================================
-- REALTIME
-- Habilita publicação de mudanças para o Supabase Realtime
-- =====================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE viagens;
ALTER PUBLICATION supabase_realtime ADD TABLE gastos;
ALTER PUBLICATION supabase_realtime ADD TABLE ajustes;
