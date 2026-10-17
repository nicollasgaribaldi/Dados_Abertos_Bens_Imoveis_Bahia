# Dicionário de dados

## Fonte: `imoveisproprios.json`

Dicionário oficial em [`db_bensimoveis_ba/dicionario_dados_bens_imoveis.pdf`](../db_bensimoveis_ba/dicionario_dados_bens_imoveis.pdf).
A coluna "Observado" registra o que a análise encontrou na base de 17/10/2026 (190.544 registros).

| Campo | Tipo | Descrição oficial | Observado |
|---|---|---|---|
| `NumeroPatrimonio` | inteiro | Número de identificação patrimonial | 6.809 imóveis distintos |
| `Exercicio` | inteiro | "Ano de cadastro do imóvel" | **Na prática é o ano de referência do valor**: cada imóvel aparece uma vez por exercício (1992 a 2026) |
| `Valor` | decimal | Valor monetário do bem | Valor contábil, depreciado cerca de 5% ao ano. 1992 e 1993 em moeda pré-Real; 334 zeros, 1 negativo, 1 pico de digitação (imóvel 8368 em 2023) |
| `Dimensoes` | decimal | Medida física (área em m²) | 356 vazios e 5.307 zeros |
| `Endereco` | texto | Bairro, rua e número | Vírgula inicial, espaços repetidos, 17 vazios |
| `OrgaoGestor` | texto | Órgão responsável | 33 órgãos; 49 registros com espaço duplo |
| `Destino` | texto | Finalidade ou situação | 6 valores; 91% "Não definido" no último exercício |
| `Municipio` | texto | Município | 417 municípios; preenchido com espaços até 30 caracteres |

## Data Warehouse (schema `dw`)

### `fato_patrimonio_anual`: 1 linha por imóvel por exercício
| Coluna | Descrição |
|---|---|
| `sk_imovel`, `sk_tempo` | Chave primária composta; FKs para `dim_imovel` e `dim_tempo` |
| `sk_municipio`, `sk_orgao`, `sk_destino` | FKs: situação do imóvel **naquele exercício** |
| `valor` | Valor contábil no exercício (R$; moeda antiga em 1992-1993). **Semiaditivo** |
| `area_m2` | Área informada no exercício (nula quando vazia na fonte) |
| `fl_valor_invalido` | `valor` nulo ou <= 0 |
| `fl_area_invalida` | `area_m2` nula ou <= 0 |
| `fl_valor_atipico` | Pico isolado: >= 100 vezes o exercício seguinte (e o anterior, se houver), fora do pré-Real |

### `dim_tempo`
| Coluna | Descrição |
|---|---|
| `ano` | Exercício |
| `decada` | Ex.: `2020s` |
| `periodo_monetario` | `Pré-Real` (1992-1993) ou `Real` |
| `fl_moeda_pre_real` | Verdadeiro em 1992-1993 |
| `fl_ultimo_ano` | Verdadeiro no exercício mais recente da carga |

### `dim_imovel`
| Coluna | Descrição |
|---|---|
| `numero_patrimonio` | Chave natural |
| `endereco`, `area_m2_atual` | Do exercício mais recente (SCD tipo 1) |
| `primeiro_exercicio`, `ultimo_exercicio` | Primeiro e último ano em que aparece |
| `fl_ativo_ultimo_ano` | Aparece no exercício mais recente? (332 imóveis saíram do cadastro) |

### `dim_municipio`
| Coluna | Descrição |
|---|---|
| `municipio` | Nome padronizado (caixa alta, sem espaços extras) |
| `uf` | `BA` |
| `localizacao_mapa` | `"<MUNICÍPIO>, Bahia, Brasil"` para geocodificação do mapa no Power BI |
| `fl_capital` | Salvador |
| `fl_regiao_metropolitana` | 13 municípios da Região Metropolitana de Salvador |
| `regiao` | `Salvador`, `RMS (sem Salvador)` ou `Interior` |

### `dim_orgao`
| Coluna | Descrição |
|---|---|
| `orgao_gestor` | Nome padronizado |
| `area_governo` | Educação, Saúde, Segurança Pública, Agricultura e Meio Ambiente, Social, Cultura e Esporte, Infraestrutura e Desenvolvimento, Gestão e Fazenda |

### `dim_destino`
| Coluna | Descrição |
|---|---|
| `destino` | Valor original da fonte |
| `grupo_destino` | `Sem destinação` (Não definido), `Em uso` (Uso), `Alienação e outorga` (Alienação, Projeto de alienação, Arrematado/leilão, Outorgada à empresa) |
