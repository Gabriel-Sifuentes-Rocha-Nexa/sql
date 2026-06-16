"""
corrige_cash_flow_PROD.py  —  APLICAR EM PRODUCAO (voce roda; o assistente NAO executa)
---------------------------------------------------------------------------------------
Corrige no PROD o `valuations.cash_flow` de eventos de amortizacao de securitization_series
que foram lancados ERRADOS (= -clean_price) em vez do caixa realmente distribuido.
O valor correto vem da metadata `amortization` do V1 (fonte-de-verdade) = principal(+juros)
pago naquela data. Cada linha antiga e' salva em `histories` (old_value = to_jsonb) ANTES
do UPDATE.

SEGURANCA:
  - Conexao = env DATABASE_URL. APONTE para o PROD (tunel :5003) ao rodar.
  - DRY-RUN por padrao (COMMIT=False): executa na transacao e da ROLLBACK -> nada muda.
  - Resolve a linha POR (nome da serie -> entities.id, data, methodology=amortized_cost,
    cash_flow<>0). PRE-CHECK aborta (sem alterar) se nao achar exatamente 1 linha OU se o
    cash_flow atual nao for o valor-bug esperado (estado ja mudou / linha errada).
  - So altera a coluna cash_flow. clean_price/accrued NAO sao tocados.

ESCOPO (decisao 2026-06-09): SO os 4 casos GLITCH_ACCRUED, onde o clean_price do V2 esta
CORRETO (cash_flow certo = queda do clean = V1_total) -> fix consistente e seguro.
Os 4 casos DIVERGE ficam em CASES_REVIEW (DESABILITADOS) — gravar V1_total neles seria
ERRADO (ver motivo em cada um). Nao habilitar sem decidir caso a caso.

USO:
  $env:DATABASE_URL = "postgresql://gabriel_sifuentes:...@127.0.0.1:5003/engine"   # PROD (tunel)
  python corrige_cash_flow_PROD.py        # DRY-RUN: pre-check, preview do UPDATE e do histories
  # valide -> edite COMMIT=True -> rode de novo p/ aplicar.
"""
import os, re, sys
from sqlalchemy import create_engine, text

# ============================ CONFIG ============================
COMMIT = False                       # True = aplica no PROD (apos validar o dry-run)
CREATED_BY = 'gabriel_sifuentes'     # vai em histories.created_by
DESC = 'corrige cash_flow do evento de amortizacao (estava = -clean_price; valor correto = amortizacao paga conforme V1)'
TOL = 0.01                           # tolerancia p/ casar o cash_flow atual com o valor-bug esperado
# ================================================================

# 4 casos SEGUROS (GLITCH_ACCRUED): clean_price do V2 correto; cash_flow certo = queda do clean = V1_total.
# (serie, data, cash_flow_atual_esperado, cash_flow_novo)
CASES = [
    ('CR-FGTS-01-01-SINGLE', '2025-11-14', -87.34147505, 0.1263079),
    ('CR-FGTS-02-01-SINGLE', '2025-11-14', -94.123675,   1.053923),
    ('CR-FGTS-03-01-SINGLE', '2025-11-14', -94.241843,   1.268654),
    ('CR-FGTS-06-01-SINGLE', '2025-11-14', -97.1780958,  1.0783792),
]

# 4 casos DIVERGE — DESABILITADOS. NAO e' so trocar cash_flow:
#   ('CR-FGTS-08-01-SENIOR',    '2026-04-17', -5.724204,    93.833296),
#       -> V2 NAO tem o evento de 2026-03-16 (V1 tem; amort 13.53). O 04-17 do V2 esta "lumped"
#          e nao corresponde ao 04-17 do V1; gravar 93.83 seria errado. Exige tratar o evento faltante.
#   ('CR-FGTS-08-02-MEZZANINE', '2026-04-17', -5.599095,    93.958405),
#       -> idem (V1 tem 2026-03-16 amort 14.10 ausente no V2).
#   ('CR-FGTS-23-01-SINGLE',    '2026-05-07', -99.92420891, 0.54213173),
#       -> clean do V2 quase nao caiu (0.076), mas V1 diz 0.542. Gravar 0.542 com o preco parado
#          RECRIA a inconsistencia "caixa grande, preco parado". V2 sub-amortizou (clean_price tb errado).
#   ('CR-FGTS-25-01-SINGLE',    '2026-05-06', -96.20201,    5.26621213491274),
#       -> idem: clean caiu 3.798, V1 diz 5.266. V2 sub-amortizou; clean_price tb diverge.
CASES_REVIEW = []  # manter vazio ate decisao caso a caso

URL = os.environ.get('DATABASE_URL')
if not URL:
    sys.exit('Defina DATABASE_URL apontando para o PROD (tunel :5003) antes de rodar.')

eng = create_engine(URL)
conn = eng.connect()
trans = conn.begin()


def abort(msg):
    trans.rollback(); conn.close()
    sys.exit('PRE-CHECK FALHOU -> ' + msg + ' (nada alterado).')


print('Alvo  :', re.sub(r'(//[^:]+:)[^@]+(@)', r'\1***\2', URL))
print('Modo  :', 'COMMIT (APLICA)' if COMMIT else 'DRY-RUN (rollback)', '| by:', CREATED_BY)
print('-' * 92)

try:
    meth = conn.execute(text("SELECT id FROM valuation_methodologies WHERE name='amortized_cost'")).scalar()
    if meth is None:
        abort('methodology amortized_cost nao encontrada')

    plano = []
    for serie, data, cf_old, cf_new in CASES:
        aid = conn.execute(text('SELECT id FROM entities WHERE name=:n'), {'n': serie}).scalar()
        if aid is None:
            abort(f'serie "{serie}" nao existe')
        rows = conn.execute(text(
            "SELECT id, cash_flow, clean_price, accrued_interest "
            "FROM valuations "
            "WHERE asset_id=:a AND methodology_id=:m AND date::date=:d "
            "  AND cash_flow IS NOT NULL AND cash_flow <> 0"),
            {'a': aid, 'm': meth, 'd': data}).fetchall()
        if len(rows) != 1:
            abort(f'{serie} {data}: esperava 1 linha-evento, achei {len(rows)}')
        vid, cf_cur, clean, acc = rows[0]
        if abs(float(cf_cur) - cf_old) > TOL:
            abort(f'{serie} {data}: cash_flow atual {cf_cur} != esperado {cf_old} (estado mudou?)')
        plano.append({'serie': serie, 'data': data, 'vid': vid,
                      'cf_cur': float(cf_cur), 'cf_new': cf_new, 'clean': float(clean)})

    print(f'PRE-CHECK ok: {len(plano)} linha(s)-evento resolvida(s) no PROD.\n')
    print(f"{'serie':<26} {'data':<11} {'val_id':>10} {'cash_flow atual':>18} -> {'cash_flow novo':>16}   clean")
    for p in plano:
        print(f"  {p['serie']:<24} {p['data']:<11} {p['vid']:>10} {p['cf_cur']:>18.8f} -> {p['cf_new']:>16.8f}   {p['clean']:.6f}")

    # ---------- HISTORIES (linha antiga) + UPDATE ----------
    for p in plano:
        conn.execute(text(
            "INSERT INTO histories (created_by, table_name, old_value, operation, description) "
            "SELECT :by, 'valuations', to_jsonb(t), 'update', :d FROM valuations t WHERE t.id = :i"),
            {'by': CREATED_BY, 'd': DESC, 'i': p['vid']})
        conn.execute(text('UPDATE valuations SET cash_flow=:v WHERE id=:i'),
                     {'v': p['cf_new'], 'i': p['vid']})

    # ---------- POST-CHECK ----------
    bad = []
    for p in plano:
        novo = conn.execute(text('SELECT cash_flow FROM valuations WHERE id=:i'), {'i': p['vid']}).scalar()
        if abs(float(novo) - p['cf_new']) > 1e-6:
            bad.append(f"val {p['vid']} = {novo} (esperado {p['cf_new']})")
    if bad:
        abort('POST-CHECK inconsistente: ' + '; '.join(bad))
    nhist = conn.execute(text("SELECT count(*) FROM histories WHERE created_by=:by AND description=:d"),
                         {'by': CREATED_BY, 'd': DESC}).scalar()
    print(f'\nPOST-CHECK ok. UPDATEs: {len(plano)} | linhas em histories nesta transacao (aprox): {nhist}')

    if COMMIT:
        trans.commit(); print('\nCOMMIT aplicado no PROD.')
    else:
        trans.rollback(); print('\nDRY-RUN: ROLLBACK -> NADA alterado. Valide e rode com COMMIT=True.')
except SystemExit:
    raise
except Exception:
    trans.rollback(); raise
finally:
    if not conn.closed:
        conn.close()
