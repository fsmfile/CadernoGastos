ALTER TABLE carteiras
  ADD COLUMN IF NOT EXISTS tipo TEXT NOT NULL DEFAULT 'viagem'
  CHECK (tipo IN ('viagem', 'comum'));