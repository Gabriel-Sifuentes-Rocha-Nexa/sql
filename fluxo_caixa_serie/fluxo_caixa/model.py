"""Estruturas de dados: Series (caracteristicas + ultimo PU) e CashFlow."""
from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import date
from typing import Optional


@dataclass
class Series:
    id: int
    name: str
    indexer: str            # PREFIXADO | CDI | DOLLAR_PTAX | SOFR | IPCA | ...
    pct: float              # % do indexador (1.0 = 100%)
    spread: float           # taxa (prefixado) ou spread sobre o indexador (pos)
    issuance_date: date
    maturity_date: date
    initial_price: Optional[float]
    quantity: float
    pu_date: Optional[date]    # data do ultimo PU (last_valuation_flag)
    pu_dirty: Optional[float]  # PU sujo = clean_price + accrued_interest
    methodology_id: Optional[int] = None    # metodologia de valuation escolhida
    methodology: Optional[str] = None       # nome (ex.: amortized_cost, pu_nexa)


@dataclass
class CashFlow:
    series_id: int
    series_name: str
    indexer: str
    classification: str     # bullet | amortizing | unsupported
    date: date
    amount: float           # valor total do evento (PU * quantidade)
    currency: str           # BRL | USD
    kind: str               # amortization | redemption | none
    is_projected: bool      # True = projetado p/ frente; False = realizado (do PU)
    note: str = ""

    def as_row(self) -> dict:
        d = asdict(self)
        d["month"] = self.date.strftime("%Y-%m") if self.date else None
        return d
