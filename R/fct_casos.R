# R/fct_casos.R -- carga dos casos e das malhas, compartilhada entre sessoes
# ==================================================================================
# No Shiny Server todas as sessoes do painel (cada usuario que abre a pagina)
# rodam no mesmo processo R. Casos e malhas sao carregados uma vez por
# processo e reaproveitados por toda sessao nova (carrega_casos(),
# malha_*()); os casos recarregam sozinhos quando o cache muda no disco
# (base remontada por prepara_base(), em R/fct_db_update.R).
#
# Cada caso ja' sai com o municipio e a GERES de residencia
# (atribui_territorio()), gravados no cache por update_hans_data(): os
# indicadores por territorio contam por essas colunas.
# ==================================================================================

cache_processo <- new.env(parent = emptyenv())

# Guarda em cache_processo o resultado de `expr` na primeira chamada; as
# seguintes (inclusive de outras sessoes) devolvem o mesmo objeto.
memo_processo <- function(chave, expr) {
  if (is.null(cache_processo[[chave]])) cache_processo[[chave]] <- force(expr)
  cache_processo[[chave]]
}

caminho_shape <- function(arquivo) {
  app_sys("app/www/shapes", arquivo)
}

# 185 municipios de Pernambuco, com GERES, populacao total e de menores de
# 15 anos (Censo 2022) -- gerados por dev/build_malhas_pe.R, ja'
# simplificados pro desenho sem abrir frestas entre vizinhos. SIRGAS 2000
# geografico (EPSG 4674); nenhum calculo do painel e' espacial (o territorio
# do caso vem do codigo do municipio de residencia), entao nao ha' projecao.
malha_municipios <- function() {
  memo_processo("malha_municipios", {
    sf::st_read(caminho_shape("municipios_pe.gpkg"), quiet = TRUE)
  })
}

# 12 Gerencias Regionais de Saude (uniao dos municipios de cada uma)
malha_geres <- function() {
  memo_processo("malha_geres", {
    sf::st_read(caminho_shape("geres_pe.gpkg"), quiet = TRUE)
  })
}

# Municipio (territorio_municipio, code_muni de 7 digitos) e GERES
# (territorio_geres) de residencia de cada caso, pelo codigo IBGE do SINAN
# (ID_MN_RESI, 6 digitos). NA = residente fora de Pernambuco ou sem
# municipio de residencia -- fica fora dos indicadores por territorio, mas
# continua nos cards, no mapa e na tabela de casos.
#
# Pelo codigo, e nao pela coordenada: o municipio de residencia vem
# preenchido mesmo nos casos que a pipeline nao conseguiu georreferenciar
# (centroide), e a taxa de deteccao usa o municipio de residencia.
atribui_territorio <- function(casos) {
  mun <- malha_municipios()
  idx <- match(casos$cod_mun_residencia, mun$cod_muni6)
  casos$territorio_municipio <- mun$code_muni[idx]
  casos$territorio_geres <- mun$geres[idx]
  casos$municipio_residencia <- mun$nome[idx]
  casos
}

# hans_sinan_treated (DuckDB) -> casos do painel: pontos em WGS 84 (caso sem
# coordenada vira ponto vazio), tempo de tratamento e territorio
# (atribui_territorio()). Usado pra gerar local/casos_cache.rds
# (update_hans_data()) e na carga direta do DuckDB quando o cache nao existe.
prepara_casos <- function(casos_raw) {
  casos_raw <- dplyr::as_tibble(casos_raw)

  last_date <- max(casos_raw$dt_notificacao, na.rm = TRUE)

  casos_raw |>
    # na.fail = FALSE: caso sem coordenada vira ponto vazio em vez de
    # derrubar o cache inteiro (fica fora do mapa, mas continua nos cards,
    # nos indicadores por territorio e na tabela de casos)
    sf::st_as_sf(coords = c("long", "lat"), crs = 4674, na.fail = FALSE) |>
    sf::st_transform(4326) |>
    dplyr::mutate(
      # Dias desde o diagnostico ate' a saida (encerrados) ou ate' a ultima
      # notificacao da base (em tratamento)
      tempo_aberto = dplyr::case_when(
        situacao == "Encerrado" ~ as.integer(difftime(dt_alta, dt_diagnostico, units = "days")),
        TRUE                    ~ as.integer(difftime(last_date, dt_diagnostico, units = "days"))
      )
    ) |>
    atribui_territorio()
}

# Casos do painel, compartilhados entre as sessoes do processo. Le'
# local/casos_cache.rds (ou, sem ele, o DuckDB) so' na primeira chamada ou
# quando o arquivo muda.
carrega_casos <- function() {
  arq <- "local/casos_cache.rds"
  versao <- if (file.exists(arq)) file.mtime(arq) else "sem cache"

  if (!is.null(cache_processo$casos) && identical(cache_processo$casos_versao, versao)) {
    return(cache_processo$casos)
  }

  casos <- if (file.exists(arq)) {
    readRDS(arq)
  } else {
    con <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb", read_only = TRUE)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    prepara_casos(DBI::dbGetQuery(con, "select * from hans_sinan_treated"))
  }

  # Cache gerado antes do codigo CNES ir com 7 digitos (update_hans_data()
  # anterior): completa aqui, pra casar com a camada de unidades de saude.
  casos$cod_unidade_notificadora <- normaliza_cnes(casos$cod_unidade_notificadora)

  cache_processo$casos <- casos
  cache_processo$casos_versao <- versao
  casos
}

# Codigo CNES com 7 digitos. O SINAN (ID_UNIDADE) e a API do CNES trazem o
# codigo como numero, sem os zeros a esquerda (434 = 0000434, o IMIP). O que
# nao for codigo (vazio, texto) vira NA.
normaliza_cnes <- function(x) {
  x <- sub("\\.0+$", "", trimws(as.character(x)))
  codigo <- rep(NA_character_, length(x))
  ok <- !is.na(x) & grepl("^[0-9]{1,7}$", x)
  codigo[ok] <- sprintf("%07d", as.integer(x[ok]))
  codigo
}

# Unidades de saude do mapa (rede SUS e outras notificadoras), em
# local/unidades_cnes.rds -- copiado do cadastro publico do pacote
# (inst/extdata/dados_ficticios) por prepara_base(), ou regerado por
# dev/build_unidades_cnes.R. Sem ele, as camadas de unidades ficam vazias.
# Compartilhadas entre as sessoes, relidas quando o arquivo muda.
carrega_unidades <- function() {
  arq <- "local/unidades_cnes.rds"
  versao <- if (file.exists(arq)) file.mtime(arq) else "sem arquivo"

  if (!is.null(cache_processo$unidades) && identical(cache_processo$unidades_versao, versao)) {
    return(cache_processo$unidades)
  }

  unidades <- if (file.exists(arq)) {
    readRDS(arq)
  } else {
    tibble::tibble(
      codigo_cnes = character(), nome = character(), tipo_unidade = character(),
      natureza = character(), publica = logical(), cod_municipio = character(), municipio = character(),
      latitude = double(), longitude = double(), fonte_coordenada = character(),
      aproximada = logical()
    )
  }

  cache_processo$unidades <- unidades
  cache_processo$unidades_versao <- versao
  unidades
}

# Datas de diagnostico da base (limites do filtro de periodo) e periodo
# inicial do painel: do 1o de janeiro do ano mais recente ate' a ultima data
# de diagnostico. Sem base, o ultimo ano ate' hoje.
limites_periodo <- function() {
  tem_base <- file.exists("local/casos_cache.rds") || file.exists("local/sinan.duckdb")
  casos <- if (tem_base) tryCatch(carrega_casos(), error = function(e) NULL)
  datas <- if (is.null(casos)) as.Date(NA) else casos$dt_diagnostico
  if (all(is.na(datas))) return(c(as.Date("2001-01-01"), Sys.Date()))
  range(datas, na.rm = TRUE)
}

periodo_padrao <- function() {
  lim <- limites_periodo()
  c(max(lim[1], lubridate::floor_date(lim[2], "year")), lim[2])
}

# Fernando de Noronha no mapa. O arquipelago fica a ~550 km da costa, fora
# do enquadramento do estado e pequeno demais pra ver nele. No desenho -- so'
# no desenho -- ele vai pra um quadro de detalhe perto da costa norte de PE,
# ampliado: municipio, GERES I, casos e unidades de saude que estao nele.
# Nenhum calculo usa coordenadas (o territorio do caso vem do codigo do
# municipio de residencia), entao os numeros nao mudam.
noronha <- list(
  # arquipelago real (WGS 84), com folga
  caixa = c(xmin = -32.55, ymin = -3.95, xmax = -32.30, ymax = -3.74),
  centro = c(-32.4267, -3.8430),
  # centro do quadro de detalhe: no mar, a leste do Recife, longe do
  # controle de camadas do mapa (canto de cima a' direita)
  destino = c(-34.05, -8.40),
  escala = 4
)

no_arquipelago <- function(x, y) {
  !is.na(x) & !is.na(y) &
    x >= noronha$caixa[["xmin"]] & x <= noronha$caixa[["xmax"]] &
    y >= noronha$caixa[["ymin"]] & y <= noronha$caixa[["ymax"]]
}

# Coordenadas no arquipelago vao pro quadro de detalhe; as demais ficam
# onde estao
desloca_noronha_xy <- function(x, y) {
  dentro <- no_arquipelago(x, y)
  x[dentro] <- noronha$destino[1] + noronha$escala * (x[dentro] - noronha$centro[1])
  y[dentro] <- noronha$destino[2] + noronha$escala * (y[dentro] - noronha$centro[2])
  list(x = x, y = y)
}

# Mesma coisa pra poligonos em WGS 84: anel inteiramente no arquipelago (as
# ilhas do municipio, e as da GERES I) vai pro quadro; o resto da feicao (o
# continente da GERES I) fica onde esta'.
desloca_noronha <- function(malha) {
  ajusta <- function(m) {
    if (!all(no_arquipelago(m[, 1], m[, 2]))) return(m)
    novo <- desloca_noronha_xy(m[, 1], m[, 2])
    m[, 1] <- novo$x
    m[, 2] <- novo$y
    m
  }
  percorre <- function(x) if (is.matrix(x)) ajusta(x) else lapply(x, percorre)
  geom <- sf::st_geometry(malha)
  novas <- lapply(geom, function(g) structure(percorre(unclass(g)), class = class(g)))
  sf::st_set_geometry(malha, sf::st_sfc(novas, crs = sf::st_crs(geom)))
}

# Malhas em WGS 84 pro desenho no mapa, com Noronha no quadro de detalhe.
# Nao simplifica aqui: os gpkg ja' vem simplificados por
# dev/build_malhas_pe.R, que mantem a mesma divisa nos dois vizinhos --
# simplificar cada poligono de novo, por conta propria, abriria frestas
# entre eles e tiraria o contorno das GERES de cima das divisas municipais.
malha_municipios_desenho <- function() {
  memo_processo("malha_municipios_desenho", desloca_noronha(sf::st_transform(malha_municipios(), 4326)))
}

malha_geres_desenho <- function() {
  memo_processo("malha_geres_desenho", desloca_noronha(sf::st_transform(malha_geres(), 4326)))
}

# Ponto interno de cada municipio em lon/lat (WGS 84), na ordem de
# malha_municipios() -- onde fica o balao com o numero de casos do
# municipio no mapa (zoom afastado). Da malha do desenho, com Noronha no
# quadro de detalhe; calculado em Web Mercator, nao em lon/lat.
pontos_internos_municipios <- function() {
  memo_processo("pontos_internos_municipios", {
    pontos <- malha_municipios_desenho() |>
      sf::st_transform(3857) |>
      sf::st_geometry() |>
      sf::st_point_on_surface() |>
      sf::st_transform(4326)
    sf::st_coordinates(pontos)
  })
}

# Quadro de detalhe de Noronha (lng1, lat1, lng2, lat2): extensao das ilhas
# deslocadas, com margem
quadro_noronha <- function() {
  memo_processo("quadro_noronha", {
    mun <- malha_municipios_desenho()
    bb <- sf::st_bbox(mun[mun$code_muni == "2605459", ])
    margem <- 0.1
    unname(c(bb[["xmin"]] - margem, bb[["ymin"]] - margem, bb[["xmax"]] + margem, bb[["ymax"]] + margem))
  })
}

# Enquadramento do mapa do estado (lng1, lat1, lng2, lat2): o continente e o
# quadro de Noronha, com folga a leste pro nome dele (centralizado embaixo
# do quadro e mais largo que ele)
limites_mapa <- function() {
  memo_processo("limites_mapa", {
    mun <- malha_municipios_desenho()
    bb <- sf::st_bbox(mun[mun$code_muni != "2605459", ])
    q <- quadro_noronha()
    c(min(bb[["xmin"]], q[1]), min(bb[["ymin"]], q[2]), max(bb[["xmax"]], q[3] + 0.5), max(bb[["ymax"]], q[4]))
  })
}
