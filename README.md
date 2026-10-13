# SINAN Territórios: Hanseníase – Pernambuco — versão de demonstração

> ⚠️ **Atenção**
>
> **DADOS FICTÍCIOS.** Esta é uma vitrine do painel, com dados do SINAN **inteiramente fictícios**. Nenhum caso, nome, endereço, data ou coordenada corresponde a uma pessoa real. A versão de produção roda com dados sigilosos de pacientes, em ambiente seguro da Secretaria de Saúde, e não é distribuída aqui. Veja [como os dados fictícios foram gerados](#2-dados-fictícios).

### [▶ Ver o painel ao vivo](https://dev-cenarios.github.io/SINAN_Territorios_Pernambuco_Hansen/)

O painel roda inteiro no seu navegador, com os dados fictícios, sem instalar nada. A primeira abertura leva de 30 segundos a pouco mais de um minuto, conforme a conexão — o navegador baixa o R e os pacotes —, e as seguintes são mais rápidas. Funciona melhor num computador; em celulares mais simples pode ficar lento ([como é feito](#67-versão-web-github-pages)).

Painel de vigilância epidemiológica de hanseníase do estado de Pernambuco, construído em R/Shiny com o framework [`golem`](https://engineering-shiny.org/). O painel consolida as notificações de hanseníase do SINAN. Gestores e equipes de vigilância acompanham num só lugar os casos novos, a taxa de detecção por município e por GERES, o diagnóstico tardio (grau 2 de incapacidade), a transmissão recente (casos em menores de 15 anos), os desfechos do tratamento e o exame de contatos. Há filtros por período, perfil demográfico e características clínicas.

> O painel foi derivado do [SINAN Territórios: Recife-PE](https://github.com/Dev-Cenarios/SINAN_Territorios_Recife_PE_TB) ([painel ao vivo](https://dev-cenarios.github.io/SINAN_Territorios_Recife_PE_TB/)), de tuberculose, e reaproveita a arquitetura, a identidade visual e as otimizações de desempenho dele.

## Sobre o Projeto

O Programa Cenários, coordenado pelo Prof. Dr. Walter Massa Ramalho da Universidade de Brasília (UnB), é uma iniciativa científica e tecnológica que reúne pesquisadores, gestores de saúde e parceiros nacionais e internacionais para desenvolver soluções inovadoras no enfrentamento de doenças determinadas socialmente. O programa tem dois eixos de pesquisa: Tuberculose e Hanseníase.

### Hanseníase – Modelagem de Cenários de Risco

Cenários Hanseníase tem como objetivo identificar áreas de risco e cadeias invisíveis de transmissão da hanseníase no Brasil, com foco especial nas regiões metropolitanas de Brasília (DF), Recife (PE), Palmas (TO) e demais capitais. A proposta integra inteligência artificial generativa, georreferenciamento por setores censitários e rastreamento de contatos. Os resultados incluem um dashboard nacional, algoritmos de análise espacial e temporal, e relatórios técnicos para subsidiar ações estratégicas do SUS, com foco na redução de desigualdades e modernização da vigilância.

Este painel — o **SINAN Territórios: Hanseníase – Pernambuco** — é uma das entregas do eixo Hanseníase, com estratificação territorial por município e por Gerência Regional de Saúde (GERES).

[Saiba mais sobre o projeto!](https://cenarios.unb.br/hanseniase-modelagem-de-cenarios-de-risco/)

## Sumário

1. [Funcionalidades](#1-funcionalidades)
2. [Dados fictícios](#2-dados-fictícios)
3. [Estrutura do projeto](#3-estrutura-do-projeto)
4. [Fontes de dados](#4-fontes-de-dados)
5. [Tecnologias e pré-requisitos](#5-tecnologias-e-pré-requisitos)
6. [Como rodar](#6-como-rodar)
7. [Troubleshooting](#7-troubleshooting)
8. [Desenvolvedores](#8-desenvolvedores)
9. [Licença](#licença)

## 1. Funcionalidades

- **Cards de indicadores**: casos novos, paucibacilares, multibacilares, casos novos em menores de 15 anos, grau 2 de incapacidade física no diagnóstico, em tratamento, curados, abandono, proporção de contatos examinados e proporção de casos novos com o grau de incapacidade avaliado no diagnóstico. Todos são recalculados de acordo com os filtros ativos e com o município selecionado no mapa. Os cards de paucibacilares, multibacilares, em tratamento e grau de incapacidade avaliado têm atalhos que filtram o painel para esses casos (no último, os não avaliados), cada um na cor do seu card. ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#1-cards-de-indicadores-topo-do-painel))
- **Mapa de casos**:
  - Pontos georreferenciados de cada notificação, coloridos pelo desfecho.
  - Camada de indicador por **município** (185) ou por **GERES** (12). O indicador padrão é a **taxa de detecção** de casos novos por 100 mil habitantes/ano, com a população do Censo 2022.
  - Outros indicadores: taxa de detecção em menores de 15 anos, proporção de multibacilares e paucibacilares, grau 2 de incapacidade no diagnóstico, grau de incapacidade avaliado no diagnóstico, proporção de cura, proporção de abandono e contatos examinados.
  - As cores seguem as classes de endemicidade e de qualidade do Ministério da Saúde.
  - O contorno das GERES fica numa camada própria.
  - **Clique num município** (ou numa GERES, no recorte por GERES): os cards, a distribuição dos desfechos, os casos no mapa e a tabela passam a mostrar só os residentes dele, e o mapa se enquadra nele. O botão "Ver todo o estado", na coluna da esquerda, volta para Pernambuco.
  - **Fernando de Noronha** aparece num quadro de detalhe no mar, a leste do Recife, ampliado 4 vezes. No mapa real ele fica a ~550 km da costa, fora do enquadramento do estado.
  - Camadas de unidades de saúde do CNES: a **rede SUS** (UBS/USF, postos, policlínicas, hospitais públicos, UPA, CAPS), marcada com um "S" vermelho, e as **outras unidades notificadoras**, com "✕". Com o mapa afastado, as unidades próximas se juntam num círculo com o total, que se desfaz ao aproximar. O hover mostra quantos casos cada unidade notificou no período. As duas camadas começam desligadas; ligue no controle de camadas do mapa.
  - ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#2-mapa-de-casos))
- **Tabela de casos**: lista pesquisável das notificações filtradas, com acesso à ficha completa do caso pelo número de notificação. ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#3-tabela-de-casos))
- **Filtros**: período (data de diagnóstico), sexo, idade, raça/cor, modo de entrada, modo de detecção, baciloscopia, classificação operacional, forma clínica, grau de incapacidade no diagnóstico e desfecho. O período abre no ano mais recente da base, até a última data de diagnóstico. ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#4-filtros))
- **Aviso de dados fictícios** — exclusivo desta vitrine: selo no cabeçalho, faixa no topo da página, aviso ao abrir o painel, selo no mapa e na ficha de cada caso. Somem sozinhos quando o painel roda com dados reais ([6.5](#65-rodar-com-dados-reais)). Na versão de produção, no lugar do selo do cabeçalho fica o botão administrativo "Atualizar dados", que reprocessa a base a partir do banco de origem.

Para a metodologia completa por trás de cada número exibido, veja a **[Documentação de Gráficos](docs/DOCUMENTACAO_GRAFICOS.md)**.

## 2. Dados fictícios

O painel lê a base de casos no mesmo formato da produção — a saída da pipeline de georreferenciamento do projeto —, mas aqui gerada por simulação:

| Arquivo | Conteúdo | Registros |
|---|---|---|
| [`inst/extdata/dados_ficticios/sinan_hanseniase_pe_ficticio.csv`](inst/extdata/dados_ficticios/sinan_hanseniase_pe_ficticio.csv) | Casos de hanseníase no formato do SINAN (só as colunas que o painel usa), com as colunas `GEORREFERENCIADO`, `INDICADOR` e `LATITUDE`/`LONGITUDE` da pipeline de georreferenciamento | 25.935 casos, diagnosticados de 2016 a 20/11/2025 |

**Como foram gerados** ([`dev/gerar_dados_ficticios.R`](dev/gerar_dados_ficticios.R), semente fixa): cada caso é sorteado — datas, sexo, idade, raça/cor, escolaridade, classificação operacional, forma clínica, baciloscopia, esquema terapêutico, grau de incapacidade, lesões e nervos afetados, contatos registrados e examinados, modo de entrada e de detecção, desfecho, município de residência e de notificação, e unidade notificadora. O nome é sempre `PACIENTE FICTÍCIO 00001`, `00002`…, o endereço é sempre uma `RUA FICTÍCIA …` (ou `UNIDADE PRISIONAL FICTÍCIA` / `SEM ENDEREÇO FIXO (FICTÍCIO)`), o bairro é `BAIRRO FICTÍCIO`, e o número de notificação tem 8 dígitos começando por 99 (os do SINAN têm 7, então nunca coincidem com uma notificação real). As associações entre as variáveis são simplificadas (por exemplo, forma clínica, baciloscopia e grau de incapacidade conforme a classificação operacional, e tempo de tratamento de ~6 meses nos paucibacilares e ~12 nos multibacilares) e não devem ser lidas como achados epidemiológicos.

**O que vem da realidade**: só ordens de grandeza agregadas, para o painel se comportar como o de produção — nenhum registro da base real foi copiado. São elas:
- o total de casos por ano e as proporções gerais (sexo, faixa etária, raça/cor, classificação operacional, forma clínica, grau de incapacidade, modo de entrada e de detecção, desfechos, contatos examinados), arredondados;
- a taxa média anual de detecção de casos novos por 100 mil habitantes de cada município, com **ruído aleatório de ~15%** e arredondada ([`parametros_municipios.csv`](inst/extdata/dados_ficticios/parametros_municipios.csv)) — define só o peso relativo de cada município no sorteio.

**Unidade notificadora e coordenada**: não usam nenhum dado de caso real. A unidade é sorteada entre as do cadastro público no município de notificação — 65% na atenção primária (UBS/USF, posto de saúde) e o resto numa unidade de referência sorteada pelo tipo (hospital, policlínica, centro de especialidade, unidade mista, UPA), com pesos que são hipóteses da simulação. Por isso, o número de casos que cada unidade "notificou" no painel não diz nada sobre a unidade real. A coordenada fica perto de uma unidade de atenção primária do município de residência — um indicador público de onde mora gente —, com deslocamento aleatório de algumas centenas de metros, ou num ponto qualquer do município.

O resultado reproduz a ordem de grandeza dos indicadores de Pernambuco — de 1.900 a 3.400 casos por ano e taxa de detecção de ~20 casos novos por 100 mil habitantes/ano —, mas **os números não devem ser usados para análise ou tomada de decisão**.

O cadastro das unidades de saúde ([`unidades_cnes.rds`](inst/extdata/dados_ficticios/unidades_cnes.rds)) é público: API do CNES/DATASUS e camada da rede de saúde da Prefeitura do Recife (ver [Fontes de dados](#4-fontes-de-dados)). Ele traz só dados cadastrais (nome, tipo, natureza jurídica, município, coordenada), sem nenhuma contagem de casos.

Os avisos de dados fictícios aparecem sempre que a base carregada é a fictícia, e somem sozinhos quando o painel roda com dados reais — ver [6.5](#65-rodar-com-dados-reais).

## 3. Estrutura do projeto

```text
.
├── R/
│   ├── app_ui.R                 # Interface: cabeçalho, faixa e selo de dados fictícios, layout geral
│   ├── app_server.R             # Servidor raiz: confere a base e mostra o aviso de dados fictícios ao abrir
│   ├── app_config.R             # Acesso a arquivos internos do pacote e ao golem-config.yml
│   ├── mod_municipio.R          # Módulo principal: cards, mapa, tabela de casos, filtros
│   ├── fct_casos.R              # Carga dos casos e das malhas, compartilhada entre sessões
│   ├── fct_db_update.R          # Fonte dos dados (fictícios ou reais) e montagem da base local (DuckDB + cache)
│   ├── utils_app_theme.R        # Paleta de cores do painel (tema fresh)
│   ├── golem_utils_*.R          # Utilitários genéricos do golem
│   └── run_app.R                # Função exportada que inicia o Shiny
├── inst/
│   ├── golem-config.yml
│   ├── extdata/
│   │   └── dados_ficticios/     # Base fictícia, parâmetros da simulação e cadastro de unidades
│   └── app/
│       ├── badges_inline.css    # CSS (cores dos cards, navbar, avisos) injetado inline
│       └── www/                 # Logo, favicon
│           └── shapes/
│               ├── municipios_pe.gpkg  # 185 municípios + GERES + população (Censo 2022)
│               └── geres_pe.gpkg       # 12 GERES + população
├── dev/
│   ├── gerar_dados_ficticios.R  # Gera a base fictícia desta vitrine
│   ├── build_shinylive.R        # Gera a versão web (Shinylive) publicada no GitHub Pages
│   ├── build_malhas_pe.R        # Gera as duas malhas acima (geobr + SIDRA/IBGE)
│   ├── build_unidades_cnes.R    # Gera a camada de unidades de saúde (API do CNES + SESAU Recife)
│   └── 01_start.R, 02_dev.R, …  # Scripts padrão do golem
├── docs/
│   └── DOCUMENTACAO_GRAFICOS.md # Metodologia de cada card, indicador e filtro
├── tests/                       # Testes (testthat)
├── app.R                        # Ponto de entrada do Shiny
└── DESCRIPTION, NAMESPACE
```

> A pasta `local/` não é versionada: o painel a cria sozinho na primeira abertura, com a base DuckDB (`sinan.duckdb`) montada a partir do CSV fictício (ou do real, ver [6.5](#65-rodar-com-dados-reais)), o registro da origem da base (`fonte_dados.rds`), o cache dos casos (`casos_cache.rds`) e o cadastro das unidades de saúde (`unidades_cnes.rds`).

## 4. Fontes de dados

- **SINAN – Hanseníase — fictício nesta vitrine** (ver [Dados fictícios](#2-dados-fictícios)). Na produção, as notificações do estado de Pernambuco chegam de um banco PostgreSQL interno, já georreferenciadas pela pipeline do projeto (com `GEORREFERENCIADO`, `INDICADOR` e `LATITUDE`/`LONGITUDE`).
  - O painel reprocessa os dados e os salva no **DuckDB** local (`local/sinan.duckdb`, tabela `hans_sinan_treated`) — é essa cópia que ele efetivamente lê, nas duas versões.
  - As categorias seguem o dicionário de dados do SINAN NET – Hanseníase ([detalhes](docs/DOCUMENTACAO_GRAFICOS.md)).
  - As datas são aceitas como texto `dd/mm/aaaa` (formato dos fictícios), `aaaa-mm-dd`, `aaaammdd` ou número de série do Excel (dias desde 30/12/1899), que é como a pipeline entrega quando o CSV passa por planilha. A montagem da base para, sem mexer no painel, se encontrar um formato de data que não reconhece.
  - **Não há linkage com o SIM**: o desfecho vem só do tipo de saída do SINAN (`TPALTA_N`).
- **Território**: o município de residência (`ID_MN_RESI`) e a sua GERES. Os indicadores por território não dependem do georreferenciamento.
- **IBGE**:
  - Malha municipal de 2022, via [`geobr`](https://github.com/ipeaGIT/geobr), na resolução original. Ela é simplificada uma vez, a 100 m, de um jeito que mantém a mesma divisa nos dois municípios vizinhos, sem abrir frestas entre eles. O contorno das GERES é a união dos municípios e cai exatamente sobre as divisas municipais.
  - População do Censo 2022 pela API do [SIDRA](https://sidra.ibge.gov.br/): tabela 4714 para a população total (9.058.931 habitantes) e tabela 9514 para os menores de 15 anos.
- **GERES**: regiões de saúde do Ministério da Saúde (2013), que em Pernambuco correspondem às 12 GERES da SES-PE.
- **Unidades de saúde**: [API pública do CNES/DATASUS](https://apidadosabertos.saude.gov.br/cnes/estabelecimentos) (coordenada, tipo, natureza jurídica, habilitação). Em Recife, a coordenada da rede municipal vem da camada oficial da SESAU no ESIG. "Pública" é definida pela natureza jurídica (1xxx, 2011, 2038), não pela esfera administrativa. Unidade sem coordenada no CNES, ou com coordenada fora do próprio município, vai para a sede do município, marcada como localização aproximada ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#25-unidades-de-saúde-camadas-rede-sus-s-e-outras-notificadoras-)). Nesta vitrine o cadastro vem pronto em `inst/extdata/dados_ficticios/unidades_cnes.rds`.
- **Dados sensíveis (produção)**: a base real contém dados pessoais de pacientes. Na produção, a base local e as credenciais de acesso ao banco de origem não são versionadas, e o painel roda atrás de autenticação institucional — com os cuidados da LGPD. Esta vitrine existe justamente para mostrar o painel sem expor esses dados.

## 5. Tecnologias e pré-requisitos

**Linguagem/framework**: R (4.4+) / Shiny, estruturado como pacote `golem`.

**Principais dependências** (lista completa em [`DESCRIPTION`](DESCRIPTION)): `bs4Dash`, `fresh`, `leaflet`, `sf`, `reactable`, `duckdb`, `DBI`, `shinyjs`, `shinyWidgets`, `shinytoastr`, `dplyr`, `tidyr`, `lubridate`, `stringi`. Os scripts de `dev/` usam também `geobr`, `httr2` e `pkgload`.

**Dependências de sistema (Linux)** — para compilar `sf`/`duckdb`: `libgdal-dev`, `libgeos-dev`, `libproj-dev`, `libudunits2-dev`, `libcurl4-openssl-dev`, `libssl-dev`, `libxml2-dev`. No Windows e no macOS, os binários do CRAN já trazem tudo.

**Pré-requisitos de ambiente**: nenhum banco de dados nem credencial — os dados fictícios vêm no repositório. O navegador de quem usa o painel precisa de internet para as fontes (Google Fonts) e os mapas de fundo (Esri).

## 6. Como rodar

### 6.1 Clonar o repositório

```bash
git clone https://github.com/Dev-Cenarios/SINAN_Territorios_Pernambuco_Hansen.git
cd SINAN_Territorios_Pernambuco_Hansen
```

### 6.2 Instalar as dependências

Com o R aberto na pasta do projeto (ou o `.Rproj` aberto no RStudio):

```r
install.packages(c(
  "attempt", "bs4Dash", "config", "DBI", "dplyr", "DT", "duckdb",
  "fresh", "glue", "golem", "htmltools", "htmlwidgets", "leaflet", "lubridate",
  "plotly", "purrr", "reactable", "scales", "sf", "shiny", "shinyjs",
  "shinyWidgets", "tibble", "tidyr", "shinytoastr", "stringi", "pkgload"
))
```

### 6.3 Rodar o painel

Na raiz do projeto:

```r
pkgload::load_all()
run_app()
```

Ou, com o projeto aberto no RStudio, abra o `app.R` e use o botão **"Run App"**.

Na primeira abertura, o painel cria a pasta `local/` e monta a base a partir do CSV fictício — leva alguns segundos e acontece uma vez só.

### 6.4 Regerar os dados fictícios

```bash
Rscript dev/gerar_dados_ficticios.R
```

Regrava o CSV em `inst/extdata/dados_ficticios/` (leva alguns segundos). Na próxima abertura, o painel percebe que o arquivo mudou e remonta a base sozinho. Para outra simulação, troque a semente (`set.seed`) ou os parâmetros no topo do script.

### 6.5 Rodar com dados reais

Sem configuração, o painel usa os dados fictícios e mostra os avisos. Para rodar com dados reais, defina a variável de ambiente `PAINEL_HANSEN_PE_DADOS_REAIS_DIR` com o caminho de uma pasta **fora do repositório** — por exemplo, no `.Renviron` do usuário que roda o painel no servidor:

```
PAINEL_HANSEN_PE_DADOS_REAIS_DIR=/caminho/seguro/dados_hanseniase_pe
```

A pasta deve ter o arquivo `sinan_hanseniase_pe.csv`, com as colunas de [`sinan_hanseniase_pe_ficticio.csv`](inst/extdata/dados_ficticios/sinan_hanseniase_pe_ficticio.csv) — é o formato da saída da pipeline de georreferenciamento; colunas a mais são ignoradas. Formato: UTF-8, separador `,` ou `;` (detectado sozinho), coordenadas com decimal `.` ou `,`, datas como na [seção 4](#4-fontes-de-dados) e códigos do SINAN como no dicionário de dados. O nome da variável é específico deste painel, para não colidir com outros painéis no mesmo servidor.

O que acontece:
- **Os avisos de dados fictícios somem sozinhos.** Eles não têm uma chave própria: dependem da origem da base que está carregada, registrada em `local/fonte_dados.rds`. Não há como mostrar os dados fictícios sem aviso, nem esquecer o aviso ligado sobre dados reais.
- Na primeira abertura com a variável definida, o painel apaga a base fictícia de `local/` e monta a real. A cada abertura confere a data e o tamanho do arquivo e remonta a base quando ele muda — basta substituir o CSV na pasta.
- Uma atualização com bem menos registros que a anterior (menos da metade), ou com datas de diagnóstico que não reconhece, é recusada, e o painel segue com a base que já tinha — as mesmas travas da produção.
- Se a variável apontar para uma pasta sem `sinan_hanseniase_pe.csv`, o painel não abre e registra o erro no log, em vez de cair nos dados fictícios.
- Removida a variável, o painel volta à base fictícia, com os avisos.
- O período inicial do filtro de datas e os limites do calendário acompanham a base carregada.

> 🛑 **Cuidado**
>
> Dados reais de pacientes são sigilosos (LGPD). Mantenha a pasta e o `.Renviron` fora do repositório e rode o painel só em ambiente protegido. Como proteção extra, o `.gitignore` deste repositório ignora `.Renviron`, `local/`, `dados_reais/`, arquivos `.duckdb` e qualquer `.csv` fora de `inst/extdata/dados_ficticios/`.

### 6.6 Camada de unidades de saúde e malhas

O cadastro de unidades vem pronto. Para atualizá-lo (a rede muda aos poucos), com a base local já montada:

```bash
Rscript dev/build_unidades_cnes.R
```

Precisa de internet (API do CNES e ESIG da Prefeitura do Recife) e leva alguns minutos. Grava `local/unidades_cnes.rds`; as unidades postas na sede do município saem em `local/unidades_localizacao_aproximada.csv`, para correção da coordenada no CNES.

As malhas de municípios e GERES são regeradas com `Rscript dev/build_malhas_pe.R` (só precisa de internet: geobr e SIDRA). O script para com erro se sobrar polígono inválido, fresta ou sobreposição entre vizinhos, ou buraco numa GERES.

### 6.7 Versão web (GitHub Pages)

O [painel ao vivo](https://dev-cenarios.github.io/SINAN_Territorios_Pernambuco_Hansen/) usa o [Shinylive](https://posit-dev.github.io/r-shinylive/): o R, compilado para WebAssembly ([webR](https://docs.r-wasm.org/webr/latest/)), roda no navegador de quem visita, sem servidor. É um site estático no branch `gh-pages` deste repositório, publicado pelo GitHub Pages.

Para regerar o site (por exemplo, depois de mudar o painel ou os dados fictícios):

```bash
Rscript dev/build_shinylive.R
```

O script monta a base fictícia, copia para uma pasta temporária só o código que o painel executa, as malhas e os caches prontos de `local/` (o navegador não refaz a carga do CSV) e exporta tudo para `site/` (não versionada no `main`). **Ele só aceita a base fictícia**: para com erro se `PAINEL_HANSEN_PE_DADOS_REAIS_DIR` estiver definido ou se a base local não for a fictícia, porque o site é público. Para ver antes de publicar: `Rscript -e "httpuv::runStaticServer('site', port = 8009)"` e abra `http://localhost:8009`.

Para publicar, substituindo o site anterior:

```bash
cd site
git init -b gh-pages
git add -A
git commit -m "Versao web do painel"
git push --force https://github.com/Dev-Cenarios/SINAN_Territorios_Pernambuco_Hansen.git gh-pages
```

Na primeira publicação, em **Settings → Pages** do repositório, a fonte é "Deploy from a branch", branch `gh-pages`, pasta `/ (root)`.

## 7. Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| Mapa não carrega / erro contendo `dsn must point to a source` | O painel não encontra as malhas em `inst/app/www/shapes/*.gpkg`: foi iniciado fora da raiz do projeto sem o pacote instalado | Rode a partir da raiz do projeto (`pkgload::load_all()` + `run_app()`) ou instale o pacote (`install.packages(".", repos = NULL, type = "source")`) |
| Dados não mudam depois de trocar o CSV | A base é conferida a cada abertura de página; uma sessão já aberta continua com a base anterior | Recarregue a página. Se a atualização tiver sido recusada, o log do R mostra "Atualizacao abortada" — para forçar, apague a pasta `local/` |
| Painel não abre e o log mostra `PAINEL_HANSEN_PE_DADOS_REAIS_DIR esta' definido, mas a pasta nao tem o arquivo sinan_hanseniase_pe.csv` | A variável aponta para uma pasta sem o arquivo de casos | Corrija o caminho ou o nome do arquivo (ver [6.5](#65-rodar-com-dados-reais)), ou remova a variável para voltar aos dados fictícios |
| "Atualizacao abortada: datas de diagnostico nao reconhecidas" | As datas do CSV real estão num formato que a transformação não conhece | O log mostra o formato que chegou (dígitos trocados por 9, sem expor valores); converta para um dos formatos da [seção 4](#4-fontes-de-dados) |

## 8. Desenvolvedores

- **Eduardo Schneider Arruda** — colaborador do Projeto Cenários, Engenheiro de Computação. Trabalha à frente do georreferenciamento usado no painel. Contato: geoprocenarios@gmail.com
- **João Morais** — desenvolvedor do frontend. Contato: geoprocenarios@gmail.com

## Licença

[MIT](LICENSE.md) — © 2026 Projeto Cenários.
