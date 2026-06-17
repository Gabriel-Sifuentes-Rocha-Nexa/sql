-- NXCOF25-2 (1938) anomalias em valuations: total, #vigentes, metodologias, range, pos-0602, clean<0, eventos cf
SELECT
  count(*) AS total,
  count(*) FILTER (WHERE last_valuation_flag) AS n_vigentes,
  count(DISTINCT methodology_id) AS n_meth,
  min(date)::text AS mind, max(date)::text AS maxd,
  count(*) FILTER (WHERE date::date > '2025-06-02') AS apos_0602,
  count(*) FILTER (WHERE clean_price < 0) AS n_clean_neg,
  count(*) FILTER (WHERE cash_flow <> 0) AS n_cf_events,
  count(*) FILTER (WHERE date IS NULL) AS n_date_null
FROM valuations WHERE asset_id=1938
