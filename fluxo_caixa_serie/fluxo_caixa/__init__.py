"""
Fluxo de caixa pela CARACTERISTICA DA SERIE (nao pelo lastro).

Pega o ultimo PU de cada serie e leva a valor futuro ate o vencimento pela
taxa contratual. Bullet exato p/ series sem amortizacao; amortizantes (FGTS)
tem o realizado reconstruido do PU e o futuro projetado (ver builders).

Conexao SEMPRE local (engine em 127.0.0.1) e read-only. Nunca toca prod.
"""

__all__ = ["db", "daycount", "rates", "model", "builders", "engine"]
