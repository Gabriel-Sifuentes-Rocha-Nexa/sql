-- Linha completa do token e da série a partir do id 1400752.
-- 1400752 pode ser o id do token OU o id da série — resolve o par pelo
-- issuer_id em comum (token espelha a série; ligam pela mãe = issuer_id).
-- tokens.id e securitization_series.id são ambos FK → entities.id.

-- ── Série (securitization_series) ──────────────────────────────
SELECT s.*
FROM securitization_series s
WHERE s.issuer_id IN (
  SELECT issuer_id FROM tokens                WHERE id = 1400752
  UNION
  SELECT issuer_id FROM securitization_series WHERE id = 1400752
);

-- ── Token (tokens) ─────────────────────────────────────────────
SELECT t.*
FROM tokens t
WHERE t.issuer_id IN (
  SELECT issuer_id FROM tokens                WHERE id = 1400752
  UNION
  SELECT issuer_id FROM securitization_series WHERE id = 1400752
);