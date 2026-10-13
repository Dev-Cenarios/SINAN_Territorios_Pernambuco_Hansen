# R/fct_db_update.R
# ==================================================================================
# FUNÇÃO: update_hans_data()
#
# PROPÓSITO:
#   Monta a base local (DuckDB + cache) de casos de hanseníase de Pernambuco a
#   partir da fonte de dados configurada (ver fonte_dados_configurada()
#   abaixo) e aplica as transformações do painel. Sem configuração, a fonte
#   são os DADOS FICTÍCIOS distribuídos com o pacote
#   (inst/extdata/dados_ficticios, gerados por dev/gerar_dados_ficticios.R).
#
# RETORNO:
#   Lista com: success (TRUE/FALSE), message (texto do resultado), records_updated (número)
#
# Sem linkage com o SIM: o desfecho vem só do tipo de saída do SINAN
# (TPALTA_N).
# ==================================================================================

# ==================================================================================
# FONTE DOS DADOS: FICTÍCIOS (PADRÃO) OU REAIS
# ==================================================================================
# Sem configuracao, o painel usa os dados ficticios do pacote e mostra os
# avisos de DADOS FICTICIOS. Para rodar com dados reais, defina a variavel de
# ambiente PAINEL_HANSEN_PE_DADOS_REAIS_DIR (no .Renviron do servidor, FORA do
# repositorio) com a pasta que contem sinan_hanseniase_pe.csv: casos, com as
# colunas do CSV ficticio (ver README, "Rodar com dados reais"). O nome da
# variavel e' especifico deste painel, para nao colidir com outros paineis
# rodando no mesmo servidor.
# Os avisos nao tem chave propria: dependem da origem da base que esta'
# carregada (registrada em local/fonte_dados.rds por prepara_base()). Assim
# nao ha' como mostrar dados ficticios sem aviso, nem esquecer o aviso ligado
# sobre dados reais.

arquivo_fonte_base <- "local/fonte_dados.rds"
variavel_dados_reais <- "PAINEL_HANSEN_PE_DADOS_REAIS_DIR"

# Arquivo de inst/extdata/dados_ficticios, no pacote instalado ou na pasta do app
caminho_dados_ficticios <- function(arquivo) {
  app_sys("extdata/dados_ficticios", arquivo)
}

# Fonte configurada: modo ("ficticio"/"real") e caminho do arquivo de casos
fonte_dados_configurada <- function() {
  dir_reais <- Sys.getenv(variavel_dados_reais)

  if (!nzchar(dir_reais)) {
    return(list(modo = "ficticio", sinan = caminho_dados_ficticios("sinan_hanseniase_pe_ficticio.csv")))
  }

  # Com a variavel definida, nunca cai nos ficticios em silencio: sem o
  # arquivo de casos, para com erro.
  sinan <- file.path(dir_reais, "sinan_hanseniase_pe.csv")
  if (!file.exists(sinan)) {
    stop(variavel_dados_reais, " esta' definido, mas a pasta nao tem o arquivo sinan_hanseniase_pe.csv")
  }
  list(modo = "real", sinan = normalizePath(sinan))
}

# Identifica a fonte e a versao do arquivo (data de modificacao e tamanho): a
# base local e' remontada quando muda
assinatura_fonte <- function(fonte) {
  info <- file.info(fonte$sinan)
  list(
    modo     = fonte$modo,
    arquivos = unname(as.character(fonte$sinan)),
    mtime    = as.numeric(info$mtime),
    tamanho  = info$size
  )
}

# TRUE quando a base carregada veio dos dados ficticios -- liga os avisos de
# DADOS FICTICIOS. Sem registro de origem (base montada por uma versao antiga
# ou ainda em montagem), considera ficticia: na duvida, o aviso aparece.
dados_sao_ficticios <- function() {
  !identical(le_fonte_base()$modo, "real")
}

# Registro de origem da base local (NULL se nao existe ou nao da' para ler)
le_fonte_base <- function() {
  if (!file.exists(arquivo_fonte_base)) return(NULL)
  tryCatch(readRDS(arquivo_fonte_base), error = function(e) NULL)
}

# Transformação hans_sinan (bruta) -> hans_sinan_treated, no DuckDB.
#
# Categorias decodificadas pelo dicionário de dados do SINAN NET --
# Hanseníase. Campo vazio vira "Ignorado" (ou "Em tratamento", no desfecho)
# em vez de NULL: os filtros do painel usam %in% e descartariam NULL
# silenciosamente.
#
# Datas e códigos passam por try_cast/try_strptime: valor fora do formato
# vira NULL em vez de derrubar a atualização (a trava de update_hans_data()
# aborta se as datas de diagnóstico não forem reconhecidas).
#
# Datas: aceitas como número de série do Excel -- dias desde 30/12/1899, com
# 4 ou 5 dígitos (ex.: 43538 = 14/03/2019), como a saída da pipeline de
# georreferenciamento traz quando o CSV passou por planilha --, texto
# dd/mm/aaaa (formato dos fictícios), aaaa-mm-dd e aaaammdd, e DATE/TIMESTAMP.
# Número que chega como double ("43538.0") perde o ".0" antes (texto_sinan).
transforma_hans_sinan <- function(con) {
  DBI::dbExecute(con, "
    create or replace macro texto_sinan(x) as regexp_replace(trim(cast(x as varchar)), '\\.0+$', '')
  ")
  DBI::dbExecute(con, "
    create or replace macro data_sinan(x) as
      case
        when regexp_full_match(texto_sinan(x), '[0-9]{4,5}')
          then date '1899-12-30' + try_cast(texto_sinan(x) as integer)
        else try_cast(try_strptime(left(texto_sinan(x), 10), ['%d/%m/%Y', '%Y-%m-%d', '%Y%m%d']) as date)
      end
  ")
  DBI::dbExecute(con, "
    create or replace macro cod_sinan(x) as try_cast(try_cast(x as double) as integer)
  ")
  # Código IBGE de 6 dígitos (o do SINAN), venha ele com 6 ou 7 dígitos
  DBI::dbExecute(con, "
    create or replace macro mun_sinan(x) as left(cast(try_cast(try_cast(x as double) as bigint) as varchar), 6)
  ")

  DBI::dbExecute(con, "
    create or replace table hans_sinan_treated as (
    with base as (
    select
    -- 7 digitos como no SINAN: a origem traz numero inteiro, sem os zeros
    -- a esquerda
    lpad(texto_sinan(NU_NOTIFIC), 7, '0') as numero_notificacao,
    data_sinan(DT_DIAG) as dt_diagnostico,
    data_sinan(DT_NOTIFIC) as dt_notificacao,
    data_sinan(DTINICTRAT) as dt_inicio_tratamento,
    data_sinan(DTALTA_N) as dt_alta,
    NM_PACIENT as nome_paciente,
    data_sinan(DT_NASC) as dt_nasc_sinan,
    -- NU_IDADE_N: 1o digito = unidade (1 hora, 2 dia, 3 mes, 4 ano), o
    -- resto = valor
    case left(cast(cod_sinan(NU_IDADE_N) as varchar), 1)
      when '1' then try_cast(substr(cast(cod_sinan(NU_IDADE_N) as varchar), 2) as integer)/8760
      when '2' then try_cast(substr(cast(cod_sinan(NU_IDADE_N) as varchar), 2) as integer)/365
      when '3' then try_cast(substr(cast(cod_sinan(NU_IDADE_N) as varchar), 2) as integer)/12
      when '4' then try_cast(substr(cast(cod_sinan(NU_IDADE_N) as varchar), 2) as integer)
    end as idade,
    coalesce(nullif(upper(trim(cast(CS_SEXO as varchar))), ''), 'I') as sexo,
    case cod_sinan(CS_RACA)
      when 1 then 'Branca'
      when 2 then 'Preta'
      when 3 then 'Amarela'
      when 4 then 'Parda'
      when 5 then 'Indígena'
      else 'Ignorado'
    end as raca_cor,
    case cod_sinan(CS_ESCOL_N)
      when 0 then 'Analfabeto'
      when 1 then '1ª a 4ª série incompleta do EF'
      when 2 then '4ª série completa do EF'
      when 3 then '5ª à 8ª série incompleta do EF'
      when 4 then 'Ensino fundamental completo'
      when 5 then 'Ensino médio incompleto'
      when 6 then 'Ensino médio completo'
      when 7 then 'Educação superior incompleta'
      when 8 then 'Educação superior completa'
      when 10 then 'Não se aplica'
      else 'Ignorado'
    end as escolaridade,
    case cod_sinan(CS_GESTANT)
      when 1 then '1º trimestre'
      when 2 then '2º trimestre'
      when 3 then '3º trimestre'
      when 4 then 'Idade gestacional ignorada'
      when 5 then 'Não'
      when 6 then 'Não se aplica'
      else 'Ignorado'
    end as gestante,
    -- Municipio de residencia (territorio dos indicadores) e de notificacao,
    -- codigo IBGE de 6 digitos
    mun_sinan(ID_MN_RESI) as cod_mun_residencia,
    mun_sinan(ID_MUNICIP) as cod_mun_notificacao,
    -- Codigo CNES da unidade notificadora, com 7 digitos (a origem traz
    -- numero, sem os zeros a esquerda) -- cruza com a camada de unidades de
    -- saude do mapa (dev/build_unidades_cnes.R)
    lpad(nullif(texto_sinan(ID_UNIDADE), ''), 7, '0') as cod_unidade_notificadora,
    cod_sinan(NU_LESOES) as n_lesoes,
    cod_sinan(NERVOSAFET) as n_nervos_afetados,
    case cod_sinan(FORMACLINI)
      when 1 then 'Indeterminada'
      when 2 then 'Tuberculoide'
      when 3 then 'Dimorfa'
      when 4 then 'Virchowiana'
      when 5 then 'Não classificada'
      else 'Ignorado'
    end as forma_clinica,
    case cod_sinan(CLASSOPERA)
      when 1 then 'Paucibacilar'
      when 2 then 'Multibacilar'
      else 'Ignorado'
    end as classificacao_operacional,
    -- Grau de incapacidade fisica (GIF) no diagnostico e na alta
    case cod_sinan(AVALIA_N)
      when 0 then 'Grau 0'
      when 1 then 'Grau I'
      when 2 then 'Grau II'
      when 3 then 'Não avaliado'
      else 'Ignorado'
    end as gif_diagnostico,
    case cod_sinan(AVAL_ATU_N)
      when 0 then 'Grau 0'
      when 1 then 'Grau I'
      when 2 then 'Grau II'
      when 3 then 'Não avaliado'
      else 'Ignorado'
    end as gif_alta,
    case cod_sinan(MODOENTR)
      when 1 then 'Caso novo'
      when 2 then 'Transferência do mesmo município'
      when 3 then 'Transferência de outro município'
      when 4 then 'Transferência de outro estado'
      when 5 then 'Transferência de outro país'
      when 6 then 'Recidiva'
      when 7 then 'Outros reingressos'
      else 'Ignorado'
    end as modo_entrada_detalhe,
    case
      when cod_sinan(MODOENTR) = 1 then 'Caso novo'
      when cod_sinan(MODOENTR) in (2, 3, 4, 5) then 'Transferência'
      when cod_sinan(MODOENTR) = 6 then 'Recidiva'
      when cod_sinan(MODOENTR) = 7 then 'Outros reingressos'
      else 'Ignorado'
    end as modo_entrada,
    case cod_sinan(MODODETECT)
      when 1 then 'Encaminhamento'
      when 2 then 'Demanda espontânea'
      when 3 then 'Exame de coletividade'
      when 4 then 'Exame de contatos'
      when 5 then 'Outros modos'
      else 'Ignorado'
    end as modo_deteccao,
    case cod_sinan(BACILOSCO)
      when 1 then 'Positiva'
      when 2 then 'Negativa'
      when 3 then 'Não realizada'
      else 'Ignorado'
    end as baciloscopia,
    case cod_sinan(ESQ_INI_N)
      when 1 then 'PQT/PB/6 doses'
      when 2 then 'PQT/MB/12 doses'
      when 3 then 'Outros esquemas substitutos'
      else 'Ignorado'
    end as esquema_inicial,
    cod_sinan(CONTREG) as contatos_registrados,
    cod_sinan(CONTEXAM) as contatos_examinados,
    case cod_sinan(TPALTA_N)
      when 1 then 'Cura'
      when 2 then 'Transferência para o mesmo município'
      when 3 then 'Transferência para outro município'
      when 4 then 'Transferência para outro estado'
      when 5 then 'Transferência para outro país'
      when 6 then 'Óbito'
      when 7 then 'Abandono'
      when 8 then 'Erro diagnóstico'
      when 9 then 'Transferência não especificada'
    end as tipo_saida,
    -- Desfecho agrupado (o que o painel filtra e colore): as transferencias
    -- viram uma categoria so'; sem tipo de saida = em tratamento
    case
      when cod_sinan(TPALTA_N) = 1 then 'Cura'
      when cod_sinan(TPALTA_N) in (2, 3, 4, 5, 9) then 'Transferência'
      when cod_sinan(TPALTA_N) = 6 then 'Óbito'
      when cod_sinan(TPALTA_N) = 7 then 'Abandono'
      when cod_sinan(TPALTA_N) = 8 then 'Erro diagnóstico'
      else 'Em tratamento'
    end as desfecho,
    ADDRESS_CORE as endereco,
    ENDERECO_CNEFE as endereco_cnefe,
    NM_BAIRRO as bairro,
    -- GEORREFERENCIADO e INDICADOR vem prontos da pipeline de
    -- georreferenciamento (repositorio Sistema-de-georreferenciamento-
    -- Projeto-Cenarios-UnB):
    --   georreferenciado = 1: o caso casou numa fase de endereco; 0:
    --     centroide, sem coordenada ou endereco vazio (NULL conta como 0).
    --   indicador = 0: detento ou situacao de rua; 1: demais.
    -- Lidos como texto: codigo 1 ou 1.0, coordenada com decimal ponto ou virgula
    coalesce(cod_sinan(GEORREFERENCIADO), 0) as georreferenciado,
    coalesce(cod_sinan(INDICADOR), 1) as indicador,
    try_cast(replace(trim(cast(LATITUDE as varchar)), ',', '.') as double) as lat,
    try_cast(replace(trim(cast(LONGITUDE as varchar)), ',', '.') as double) as long
    from hans_sinan
    )
    select
    * exclude (dt_nasc_sinan, idade),
    dt_nasc_sinan as dt_nasc,
    -- Sem NU_IDADE_N valido, calcula pela data de nascimento
    coalesce(idade, date_diff('day', dt_nasc_sinan, dt_diagnostico) / 365.25) as idade,
    case when desfecho = 'Em tratamento' then 'Em tratamento' else 'Encerrado' end as situacao
    from base
    );
  ")
}

# Data num formato que transforma_hans_sinan() não reconhece vira NULL, e
# caso sem data de diagnóstico não cai em período nenhum: o painel abriria
# zerado. Para a atualização antes de regravar o cache -- o painel continua
# com os dados anteriores -- e mostra o formato que chegou (dígitos trocados
# por 9, sem expor valores).
valida_datas_hans <- function(con) {
  datas <- DBI::dbGetQuery(con, "
    select count(*) as n, count(dt_diagnostico) as n_datas, max(dt_diagnostico) as ultima
    from hans_sinan_treated
  ")
  if (datas$n_datas < 0.5 * datas$n ||
      datas$ultima < as.Date("2000-01-01") || datas$ultima > Sys.Date() + 366) {
    formatos <- DBI::dbGetQuery(con, "
      select regexp_replace(cast(DT_DIAG as varchar), '[0-9]', '9', 'g') as formato, count(*) as n
      from hans_sinan group by 1 order by 2 desc limit 3
    ")
    stop(
      "Atualizacao abortada: datas de diagnostico nao reconhecidas (", datas$n_datas, " de ",
      datas$n, " registros com data valida, ultima: ", format(datas$ultima, "%d/%m/%Y"),
      "). Formato de DT_DIAG na origem: ", paste0("'", formatos$formato, "'", collapse = ", "),
      ". O cache do painel nao foi alterado.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# CSV da fonte com todas as colunas como texto -- a transformacao converte
# datas, codigos e coordenadas (try_cast). O DuckDB detecta o separador
# ("," ou ";").
le_csv_fonte <- function(caminho) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sprintf(
    "select * from read_csv(%s, header = true, all_varchar = true, nullstr = ['NA', ''])",
    DBI::dbQuoteString(con, normalizePath(caminho, winslash = "/"))
  ))
}

update_hans_data <- function(fonte = fonte_dados_configurada()) {

  # Envolve todo o código em tryCatch para capturar erros sem quebrar o app
  tryCatch({

    # ==================================================================================
    # PASSO 2: CONTAR REGISTROS ANTIGOS NO DUCKDB
    # ==================================================================================

    # Só abre o banco em modo leitura se o arquivo já existir -- duckdb com
    # read_only = TRUE dá erro na conexão quando o arquivo não existe
    # (instalação recém-clonada).
    count_old <- if (file.exists("local/sinan.duckdb")) {
      con_duck_check <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb", read_only = TRUE)
      resultado <- tryCatch(
        DBI::dbGetQuery(con_duck_check, "SELECT COUNT(*) as cnt FROM hans_sinan_treated")$cnt,
        error = function(e) 0
      )
      DBI::dbDisconnect(con_duck_check, shutdown = TRUE)
      resultado
    } else {
      0
    }

    # ==================================================================================
    # PASSO 3: LER OS CASOS DA FONTE
    # ==================================================================================

    # Colunas da saida da pipeline de georreferenciamento: campos do SINAN,
    # GEORREFERENCIADO, INDICADOR e LATITUDE/LONGITUDE
    hans_sinan_new <- le_csv_fonte(fonte$sinan)

    # ==================================================================================
    # PASSO 3.1: VALIDAR OS DADOS NOVOS ANTES DE SOBRESCREVER
    # ==================================================================================

    # Nunca sobrescrever dados bons com um arquivo vazio ou bem menor do que
    # o que já existia (extração incompleta, arquivo em gravação) -- sem essa
    # trava, uma falha silenciosa apaga a base local.
    if (nrow(hans_sinan_new) == 0) {
      stop("Atualizacao abortada: os dados de origem vieram com 0 registros. Nenhum dado foi sobrescrito.")
    }
    if (count_old > 0 && nrow(hans_sinan_new) < count_old * 0.5) {
      stop(
        "Atualizacao abortada: os dados de origem vieram com ", nrow(hans_sinan_new),
        " registros, bem menos que os ", count_old, " ja existentes. ",
        "Nenhum dado foi sobrescrito."
      )
    }

    # ==================================================================================
    # PASSO 4: GRAVAR NO DUCKDB E TRANSFORMAR
    # ==================================================================================

    dir.create("local", showWarnings = FALSE)
    con_duck <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb")
    on.exit(DBI::dbDisconnect(con_duck, shutdown = TRUE), add = TRUE)

    DBI::dbWriteTable(con_duck, "hans_sinan", hans_sinan_new, overwrite = TRUE)
    transforma_hans_sinan(con_duck)

    # ==================================================================================
    # PASSO 4.1: VALIDAR AS DATAS ANTES DE REGRAVAR O CACHE
    # ==================================================================================

    valida_datas_hans(con_duck)

    # ==================================================================================
    # PASSO 5: GERAR CACHE RDS (carregamento rápido na sessão do usuário)
    # ==================================================================================

    # prepara_casos() (R/fct_casos.R) monta os casos do painel já com o
    # município e a GERES de residência de cada um.
    tryCatch({
      casos_cache <- DBI::dbGetQuery(con_duck, "SELECT * FROM hans_sinan_treated") |>
        prepara_casos()
      saveRDS(casos_cache, "local/casos_cache.rds")
    }, error = function(e) {
      warning("Cache RDS não gerado: ", as.character(e))
    })

    # ==================================================================================
    # PASSO 6: CALCULAR DIFERENÇA E RETORNAR RESULTADO
    # ==================================================================================

    count_new <- DBI::dbGetQuery(con_duck, "SELECT COUNT(*) as cnt FROM hans_sinan_treated")$cnt
    records_updated <- count_new - count_old

    if (records_updated > 0) {
      list(
        success = TRUE,
        message = paste0("✅ Atualização concluída! ", records_updated, " novo(s) registro(s) adicionado(s)."),
        records_updated = records_updated
      )
    } else if (records_updated == 0) {
      list(
        success = TRUE,
        message = "ℹ️ Nenhum dado novo para atualizar.",
        records_updated = 0
      )
    } else {
      list(
        success = TRUE,
        message = paste0("📊 Dados reprocessados. Total: ", count_new, " registros."),
        records_updated = count_new
      )
    }

  }, error = function(e) {
    list(
      success = FALSE,
      message = paste0("❌ Erro na atualização: ", as.character(e)),
      records_updated = 0
    )
  })
}

# ==================================================================================
# FUNÇÃO: prepara_base()
#
# Chamada a cada abertura do painel. Monta a base local quando ela ainda nao
# existe ou quando a fonte mudou -- troca entre dados ficticios e reais, outra
# pasta, ou arquivo atualizado -- e registra a origem em local/fonte_dados.rds
# (que liga ou desliga os avisos de DADOS FICTICIOS, ver dados_sao_ficticios()).
# Sem mudanca, so' confere data e tamanho do arquivo. Tambem copia o cadastro
# publico das unidades de saude, se local/ ainda nao tem um.
# ==================================================================================

prepara_base <- function() {
  if (!dir.exists("local")) dir.create("local")

  if (!file.exists("local/unidades_cnes.rds")) {
    file.copy(caminho_dados_ficticios("unidades_cnes.rds"), "local/unidades_cnes.rds")
  }

  fonte <- fonte_dados_configurada()
  nova <- assinatura_fonte(fonte)
  atual <- le_fonte_base()

  if (identical(atual, nova) && file.exists("local/casos_cache.rds")) {
    return(invisible(nova$modo))
  }

  # Outra fonte (ficticio <-> real, outra pasta) ou base sem registro de
  # origem: comeca do zero, sem a trava de "bem menos registros que antes"
  # do update_hans_data() (que so' faz sentido para a mesma fonte). O registro
  # de origem sai primeiro: enquanto a base nao estiver pronta, vale o aviso.
  mesma_fonte <- !is.null(atual) && identical(atual[c("modo", "arquivos")], nova[c("modo", "arquivos")])
  if (!mesma_fonte) {
    unlink(c(arquivo_fonte_base, "local/sinan.duckdb", "local/sinan.duckdb.wal", "local/casos_cache.rds"))
  }

  message("Montando a base local a partir dos dados ",
          if (fonte$modo == "real") "REAIS" else "ficticios", "...")
  resultado <- update_hans_data(fonte)

  if (!isTRUE(resultado$success)) {
    # Mesma fonte com arquivo novo recusado pela validacao: segue com a base
    # anterior, que tem a mesma origem (e tenta de novo na proxima abertura)
    if (mesma_fonte && file.exists("local/casos_cache.rds")) {
      warning(resultado$message)
      return(invisible(atual$modo))
    }
    stop(resultado$message)
  }

  saveRDS(nova, arquivo_fonte_base)
  message(resultado$message)
  invisible(nova$modo)
}
