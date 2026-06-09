"""
fgts_token_rename_v2.py
---------------------------------------------------------------------------
Renomeia, SOMENTE no V2 LOCAL (engine @ 127.0.0.1:5432), os 6 tokens FGTS cujo
nome diverge do V1, ESPELHANDO o V1 exatamente. Como os nomes formam uma
permutacao fechada (o nome certo de um esta ocupado por outro), o rename e feito
em 2 FASES (nomes temporarios) p/ nunca violar o UNIQUE de entities.name /
financial_accounts.name no meio do caminho.

Tambem trata a entidade ORFA 'NXFGTSI35-2' (id 262653), que ocupa o nome -2.
  ORPHAN_MODE='archive' (padrao): renomeia a orfa + a fa dela p/ ARCHIVED-...
      (seguro, reversivel; mantem as 9 valuations e o entity_type ligados a ela).
  ORPHAN_MODE='delete': APAGA a orfa em cascata (9 valuations + 1 entity_type +
      a fa 9916 + a entity 262653). So use depois de conferir essas 9 valuations.

Mapa final (decidido: ESPELHAR V1):
  CR-01 NXFGTSL34-1 -> NXFGTSJ34-1     CR-04 NXFGTSI35-4 -> NXFGTSI35-1
  CR-02 NXFGTSI35-1 -> NXFGTSH35-1     CR-05 NXFGTSI35-5 -> NXFGTSI35-2
  CR-03 NXFGTSI35-3 -> NXFGTSH35-2     CR-06 NXFGTSI35-6 -> NXFGTSI35-3

Seguranca:
  - conecta SO no DATABASE_URL do .env e ABORTA se nao for 127.0.0.1:5432/engine;
  - DRY-RUN por padrao (COMMIT=False): roda tudo na transacao e da ROLLBACK;
  - PRE-CHECK aborta se o estado do banco nao casar com o mapa (ids/nomes/alvos);
  - so toca os 7 ids listados; rename muda apenas o NOME (FKs sao por id -> intactas);
  - POST-CHECK confirma o estado final antes de voce trocar COMMIT=True.

Uso:
  cd v1v2/queries/utils
  ..\\..\\.venv\\Scripts\\python.exe fgts_token_rename_v2.py     # dry-run (rollback)
  # valide PRE/POST-CHECK; depois edite COMMIT=True e rode de novo p/ aplicar.
"""
import re
import pathlib
import pandas as pd
from sqlalchemy import create_engine, text

# ============================ CONFIG ============================
COMMIT = False            # False = dry-run (ROLLBACK). True = aplica no V2 local.
ORPHAN_MODE = 'archive'   # 'archive' (seguro) | 'delete' (cascateia valuations+entity_type)
# ================================================================

# (entity_id, fa_id_colateral, nome_atual, nome_final_V1)
RENAMES = [
    (20451,   9632,  'NXFGTSL34-1', 'NXFGTSJ34-1'),   # CR-FGTS-01
    (159526,  9915,  'NXFGTSI35-1', 'NXFGTSH35-1'),   # CR-FGTS-02
    (1035060, 9917,  'NXFGTSI35-3', 'NXFGTSH35-2'),   # CR-FGTS-03
    (1047752, 9940,  'NXFGTSI35-4', 'NXFGTSI35-1'),   # CR-FGTS-04
    (1052807, 9972,  'NXFGTSI35-5', 'NXFGTSI35-2'),   # CR-FGTS-05
    (1057260, 10005, 'NXFGTSI35-6', 'NXFGTSI35-3'),   # CR-FGTS-06
]
ORPHAN_ID = 262653
ORPHAN_NAME = 'NXFGTSI35-2'
FA_PREFIX = 'assets pledged as collateral - '

# ---- credencial: le do .env do subprojeto de amortizacao (V2 local) ----
ENV_PATH = pathlib.Path(__file__).resolve().parents[2] / 'corrigir_amortizacao_token' / '.env'
env = {}
for _ln in ENV_PATH.read_text(encoding='utf-8').splitlines():
    _ln = _ln.strip()
    if _ln and not _ln.startswith('#') and '=' in _ln:
        _k, _v = _ln.split('=', 1)
        env[_k.strip()] = _v.strip()
URL = env.get('DATABASE_URL', '')

# ---- TRAVA: so o V2 LOCAL ----
if not re.search(r'@(127\.0\.0\.1|localhost):5432/engine(\b|$|\?)', URL):
    raise SystemExit('ABORTADO: DATABASE_URL nao aponta para 127.0.0.1:5432/engine (V2 local).')
if 'supabase' in URL.lower() or env.get('V1_DATABASE_URL', '') == URL:
    raise SystemExit('ABORTADO: a URL parece ser de prod/V1. Recuso.')

print('Alvo (V2 local):', re.sub(r'(//[^:]+:)[^@]+(@)', r'\1***\2', URL))
print('Modo:', 'COMMIT (aplica)' if COMMIT else 'DRY-RUN (rollback ao final)', '| orfa:', ORPHAN_MODE)
print('-' * 78)

eng = create_engine(URL)
conn = eng.connect()
trans = conn.begin()


def scalar(sql, **p):
    return conn.execute(text(sql), p).scalar()


def abort(msg):
    trans.rollback(); conn.close()
    raise SystemExit('PRE-CHECK FALHOU -> ' + msg + ' (nada alterado).')


try:
    # ============ PRE-CHECK (aborta se algo nao casar) ============
    finais = [r[3] for r in RENAMES]
    atuais = [r[2] for r in RENAMES]
    ids = [r[0] for r in RENAMES]
    fids = [r[1] for r in RENAMES]

    for eid, fid, cur, fin in RENAMES:
        if scalar('SELECT name FROM entities WHERE id=:i', i=eid) != cur:
            abort(f'entity {eid} nao tem nome {cur}')
        if scalar('SELECT name FROM financial_accounts WHERE id=:i', i=fid) != FA_PREFIX + cur:
            abort(f'fa {fid} nao e a conta de colateral de {cur}')

    # orfa no estado esperado
    if scalar('SELECT name FROM entities WHERE id=:i', i=ORPHAN_ID) != ORPHAN_NAME:
        abort(f'orfa {ORPHAN_ID} nao tem nome {ORPHAN_NAME}')

    # nenhum nome-FINAL ja existe, exceto se for de um dos nossos ids (sera liberado) ou da orfa
    rows = conn.execute(text(
        'SELECT id, name FROM entities WHERE name = ANY(:n)'), {'n': finais}).fetchall()
    for rid, rname in rows:
        if rid not in ids and rid != ORPHAN_ID:
            abort(f'nome final {rname} ja pertence a entity {rid} (fora do escopo)')
    rows = conn.execute(text(
        "SELECT id, name FROM financial_accounts WHERE name = ANY(:n)"),
        {'n': [FA_PREFIX + f for f in finais]}).fetchall()
    ok_fa = set(fids) | {scalar('SELECT id FROM financial_accounts WHERE name=:n',
                                n=FA_PREFIX + ORPHAN_NAME)}
    for rid, rname in rows:
        if rid not in ok_fa:
            abort(f'fa final {rname} ja pertence a fa {rid} (fora do escopo)')

    # nenhum nome temporario colide
    if scalar("SELECT count(*) FROM entities WHERE name LIKE 'TMP-REN-%'") or \
       scalar("SELECT count(*) FROM financial_accounts WHERE name LIKE 'TMP-REN-%'"):
        abort('ja existem nomes TMP-REN-% no banco')

    print('PRE-CHECK ok: 6 tokens + 6 contas + orfa no estado esperado; alvos livres.\n')
    print('=== ANTES ===')
    print(pd.read_sql(text('SELECT id, name FROM entities WHERE id = ANY(:i) ORDER BY name'),
                      conn, params={'i': ids + [ORPHAN_ID]}).to_string(index=False))

    # ============ ORFA ============
    if ORPHAN_MODE == 'archive':
        conn.execute(text("UPDATE entities SET name = 'ARCHIVED-' || :nm || '-' || id WHERE id=:i"),
                     {'nm': ORPHAN_NAME, 'i': ORPHAN_ID})
        conn.execute(text(
            "UPDATE financial_accounts SET name = 'ARCHIVED-' || name || '-' || id "
            "WHERE name = :n"), {'n': FA_PREFIX + ORPHAN_NAME})
        print(f'\norfa {ORPHAN_ID} ARQUIVADA (entity + fa).')
    elif ORPHAN_MODE == 'delete':
        # re-checa que so os refs conhecidos existem antes de cascatear
        refs = {}
        for tbl, col in [('positions', 'asset_id'), ('positions', 'holder_id'),
                         ('positions', 'originator_id'), ('positions', 'broker_id'),
                         ('valuations', 'asset_id'), ('entity_types', 'entity_id'),
                         ('tokens', 'id'), ('tokens', 'issuer_id'),
                         ('securitization_series', 'id'), ('securitization_series', 'issuer_id')]:
            n = scalar(f'SELECT count(*) FROM {tbl} WHERE {col}=:i', i=ORPHAN_ID)
            if n:
                refs[f'{tbl}.{col}'] = n
        # so toleramos valuations.asset_id e entity_types.entity_id
        unexpected = {k: v for k, v in refs.items()
                      if k not in ('valuations.asset_id', 'entity_types.entity_id')}
        if unexpected:
            abort(f'orfa tem refs inesperadas: {unexpected} -> recuso DELETE, use archive')
        nv = conn.execute(text('DELETE FROM valuations WHERE asset_id=:i'), {'i': ORPHAN_ID}).rowcount
        ne = conn.execute(text('DELETE FROM entity_types WHERE entity_id=:i'), {'i': ORPHAN_ID}).rowcount
        nf = conn.execute(text('DELETE FROM financial_accounts WHERE name=:n'),
                          {'n': FA_PREFIX + ORPHAN_NAME}).rowcount
        nn = conn.execute(text('DELETE FROM entities WHERE id=:i'), {'i': ORPHAN_ID}).rowcount
        print(f'\norfa DELETADA: valuations={nv} entity_types={ne} fa={nf} entity={nn}')
    else:
        abort(f'ORPHAN_MODE invalido: {ORPHAN_MODE}')

    # ============ FASE 1: tudo -> nomes temporarios ============
    for eid, fid, cur, fin in RENAMES:
        conn.execute(text('UPDATE entities SET name = :t WHERE id=:i'),
                     {'t': f'TMP-REN-{eid}', 'i': eid})
        conn.execute(text('UPDATE financial_accounts SET name = :t WHERE id=:i'),
                     {'t': f'TMP-REN-FA-{fid}', 'i': fid})

    # ============ FASE 2: temporarios -> nomes finais (V1) ============
    for eid, fid, cur, fin in RENAMES:
        conn.execute(text('UPDATE entities SET name = :n WHERE id=:i'), {'n': fin, 'i': eid})
        conn.execute(text('UPDATE financial_accounts SET name = :n WHERE id=:i'),
                     {'n': FA_PREFIX + fin, 'i': fid})

    # ============ POST-CHECK ============
    print('\n=== DEPOIS (entities) ===')
    print(pd.read_sql(text('SELECT id, name FROM entities WHERE id = ANY(:i) ORDER BY name'),
                      conn, params={'i': ids + [ORPHAN_ID]}).to_string(index=False))
    print('\n=== DEPOIS (contas de colateral) ===')
    print(pd.read_sql(text('SELECT id, name FROM financial_accounts WHERE id = ANY(:i) ORDER BY name'),
                      conn, params={'i': fids}).to_string(index=False))

    bad = []
    for eid, fid, cur, fin in RENAMES:
        if scalar('SELECT name FROM entities WHERE id=:i', i=eid) != fin:
            bad.append(f'entity {eid} != {fin}')
        if scalar('SELECT name FROM financial_accounts WHERE id=:i', i=fid) != FA_PREFIX + fin:
            bad.append(f'fa {fid} != {fin}')
    # os nomes antigos "so-V2" nao podem sobrar como entity
    leftover = conn.execute(text('SELECT name FROM entities WHERE name = ANY(:n)'),
                            {'n': ['NXFGTSL34-1', 'NXFGTSI35-4', 'NXFGTSI35-5', 'NXFGTSI35-6']}
                            ).fetchall()
    if leftover:
        bad.append(f'sobraram nomes antigos: {leftover}')
    if bad:
        abort('POST-CHECK detectou inconsistencia: ' + '; '.join(bad))
    print('\nPOST-CHECK ok: 6 tokens + contas com nome final; nomes antigos sumiram.')

    if COMMIT:
        trans.commit()
        print('\nCOMMIT aplicado no V2 local.')
    else:
        trans.rollback()
        print('\nDRY-RUN: ROLLBACK -> NADA alterado. Valide e rode com COMMIT=True.')
except SystemExit:
    raise
except Exception:
    trans.rollback()
    raise
finally:
    if not conn.closed:
        conn.close()
