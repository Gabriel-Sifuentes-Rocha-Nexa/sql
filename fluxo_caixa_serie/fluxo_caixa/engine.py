"""
Orquestra: carrega series + historico + calendario + curva DI, roteia cada
serie ao builder e devolve um DataFrame com todos os fluxos.
"""
from __future__ import annotations

from datetime import date
from typing import Optional

import pandas as pd

from . import db
from .builders import BuildContext, build_series
from .daycount import BusinessCalendar
from .rates import CurveForwardProvider


def build_context(conn, series, asof: Optional[date], calendar: str,
                  strategy: str, drop_threshold: float) -> BuildContext:
    ids = [s.id for s in series]
    history = db.load_valuations(conn, ids)
    cal = BusinessCalendar(db.load_holidays(conn, calendar))
    if asof is None:
        asof = max((s.pu_date for s in series if s.pu_date), default=db.max_valuation_date(conn))
    di = CurveForwardProvider(db.load_di_curve(conn, asof))
    return BuildContext(cal=cal, di=di, asof=asof, history=history,
                        strategy=strategy, drop_threshold=drop_threshold)


def build_all(conn, *, asof: Optional[date] = None, calendar: str = "anbima",
              strategy: str = "extrapolate", non_subordinated: bool = True,
              name_filter: Optional[str] = None, drop_threshold: float = 0.005) -> pd.DataFrame:
    series = db.load_series(conn, non_subordinated=non_subordinated, name_filter=name_filter)
    ctx = build_context(conn, series, asof, calendar, strategy, drop_threshold)
    rows = []
    for s in series:
        for cf in build_series(s, ctx):
            row = cf.as_row()
            row["methodology"] = s.methodology
            rows.append(row)
    df = pd.DataFrame(rows)
    if not df.empty:
        df = df.sort_values(["series_name", "date"]).reset_index(drop=True)
    return df


def summary_by_month(df: pd.DataFrame) -> pd.DataFrame:
    """Fluxo PROJETADO agregado por mes e moeda (ignora realizado e unsupported)."""
    proj = df[(df["is_projected"]) & (df["classification"] != "unsupported")]
    if proj.empty:
        return proj
    g = (proj.groupby(["month", "currency"], as_index=False)["amount"]
              .sum().sort_values(["month", "currency"]))
    return g
