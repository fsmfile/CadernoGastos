-- Caderno de Gastos — migração 003: corrige políticas RLS
-- Executar no SQL Editor do Supabase APÓS a migração 002

-- Fix 1: carteiras SELECT
-- Problema: INSERT + .select() falha porque o usuário ainda não está em
-- carteira_membros quando o PostgREST faz o RETURNING *.
-- Solução: owner também pode ler sua própria carteira.
DROP POLICY IF EXISTS "Members read carteiras" ON carteiras;
CREATE POLICY "Members or owner read carteiras"
  ON carteiras FOR SELECT TO authenticated
  USING (id IN (SELECT auth_carteiras()) OR owner_id = auth.uid());

-- Fix 2: carteira_convites SELECT
-- Problema: `SELECT email FROM auth.users` falha — o role `authenticated`
-- não tem acesso direto à tabela auth.users.
-- Solução: usar auth.email() que o Supabase expõe para esse fim.
DROP POLICY IF EXISTS "Owner or invited reads convites" ON carteira_convites;
CREATE POLICY "Owner or invited reads convites"
  ON carteira_convites FOR SELECT TO authenticated
  USING (
    carteira_id IN (SELECT id FROM carteiras WHERE owner_id = auth.uid())
    OR lower(email) = lower(auth.email())
  );
