-- =====================================================================
-- Consultas analíticas: respondem às perguntas de negócio no DW.
-- Lembrete: "valor" é semiaditivo -> sempre filtrar UM exercício
-- antes de somar (aqui, o mais recente: dim_tempo.fl_ultimo_ano).
-- =====================================================================

-- P1. Quanto vale o patrimônio hoje e com quem ele está? (por órgão)
SELECT o.area_governo, o.orgao_gestor,
       count(*)                           AS qtd_imoveis,
       round(sum(f.valor) / 1e6, 1)       AS valor_milhoes,
       round(100 * sum(f.valor) / sum(sum(f.valor)) OVER (), 1) AS pct_valor
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
JOIN dw.dim_orgao o USING (sk_orgao)
WHERE t.fl_ultimo_ano
GROUP BY 1, 2
ORDER BY valor_milhoes DESC;

-- P2. Onde estão os imóveis? Salvador x RMS x interior
SELECT CASE WHEN m.fl_capital THEN '1 Salvador'
            WHEN m.fl_regiao_metropolitana THEN '2 RMS (sem Salvador)'
            ELSE '3 Interior' END     AS regiao,
       count(*)                       AS qtd_imoveis,
       round(sum(f.valor) / 1e6, 1)   AS valor_milhoes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)        AS pct_qtd,
       round(100 * sum(f.valor) / sum(sum(f.valor)) OVER (), 1)  AS pct_valor
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
JOIN dw.dim_municipio m USING (sk_municipio)
WHERE t.fl_ultimo_ano
GROUP BY 1 ORDER BY 1;

-- P2b. Top 10 municípios por valor
SELECT m.municipio, count(*) AS qtd_imoveis, round(sum(f.valor) / 1e6, 1) AS valor_milhoes
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
JOIN dw.dim_municipio m USING (sk_municipio)
WHERE t.fl_ultimo_ano
GROUP BY 1 ORDER BY valor_milhoes DESC LIMIT 10;

-- P3. Os imóveis têm destinação definida?
SELECT d.grupo_destino, d.destino,
       count(*)                          AS qtd_imoveis,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_qtd,
       round(sum(f.valor) / 1e6, 1)      AS valor_milhoes
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
JOIN dw.dim_destino d USING (sk_destino)
WHERE t.fl_ultimo_ano
GROUP BY 1, 2 ORDER BY qtd_imoveis DESC;

-- P3b. "Sem destinação" por área de governo
SELECT o.area_governo,
       count(*) FILTER (WHERE d.grupo_destino = 'Sem destinação') AS sem_destinacao,
       count(*)                                                  AS total,
       round(100.0 * count(*) FILTER (WHERE d.grupo_destino = 'Sem destinação') / count(*), 1) AS pct_sem_destinacao
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
JOIN dw.dim_orgao o USING (sk_orgao)
JOIN dw.dim_destino d USING (sk_destino)
WHERE t.fl_ultimo_ano
GROUP BY 1 ORDER BY pct_sem_destinacao DESC;

-- P4. Patrimônio que pode virar receita (alienação, leilão, outorga)
SELECT d.destino, m.municipio, i.numero_patrimonio, i.endereco, f.valor
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
JOIN dw.dim_destino d USING (sk_destino)
JOIN dw.dim_municipio m USING (sk_municipio)
JOIN dw.dim_imovel i USING (sk_imovel)
WHERE t.fl_ultimo_ano AND d.grupo_destino = 'Alienação e outorga'
ORDER BY f.valor DESC;

-- P5. Evolução do valor total (somente período do Real)
SELECT t.ano, count(*) AS qtd_imoveis, round(sum(f.valor) / 1e9, 2) AS valor_bilhoes,
       round(100 * (sum(f.valor) / lag(sum(f.valor)) OVER (ORDER BY t.ano) - 1), 1) AS var_pct_ano
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
WHERE NOT t.fl_moeda_pre_real
GROUP BY t.ano ORDER BY t.ano;

-- P6. Valor por m² por município (áreas válidas, mínimo de 5 imóveis)
SELECT m.municipio, count(*) AS qtd_imoveis,
       round(sum(f.valor) / sum(f.area_m2), 2) AS valor_m2
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
JOIN dw.dim_municipio m USING (sk_municipio)
WHERE t.fl_ultimo_ano AND NOT f.fl_area_invalida AND NOT f.fl_valor_invalido
GROUP BY 1 HAVING count(*) >= 5
ORDER BY valor_m2 DESC LIMIT 15;

-- P7. Qualidade do cadastro no último exercício
SELECT count(*)                                         AS imoveis,
       count(*) FILTER (WHERE f.fl_area_invalida)       AS sem_area,
       count(*) FILTER (WHERE f.fl_valor_invalido)      AS sem_valor,
       round(100.0 * count(*) FILTER (WHERE NOT f.fl_area_invalida AND NOT f.fl_valor_invalido) / count(*), 1)
                                                        AS pct_cadastro_completo
FROM dw.fato_patrimonio_anual f
JOIN dw.dim_tempo t USING (sk_tempo)
WHERE t.fl_ultimo_ano;
