-- V1: primeira position do CR-mae (aux ebc14760...) + primeiras linhas
SELECT p.position_date, p.amount, p.available,
       (p.holder_aux_id='ebc14760-1900-4ef9-8d7c-d4fa7429f2e0') AS cr_e_holder,
       (p.asset_aux_id='ebc14760-1900-4ef9-8d7c-d4fa7429f2e0')  AS cr_e_asset,
       hs.name AS holder_sec, as_s.name AS asset_sec
FROM positions p
LEFT JOIN securities hs   ON hs.aux_id = p.holder_aux_id
LEFT JOIN securities as_s ON as_s.aux_id = p.asset_aux_id
WHERE p.holder_aux_id='ebc14760-1900-4ef9-8d7c-d4fa7429f2e0'
   OR p.asset_aux_id ='ebc14760-1900-4ef9-8d7c-d4fa7429f2e0'
ORDER BY p.position_date, p.id
LIMIT 20
