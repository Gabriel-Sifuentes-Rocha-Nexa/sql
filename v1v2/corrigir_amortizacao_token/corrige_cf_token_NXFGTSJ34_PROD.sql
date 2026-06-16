-- ============================================================================
-- corrige_cf_token_NXFGTSJ34_PROD.sql      (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Deixa o cash_flow do TOKEN NXFGTSJ34-1 identico ao da SERIE CR-FGTS-01-01-SINGLE.
-- O token ficou de fora da correcao dos 78 SIM, entao 5 eventos (07-08, 08-05,
-- 09-08, 10-06, 11-06) ainda tem cash_flow = -clean_price (bug). Aqui seto cada um
-- = ao cash_flow ja correto da serie (mesma data). clean_price/accrued ja sao iguais.
-- Cada linha antiga do token vai para `histories` (operation='update') ANTES do UPDATE.
-- IDs por NOME. DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (1) linhas-evento do token a corrigir, com o valor correto vindo da serie
CREATE TEMP TABLE _fix ON COMMIT DROP AS
SELECT vt.id AS token_val_id, vt.date::date AS dia, vt.cash_flow AS cf_old,
       vt.clean_price, vs.cash_flow AS cf_new
FROM valuations vt
JOIN valuations vs
  ON vs.asset_id = (SELECT id FROM entities WHERE name='CR-FGTS-01-01-SINGLE')
 AND vs.date::date = vt.date::date
 AND vs.cash_flow <> 0
WHERE vt.asset_id = (SELECT id FROM entities WHERE name='NXFGTSJ34-1')
  AND vt.cash_flow <> 0
  AND vt.date::date IN ('2025-07-08','2025-08-05','2025-09-08','2025-10-06','2025-11-06');

-- (2) preview (bug_check_0 deve ser 0 = cash_flow era -clean_price)
SELECT dia, cf_old, clean_price, cf_new, round((cf_old + clean_price)::numeric, 6) AS bug_check_0
FROM _fix ORDER BY dia;

-- (3) GUARDA: exatamente 5 linhas e todas com a assinatura do bug
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _fix;
  IF n <> 5 THEN RAISE EXCEPTION '_fix = % (esperado 5)', n; END IF;
  SELECT count(*) INTO n FROM _fix WHERE abs(cf_old + clean_price) > 0.01;
  IF n > 0 THEN RAISE EXCEPTION 'assinatura do bug falhou em % linha(s) (cash_flow <> -clean_price)', n; END IF;
END $$;

-- (4) histories (linha antiga do token) antes do UPDATE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update',
       'corrige cash_flow do token NXFGTSJ34-1 p/ casar com a serie CR-FGTS-01-01-SINGLE (estava = -clean_price)'
FROM valuations v JOIN _fix f ON f.token_val_id = v.id;

-- (5) UPDATE
UPDATE valuations v SET cash_flow = f.cf_new FROM _fix f WHERE v.id = f.token_val_id;

-- (6) GUARDA FINAL: serie x token sem NENHUMA diferenca (clean/accrued/cash_flow)
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM (
    WITH s AS (SELECT date::date d, (cash_flow IS NOT NULL AND cash_flow<>0) ev, clean_price, accrued_interest, cash_flow
               FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-01-01-SINGLE')),
         t AS (SELECT date::date d, (cash_flow IS NOT NULL AND cash_flow<>0) ev, clean_price, accrued_interest, cash_flow
               FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSJ34-1'))
    SELECT 1 FROM s FULL JOIN t ON s.d=t.d AND s.ev=t.ev
    WHERE s.clean_price IS DISTINCT FROM t.clean_price
       OR s.accrued_interest IS DISTINCT FROM t.accrued_interest
       OR s.cash_flow IS DISTINCT FROM t.cash_flow
  ) x;
  IF n <> 0 THEN RAISE EXCEPTION 'ainda ha % linha(s) diferentes serie x token', n; END IF;
  RAISE NOTICE 'OK: serie e token identicos (0 diferencas)';
END $$;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
