# dev/build_unidades_cnes.R -- unidades de saude do mapa (Pernambuco)
# ==================================================================================
# Monta local/unidades_cnes.rds, lido pelas camadas "Rede SUS (S)" e "Outras
# notificadoras (✕)" do mapa:
#   - Rede SUS: toda a rede publica assistencial de Pernambuco (postos,
#     UBS/USF, policlinicas, hospitais publicos, UPA, CAPS...), mesmo sem
#     caso notificado;
#   - Outras notificadoras: as demais unidades que aparecem como
#     notificadoras nos casos do painel (filantropicas, privadas...).
# Dados da API publica do CNES/DATASUS (coordenada, tipo, natureza juridica,
# habilitacao). Em Recife, a coordenada da rede municipal vem da camada
# oficial da SESAU no ESIG, como no painel de TB de Recife -- la' a do CNES
# erra bastante.
#
# Os codigos das unidades notificadoras saem dos casos da base local: rode
# depois de a base local estar montada (prepara_base(), que roda ao abrir o
# painel). Precisa de internet. Rode na raiz do projeto, no
# ambiente onde o painel vai ler o arquivo (local/ nao e' versionado):
#   Rscript dev/build_unidades_cnes.R
# Leva alguns minutos: a API devolve 20 unidades por pagina.
# ==================================================================================

pkgload::load_all(".", quiet = TRUE)
sf::sf_use_s2(FALSE)

`%||%` <- function(a, b) if (is.null(a)) b else a

API_CNES <- "https://apidadosabertos.saude.gov.br/cnes/estabelecimentos"
CODIGO_UF <- 26
CODIGO_RECIFE <- "261160"

# Coordenada ate' esta distancia fora do proprio municipio e' puxada pra
# borda (impreciso da coordenada ou da malha, simplificada a 100 m); mais
# longe que isso, a unidade vai pra sede do municipio, marcada como
# localizacao aproximada.
TOLERANCIA_M <- 500

# Rotulos dos tipos de unidade do CNES (lista completa em
# https://apidadosabertos.saude.gov.br/cnes/tipounidades)
TIPOS_UNIDADE <- c(
  "1" = "Posto de saúde", "2" = "Unidade básica de saúde (UBS/USF)", "4" = "Policlínica",
  "5" = "Hospital geral", "7" = "Hospital especializado", "15" = "Unidade mista",
  "20" = "Pronto-socorro geral", "21" = "Pronto-socorro especializado", "22" = "Consultório isolado",
  "32" = "Unidade móvel fluvial", "36" = "Clínica / centro de especialidade",
  "39" = "Apoio diagnóstico e terapia (SADT)", "40" = "Unidade móvel terrestre",
  "42" = "Unidade móvel de urgência", "43" = "Farmácia", "50" = "Vigilância em saúde",
  "60" = "Cooperativa / cessão de trabalhadores", "61" = "Centro de parto normal", "62" = "Hospital-dia",
  "64" = "Central de regulação", "67" = "Laboratório central (LACEN)", "68" = "Gestão em saúde",
  "69" = "Hemoterapia / hematologia", "70" = "Centro de Atenção Psicossocial (CAPS)",
  "71" = "Centro de apoio à saúde da família", "72" = "Atenção à saúde indígena",
  "73" = "Pronto atendimento (UPA)", "74" = "Polo Academia da Saúde", "75" = "Telessaúde",
  "76" = "Regulação médica das urgências", "77" = "Atenção domiciliar", "78" = "Atenção em regime residencial",
  "79" = "Oficina ortopédica", "80" = "Laboratório de saúde pública", "81" = "Regulação do acesso",
  "82" = "Central de captação de órgãos", "83" = "Prevenção e promoção da saúde",
  "84" = "Central de abastecimento", "85" = "Centro de imunização"
)

# Tipos assistenciais da rede publica que entram no mapa mesmo sem notificar
# caso: atencao basica, urgencia, especializada e hospitalar. Ficam de fora
# ambulancias, farmacias, laboratorios, vigilancia, gestao, regulacao,
# academias etc. (entram so' se notificaram algum caso). Mesma lista do
# painel de TB de Recife.
TIPOS_REDE_SUS <- c(1, 2, 4, 5, 7, 15, 20, 21, 36, 61, 62, 70, 73)

## 1. Unidades notificadoras dos casos ----

if (!file.exists("local/casos_cache.rds") && !file.exists("local/sinan.duckdb")) {
  stop("Base local nao encontrada: rode a atualizacao de dados antes (update_hans_data()).")
}
codigos_casos <- unique(stats::na.omit(carrega_casos()$cod_unidade_notificadora))
message(sprintf("%d unidades notificadoras distintas nos casos.", length(codigos_casos)))

## 2. API do CNES ----

linha_cnes <- function(e) {
  tibble::tibble(
    codigo_cnes = normaliza_cnes(e$codigo_cnes %||% NA),
    nome_fantasia = e$nome_fantasia %||% NA_character_,
    razao_social = e$nome_razao_social %||% NA_character_,
    latitude = as.numeric(e$latitude_estabelecimento_decimo_grau %||% NA),
    longitude = as.numeric(e$longitude_estabelecimento_decimo_grau %||% NA),
    codigo_uf = as.character(e$codigo_uf %||% NA),
    codigo_municipio = as.character(e$codigo_municipio %||% NA),
    codigo_tipo = as.integer(e$codigo_tipo_unidade %||% NA),
    # Vem o codigo (ex.: "1244"), apesar do nome do campo na API
    natureza_juridica = as.character(e$descricao_natureza_juridica_estabelecimento %||% NA),
    atende_sus = e$estabelecimento_faz_atendimento_ambulatorial_sus %||% NA_character_,
    habilitado = is.null(e$codigo_motivo_desabilitacao_estabelecimento)
  )
}

requisicao <- function(url) {
  httr2::request(url) |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_timeout(60)
}

# Todas as unidades de um tipo em Pernambuco. A API pagina em blocos fixos
# de 20 (o `limit` nao aumenta a pagina): percorre ate' vir uma pagina vazia.
busca_tipo <- function(tipo, max_paginas = 1000) {
  paginas <- list()
  for (pagina in seq_len(max_paginas)) {
    est <- requisicao(API_CNES) |>
      httr2::req_url_query(codigo_uf = CODIGO_UF, codigo_tipo_unidade = tipo,
                           limit = 20, offset = 20 * (pagina - 1)) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    est <- est$estabelecimentos
    if (length(est) == 0) return(dplyr::bind_rows(paginas))
    paginas[[pagina]] <- dplyr::bind_rows(lapply(est, linha_cnes))
    Sys.sleep(0.05) # nao martelar a API publica
  }
  warning("Tipo ", tipo, ": atingiu o limite de ", max_paginas, " paginas -- a lista pode estar incompleta.")
  dplyr::bind_rows(paginas)
}

# Uma unidade pelo codigo (as notificadoras que nao vieram nas listas por
# tipo). Codigo que a API nao conhece fica de fora.
busca_codigo <- function(codigo) {
  tryCatch({
    e <- requisicao(paste0(API_CNES, "/", codigo)) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    if (is.null(e$codigo_cnes)) NULL else linha_cnes(e)
  }, error = function(err) NULL)
}

message("Consultando a API do CNES (rede SUS por tipo de unidade)...")
estab <- dplyr::bind_rows(lapply(TIPOS_REDE_SUS, function(tipo) {
  d <- busca_tipo(tipo)
  message(sprintf("  tipo %2d (%s): %d unidades", tipo, TIPOS_UNIDADE[[as.character(tipo)]], nrow(d)))
  d
}))

faltantes <- setdiff(codigos_casos, estab$codigo_cnes)
message(sprintf("Consultando %d notificadoras que nao vieram nas listas por tipo...", length(faltantes)))
estab <- dplyr::bind_rows(estab, dplyr::bind_rows(lapply(faltantes, busca_codigo))) |>
  dplyr::distinct(codigo_cnes, .keep_all = TRUE)

## 3. Classificacao ----
# Publica = natureza juridica de administracao publica (1xxx: orgaos,
# autarquias e fundacoes publicas federais, estaduais e municipais) ou
# empresa publica / sociedade de economia mista (2011/2038 -- ex.: Hospital
# das Clinicas, gerido pela EBSERH). NAO usar a esfera administrativa: ela
# reflete a gestao, nao a propriedade. Filantropicos (3xxx -- IMIP, Santa
# Casa) atendem SUS mas nao sao publicos: ficam com "✕", com "atende SUS" no
# hover.

estab <- estab |>
  dplyr::mutate(
    publica = dplyr::coalesce(substr(natureza_juridica, 1, 1) == "1" | natureza_juridica %in% c("2011", "2038"), FALSE),
    natureza = dplyr::case_when(
      publica ~ "Pública",
      substr(natureza_juridica, 1, 1) == "3" ~ "Sem fins lucrativos (filantrópica)",
      substr(natureza_juridica, 1, 1) == "4" ~ "Pessoa física",
      TRUE ~ "Privada"
    ),
    natureza = dplyr::if_else(!publica & atende_sus %in% "SIM", paste0(natureza, ", atende SUS"), natureza),
    tipo_unidade = dplyr::coalesce(unname(TIPOS_UNIDADE[as.character(codigo_tipo)]), paste("Tipo CNES", codigo_tipo))
  )

# Entram no mapa: a rede publica assistencial habilitada + qualquer unidade
# habilitada que notificou caso, em Pernambuco
unidades <- estab |>
  dplyr::filter(
    habilitado,
    codigo_uf == as.character(CODIGO_UF),
    codigo_cnes %in% codigos_casos | (publica & codigo_tipo %in% TIPOS_REDE_SUS)
  )

## 4. Coordenada oficial da SESAU em Recife ----
# Camada "Rede de Saude de Recife" do ESIG (servidor de mapas da
# Prefeitura). Pontos "satelite" que dividem o CNES da unidade principal
# (residencias terapeuticas dos CAPS, farmacias, equipes...) sao ignorados
# quando a unidade principal tambem esta la'. O certificado TLS do ESIG nao
# valida a cadeia completa; a camada e' publica e so' de leitura. Se o ESIG
# estiver fora do ar, segue com a coordenada do CNES.

SATELITES_ESIG <- c(
  "RT", "ESPACO MAE CORUJA", "FARMACIA FAMILIA", "FARMACIA DISTRITAL", "CONSULTORIO DE RUA",
  "CONSULTORIO NA RUA", "ACOLHIMENTO CAPS AD", "NDI", "PAC", "AMBULANCIA", "MOTOLANCIA", "eMulti",
  "EMAD", "EMAP", "BASE SAMU", "HELICOPTERO SAMU", "CENTRO DE VACINACAO SHOPPING",
  "CENTRO DE CONVIVENCIA", "ATENDIMENTO DOMICILIAR"
)

message("Buscando as coordenadas oficiais da rede municipal de Recife no ESIG...")
coord_sesau <- tryCatch({
  url_esig <- paste0(
    "https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/",
    utils::URLencode("Rede_de_Saúde_de_Recife"),
    "/FeatureServer/0/query?where=servico_saude%3D%27S%27&outFields=cnes,tipo_servico&outSR=4326&f=geojson"
  )
  arquivo_esig <- tempfile(fileext = ".geojson")
  curl::curl_download(url_esig, arquivo_esig,
                      handle = curl::new_handle(ssl_verifypeer = FALSE, connecttimeout = 30, timeout = 180))

  rede <- sf::st_read(arquivo_esig, quiet = TRUE)
  rede$cnes <- normaliza_cnes(rede$cnes)
  rede <- rede |>
    dplyr::filter(!is.na(cnes), !cnes %in% c("0000000", "9999999")) |>
    dplyr::group_by(cnes) |>
    dplyr::filter(!tipo_servico %in% SATELITES_ESIG | all(tipo_servico %in% SATELITES_ESIG)) |>
    dplyr::slice(1) |>
    dplyr::ungroup()

  xy <- sf::st_coordinates(rede)
  tibble::tibble(codigo_cnes = rede$cnes, lon_sesau = xy[, "X"], lat_sesau = xy[, "Y"])
}, error = function(e) {
  warning("ESIG indisponivel -- usando so' a coordenada do CNES em Recife: ", conditionMessage(e))
  tibble::tibble(codigo_cnes = character(), lon_sesau = double(), lat_sesau = double())
})

unidades <- unidades |>
  dplyr::left_join(coord_sesau, by = "codigo_cnes") |>
  dplyr::mutate(
    sesau = codigo_municipio == CODIGO_RECIFE & !is.na(lat_sesau),
    latitude = dplyr::if_else(sesau, lat_sesau, latitude),
    longitude = dplyr::if_else(sesau, lon_sesau, longitude),
    fonte_coordenada = dplyr::if_else(sesau, "SESAU Recife (ESIG)", "CNES")
  ) |>
  dplyr::select(-lat_sesau, -lon_sesau, -sesau)

message(sprintf("  %d unidades de Recife com coordenada oficial da SESAU.", sum(unidades$fonte_coordenada != "CNES")))

## 5. Coordenada dentro do proprio municipio ----
# Parte das coordenadas do CNES falta ou cai fora do municipio da unidade
# (no mar, em outro municipio, a centenas de km):
#   - dentro do municipio: mantem;
#   - ate' TOLERANCIA_M fora: puxa pro ponto mais proximo da borda;
#   - sem coordenada ou mais longe: poe na sede do municipio (geobr), marcada
#     como localizacao aproximada pro hover do mapa avisar. A lista sai em
#     local/unidades_localizacao_aproximada.csv, pra correcao no CNES.

mun <- malha_municipios() |> sf::st_transform(5880)
idx_mun <- match(unidades$codigo_municipio, mun$cod_muni6)
unidades <- unidades[!is.na(idx_mun), ]
idx_mun <- idx_mun[!is.na(idx_mun)]

tem_coord <- !is.na(unidades$latitude) & !is.na(unidades$longitude) &
  unidades$latitude != 0 & unidades$longitude != 0
pontos <- sf::st_as_sf(unidades, coords = c("longitude", "latitude"), crs = 4326, na.fail = FALSE) |>
  sf::st_geometry() |>
  sf::st_transform(5880)

dist_m <- rep(Inf, nrow(unidades))
dist_m[tem_coord] <- as.numeric(sf::st_distance(pontos[tem_coord], sf::st_geometry(mun)[idx_mun[tem_coord]], by_element = TRUE))

ajustar <- dist_m > 0 & dist_m <= TOLERANCIA_M
aproximar <- dist_m > TOLERANCIA_M

if (any(ajustar)) {
  sel <- which(ajustar)
  linhas <- sf::st_nearest_points(pontos[sel], sf::st_geometry(mun)[idx_mun[sel]], pairwise = TRUE)
  # 2o vertice de cada linha: o ponto mais proximo na borda do municipio
  novos <- sf::st_cast(linhas, "POINT")[seq(2, 2 * length(sel), by = 2)] |> sf::st_transform(4326)
  xy <- sf::st_coordinates(novos)
  unidades$longitude[sel] <- xy[, "X"]
  unidades$latitude[sel] <- xy[, "Y"]
}

unidades$aproximada <- aproximar
if (any(aproximar)) {
  # Sede do municipio; sem ela (geobr fora do ar), um ponto interno do
  # poligono do municipio
  sede <- sf::st_transform(sf::st_point_on_surface(sf::st_geometry(mun)), 4326)
  sedes_geobr <- tryCatch(
    geobr::read_municipal_seat(year = 2010, showProgress = FALSE) |> dplyr::filter(code_state == CODIGO_UF),
    error = function(e) {
      warning("Sedes municipais indisponiveis no geobr -- usando um ponto interno do municipio: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(sedes_geobr)) {
    i <- match(mun$code_muni, as.character(sedes_geobr$code_muni))
    sede[!is.na(i)] <- sf::st_transform(sf::st_geometry(sedes_geobr), 4326)[i[!is.na(i)]]
  }

  sel <- which(aproximar)
  xy <- sf::st_coordinates(sede[idx_mun[sel]])
  unidades$longitude[sel] <- xy[, "X"]
  unidades$latitude[sel] <- xy[, "Y"]
  unidades$fonte_coordenada[sel] <- "Sede do município (aproximada)"

  dir.create("local", showWarnings = FALSE)
  utils::write.csv2(
    data.frame(
      codigo_cnes = unidades$codigo_cnes[sel],
      unidade = dplyr::coalesce(unidades$nome_fantasia[sel], unidades$razao_social[sel]),
      tipo = unidades$tipo_unidade[sel],
      municipio = mun$nome[idx_mun[sel]],
      motivo = ifelse(is.infinite(dist_m[sel]), "sem coordenada no CNES",
                      sprintf("coordenada do CNES a %.1f km do municipio", dist_m[sel] / 1000))
    ),
    "local/unidades_localizacao_aproximada.csv", row.names = FALSE, fileEncoding = "UTF-8"
  )
}

message(sprintf(
  "Coordenadas: %d dentro do municipio, %d puxadas ate' a borda (ate' %d m fora), %d na sede do municipio (%d sem coordenada, %d fora do municipio).",
  sum(dist_m == 0), sum(ajustar), TOLERANCIA_M, sum(aproximar),
  sum(is.infinite(dist_m)), sum(aproximar & is.finite(dist_m))
))

## 6. Gravacao ----

unidades <- unidades |>
  dplyr::transmute(
    codigo_cnes,
    nome = dplyr::coalesce(dplyr::na_if(trimws(nome_fantasia), ""), razao_social),
    tipo_unidade,
    natureza,
    publica,
    cod_municipio = codigo_municipio,
    municipio = mun$nome[idx_mun],
    latitude,
    longitude,
    fonte_coordenada,
    aproximada
  )

dir.create("local", showWarnings = FALSE)
saveRDS(unidades, "local/unidades_cnes.rds")

message(sprintf(
  "Salvo em local/unidades_cnes.rds: %d unidades -- %d da rede SUS (S) e %d outras notificadoras (✕).%s",
  nrow(unidades), sum(unidades$publica), sum(!unidades$publica),
  if (any(aproximar)) " Unidades com localizacao aproximada listadas em local/unidades_localizacao_aproximada.csv." else ""
))
