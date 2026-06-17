#!/usr/bin/env python
r"""Executa um arquivo .sql COMPLETO (read-write) contra o V2, respeitando o
controle de transacao (BEGIN/COMMIT/ROLLBACK) escrito DENTRO do .sql.

Diferente de queries/run_query.py (que e' read-only e so' aceita 1 SELECT), este
runner serve p/ aplicar scripts de correcao *_PROD.sql (com histories + dry-run).
A SEGURANCA fica no proprio .sql: mande-o com ROLLBACK no fim p/ dry-run, e troque
por COMMIT (ou passe --commit) p/ aplicar de verdade.

Credenciais: lidas do MESMO .env do projeto (DATABASE_URL) — nunca passadas em texto.
Uso:
    & "..\.venv\Scripts\python.exe" apply_sql_prod.py corrige_spread_NXFGTSF31-1_PROD.sql
    & "..\.venv\Scripts\python.exe" apply_sql_prod.py corrige_spread_NXFGTSF31-1_PROD.sql --commit
"""
import argparse
import os
import re
import sys
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

import psycopg2
import psycopg2.extras


def load_env(env_file=None):
    if load_dotenv is None:
        return
    if env_file:
        p = Path(env_file)
        if not p.exists():
            sys.exit(f"ERRO: --env-file nao encontrado: {p}")
        load_dotenv(p, override=True)
        return
    here = Path(__file__).resolve().parent
    # ATENCAO: ha um .env LOCAL nesta pasta (5432). Pro PROD, passe --env-file ../queries/.env.
    for candidate in (here / ".env", here.parent / ".env",
                      here.parent / "queries" / ".env", Path.cwd() / ".env"):
        if candidate.exists():
            load_dotenv(candidate)
            return


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--commit", action="store_true",
                    help="troca o ROLLBACK final do .sql por COMMIT antes de executar")
    ap.add_argument("--env-file", default=None,
                    help="caminho do .env a usar (PROD = ../queries/.env). Sem isso, busca local (5432).")
    args = ap.parse_args()

    load_env(args.env_file)
    url = os.environ.get("DATABASE_URL")
    if not url:
        sys.exit("ERRO: DATABASE_URL nao encontrado (.env).")

    # mostra so' host:porta/db (sem usuario/senha) p/ confirmar o alvo
    safe = re.sub(r"://[^@]*@", "://***@", url)
    print(f"-- alvo: {safe}")

    sql = Path(args.sql_file).read_text(encoding="utf-8")
    if args.commit:
        # troca apenas o ULTIMO ROLLBACK por COMMIT
        idx = sql.lower().rfind("rollback")
        if idx == -1:
            sys.exit("ERRO: --commit pedido mas nao achei 'ROLLBACK' no arquivo.")
        sql = sql[:idx] + "COMMIT" + sql[idx + len("rollback"):]
        print("-- modo: COMMIT (aplicando de verdade)")
    else:
        print("-- modo: dry-run (ROLLBACK conforme o .sql)")

    conn = psycopg2.connect(url)
    conn.autocommit = True  # o controle de txn vem do proprio .sql
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            try:
                cur.execute(sql)
            finally:
                for n in conn.notices:
                    print(n.rstrip())
            # imprime o ULTIMO result set, se houver (limitacao do PQexec multi-statement)
            if cur.description is not None:
                rows = cur.fetchall()
                print(f"\n-- ultimo result set: {len(rows)} linha(s) --")
                for i, row in enumerate(rows, 1):
                    print(f"[{i}] " + "  ".join(f"{k}={v}" for k, v in row.items()))
    except psycopg2.Error as e:
        print(f"\nERRO SQL: {e}")
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
