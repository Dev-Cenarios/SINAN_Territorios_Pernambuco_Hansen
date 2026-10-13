# dev/gerar_dados_ficticios.R
# ==================================================================================
# Gera a base FICTICIA de casos de hanseniase de Pernambuco (formato SINAN, com
# as colunas da pipeline de georreferenciamento) usada pela versao de
# demonstracao do painel.
#
# NENHUM registro aqui corresponde a uma pessoa real. Cada caso e' sorteado:
# datas, sexo, idade, raca/cor, escolaridade, classificacao operacional, forma
# clinica, baciloscopia, grau de incapacidade, contatos, modo de entrada e de
# deteccao, desfecho, municipio, unidade notificadora, nome ("PACIENTE
# FICTICIO 00001"), endereco ("RUA FICTICIA ...") e coordenada.
#
# O que vem da realidade sao so' ordens de grandeza agregadas, para o painel
# se parecer com o de producao:
#   - total de casos por ano e proporcoes gerais (sexo, idade, classificacao,
#     desfechos...), arredondados, no bloco PARAMETROS abaixo;
#   - inst/extdata/dados_ficticios/parametros_municipios.csv: taxa media anual
#     de deteccao de casos novos por 100 mil hab. em cada municipio, com
#     ruido aleatorio de ~15% e arredondada -- define so' o peso relativo de
#     cada municipio no sorteio.
#
# Unidade notificadora e coordenada NAO usam nenhum dado de caso real: saem do
# cadastro publico de unidades (unidades_cnes.rds, API do CNES/DATASUS). A
# unidade e' sorteada entre as do municipio de notificacao -- atencao
# primaria (UBS/USF, posto) ou referencia (hospital, policlinica, centro de
# especialidade...), com pesos que sao hipoteses da simulacao. A coordenada
# fica perto de uma unidade de atencao primaria do municipio de residencia
# (onde mora gente), com deslocamento aleatorio, ou num ponto qualquer do
# municipio.
#
# Uso (na raiz do projeto):
#   Rscript dev/gerar_dados_ficticios.R
# Regrava inst/extdata/dados_ficticios/sinan_hanseniase_pe_ficticio.csv. Na
# proxima abertura, o painel percebe que o arquivo mudou e remonta a base.
# ==================================================================================

suppressMessages({
  library(dplyr)
  library(sf)
})

sf::sf_use_s2(FALSE)
set.seed(20261010)

dir_saida <- "inst/extdata/dados_ficticios"
dir_shapes <- "inst/app/www/shapes"

# ==================================================================================
# PARAMETROS (ordens de grandeza, arredondadas)
# ==================================================================================

anos <- 2016:2025
data_corte <- as.Date("2025-11-20") # ultima data da base (2025 incompleto)

# Casos notificados por ano de diagnostico (todos os modos de entrada)
casos_por_ano <- c(2400, 3160, 3040, 3350, 2110, 2200, 2540, 2540, 2430, 1890)

# Proporcao de casos novos por ano; os demais modos de entrada (codigo
# MODOENTR do SINAN) seguem estas proporcoes
prop_caso_novo <- c(.79, .77, .76, .77, .77, .72, .75, .70, .72, .69)
outros_modos_entrada <- c("7" = .49, "6" = .224, "2" = .134, "3" = .102, "4" = .031, "5" = .004, "9" = .015)

# Desfecho de quem encerra o tratamento. Abandono por ano; cura e' o resto.
prop_abandono <- c(.08, .10, .09, .14, .15, .12, .13, .13, .13, .13)
prop_transferencia <- .095
prop_obito <- .02
prop_erro_diagnostico <- .021
# Tipo de transferencia (TPALTA_N): mesmo municipio, outro municipio, outro
# estado, outro pais
tipo_transferencia <- c("2" = .41, "3" = .47, "4" = .11, "5" = .01)

# Casos sem saida registrada no SINAN alem dos que ainda estao em tratamento
# na data de corte (mais comuns nos anos recentes)
prop_sem_encerramento <- c(.005, .004, .010, .008, .014, .035, .08, .11, .15, .15)

prop_sem_georref <- .005        # endereco nao localizado (fica no centroide do municipio)
prop_rua_detento <- .025        # INDICADOR = 0 na pipeline de georreferenciamento
prop_notifica_outro_mun <- .05  # notificado fora do municipio de residencia
prop_reside_fora_pe <- .0015

# Idade por sexo (faixas e pesos) -- dentro da faixa, idade uniforme
faixas <- list(c(0, 4), c(5, 9), c(10, 14), c(15, 19), c(20, 29), c(30, 39), c(40, 49),
               c(50, 59), c(60, 69), c(70, 79), c(80, 95))
peso_faixa <- list(
  F = c(45, 215, 410, 540, 1140, 1760, 2600, 2530, 1770, 900, 300),
  M = c(40, 250, 430, 560, 1450, 2090, 2570, 2580, 2100, 1060, 330)
)
prop_feminino <- .476

# Codigos do SINAN e proporcoes
raca <- c("1" = .184, "2" = .136, "3" = .007, "4" = .588, "5" = .009, "9" = .076)
escolaridade <- c("0" = .070, "1" = .142, "2" = .059, "3" = .111, "4" = .041, "5" = .052,
                  "6" = .121, "7" = .012, "8" = .038, "9" = .354)
gestante_15_49 <- c("5" = .741, "9" = .095, "6" = .143, "1" = .005, "2" = .008, "3" = .005, "4" = .003)
modo_deteccao <- c("1" = .366, "2" = .260, "3" = .032, "4" = .059, "5" = .019, "9" = .264)
# Multibacilares: menos entre os casos novos que entre recidivas e reingressos
prop_multibacilar <- c(caso_novo = .72, outros = .89)

# Por classificacao operacional: Multibacilar (MB) e Paucibacilar (PB)
forma_clinica <- list(MB = c("3" = .539, "4" = .179, "5" = .137, "1" = .054, "2" = .038, "9" = .053),
                      PB = c("1" = .426, "2" = .359, "5" = .114, "3" = .028, "4" = .007, "9" = .066))
baciloscopia <- list(MB = c("3" = .465, "1" = .223, "2" = .194, "9" = .118),
                     PB = c("3" = .593, "2" = .204, "1" = .073, "9" = .130))
esquema <- list(MB = c("2" = .935, "3" = .058, "1" = .005, "9" = .002),
                PB = c("1" = .954, "3" = .016, "2" = .024, "9" = .006))
# Grau de incapacidade no diagnostico (AVALIA_N; "NA" = ignorado)
gif_diagnostico <- list(MB = c("0" = .422, "1" = .255, "2" = .107, "3" = .139, "NA" = .077),
                        PB = c("0" = .735, "1" = .096, "2" = .012, "3" = .098, "NA" = .059))
gif_alta <- c("0" = .331, "1" = .077, "2" = .032, "3" = .090, "NA" = .470)

# Unidade notificadora (hipoteses da simulacao, sem calibracao): proporcao
# notificada pela atencao primaria do municipio; os demais por uma unidade de
# referencia sorteada pelo tipo, entre as que existem no municipio
prop_notificacao_aps <- .65
tipos_aps <- c("Unidade básica de saúde (UBS/USF)", "Posto de saúde")
peso_tipo_referencia <- c(
  "Hospital geral" = .30, "Policlínica" = .25, "Clínica / centro de especialidade" = .25,
  "Unidade mista" = .10, "Hospital especializado" = .05, "Pronto atendimento (UPA)" = .05
)

# ==================================================================================
# MALHAS, MUNICIPIOS E UNIDADES
# ==================================================================================

municipios <- sf::st_read(file.path(dir_shapes, "municipios_pe.gpkg"), quiet = TRUE) |>
  dplyr::mutate(cod_muni6 = as.character(cod_muni6))
par_mun <- utils::read.csv(file.path(dir_saida, "parametros_municipios.csv"), fileEncoding = "UTF-8",
                           colClasses = c(cod_muni6 = "character"))
municipios <- municipios |>
  dplyr::left_join(par_mun |> dplyr::select(cod_muni6, taxa = taxa_deteccao_media_anual_100mil), by = "cod_muni6") |>
  dplyr::mutate(peso = taxa * pop)
mun_df <- sf::st_drop_geometry(municipios)

# Polo de cada GERES (municipio mais populoso) -- onde vai parte das
# notificacoes de quem mora em outro municipio
polo_geres <- mun_df |> dplyr::group_by(geres) |> dplyr::slice_max(pop, n = 1, with_ties = FALSE) |>
  dplyr::ungroup() |> dplyr::select(geres, polo = cod_muni6)
recife <- mun_df$cod_muni6[mun_df$nome == "Recife"]

unidades <- readRDS(file.path(dir_saida, "unidades_cnes.rds")) |>
  dplyr::filter(!is.na(latitude), !is.na(longitude)) |>
  dplyr::mutate(cod_muni6 = substr(as.character(cod_municipio), 1, 6))

sorteia <- function(n, probs) sample(names(probs), n, replace = TRUE, prob = probs)
codigo <- function(n, probs) suppressWarnings(as.integer(sorteia(n, probs)))
sem_acento <- function(x) toupper(stringi::stri_trans_general(x, "Latin-ASCII"))
data_br <- function(d) ifelse(is.na(d), NA_character_, format(d, "%d/%m/%Y"))
atraso_lognormal <- function(k, mediana, dispersao) round(stats::rlnorm(k, log(mediana), dispersao))

# ==================================================================================
# 1. CASOS
# ==================================================================================

casos <- purrr::map_dfr(seq_along(anos), function(i) {
  k <- stats::rpois(1, casos_por_ano[i])
  inicio <- as.Date(sprintf("%d-01-01", anos[i]))
  fim <- min(as.Date(sprintf("%d-12-31", anos[i])), data_corte)
  dplyr::tibble(
    ano = anos[i],
    i_ano = i,
    dt_diag = inicio + sample(0:as.integer(fim - inicio), k, replace = TRUE)
  )
})
n <- nrow(casos)

# ---- Pessoa ----
casos$sexo <- ifelse(stats::runif(n) < prop_feminino, "F", "M")
faixa <- integer(n)
for (s in c("M", "F")) {
  idx <- which(casos$sexo == s)
  faixa[idx] <- sample(seq_along(faixas), length(idx), replace = TRUE, prob = peso_faixa[[s]])
}
lim_inf <- vapply(faixas, `[`, numeric(1), 1)[faixa]
lim_sup <- vapply(faixas, `[`, numeric(1), 2)[faixa]
casos$idade <- as.integer(lim_inf + floor(stats::runif(n) * (lim_sup - lim_inf + 1)))

casos$CS_RACA <- codigo(n, raca)
casos$CS_ESCOL_N <- ifelse(casos$idade < 7, 10L, codigo(n, escolaridade))
mulher_fertil <- casos$sexo == "F" & casos$idade >= 15 & casos$idade < 50
casos$CS_GESTANT <- ifelse(mulher_fertil, codigo(n, gestante_15_49), 6L)

# ---- Clinica ----
casos$MODOENTR <- ifelse(stats::runif(n) < prop_caso_novo[casos$i_ano], 1L, codigo(n, outros_modos_entrada))
casos$mb <- stats::runif(n) < ifelse(casos$MODOENTR == 1L, prop_multibacilar[["caso_novo"]], prop_multibacilar[["outros"]])
por_classe <- function(lista) {
  ifelse(casos$mb, codigo(n, lista$MB), codigo(n, lista$PB))
}
casos$CLASSOPERA <- ifelse(casos$mb, 2L, 1L)
casos$FORMACLINI <- por_classe(forma_clinica)
casos$BACILOSCO <- por_classe(baciloscopia)
casos$ESQ_INI_N <- por_classe(esquema)
casos$AVALIA_N <- por_classe(gif_diagnostico)
casos$NU_LESOES <- ifelse(casos$mb,
                          stats::rnbinom(n, mu = 7.5, size = 0.9),
                          pmin(5L, 1L + stats::rnbinom(n, mu = 0.5, size = 1)))
casos$NU_LESOES[stats::runif(n) < ifelse(casos$mb, .12, .05)] <- NA
casos$NERVOSAFET <- ifelse(casos$mb, stats::rnbinom(n, mu = 1.9, size = 0.7), stats::rnbinom(n, mu = 0.2, size = 0.5))
casos$MODODETECT <- codigo(n, modo_deteccao)
casos$CONTREG <- stats::rnbinom(n, mu = 3.1, size = 2.5)
casos$CONTEXAM <- stats::rbinom(n, casos$CONTREG, stats::rbeta(n, 8, 1.75))
sem_contato <- stats::runif(n) < .033
casos$CONTREG[sem_contato] <- NA
casos$CONTEXAM[sem_contato] <- NA

# ---- Desfecho ----
# Desfecho de quem encerra, sorteado pelas proporcoes do ano; a data de saida
# vem do tempo tipico de cada desfecho (cura: ~6 meses no PB e ~12 no MB).
# Saida depois da data de corte = ainda em tratamento.
p_ab <- prop_abandono[casos$i_ano]
p_cura <- 1 - p_ab - prop_transferencia - prop_obito - prop_erro_diagnostico
u <- stats::runif(n)
casos$desfecho <- dplyr::case_when(
  u < p_cura ~ "Cura",
  u < p_cura + p_ab ~ "Abandono",
  u < p_cura + p_ab + prop_transferencia ~ "Transferência",
  u < p_cura + p_ab + prop_transferencia + prop_obito ~ "Óbito",
  TRUE ~ "Erro diagnóstico"
)
dias_ate_saida <- dplyr::case_when(
  casos$desfecho == "Cura" & casos$mb ~ 330 + round(stats::rgamma(n, 1.3, 1 / 90)),
  casos$desfecho == "Cura" ~ 165 + round(stats::rgamma(n, 1.2, 1 / 55)),
  casos$desfecho == "Abandono" ~ atraso_lognormal(n, 300, .8),
  casos$desfecho == "Transferência" ~ ifelse(stats::runif(n) < .25, sample(0:7, n, replace = TRUE), atraso_lognormal(n, 150, 1)),
  casos$desfecho == "Óbito" ~ atraso_lognormal(n, 210, .9),
  TRUE ~ atraso_lognormal(n, 105, .9)
)
casos$dt_alta <- casos$dt_diag + dias_ate_saida
sem_saida <- casos$dt_alta > data_corte | stats::runif(n) < prop_sem_encerramento[casos$i_ano]
casos$TPALTA_N <- dplyr::case_when(
  sem_saida ~ NA_integer_,
  casos$desfecho == "Cura" ~ 1L,
  casos$desfecho == "Transferência" ~ codigo(n, tipo_transferencia),
  casos$desfecho == "Óbito" ~ 6L,
  casos$desfecho == "Abandono" ~ 7L,
  TRUE ~ 8L
)
casos$dt_alta[sem_saida] <- NA
casos$AVAL_ATU_N <- ifelse(sem_saida, NA_integer_, codigo(n, gif_alta))

# ---- Datas ----
casos$dt_notif <- pmin(data_corte, casos$dt_diag + dplyr::case_when(
  stats::runif(n) < .55 ~ 0,
  stats::runif(n) < .65 ~ as.numeric(sample(1:7, n, replace = TRUE)),
  TRUE ~ pmin(120, atraso_lognormal(n, 15, .8))
))
casos$dt_inicio <- casos$dt_diag + dplyr::case_when(
  stats::runif(n) < .5 ~ 0,
  stats::runif(n) < .5 ~ as.numeric(sample(1:3, n, replace = TRUE)),
  TRUE ~ pmin(90, atraso_lognormal(n, 8, .8))
)
casos$dt_nasc <- casos$dt_diag - round(casos$idade * 365.25) - sample(0:364, n, replace = TRUE)

# ---- Municipio de residencia e de notificacao ----
casos$mun_resid <- sample(mun_df$cod_muni6, n, replace = TRUE, prob = mun_df$peso)
casos$geres <- mun_df$geres[match(casos$mun_resid, mun_df$cod_muni6)]
outro <- stats::runif(n) < prop_notifica_outro_mun
polo <- polo_geres$polo[match(casos$geres, polo_geres$geres)]
polo[casos$geres == 1 | polo == casos$mun_resid] <- recife
casos$mun_notif <- ifelse(outro, polo, casos$mun_resid)

fora_pe <- stats::runif(n) < prop_reside_fora_pe
casos$mun_resid[fora_pe] <- sample(c("250750", "270430", "291840"), sum(fora_pe), replace = TRUE)
casos$mun_notif[fora_pe] <- sample(c(recife, mun_df$cod_muni6[mun_df$nome == "Petrolina"]), sum(fora_pe), replace = TRUE)

# ---- Unidade notificadora (cadastro publico, ver cabecalho) ----
casos$ID_UNIDADE <- NA_integer_
aps <- stats::runif(n) < prop_notificacao_aps
for (m in unique(casos$mun_notif)) {
  idx <- which(casos$mun_notif == m)
  u_mun <- unidades[unidades$cod_muni6 == m, ]
  if (nrow(u_mun) == 0) next
  u_aps <- u_mun$codigo_cnes[u_mun$tipo_unidade %in% tipos_aps]
  u_ref <- u_mun[u_mun$tipo_unidade %in% names(peso_tipo_referencia), ]
  for (k in idx) {
    if ((aps[k] && length(u_aps) > 0) || nrow(u_ref) == 0) {
      lista <- if (length(u_aps) > 0) u_aps else u_mun$codigo_cnes
      casos$ID_UNIDADE[k] <- as.integer(lista[sample.int(length(lista), 1)])
    } else {
      w <- peso_tipo_referencia[u_ref$tipo_unidade]
      casos$ID_UNIDADE[k] <- as.integer(u_ref$codigo_cnes[sample.int(nrow(u_ref), 1, prob = w)])
    }
  }
}

# ---- Coordenada ----
# 85%: perto de uma unidade de atencao primaria do municipio de residencia
# (deslocamento normal de ~600 m), desde que caia dentro do municipio; o
# resto, e quem nao tem unidade no municipio, num ponto qualquer do municipio.
casos$sem_georref <- stats::runif(n) < prop_sem_georref
casos$LONGITUDE <- NA_real_
casos$LATITUDE <- NA_real_
em_pe <- !fora_pe
mun_idx <- match(casos$mun_resid, mun_df$cod_muni6)
perto_unidade <- em_pe & !casos$sem_georref & stats::runif(n) < .85
for (m in unique(casos$mun_resid[perto_unidade])) {
  idx <- which(perto_unidade & casos$mun_resid == m)
  u_m <- unidades[unidades$cod_muni6 == m & unidades$tipo_unidade %in% tipos_aps, ]
  if (nrow(u_m) == 0) next
  esc <- sample.int(nrow(u_m), length(idx), replace = TRUE)
  casos$LONGITUDE[idx] <- u_m$longitude[esc] + stats::rnorm(length(idx), 0, .0055)
  casos$LATITUDE[idx] <- u_m$latitude[esc] + stats::rnorm(length(idx), 0, .0055)
}
# Pontos que sairam do municipio voltam para o sorteio uniforme
com_ponto <- which(!is.na(casos$LONGITUDE))
pts <- sf::st_as_sf(data.frame(x = casos$LONGITUDE[com_ponto], y = casos$LATITUDE[com_ponto]),
                    coords = c("x", "y"), crs = 4674)
dentro <- vapply(sf::st_intersects(pts, municipios), function(i) if (length(i)) i[1] else NA_integer_, integer(1))
fora_do_mun <- com_ponto[is.na(dentro) | dentro != mun_idx[com_ponto]]
casos$LONGITUDE[fora_do_mun] <- NA
casos$LATITUDE[fora_do_mun] <- NA

uniforme <- which(em_pe & !casos$sem_georref & is.na(casos$LONGITUDE))
for (m in unique(casos$mun_resid[uniforme])) {
  idx <- uniforme[casos$mun_resid[uniforme] == m]
  p <- sf::st_coordinates(sf::st_sample(sf::st_geometry(municipios)[mun_idx[idx[1]]], length(idx), exact = TRUE))
  casos$LONGITUDE[idx] <- p[, "X"]
  casos$LATITUDE[idx] <- p[, "Y"]
}
# Sem georreferenciamento: centroide do municipio de residencia
centroides <- sf::st_coordinates(suppressWarnings(sf::st_point_on_surface(sf::st_geometry(municipios))))
sg <- which(em_pe & casos$sem_georref)
casos$LONGITUDE[sg] <- centroides[mun_idx[sg], "X"]
casos$LATITUDE[sg] <- centroides[mun_idx[sg], "Y"]
casos$LONGITUDE <- round(casos$LONGITUDE, 6)
casos$LATITUDE <- round(casos$LATITUDE, 6)

# ---- Endereco ----
nomes_rua <- c("DAS ACÁCIAS", "DOS IPÊS", "DAS ORQUÍDEAS", "DAS BROMÉLIAS", "DOS CAJUEIROS",
               "DAS MANGUEIRAS", "DOS JASMINS", "DOS GIRASSÓIS", "DAS VIOLETAS", "DAS HORTÊNSIAS",
               "DAS AZALEIAS", "DOS CRAVOS", "DOS LÍRIOS", "DAS MAGNÓLIAS", "DAS PITANGUEIRAS",
               "DAS JAQUEIRAS", "DOS UMBUZEIROS", "DOS MANDACARUS", "DOS SABIÁS", "DOS BEIJA-FLORES",
               "DAS GARDÊNIAS", "DOS COQUEIROS", "DAS CAMÉLIAS", "DOS JUAZEIROS")
tipo_via <- c("RUA" = .7, "AVENIDA" = .1, "TRAVESSA" = .15, "SÍTIO" = .05)
via <- sorteia(n, tipo_via)
endereco <- paste0(via, ifelse(via == "SÍTIO", " FICTÍCIO ", " FICTÍCIA "), sample(nomes_rua, n, replace = TRUE),
                   ", ", sample(1:1500, n, replace = TRUE))
rua_detento <- stats::runif(n) < prop_rua_detento
endereco[rua_detento] <- sample(c("UNIDADE PRISIONAL FICTÍCIA", "SEM ENDEREÇO FIXO (FICTÍCIO)"),
                                sum(rua_detento), replace = TRUE, prob = c(.6, .4))
endereco[casos$sem_georref | fora_pe] <- "ENDEREÇO NÃO LOCALIZADO (FICTÍCIO)"

# ==================================================================================
# 2. TABELA NO FORMATO DA PIPELINE
# ==================================================================================

sinan <- dplyr::tibble(
  # 8 digitos (o SINAN numera com 7): nunca coincide com uma notificacao real
  NU_NOTIFIC = as.character(sample(99000000:99999999, n)),
  DT_NOTIFIC = data_br(casos$dt_notif),
  DT_DIAG = data_br(casos$dt_diag),
  ID_MUNICIP = casos$mun_notif,
  ID_UNIDADE = casos$ID_UNIDADE,
  NM_PACIENT = NA_character_, # numerado abaixo, na ordem de notificacao
  DT_NASC = data_br(casos$dt_nasc),
  NU_IDADE_N = ifelse(casos$idade == 0, 3000L + sample(1:11, n, replace = TRUE), 4000L + casos$idade),
  CS_SEXO = casos$sexo,
  CS_GESTANT = casos$CS_GESTANT,
  CS_RACA = casos$CS_RACA,
  CS_ESCOL_N = casos$CS_ESCOL_N,
  ID_MN_RESI = casos$mun_resid,
  NM_BAIRRO = "BAIRRO FICTÍCIO",
  NU_LESOES = casos$NU_LESOES,
  FORMACLINI = casos$FORMACLINI,
  AVALIA_N = casos$AVALIA_N,
  CLASSOPERA = casos$CLASSOPERA,
  MODOENTR = casos$MODOENTR,
  MODODETECT = casos$MODODETECT,
  BACILOSCO = casos$BACILOSCO,
  DTINICTRAT = data_br(casos$dt_inicio),
  ESQ_INI_N = casos$ESQ_INI_N,
  CONTREG = casos$CONTREG,
  NERVOSAFET = casos$NERVOSAFET,
  AVAL_ATU_N = casos$AVAL_ATU_N,
  CONTEXAM = casos$CONTEXAM,
  DTALTA_N = data_br(casos$dt_alta),
  TPALTA_N = casos$TPALTA_N,
  ADDRESS_CORE = endereco,
  ENDERECO_CNEFE = ifelse(rua_detento | casos$sem_georref | fora_pe, NA_character_, sem_acento(endereco)),
  LATITUDE = casos$LATITUDE,
  LONGITUDE = casos$LONGITUDE,
  GEORREFERENCIADO = ifelse(casos$sem_georref | fora_pe, 0L, 1L),
  INDICADOR = ifelse(rua_detento, 0L, 1L)
) |>
  dplyr::arrange(as.Date(DT_NOTIFIC, "%d/%m/%Y"), NU_NOTIFIC) |>
  dplyr::mutate(NM_PACIENT = sprintf("PACIENTE FICTÍCIO %05d", dplyr::row_number()))

utils::write.csv(sinan, file.path(dir_saida, "sinan_hanseniase_pe_ficticio.csv"),
                 row.names = FALSE, na = "", fileEncoding = "UTF-8")

# ==================================================================================
# Resumo
# ==================================================================================

cat("Casos ficticios:", nrow(sinan), "\n")
print(table(ano = casos$ano))
novos <- casos$MODOENTR == 1L
cat("Taxa de deteccao media anual (casos novos, 2016-2024) por 100 mil hab.:",
    round(1e5 * sum(novos & casos$ano <= 2024 & !fora_pe) / sum(mun_df$pop) / 9, 1), "\n")
cat("Multibacilares:", round(mean(casos$mb), 3), "| em tratamento:", round(mean(is.na(casos$TPALTA_N)), 3), "\n")
print(round(prop.table(table(casos$desfecho[!sem_saida])), 3))
