#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_ui <- function(request) {
  # Monta ou atualiza a base antes de desenhar a pagina: os avisos de DADOS
  # FICTICIOS dependem da origem da base carregada (ver prepara_base() e
  # dados_sao_ficticios() em R/fct_db_update.R)
  prepara_base()
  ficticio <- dados_sao_ficticios()

  shiny::tagList(
    # Leave this function for adding external resources
    golem_add_external_resources(ficticio),
    # Your application UI logic
    bs4Dash::bs4DashPage(
      header = bs4Dash::bs4DashNavbar(
        title = NULL,
        status = "primary",
        skin = "dark",
        shiny::column(
          3,
          htmltools::div(
            style = "display: flex; align-items: center; gap: 10px;",
            htmltools::img(src = "www/cenarios_logo_full.png", height = "40px", style = "margin-top: 4px;", class = "logo-cenarios")
          )
        ),

        htmltools::div(
          style = "flex: 1 1 auto; display: flex; align-items: center; justify-content: center; gap: 12px;",
          htmltools::h4(
            "SINAN Territórios: Hanseníase – Pernambuco",
            style = "color: #FFFFFF; margin: 0; font-weight: 600; white-space: nowrap;"
          ),
          # Com dados ficticios, selo permanente no cabecalho
          if (ficticio) {
            htmltools::span(
              class = "selo-ficticio",
              title = "Versão de demonstração: todos os casos foram gerados por simulação",
              shiny::icon("triangle-exclamation"), " DADOS FICTÍCIOS"
            )
          }
        ),

        shiny::column(3,
                      shiny::uiOutput("municipio_1-db_info_ui"),
                      align="right"
                      )
      ),

      sidebar = bs4Dash::bs4DashSidebar(disable = TRUE),

      body = bs4Dash::bs4DashBody(
        shinyjs::useShinyjs(),
        shinytoastr::useToastr(),
        if (ficticio) {
          htmltools::div(
            class = "faixa-ficticia",
            role = "alert",
            shiny::icon("triangle-exclamation"),
            htmltools::span(htmltools::HTML(paste0(
              "<b>DADOS FICTÍCIOS</b> &mdash; versão de demonstração do painel. ",
              "Todos os casos, nomes, endereços e datas foram gerados por simulação ",
              "e não correspondem a pessoas reais. Os números reproduzem apenas a ordem de ",
              "grandeza dos indicadores de hanseníase de Pernambuco."
            )))
          )
        },
        mod_municipio_ui("municipio_1")
      )
    )
  )
}

#' Add external Resources to the Application
#'
#' This function is internally used to add external
#' resources inside the Shiny application.
#'
#' @import shiny
#' @importFrom golem add_resource_path activate_js favicon bundle_resources
#' @noRd
golem_add_external_resources <- function(ficticio = TRUE) {
  golem::add_resource_path(
    "www",
    app_sys("app/www")
  )

  # CSS de customizacao (cores dos cards, navbar, etc.) embutido inline no HTML
  # em vez de carregado como arquivo externo (.css) -- assim ele chega sempre
  # atualizado a cada carregamento da pagina, sem depender de cache de arquivo
  # do navegador (usuarios que ja visitaram o painel antes de uma mudanca de
  # cor nao ficam presos numa versao antiga em cache).
  # Le' o CSS da pasta do app quando ela existe (servidor rodando direto do
  # clone do git) em vez do pacote instalado -- assim mudanca de CSS entra
  # com um `git pull`, sem precisar reinstalar o pacote.
  css_path <- if (file.exists("inst/app/badges_inline.css")) "inst/app/badges_inline.css" else app_sys("app/badges_inline.css")
  inline_css <- paste(readLines(css_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  tags$head(
    golem::favicon(),
    # Fontes do guia de identidade visual dos paineis Cenarios: Poppins 700
    # (titulos) e DM Sans 400/700 (corpo, rotulos, tabelas, numeros de KPI)
    tags$link(rel = "preconnect", href = "https://fonts.googleapis.com"),
    tags$link(rel = "preconnect", href = "https://fonts.gstatic.com", crossorigin = NA),
    tags$link(
      rel = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;700&family=Poppins:wght@700&display=swap"
    ),
    fresh::use_theme(app_theme),
    golem::bundle_resources(
      path = app_sys("app/www"),
      app_title = paste0("SINAN Territórios Hanseníase PE", if (ficticio) " (dados fictícios)")
    ),
    htmltools::tags$style(htmltools::HTML(inline_css))
    # Add here other external resources
    # for example, you can add shinyalert::useShinyalert()
  )
}
