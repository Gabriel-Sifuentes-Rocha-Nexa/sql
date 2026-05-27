-- Sanity check de conexão (read-only). Não depende de nenhuma tabela do schema.
SELECT
    current_database()  AS database,
    current_user        AS usuario,
    now()               AS agora;
