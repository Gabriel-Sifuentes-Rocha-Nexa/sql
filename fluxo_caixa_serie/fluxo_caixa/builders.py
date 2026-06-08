"""
Construtores de fluxo de caixa por TIPO de serie.

Metodo central (validado): entre eventos de caixa o engine acretua o PU
exatamente na taxa contratual, entao levar o ultimo PU a valor futuro pela
taxa reproduz a mecanica do engine.

  factor_prefixado(spread, du) = (1+spread)^(du/252)
  factor_cdi(r,pct,spread,du)  = (1 + ((1+r)^(1/252)-1)*pct)^du * (1+spread)^(du/252)
  factor_usd(spread, dias360)  = (1+spread)^(dias360/360)   [+ FX, pendente]

Roteamento:
  bullet     -> BulletBuilder    : 1 resgate no vencimento = PU * factor * qtd
  amortizing -> AmortizingBuilder: realizado reconstruido dos degraus do PU +
                futuro projetado (declinio de saldo pela fracao observada, ou
                bullet como teto). Ver NOTA_AMORT.
  USD/IPCA   -> nao ha dado local; sai como 'unsupported' com nota.
"""
from __future__ import annotations

import statistics
from calendar import monthrange
from dataclasses import dataclass
from datetime import date
from typing import Optional

from .daycount import BusinessCalendar, day_count_360
from .model import CashFlow, Series
from .rates import ForwardRateProvider

NOTA_AMORT = (
    "futuro projetado: amortizacao do FGTS e' dirigida pelo lastro e nao e' "
    "caracteristica recuperavel da serie; aqui extrapola-se a fracao mensal "
    "observada no historico de PU (ajustavel)"
)

SUPPORTED_BRL = {"PREFIXADO", "CDI"}
SUPPORTED_USD = {"DOLLAR_PTAX", "SOFR"}


@dataclass
class BuildContext:
    cal: BusinessCalendar
    di: ForwardRateProvider          # curva DI forward (p/ CDI)
    asof: date
    history: dict                    # series_id -> [{'d','id','pu'}]
    strategy: str = "extrapolate"    # 'extrapolate' | 'bullet'
    drop_threshold: float = 0.005    # queda de PU que marca amortizacao


# ---------------------------------------------------------------- fatores ----
def factor_prefixado(spread: float, du: int) -> float:
    return (1.0 + spread) ** (du / 252.0)


def factor_cdi(r: float, pct: float, spread: float, du: int) -> float:
    daily = 1.0 + ((1.0 + r) ** (1.0 / 252.0) - 1.0) * pct
    return (daily ** du) * ((1.0 + spread) ** (du / 252.0))


def factor_usd(spread: float, dias360: int) -> float:
    return (1.0 + spread) ** (dias360 / 360.0)


def accrual(series: Series, d0: date, d1: date, ctx: BuildContext):
    """Retorna (factor, periodos, moeda) p/ acretuar de d0 ate d1."""
    if series.indexer == "PREFIXADO":
        du = ctx.cal.business_days(d0, d1)
        return factor_prefixado(series.spread, du), du, "BRL"
    if series.indexer == "CDI":
        du = ctx.cal.business_days(d0, d1)
        r = ctx.di.rate_for(du)
        return factor_cdi(r, series.pct, series.spread, du), du, "BRL"
    if series.indexer in SUPPORTED_USD:
        dd = day_count_360(d0, d1)
        return factor_usd(series.spread, dd), dd, "USD"
    raise ValueError(f"indexador nao suportado: {series.indexer}")


# ------------------------------------------------------------ classificacao ----
def _daily_pu(pu_history: list[dict], methodology_id) -> list[tuple]:
    """Serie diaria limpa: filtra a metodologia escolhida e colapsa 1 PU por data.

    O historico vem ordenado por (data, id); ao sobrescrever por data fica o
    ultimo id = PU oficial de fim de dia (pos-evento, se houver amortizacao)."""
    by_date: dict[date, float] = {}
    for r in pu_history:
        if methodology_id is None or r["methodology_id"] == methodology_id:
            by_date[r["d"]] = r["pu"]
    return sorted(by_date.items())


def classify(pu_history: list[dict], methodology_id, thr: float = 0.005) -> str:
    """'amortizing' se ha queda de PU dia-a-dia > thr (degrau de principal); senao 'bullet'."""
    daily = _daily_pu(pu_history, methodology_id)
    for (d0, p0), (d1, p1) in zip(daily, daily[1:]):
        if p0 > 0 and (p1 - p0) / p0 < -thr:
            return "amortizing"
    return "bullet"


def _realized_amortizations(pu_history: list[dict], methodology_id, thr: float):
    """Lista (data, fracao_do_saldo, pu_antes) p/ cada queda de PU no historico.

    Cada queda dia-a-dia = principal devolvido. A fracao netifica o accrual do
    dia (efeito pequeno), entao e' uma boa aproximacao do caixa distribuido."""
    daily = _daily_pu(pu_history, methodology_id)
    events = []
    for (d0, p0), (d1, p1) in zip(daily, daily[1:]):
        if p0 > 0 and (p1 - p0) / p0 < -thr:
            events.append((d1, (p0 - p1) / p0, p0))
    return events


def _add_month(d: date) -> date:
    y, m = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    return date(y, m, min(d.day, monthrange(y, m)[1]))


# -------------------------------------------------------------- builders ----
def build_bullet(series: Series, ctx: BuildContext) -> list[CashFlow]:
    factor, _, ccy = accrual(series, series.pu_date, series.maturity_date, ctx)
    amount = series.pu_dirty * factor * series.quantity
    return [CashFlow(series.id, series.name, series.indexer, "bullet",
                     series.maturity_date, amount, ccy, "redemption", True)]


def build_amortizing(series: Series, ctx: BuildContext) -> list[CashFlow]:
    hist = ctx.history.get(series.id, [])
    flows: list[CashFlow] = []
    ccy = "USD" if series.indexer in SUPPORTED_USD else "BRL"

    # 1) realizado: cada degrau do PU = caixa ja distribuido (do proprio PU)
    events = _realized_amortizations(hist, series.methodology_id, ctx.drop_threshold)
    for d, frac, pu_before in events:
        flows.append(CashFlow(series.id, series.name, series.indexer, "amortizing",
                              d, frac * pu_before * series.quantity, ccy,
                              "amortization", False, "realizado (degrau de PU)"))

    # 2) futuro: projeta do ultimo PU ate o vencimento
    f_month = statistics.median([e[1] for e in events]) if events else 0.0
    if ctx.strategy == "bullet" or f_month <= 0:
        factor, _, ccy = accrual(series, series.pu_date, series.maturity_date, ctx)
        amount = series.pu_dirty * factor * series.quantity
        note = "teto bullet (ignora amortizacoes futuras)" if ctx.strategy == "bullet" else \
               "sem amortizacao observada -> tratado como bullet"
        flows.append(CashFlow(series.id, series.name, series.indexer, "amortizing",
                              series.maturity_date, amount, ccy, "redemption", True, note))
        return flows

    # declinio de saldo: a cada mes acretua e amortiza f_month do saldo
    outstanding = series.pu_dirty           # por unidade
    cur = series.pu_date
    guard = 0
    while guard < 600:
        guard += 1
        nxt = _add_month(cur)
        pay = min(nxt, series.maturity_date)
        factor, _, ccy = accrual(series, cur, pay, ctx)
        outstanding *= factor
        if pay >= series.maturity_date:
            flows.append(CashFlow(series.id, series.name, series.indexer, "amortizing",
                                  series.maturity_date, outstanding * series.quantity,
                                  ccy, "redemption", True, NOTA_AMORT))
            break
        amort = f_month * outstanding
        outstanding -= amort
        flows.append(CashFlow(series.id, series.name, series.indexer, "amortizing",
                              pay, amort * series.quantity, ccy, "amortization",
                              True, NOTA_AMORT))
        cur = pay
    return flows


def build_unsupported(series: Series, classification: str, reason: str) -> list[CashFlow]:
    return [CashFlow(series.id, series.name, series.indexer, "unsupported",
                     series.maturity_date, 0.0,
                     "USD" if series.indexer in SUPPORTED_USD else "BRL",
                     "none", True, reason)]


def build_series(series: Series, ctx: BuildContext) -> list[CashFlow]:
    """Roteia a serie p/ o builder certo e devolve seus fluxos."""
    if series.pu_dirty is None or series.pu_date is None:
        return build_unsupported(series, "unsupported", "sem PU (last_valuation_flag) p/ projetar")
    if series.indexer in SUPPORTED_USD:
        return build_unsupported(series, "unsupported",
                                 "USD: day-count 30/360 pronto, mas falta FX (exchange_rates) p/ converter")
    if series.indexer not in SUPPORTED_BRL:
        return build_unsupported(series, "unsupported",
                                 f"indexador {series.indexer}: sem dado local / precisa projecao de indice")

    classification = classify(ctx.history.get(series.id, []), series.methodology_id, ctx.drop_threshold)
    if classification == "amortizing":
        return build_amortizing(series, ctx)
    return build_bullet(series, ctx)
