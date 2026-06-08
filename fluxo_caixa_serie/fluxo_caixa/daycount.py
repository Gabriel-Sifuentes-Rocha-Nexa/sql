"""
Contagem de dias para accrual.

  - DU 252 (Brasil): dias uteis no intervalo (start, end], calendario anbima/b3
    montado a partir da tabela `holidays`. Equivalente exato ao
    generate_series(start+1, end) filtrando fim de semana e feriados que a
    query SQL usa (validado em validate.py).
  - 30/360 (US/NASD): aritmetica pura de data, p/ papeis em USD.
"""
from __future__ import annotations

from datetime import date

import numpy as np


class BusinessCalendar:
    def __init__(self, holidays):
        self._holidays = np.array(sorted(set(holidays)), dtype="datetime64[D]")

    def is_business_day(self, d: date) -> bool:
        return bool(np.is_busday(np.datetime64(d, "D"), holidays=self._holidays))

    def business_days(self, start: date, end: date) -> int:
        """Dias uteis no intervalo (start, end] (start exclusivo, end inclusive)."""
        if end <= start:
            return 0
        # busday_count conta [begin, end); usar (start+1, end+1) = (start, end]
        b = np.datetime64(start, "D") + 1
        e = np.datetime64(end, "D") + 1
        return int(np.busday_count(b, e, holidays=self._holidays))


def day_count_360(start: date, end: date) -> int:
    """Convencao 30/360 US/NASD."""
    d1, d2 = start.day, end.day
    d1 = min(d1, 30)
    if d1 == 30 and d2 == 31:
        d2 = 30
    return (end.year - start.year) * 360 + (end.month - start.month) * 30 + (d2 - d1)
