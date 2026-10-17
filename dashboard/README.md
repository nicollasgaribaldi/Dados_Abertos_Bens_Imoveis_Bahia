# Dashboard Power BI

Arquivo: `bens_imoveis_ba.pbix` · Prints: [`prints/`](prints/)

O dashboard lê **somente o schema `dw`** (modelo estrela), em modo **Import**. Ele nunca toca na staging; a coerência do pipeline
fica assim: raw → landing → staging → DW → Power BI.

## 1. Conexão

1. Banco no ar e pipeline executado (veja o [README principal](../README.md)).
2. Power BI Desktop → **Obter dados → Banco de dados PostgreSQL**
   - Servidor: `localhost:5437` · Banco de dados: `dw_bens_imoveis` · Modo: **Importar**
   - Credenciais: **Banco de dados**, usuário e senha do seu `.env`.
3. Selecione as 6 tabelas do schema `dw`: `dw.fato_patrimonio_anual`, `dw.dim_tempo`, `dw.dim_imovel`, `dw.dim_municipio`,
   `dw.dim_orgao`, `dw.dim_destino` → **Carregar**.

## 2. Modelo

Na exibição de **Modelo**, confira (o Power BI costuma detectar sozinho pelas colunas `sk_*`):

| De (fato, N) | Para (dimensão, 1) | Direção |
|---|---|---|
| `fato_patrimonio_anual[sk_tempo]` | `dim_tempo[sk_tempo]` | Única |
| `fato_patrimonio_anual[sk_imovel]` | `dim_imovel[sk_imovel]` | Única |
| `fato_patrimonio_anual[sk_municipio]` | `dim_municipio[sk_municipio]` | Única |
| `fato_patrimonio_anual[sk_orgao]` | `dim_orgao[sk_orgao]` | Única |
| `fato_patrimonio_anual[sk_destino]` | `dim_destino[sk_destino]` | Única |

Ajustes:
- Oculte as colunas `sk_*` (botão direito → Ocultar na exibição de relatório).
- `dim_tempo[ano]`: **Resumir por = Não resumir**.
- `dim_municipio[localizacao_mapa]`: Categoria de dados = **Local**. `dim_municipio[municipio]`: Categoria = **Cidade**.
- Crie uma tabela vazia para as medidas: **Página Inicial → Inserir dados** → nome `_Medidas` → Carregar.

## 3. Medidas DAX

Regra de ouro: **`valor` é semiaditivo**. Cada imóvel aparece uma vez por exercício, então somar anos contaria o mesmo imóvel várias
vezes. Todas as medidas de estoque usam **o último exercício do contexto** (`[Ano Referência]`). Num gráfico por ano, cada ponto usa o
próprio ano; num cartão sem filtro, usa o ano mais recente (2026).

Crie na tabela `_Medidas` (**Nova medida**), uma por vez:

```dax
Ano Referência =
CALCULATE ( MAX ( dim_tempo[ano] ), fato_patrimonio_anual )
```

```dax
Valor Patrimônio =
VAR _ano = [Ano Referência]
RETURN
    CALCULATE (
        SUM ( fato_patrimonio_anual[valor] ),
        dim_tempo[ano] = _ano,
        fato_patrimonio_anual[fl_valor_atipico] = FALSE ()
    )
```

```dax
Imóveis =
VAR _ano = [Ano Referência]
RETURN
    CALCULATE ( DISTINCTCOUNT ( fato_patrimonio_anual[sk_imovel] ), dim_tempo[ano] = _ano )
```

```dax
Valor Mediano =
VAR _ano = [Ano Referência]
RETURN
    CALCULATE (
        MEDIAN ( fato_patrimonio_anual[valor] ),
        dim_tempo[ano] = _ano,
        fato_patrimonio_anual[fl_valor_invalido] = FALSE (),
        fato_patrimonio_anual[fl_valor_atipico] = FALSE ()
    )
```

```dax
Imóveis Sem Destinação =
CALCULATE ( [Imóveis], dim_destino[grupo_destino] = "Sem destinação" )
```

```dax
% Sem Destinação =
DIVIDE ( [Imóveis Sem Destinação], [Imóveis] )
```

```dax
Valor Potencial de Receita =
CALCULATE ( [Valor Patrimônio], dim_destino[grupo_destino] = "Alienação e outorga" )
```

```dax
Valor por m² =
VAR _ano = [Ano Referência]
VAR _validos =
    CALCULATETABLE (
        fato_patrimonio_anual,
        dim_tempo[ano] = _ano,
        fato_patrimonio_anual[fl_area_invalida] = FALSE (),
        fato_patrimonio_anual[fl_valor_invalido] = FALSE (),
        fato_patrimonio_anual[fl_valor_atipico] = FALSE ()
    )
RETURN
    DIVIDE (
        SUMX ( _validos, fato_patrimonio_anual[valor] ),
        SUMX ( _validos, fato_patrimonio_anual[area_m2] )
    )
```

```dax
Valor Ano Anterior =
VAR _ano = [Ano Referência]
RETURN
    CALCULATE (
        SUM ( fato_patrimonio_anual[valor] ),
        dim_tempo[ano] = _ano - 1,
        fato_patrimonio_anual[fl_valor_atipico] = FALSE ()
    )
```

```dax
Var % Anual =
DIVIDE ( [Valor Patrimônio] - [Valor Ano Anterior], [Valor Ano Anterior] )
```

```dax
% do Valor =
DIVIDE (
    [Valor Patrimônio],
    CALCULATE ( [Valor Patrimônio], ALLSELECTED ( dim_orgao ), ALLSELECTED ( dim_municipio ), ALLSELECTED ( dim_destino ) )
)
```

```dax
% Cadastro Completo =
DIVIDE (
    CALCULATE (
        [Imóveis],
        fato_patrimonio_anual[fl_area_invalida] = FALSE (),
        fato_patrimonio_anual[fl_valor_invalido] = FALSE ()
    ),
    [Imóveis]
)
```

Formatos: `Valor Patrimônio`, `Valor Mediano`, `Valor Potencial de Receita`, `Valor Ano Anterior` e `Valor por m²` → Moeda
(R$ Português (Brasil)), unidade **Automática** nos cartões. `% Sem Destinação`, `Var % Anual`, `% do Valor` e `% Cadastro Completo` →
Percentual com 1 casa decimal. `Imóveis` → Número inteiro com separador de milhar.

Conferência (exercício 2026, sem filtros): Valor Patrimônio ≈ **R$ 5,54 bi**, Imóveis = **6.477**, % Sem Destinação ≈ **91,1%**,
Valor Potencial de Receita ≈ **R$ 0,66 bi**. Os mesmos números saem de `sql/consultas_analiticas.sql`.

## 4. Páginas (roteiro do storytelling)

Filtro em **todas as páginas** (painel Filtros → Filtros em todas as páginas): `dim_tempo[periodo_monetario]` = **Real**.

**Página 1: "Visão geral"** (a manchete)
- Caixa de texto (título): *"R$ 5,5 bi em imóveis próprios, e 9 em cada 10 sem destinação registrada"*.
- 4 cartões: `Valor Patrimônio`, `Imóveis`, `% Sem Destinação`, `Valor Potencial de Receita`.
- Segmentação: `dim_tempo[ano]` (lista suspensa, seleção única, padrão 2026).
- Gráfico de linhas: eixo `dim_tempo[ano]`, valor `Valor Patrimônio` (desligue a interação da segmentação com este gráfico:
  Formatar → Editar interações).
- Gráfico de barras horizontais: `dim_orgao[area_governo]` × `Valor Patrimônio`, ordenado do maior para o menor.
- Rodapé (texto pequeno): *"Valores contábeis (depreciados) informados pela SAEB/SIMOV, não valor de mercado."*

**Página 2: "Onde estão"**
- Mapa (bolhas): Local = `dim_municipio[localizacao_mapa]`, Tamanho = `Valor Patrimônio`, Dica de ferramenta = `Imóveis`.
- Gráfico de colunas 100% empilhadas ou rosca: `dim_municipio[regiao]` × `Imóveis` e `Valor Patrimônio` (mostra 11% dos imóveis
  × 67% do valor em Salvador).
- Barras: top 10 `dim_municipio[municipio]` por `Valor Patrimônio` (filtro do visual: N superiores = 10).

**Página 3: "Destinação e receita"**
- Barras horizontais: `dim_orgao[area_governo]` × `% Sem Destinação` (formatação condicional: vermelho acima de 90%).
- Matriz: linhas `dim_orgao[area_governo]`, colunas `dim_destino[grupo_destino]`, valores `Imóveis`.
- Tabela: `dim_imovel[numero_patrimonio]`, `dim_imovel[endereco]`, `dim_municipio[municipio]`, `dim_destino[destino]`,
  `Valor Patrimônio`, com filtro do visual `dim_destino[grupo_destino]` = "Alienação e outorga", ordenada por valor.

**Página 4: "Qualidade do cadastro"** (mostra domínio técnico)
- Cartões: `% Cadastro Completo`, `Valor por m²`, `Valor Mediano`.
- Barras: `dim_orgao[area_governo]` × `% Cadastro Completo`.
- Caixa de texto com os tratamentos: JSON reparado (190.544 registros), moeda pré-Real (1992-1993) separada, pico de digitação de
  2023 (imóvel 8368) marcado como atípico, 5.663 registros sem área.

Tema sugerido: Exibir → Temas → **Executivo** (ou cores sóbrias, azul para valores e vermelho só para alertas).

## 5. Prints para o repositório

Salve em `dashboard/prints/` (Arquivo → Exportar → PDF ou Ferramenta de Captura do Windows, `Win+Shift+S`):

1. `01_visao_geral.png`: página 1 inteira.
2. `02_onde_estao.png`: página 2 com o mapa.
3. `03_destinacao.png`: página 3.
4. `04_qualidade.png`: página 4.
5. `05_modelo.png`: exibição de Modelo mostrando a estrela (fato no centro, 5 dimensões).
