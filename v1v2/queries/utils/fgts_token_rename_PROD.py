"""
fgts_token_rename_PROD.py  —  APLICAR EM PRODUCAO (voce roda; o assistente NAO executa)
---------------------------------------------------------------------------------------
Corrige no PROD o nome dos 6 tokens FGTS (espelha o V1) + remove/arquiva a entidade
orfa 'NXFGTSI35-2', LOGANDO cada linha antiga em `histories` (old_value = to_jsonb)
ANTES de alterar — tudo rastreavel.

POR QUE 2 FASES: os nomes formam uma permutacao fechada (o nome final de um esta
ocupado por outro), entao renomeia-se tudo p/ nomes temporarios e depois p/ os finais,
sem violar o UNIQUE de entities.name / financial_accounts.name no meio.

SEGURANCA:
  - Conexao = env DATABASE_URL. APONTE para o PROD ao rodar (ex.: $env:DATABASE_URL=...).
  - DRY-RUN por padrao (COMMIT=False): executa tudo na transacao e da ROLLBACK -> nada muda.
  - Resolve ids POR NOME em runtime (ids de prod diferem do ambiente local).
  - PRE-CHECK aborta (sem alterar) se o estado de prod nao casar com o esperado.
  - Cada UPDATE/DELETE e precedido por INSERT em `histories` com a linha antiga (to_jsonb).
  - rename muda so o NOME (+updated_at); FKs sao por id -> intactas.

USO:
  $env:DATABASE_URL = "postgresql://<prod...>"     # PowerShell
  python fgts_token_rename_PROD.py                  # DRY-RUN: mostra pre-check, histories e pos-check
  # valide tudo -> edite COMMIT=True -> rode de novo p/ aplicar.
"""
import os, re, sys
from sqlalchemy import create_engine, text

# ============================ CONFIG ============================
COMMIT = False                 # True = aplica no PROD (apos validar o dry-run)
ORPHAN_MODE = 'archive'        # 'archive' (seguro/reversivel) | 'delete' (cascateia valuations+entity_type)
CREATED_BY = 'gabriel_sifuentes'   # vai em histories.created_by  <<< confirme seu usuario de histories
DESC_REN = 'corrige nome do token FGTS para espelhar o V1 (permutacao do balde I35/L34)'
DESC_ORF = 'remove/arquiva entidade orfa NXFGTSI35-2 (token stub: sem token/positions)'
# ================================================================

RENAMES = [  # (nome_atual, nome_final_V1)
    ('NXFGTSL34-1', 'NXFGTSJ34-1'),   # CR-01
    ('NXFGTSI35-1', 'NXFGTSH35-1'),   # CR-02
    ('NXFGTSI35-3', 'NXFGTSH35-2'),   # CR-03
    ('NXFGTSI35-4', 'NXFGTSI35-1'),   # CR-04
    ('NXFGTSI35-5', 'NXFGTSI35-2'),   # CR-05
    ('NXFGTSI35-6', 'NXFGTSI35-3'),   # CR-06
]
FREE_TARGETS = ['NXFGTSJ34-1', 'NXFGTSH35-1', 'NXFGTSH35-2']  # alvos que devem estar livres
ORPHAN_NAME = 'NXFGTSI35-2'
FA = 'assets pledged as collateral - '

URL = os.environ.get('DATABASE_URL')
if not URL:
    sys.exit('Defina DATABASE_URL apontando para o PROD antes de rodar.')
if CREATED_BY == 'SEU_USUARIO':
    sys.exit('Edite CREATED_BY com o seu usuario (vai em histories.created_by).')

eng = create_engine(URL)
conn = eng.connect()
trans = conn.begin()


def sc(q, **p):
    return conn.execute(text(q), p).scalar()


def hist(table, where_col, where_id, op, desc):
    """Salva a linha antiga (to_jsonb) em histories ANTES de mexer nela."""
    conn.execute(text(
        f"INSERT INTO histories (created_by, table_name, old_value, operation, description) "
        f"SELECT :by, :tb, to_jsonb(t), :op, :d FROM {table} t WHERE t.{where_col} = :i"),
        {'by': CREATED_BY, 'tb': table, 'op': op, 'd': desc, 'i': where_id})


def abort(msg):
    trans.rollback(); conn.close()
    sys.exit('PRE-CHECK FALHOU -> ' + msg + ' (nada alterado).')


print('Alvo  :', re.sub(r'(//[^:]+:)[^@]+(@)', r'\1***\2', URL))
print('Modo  :', 'COMMIT (APLICA)' if COMMIT else 'DRY-RUN (rollback)', '| orfa:', ORPHAN_MODE, '| by:', CREATED_BY)
print('-' * 80)

try:
    # ---------- PRE-CHECK + resolucao de ids por NOME ----------
    mp = []
    for cur, fin in RENAMES:
        eid = sc('SELECT id FROM entities WHERE name = :n', n=cur)
        fid = sc('SELECT id FROM financial_accounts WHERE name = :n', n=FA + cur)
        if eid is None:
            abort(f'entity "{cur}" nao existe no estado original')
        if fid is None:
            abort(f'conta de colateral de "{cur}" nao existe')
        mp.append({'eid': eid, 'fid': fid, 'cur': cur, 'fin': fin})

    for t in FREE_TARGETS:
        if sc('SELECT 1 FROM entities WHERE name = :n', n=t):
            abort(f'nome-alvo livre "{t}" ja existe em entities')
        if sc('SELECT 1 FROM financial_accounts WHERE name = :n', n=FA + t):
            abort(f'conta-alvo de "{t}" ja existe')

    if sc("SELECT count(*) FROM entities WHERE name LIKE 'TMP-REN-%'") or \
       sc("SELECT count(*) FROM financial_accounts WHERE name LIKE 'TMP-REN-%'"):
        abort('ja existem nomes TMP-REN-% (rodada anterior incompleta?)')

    # orfa: deve ser ausente OU um stub (sem token, sem positions)
    oid = sc('SELECT id FROM entities WHERE name = :n', n=ORPHAN_NAME)
    if oid is not None:
        ntok = sc('SELECT count(*) FROM tokens WHERE id = :i', i=oid)
        npos = sc('SELECT count(*) FROM positions WHERE asset_id = :i OR holder_id = :i', i=oid)
        if ntok or npos:
            abort(f'"{ORPHAN_NAME}" (id {oid}) NAO e stub (tokens={ntok}, positions={npos}) -> nao mexo')

    print('PRE-CHECK ok: 6 tokens no estado original, alvos livres, orfa =',
          ('stub id %s' % oid) if oid else 'ausente (nome ja livre)')
    print('\nMapa (resolvido em prod):')
    for r in mp:
        print(f"  entity {r['eid']:>9} / fa {r['fid']:>6}  {r['cur']:<14} -> {r['fin']}")

    # ---------- ORFA (antes do rename, p/ liberar o nome -2) ----------
    if oid is not None:
        fa_oid = sc('SELECT id FROM financial_accounts WHERE name = :n', n=FA + ORPHAN_NAME)
        if ORPHAN_MODE == 'archive':
            hist('entities', 'id', oid, 'update', DESC_ORF)
            if fa_oid:
                hist('financial_accounts', 'id', fa_oid, 'update', DESC_ORF)
            conn.execute(text("UPDATE entities SET name='ARCHIVED-'||:n||'-'||id, updated_at=now() WHERE id=:i"),
                         {'n': ORPHAN_NAME, 'i': oid})
            if fa_oid:
                conn.execute(text("UPDATE financial_accounts SET name='ARCHIVED-'||name||'-'||id, updated_at=now() WHERE id=:i"),
                             {'i': fa_oid})
            print(f'\norfa {oid}: ARQUIVADA (entity + fa) e logada em histories.')
        elif ORPHAN_MODE == 'delete':
            # log de TODAS as linhas que serao apagadas (operation='delete')
            for v in conn.execute(text('SELECT id FROM valuations WHERE asset_id=:i'), {'i': oid}).scalars():
                hist('valuations', 'id', v, 'delete', DESC_ORF)
            for et in conn.execute(text('SELECT id FROM entity_types WHERE entity_id=:i'), {'i': oid}).scalars():
                hist('entity_types', 'id', et, 'delete', DESC_ORF)
            if fa_oid:
                hist('financial_accounts', 'id', fa_oid, 'delete', DESC_ORF)
            hist('entities', 'id', oid, 'delete', DESC_ORF)
            # deletes na ordem das FKs
            nv = conn.execute(text('DELETE FROM valuations WHERE asset_id=:i'), {'i': oid}).rowcount
            ne = conn.execute(text('DELETE FROM entity_types WHERE entity_id=:i'), {'i': oid}).rowcount
            nf = conn.execute(text('DELETE FROM financial_accounts WHERE id=:i'), {'i': fa_oid}).rowcount if fa_oid else 0
            nn = conn.execute(text('DELETE FROM entities WHERE id=:i'), {'i': oid}).rowcount
            print(f'\norfa {oid}: DELETADA (valuations={nv}, entity_types={ne}, fa={nf}, entity={nn}) e logada.')
        else:
            abort(f'ORPHAN_MODE invalido: {ORPHAN_MODE}')

    # ---------- HISTORIES dos 6 (antes do update) ----------
    for r in mp:
        hist('entities', 'id', r['eid'], 'update', DESC_REN)
        hist('financial_accounts', 'id', r['fid'], 'update', DESC_REN)

    # ---------- FASE 1: nomes temporarios ----------
    for r in mp:
        conn.execute(text("UPDATE entities SET name='TMP-REN-'||id, updated_at=now() WHERE id=:i"), {'i': r['eid']})
        conn.execute(text("UPDATE financial_accounts SET name='TMP-REN-FA-'||id, updated_at=now() WHERE id=:i"), {'i': r['fid']})

    # ---------- FASE 2: nomes finais ----------
    for r in mp:
        conn.execute(text('UPDATE entities SET name=:n WHERE id=:i'), {'n': r['fin'], 'i': r['eid']})
        conn.execute(text('UPDATE financial_accounts SET name=:n WHERE id=:i'), {'n': FA + r['fin'], 'i': r['fid']})

    # ---------- POST-CHECK ----------
    bad = []
    for r in mp:
        if sc('SELECT name FROM entities WHERE id=:i', i=r['eid']) != r['fin']:
            bad.append(f"entity {r['eid']} != {r['fin']}")
        if sc('SELECT name FROM financial_accounts WHERE id=:i', i=r['fid']) != FA + r['fin']:
            bad.append(f"fa {r['fid']} != {r['fin']}")
    leftover = conn.execute(text('SELECT name FROM entities WHERE name = ANY(:n)'),
                            {'n': [c for c, _ in RENAMES if c not in [f for _, f in RENAMES]]}).fetchall()
    if leftover:
        bad.append(f'sobraram nomes antigos liberados: {leftover}')
    if bad:
        abort('POST-CHECK inconsistente: ' + '; '.join(bad))

    nhist = sc("SELECT count(*) FROM histories WHERE created_by=:by AND description IN (:a,:b)",
               by=CREATED_BY, a=DESC_REN, b=DESC_ORF)
    print(f'\nPOST-CHECK ok. Linhas inseridas em histories nesta transacao (aprox): {nhist}')
    print('Estado final:')
    for r in mp:
        print(f"  {r['cur']:<14} -> {sc('SELECT name FROM entities WHERE id=:i', i=r['eid'])}")

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
