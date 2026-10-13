#' app_theme
#'
#' @description A utils function
#'
#' @return The return value, if any, from executing the utility.
#'
#' @noRd
# Identidade visual: guia "Documentacao -- ID visual para paineis" do
# Programa Cenarios (cenarios.unb.br), com a excecao herdada do painel de TB
# de Recife -- o navy #12346B continua como "primary",
# que o bs4Dash usa nas barras estrategicas: cabecalho e barras de titulo
# das caixas (Mapa de casos, Tabela de casos, borda da caixa de Filtros).
# Todo o resto segue o guia: azul Cenarios (#3891C0) como "info", cores de
# estado do guia pra success/warning/danger, fundo #F2F6F9, DM Sans no
# corpo (Poppins nos titulos, botoes em azul acao etc. vem do CSS em
# inst/app/badges_inline.css, que tambem traz os tokens --cen-*).
app_theme <- fresh::create_theme(
  fresh::bs4dash_vars(
    navbar_light_color = "#E6F1F7",
    navbar_light_active_color = "#FFF",
    navbar_light_hover_color = "#FFF"
  ),
  fresh::bs4dash_yiq(
    contrasted_threshold = 150,
    text_dark = "#12222B",
    text_light = "#FFF"
  ),
  fresh::bs4dash_layout(
    main_bg = "#F2F6F9"
  ),
  fresh::bs4dash_font(
    family_sans_serif = "'DM Sans', 'Helvetica Neue', Arial, sans-serif"
  ),
  fresh::bs4dash_status(
    primary = "#12346B", # navy (barras estrategicas)
    info = "#3891C0",
    success = "#1F6F4A",
    warning = "#8A6100",
    danger = "#A32235"
  )
)
