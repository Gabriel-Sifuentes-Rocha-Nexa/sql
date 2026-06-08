"""
Acesso ao banco LOCAL `engine` (copia V2). READ-ONLY e travado em localhost.

Seguranca (NUNCA tocar prod):
  - so conecta se o host for local (127.0.0.1 / localhost / ::1);
  - sessao read-only (psycopg2 set_session readonly=True);
  - apenas SELECTs.
A DSN vem de DATABASE_URL (se local) ou do default local explicito. A
V1_DATABASE_URL (Supabase prod) e' deliberadamente IGNORADA aqui.
"""
from __future__ import annotations

import os
from datetime import date
from urllib.parse import urlparse

import psycopg2
import psycopg2.extras

from .model import Series

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1", ""}
DEFAULT_DSN = "postgresql://postgres:postgres@127.0.0.1:5432/engine"

# curva DI nominal forward (parameter = DU base 252, value = taxa a.a.)
DI_CURVE_ID = 10

# Uma serie pode ter VARIOS PUs com last_valuation_flag=TRUE (uma por
# metodologia de valuation). Escolhemos UM PU por unidade, por prioridade.
# O metodo assume "PU que acretua na taxa contratual" -> amortized_cost na
# frente (validado); depois modelo/curva e marca da casa (nexa). Excluimos
# de proposito amount_* e face_value (sao totais/par, nao PU por unidade).
#   2=amortized_cost 5=mark_to_model 16=pu_nexa 13=pu_daycoval
#   14=pu_vortex 3=mark_to_market 1=zero_spread 7=clean_coupon_dollar
PU_METHODOLOGY_PRIORITY = [2, 5, 16, 13, 14, 3, 1, 7]


def _host_of(dsn: str) -> str:
    try:
        return (urlparse(dsn).hostname or "").lower()
    except Exception:
        return "?"


def connect(dsn: str | None = None):
    """Abre conexao read-only com o engine local. Recusa host nao-local."""
    dsn = dsn or os.environ.get("DATABASE_URL") or DEFAULT_DSN
    host = _host_of(dsn)
    if host not in LOCAL_HOSTS:
        raise RuntimeError(
            f"Recusando conectar em host nao-local '{host}'. "
            f"Este projeto so opera na copia LOCAL do engine (127.0.0.1)."
        )
    conn = psycopg2.connect(dsn)
    conn.set_session(readonly=True, autocommit=True)
    return conn


def _dicts(conn, sql, params=None):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params or [])
        return cur.fetchall()


def load_series(conn, non_subordinated: bool = True, name_filter: str | None = None,
                methodology_priority: list[int] | None = None) -> list[Series]:
    prio = methodology_priority or PU_METHODOLOGY_PRIORITY
    params = {"prio": prio}
    filters = []
    if non_subordinated:
        filters.append("e.name NOT ILIKE %(sub)s")
        params["sub"] = "%SUBORDINATED%"
    if name_filter:
        filters.append("e.name ILIKE %(nm)s")
        params["nm"] = name_filter
    wsql = (" WHERE " + " AND ".join(filters)) if filters else ""
    # `pick`: 1 PU por serie = a metodologia de maior prioridade disponivel
    sql = f"""
        WITH pick AS (
            SELECT DISTINCT ON (v.asset_id)
                   v.asset_id,
                   v.date::date                                      AS pu_date,
                   v.methodology_id,
                   (v.clean_price + COALESCE(v.accrued_interest, 0)) AS pu_dirty
            FROM valuations v
            WHERE v.last_valuation_flag = TRUE
              AND v.methodology_id = ANY(%(prio)s)
            ORDER BY v.asset_id, array_position(%(prio)s::int[], v.methodology_id)
        )
        SELECT ss.id,
               e.name                AS name,
               idx.name              AS indexer,
               ss.indexer_percentage AS pct,
               ss.spread_over_indexer AS spread,
               ss.issuance_date,
               ss.maturity_date,
               ss.initial_price,
               ss.quantity,
               p.pu_date,
               p.pu_dirty,
               p.methodology_id,
               m.name                AS methodology
        FROM securitization_series ss
        JOIN entities   e   ON e.id  = ss.id
        JOIN indexers   idx ON idx.id = ss.indexer_id
        LEFT JOIN pick p ON p.asset_id = ss.id
        LEFT JOIN valuation_methodologies m ON m.id = p.methodology_id
        {wsql}
        ORDER BY e.name
    """
    out = []
    for r in _dicts(conn, sql, params):
        out.append(Series(
            id=r["id"], name=r["name"], indexer=r["indexer"],
            pct=float(r["pct"]) if r["pct"] is not None else 1.0,
            spread=float(r["spread"]) if r["spread"] is not None else 0.0,
            issuance_date=r["issuance_date"], maturity_date=r["maturity_date"],
            initial_price=float(r["initial_price"]) if r["initial_price"] is not None else None,
            quantity=float(r["quantity"]) if r["quantity"] is not None else 0.0,
            pu_date=r["pu_date"],
            pu_dirty=float(r["pu_dirty"]) if r["pu_dirty"] is not None else None,
            methodology_id=r["methodology_id"],
            methodology=r["methodology"],
        ))
    return out


def load_valuations(conn, series_ids: list[int],
                    methodology_priority: list[int] | None = None) -> dict[int, list[dict]]:
    """Historico de PU por serie (so metodologias de PU por unidade), ord. (data, id).

    Inclui methodology_id p/ o builder filtrar na metodologia escolhida da serie."""
    if not series_ids:
        return {}
    prio = methodology_priority or PU_METHODOLOGY_PRIORITY
    sql = """
        SELECT v.asset_id,
               v.date::date                                      AS d,
               v.id,
               v.methodology_id,
               (v.clean_price + COALESCE(v.accrued_interest, 0)) AS pu
        FROM valuations v
        WHERE v.asset_id = ANY(%(ids)s) AND v.clean_price > 0
          AND v.methodology_id = ANY(%(prio)s)
        ORDER BY v.asset_id, v.date, v.id
    """
    hist: dict[int, list[dict]] = {}
    for r in _dicts(conn, sql, {"ids": series_ids, "prio": prio}):
        hist.setdefault(r["asset_id"], []).append(
            {"d": r["d"], "id": r["id"], "pu": float(r["pu"]),
             "methodology_id": r["methodology_id"]}
        )
    return hist


def load_holidays(conn, calendar: str = "anbima") -> list[date]:
    rows = _dicts(conn, "SELECT date FROM holidays WHERE calendar = %s", [calendar])
    return [r["date"] for r in rows]


def load_di_curve(conn, asof: date) -> dict[int, float]:
    """Curva DI forward (DU -> taxa a.a.) na ultima data disponivel <= asof."""
    sql = """
        SELECT parameter::int AS du, value::float AS rate
        FROM curves
        WHERE curve_id = %s
          AND parameter ~ '^[0-9]+$'
          AND date = (SELECT max(date) FROM curves WHERE curve_id = %s AND date <= %s)
        ORDER BY du
    """
    rows = _dicts(conn, sql, [DI_CURVE_ID, DI_CURVE_ID, asof])
    return {r["du"]: r["rate"] for r in rows}


def max_valuation_date(conn) -> date:
    rows = _dicts(conn, "SELECT max(date)::date AS d FROM valuations WHERE last_valuation_flag = TRUE")
    return rows[0]["d"]
