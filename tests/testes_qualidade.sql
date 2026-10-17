-- =====================================================================
-- Testes de qualidade de dados do pipeline
-- Convenção: cada teste é uma consulta que retorna as LINHAS COM PROBLEMA.
-- "-- teste:"  integridade do pipeline: aprovado = 0 linhas (falha derruba a execução).
-- "-- alerta:"  problema da FONTE, conhecido e tratado com flag: só é reportado.
-- Rodados por tests/rodar_testes.py.
-- =====================================================================

-- teste: stg_sem_duplicidade_imovel_exercicio
SELECT numero_patrimonio, exercicio, count(*)
FROM stg.bens_imoveis
GROUP BY 1, 2
HAVING count(*) > 1;

-- teste: fato_mesmo_numero_de_linhas_da_staging
SELECT s.qtd AS stg, f.qtd AS fato
FROM (SELECT count(*) AS qtd FROM stg.bens_imoveis) s,
     (SELECT count(*) AS qtd FROM dw.fato_patrimonio_anual) f
WHERE s.qtd <> f.qtd;

-- teste: fato_mesmo_valor_total_da_staging
SELECT s.total AS stg, f.total AS fato
FROM (SELECT coalesce(sum(valor), 0) AS total FROM stg.bens_imoveis) s,
     (SELECT coalesce(sum(valor), 0) AS total FROM dw.fato_patrimonio_anual) f
WHERE s.total <> f.total;

-- teste: fato_sem_chave_orfa
SELECT f.*
FROM dw.fato_patrimonio_anual f
LEFT JOIN dw.dim_imovel    i USING (sk_imovel)
LEFT JOIN dw.dim_tempo     t USING (sk_tempo)
LEFT JOIN dw.dim_municipio m USING (sk_municipio)
LEFT JOIN dw.dim_orgao     o USING (sk_orgao)
LEFT JOIN dw.dim_destino   d USING (sk_destino)
WHERE i.sk_imovel IS NULL OR t.sk_tempo IS NULL OR m.sk_municipio IS NULL
   OR o.sk_orgao IS NULL OR d.sk_destino IS NULL;

-- teste: dim_imovel_um_registro_por_patrimonio
SELECT s.qtd AS stg, d.qtd AS dim
FROM (SELECT count(DISTINCT numero_patrimonio) AS qtd FROM stg.bens_imoveis) s,
     (SELECT count(*) AS qtd FROM dw.dim_imovel) d
WHERE s.qtd <> d.qtd;

-- teste: textos_sem_espacos_sobrando
SELECT 'municipio' AS coluna, municipio AS valor FROM dw.dim_municipio
WHERE municipio <> btrim(municipio) OR municipio ~ '\s{2,}'
UNION ALL
SELECT 'orgao_gestor', orgao_gestor FROM dw.dim_orgao
WHERE orgao_gestor <> btrim(orgao_gestor) OR orgao_gestor ~ '\s{2,}';

-- teste: destino_no_dominio_conhecido
SELECT destino, grupo_destino
FROM dw.dim_destino
WHERE grupo_destino = 'Outros';

-- teste: exercicio_em_faixa_valida
SELECT ano FROM dw.dim_tempo
WHERE ano < 1990 OR ano > extract(year FROM current_date);

-- teste: dim_tempo_sem_buracos
SELECT ano + 1 AS ano_faltando
FROM dw.dim_tempo t
WHERE ano < (SELECT max(ano) FROM dw.dim_tempo)
  AND NOT EXISTS (SELECT 1 FROM dw.dim_tempo t2 WHERE t2.ano = t.ano + 1);

-- teste: apenas_um_ultimo_ano
SELECT count(*) FROM dw.dim_tempo WHERE fl_ultimo_ano HAVING count(*) <> 1;

-- teste: flag_valor_invalido_coerente
SELECT * FROM dw.fato_patrimonio_anual
WHERE fl_valor_invalido <> (valor IS NULL OR valor <= 0);

-- teste: flag_area_invalida_coerente
SELECT * FROM dw.fato_patrimonio_anual
WHERE fl_area_invalida <> (area_m2 IS NULL OR area_m2 <= 0);

-- alerta: valor_negativo_na_fonte
SELECT * FROM dw.fato_patrimonio_anual WHERE valor < 0;

-- alerta: valor_zerado_na_fonte
SELECT * FROM dw.fato_patrimonio_anual WHERE valor = 0;

-- alerta: area_nula_ou_zerada_na_fonte
SELECT * FROM dw.fato_patrimonio_anual WHERE fl_area_invalida;

-- alerta: imovel_trocou_de_orgao_gestor
SELECT sk_imovel FROM dw.fato_patrimonio_anual
GROUP BY sk_imovel HAVING count(DISTINCT sk_orgao) > 1;

-- alerta: valor_atipico_pico_isolado
SELECT * FROM dw.fato_patrimonio_anual WHERE fl_valor_atipico;

-- alerta: valores_em_moeda_pre_real
SELECT f.* FROM dw.fato_patrimonio_anual f JOIN dw.dim_tempo t USING (sk_tempo)
WHERE t.fl_moeda_pre_real;
