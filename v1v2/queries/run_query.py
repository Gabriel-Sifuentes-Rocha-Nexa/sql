#!/usr/bin/env python
"""Executa um arquivo .sql (READ-ONLY) contra o banco V2 e imprime os resultados.

Uso (sempre via o venv):
    & "../.venv/Scripts/python.exe" run_query.py v2/03_nxni_metadata.sql --ticker NXNIC26-2

Credenciais NUNCA são passadas em texto pelo agente. São lidas de:
  1. DATABASE_URL (variável de ambiente ou arquivo .env), ou
  2. variáveis PG* padrão do libpq (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD)
     + ~/.pgpass / %APPDATA%/postgresql/pgpass.conf

A sessão é aberta como READ ONLY: qualquer tentativa de escrita falha.
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


def load_env():
    if load_dotenv is None:
        return
    here = Path(__file__).resolve().parent
    for candidate in (here / ".env", here.parent / ".env", Path.cwd() / ".env"):
        if candidate.exists():
            load_dotenv(candidate)
            return


def _strip_inline_comment(line):
    """Remove '-- ...' até o fim da linha, respeitando strings entre aspas simples."""
    in_str = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "'":
            in_str = not in_str
        elif ch == "-" and not in_str and i + 1 < len(line) and line[i + 1] == "-":
            return line[:i]
        i += 1
    return line


def strip_sql(text, ticker):
    # remove comentários (linha inteira e inline), preservando strings
    lines = []
    for ln in text.splitlines():
        cleaned = _strip_inline_comment(ln).rstrip()
        if cleaned.strip():
            lines.append(cleaned)
    sql = "\n".join(lines)
    sql = sql.replace("${fractionalWhere}", "")  # placeholder do framework V1
    if "${ticker}" in sql:
        if ticker is None:
            sys.exit("ERRO: a query usa ${ticker} — passe --ticker <valor>")
        sql = sql.replace("${ticker}", f"'{ticker}'")
    return sql.strip()


# Keywords de escrita/DDL: qualquer uma presente como palavra isolada barra a execução.
_FORBIDDEN = (
    "insert", "update", "delete", "drop", "truncate", "alter",
    "create", "grant", "revoke", "merge", "copy",
)


def assert_select_only(sql):
    """Guardrail: só permite uma única instrução SELECT/WITH de leitura.

    Defesa em profundidade junto com a sessão READ ONLY do banco. Falha rápido
    (antes de tocar o banco) com mensagem clara se a query não for de leitura.
    """
    # neutraliza literais entre aspas para não casar keywords dentro de strings
    sanitized = re.sub(r"'(?:[^']|'')*'", "''", sql)
    # um único statement: ';' só é tolerado no final
    if ";" in sanitized.rstrip().rstrip(";"):
        sys.exit("ERRO (guardrail): múltiplos statements não são permitidos — apenas um SELECT.")
    first = re.match(r"\s*(\w+)", sanitized)
    if not first or first.group(1).lower() not in ("select", "with"):
        found = first.group(1) if first else "?"
        sys.exit(f"ERRO (guardrail): apenas SELECT/WITH permitido (início: '{found}').")
    for kw in _FORBIDDEN:
        if re.search(rf"\b{kw}\b", sanitized, re.IGNORECASE):
            sys.exit(f"ERRO (guardrail): comando de escrita '{kw.upper()}' detectado — apenas leitura permitida.")
    return sql


def connect():
    url = os.environ.get("DATABASE_URL")
    if url:
        return psycopg2.connect(url)
    return psycopg2.connect()  # libpq resolve via PG* + pgpass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--ticker", default=None)
    ap.add_argument("--max-rows", type=int, default=50)
    args = ap.parse_args()

    load_env()
    raw = Path(args.sql_file).read_text(encoding="utf-8")
    sql = strip_sql(raw, args.ticker)
    assert_select_only(sql)

    conn = connect()
    conn.set_session(readonly=True, autocommit=True)
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql)
            rows = cur.fetchall()
            print(f"-- {len(rows)} linha(s) retornada(s) --")
            for i, row in enumerate(rows[: args.max_rows], 1):
                print(f"\n[{i}]")
                for key, value in row.items():
                    print(f"  {key}: {value}")
            if len(rows) > args.max_rows:
                print(f"\n... (+{len(rows) - args.max_rows} linhas, use --max-rows)")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
