-- ============================================================================
-- corrige_delecao_FGTS01_token.sql        (LOCAL apenas — 127.0.0.1:5432/engine)
-- ----------------------------------------------------------------------------
-- Conserta a delecao com escopo invertido:
--   ANTES (errado): apaguei os ANTERIORES (<= 11-14) da serie, menos o seed.
--   CERTO (intencao): manter os anteriores (ate o pre-amort 11-14 00:00) e apagar
--                     DO EVENTO DE AMORTIZACAO EM DIANTE (> 11-14 00:00).
--
-- Acoes:
--   (1) restaura na serie CR-FGTS-01-01-SINGLE (id 20450) os anteriores (<= 11-14 00:00)
--       a partir do backup (o evento de amort 11-14 09:00 NAO e' restaurado).
--   (2) apaga > 11-14 00:00 na serie (20450) E no token NXFGTSJ34-1 (20451)
--       -> remove o evento de amort 11-14 09:00 + tudo de 11-15 em diante.
--   Mantem em ambos o pre-amort 11-14 00:00 (seed).
--
-- DRY-RUN: roda em BEGIN ... ROLLBACK. Trocar ROLLBACK por COMMIT p/ aplicar.
-- Rodar com cwd = pasta corrigir_amortizacao_token (o \copy usa caminho relativo).
-- ============================================================================

BEGIN;

-- (1) restaura os anteriores da serie a partir do backup
CREATE TEMP TABLE _r AS SELECT * FROM valuations WHERE false;
\copy _r FROM 'backup_valuations_FGTS01_ate_1114.csv' CSV HEADER

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _r;
  IF n <> 151 THEN RAISE EXCEPTION 'backup _r = % linhas (esperado 151)', n; END IF;
END $$;

INSERT INTO valuations
SELECT * FROM _r
WHERE date <= timestamptz '2025-11-14 00:00:00-03'
  AND id NOT IN (SELECT id FROM valuations WHERE asset_id = 20450);

-- (2) apaga do evento de amortizacao em diante (> 11-14 00:00) na serie e no token
DELETE FROM valuations WHERE asset_id = 20450 AND date > timestamptz '2025-11-14 00:00:00-03';
DELETE FROM valuations WHERE asset_id = 20451 AND date > timestamptz '2025-11-14 00:00:00-03';

-- (3) GUARDA: estado final esperado = 150 linhas em cada, max(date) = 11-14 00:00
DO $$
DECLARE ns int; nt int; ms timestamptz; mt timestamptz;
BEGIN
  SELECT count(*), max(date) INTO ns, ms FROM valuations WHERE asset_id = 20450;
  SELECT count(*), max(date) INTO nt, mt FROM valuations WHERE asset_id = 20451;
  IF ns <> 150 THEN RAISE EXCEPTION 'serie final = % (esperado 150)', ns; END IF;
  IF nt <> 150 THEN RAISE EXCEPTION 'token final = % (esperado 150)', nt; END IF;
  IF ms <> timestamptz '2025-11-14 00:00:00-03' THEN RAISE EXCEPTION 'serie max(date) = % (esperado 11-14 00:00)', ms; END IF;
  IF mt <> timestamptz '2025-11-14 00:00:00-03' THEN RAISE EXCEPTION 'token max(date) = % (esperado 11-14 00:00)', mt; END IF;
END $$;

-- (4) preview do estado final
SELECT 'serie 20450' AS o, count(*) AS n, min(date) AS menor, max(date) AS maior FROM valuations WHERE asset_id = 20450;
SELECT 'token 20451' AS o, count(*) AS n, min(date) AS menor, max(date) AS maior FROM valuations WHERE asset_id = 20451;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
