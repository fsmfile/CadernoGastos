-- Caderno de Gastos — migração 006: garante colunas tipo e parent_id + fix UPDATE
-- Executar no SQL Editor do Supabase
--
-- Corrige:
-- 1. Coluna 'tipo' (adicionada em 004, idempotente)
-- 2. Coluna 'parent_id' (adicionada em 1.9.2 sem migration, idempotente)
-- 3. Política UPDATE com WITH CHECK explícito para UPDATE+RETURNING funcionar

-- 1. Coluna tipo
ALTER TABLE carteiras
  ADD COLUMN IF NOT EXISTS tipo TEXT NOT NULL DEFAULT 'viagem'
  CHECK (tipo IN ('viagem', 'comum'));

-- 2. Coluna parent_id (sub-carteiras)
ALTER TABLE carteiras
  ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES carteiras(id) ON DELETE SET NULL;

-- 3. Recria política de UPDATE com WITH CHECK explícito
DROP POLICY IF EXISTS "Owners update carteira" ON carteiras;

CREATE POLICY "Owners update carteira"
  ON carteiras FOR UPDATE TO authenticated
  USING    (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());
