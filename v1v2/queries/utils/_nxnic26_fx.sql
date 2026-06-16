-- PTAX USD/BRL no dia 0 (2025-03-14) e proximo ao vencimento (2026-03-16)
SELECT
    er.date,
    num.name  AS numerator,
    den.name  AS denominator,
    er.value,
    vm.name   AS methodology
FROM exchange_rates er
JOIN entities num ON num.id = er.numerator_id
JOIN entities den ON den.id = er.denominator_id
LEFT JOIN valuation_methodologies vm ON vm.id = er.methodology_id
WHERE er.date::date IN ('2025-03-14','2025-03-13','2026-03-16','2026-03-13')
  AND (num.name ILIKE '%USD%' OR num.name ILIKE '%dol%' OR den.name ILIKE '%USD%' OR den.name ILIKE '%dol%')
ORDER BY er.date, num.name;
