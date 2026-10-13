# Documentação de Gráficos e Indicadores — SINAN Territórios: Hanseníase – Pernambuco

> ⚠️ **Atenção**
>
> **Versão de demonstração com DADOS FICTÍCIOS.** A metodologia descrita aqui é a do painel de produção. Nesta vitrine, os casos do SINAN são gerados por simulação ([README, seção 2](../README.md#2-dados-fictícios)) e passam pelas mesmas transformações e cálculos descritos abaixo.

Este documento explica **por que cada visualização do painel existe, como ela é calculada e onde está implementada no código**. É destinado a epidemiologistas e gestores que precisam entender a metodologia por trás de cada número, sem necessariamente ler R.

Cada item segue o mesmo padrão:

1. **O que mostra** — descrição da visualização.
2. **Por que existe** — justificativa epidemiológica/de gestão.
3. **Como é calculado** — fórmula, filtros e fonte dos dados.
4. **Código** — função de referência, para quem for dar manutenção.

Todo o código-fonte fica em [`R/mod_municipio.R`](../R/mod_municipio.R), salvo indicação contrária.

> **Validação.** As categorias seguem o dicionário do SINAN NET – Hanseníase. Os códigos foram conferidos na saída da pipeline de georreferenciamento com a base de produção (cerca de 25 mil notificações, fev/2026): `AVALIA_N` e `AVAL_ATU_N` de 0 a 3, `TPALTA_N` de 1 a 8, com proporções plausíveis (cerca de 11% de grau 2 entre os avaliados, 2% de óbito e 12% de abandono entre os encerrados). Nessa base as datas vêm como **número de série do Excel** (dias desde 30/12/1899); a transformação converte esse formato e os de texto (ver seção 5.2).

### Conceitos usados em todo o painel

- **Caso novo**: notificação com modo de entrada (`MODOENTR`) = 1, "Caso novo". É a base da taxa de detecção e dos demais indicadores do Ministério da Saúde. Recidivas, transferências e outros reingressos aparecem nos cards de acompanhamento e na tabela, mas não contam como casos novos.
- **Erro diagnóstico** (`TPALTA_N` = 8): não é caso de hanseníase. Fica fora do painel por padrão (filtro de desfecho) e **sempre** fora dos indicadores por território, como orienta o Ministério da Saúde.
- **Encerrado**: caso com tipo de saída preenchido. Sem tipo de saída, o caso está **em tratamento**.
- **Território**: município de residência do SINAN (`ID_MN_RESI`) e a GERES a que ele pertence. Não depende do georreferenciamento: o caso sem coordenada (centroide) também conta no seu município. Casos residentes fora de Pernambuco ficam fora dos indicadores por território, mas continuam nos cards, no mapa e na tabela.

---

## 1. Cards de indicadores (topo do painel)

Todos respeitam o período (data de diagnóstico), os filtros ativos e o território selecionado no mapa (seção 2.7). A primeira linha traz o perfil dos casos no diagnóstico; a segunda, o acompanhamento e os indicadores operacionais (contatos examinados e grau de incapacidade avaliado).

| Card | Como é calculado | Rodapé |
|---|---|---|
| Casos novos no período | Notificações com modo de entrada "Caso novo" | Total de notificações filtradas |
| Paucibacilares | Casos novos com classificação operacional paucibacilar; o subtítulo traz o % dos casos novos | Atalho "Ver paucibacilares", em ocre |
| Multibacilares | Casos novos com classificação operacional multibacilar; o subtítulo traz o % dos casos novos | Atalho "Ver multibacilares", em roxo |
| Casos novos em menores de 15 anos | Casos novos com idade < 15 anos — sinal de transmissão ativa e recente | % dos casos novos |
| Grau 2 de incapacidade no diagnóstico | Casos novos com GIF 2 no diagnóstico (`AVALIA_N`) — sinal de diagnóstico tardio | % entre os casos novos **avaliados** (grau 0, I ou II) |
| Em tratamento | Notificações sem tipo de saída | Atalho "Ver todos em tratamento", em azul |
| Curados | Notificações com saída por cura | — |
| Abandono | Notificações com saída por abandono | — |
| Contatos examinados | Σ contatos examinados ÷ Σ contatos registrados, nos casos novos | Números absolutos |
| Grau de incapacidade avaliado no diagnóstico | Casos novos com o grau de incapacidade física avaliado no diagnóstico (grau 0, I ou II) ÷ casos novos — indicador operacional do Ministério da Saúde; o ideal é 100% | Atalho "Ver não avaliados" (grau "Não avaliado" ou não informado), com o número e o % deles, em ciano |

Os **atalhos** aplicam um filtro mantendo os demais (classificação operacional = paucibacilar ou multibacilar; desfecho = em tratamento; grau de incapacidade no diagnóstico = não avaliado ou ignorado) e abrem a caixa de filtros mostrando a mudança. "Limpar filtros" volta ao padrão.

**Código**: `output$box_*` e `aplica_atalho()` em `mod_municipio_server()`.

---

## 2. Mapa de casos

### 2.1 Pontos de casos

- **O que mostra**: cada notificação georreferenciada (`georreferenciado = 1`, classificado pela pipeline de georreferenciamento), colorida pelo desfecho. O hover mostra sexo, idade, classificação operacional e desfecho; o clique abre um popup com os dados do caso.
- **Como é calculado**: casos filtrados, restritos aos desfechos marcados na tabela "Distribuição dos desfechos" (seção 2.3). Casos não georreferenciados ficam fora do mapa, mas continuam nos cards, nos indicadores por território e na tabela.
- **Código**: `casos_points()` e o observador "Casos no mapa"; popup em `popup_caso()`.

### 2.2 Indicador por território: município ou GERES

- **O que mostra**: camada opcional com um indicador por município (185, incluindo Fernando de Noronha) ou por GERES (12), escolhido entre oito opções. O hover traz numerador, denominador e valor.
- **Por que existe**: identificar onde a endemia está concentrada e onde a vigilância é mais frágil (diagnóstico tardio, cura baixa, contatos não examinados).
- **Como é calculado** (`calcular_indicador_territorio()`), sempre sem erro diagnóstico:

| Indicador | Numerador | Denominador | Classes (Ministério da Saúde) |
|---|---|---|---|
| **Taxa de detecção** (indicador padrão) | Casos novos residentes | População do Censo 2022 × anos do período, por 100 mil | Baixo: < 2,00 · Médio: 2,00 a 9,99 · Alto: 10,00 a 19,99 · Muito alto: 20,00 a 39,99 · Hiperendêmico: ≥ 40,00 |
| Taxa de detecção em menores de 15 anos | Casos novos < 15 anos | População < 15 anos do Censo 2022 × anos, por 100 mil | Baixo: < 0,50 · Médio: 0,50 a 2,49 · Alto: 2,50 a 4,99 · Muito alto: 5,00 a 9,99 · Hiperendêmico: ≥ 10,00 |
| Proporção de multibacilares e paucibacilares | Casos novos multibacilares | Casos novos com classificação operacional informada (o restante são paucibacilares) | Sem parâmetro oficial: < 50% em laranja (predominam os paucibacilares) e faixas de 10 pontos em roxo a partir de 50% |
| Grau 2 de incapacidade no diagnóstico | Casos novos com GIF 2 | Casos novos avaliados (grau 0, I ou II) | Baixo: < 5,0% · Médio: 5,0 a 9,9% · Alto: ≥ 10,0% |
| Grau de incapacidade avaliado no diagnóstico | Casos novos com GIF avaliado (grau 0, I ou II) | Todos os casos novos | Precário: < 75,0% · Regular: 75,0 a 89,9% · Bom: ≥ 90,0% |
| Proporção de cura | Casos novos curados | Casos novos encerrados | Precário: < 75,0% · Regular: 75,0 a 89,9% · Bom: ≥ 90,0% |
| Proporção de abandono | Casos novos em abandono | Casos novos encerrados | Sem parâmetro oficial: faixas < 5,0%, 5,0 a 9,9%, 10,0 a 24,9% e ≥ 25,0% |
| Contatos examinados | Σ contatos examinados dos casos novos | Σ contatos registrados dos casos novos | Precário: < 75,0% · Regular: 75,0 a 89,9% · Bom: ≥ 90,0% |

  - A **taxa de detecção** é a "taxa de detecção geral de casos novos de hanseníase" do Ministério da Saúde. Na hanseníase o Ministério usa "detecção", e não "incidência": pela incubação longa, não se sabe quando a doença começou, e o número de casos novos depende também da capacidade dos serviços de encontrá-los. É anualizada: o total do período é dividido pelo número de anos. Período de menos de um ano conta como um ano (não há extrapolação).
  - As classes seguem as *Diretrizes para vigilância, atenção e eliminação da hanseníase como problema de saúde pública* (Ministério da Saúde, 2016). Como são faixas fixas, as cores são comparáveis entre períodos e filtros. A legenda usa a notação do guia ("Médio: 2,00 a 9,99"): cada faixa termina um passo antes do início da seguinte, sem número repetido entre faixas, com 2 casas decimais nas taxas e 1 nas proporções.
  - **Simplificação em relação ao Ministério**: a proporção de cura, a de abandono e a de contatos examinados oficiais usam coortes (paucibacilares diagnosticados no ano anterior ao da avaliação, multibacilares dois anos antes). O painel usa os casos novos **diagnosticados no período escolhido** (na cura e no abandono, os já encerrados). Para uma leitura próxima da oficial, escolha um período de diagnóstico já fechado (por exemplo, dois anos atrás).
  - Território em que o indicador não pode ser calculado (denominador zero) fica cinza, em vez de 0%. A legenda e o hover dizem o motivo: "Sem casos novos encerrados" na cura e no abandono (é o caso do município com casos no mapa, mas todos ainda em tratamento), "Sem casos novos avaliados" no grau 2, "Sem casos novos classificados" na proporção de multibacilares, "Sem contatos registrados" nos contatos examinados e "Sem casos novos" no grau de incapacidade avaliado.
- **Código**: `config_indicadores` (faixas, classes e paletas), `calcular_indicador_territorio()`, `hover_indicador()`, `ind_municipio()`, `ind_geres()` e o observador "Indicador por territorio".

### 2.3 Tabela de distribuição de desfechos (legenda/filtro do mapa)

- **O que mostra**: frequência e percentual de cada desfecho entre os casos filtrados, com barras nas cores do mapa. Marcar/desmarcar uma linha mostra/esconde aqueles pontos no mapa.
- **Desfechos** (agrupados a partir do tipo de saída `TPALTA_N`): Cura, Em tratamento, Abandono, Óbito, Transferência (as cinco modalidades de transferência juntas) e Erro diagnóstico. A ficha do caso mostra o tipo de saída detalhado.

### 2.4 Contorno das GERES

- **O que mostra**: limites e números (I a XII) das Gerências Regionais de Saúde, em navy sobre um halo branco. Camada própria, que liga/desliga independente do indicador.
- **Fonte**: regiões de saúde do Ministério da Saúde (`geobr`, 2013), que em Pernambuco coincidem com as 12 GERES da SES-PE. Ver `dev/build_malhas_pe.R`.
- **Geometria**: cada GERES é a união dos seus municípios, então o contorno cai exatamente sobre as divisas municipais. Isso depende de a malha municipal ser uma cobertura sem frestas, o que a versão simplificada do `geobr` não é (cada município simplificado por conta própria deixava ~750 frestas, desenhadas como riscos soltos dentro das GERES). Por isso o script parte da malha original do IBGE e simplifica cada divisa uma única vez, a 100 m (`simplifica_cobertura()`).

### 2.5 Unidades de saúde (camadas "Rede SUS (S)" e "Outras notificadoras (✕)")

- **O que mostra**: as unidades de saúde do CNES, como no painel de TB de Recife.
  - **Rede SUS ("S" vermelho)**: toda a rede pública assistencial de Pernambuco, mesmo sem caso notificado — postos de saúde, UBS/USF, policlínicas, hospitais gerais e especializados, unidades mistas, prontos-socorros, clínicas e centros de especialidade, centros de parto normal, hospitais-dia, CAPS e UPA (tipos 1, 2, 4, 5, 7, 15, 20, 21, 36, 61, 62, 70 e 73 do CNES), cerca de 4 mil unidades. Uma unidade pública de outro tipo (vigilância, gestão) entra se notificou algum caso.
  - **Outras notificadoras ("✕")**: as demais unidades que aparecem como notificadoras nos casos (filantrópicas, privadas).
  - O hover traz nome, tipo, natureza jurídica (com "atende SUS" nas não públicas), município e quantos casos a unidade notificou no período e nos filtros atuais.
- **Por que existe**: mostrar onde está a rede e quais unidades de fato notificam hanseníase, ao lado da distribuição dos casos e do indicador.
- **Como é calculado**:
  - "Pública" é definida pela **natureza jurídica** (1xxx, administração pública; 2011 e 2038, empresa pública e sociedade de economia mista), não pela esfera administrativa, que no CNES reflete a gestão. Só entram unidades habilitadas e localizadas em Pernambuco.
  - Notificadora é a unidade do campo `ID_UNIDADE` dos casos (código CNES, completado com zeros até 7 dígitos). No extrato de fev/2026, 97,1% dos casos foram notificados por unidades da camada da rede SUS e 0,3% por outras notificadoras. Os 2,6% restantes vêm de unidades desabilitadas no CNES, ausentes da API ou de fora de Pernambuco, que não aparecem no mapa.
  - **Coordenada**: a do CNES; em Recife, a da camada oficial da SESAU no ESIG para a rede municipal. Coordenada fora do próprio município até 500 m é puxada para a borda. Sem coordenada, ou mais longe que isso, a unidade vai para a sede do município, com aviso de localização aproximada no hover. A lista dessas unidades sai em `local/unidades_localizacao_aproximada.csv`, para correção no CNES.
- **Desenho**: as duas camadas começam desligadas (o mapa abre com casos, indicador e GERES); o usuário liga no controle de camadas do mapa. Com o mapa afastado, as unidades próximas se juntam num círculo com o total (anel vermelho na rede SUS, escuro nas demais), que se desfaz ao aproximar ou ao clicar. Unidades no mesmo ponto se abrem em leque no zoom máximo. Isso evita uma mancha de símbolos no mapa do estado e mantém o navegador leve, porque só as unidades da área visível ficam na página.
- **Desempenho**: as unidades são desenhadas uma vez por sessão (cerca de 0,7 MB). Ao trocar filtros ou período, o servidor manda só a contagem de casos por unidade (cerca de 0,04 MB), e o navegador completa o hover quando ele abre (`js_contagem_unidades`). Redesenhar as unidades mandaria cerca de 0,8 MB a cada clique.
- **Atualização**: `Rscript dev/build_unidades_cnes.R`, com a base local já montada (os códigos das notificadoras saem dos casos). Grava `local/unidades_cnes.rds`, que não é versionado. Nesta vitrine, o cadastro vem pronto em `inst/extdata/dados_ficticios/unidades_cnes.rds` e é copiado para `local/` na primeira abertura; o número de casos de cada unidade é fictício.
- **Código**: `camadas_unidades`, `adicionar_camada_unidades()` e os observadores "Unidades de saude" em `R/mod_municipio.R`; `carrega_unidades()` e `normaliza_cnes()` em `R/fct_casos.R`; estilo dos agrupamentos em `inst/app/badges_inline.css`.

### 2.6 Fernando de Noronha (quadro de detalhe)

- **O que mostra**: o arquipélago fica a ~550 km da costa, fora do enquadramento do estado e pequeno demais para ver nele. No desenho, ele vai para um quadro tracejado no mar, a leste do Recife, ampliado 4 vezes, com o nome do arquipélago embaixo da moldura. O município, a parte insular da I GERES, os casos e as unidades de saúde de Noronha são desenhados ali, e o clique no quadro seleciona Noronha como qualquer município.
- **Como é feito**: só o desenho muda. Nenhum cálculo usa coordenadas (o território do caso vem do código do município de residência), então os números não mudam.
- **Código**: `noronha`, `desloca_noronha()`, `desloca_noronha_xy()`, `quadro_noronha()` e `limites_mapa()` em `R/fct_casos.R`.

### 2.7 Território selecionado (clique no mapa)

- **O que faz**: clicar num município do indicador (ou numa GERES, no recorte por GERES) seleciona esse território. Os cards, a distribuição dos desfechos, os casos no mapa e a tabela de casos passam a mostrar só os casos **residentes** nele, junto com os filtros e o período. O título do mapa e a coluna da esquerda mostram o território, e o mapa se enquadra nele com um contorno escuro, sem passar do zoom 10 para continuar dando para clicar nos vizinhos. O botão "Ver todo o estado" volta para Pernambuco.
- **O que não muda**: o indicador do mapa continua com todos os territórios, para dar contexto e permitir clicar em outro. O hover das unidades de saúde continua contando todos os casos que a unidade notificou.
- **Por que existe**: ver a situação de um município específico sem perder a visão do estado.
- **Código**: `territorio_sel()`, `casos_territorio()`, `output$territorio_ui` e o observador "Territorio selecionado" em `R/mod_municipio.R`.

### 2.8 Título e subtítulo do mapa

O título traz o período; o subtítulo lista só os filtros que foram alterados em relação ao padrão.

---

## 3. Tabela de casos

- **O que mostra**: todas as notificações filtradas, com número de notificação, datas de diagnóstico e notificação, município de residência, idade, sexo, classificação operacional, forma clínica, GIF no diagnóstico, data de saída, desfecho e dias desde o diagnóstico (até a saída, ou até a notificação mais recente da base se em tratamento). Busca e filtro por coluna.
- **Ficha completa do caso**: clicar no número de notificação abre um modal com datas, demografia (inclusive escolaridade e gestação), município e GERES de residência, modo de entrada e de detecção, baciloscopia, classificação operacional, forma clínica, lesões cutâneas, nervos afetados, grau de incapacidade no diagnóstico e na saída, esquema terapêutico, contatos, desfecho e endereço.
- **Código**: `output$tabela_casos`; ficha no `observeEvent(input$ver_detalhes_casos)`.

---

## 4. Filtros

| Filtro | Aplicado sobre (coluna / campo do SINAN) |
|---|---|
| Período (padrão: do 1º de janeiro do ano mais recente até a última data de diagnóstico da base) | `dt_diagnostico` / `DT_DIAG` |
| Sexo | `sexo` / `CS_SEXO` |
| Idade | `idade` / `NU_IDADE_N` (ou data de nascimento) |
| Raça/cor | `raca_cor` / `CS_RACA` |
| Modo de entrada (caso novo, transferência, recidiva, outros reingressos) | `modo_entrada` / `MODOENTR` |
| Modo de detecção | `modo_deteccao` / `MODODETECT` |
| Baciloscopia | `baciloscopia` / `BACILOSCO` |
| Classificação operacional | `classificacao_operacional` / `CLASSOPERA` |
| Forma clínica | `forma_clinica` / `FORMACLINI` |
| Grau de incapacidade física no diagnóstico | `gif_diagnostico` / `AVALIA_N` |
| Desfecho (tipo de saída) | `desfecho` / `TPALTA_N` |

Campo em branco vira "Ignorado" (ou "Em tratamento", no desfecho), para não sumir dos filtros. Idade em branco só sai quando o filtro de idade é alterado. Os filtros ficam numa caixa colapsável e valem ao clicar em **"Aplicar filtros"**; **"Limpar filtros"** volta ao padrão. O período vale quando o calendário fecha.

**Código**: `casos_filtered()`, `filtros_ativos()` e os observadores de aplicar/limpar.

---

## 5. Outras informações do painel

### 5.1 Status de atualização dos dados

No cabeçalho: a data da notificação mais recente da base e o percentual de casos georreferenciados (sobre a base inteira, sem filtros).

### 5.2 Montagem da base (e botão "Atualizar dados", só na produção)

Na produção, um botão administrativo no cabeçalho, protegido por senha própria do painel, reprocessa a base a partir do PostgreSQL de origem. **Nesta vitrine ele não existe**: a base é montada automaticamente a partir do CSV fictício (ou do real, com a variável `PAINEL_HANSEN_PE_DADOS_REAIS_DIR` — [README, 6.5](../README.md#65-rodar-com-dados-reais)) e remontada sempre que o arquivo muda (`prepara_base()`). Com os dados fictícios, o lugar do botão no cabeçalho fica com o selo "DADOS FICTÍCIOS".

Nas duas versões, a montagem recusa sobrescrever a base local se a origem vier com zero registros ou menos da metade dos que já existem, grava `hans_sinan` no DuckDB, transforma em `hans_sinan_treated` (`transforma_hans_sinan()`) e regrava `local/casos_cache.rds`.

- **Datas**: aceitas como número de série do Excel (4 ou 5 dígitos, como a pipeline entrega quando o CSV passa por planilha), texto `dd/mm/aaaa` (formato dos fictícios), `aaaa-mm-dd` ou `aaaammdd`, e DATE/TIMESTAMP.
- **Trava de datas** (`valida_datas_hans()`): se menos da metade das notificações ficar com data de diagnóstico reconhecida, ou se a mais recente cair antes de 2000 ou depois do ano que vem, a atualização para antes de regravar o cache — o painel continua com os dados anteriores — e a mensagem mostra o formato que chegou em `DT_DIAG` (dígitos trocados por 9, sem expor valores). Sem essa trava, um formato novo de data deixaria o painel inteiro zerado.
- **Número de notificação**: completado com zeros à esquerda até 7 dígitos, como no SINAN (a origem traz número inteiro).

**Código**: `prepara_base()`, `update_hans_data()`, `transforma_hans_sinan()` e `valida_datas_hans()` em `R/fct_db_update.R`.

### 5.3 População

Censo Demográfico 2022 do IBGE, pela API do SIDRA: tabela 4714 (população residente por município, 9.058.931 habitantes em PE) e tabela 9514 (população de 0 a 14 anos). A população da GERES é a soma dos seus municípios. Gerada uma vez por `dev/build_malhas_pe.R` e gravada nas malhas.

---

## 6. Identidade visual

Segue o guia **["Documentação – ID visual para painéis"](https://cenarios.unb.br/documentacao-id-visual-para-paineis/)** do Programa Cenários, herdando do painel de TB de Recife o navy `#12346B` nas barras estratégicas e as paletas ColorBrewer no mapa de indicadores.

| Desfecho | Cor |
|---|---|
| Cura | adequado `#1F6F4A` |
| Em tratamento | série 1, azul |
| Abandono | grave `#C24B12` |
| Óbito | crítico `#A32235` |
| Transferência | série 8, ciano |
| Erro diagnóstico | cinza `#7A8B95` |

A classificação operacional tem cores próprias: paucibacilares em ocre (série 6, `#B08A1E`) e multibacilares em roxo (série 3, `#6C5CA8`), nos cards e nos atalhos. No mapa, o indicador de multibacilares usa cores da PuOr (ColorBrewer): laranja onde predominam os paucibacilares, roxo cada vez mais escuro conforme sobe a proporção de multibacilares.

**Código**: `cores_cen`, `cores_desfecho` e `config_indicadores` em `R/mod_municipio.R`; variáveis `--cen-*` em `inst/app/badges_inline.css`; tema em `R/utils_app_theme.R`.

---

## 7. Fontes de dados

| O que | Fonte | Onde fica | Como atualizar |
|---|---|---|---|
| Casos de hanseníase | **Vitrine: fictícios** (`inst/extdata/dados_ficticios/sinan_hanseniase_pe_ficticio.csv`, gerado por `dev/gerar_dados_ficticios.R`). Produção: SINAN, via pipeline de georreferenciamento do projeto, num PostgreSQL interno. Categorias pelo dicionário de dados do SINAN NET – Hanseníase | `local/sinan.duckdb` (`hans_sinan_treated`) e `local/casos_cache.rds` | Vitrine: trocar o CSV e reabrir a página. Produção: botão "Atualizar dados" |
| Malha municipal (185) | IBGE 2022, resolução original, via [`geobr`](https://github.com/ipeaGIT/geobr); simplificada a 100 m preservando as divisas compartilhadas | `inst/app/www/shapes/municipios_pe.gpkg` | `dev/build_malhas_pe.R` |
| GERES (12) | Regiões de saúde do Ministério da Saúde (2013), via `geobr` | `inst/app/www/shapes/geres_pe.gpkg` | `dev/build_malhas_pe.R` |
| Unidades de saúde ("S" e "✕") | [API pública do CNES/DATASUS](https://apidadosabertos.saude.gov.br/cnes/estabelecimentos); em Recife, coordenadas da camada [Rede de Saúde de Recife](https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/Rede_de_Sa%C3%BAde_de_Recife/FeatureServer/0) (SESAU/ESIG); sedes municipais via `geobr` | `local/unidades_cnes.rds` (na vitrine, copiado de `inst/extdata/dados_ficticios/unidades_cnes.rds`) | `dev/build_unidades_cnes.R` |
| População total e < 15 anos | IBGE, Censo 2022 — SIDRA, tabelas 4714 e 9514 | nas duas malhas acima | `dev/build_malhas_pe.R` |
| Mapas de fundo e fontes | Esri (`WorldGrayCanvas`, `WorldImagery`) e Google Fonts | Carregados pelo navegador | — |
