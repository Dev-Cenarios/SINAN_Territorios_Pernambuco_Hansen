# dev/build_shinylive.R -- versao web do painel (Shinylive), para o GitHub Pages
# ==================================================================================
# Exporta o painel para rodar inteiro no navegador de quem visita (R compilado
# para WebAssembly, o webR), sem servidor R. O resultado e' um site estatico
# em site/ (nao versionado no main), publicado no branch gh-pages.
#
# SO' COM OS DADOS FICTICIOS: o script para se a variavel de dados reais
# (PAINEL_HANSEN_PE_DADOS_REAIS_DIR) estiver definida ou se a base local nao for a
# ficticia -- o site e' publico.
#
# A base vai pronta (os caches de local/, montados aqui): o navegador nao
# refaz a carga do CSV, so' le os caches, e abre mais rapido.
#
# Uso (na raiz do projeto):
#   Rscript dev/build_shinylive.R
# Para ver o site localmente antes de publicar:
#   Rscript -e "httpuv::runStaticServer('site', port = 8009)"
# Para publicar, ver README ("Versao web").
# ==================================================================================

pkgload::load_all(".", quiet = TRUE)
sf::sf_use_s2(FALSE)

if (nzchar(Sys.getenv("PAINEL_HANSEN_PE_DADOS_REAIS_DIR"))) {
  stop("PAINEL_HANSEN_PE_DADOS_REAIS_DIR esta' definido: a versao web e' publica e so' pode ter os dados ficticios.")
}
prepara_base()
if (!dados_sao_ficticios()) stop("A base local nao e' a ficticia: a versao web e' publica.")

# ---- Pasta do app web ----
app_web <- file.path(tempdir(), "app_web")
unlink(app_web, recursive = TRUE)
dir.create(file.path(app_web, "local"), recursive = TRUE)

# So' o codigo que o painel executa -- sem a montagem da base
# (fct_db_update.R, que usa o DuckDB: a base vai pronta), os scripts de
# preparacao offline e os utilitarios genericos do golem, que trariam pacotes
# que o navegador baixaria a toa. Numa pasta que nao se chama R/: o Shiny
# carregaria R/ sozinho, num ambiente onde as definicoes do app.R abaixo nao
# valeriam.
codigo <- c("app_config.R", "app_ui.R", "app_server.R", "mod_municipio.R", "fct_casos.R", "utils_app_theme.R")
dir.create(file.path(app_web, "codigo"))
file.copy(file.path("R", codigo), file.path(app_web, "codigo"))

# Arquivos internos (CSS, imagens, malhas) -- sem os CSVs de inst/extdata,
# que o navegador nao usa
dir.create(file.path(app_web, "inst"))
file.copy("inst/app", file.path(app_web, "inst"), recursive = TRUE)
file.copy("inst/golem-config.yml", file.path(app_web, "inst"))

# Base ficticia pronta
caches <- c("casos_cache.rds", "unidades_cnes.rds", "fonte_dados.rds")
file.copy(file.path("local", caches[file.exists(file.path("local", caches))]), file.path(app_web, "local"))

writeLines(c(
  "# Versao web (Shinylive) do painel, gerada por dev/build_shinylive.R: roda no",
  "# navegador, com a base ficticia ja' montada em local/.",
  "# O que o NAMESPACE do pacote importa",
  "library(shiny)",
  "`%>%` <- magrittr::`%>%`",
  "# Tudo no ambiente deste arquivo, para as definicoes abaixo valerem dentro",
  "# das funcoes do painel",
  "for (arquivo in list.files('codigo', pattern = '[.][Rr]$', full.names = TRUE)) {",
  "  source(arquivo, local = TRUE, encoding = 'UTF-8')",
  "}",
  "# A base vem pronta e e' sempre a ficticia (o build recusa outra): nada a",
  "# montar no navegador, e os avisos de dados ficticios sempre ligados",
  "prepara_base <- function() invisible('ficticio')",
  "dados_sao_ficticios <- function() TRUE",
  "options(shiny.sanitize.errors = TRUE)",
  "shiny::shinyApp(ui = app_ui, server = app_server)"
), file.path(app_web, "app.R"))

# ---- Exporta ----
unlink("site", recursive = TRUE)
shinylive::export(app_web, "site")

# Sem isso o GitHub Pages (Jekyll) ignora arquivos e pastas que comecam com "_"
file.create(file.path("site", ".nojekyll"))

tamanho <- sum(file.info(list.files("site", recursive = TRUE, full.names = TRUE, all.files = TRUE))$size)
message(sprintf("Site gerado em site/ (%.0f MB).", tamanho / 1024^2))
