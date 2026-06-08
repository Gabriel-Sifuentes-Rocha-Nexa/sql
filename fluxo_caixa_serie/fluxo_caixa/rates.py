"""
Provedores de taxa forward.

  - FlatForwardProvider: taxa constante (fallback/teste).
  - CurveForwardProvider: curva zero por DU (base 252), interpolacao linear e
    extrapolacao flat nas pontas. Usado p/ projetar CDI a partir da curve_id=10
    (DI nominal forward) do engine.
"""
from __future__ import annotations

from bisect import bisect_left


class ForwardRateProvider:
    def rate_for(self, du: int) -> float:
        raise NotImplementedError


class FlatForwardProvider(ForwardRateProvider):
    def __init__(self, rate: float):
        self.rate = rate

    def rate_for(self, du: int) -> float:
        return self.rate


class CurveForwardProvider(ForwardRateProvider):
    def __init__(self, points: dict[int, float]):
        items = sorted((d, r) for d, r in points.items() if d > 0)
        self._du = [d for d, _ in items]
        self._r = [r for _, r in items]

    def is_empty(self) -> bool:
        return not self._du

    def rate_for(self, du: int) -> float:
        if not self._du:
            raise ValueError("curva DI vazia (curve_id=10 sem pontos)")
        if du <= self._du[0]:
            return self._r[0]
        if du >= self._du[-1]:
            return self._r[-1]
        i = bisect_left(self._du, du)
        d0, d1 = self._du[i - 1], self._du[i]
        r0, r1 = self._r[i - 1], self._r[i]
        w = (du - d0) / (d1 - d0)
        return r0 + w * (r1 - r0)
