# dev/build_malhas_pe.R -- malhas de Pernambuco do painel de hanseniase
# ==================================================================================
# Gera, em inst/app/www/shapes:
#   - municipios_pe.gpkg: 185 municipios (184 + Fernando de Noronha), com
#     GERES, populacao total e populacao de menores de 15 anos (Censo 2022);
#   - geres_pe.gpkg: as 12 Gerencias Regionais de Saude (GERES), uniao dos
#     municipios de cada uma, com as populacoes somadas.
# As geometrias ja' saem prontas pro desenho do mapa (simplificadas, ver
# simplifica_cobertura()) -- o painel nao simplifica nada em tempo de
# execucao.
#
# Fontes:
#   - Malha municipal: IBGE 2022, resolucao original, via
#     geobr::read_municipality(simplified = FALSE).
#   - GERES: regioes de saude do Ministerio da Saude (geobr::
#     read_health_region(), 2013). Em Pernambuco as 12 regioes de saude
#     coincidem com as 12 GERES da SES-PE; o nome da regiao e' o do municipio
#     sede, traduzido aqui pro numero romano da GERES.
#   - Populacao: Censo 2022, SIDRA/IBGE -- tabela 4714 (populacao residente) e
#     tabela 9514 (populacao por idade: 0-4, 5-9 e 10-14 anos).
#
# So' precisa de internet. Rode na raiz do projeto:
#   Rscript dev/build_malhas_pe.R
# ==================================================================================

sf::sf_use_s2(FALSE)

# Tolerancia da simplificacao das divisas, em metros
tolerancia_m <- 100

# Sede da regiao de saude -> GERES (numeracao da SES-PE)
geres_sede <- c(
  "Recife" = "I", "Limoeiro" = "II", "Palmares" = "III", "Caruaru" = "IV",
  "Garanhuns" = "V", "Arcoverde" = "VI", "Salgueiro" = "VII", "Petrolina" = "VIII",
  "Ouricuri" = "IX", "Afogados da Ingazeira" = "X", "Serra Talhada" = "XI", "Goiana" = "XII"
)

sidra <- function(url) {
  linhas <- httr2::request(url) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
  # primeira linha e' o cabecalho
  linhas <- linhas[-1]
  data.frame(
    code_muni = vapply(linhas, function(l) l$D1C, character(1)),
    valor = as.numeric(vapply(linhas, function(l) l$V, character(1)))
  )
}

# Simplificacao que preserva a cobertura: cada divisa entre municipios (arco
# entre dois pontos de encontro de tres ou mais municipios, ou trecho do
# limite do estado) e' simplificada UMA vez, e os poligonos sao remontados a
# partir das divisas simplificadas. Os dois vizinhos ficam com exatamente a
# mesma linha -- sem frestas nem sobreposicao.
#
# A versao simplificada do proprio geobr (simplified = TRUE) simplifica cada
# municipio por conta propria: a mesma divisa sai diferente dos dois lados e
# sobram ~750 frestas e ~18 km2 de sobreposicao entre vizinhos. Unidas por
# GERES, as frestas viravam buracos, desenhados no mapa como riscos soltos e
# contornos de GERES fora das divisas municipais.
#
# `malha` precisa estar numa projecao em metros e ser uma cobertura limpa (a
# malha original do IBGE e').
simplifica_cobertura <- function(malha, tolerancia) {
  geom <- sf::st_geometry(malha)

  arcos <- sf::st_union(sf::st_boundary(geom)) |>
    sf::st_line_merge() |>
    sf::st_cast("LINESTRING") |>
    sf::st_simplify(dTolerance = tolerancia, preserveTopology = TRUE)

  faces <- sf::st_polygonize(sf::st_union(arcos)) |>
    sf::st_collection_extract("POLYGON") |>
    sf::st_cast("POLYGON")

  # Municipio de cada face: o que contem um ponto interno dela
  dono <- vapply(sf::st_intersects(sf::st_point_on_surface(faces), geom),
                 function(i) if (length(i) > 0) i[1] else NA_integer_, integer(1))
  if (anyNA(dono)) dono[is.na(dono)] <- sf::st_nearest_feature(faces[is.na(dono)], geom)

  novas <- lapply(seq_along(geom), function(i) {
    if (!any(dono == i)) stop("Municipio sem poligono depois da simplificacao: ", malha$name_muni[i])
    sf::st_union(faces[dono == i])[[1]]
  })

  sf::st_set_geometry(malha, sf::st_cast(sf::st_sfc(novas, crs = sf::st_crs(malha)), "MULTIPOLYGON"))
}

# Coordenadas arredondadas a 5 casas decimais (~1 m): o mapa manda os
# poligonos pro navegador como texto, e mais casas so' aumentam o envio. O
# vertice de uma divisa e' o mesmo nos dois vizinhos, entao continua igual
# depois de arredondado.
arredonda <- function(malha, precisao = 1e5) {
  wkb <- sf::st_as_binary(sf::st_geometry(malha), precision = precisao)
  sf::st_set_geometry(malha, sf::st_as_sfc(wkb, crs = sf::st_crs(malha)))
}

# Numero de buracos (aneis internos) de uma geometria
conta_buracos <- function(geom) {
  sum(vapply(geom, function(g) {
    poligonos <- if (inherits(g, "MULTIPOLYGON")) unclass(g) else list(unclass(g))
    sum(vapply(poligonos, function(p) length(p) - 1L, integer(1)))
  }, integer(1)))
}

# Para o script se a malha tiver poligono invalido, fresta ou sobreposicao
checa_cobertura <- function(malha, nome) {
  geom <- sf::st_geometry(sf::st_transform(malha, 5880))
  if (!all(sf::st_is_valid(geom))) stop(nome, ": poligono invalido")
  frestas <- conta_buracos(sf::st_union(geom))
  if (frestas > 0) stop(nome, ": ", frestas, " fresta(s) entre vizinhos")
  viz <- sf::st_relate(geom, geom, pattern = "2********")
  sobreposicao <- sum(vapply(seq_along(viz), function(i) {
    j <- viz[[i]][viz[[i]] > i]
    if (length(j) == 0) return(0)
    sum(as.numeric(sf::st_area(sf::st_intersection(geom[i], geom[j]))))
  }, numeric(1)))
  if (sobreposicao > 1) stop(nome, sprintf(": %.0f m2 de sobreposicao entre vizinhos", sobreposicao))
  invisible(TRUE)
}

## Municipios ----

# Malha original (resolucao completa) em SIRGAS 2000 / Brazil Polyconic, pra
# simplificar em metros
mun <- geobr::read_municipality(code_muni = 26, year = 2022, simplified = FALSE, showProgress = FALSE) |>
  sf::st_transform(5880)
mun$code_muni <- as.character(mun$code_muni)
checa_cobertura(mun, "Malha original")

## Populacao (Censo 2022) ----

pop <- sidra("https://apisidra.ibge.gov.br/values/t/4714/n6/in%20n3%2026/v/93/p/2022")
names(pop)[2] <- "pop"

# 0 a 4, 5 a 9 e 10 a 14 anos, ambos os sexos, qualquer forma de declaracao
pop15 <- sidra(paste0(
  "https://apisidra.ibge.gov.br/values/t/9514/n6/in%20n3%2026/v/93/p/2022",
  "/c2/6794/c287/93070,93084,93085/c286/113635"
))
pop15 <- stats::aggregate(valor ~ code_muni, data = pop15, FUN = sum)
names(pop15)[2] <- "pop_menor15"

mun <- mun |>
  dplyr::left_join(pop, by = "code_muni") |>
  dplyr::left_join(pop15, by = "code_muni")

stopifnot(!anyNA(mun$pop), !anyNA(mun$pop_menor15))

## GERES de cada municipio ----

regioes <- geobr::read_health_region(year = 2013, showProgress = FALSE) |>
  dplyr::filter(code_state == 26) |>
  sf::st_transform(5880)

nao_mapeadas <- setdiff(regioes$name_health_region, names(geres_sede))
if (length(nao_mapeadas) > 0) stop("Regiao de saude sem GERES: ", paste(nao_mapeadas, collapse = ", "))

pontos <- sf::st_point_on_surface(sf::st_geometry(mun))
idx <- sf::st_intersects(pontos, regioes)
mun$geres <- unname(geres_sede[regioes$name_health_region[
  vapply(idx, function(i) if (length(i) > 0) i[1] else NA_integer_, integer(1))
]])

# Fernando de Noronha (2605459) fica fora dos poligonos das regioes de saude
# no geobr; pela SES-PE pertence a I GERES.
mun$geres[mun$code_muni == "2605459" & is.na(mun$geres)] <- "I"

if (anyNA(mun$geres)) stop("Municipios sem GERES: ", paste(mun$name_muni[is.na(mun$geres)], collapse = ", "))

## Simplificacao pro desenho ----

vertices_antes <- nrow(sf::st_coordinates(mun))

mun <- mun |>
  simplifica_cobertura(tolerancia_m) |>
  sf::st_transform(4674) |>
  arredonda() |>
  dplyr::transmute(
    code_muni,
    # codigo de 6 digitos, o usado pelo SINAN (ID_MN_RESI, ID_MUNICIP)
    cod_muni6 = substr(code_muni, 1, 6),
    nome = name_muni,
    geres,
    pop,
    pop_menor15
  )

checa_cobertura(mun, "Malha simplificada")

## GERES ----

ordem_geres <- unname(geres_sede[order(match(geres_sede, as.character(utils::as.roman(1:12))))])

# Uniao dos municipios de cada GERES: como os vizinhos dividem exatamente a
# mesma divisa, o contorno da GERES coincide com as divisas municipais
geres <- mun |>
  dplyr::group_by(geres) |>
  dplyr::summarise(
    pop = sum(pop),
    pop_menor15 = sum(pop_menor15),
    n_municipios = dplyr::n(),
    .groups = "drop"
  ) |>
  dplyr::mutate(
    sede = names(geres_sede)[match(geres, geres_sede)],
    nome = sprintf("%s GERES (%s)", geres, sede)
  ) |>
  dplyr::arrange(match(geres, ordem_geres))

checa_cobertura(geres, "GERES")
buracos_geres <- conta_buracos(sf::st_geometry(geres))
if (buracos_geres > 0) stop("GERES com ", buracos_geres, " buraco(s)")

## Gravacao ----

dir.create("inst/app/www/shapes", showWarnings = FALSE, recursive = TRUE)
sf::st_write(mun, "inst/app/www/shapes/municipios_pe.gpkg", delete_dsn = TRUE, quiet = TRUE)
sf::st_write(geres, "inst/app/www/shapes/geres_pe.gpkg", delete_dsn = TRUE, quiet = TRUE)

message(sprintf(
  "%d municipios, %d GERES, populacao total %s (menores de 15: %s); vertices: %s -> %s",
  nrow(mun), nrow(geres),
  format(sum(mun$pop), big.mark = ".", decimal.mark = ","),
  format(sum(mun$pop_menor15), big.mark = ".", decimal.mark = ","),
  format(vertices_antes, big.mark = ".", decimal.mark = ","),
  format(nrow(sf::st_coordinates(mun)), big.mark = ".", decimal.mark = ",")
))
print(sf::st_drop_geometry(geres))
