"""
reset_amortizacao_local.py
---------------------------------------------------------------------------
Apaga, *somente* no V2 LOCAL (engine @ 127.0.0.1:5432), os artefatos da
amortizacao errada de CR-FGTS-30-01-SENIOR / NXFSE26-1 no vencimento (2026-05-15),
para depois RE-LANCAR a amortizacao pela API e diagnosticar.

Apaga:
  (1) valuations com clean_price < 0 da serie e do token
      (= o evento de 15/05 + a propagacao 16/05 -> 01/06);
  (2) a(s) posicao(oes) de AMORTIZATION do CR-FGTS-30 em 15/05 (a perna de caixa orfa).

NAO apaga a valuation "diaria normal" de 15/05 (clean_price = 100, cash_flow = 0),
que e o estado pre-vencimento correto.

Seguranca:
  - conecta SO no DATABASE_URL e ABORTA se nao for 127.0.0.1:5432/engine (nunca V1/prod);
  - DRY-RUN por padrao (COMMIT = False): mostra o preview, executa os DELETE dentro de
    uma transacao e da ROLLBACK -> nada muda. Troque para COMMIT = True para aplicar.
  - os triggers do banco recompoem last_valuation_flag / total_quantity / last_position_flag.

Uso:
  .venv\\Scripts\\python.exe reset_amortizacao_local.py          # dry-run (preview + rollback)
  # depois de validar o preview, edite COMMIT = True e rode de novo para aplicar.
"""
import re
import pathlib
import pandas as pd
from sqlalchemy import create_engine, text

# ============================ CONFIG ============================
COMMIT = False   # False = dry-run (ROLLBACK). True = aplica de verdade no V2 local.

SERIE = 'CR-FGTS-30-01-SENIOR'
TOKEN = 'NXFSE26-1'
CR    = 'CR-FGTS-30'
DIA   = '2026-05-15'
# ================================================================

ENV_PATH = pathlib.Path(__file__).with_name('.env')
env = {}
for _ln in ENV_PATH.read_text(encoding='utf-8').splitlines():
    _ln = _ln.strip()
    if _ln and not _ln.startswith('#') and '=' in _ln:
        _k, _v = _ln.split('=', 1)
        env[_k.strip()] = _v.strip()
URL = env.get('DATABASE_URL', '')

# ---- TRAVA DE SEGURANCA: so o V2 LOCAL ----
if not re.search(r'@(127\.0\.0\.1|localhost):5432/engine(\b|$|\?)', URL):
    raise SystemExit('ABORTADO: DATABASE_URL nao aponta para 127.0.0.1:5432/engine (V2 local).')
if 'supabase' in URL.lower() or env.get('V1_DATABASE_URL', '') == URL:
    raise SystemExit('ABORTADO: a URL parece ser de prod/V1. Recuso.')

_masked = re.sub(r'(//[^:]+:)[^@]+(@)', r'\1***\2', URL)
print('Alvo (V2 local):', _masked)
print('Modo:', 'COMMIT (aplica)' if COMMIT else 'DRY-RUN (rollback ao final)')
print('-' * 70)

eng = create_engine(URL)  # SEM read-only: este script escreve (so no local)

params = {'serie': SERIE, 'token': TOKEN, 'cr': CR, 'dia': DIA}

SQL_VAL_PREVIEW = text("""
    SELECT v.id, e.name AS ativo, m.name AS metodologia, v.date::date AS data,
           v.clean_price, v.cash_flow
    FROM valuations v
    JOIN entities e ON e.id = v.asset_id
    LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
    WHERE e.name IN (:serie, :token) AND v.clean_price < 0 AND v.date >= :dia
    ORDER BY e.name, v.date, v.id
""")
SQL_VAL_DELETE = text("""
    DELETE FROM valuations v
    USING entities e
    WHERE e.id = v.asset_id AND e.name IN (:serie, :token)
      AND v.clean_price < 0 AND v.date >= :dia
""")

SQL_POS_PREVIEW = text("""
    SELECT p.id, a.name AS ativo, h.name AS holder, fa.name AS conta,
           tt.name AS tx, p.variation, p.total_quantity AS saldo, p.block_id, p.doc_id
    FROM positions p
    JOIN entities a ON a.id = p.asset_id
    JOIN entities h ON h.id = p.holder_id
    LEFT JOIN financial_accounts fa ON fa.id = p.financial_account_id
    JOIN transaction_types tt ON tt.id = p.transaction_type_id
    WHERE p.date::date = :dia AND tt.name = 'AMORTIZATION' AND h.name = :cr
    ORDER BY p.id
""")
SQL_POS_DELETE = text("""
    DELETE FROM positions p
    USING entities h, transaction_types tt
    WHERE h.id = p.holder_id AND tt.id = p.transaction_type_id
      AND p.date::date = :dia AND tt.name = 'AMORTIZATION' AND h.name = :cr
""")

# valuation vigente (apos o delete) por ativo -> confirma que o trigger restaurou um preco sao
SQL_AFTER = text("""
    SELECT e.name AS ativo, v.date::date AS data, v.clean_price, v.last_valuation_flag AS vigente
    FROM valuations v
    JOIN entities e ON e.id = v.asset_id
    WHERE e.name IN (:serie, :token) AND v.last_valuation_flag
    ORDER BY e.name
""")

conn = eng.connect()
trans = conn.begin()
try:
    print('=== PREVIEW (1) valuations negativas a apagar ===')
    print(pd.read_sql(SQL_VAL_PREVIEW, conn, params=params).to_string())
    print('\n=== PREVIEW (2) posicao(oes) de AMORTIZATION a apagar ===')
    print(pd.read_sql(SQL_POS_PREVIEW, conn, params=params).to_string())

    rv = conn.execute(SQL_VAL_DELETE, params)
    rp = conn.execute(SQL_POS_DELETE, params)
    print(f'\n>>> valuations deletadas: {rv.rowcount}   |   posicoes deletadas: {rp.rowcount}')

    print('\n=== Valuation VIGENTE apos o delete (trigger recompoe last_valuation_flag) ===')
    print(pd.read_sql(SQL_AFTER, conn, params=params).to_string())

    if COMMIT:
        trans.commit()
        print('\nCOMMIT aplicado. Mudancas persistidas no V2 local.')
    else:
        trans.rollback()
        print('\nDRY-RUN: ROLLBACK executado -> NADA foi alterado. '
              'Valide o preview e, se ok, edite COMMIT = True e rode de novo.')
except Exception:
    trans.rollback()
    raise
finally:
    conn.close()
