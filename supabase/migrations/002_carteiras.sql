-- Caderno de Gastos — migração 002: sistema de Carteiras (multi-tenant)
-- Executar no SQL Editor do Supabase APÓS a migração 001

-- =====================================================================
-- NOVAS TABELAS
-- =====================================================================

-- Carteira = grupo compartilhado de usuários (ex: "Família Matos")
CREATE TABLE IF NOT EXISTS carteiras (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome       TEXT NOT NULL,
  owner_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  criada_em  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Membros de cada carteira (N:N usuários ↔ carteiras)
CREATE TABLE IF NOT EXISTS carteira_membros (
  carteira_id  UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nome_exibicao TEXT,
  criada_em    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (carteira_id, user_id)
);

-- Convites pendentes por e-mail
CREATE TABLE IF NOT EXISTS carteira_convites (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  carteira_id   UUID NOT NULL REFERENCES carteiras(id) ON DELETE CASCADE,
  email         TEXT NOT NULL,
  convidado_por UUID REFERENCES auth.users(id),
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  aceito_em     TIMESTAMPTZ
);

-- =====================================================================
-- ADICIONAR carteira_id NAS TABELAS EXISTENTES
-- =====================================================================

ALTER TABLE viagens ADD COLUMN IF NOT EXISTS carteira_id UUID REFERENCES carteiras(id) ON DELETE CASCADE;
ALTER TABLE gastos  ADD COLUMN IF NOT EXISTS carteira_id UUID REFERENCES carteiras(id) ON DELETE CASCADE;
ALTER TABLE ajustes ADD COLUMN IF NOT EXISTS carteira_id UUID REFERENCES carteiras(id) ON DELETE CASCADE;

-- =====================================================================
-- ÍNDICES
-- =====================================================================

CREATE INDEX IF NOT EXISTS viagens_carteira_id_idx       ON viagens (carteira_id);
CREATE INDEX IF NOT EXISTS gastos_carteira_id_idx        ON gastos  (carteira_id);
CREATE INDEX IF NOT EXISTS ajustes_carteira_id_idx       ON ajustes (carteira_id);
CREATE INDEX IF NOT EXISTS carteira_membros_user_id_idx  ON carteira_membros (user_id);
CREATE INDEX IF NOT EXISTS carteira_convites_email_idx   ON carteira_convites (lower(email));

-- =====================================================================
-- FUNÇÃO HELPER — carteiras acessíveis pelo usuário atual
-- =====================================================================

CREATE OR REPLACE FUNCTION auth_carteiras()
RETURNS SETOF UUID
LANGUAGE SQL STABLE SECURITY DEFINER
AS $$
  SELECT carteira_id FROM carteira_membros WHERE user_id = auth.uid()
$$;

-- =====================================================================
-- RLS — NOVAS TABELAS
-- =====================================================================

ALTER TABLE carteiras          ENABLE ROW LEVEL SECURITY;
ALTER TABLE carteira_membros   ENABLE ROW LEVEL SECURITY;
ALTER TABLE carteira_convites  ENABLE ROW LEVEL SECURITY;

-- carteiras
CREATE POLICY "Members read carteiras"
  ON carteiras FOR SELECT TO authenticated
  USING (id IN (SELECT auth_carteiras()));

CREATE POLICY "Any auth can create carteira"
  ON carteiras FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Owners update carteira"
  ON carteiras FOR UPDATE TO authenticated
  USING (owner_id = auth.uid());

CREATE POLICY "Owners delete carteira"
  ON carteiras FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- carteira_membros
CREATE POLICY "Members see members"
  ON carteira_membros FOR SELECT TO authenticated
  USING (carteira_id IN (SELECT auth_carteiras()));

CREATE POLICY "User inserts themselves"
  ON carteira_membros FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Owner removes members"
  ON carteira_membros FOR DELETE TO authenticated
  USING (carteira_id IN (SELECT id FROM carteiras WHERE owner_id = auth.uid())
      OR user_id = auth.uid());

-- carteira_convites
CREATE POLICY "Owner or invited reads convites"
  ON carteira_convites FOR SELECT TO authenticated
  USING (
    carteira_id IN (SELECT id FROM carteiras WHERE owner_id = auth.uid())
    OR lower(email) = lower((SELECT email FROM auth.users WHERE id = auth.uid()))
  );

CREATE POLICY "Owner creates convites"
  ON carteira_convites FOR INSERT TO authenticated
  WITH CHECK (carteira_id IN (SELECT id FROM carteiras WHERE owner_id = auth.uid()));

CREATE POLICY "Invited accepts convite"
  ON carteira_convites FOR UPDATE TO authenticated
  USING (lower(email) = lower((SELECT email FROM auth.users WHERE id = auth.uid())));

-- =====================================================================
-- ATUALIZAR RLS DAS TABELAS EXISTENTES (escopo por carteira)
-- =====================================================================

-- Remove políticas abertas da migração 001
DROP POLICY IF EXISTS "Authenticated users can read viagens"   ON viagens;
DROP POLICY IF EXISTS "Authenticated users can insert viagens" ON viagens;
DROP POLICY IF EXISTS "Authenticated users can update viagens" ON viagens;
DROP POLICY IF EXISTS "Authenticated users can delete viagens" ON viagens;

DROP POLICY IF EXISTS "Authenticated users can read gastos"   ON gastos;
DROP POLICY IF EXISTS "Authenticated users can insert gastos" ON gastos;
DROP POLICY IF EXISTS "Authenticated users can update gastos" ON gastos;
DROP POLICY IF EXISTS "Authenticated users can delete gastos" ON gastos;

DROP POLICY IF EXISTS "Authenticated users can read ajustes"   ON ajustes;
DROP POLICY IF EXISTS "Authenticated users can insert ajustes" ON ajustes;
DROP POLICY IF EXISTS "Authenticated users can update ajustes" ON ajustes;
DROP POLICY IF EXISTS "Authenticated users can delete ajustes" ON ajustes;

-- Novas políticas com escopo de carteira
CREATE POLICY "Members access viagens"
  ON viagens FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

CREATE POLICY "Members access gastos"
  ON gastos FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

CREATE POLICY "Members access ajustes"
  ON ajustes FOR ALL TO authenticated
  USING    (carteira_id IN (SELECT auth_carteiras()))
  WITH CHECK (carteira_id IN (SELECT auth_carteiras()));

-- =====================================================================
-- REALTIME para as novas tabelas
-- =====================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE carteiras;
ALTER PUBLICATION supabase_realtime ADD TABLE carteira_membros;
