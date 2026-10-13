# UI ----

filtro_sexo_default <- c("F", "M", "I")
filtro_idade_default <- as.integer(c(0, 120))
filtro_raca_cor_default <- c("Branca", "Preta", "Amarela", "Parda", "Indígena", "Ignorado")
filtro_modo_entrada_default <- c("Caso novo", "Transferência", "Recidiva", "Outros reingressos", "Ignorado")
filtro_modo_deteccao_default <- c("Encaminhamento", "Demanda espontânea", "Exame de coletividade",
                                  "Exame de contatos", "Outros modos", "Ignorado")
filtro_classificacao_default <- c("Paucibacilar", "Multibacilar", "Ignorado")
filtro_forma_clinica_default <- c("Indeterminada", "Tuberculoide", "Dimorfa", "Virchowiana",
                                  "Não classificada", "Ignorado")
filtro_gif_default <- c("Grau 0", "Grau I", "Grau II", "Não avaliado", "Ignorado")
filtro_baciloscopia_default <- c("Positiva", "Negativa", "Não realizada", "Ignorado")
# "Erro diagnóstico" fica de fora por padrao: nao e' caso de hanseniase (o
# Ministerio da Saude exclui esses registros de todos os indicadores). Da'
# pra incluir pelo filtro de desfecho, pra conferencia -- os indicadores
# por territorio continuam excluindo (ver casos_indicador()).
filtro_desfecho_opcoes <- c("Cura", "Em tratamento", "Abandono", "Óbito", "Transferência", "Erro diagnóstico")
filtro_desfecho_default <- setdiff(filtro_desfecho_opcoes, "Erro diagnóstico")

# O periodo so' vale pro painel quando a escolha termina: enquanto algum
# calendario do filtro de datas estiver aberto (ou o usuario digitando), a
# mudanca fica guardada; quando ele fecha, vai pro servidor como
# input$periodo_aplicado. Senao cada data escolhida recalcularia tudo na
# hora -- trocar inicio e fim do periodo custaria dois recalculos.
js_periodo_aplicado <- "
(function() {
  var id = '%s', destino = '%s';
  var pendente = null, enviado = null, aberto = false, timer = null;
  function agenda() {
    clearTimeout(timer);
    timer = setTimeout(function() {
      if (aberto || pendente === null) return;
      var valor = JSON.stringify(pendente);
      if (valor === enviado) return;
      enviado = valor;
      Shiny.setInputValue(destino + ':shiny.date', pendente);
    }, 600);
  }
  $(document).on('shiny:inputchanged', function(e) {
    if (e.name === id) { pendente = e.value; agenda(); }
  });
  $(document).on('show', '#' + id + ' input', function() { aberto = true; clearTimeout(timer); });
  $(document).on('hide', '#' + id + ' input', function() { aberto = false; agenda(); });
})();
"

# O leaflet do R destroi e recria o mapa a cada render, e no Leaflet 1.3 um
# redesenho de canvas ja' agendado dispara depois do canvas destruido
# ("Cannot read properties of undefined (reading 'clearRect')" no console --
# inofensivo, mas polui). Ignora esse redesenho, como o proprio Leaflet
# passou a fazer a partir da 1.4.
js_canvas_redesenho <- "
if (window.L && L.Canvas && !L.Canvas.prototype._ignoraRedesenhoSemCanvas) {
  var redesenhaCanvas = L.Canvas.prototype._redraw;
  L.Canvas.prototype._redraw = function() {
    if (!this._ctx) { this._redrawRequest = null; return; }
    return redesenhaCanvas.apply(this, arguments);
  };
  L.Canvas.prototype._ignoraRedesenhoSemCanvas = true;
}
"

# Ordem de desenho no canvas do mapa: indicador (ou contorno de PE) <
# contorno das GERES < contorno do territorio selecionado < casos. No canvas
# a ordem e' a ordem em que as camadas entram no mapa, e as camadas sao
# atualizadas separadamente (leafletProxy, ver output$main_map): um
# indicador redesenhado entraria por cima dos casos -- escondendo os pontos
# e roubando o hover deles. Registrado como metodo do leaflet no onRender
# do mapa (output$main_map): o servidor chama (leaflet::invokeMethod) depois
# de cada atualizacao, e o mapa, a cada camada religada no controle. Manda
# pro fundo so' as malhas, na ordem inversa (o halo branco continua embaixo
# da linha).
js_ordena_camadas <- "
if (window.LeafletWidget && !LeafletWidget.methods.ordenaCamadas) {
  LeafletWidget.methods.ordenaCamadas = function() {
    var map = this;
    var aoFundo = function(grupos, tipo) {
      var lista = [];
      grupos.forEach(function(nome) {
        var grupo = map.layerManager.getLayerGroup(nome, false);
        if (!grupo) return;
        grupo.eachLayer(function(l) {
          if (l instanceof tipo && map.hasLayer(l)) lista.push(l);
        });
      });
      for (var i = lista.length - 1; i >= 0; i--) lista[i].bringToBack();
    };
    aoFundo(['Seleção'], L.Polygon);
    aoFundo(['GERES'], L.Polygon);
    aoFundo(['Indicador por território', 'Pernambuco'], L.Polygon);
  };
}
"

# Contagem de casos no hover das unidades de saude (camadas "Rede SUS (S)" e
# "Outras notificadoras (✕)"). As ~4 mil unidades sao desenhadas uma vez por
# sessao; a cada troca de filtro ou periodo o servidor manda so' a contagem
# por codigo CNES (metodo contagemUnidades, via leaflet::invokeMethod) --
# redesenhar as unidades mandaria ~0,8 MB por clique. O navegador guarda a
# contagem e completa o hover quando ele abre: o rotulo de cada unidade traz
# o codigo em data-cnes (ver adicionar_camada_unidades()). Completar na
# abertura, e nao percorrendo as unidades quando a contagem chega, tambem
# evita depender do momento em que o markercluster termina de receber as
# unidades -- na primeira contagem elas ainda nao estao no grupo.
js_contagem_unidades <- "
if (window.LeafletWidget && !LeafletWidget.methods.contagemUnidades) {
  LeafletWidget.methods.contagemUnidades = function(contagem) {
    var map = this;
    map.contagemUnidades = contagem || {};
    if (map.contagemUnidadesLigada) return;
    map.contagemUnidadesLigada = true;
    map.on('tooltipopen', function(e) {
      var tip = e.tooltip;
      if (tip.rotuloBase === undefined) {
        var rotulo = tip.getContent();
        if (typeof rotulo !== 'string' || rotulo.indexOf('data-cnes=') < 0) return;
        tip.rotuloBase = rotulo;
      }
      var cnes = /data-cnes=\"(\\d+)\"/.exec(tip.rotuloBase);
      var casos = (cnes && map.contagemUnidades[cnes[1]]) || 0;
      tip.setContent(tip.rotuloBase + '<br><b>' + casos + '</b> caso(s) notificado(s) no período selecionado');
    });
  };
}
"

reactable_idioma <- reactable::reactableLang(
  sortLabel = "Ordenar {name}",
  filterLabel = "Filtrar {name}",
  searchPlaceholder = "Buscar",
  searchLabel = "Buscar",
  noData = "Nenhum registro encontrado",
  pageNext = "Próxima",
  pagePrevious = "Anterior",
  pageNumbers = "{page} de {pages}",
  pageInfo = "{rowStart}–{rowEnd} de {rows} registros",
  pageSizeOptions = "Mostrar {rows}",
  pageNextLabel = "Próxima",
  pagePreviousLabel = "Anterior",
  pageNumberLabel = "Página {page}",
  pageJumpLabel = "Ir para página",
  pageSizeOptionsLabel = "Registros por página",
  groupExpandLabel = "Abrir grupo",
  detailsExpandLabel = "Mostrar detalhes",
  selectAllRowsLabel = "Selecionar todos",
  selectAllSubRowsLabel = "Selecionar todos do grupo",
  selectRowLabel = "Selecionar linha"
)

opcoes_picker <- function(nenhum, max_opcoes = NULL, acoes = TRUE) {
  shinyWidgets::pickerOptions(
    noneSelectedText = nenhum,
    noneResultsText = "Nenhum resultado encontrado.",
    deselectAllText = "Limpar seleção",
    selectAllText = "Selecionar tudo",
    maxOptions = max_opcoes,
    actionsBox = acoes
  )
}

# Card de estatistica numa coluna de largura igual as demais da linha (5
# em cada uma); empilhados em tela estreita
caixa_card <- function(id) {
  htmltools::div(class = "col-12 col-md card-estatistica", bs4Dash::bs4ValueBoxOutput(id, width = NULL))
}


#' municipio UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
#' @importFrom magrittr %>%
mod_municipio_ui <- function(id) {
  ns <- shiny::NS(id)
  limites <- limites_periodo()
  periodo_inicial <- periodo_padrao()

  htmltools::tagList(
    shiny::fluidRow(
      bs4Dash::column(2,
                      ## General input ----
                      htmltools::h1("Panorama geral", style = "font-weight: 600"),
                      shiny::dateRangeInput(
                        ns("periodo"),
                        label = htmltools::HTML("Filtro de data de diagnóstico"),
                        start = periodo_inicial[1],
                        end = periodo_inicial[2],
                        min = limites[1],
                        max = limites[2],
                        format = "dd/mm/yyyy",
                        startview = "month",
                        language = "pt-BR",
                        separator = "até",
                        width = "100%"
                      ),
                      htmltools::tags$script(htmltools::HTML(
                        sprintf(js_periodo_aplicado, ns("periodo"), ns("periodo_aplicado"))
                      )),
                      bs4Dash::actionButton(
                        ns("mostrar_filtros"),
                        label = "Abrir filtros",
                        icon = shiny::icon("plus"),
                        status = "secondary",
                        size = "xs",
                        width="60%"
                      ),
                      # Territorio selecionado no mapa (ou a dica de como selecionar)
                      shiny::uiOutput(ns("territorio_ui")),
                      align="center", style="z-index:1002;"
      ),
      ## Boxes ----
      # Primeira linha: perfil dos casos no diagnostico; segunda: acompanhamento
      bs4Dash::column(
        10,
        shiny::fluidRow(
          caixa_card(ns("box_total")),
          caixa_card(ns("box_paucibacilar")),
          caixa_card(ns("box_multibacilar")),
          caixa_card(ns("box_menor15")),
          caixa_card(ns("box_gif2"))
        ),
        shiny::fluidRow(
          caixa_card(ns("box_tratamento")),
          caixa_card(ns("box_cura")),
          caixa_card(ns("box_abandono")),
          caixa_card(ns("box_contatos")),
          caixa_card(ns("box_gif_avaliado"))
        )
      )
    ),
    ## Filter boxes ----
    shiny::fluidRow(
      bs4Dash::column(12,
                      bs4Dash::box(
                        id = ns("box_filtro"),
                        title = "Filtros",
                        width = NULL,
                        status = "primary",
                        solidHeader = F,
                        closable = T,
                        collapsible = F,
                        icon = shiny::icon("sliders"),
                        shiny::fluidRow(
                          bs4Dash::column(
                            3,
                            shinyWidgets::checkboxGroupButtons(
                              ns("filtro_sexo"),
                              label = "Sexo",
                              choiceNames = c("Feminino", "Masculino", "Ignorado"),
                              choiceValues = c("F", "M", "I"),
                              selected = filtro_sexo_default,
                              checkIcon = list(
                                yes = shiny::icon("check")
                              ),
                              status = "info"
                            ),
                            shiny::sliderInput(
                              ns("filtro_idade"),
                              label = "Idade (anos)",
                              min = 0,
                              max = 120,
                              value = filtro_idade_default,
                              step = 1
                            ),
                            shinyWidgets::pickerInput(
                              ns("filtro_raca_cor"),
                              label = "Raça/cor",
                              choices = filtro_raca_cor_default,
                              selected = filtro_raca_cor_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione raça/cor...")
                            )
                          ),
                          bs4Dash::column(
                            3,
                            shinyWidgets::pickerInput(
                              ns("filtro_modo_entrada"),
                              label = "Modo de entrada",
                              choices = filtro_modo_entrada_default,
                              selected = filtro_modo_entrada_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione modo de entrada...")
                            ),
                            shinyWidgets::pickerInput(
                              ns("filtro_modo_deteccao"),
                              label = "Modo de detecção",
                              choices = filtro_modo_deteccao_default,
                              selected = filtro_modo_deteccao_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione modo de detecção...")
                            ),
                            shinyWidgets::pickerInput(
                              ns("filtro_baciloscopia"),
                              label = "Baciloscopia",
                              choices = filtro_baciloscopia_default,
                              selected = filtro_baciloscopia_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione baciloscopia...")
                            )
                          ),
                          bs4Dash::column(
                            3,
                            shinyWidgets::pickerInput(
                              ns("filtro_classificacao"),
                              label = "Classificação operacional",
                              choices = filtro_classificacao_default,
                              selected = filtro_classificacao_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione classificação...")
                            ),
                            shinyWidgets::pickerInput(
                              ns("filtro_forma_clinica"),
                              label = "Forma clínica",
                              choices = filtro_forma_clinica_default,
                              selected = filtro_forma_clinica_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione forma clínica...")
                            ),
                            bs4Dash::actionButton(
                              ns("filtro_clear"),
                              htmltools::strong("Limpar filtros"),
                              icon = shiny::icon("undo"),
                              width = "100%",
                              status = "secondary"
                            )
                          ),
                          bs4Dash::column(
                            3,
                            shinyWidgets::pickerInput(
                              ns("filtro_gif"),
                              label = "Grau de incapacidade física no diagnóstico",
                              choices = filtro_gif_default,
                              selected = filtro_gif_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione grau de incapacidade...")
                            ),
                            shinyWidgets::pickerInput(
                              ns("filtro_desfecho"),
                              label = "Desfecho (tipo de saída)",
                              choices = filtro_desfecho_opcoes,
                              selected = filtro_desfecho_default,
                              multiple = TRUE,
                              options = opcoes_picker("Selecione desfecho...")
                            ),
                            bs4Dash::actionButton(
                              ns("filtro_update"),
                              htmltools::strong("Aplicar filtros"),
                              icon = shiny::icon("refresh"),
                              width = "100%",
                              status = "primary"
                            ),
                            style="z-index:1002;"
                          )
                        )
                      )
      ),
      id = ns("box_filtro_row")
    ) |> shinyjs::hidden(),
    ## Leaflet Map ----
    shiny::fluidRow(
      bs4Dash::column(12,
                      bs4Dash::box(
                        title = htmltools::strong("Mapa de casos"),
                        width = NULL,
                        status = "primary",
                        solidHeader = TRUE,
                        icon = shiny::icon("map-pin"),
                        shiny::fluidRow(
                          bs4Dash::column(4,

                                          htmltools::h3("Distribuição dos desfechos", style = "font-weight: 600"),

                                          htmltools::p("Selecione quais desfechos a serem mostrados no mapa", style = "color: gray; font-size: 14px"),

                                          reactable::reactableOutput(ns("casos_table")),

                                          htmltools::hr(),

                                          htmltools::h3("Indicadores por território", style = "font-weight: 600"),

                                          shinyWidgets::prettyCheckbox(ns("show_indicador"),
                                                                       label = "Mostrar indicador no mapa",
                                                                       status = "info",
                                                                       icon = shiny::icon("check"),
                                                                       value = TRUE),
                                          shiny::radioButtons(
                                            ns("nivel_territorial"),
                                            label = "Recorte",
                                            choices = c("Município" = "municipio", "GERES" = "geres"),
                                            selected = "municipio",
                                            inline = TRUE
                                          ),
                                          shiny::selectInput(
                                            ns("indicador"),
                                            label = "Indicador",
                                            choices = stats::setNames(
                                              names(config_indicadores),
                                              vapply(config_indicadores, function(x) x$opcao, character(1))
                                            ),
                                            selected = "det"
                                          ),
                                          shiny::uiOutput(ns("indicador_nota"))

                          ),
                          bs4Dash::column(8,
                                          shiny::uiOutput(ns("main_map_title")),
                                          shiny::uiOutput(ns("main_map_subtitle")),
                                          # div so' pro spinner (badges_inline.css) -- no mapa, pelo
                                          # estado "ocupado" do servidor: as camadas sao atualizadas
                                          # por leafletProxy, a saida nao recalcula
                                          htmltools::div(
                                            class = "saida-carregando saida-carregando-ocupado",
                                            leaflet::leafletOutput(ns("main_map"), height = 720)
                                          ),
                                          # Os demais metodos do mapa sao registrados no onRender
                                          # (ver output$main_map)
                                          htmltools::tags$script(htmltools::HTML(js_canvas_redesenho))
                          )
                        )
                      ),
      )
    ),

    shiny::fluidRow(
      bs4Dash::column(12,
                      bs4Dash::box(
                        title = htmltools::strong("Tabela de casos"),
                        width = NULL,
                        status = "primary",
                        solidHeader = TRUE,
                        icon = shiny::icon("table"),
                        # div so' pro spinner enquanto recalcula (badges_inline.css)
                        htmltools::div(
                          class = "saida-carregando",
                          reactable::reactableOutput(ns("tabela_casos"))
                        )
                      )
      )
    )

  )
}

# Identidade visual dos paineis do Programa Cenarios (guia "Documentacao --
# ID visual para paineis", cenarios.unb.br). Mesmos tokens --cen-* de
# inst/app/badges_inline.css.
cores_cen <- list(
  azul = "#3891C0", azul_acao = "#0E7BA8", azul_texto = "#00638C",
  terra = "#B67355", terra_texto = "#8C4A2A",
  tinta = "#12222B", tinta_2 = "#4A4A4A", tinta_3 = "#7A8B95", linha = "#D8E3EA",
  ok = "#1F6F4A", atencao = "#8A6100", grave = "#C24B12", critico = "#A32235",
  # series de dados 1 a 8, nesta ordem
  series = c("#3891C0", "#C0663C", "#6C5CA8", "#5A9E2E", "#8E3B46", "#B08A1E", "#3F4E9E", "#1B9AAA"),
  sequencial = c("#89B8D5", "#5BA1CA", "#2F8AB8", "#006E9C", "#005477", "#003A56"),
  divergente = c("#822F00", "#BE643A", "#DBA289", "#EDEAE6", "#89B8D5", "#2F8AB8", "#005477")
)

navy_painel <- "#12346B" # barras estrategicas e contorno das GERES

# Cores dos desfechos -- fonte unica pra ficha do caso, tabela de
# distribuicao, tabela de casos e mapa. Cores de estado do guia onde ha'
# sentido clinico (cura = adequado, obito = critico, abandono = grave);
# series do guia nos demais. A ordem aqui e' a da legenda do mapa.
cores_desfecho <- c(
  "Cura"             = cores_cen$ok,
  "Em tratamento"    = cores_cen$series[1], # azul
  "Abandono"         = cores_cen$grave,
  "Óbito"            = cores_cen$critico,
  "Transferência"    = cores_cen$series[8], # ciano
  "Erro diagnóstico" = cores_cen$tinta_3
)

# Indicadores por territorio (municipio ou GERES). Classes pelos parametros
# do Ministerio da Saude (Diretrizes para vigilancia, atencao e eliminacao
# da hanseniase como problema de saude publica, 2016), onde existem:
#   - taxa de deteccao de casos novos por 100 mil hab./ano:
#     baixo < 2, medio 2-9,99, alto 10-19,99, muito alto 20-39,99,
#     hiperendemico >= 40; em menores de 15 anos: < 0,5; 0,5-2,49;
#     2,5-4,99; 5-9,99; >= 10;
#   - proporcao de GIF 2 entre os casos novos avaliados: baixo < 5%,
#     medio 5-9,9%, alto >= 10%;
#   - proporcao de cura, de contatos examinados e de casos novos com GIF
#     avaliado no diagnostico: precario < 75%, regular 75-89,9%, bom >= 90%.
# Abandono e proporcao de multibacilares nao tem parametro oficial -- faixas
# fixas (nos multibacilares, com corte em 50%: abaixo, predominam os
# paucibacilares).
# `bins` em valor do indicador (proporcao de 0 a 1 nos percentuais); faixa
# fechada a esquerda: [2, 10) e' "medio". `sem_dado`: rotulo, na legenda e
# no hover, do territorio sem valor (denominador zero).
config_indicadores <- list(
  det = list(
    opcao = "Taxa de detecção (casos novos/população)",
    titulo = "Taxa de detecção anual<br>(por 100 mil hab.)",
    bins = c(0, 2, 10, 20, 40, Inf),
    classes = c("Baixo", "Médio", "Alto", "Muito alto", "Hiperendêmico"),
    paleta = "YlOrRd", percentual = FALSE,
    sem_dado = "Sem população"
  ),
  det15 = list(
    opcao = "Taxa de detecção em menores de 15 anos",
    titulo = "Taxa de detecção anual < 15 anos<br>(por 100 mil hab.)",
    bins = c(0, 0.5, 2.5, 5, 10, Inf),
    classes = c("Baixo", "Médio", "Alto", "Muito alto", "Hiperendêmico"),
    paleta = "YlOrRd", percentual = FALSE,
    sem_dado = "Sem população"
  ),
  prop_mb = list(
    opcao = "Proporção de multibacilares e paucibacilares",
    titulo = "Multibacilares (%)<br><small>o restante são paucibacilares</small>",
    bins = c(0, 0.5, 0.6, 0.7, 0.8, 0.9, 1),
    classes = c("mais PB que MB", "", "", "", "", ""),
    # Cores da PuOr (ColorBrewer): laranja onde predominam os paucibacilares,
    # roxo cada vez mais escuro conforme sobe a proporcao de multibacilares
    paleta = c("#E08214", "#D8DAEB", "#B2ABD2", "#8073AC", "#542788", "#2D004B"),
    percentual = TRUE,
    sem_dado = "Sem casos novos classificados"
  ),
  gif2 = list(
    opcao = "Grau 2 de incapacidade no diagnóstico (%)",
    titulo = "GIF 2 no diagnóstico (%)",
    bins = c(0, 0.05, 0.10, 1),
    classes = c("Baixo", "Médio", "Alto"),
    paleta = "OrRd", percentual = TRUE,
    sem_dado = "Sem casos novos avaliados"
  ),
  gif_aval = list(
    opcao = "Grau de incapacidade avaliado no diagnóstico (%)",
    titulo = "GIF avaliado no diagnóstico (%)",
    bins = c(0, 0.75, 0.90, 1),
    classes = c("Precário", "Regular", "Bom"),
    paleta = "RdYlGn", percentual = TRUE,
    sem_dado = "Sem casos novos"
  ),
  prop_cura = list(
    opcao = "Proporção de cura (curados/encerrados)",
    titulo = "Proporção de cura (%)",
    bins = c(0, 0.75, 0.90, 1),
    classes = c("Precário", "Regular", "Bom"),
    paleta = "RdYlGn", percentual = TRUE,
    sem_dado = "Sem casos novos encerrados"
  ),
  prop_aband = list(
    opcao = "Proporção de abandono (abandono/encerrados)",
    titulo = "Proporção de abandono (%)",
    bins = c(0, 0.05, 0.10, 0.25, 1),
    classes = NULL,
    paleta = "Oranges", percentual = TRUE,
    sem_dado = "Sem casos novos encerrados"
  ),
  prop_contatos = list(
    opcao = "Contatos examinados (examinados/registrados)",
    titulo = "Contatos examinados (%)",
    bins = c(0, 0.75, 0.90, 1),
    classes = c("Precário", "Regular", "Bom"),
    paleta = "RdYlGn", percentual = TRUE,
    sem_dado = "Sem contatos registrados"
  )
)

formata_num <- function(x, digitos = 0) {
  formatC(x, format = "f", digits = digitos, big.mark = ".", decimal.mark = ",")
}

formata_pct <- function(x, digitos = 1) {
  ifelse(is.na(x), "–", paste0(formata_num(100 * x, digitos), "%"))
}

# Rotulos da legenda do indicador no formato do guia do Ministerio da Saude
# ("Médio: 2,00 a 9,99"): faixas sem numero repetido -- o fim de cada uma e'
# um passo antes do inicio da seguinte --, a primeira "< x" e a ultima
# "≥ x", com 2 casas nas taxas e 1 nas proporcoes (em %). Classe na frente
# quando todas as faixas tem uma; nota so' em algumas faixas vai depois
# ("< 50,0% · mais PB que MB").
rotulos_legenda <- function(cfg) {
  casas <- if (cfg$percentual) 1 else 2
  escala <- if (cfg$percentual) 100 else 1
  sufixo <- if (cfg$percentual) "%" else ""
  num <- function(x) formata_num(escala * x, casas)
  passo <- 10^-casas / escala
  # n - 1 faixas: "< b2", "b2 a (b3 - passo)", ..., "≥ b[n-1]"
  b <- cfg$bins
  n <- length(b)
  meio <- if (n > 3) paste0(num(b[2:(n - 2)]), " a ", num(b[3:(n - 1)] - passo), sufixo) else character(0)
  faixas <- c(paste0("< ", num(b[2]), sufixo), meio, paste0("≥ ", num(b[n - 1]), sufixo))
  if (is.null(cfg$classes)) return(faixas)
  if (all(nzchar(cfg$classes))) return(paste0(cfg$classes, ": ", faixas))
  ifelse(nzchar(cfg$classes), paste0(faixas, " · ", cfg$classes), faixas)
}

# Indicador por territorio (municipio ou GERES): conta os casos por
# territorio e calcula o indicador escolhido. `coluna` e' a coluna do caso
# com o territorio de residencia (territorio_municipio/territorio_geres,
# atribuida uma vez por caso em R/fct_casos.R) e `chaves` o identificador de
# cada linha de `terr`, na mesma ordem. `anos` = duracao do periodo, pra
# anualizar as taxas de deteccao. Detalhes em docs/DOCUMENTACAO_GRAFICOS.md,
# secao 2.2.
calcular_indicador_territorio <- function(terr, casos, indicador, coluna, chaves, anos) {
  contar <- function(x) as.integer(table(factor(x[[coluna]], levels = chaves)))
  somar <- function(x, campo) {
    s <- tapply(dplyr::coalesce(x[[campo]], 0L), factor(x[[coluna]], levels = chaves), sum)
    dplyr::coalesce(as.integer(s), 0L)
  }

  novos <- casos |> dplyr::filter(modo_entrada == "Caso novo")
  encerrados_novos <- novos |> dplyr::filter(situacao == "Encerrado")

  if (indicador == "det") {
    terr$numerador <- contar(novos)
    terr$denominador <- terr$pop
    terr$ind <- 1e5 * terr$numerador / terr$denominador / anos
  } else if (indicador == "det15") {
    terr$numerador <- contar(novos |> dplyr::filter(idade < 15))
    terr$denominador <- terr$pop_menor15
    terr$ind <- 1e5 * terr$numerador / terr$denominador / anos
  } else if (indicador == "prop_mb") {
    classificados <- novos |> dplyr::filter(classificacao_operacional %in% c("Paucibacilar", "Multibacilar"))
    terr$numerador <- contar(classificados |> dplyr::filter(classificacao_operacional == "Multibacilar"))
    terr$denominador <- contar(classificados)
    terr$ind <- terr$numerador / terr$denominador
  } else if (indicador == "gif2") {
    avaliados <- novos |> dplyr::filter(gif_diagnostico %in% c("Grau 0", "Grau I", "Grau II"))
    terr$numerador <- contar(avaliados |> dplyr::filter(gif_diagnostico == "Grau II"))
    terr$denominador <- contar(avaliados)
    terr$ind <- terr$numerador / terr$denominador
  } else if (indicador == "gif_aval") {
    # Avaliado = grau 0, I ou II; "Não avaliado" e campo vazio ("Ignorado")
    # contam como nao avaliados
    terr$numerador <- contar(novos |> dplyr::filter(gif_diagnostico %in% c("Grau 0", "Grau I", "Grau II")))
    terr$denominador <- contar(novos)
    terr$ind <- terr$numerador / terr$denominador
  } else if (indicador == "prop_cura") {
    terr$numerador <- contar(encerrados_novos |> dplyr::filter(desfecho == "Cura"))
    terr$denominador <- contar(encerrados_novos)
    terr$ind <- terr$numerador / terr$denominador
  } else if (indicador == "prop_aband") {
    terr$numerador <- contar(encerrados_novos |> dplyr::filter(desfecho == "Abandono"))
    terr$denominador <- contar(encerrados_novos)
    terr$ind <- terr$numerador / terr$denominador
  } else if (indicador == "prop_contatos") {
    terr$numerador <- somar(novos, "contatos_examinados")
    terr$denominador <- somar(novos, "contatos_registrados")
    terr$ind <- terr$numerador / terr$denominador
  }

  # 0/0 (territorio sem caso no denominador) fica sem cor, nao como 0%
  terr$ind[!is.finite(terr$ind)] <- NA
  terr
}

# Texto do hover de cada territorio, por indicador. `dica` vai no fim, em
# italico (ex.: que o clique seleciona o territorio). Territorio sem valor
# ganha uma linha dizendo por que (o `sem_dado` do indicador).
hover_indicador <- function(terr, indicador, dica = NULL) {
  n <- function(x) formata_num(x)
  sem_valor <- ifelse(
    is.na(terr$ind),
    paste0("<br><i>", config_indicadores[[indicador]]$sem_dado, " no período: indicador não calculado</i>"),
    ""
  )
  valor <- switch(
    indicador,
    det = sprintf("Casos novos no período: <b>%s</b><br>População (2022): <b>%s</b><br>Taxa de detecção anual: <b>%s</b> por 100 mil hab./ano",
                  n(terr$numerador), n(terr$denominador), formata_num(terr$ind, 1)),
    det15 = sprintf("Casos novos em menores de 15 anos: <b>%s</b><br>População < 15 anos (2022): <b>%s</b><br>Taxa de detecção anual: <b>%s</b> por 100 mil hab./ano",
                    n(terr$numerador), n(terr$denominador), formata_num(terr$ind, 1)),
    prop_mb = sprintf("Multibacilares: <b>%s</b> (%s)<br>Paucibacilares: <b>%s</b> (%s)<br>Casos novos com classificação: <b>%s</b>",
                      n(terr$numerador), formata_pct(terr$ind),
                      n(terr$denominador - terr$numerador), formata_pct(1 - terr$ind),
                      n(terr$denominador)),
    gif2 = sprintf("Casos novos com GIF 2: <b>%s</b><br>Casos novos avaliados no diagnóstico: <b>%s</b><br>Proporção: <b>%s</b>",
                   n(terr$numerador), n(terr$denominador), formata_pct(terr$ind)),
    gif_aval = sprintf("Casos novos com GIF avaliado no diagnóstico: <b>%s</b><br>Não avaliados: <b>%s</b><br>Casos novos: <b>%s</b><br>Proporção avaliada: <b>%s</b>",
                       n(terr$numerador), n(terr$denominador - terr$numerador), n(terr$denominador),
                       formata_pct(terr$ind)),
    prop_cura = sprintf("Curados: <b>%s</b><br>Casos novos encerrados: <b>%s</b><br>Proporção de cura: <b>%s</b>",
                        n(terr$numerador), n(terr$denominador), formata_pct(terr$ind)),
    prop_aband = sprintf("Abandono: <b>%s</b><br>Casos novos encerrados: <b>%s</b><br>Proporção de abandono: <b>%s</b>",
                         n(terr$numerador), n(terr$denominador), formata_pct(terr$ind)),
    prop_contatos = sprintf("Contatos examinados: <b>%s</b><br>Contatos registrados: <b>%s</b><br>Proporção examinada: <b>%s</b>",
                            n(terr$numerador), n(terr$denominador), formata_pct(terr$ind))
  )
  paste0("<strong>", htmltools::htmlEscape(terr$nome_territorio), "</strong><br>", valor, sem_valor,
         if (!is.null(dica)) paste0("<br><i>", dica, "</i>") else "") |>
    lapply(htmltools::HTML)
}

# Popup de um ou mais pontos do mapa. Montado so' quando o ponto e' clicado
# (ver output$main_map), nao enviado junto com cada ponto.
popup_caso <- function(casos) {
  sprintf(
    "<b>Número de notificação</b>: %s
        <br><b>Data de diagnóstico</b>: %s
        <br><b>Data de notificação</b>: %s
        <br><b>Início do tratamento</b>: %s
        <br><b>Data de saída</b>: %s
        <br><b>Sexo</b>: %s
        <br><b>Idade</b>: %s
        <br><b>Raça/cor</b>: %s
        <br><b>Município de residência</b>: %s
        <br><b>Endereço</b>: %s
        <br><b>Modo de entrada</b>: %s
        <br><b>Classificação operacional</b>: %s
        <br><b>Forma clínica</b>: %s
        <br><b>Grau de incapacidade no diagnóstico</b>: %s
        <br><br><b>Desfecho</b>: %s",
    casos$numero_notificacao,
    format(casos$dt_diagnostico, "%d/%m/%Y"),
    format(casos$dt_notificacao, "%d/%m/%Y"),
    format(casos$dt_inicio_tratamento, "%d/%m/%Y"),
    format(casos$dt_alta, "%d/%m/%Y"),
    casos$sexo,
    round(casos$idade),
    casos$raca_cor,
    htmltools::htmlEscape(casos$municipio_residencia),
    htmltools::htmlEscape(casos$endereco),
    casos$modo_entrada,
    casos$classificacao_operacional,
    casos$forma_clinica,
    casos$gif_diagnostico,
    dplyr::coalesce(casos$tipo_saida, casos$desfecho)
  )
}

# Simbolos das unidades de saude, como no painel de TB de Recife: "S"
# vermelho pra rede publica/SUS e "✕" pras demais unidades notificadoras.
# Desenhados em SVG (icone de marcador comum), com contorno branco pra
# aparecer sobre qualquer cor do indicador.
icone_svg <- function(svg, tamanho) {
  leaflet::makeIcon(
    iconUrl = paste0("data:image/svg+xml;charset=utf-8,", utils::URLencode(svg, reserved = TRUE)),
    iconWidth = tamanho, iconHeight = tamanho,
    iconAnchorX = tamanho / 2, iconAnchorY = tamanho / 2
  )
}

camadas_unidades <- list(
  sus = list(
    grupo = "Rede SUS (S)",
    cluster = "unidades_sus",
    rotulo_cluster = "unidades da rede SUS",
    icone = icone_svg(paste0(
      '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">',
      '<text x="9" y="15" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="17" ',
      'font-weight="900" fill="', cores_cen$critico, '" stroke="#FFFFFF" stroke-width="3" ',
      'stroke-linejoin="round" paint-order="stroke">S</text></svg>'
    ), 18)
  ),
  outras = list(
    grupo = "Outras notificadoras (✕)",
    cluster = "unidades_outras",
    rotulo_cluster = "outras unidades notificadoras",
    icone = icone_svg(paste0(
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">',
      '<path d="M3 3 L13 13 M13 3 L3 13" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round"/>',
      '<path d="M3 3 L13 13 M13 3 L3 13" stroke="', cores_cen$tinta, '" stroke-width="2.4" stroke-linecap="round"/>',
      '</svg>'
    ), 16)
  )
)

# Camada de unidades de saude no mapa. Com ~4 mil unidades no estado, as
# proximas umas das outras se juntam num circulo com o total (Leaflet.
# markercluster, estilo .cluster-unidades em badges_inline.css), que se
# desfaz ao aproximar o mapa; unidades no mesmo ponto se abrem em leque
# (spiderfy) no zoom maximo. O agrupamento tambem so' poe na pagina as
# unidades da area visivel. O hover traz nome, tipo, natureza e municipio;
# a contagem de casos entra depois, pelo navegador (js_contagem_unidades).
adicionar_camada_unidades <- function(m, unidades, camada) {
  if (nrow(unidades) == 0) return(m)

  nota_aproximada <- ifelse(
    unidades$aproximada %in% TRUE,
    "<br><i>Localização aproximada: sede do município (coordenada do CNES ausente ou fora do município)</i>",
    ""
  )
  rotulos <- sprintf(
    '<span data-cnes="%s"><b>%s</b><br>%s · %s<br>%s%s</span>',
    unidades$codigo_cnes,
    htmltools::htmlEscape(unidades$nome),
    htmltools::htmlEscape(unidades$tipo_unidade),
    htmltools::htmlEscape(unidades$natureza),
    htmltools::htmlEscape(unidades$municipio),
    nota_aproximada
  )

  # As de Fernando de Noronha vao pro quadro de detalhe (desloca_noronha_xy())
  xy <- desloca_noronha_xy(unidades$longitude, unidades$latitude)

  m |>
    leaflet::addMarkers(
      lng = xy$x,
      lat = xy$y,
      layerId = unidades$codigo_cnes,
      icon = camada$icone,
      label = lapply(rotulos, htmltools::HTML),
      labelOptions = leaflet::labelOptions(textsize = "13px", direction = "auto"),
      group = camada$grupo,
      clusterId = camada$cluster,
      clusterOptions = leaflet::markerClusterOptions(
        showCoverageOnHover = FALSE,
        spiderfyOnMaxZoom = TRUE,
        maxClusterRadius = 35,
        iconCreateFunction = leaflet::JS(sprintf(
          "function(cluster) {
             var n = cluster.getChildCount();
             return L.divIcon({
               html: '<div title=\"' + n + ' %s (clique para aproximar)\"><span>' + n + '</span></div>',
               className: 'cluster-unidades cluster-%s',
               iconSize: L.point(32, 32)
             });
           }",
          camada$rotulo_cluster, sub("^unidades_", "", camada$cluster)
        ))
      )
    )
}

# Plugin de agrupamento (markercluster) das camadas de unidades, carregado
# junto com o mapa, na criacao. As unidades entram depois, por leafletProxy;
# na versao web do painel (Shinylive) o plugin nao chegava por esse caminho e
# as camadas de unidades falhavam no navegador.
com_plugin_agrupamento <- function(mapa) {
  mapa$dependencies <- c(mapa$dependencies, leaflet::leafletDependencies$markerCluster())
  mapa
}

# SERVER ----
#' municipio Server Functions
#'
#' @noRd
mod_municipio_server <- function(id, cache_trigger = shiny::reactiveVal(0)){
  shiny::moduleServer(id, function(input, output, session){
    ns <- session$ns

    # Base carregada veio dos dados ficticios? Liga os avisos do mapa, da
    # ficha do caso e do cabecalho (ver dados_sao_ficticios() em
    # R/fct_db_update.R)
    ficticio <- dados_sao_ficticios()

    ## Filtros ativos -----
    # Valem so' depois de "Aplicar filtros" (ou "Limpar filtros").

    filtros_padrao <- list(
      sexo = filtro_sexo_default,
      idade = filtro_idade_default,
      raca_cor = filtro_raca_cor_default,
      modo_entrada = filtro_modo_entrada_default,
      modo_deteccao = filtro_modo_deteccao_default,
      baciloscopia = filtro_baciloscopia_default,
      classificacao = filtro_classificacao_default,
      forma_clinica = filtro_forma_clinica_default,
      gif = filtro_gif_default,
      desfecho = filtro_desfecho_default
    )

    filtros_ativos <- shiny::reactiveVal(filtros_padrao)

    # Periodo em vigor no painel -- so' muda quando a escolha de datas
    # termina (input$periodo_aplicado, ver js_periodo_aplicado no topo do
    # arquivo), nao a cada data clicada. Periodo invalido (data vazia ou
    # inicio depois do fim) e' ignorado.
    periodo_ativo <- shiny::reactiveVal(periodo_padrao())

    shiny::observeEvent(input$periodo_aplicado, {
      periodo <- as.Date(input$periodo_aplicado)
      if (length(periodo) == 2 && !anyNA(periodo) && periodo[1] <= periodo[2]) {
        periodo_ativo(periodo)
      }
    })

    # Duracao do periodo em anos, pra anualizar as taxas de deteccao. Periodo
    # de menos de um ano conta como um ano (a taxa nao e' extrapolada).
    periodo_anos <- shiny::reactive({
      pmax(1, as.numeric(periodo_ativo()[2] - periodo_ativo()[1]) / 365.25)
    })

    desfecho_ids <- dplyr::tibble(desfecho = names(cores_desfecho)) |>
      dplyr::mutate(desfecho_id = dplyr::row_number())

    ### Cases -----

    # Casos compartilhados entre as sessoes, ja' com o municipio e a GERES
    # de residencia (ver carrega_casos() em R/fct_casos.R). cache_trigger()
    # faz a sessao reler na hora quando a base e' remontada.
    casos_sf <- shiny::reactive({
      cache_trigger()
      carrega_casos()
    })

    ### Filtered cases -----

    casos_filtered <- shiny::reactive({
      shiny::req(casos_sf())
      shiny::req(periodo_ativo())
      f <- filtros_ativos()

      # Idade em branco so' sai quando o filtro de idade foi mexido
      idade_padrao <- identical(f$idade, filtro_idade_default)

      casos_sf() |>
        dplyr::filter(
          dt_diagnostico >= periodo_ativo()[1],
          dt_diagnostico <= periodo_ativo()[2],
          sexo %in% f$sexo,
          (is.na(idade) & idade_padrao) | (idade >= f$idade[1] & idade <= f$idade[2]),
          raca_cor %in% f$raca_cor,
          modo_entrada %in% f$modo_entrada,
          modo_deteccao %in% f$modo_deteccao,
          baciloscopia %in% f$baciloscopia,
          classificacao_operacional %in% f$classificacao,
          forma_clinica %in% f$forma_clinica,
          gif_diagnostico %in% f$gif,
          desfecho %in% f$desfecho
        )
    })

    ### Territorio selecionado no mapa ----

    # Clique num municipio do indicador (ou numa GERES, no recorte por
    # GERES): cards, distribuicao dos desfechos, casos no mapa e tabela de
    # casos passam a mostrar so' os residentes dele (territorio_municipio /
    # territorio_geres). O indicador do mapa continua com todos os
    # territorios -- da' o contexto e permite clicar em outro -- e o hover das
    # unidades de saude continua contando todos os casos que elas notificaram.
    # NULL = Pernambuco inteiro.
    territorio_sel <- shiny::reactiveVal(NULL)

    # layerId dos poligonos do indicador: "<recorte>|<chave>" (ver o
    # observador do indicador por territorio)
    shiny::observeEvent(input$main_map_shape_click, {
      partes <- strsplit(as.character(input$main_map_shape_click$id), "|", fixed = TRUE)[[1]]
      if (length(partes) != 2 || !partes[1] %in% c("municipio", "geres")) return()
      territorio_sel(list(recorte = partes[1], chave = partes[2]))
    })

    shiny::observeEvent(input$territorio_limpar, territorio_sel(NULL))

    # Nome do territorio selecionado, ex.: "Petrolina (VIII GERES)"
    territorio_nome <- shiny::reactive({
      sel <- territorio_sel()
      if (is.null(sel)) return(NULL)
      if (sel$recorte == "municipio") {
        mun <- malha_municipios()
        i <- match(sel$chave, mun$code_muni)
        sprintf("%s (%s GERES)", mun$nome[i], mun$geres[i])
      } else {
        geres <- malha_geres()
        geres$nome[match(sel$chave, geres$geres)]
      }
    })

    casos_territorio <- shiny::reactive({
      casos <- casos_filtered()
      sel <- territorio_sel()
      if (is.null(sel)) return(casos)
      coluna <- if (sel$recorte == "municipio") "territorio_municipio" else "territorio_geres"
      casos[casos[[coluna]] %in% sel$chave, ]
    })

    # Casos novos (modo de entrada "Caso novo") -- base da taxa de deteccao e dos
    # indicadores do Ministerio da Saude
    casos_novos <- shiny::reactive({
      casos_territorio() |> dplyr::filter(modo_entrada == "Caso novo")
    })

    ### Filtered points ----

    # Desfechos marcados na tabela "Distribuicao dos desfechos" -- o filtro
    # dos pontos no mapa. Comeca com todos e so' muda quando a tabela informa
    # a selecao do usuario. Antes os pontos esperavam a tabela mandar o
    # estado inicial ao servidor; quando isso nao chegava, o mapa abria sem
    # pontos ate' a tabela ser redesenhada (ex.: ao selecionar um municipio).
    desfechos_marcados <- shiny::reactiveVal(desfecho_ids$desfecho)

    shiny::observeEvent(reactable::getReactableState("casos_table", "selected"), {
      # linhas marcadas (1, 2, ...); nenhuma marcada chega como NULL ou lista vazia
      linhas <- as.integer(unlist(reactable::getReactableState("casos_table", "selected")))
      desfechos_marcados(desfecho_ids$desfecho[linhas])
    }, ignoreNULL = FALSE, ignoreInit = TRUE)

    casos_points <- shiny::reactive({
      casos_territorio() |>
        dplyr::filter(desfecho %in% desfechos_marcados())
    })

    ### Indicator by territory (municipio / GERES) ----

    # Erro diagnostico nunca entra nos indicadores, mesmo que o filtro de
    # desfecho o inclua. Diferente do painel de TB, o territorio e' o
    # municipio de residencia do SINAN (nao a coordenada), entao casos nao
    # georreferenciados e de situacao de rua/privados de liberdade tambem
    # contam.
    casos_indicador <- shiny::reactive({
      casos_filtered() |>
        sf::st_drop_geometry() |>
        dplyr::filter(desfecho != "Erro diagnóstico")
    })

    # Geometria so' pro desenho (simplificada)
    ind_municipio <- shiny::reactive({
      mun <- malha_municipios_desenho()
      calcular_indicador_territorio(mun, casos_indicador(), input$indicador,
                                    coluna = "territorio_municipio", chaves = mun$code_muni,
                                    anos = periodo_anos()) |>
        dplyr::mutate(nome_territorio = sprintf("%s (%s GERES)", nome, geres))
    })

    ind_geres <- shiny::reactive({
      geres <- malha_geres_desenho()
      calcular_indicador_territorio(geres, casos_indicador(), input$indicador,
                                    coluna = "territorio_geres", chaves = geres$geres,
                                    anos = periodo_anos()) |>
        dplyr::mutate(nome_territorio = sprintf("%s – %d municípios", nome, n_municipios))
    })

    ## ShinyJS ----

    shiny::observeEvent(input$show_indicador, {
      if (input$show_indicador) {
        shinyjs::enable("indicador")
        shinyjs::enable("nivel_territorial")
      } else {
        shinyjs::disable("indicador")
        shinyjs::disable("nivel_territorial")
      }
    })

    shiny::observeEvent(input$mostrar_filtros, {
      shinyjs::show("box_filtro_row")
      bs4Dash::updateBox("box_filtro", action = "restore", session = session)
    })

    shiny::observeEvent(input$filtro_update, {
      filtros_ativos(list(
        sexo = input$filtro_sexo,
        idade = as.integer(input$filtro_idade),
        raca_cor = input$filtro_raca_cor,
        modo_entrada = input$filtro_modo_entrada,
        modo_deteccao = input$filtro_modo_deteccao,
        baciloscopia = input$filtro_baciloscopia,
        classificacao = input$filtro_classificacao,
        forma_clinica = input$filtro_forma_clinica,
        gif = input$filtro_gif,
        desfecho = input$filtro_desfecho
      ))

      bs4Dash::updateBox("box_filtro", action = "remove", session = session)
    })

    atualiza_pickers <- function(f) {
      shinyWidgets::updateCheckboxGroupButtons("filtro_sexo", session = session, selected = f$sexo)
      shiny::updateSliderInput("filtro_idade", session = session, value = f$idade)
      shinyWidgets::updatePickerInput(session = session, "filtro_raca_cor", selected = f$raca_cor)
      shinyWidgets::updatePickerInput(session = session, "filtro_modo_entrada", selected = f$modo_entrada)
      shinyWidgets::updatePickerInput(session = session, "filtro_modo_deteccao", selected = f$modo_deteccao)
      shinyWidgets::updatePickerInput(session = session, "filtro_baciloscopia", selected = f$baciloscopia)
      shinyWidgets::updatePickerInput(session = session, "filtro_classificacao", selected = f$classificacao)
      shinyWidgets::updatePickerInput(session = session, "filtro_forma_clinica", selected = f$forma_clinica)
      shinyWidgets::updatePickerInput(session = session, "filtro_gif", selected = f$gif)
      shinyWidgets::updatePickerInput(session = session, "filtro_desfecho", selected = f$desfecho)
    }

    shiny::observeEvent(input$filtro_clear, {
      atualiza_pickers(filtros_padrao)
      filtros_ativos(filtros_padrao)
      bs4Dash::updateBox("box_filtro", action = "remove", session = session)
    })

    # Atalhos no rodape dos cards ("Ver todos em tratamento", "Ver
    # paucibacilares", "Ver multibacilares", "Ver não avaliados"): aplicam um
    # filtro mantendo os demais e abrem a caixa de filtros mostrando a mudanca
    aplica_atalho <- function(campo, picker, valor) {
      f <- filtros_ativos()
      f[[campo]] <- valor
      shinyjs::show("box_filtro_row")
      bs4Dash::updateBox("box_filtro", action = "restore", session = session)
      shinyWidgets::updatePickerInput(session = session, picker, selected = valor)
      filtros_ativos(f)
    }

    shinyjs::onclick("box_tratamento_click", aplica_atalho("desfecho", "filtro_desfecho", "Em tratamento"))
    shinyjs::onclick("box_paucibacilar_click", aplica_atalho("classificacao", "filtro_classificacao", "Paucibacilar"))
    shinyjs::onclick("box_multibacilar_click", aplica_atalho("classificacao", "filtro_classificacao", "Multibacilar"))
    shinyjs::onclick("box_gif_avaliado_click", aplica_atalho("gif", "filtro_gif", c("Não avaliado", "Ignorado")))

    ## Ficha do caso ----

    shiny::observeEvent(input$ver_detalhes_casos, {

      num_notific <- input$ver_detalhes_casos$id

      caso <- casos_sf() |>
        dplyr::filter(numero_notificacao == num_notific) |>
        sf::st_drop_geometry() |>
        dplyr::slice_head(n=1)

      shiny::req(nrow(caso) == 1)

      desfecho_label <- sprintf(
        '<span style="background-color: %s; color: white; padding: 5px 15px; border-radius: 20px;
                display: inline-block; font-size: 16px; font-weight: bold;">%s</span>',
        cores_desfecho[[caso$desfecho]], caso$desfecho
      )

      campo <- function(largura, titulo, valor) {
        bs4Dash::column(
          largura,
          htmltools::HTML(sprintf("<h4><b>%s</b></h4> <p>%s</p>", titulo, valor))
        )
      }
      data_br <- function(x) ifelse(is.na(x), "–", format(x, "%d/%m/%Y"))
      texto <- function(x) ifelse(is.na(x) | x == "", "–", htmltools::htmlEscape(x))
      numero <- function(x) ifelse(is.na(x), "–", as.character(x))

      shiny::showModal(
        shiny::modalDialog(
          title = htmltools::tagList(
            paste0("Ficha de notificação ", num_notific, " "),
            if (ficticio) htmltools::span(class = "selo-ficticio", "CASO FICTÍCIO")
          ),
          htmltools::div(
            shiny::fluidRow(
              campo(4, "Data de diagnóstico", data_br(caso$dt_diagnostico)),
              campo(4, "Data de notificação", data_br(caso$dt_notificacao)),
              campo(4, "Início do tratamento", data_br(caso$dt_inicio_tratamento))
            ),
            shiny::hr(),
            shiny::fluidRow(
              campo(4, "Idade", ifelse(is.na(caso$idade), "–", floor(caso$idade))),
              campo(4, "Sexo", caso$sexo),
              campo(4, "Raça/cor", caso$raca_cor)
            ),
            shiny::hr(),
            shiny::fluidRow(
              campo(4, "Escolaridade", caso$escolaridade),
              campo(4, "Gestante", caso$gestante),
              campo(4, "Município de residência",
                    texto(ifelse(is.na(caso$municipio_residencia), NA,
                                 sprintf("%s (%s GERES)", caso$municipio_residencia, caso$territorio_geres))))
            ),
            shiny::hr(),
            shiny::fluidRow(
              campo(4, "Modo de entrada", caso$modo_entrada_detalhe),
              campo(4, "Modo de detecção", caso$modo_deteccao),
              campo(4, "Baciloscopia", caso$baciloscopia)
            ),
            shiny::hr(),
            shiny::fluidRow(
              campo(4, "Classificação operacional", caso$classificacao_operacional),
              campo(4, "Forma clínica", caso$forma_clinica),
              campo(4, "Lesões cutâneas / nervos afetados",
                    paste(numero(caso$n_lesoes), "/", numero(caso$n_nervos_afetados)))
            ),
            shiny::hr(),
            shiny::fluidRow(
              campo(4, "Grau de incapacidade (diagnóstico / saída)",
                    paste(caso$gif_diagnostico, "/", caso$gif_alta)),
              campo(4, "Esquema terapêutico inicial", caso$esquema_inicial),
              campo(4, "Contatos examinados / registrados",
                    paste(numero(caso$contatos_examinados), "/", numero(caso$contatos_registrados)))
            ),
            shiny::hr(),
            shiny::fluidRow(
              campo(4, "Desfecho", paste0(desfecho_label,
                                          ifelse(is.na(caso$tipo_saida) | caso$tipo_saida == caso$desfecho, "",
                                                 paste0("<br><small>", caso$tipo_saida, "</small>")))),
              campo(4, "Data de saída", data_br(caso$dt_alta)),
              campo(4, "Tempo desde o diagnóstico (dias)", numero(caso$tempo_aberto))
            ),
            shiny::hr(),
            shiny::fluidRow(
              campo(4, "Bairro", texto(caso$bairro)),
              campo(4, "Logradouro", texto(caso$endereco)),
              campo(4, "Georreferenciado?", ifelse(caso$georreferenciado == 1, "Sim", "Não"))
            )
          ),
          size = "xl",
          footer = shiny::modalButton("Ok")
        )
      )
    })

    ## UI outputs ----

    output$db_info_ui <- shiny::renderUI({
      shiny::req(casos_sf())

      n_geo <- sum(casos_sf()$georreferenciado == 1)
      n_tot <- nrow(casos_sf())
      last_notif_date <- max(casos_sf()$dt_notificacao, na.rm=T)

      htmltools::div(
        htmltools::div(style="font-weight: 100; color: #FFF", htmltools::HTML(sprintf("<i class=\"fa fa-clock-o\" aria-hidden=\"true\"></i>  %s: %s",
                                                                                      if (ficticio) "Dados fictícios até" else "Data de atualização dos dados",
                                                                                      format(last_notif_date, "%d/%m/%Y")))),
        htmltools::div(style="font-weight: 100; color: #FFF", htmltools::HTML(sprintf("<i class=\"fa fa-globe\" aria-hidden=\"true\"></i> Total de casos georreferenciados: %s (%s)",
                                                                                      formata_num(n_geo), formata_pct(n_geo/n_tot))))
      )
    })

    # Territorio selecionado no mapa, com o botao de voltar pro estado; sem
    # selecao, a dica de como selecionar
    output$territorio_ui <- shiny::renderUI({
      nome <- territorio_nome()
      if (is.null(nome)) {
        dica <- if (identical(input$nivel_territorial, "geres")) {
          "Clique numa GERES do mapa para ver só a situação dela."
        } else {
          "Clique num município do mapa para ver só a situação dele."
        }
        return(htmltools::p(class = "territorio-dica", dica))
      }
      htmltools::div(
        class = "territorio-selecionado",
        htmltools::div(class = "territorio-rotulo",
                       if (territorio_sel()$recorte == "municipio") "Município selecionado" else "GERES selecionada"),
        htmltools::div(class = "territorio-nome", nome),
        shiny::actionButton(ns("territorio_limpar"), "Ver todo o estado", icon = shiny::icon("undo"),
                            class = "btn-sm btn-primary")
      )
    })

    output$main_map_title <- shiny::renderUI({
      onde <- territorio_nome()
      if (is.null(onde)) onde <- "Pernambuco"
      title <- paste0(
        "Mapa de casos de hanseníase em ", onde, ", de ",
        format(periodo_ativo()[1], "%d/%m/%Y"), " a ", format(periodo_ativo()[2], "%d/%m/%Y")
      )

      bs4Dash::column(12, htmltools::h3(title, style = "font-weight: 600"), align = "center")
    })

    output$main_map_subtitle <- shiny::renderUI({
      f <- filtros_ativos()
      rotulos <- c(
        sexo = "Sexo", idade = "Idade", raca_cor = "Raça/cor", modo_entrada = "Modo de entrada",
        modo_deteccao = "Modo de detecção", baciloscopia = "Baciloscopia",
        classificacao = "Classificação operacional", forma_clinica = "Forma clínica",
        gif = "Grau de incapacidade", desfecho = "Desfechos"
      )

      modificados <- names(rotulos)[!vapply(names(rotulos), function(k) identical(f[[k]], filtros_padrao[[k]]), logical(1))]

      if (length(modificados) == 0) return(NULL)

      partes <- vapply(modificados, function(k) {
        valores <- paste(f[[k]], collapse = if (k == "idade") "-" else ", ")
        paste0("<b>", rotulos[[k]], ":</b> ", htmltools::htmlEscape(valores))
      }, character(1))

      bs4Dash::column(12,
                      htmltools::h6(htmltools::HTML(paste0("Filtros: ", paste(partes, collapse = "; "))),
                                    style = "font-weight: 400"),
                      align = "center")
    })

    output$indicador_nota <- shiny::renderUI({
      nota <- switch(
        input$indicador,
        det = "Casos novos residentes por 100 mil habitantes por ano (população do Censo 2022). Classes pelos parâmetros do Ministério da Saúde.",
        det15 = "Casos novos em menores de 15 anos por 100 mil habitantes dessa faixa etária, por ano.",
        prop_mb = "Multibacilares entre os casos novos com classificação operacional informada; o restante são paucibacilares.",
        gif2 = "Casos novos com grau 2 de incapacidade física, entre os casos novos avaliados no diagnóstico.",
        gif_aval = "Casos novos com o grau de incapacidade física avaliado no diagnóstico (grau 0, I ou II), entre todos os casos novos. O ideal é avaliar 100%.",
        prop_cura = "Curados entre os casos novos já encerrados (com tipo de saída), exceto erro diagnóstico. Casos ainda em tratamento não entram na conta: o município em que nenhum caso novo do período foi encerrado fica sem cor, mesmo com casos no mapa.",
        prop_aband = "Abandono entre os casos novos já encerrados (com tipo de saída), exceto erro diagnóstico. Casos ainda em tratamento não entram na conta: o município em que nenhum caso novo do período foi encerrado fica sem cor, mesmo com casos no mapa.",
        prop_contatos = "Soma dos contatos examinados sobre a soma dos contatos registrados, nos casos novos."
      )
      htmltools::p(nota, style = "color: gray; font-size: 13px")
    })

    ## Box outputs ----

    card <- function(valor, titulo, cor, icone, rodape = NULL) {
      bs4Dash::bs4ValueBox(
        value = htmltools::h3(valor),
        subtitle = htmltools::h5(titulo),
        color = cor,
        gradient = TRUE,
        icon = shiny::icon(icone),
        footer = rodape
      )
    }

    rodape_texto <- function(texto) htmltools::div(style = "font-size: 13px;", texto)

    # Rodape clicavel que aplica um filtro (ver aplica_atalho())
    rodape_atalho <- function(id, texto) {
      htmltools::div(id = ns(id), style = "cursor: pointer;", shiny::icon("external-link"), texto)
    }

    output$box_total <- bs4Dash::renderbs4ValueBox({
      shiny::req(casos_territorio())
      card(formata_num(nrow(casos_novos())), "Casos novos no período", "teal", "users",
           rodape_texto(sprintf("%s notificações no total", formata_num(nrow(casos_territorio())))))
    })

    output$box_tratamento <- bs4Dash::renderbs4ValueBox({
      n <- sum(casos_territorio()$desfecho == "Em tratamento")
      card(formata_num(n), "Em tratamento", "warning", "pills",
           rodape_atalho("box_tratamento_click", "Ver todos em tratamento"))
    })

    # Classificacao operacional: paucibacilares e multibacilares, cada um com
    # a sua cor (badges_inline.css) e o atalho que filtra o painel pra ele
    output$box_paucibacilar <- bs4Dash::renderbs4ValueBox({
      novos <- casos_novos()
      n <- sum(novos$classificacao_operacional == "Paucibacilar")
      card(formata_num(n), sprintf("Paucibacilares (%s dos casos novos)", formata_pct(n / nrow(novos))),
           "olive", "bacterium", rodape_atalho("box_paucibacilar_click", "Ver paucibacilares"))
    })

    output$box_multibacilar <- bs4Dash::renderbs4ValueBox({
      novos <- casos_novos()
      n <- sum(novos$classificacao_operacional == "Multibacilar")
      card(formata_num(n), sprintf("Multibacilares (%s dos casos novos)", formata_pct(n / nrow(novos))),
           "purple", "bacteria", rodape_atalho("box_multibacilar_click", "Ver multibacilares"))
    })

    output$box_menor15 <- bs4Dash::renderbs4ValueBox({
      novos <- casos_novos()
      n <- sum(novos$idade < 15, na.rm = TRUE)
      card(formata_num(n), "Casos novos em menores de 15 anos", "indigo", "child",
           rodape_texto(sprintf("%s dos casos novos", formata_pct(n / nrow(novos)))))
    })

    output$box_gif2 <- bs4Dash::renderbs4ValueBox({
      novos <- casos_novos()
      avaliados <- sum(novos$gif_diagnostico %in% c("Grau 0", "Grau I", "Grau II"))
      n <- sum(novos$gif_diagnostico == "Grau II")
      card(formata_num(n), "Grau 2 de incapacidade no diagnóstico", "danger", "wheelchair",
           rodape_texto(sprintf("%s dos casos novos avaliados", formata_pct(n / avaliados))))
    })

    output$box_cura <- bs4Dash::renderbs4ValueBox({
      n <- sum(casos_territorio()$desfecho == "Cura")
      card(formata_num(n), "Curados", "success", "heart")
    })

    output$box_abandono <- bs4Dash::renderbs4ValueBox({
      n <- sum(casos_territorio()$desfecho == "Abandono")
      card(formata_num(n), "Abandono", "orange", "medkit")
    })

    output$box_contatos <- bs4Dash::renderbs4ValueBox({
      novos <- casos_novos()
      examinados <- sum(novos$contatos_examinados, na.rm = TRUE)
      registrados <- sum(novos$contatos_registrados, na.rm = TRUE)
      card(formata_pct(examinados / registrados), "Contatos examinados", "maroon", "people-arrows",
           rodape_texto(sprintf("%s de %s contatos registrados", formata_num(examinados), formata_num(registrados))))
    })

    # Casos novos com o grau de incapacidade avaliado no diagnostico
    # (indicador operacional do Ministerio; o ideal e' 100%). "Não avaliado"
    # e campo vazio ("Ignorado") contam como nao avaliados.
    output$box_gif_avaliado <- bs4Dash::renderbs4ValueBox({
      novos <- casos_novos()
      nao_avaliados <- sum(!novos$gif_diagnostico %in% c("Grau 0", "Grau I", "Grau II"))
      card(formata_pct(1 - nao_avaliados / nrow(novos)), "Grau de incapacidade avaliado no diagnóstico",
           "info", "clipboard-check",
           rodape_atalho("box_gif_avaliado_click", sprintf("Ver não avaliados: %s (%s)",
                                                           formata_num(nao_avaliados),
                                                           formata_pct(nao_avaliados / nrow(novos)))))
    })

    ## Table output ----

    output$casos_table <- reactable::renderReactable({
      shiny::req(casos_territorio())

      desfecho_cont <- casos_territorio() |>
        sf::st_drop_geometry() |>
        dplyr::count(desfecho) |>
        dplyr::right_join(desfecho_ids, by="desfecho") |>
        tidyr::replace_na(list(n=0)) |>
        dplyr::mutate(prop = n/max(1, sum(n))) |>
        dplyr::arrange(desfecho_id)

      # Barra com rotulo a esquerda. Fonte: https://glin.github.io/reactable/articles/cookbook/cookbook.html
      bar_chart <- function(label, width = "100%", height = "1rem", fill = "#00bfc4", background = NULL) {
        bar <- htmltools::div(style = list(background = fill, width = width, height = height))
        chart <- htmltools::div(style = list(flexGrow = 1, marginLeft = "0.5rem", background = background), bar)
        htmltools::div(style = list(display = "flex", alignItems = "center", fontWeight = 600), label, chart)
      }

      desfecho_cont |>
        reactable::reactable(
          columns = list(
            desfecho = reactable::colDef(name = "Desfecho"),
            desfecho_id = reactable::colDef(show=F),
            n = reactable::colDef(
              name = "Frequência",
              cell = function(value, index) {
                desf <- desfecho_cont$desfecho[index]
                prop <- desfecho_cont$prop[index]

                bg_color <- dplyr::coalesce(unname(cores_desfecho[desf]), cores_cen$tinta_3)

                width <- paste0(value/max(1, desfecho_cont$n) * 100, "%")
                bar_chart(paste0(formata_num(value), " (", formata_pct(prop), ")"),
                          fill = bg_color,
                          width = width)
              }
            ),
            prop = reactable::colDef(show=F)
          ),
          defaultSorted = list(n = "desc"),
          defaultPageSize = 15,
          sortable = F,
          selection = "multiple",
          defaultSelected = seq_len(nrow(desfecho_cont)),
          language = reactable_idioma
        )
    })

    output$tabela_casos <- reactable::renderReactable({
      shiny::req(casos_territorio())

      # So' as colunas exibidas
      casos_df <- casos_territorio() |>
        sf::st_drop_geometry() |>
        dplyr::select(
          numero_notificacao,
          dt_diagnostico,
          dt_notificacao,
          municipio_residencia,
          idade,
          sexo,
          classificacao_operacional,
          forma_clinica,
          gif_diagnostico,
          dt_alta,
          desfecho,
          tempo_aberto,
          georreferenciado
        )

      # Cores dos desfechos como objeto JS pra colorir a etiqueta no navegador
      cores_js <- paste0(
        "{",
        paste0(sprintf("'%s': '%s'", names(cores_desfecho), unname(cores_desfecho)), collapse = ", "),
        "}"
      )

      formato_data <- reactable::colFormat(date = TRUE, locales = "pt-BR")
      fundo <- list(background = "rgba(0, 0, 0, 0.02)")

      casos_df |>
        dplyr::mutate(
          georreferenciado = factor(georreferenciado, levels = c(0,1), labels = c("Não", "Sim")),
          idade = as.integer(floor(idade))
        ) |>
        reactable::reactable(
          columns = list(
            numero_notificacao = reactable::colDef(
              name = "Núm. Notificação", align = "center",
              # Celulas de Num. Notificacao, Desfecho e Georreferenciado
              # montadas no navegador (reactable::JS): uma tag HTML por linha
              # montada no R fica lenta e pesada com dezenas de milhares de
              # casos.
              cell = reactable::JS(sprintf(
                "function(cellInfo) {
                   return React.createElement('a', {
                     style: {color: '#0E7BA8', fontWeight: 'bold', textDecoration: 'underline', cursor: 'pointer'},
                     onClick: function() {
                       Shiny.setInputValue('%s', {id: String(cellInfo.value), random: Math.random()});
                     }
                   }, cellInfo.value);
                 }",
                ns("ver_detalhes_casos")
              ))
            ),
            dt_diagnostico = reactable::colDef(name = "Diagnóstico", format = formato_data, style = fundo),
            dt_notificacao = reactable::colDef(name = "Notificação", format = formato_data, style = fundo),
            municipio_residencia = reactable::colDef(name = "Município de residência", minWidth = 140),
            idade = reactable::colDef(name = "Idade", maxWidth = 80),
            sexo = reactable::colDef(name = "Sexo", maxWidth = 80),
            classificacao_operacional = reactable::colDef(name = "Classificação operacional", style = fundo),
            forma_clinica = reactable::colDef(name = "Forma clínica", style = fundo),
            gif_diagnostico = reactable::colDef(name = "GIF no diagnóstico", style = fundo),
            dt_alta = reactable::colDef(name = "Data de saída", format = formato_data),
            desfecho = reactable::colDef(
              name = "Desfecho",
              cell = reactable::JS(sprintf(
                "function(cellInfo) {
                   var cores = %s;
                   return React.createElement('span', {
                     style: {backgroundColor: cores[cellInfo.value] || '%s', color: 'white',
                             padding: '5px 15px', borderRadius: '20px', display: 'inline-block',
                             fontSize: '12px', fontWeight: 'bold'}
                   }, cellInfo.value);
                 }",
                cores_js, cores_cen$tinta_3
              )),
              minWidth = 140,
              align = "center"
            ),
            tempo_aberto = reactable::colDef(
              name = "Dias desde o diagnóstico",
              format = reactable::colFormat(suffix = " dias")
            ),
            georreferenciado = reactable::colDef(
              name = "Georreferenciado",
              style = fundo,
              # Simbolo de estado do guia (✓ adequado) no lugar de emoji; o
              # texto continua "Sim"/"Nao" pro filtro da coluna
              cell = reactable::JS(sprintf(
                "function(cellInfo) {
                   return cellInfo.value === 'Sim'
                     ? React.createElement('span', {style: {color: '%s', fontWeight: 700}}, '✓ Sim')
                     : React.createElement('span', {style: {color: '%s'}}, 'Não');
                 }",
                cores_cen$ok, cores_cen$tinta_3
              ))
            )
          ),
          columnGroups = list(
            reactable::colGroup(name = "Datas", columns = c("dt_diagnostico", "dt_notificacao")),
            reactable::colGroup(name = "Clínica",
                                columns = c("classificacao_operacional", "forma_clinica", "gif_diagnostico")),
            reactable::colGroup(name = "Saída", columns = c("dt_alta", "desfecho", "tempo_aberto"))
          ),
          language = reactable_idioma,
          filterable = TRUE
        )
    })

    ## Map output ----
    #
    # Mapa incremental: o mapa base (fundos, controle de camadas e visao
    # inicial) e' desenhado UMA vez por sessao, e cada camada e' atualizada
    # separadamente por leafletProxy, so' quando o que ela mostra muda:
    #   - casos: filtros, periodo e desfechos marcados na tabela de
    #     distribuicao;
    #   - indicador por municipio/GERES (ou contorno de PE): indicador,
    #     recorte, filtros e periodo;
    #   - contorno das GERES e quadro de Fernando de Noronha: fixos,
    #     desenhados uma vez;
    #   - contorno do territorio selecionado: quando a selecao muda (e o mapa
    #     se enquadra nele);
    #   - unidades de saude (S e ✕): desenhadas uma vez; a cada troca de
    #     filtro ou periodo vai so' a contagem de casos do hover.
    # O usuario continua no zoom/posicao em que estava, e o popup de um caso
    # so' e' montado quando ele e' clicado.

    grupos_mapa <- c("Casos", "Indicador por território", "GERES",
                     camadas_unidades$sus$grupo, camadas_unidades$outras$grupo)

    proxy_mapa <- function() leaflet::leafletProxy("main_map", session)

    # Com dados ficticios, selo fixo no mapa (aparece em qualquer captura de
    # tela do mapa, mesmo sem a faixa do topo da pagina)
    selo_ficticio_mapa <- function(mapa) {
      if (!ficticio) return(mapa)
      leaflet::addControl(mapa, html = "<div class='selo-ficticio selo-mapa'>DADOS FICTÍCIOS</div>",
                          position = "bottomleft")
    }

    output$main_map <- leaflet::renderLeaflet({
      # preferCanvas: pontos e poligonos desenhados num <canvas> em vez de
      # um elemento SVG por feicao -- bem mais rapido com milhares de casos.
      # A ordem de desenho e' mantida por js_ordena_camadas.
      leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
        leaflet::addProviderTiles("Esri.WorldGrayCanvas", group = 'Ruas') |>
        leaflet::addProviderTiles("Esri.WorldImagery",
                                  options = leaflet::providerTileOptions(opacity = 0.8),
                                  group = 'Satélite') |>
        # Pernambuco continental e o quadro de detalhe de Fernando de
        # Noronha, perto da costa (ver desloca_noronha() em R/fct_casos.R)
        leaflet::fitBounds(lng1 = limites_mapa()[1], lat1 = limites_mapa()[2],
                           lng2 = limites_mapa()[3], lat2 = limites_mapa()[4]) |>
        leaflet::addLayersControl(
          baseGroups = c("Ruas", "Satélite"),
          options = leaflet::layersControlOptions(collapsed = FALSE),
          overlayGroups = grupos_mapa
        ) |>
        # As unidades de saude comecam desligadas: o mapa abre com casos,
        # indicador e GERES, e as unidades entram quando o usuario liga a
        # camada no controle. Como o mapa nao e' recriado, dai' em diante
        # vale o que o usuario escolheu.
        leaflet::hideGroup(c(camadas_unidades$sus$grupo, camadas_unidades$outras$grupo)) |>
        selo_ficticio_mapa() |>
        com_plugin_agrupamento() |>
        # Os metodos ordenaCamadas e contagemUnidades sao registrados aqui,
        # quando o mapa e' criado: e' garantido que o leaflet ja' carregou e
        # que nenhuma chamada do servidor chegou ainda. Num <script> da pagina
        # eles dependiam da ordem de carregamento -- sem o ordenaCamadas, um
        # indicador redesenhado ficava por cima dos casos e escondia os pontos.
        htmlwidgets::onRender(paste0("
          function(el, x) {
            var map = this;", js_ordena_camadas, js_contagem_unidades, "
            // Camada religada no controle entra no fim da ordem de desenho --
            // refaz a ordem (ver js_ordena_camadas)
            map.on('overlayadd', function() { LeafletWidget.methods.ordenaCamadas.call(map); });
            // Avisa o servidor que o mapa existe: as camadas (leafletProxy)
            // so' sao desenhadas depois disso -- chamada de proxy que chega
            // antes do mapa existir no navegador se perde.
            Shiny.setInputValue(el.id + '_renderizado', Date.now());
          }
        "))
    })

    ### Contorno das GERES (fixo) ----

    shiny::observe({
      shiny::req(input$main_map_renderizado)

      geres <- malha_geres_desenho()

      proxy_mapa() |>
        leaflet::clearGroup("GERES") |>
        # Linha navy sobre um "halo" branco mais largo: continua visivel sobre
        # as paletas quentes e frias do indicador. Sem interacao (clickable =
        # FALSE) pra nao roubar o hover dos poligonos de indicador por baixo.
        leaflet::addPolygons(
          data = geres,
          fill = FALSE,
          weight = 5,
          color = "#FFFFFF",
          opacity = 0.55,
          group = 'GERES',
          options = leaflet::pathOptions(clickable = FALSE)
        ) |>
        leaflet::addPolygons(
          data = geres,
          fill = FALSE,
          weight = 2.5,
          color = navy_painel,
          opacity = 0.9,
          group = 'GERES',
          options = leaflet::pathOptions(clickable = FALSE)
        ) |>
        leaflet::addLabelOnlyMarkers(
          # ponto interno calculado na projecao (Policonica), nao em lon/lat
          data = malha_geres() |> sf::st_transform(5880) |> sf::st_geometry() |>
            sf::st_point_on_surface() |> sf::st_transform(4326),
          label = malha_geres()$geres,
          labelOptions = leaflet::labelOptions(
            noHide = TRUE,
            direction = "center",
            textOnly = TRUE,
            style = list(
              "color" = navy_painel,
              "font-weight" = "bold",
              "font-size" = "14px",
              "text-shadow" = "-1px -1px 0 #fff, 1px -1px 0 #fff, -1px 1px 0 #fff, 1px 1px 0 #fff, 0 0 4px #fff"
            )
          ),
          group = 'GERES'
        ) |>
        # Quadro de detalhe de Fernando de Noronha (ver desloca_noronha() em
        # R/fct_casos.R): moldura tracejada e nome, fora do controle de
        # camadas -- e' parte da leitura do mapa, como a escala
        leaflet::clearGroup("Noronha") |>
        leaflet::addRectangles(
          lng1 = quadro_noronha()[1], lat1 = quadro_noronha()[2],
          lng2 = quadro_noronha()[3], lat2 = quadro_noronha()[4],
          fill = FALSE,
          weight = 1.2,
          color = cores_cen$tinta_3,
          opacity = 0.9,
          dashArray = "4 3",
          group = "Noronha",
          options = leaflet::pathOptions(clickable = FALSE)
        ) |>
        leaflet::addLabelOnlyMarkers(
          lng = mean(quadro_noronha()[c(1, 3)]),
          lat = quadro_noronha()[2],
          label = "Fernando de Noronha",
          labelOptions = leaflet::labelOptions(
            noHide = TRUE,
            direction = "bottom",
            textOnly = TRUE,
            style = list(
              "color" = cores_cen$tinta_2,
              "font-weight" = "bold",
              "font-size" = "12px",
              "text-align" = "center",
              "line-height" = "1.2",
              "text-shadow" = "-1px -1px 0 #fff, 1px -1px 0 #fff, -1px 1px 0 #fff, 1px 1px 0 #fff, 0 0 4px #fff"
            )
          ),
          group = "Noronha"
        ) |>
        leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    ### Territorio selecionado: contorno e enquadramento ----

    # Contorno escuro (sobre um halo branco) do municipio/GERES selecionado
    # e o mapa enquadrado nele -- sem passar do zoom 10, pra continuar dando
    # pra clicar nos vizinhos. Ao limpar a selecao, volta pro estado
    # inteiro. So' quando a selecao muda (ignoreInit): na abertura o mapa ja'
    # esta' no estado inteiro.
    shiny::observeEvent(territorio_sel(), ignoreNULL = FALSE, ignoreInit = TRUE, {
      sel <- territorio_sel()

      m <- proxy_mapa() |>
        leaflet::clearGroup("Seleção")

      if (is.null(sel)) {
        lim <- limites_mapa()
        m |> leaflet::fitBounds(lim[1], lim[2], lim[3], lim[4])
        return()
      }

      geom <- if (sel$recorte == "municipio") {
        mun <- malha_municipios_desenho()
        mun[mun$code_muni == sel$chave, ]
      } else {
        geres <- malha_geres_desenho()
        geres[geres$geres == sel$chave, ]
      }
      bb <- sf::st_bbox(geom)

      m |>
        leaflet::addPolygons(data = geom, fill = FALSE, weight = 7, color = "#FFFFFF", opacity = 0.85,
                             group = "Seleção", options = leaflet::pathOptions(clickable = FALSE)) |>
        leaflet::addPolygons(data = geom, fill = FALSE, weight = 3.5, color = cores_cen$tinta, opacity = 1,
                             group = "Seleção", options = leaflet::pathOptions(clickable = FALSE)) |>
        leaflet::fitBounds(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]],
                           options = list(maxZoom = 10, padding = c(30, 30))) |>
        leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    ### Unidades de saude (CNES) ----

    # Desenhadas uma vez por sessao (local/unidades_cnes.rds, gerado por
    # dev/build_unidades_cnes.R -- sem o arquivo, as camadas ficam vazias).
    unidades_desenhadas <- shiny::reactiveVal(FALSE)

    shiny::observe({
      shiny::req(input$main_map_renderizado)

      unidades <- carrega_unidades()

      proxy_mapa() |>
        leaflet::clearGroup(camadas_unidades$sus$grupo) |>
        leaflet::clearGroup(camadas_unidades$outras$grupo) |>
        adicionar_camada_unidades(unidades[unidades$publica %in% TRUE, ], camadas_unidades$sus) |>
        adicionar_camada_unidades(unidades[!unidades$publica %in% TRUE, ], camadas_unidades$outras)

      unidades_desenhadas(nrow(unidades) > 0)
    })

    # Casos notificados por unidade no filtro/periodo atual, pro hover das
    # unidades (ver js_contagem_unidades no topo do arquivo)
    shiny::observe({
      shiny::req(input$main_map_renderizado, unidades_desenhadas())

      contagem <- casos_filtered() |>
        sf::st_drop_geometry() |>
        dplyr::filter(!is.na(cod_unidade_notificadora)) |>
        dplyr::count(cod_unidade_notificadora)

      proxy_mapa() |>
        leaflet::invokeMethod(
          NULL, "contagemUnidades",
          as.list(stats::setNames(contagem$n, contagem$cod_unidade_notificadora))
        )
    })

    ### Indicador por territorio (municipio / GERES) ----

    shiny::observe({
      shiny::req(input$main_map_renderizado)

      m <- proxy_mapa() |>
        leaflet::clearGroup("Indicador por território") |>
        leaflet::clearGroup("Pernambuco") |>
        leaflet::removeControl("legenda_indicador")

      if (isTRUE(input$show_indicador)) {

        recorte <- if (input$nivel_territorial == "geres") "geres" else "municipio"
        ind_terr <- if (recorte == "geres") ind_geres() else ind_municipio()
        cfg <- config_indicadores[[input$indicador]]

        # Opacidade do mapa de indicadores
        opacidade_ind <- 0.7

        pal_ind <- leaflet::colorBin(cfg$paleta, domain = NULL, bins = cfg$bins, na.color = "#E6E6E6")
        # Cores das faixas no meio de cada uma (a ultima pode ser Inf); a
        # entrada cinza so' quando algum territorio ficou sem valor
        meio_faixas <- (utils::head(cfg$bins, -1) + pmin(utils::tail(cfg$bins, -1), 1e6)) / 2
        sem_valor <- anyNA(ind_terr$ind)

        m <- m |>
          leaflet::addPolygons(
            data = ind_terr,
            # "<recorte>|<chave>": o clique seleciona o territorio (ver
            # territorio_sel())
            layerId = paste0(recorte, "|", if (recorte == "geres") ind_terr$geres else ind_terr$code_muni),
            fillColor = pal_ind(ind_terr$ind),
            weight = 0.8,
            opacity = 1,
            color = "white",
            fillOpacity = opacidade_ind,
            group = 'Indicador por território',
            highlightOptions = leaflet::highlightOptions(
              weight = 2,
              color = cores_cen$tinta_2,
              fillOpacity = opacidade_ind,
              bringToFront = F),
            label = hover_indicador(
              ind_terr, input$indicador,
              dica = if (recorte == "geres") "Clique para ver só esta GERES" else "Clique para ver só este município"
            ),
            labelOptions = leaflet::labelOptions(
              style = list("font-weight" = "normal", padding = "3px 8px"),
              textsize = "15px",
              direction = "auto")
          ) |>
          leaflet::addLegend(
            colors = c(pal_ind(meio_faixas), if (sem_valor) "#E6E6E6"),
            labels = c(rotulos_legenda(cfg), if (sem_valor) cfg$sem_dado),
            opacity = opacidade_ind,
            title = htmltools::HTML(cfg$titulo),
            position = "bottomright",
            layerId = "legenda_indicador"
          )
      } else {
        m <- m |>
          leaflet::addPolygons(
            data = malha_geres_desenho(),
            weight = 1,
            color = cores_cen$azul,
            fillOpacity = 0.15,
            group = 'Pernambuco'
          )
      }

      m |> leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    ### Casos no mapa ----

    # Pontos desenhados no mapa agora, na ordem dos ids "caso_<n>" -- o
    # popup do clique e' montado a partir daqui.
    casos_desenhados <- shiny::reactiveVal(NULL)

    shiny::observe({
      shiny::req(input$main_map_renderizado)

      casos <- casos_points() |>
        dplyr::filter(georreferenciado == 1, !sf::st_is_empty(geometry))

      m <- proxy_mapa() |>
        leaflet::clearGroup("Casos")

      if (nrow(casos) > 0) {
        label_info <- sprintf(
          "%s, %s ano%s, %s: <b>%s</b>",
          casos$sexo,
          floor(casos$idade),
          ifelse(floor(casos$idade) == 1, "", "s"),
          casos$classificacao_operacional,
          casos$desfecho
        ) |> lapply(htmltools::HTML)

        # levels explicitos: cor e ordem da legenda seguem cores_desfecho
        pal <- leaflet::colorFactor(unname(cores_desfecho), domain = NULL, levels = names(cores_desfecho))

        # Casos de Fernando de Noronha vao pro quadro de detalhe
        # (desloca_noronha_xy() em R/fct_casos.R)
        xy <- sf::st_coordinates(casos)
        xy <- desloca_noronha_xy(xy[, "X"], xy[, "Y"])

        m <- m |>
          leaflet::addCircleMarkers(
            lng = xy$x,
            lat = xy$y,
            # "caso_<n>": linha de casos_desenhados(), pro popup do clique
            layerId = paste0("caso_", seq_len(nrow(casos))),
            radius = 3.5,
            fillColor = pal(casos$desfecho),
            fillOpacity = 0.95,
            # contorno branco fino: destaca o ponto sobre qualquer cor do
            # indicador por baixo
            stroke = TRUE,
            color = "#FFFFFF",
            weight = 0.75,
            opacity = 0.6,
            label = label_info,
            group = 'Casos',
            # Sem pane proprio: no Leaflet 1.3 pane personalizado desenha em
            # SVG (ignora preferCanvas) e roubaria o hover das camadas de baixo.
            options = leaflet::pathOptions()
          ) |> leaflet::addLegend(
            pal = pal, values = casos$desfecho,
            opacity = 0.7, title = NULL,
            position = "bottomleft",
            layerId = "legenda_casos"
          )
      } else {
        m <- m |> leaflet::removeControl("legenda_casos")
      }

      casos_desenhados(casos)

      m |> leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    # Popup do caso clicado, montado na hora
    shiny::observeEvent(input$main_map_marker_click, {
      clique <- input$main_map_marker_click
      if (is.null(clique$id) || !startsWith(clique$id, "caso_")) return()

      casos <- casos_desenhados()
      n <- suppressWarnings(as.integer(sub("^caso_", "", clique$id)))
      if (is.null(casos) || is.na(n) || n < 1 || n > nrow(casos)) return()

      proxy_mapa() |>
        leaflet::addPopups(
          lng = clique$lng, lat = clique$lat,
          popup = popup_caso(casos[n, ]),
          layerId = "popup_caso"
        )
    })

  })
}
