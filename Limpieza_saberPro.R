# SCRIPT DE LIMPIEZA Y EXPORTACIÓN  BASE SABER PRO
# Fuente: DataIcfes (bases públicas, anonimizadas)
#   02_Examen Saber Pro > 01_Módulos genéricos
#   - Examen_Saber_Pro_Genericas_2024.txt  -> base principal de la tesis
#   - Examen_Saber_Pro_Genericas_2025.txt  -> solo para validar el modelo fuera del tiempo
#
# REGISTRO DE AJUSTES (versión 21-oct-2026, revisando los .txt crudos línea a línea)
# Marcados en el código como "AJUSTE L-oct-2026". En resumen:
#  L1. Edad: se deriva de estu_fechanacimiento (antes la fecha se caía por alta
#      cardinalidad y la edad nunca llegaba al modelo).
#  L2. Bandera diag_escrita_cero: estudiantes con comunicación escrita en 0
#      (módulo no calificado). Es diagnóstico, NO predictor (sale del examen).
#  L3. estu_etnia y estu_tieneetnia fuera de forma explícita: tieneetnia = "S"
#      aparece hasta con etnia "Ninguno", no mide pertenencia.
#  L4. estu_repite fuera: trae valores tipo 120555, son códigos, no repeticiones.
#  L5. estu_depto_reside se protege del filtro de cardinalidad (el documento
#      dice que se usa y no llegaba) y sus categorías raras se agrupan.
#  L6. Variables con más de 90% de NA fuera, con diagnóstico por periodo.
#  L7. Armonización de etiquetas 2024-2025 (mayúsculas, tildes) y chequeo de
#      compatibilidad: si 2025 cambió las categorías de una variable, esa
#      variable sale de las dos bases.
#  L8. fami_trabajolabor* fuera: en 20241 es copia exacta de fami_ocupacion* y
#      desde 20243 el ICFES cambió la pregunta (dos codificaciones en un año).
#  L9. Preguntas no aplicadas en algún periodo grande (compartebaño y consola
#      vienen 100% NA en 20241 y 20242) fuera: su NA es efecto de periodo.
#####################################################3

# 1. LIBRERÍAS
inicio_total <- Sys.time()
paquetes <- c(
  "tidyverse","data.table","stringi")

nuevos <- paquetes[!(paquetes %in% installed.packages()[,"Package"])]
if(length(nuevos)) install.packages(nuevos)
invisible(lapply(paquetes, library, character.only = TRUE))
options(scipen = 999)

# 2. RUTA ARCHIVOS
# Ojo: la ruta se toma de la variable de entorno RUTA_SABERPRO y, si no existe,
# de la carpeta del proyecto (la misma que usa el pipeline, para que los dos
# scripts lean y escriban en el mismo lado).
ruta_por_defecto <- getwd()  # en mi equipo apuntaba a la carpeta Proyecto_Grado/App de OneDrive
ruta <- Sys.getenv("RUTA_SABERPRO", unset = ruta_por_defecto)
archivo_2024 <- file.path(ruta, "Examen_Saber_Pro_Genericas_2024.txt")
archivo_2025 <- file.path(ruta, "Examen_Saber_Pro_Genericas_2025.txt")

if(!file.exists(archivo_2024)) stop("No encuentro el archivo 2024 en: ", archivo_2024,
                                    "\nPilas: los .txt del ICFES tienen que estar en la misma carpeta de los CSV.")

# Log de la limpieza, igual que el pipeline: todo lo que sale en consola queda en un .txt
con_log <- file(file.path(ruta, "salida_limpieza_saberpro.txt"), open = "wt")
sink(con_log, split = TRUE)

# 3. CARGA
# Los .txt de DataIcfes vienen separados por punto y coma.
# OJO con las tildes: si el archivo no viene en UTF-8 salen cosas como "BOGOTÃ",
# por eso esta función revisa y, si ve ese síntoma, vuelve a leer en Latin-1
leer_icfes <- function(archivo){
  df <- fread(archivo, sep = ";", encoding = "UTF-8",
              na.strings = c("", "NA"), showProgress = FALSE)
  muestra_txt <- unlist(head(df[, sapply(df, is.character), with = FALSE], 2000))
  if(any(grepl("Ã", muestra_txt, fixed = TRUE))){
    message("Pilas: el archivo no venía en UTF-8, se vuelve a leer en Latin-1")
    df <- fread(archivo, sep = ";", encoding = "Latin-1",
                na.strings = c("", "NA"), showProgress = FALSE)}
  df <- as_tibble(df)
  names(df) <- tolower(names(df))
  df}

data_raw <- leer_icfes(archivo_2024)
cat("\n===== DATA ORIGINAL 2024 =====\n")
cat("Filas:", nrow(data_raw), "| Columnas:", ncol(data_raw), "\n")

# AJUSTE L-oct-2026: 2025 se lee desde el principio porque el chequeo de
# compatibilidad de categorías (sección 12) necesita las dos bases a la vez.
hay_2025 <- file.exists(archivo_2025)
data_2025_raw <- if (hay_2025) leer_icfes(archivo_2025) else NULL
if (hay_2025) {
  cat("\n===== DATA ORIGINAL 2025 =====\n")
  cat("Filas:", nrow(data_2025_raw), "| Columnas:", ncol(data_2025_raw), "\n")
  cat("Columnas de 2024 que no vienen en 2025:", paste(setdiff(names(data_raw), names(data_2025_raw)), collapse = ", "), "\n")
  cat("Columnas nuevas en 2025 (no se usan):", paste(setdiff(names(data_2025_raw), names(data_raw)), collapse = ", "), "\n")}

# Chequeos rápidos antes de limpiar (estos números van a la monografía)
cat("\nRegistros por periodo:\n")
print(table(data_raw$periodo, useNA = "ifany"))
cat("\nTipo de inscripción (estu_estudiante):\n")
print(table(data_raw$estu_estudiante, useNA = "ifany"))
cat("\n% de INSE individual faltante:",
    round(mean(is.na(data_raw$estu_inse_individual)) * 100, 1), "\n")
cat("Categorías de estu_nucleo_pregrado:",
    length(unique(na.omit(data_raw$estu_nucleo_pregrado))), "\n")

# 4. VARIABLES DERIVADAS DEL CRUDO (antes de que se pierdan)
# Esto va en una función porque a 2025 se le tiene que hacer exactamente lo mismo.

# AJUSTE L-oct-2026 (L1): edad. La fecha de nacimiento tiene miles de valores
# distintos y el filtro de alta cardinalidad la tumbaba, así que la edad nunca
# entraba. Se calcula con el año del periodo del examen (es aproximada en +-1
# año porque no se usa el día exacto del examen, para esto funciona bien).
# Edades por fuera de 15-80 se tratan como error de digitación y quedan NA.
# AJUSTE L-oct-2026 (L2): comunicación escrita en 0. En el crudo hay
# estudiantes con mod_comuni_escrita_desem vacío y punt = 0: el escrito no se
# calificó y el ICFES promedia ese 0 dentro del puntaje global, que queda
# hundido. Ningún predictor socioeconómico puede anticipar eso. La bandera NO
# entra al modelo (sale del examen, sería fuga); el pipeline la usa solo para
# diagnosticar el error.
derivar_del_crudo <- function(df, etiqueta = "") {
  if ("estu_fechanacimiento" %in% names(df)) {
    fecha_nac <- suppressWarnings(as.Date(as.character(df$estu_fechanacimiento), format = "%d/%m/%Y"))
    anio_examen <- suppressWarnings(as.numeric(substr(as.character(df$periodo), 1, 4)))
    edad <- anio_examen - as.numeric(format(fecha_nac, "%Y"))
    n_fuera <- sum(!is.na(edad) & (edad < 15 | edad > 80))
    edad[!is.na(edad) & (edad < 15 | edad > 80)] <- NA
    df$edad <- edad
    cat("\n[", etiqueta, "] Edad derivada | NA:", sum(is.na(edad)),
        "| fuera de 15-80 (quedan NA):", n_fuera, "\n")
    print(summary(edad))
    df <- df %>% select(-estu_fechanacimiento)}
  if ("mod_comuni_escrita_punt" %in% names(df)) {
    cols_punt <- grep("^mod_.*_punt$", names(df), value = TRUE)
    m_punt <- sapply(df[cols_punt], function(x) suppressWarnings(as.numeric(x)))
    n_mod_cero <- rowSums(m_punt == 0, na.rm = TRUE)
    df$diag_escrita_cero <- as.integer(suppressWarnings(as.numeric(df$mod_comuni_escrita_punt)) == 0)
    cat("\n[", etiqueta, "] Módulos en cero por estudiante:\n")
    print(table(n_mod_cero))
    cat("[", etiqueta, "] Comunicación escrita en 0:", sum(df$diag_escrita_cero == 1, na.rm = TRUE),
        sprintf("(%.1f%%)", 100 * mean(df$diag_escrita_cero == 1, na.rm = TRUE)),
        "| media global con escrita en 0:",
        round(mean(suppressWarnings(as.numeric(df$punt_global))[df$diag_escrita_cero %in% 1]), 1),
        "| sin:", round(mean(suppressWarnings(as.numeric(df$punt_global))[df$diag_escrita_cero %in% 0]), 1), "\n")}
  df}

data_raw <- derivar_del_crudo(data_raw, "2024")
if (hay_2025) data_2025_raw <- derivar_del_crudo(data_2025_raw, "2025")

# 5. LIMPIEZA DE TIPOS
# Ajuste importante frente a la versión anterior: antes una columna pasaba a
# numérica si menos del 60% fallaba al convertir. Eso era peligroso con
# variables mixtas como estu_horassemanatrabaja ("0", "Menos de 10 horas"...):
# si dominaban los "0", R la volvía número y las categorías de texto quedaban NA
# sin avisar. Ahora solo se convierte si prácticamente todo el dato es número.
convertir_num <- function(x){
  if(is.numeric(x)) return(x)
  x_ok <- x[!is.na(x)]
  if(length(x_ok) == 0) return(x)
  num <- suppressWarnings(as.numeric(x_ok))
  if(mean(is.na(num)) <= 0.005) return(suppressWarnings(as.numeric(x)))
  else return(x)}

# Estas se quedan como texto sí o sí, son categóricas aunque traigan números
vars_texto_fijo <- c("estu_horassemanatrabaja", "fami_estratovivienda",
                     "estu_estudiante", "estu_consecutivo", "estu_semestrecursa")

data <- data_raw %>%
  mutate(across(where(is.factor), as.character)) %>%
  mutate(across(-any_of(vars_texto_fijo), convertir_num))

# 6. TARGET
target <- "punt_global"
data[[target]] <- suppressWarnings(as.numeric(data[[target]]))
if(all(is.na(data[[target]]))){
  stop("ERROR: punt_global no es numérico")}

# 7. LIMPIEZA ESTRUCTURAL
data <- data %>% select(where(~ sum(!is.na(.)) > 0))
# La base pública ya viene anonimizada (no trae nombres, documento, correo ni
# teléfono). Igual se deja esta lista por si acaso el ICFES cambia algo.
vars_drop <- c(
  "estu_consecutivo","estu_snies","estu_documento",
  "estu_correoelectronico","estu_celular",
  "estu_direccion","estu_telefono",
  "estu_primernombre","estu_segundonombre",
  "estu_primerapellido","estu_segundoapellido")
data <- data %>% select(-any_of(vars_drop))

# 7.1 AJUSTE L-oct-2026 (L3): etnia. Pilas con esto, mirando el crudo se ve
# que estu_tieneetnia = "S" aparece incluso cuando estu_etnia = "Ninguno". O
# sea que la "S" parece marcar "respondió la pregunta", no "pertenece a una
# etnia". Las dos salen: una no mide lo que dice y la otra es sensible y casi
# toda NA. Se deja el cruce en el log para la sustentación.
if (all(c("estu_tieneetnia", "estu_etnia") %in% names(data))) {
  cat("\nCruce estu_tieneetnia vs. estu_etnia == 'Ninguno' (por qué se excluyen):\n")
  print(table(tieneetnia = data$estu_tieneetnia,
              etnia_ninguno = ifelse(is.na(data$estu_etnia), "etnia NA",
                                     ifelse(data$estu_etnia == "Ninguno", "Ninguno", "Otra etnia")),
              useNA = "ifany"))}
vars_etnia <- intersect(c("estu_etnia", "estu_tieneetnia"), names(data))
data <- data %>% select(-any_of(vars_etnia))
cat("Excluidas por etnia (sensibles / mal codificadas):", paste(vars_etnia, collapse = ", "), "\n")

# 7.2 AJUSTE L-oct-2026 (L4): estu_repite. En el crudo trae cosas como 120555,
# 210382 o 30710, eso no es un número de veces que se repite nada, parecen
# códigos. Se deja el resumen en el log y se saca.
if ("estu_repite" %in% names(data)) {
  cat("\nestu_repite (se excluye, valores no interpretables):\n")
  cat("  % en cero:", round(100 * mean(data$estu_repite == 0, na.rm = TRUE), 1), "\n")
  print(quantile(data$estu_repite, c(.5, .9, .95, .99, 1), na.rm = TRUE))
  data <- data %>% select(-estu_repite)}

# 8. TEXTOS VACÍOS A NA
data <- data %>% mutate(across(where(is.character), ~ na_if(str_squish(.x), "")))

# 8.1 Variables duplicadas
# AJUSTE L-oct-2026 (L8): antes se miraba la coincidencia de fami_trabajolabor*
# con fami_ocupacion* en TODO el año (~62%) y se concluía que no eran
# duplicadas. Mirando por periodo la historia es otra:
#  - en 20241 trabajolabor es una COPIA EXACTA de ocupacion (mismos conteos
#    en todas las categorías: Hogar 68.884 en las dos, etc.)
#  - desde 20243 el ICFES cambió la pregunta y trabajolabor trae categorías
#    nuevas ("Trabaja en el hogar, no trabaja o estudia"...)
# O sea que la variable mezcla dos codificaciones según el periodo y en el más
# grande no aporta nada. ocupacion* sí es consistente en 2024 y en 2025, esa
# es la que se queda.
pares_dup <- c(fami_trabajolabormadre = "fami_ocupacionmadre",
               fami_trabajolaborpadre = "fami_ocupacionpadre")
for(v in names(pares_dup)){
  if(all(c(v, pares_dup[[v]]) %in% names(data))){
    coinc_periodo <- data %>%
      group_by(periodo) %>%
      summarise(n_con_dato = sum(!is.na(.data[[v]]) & !is.na(.data[[pares_dup[[v]]]])),
                pct_iguales = round(100 * mean(.data[[v]] == .data[[pares_dup[[v]]]], na.rm = TRUE), 2),
                .groups = "drop")
    cat("\nCoincidencia", v, "vs", pares_dup[[v]], "por periodo:\n")
    print(as.data.frame(coinc_periodo))
    # si en algún periodo es copia (>99%) la variable no es una pregunta propia: fuera
    if(any(coinc_periodo$pct_iguales > 99, na.rm = TRUE)) {
      cat("->", v, "se excluye: en algún periodo es copia de", pares_dup[[v]], "y en otros cambia de codificación\n")
      data <- data %>% select(-all_of(v))}}}

# 8.2 AJUSTE L-oct-2026 (L9): preguntas que no se hicieron en todos los periodos.
# fami_cuantoscompartebaño y fami_tieneconsolavideojuegos vienen 100% NA en
# 20241 y 20242 (el 58% de la cohorte), o sea que esa pregunta no se aplicó.
# En 2025 sí se aplicó en todos. Si se dejan, "No reporta" termina queriendo
# decir "presentó en 20241": un efecto de periodo disfrazado de variable
# socioeconómica, y en 2025 casi nadie cae ahí. Regla: si en un periodo con al
# menos 10% de los registros la variable viene con más de 95% de NA, no se
# preguntó ahí y se excluye.
if ("periodo" %in% names(data)) {
  peso_periodo <- data %>% count(periodo) %>% mutate(pct = n / sum(n))
  periodos_grandes <- peso_periodo$periodo[peso_periodo$pct >= 0.10]
  na_por_periodo <- data %>%
    filter(periodo %in% periodos_grandes) %>%
    group_by(periodo) %>%
    summarise(across(-any_of(target), ~ mean(is.na(.x))), .groups = "drop")
  vars_no_preguntadas <- names(na_por_periodo)[-1][sapply(na_por_periodo[-1], function(x) any(x > 0.95))]
  cat("\nPeso de cada periodo en 2024:\n"); print(as.data.frame(peso_periodo))
  cat("Variables que no se preguntaron en algún periodo grande (se excluyen):",
      if (length(vars_no_preguntadas) > 0) paste(vars_no_preguntadas, collapse = ", ") else "ninguna", "\n")
  data <- data %>% select(-any_of(vars_no_preguntadas))}

# 9. REDUCCIÓN INICIAL

# Alta cardinalidad
cardinalidad <- sapply(data, function(x){if(is.numeric(x)) return(0)
  else return(length(unique(na.omit(x))))})
vars_high <- names(cardinalidad[cardinalidad > 50])
# OJO: estu_nucleo_pregrado reemplaza a gruporeferencia (que la base pública no
# trae) y tiene alrededor de 50 categorías, así que se protege del filtro.
# AJUSTE L-oct-2026 (L5): estu_depto_reside también se protege. El documento
# dice que el PSM controla por departamento de residencia y esa columna no
# estaba llegando al pipeline (se caía aquí). Abajo se agrupan sus categorías raras.
vars_protegidas <- c(target, "estu_nucleo_pregrado", "estu_depto_reside")
cat("\nCardinalidad de las protegidas:\n")
print(cardinalidad[intersect(vars_protegidas[-1], names(cardinalidad))])
vars_high <- setdiff(vars_high, vars_protegidas)
cat("\nVariables eliminadas por alta cardinalidad:", length(vars_high), "\n")
print(vars_high)
num_vars <- names(data)[sapply(data, is.numeric)]
varianza <- sapply(data[num_vars], var, na.rm = TRUE)
vars_const <- names(varianza[!is.na(varianza) & varianza < 1e-5])
vars_const <- setdiff(vars_const, c(target, "diag_escrita_cero"))
data <- data %>%
  select(-any_of(vars_high)) %>%
  select(-any_of(vars_const))

# 9.1 Departamento de residencia: categorías con menos de 30 estudiantes se
# agrupan (suelen ser residencias en el exterior o errores de digitación).
min_n_depto <- 30
niveles_depto_reside <- character(0)
if ("estu_depto_reside" %in% names(data)) {
  conteo_depto <- table(data$estu_depto_reside)
  niveles_depto_reside <- names(conteo_depto[conteo_depto >= min_n_depto])
  n_agrupados <- sum(!is.na(data$estu_depto_reside) & !(data$estu_depto_reside %in% niveles_depto_reside))
  data <- data %>%
    mutate(estu_depto_reside = if_else(!is.na(estu_depto_reside) & !(estu_depto_reside %in% niveles_depto_reside),
                                       "OTRO / EXTERIOR", estu_depto_reside))
  cat("estu_depto_reside: categorías que se conservan:", length(niveles_depto_reside),
      "| registros agrupados en 'OTRO / EXTERIOR':", n_agrupados, "\n")}

# 10. ELIMINAR LEAKAGE
# Puntajes por módulo, percentiles y niveles de desempeño salen del mismo
# examen, si se dejan el modelo "adivina" punt_global. Fuera.
# (diag_escrita_cero se queda solo como diagnóstico; el pipeline la saca del modelo)
vars_leakage <- c(
  "percentil_global",
  "percentil_nbc",
  grep("^mod_.*punt", names(data), value = TRUE),
  grep("^mod_.*pnal", names(data), value = TRUE),
  grep("^mod_.*pnbc", names(data), value = TRUE),
  grep("^mod_.*desem", names(data), value = TRUE))
vars_leakage <- intersect(vars_leakage, names(data))
cat("\nVariables eliminadas por leakage:", length(vars_leakage), "\n")
data <- data %>% select(-any_of(vars_leakage))

# 10.1 AJUSTE L-oct-2026 (L6): variables casi vacías. Las de cursos, refuerzo y
# simulacro vienen con ~92% de NA: solo las contesta una parte de los
# estudiantes. Imputarlas sería inventar el 92% del dato. Antes de sacarlas se
# mira el % de NA por periodo, para saber si es que en algún periodo no se
# preguntaron (eso va a la monografía como limitación).
umbral_na <- 0.90
pct_na <- sapply(data, function(x) mean(is.na(x)))
vars_casi_vacias <- setdiff(names(pct_na[pct_na > umbral_na]), target)
vars_na_altas <- names(pct_na[pct_na > 0.5])
if (length(vars_na_altas) > 0 && "periodo" %in% names(data)) {
  cat("\n% de NA por periodo en variables con más de 50% de faltantes:\n")
  print(as.data.frame(data %>%
                        group_by(periodo) %>%
                        summarise(n = n(), across(all_of(vars_na_altas), ~ round(100 * mean(is.na(.x)), 1)), .groups = "drop")))}
cat("\nVariables eliminadas por tener más de", umbral_na * 100, "% de NA:", length(vars_casi_vacias), "\n")
print(vars_casi_vacias)
data <- data %>% select(-any_of(vars_casi_vacias))

# 11. LIMPIEZA FINAL NUMÉRICA
data <- data %>% mutate(across(where(is.numeric), ~ ifelse(is.infinite(.), NA, .)))

# Chequeo de la variable que antes se podía dañar
if("estu_horassemanatrabaja" %in% names(data)){
  cat("\nestu_horassemanatrabaja (debe seguir siendo texto):", class(data$estu_horassemanatrabaja), "\n")
  print(table(data$estu_horassemanatrabaja, useNA = "ifany"))}

# 12. AJUSTE L-oct-2026 (L7): ARMONIZACIÓN DE ETIQUETAS Y COMPATIBILIDAD 2024-2025
# Revisando los dos .txt se ve que el ICFES no escribe igual las categorías de
# un año a otro: "Profesional Independiente" vs "Profesional independiente",
# "Más de 6" vs "MAS DE 6", y en fami_trabajolabor* cambió la pregunta completa
# ("Hogar" pasa a "Trabaja en el hogar, no trabaja o estudia"). En la
# validación 2025 todo lo que no existe en 2024 se va a "Other", o sea que el
# modelo pierde esa variable sin avisar.
# Paso 1: se compara por una "clave" sin tildes y en mayúscula, y cada clave se
# deja con la etiqueta más frecuente de 2024 (así 2024 no cambia sus etiquetas).
# Paso 2: si más de la mitad de los valores de 2025 de una variable no existen
# en 2024 ni siquiera así, la variable sale de las dos bases.
clave_texto <- function(x) toupper(stringi::stri_trans_general(str_squish(as.character(x)), "Latin-ASCII"))
aprender_mapa <- function(x) {
  tibble(etiqueta = as.character(x)) %>%
    filter(!is.na(etiqueta)) %>%
    count(clave = clave_texto(etiqueta), etiqueta) %>%
    group_by(clave) %>%
    slice_max(n, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(clave, etiqueta)}
aplicar_mapa <- function(x, mapa) {
  x <- as.character(x)
  nueva <- mapa$etiqueta[match(clave_texto(x), mapa$clave)]
  if_else(is.na(nueva), x, nueva)}

vars_texto <- setdiff(names(data)[sapply(data, is.character)], c("estu_estudiante"))
mapas_etiquetas <- map(set_names(vars_texto), ~ aprender_mapa(data[[.x]]))
data <- data %>% mutate(across(all_of(vars_texto), ~ aplicar_mapa(.x, mapas_etiquetas[[cur_column()]])))

vars_incompatibles <- character(0)
if (hay_2025) {
  compat <- map_dfr(vars_texto, function(v) {
    if (!(v %in% names(data_2025_raw))) {
      return(tibble(variable = v, pct_na_2024 = mean(is.na(data[[v]])), pct_na_2025 = 1,
                    pct_valores_2025_nuevos = NA_real_))}
    x25 <- aplicar_mapa(na_if(str_squish(as.character(data_2025_raw[[v]])), ""), mapas_etiquetas[[v]])
    if (v == "estu_depto_reside") x25 <- if_else(!is.na(x25) & !(x25 %in% niveles_depto_reside), "OTRO / EXTERIOR", x25)
    tibble(
      variable = v,
      pct_na_2024 = mean(is.na(data[[v]])),
      pct_na_2025 = mean(is.na(x25)),
      pct_valores_2025_nuevos = mean(!(x25[!is.na(x25)] %in% unique(data[[v]]))))})
  compat <- compat %>% arrange(desc(pct_valores_2025_nuevos))
  cat("\n===== COMPATIBILIDAD DE CATEGORÍAS 2024 vs 2025 (después de armonizar) =====\n")
  print(as.data.frame(compat %>% mutate(across(where(is.numeric), ~ round(.x, 3)))))
  write.csv(compat, file.path(ruta, "diagnostico_compatibilidad_2024_2025.csv"), row.names = FALSE)
  vars_incompatibles <- compat$variable[!is.na(compat$pct_valores_2025_nuevos) & compat$pct_valores_2025_nuevos > 0.5]
  cat("Variables que salen de las dos bases porque 2025 cambió sus categorías:",
      if (length(vars_incompatibles) > 0) paste(vars_incompatibles, collapse = ", ") else "ninguna", "\n")
  cat("Ojo: variables con valores nuevos entre 0% y 50% se quedan; esos valores van a 'Other' en el pipeline.\n")
  data <- data %>% select(-any_of(vars_incompatibles))}

# 13. REPORTE FINAL
n_na_final <- sum(sapply(data, function(x) sum(is.na(x))))
cat("\n===== DATA FINAL LIMPIA 2024 (SIN IMPUTAR) =====\n")
cat("Filas:", nrow(data), "| Columnas:", ncol(data), "\n")
cat("Celdas con NA pendientes de imputar en el pipeline principal:", n_na_final, "\n")
cat("(Esto es normal: la imputación se hace en el pipeline, después de partir\n",
    " entre entrenamiento y prueba, para no filtrar información del test.)\n")
cat("Columnas finales:\n"); print(names(data))

# 14. EXPORTAR CSV
# fwrite escribe en UTF-8. El bom = TRUE es solo para que Excel/Bloc de notas
# muestren bien las tildes (sin eso se ve "BOGOTÃ" aunque en R esté perfecto)
archivo_salida <- file.path(ruta, "data_limpia_tesis.csv")
fwrite(data, archivo_salida, bom = TRUE)
cat("\nArchivo exportado en:\n", archivo_salida, "\n")

# 15. BASE 2025 (VALIDACIÓN FUERA DEL TIEMPO)
# Esta base NO entra al entrenamiento. Solo se usa al final del pipeline para
# ver si el modelo entrenado con 2024 aguanta una cohorte que nunca vio.
# Para que sea comparable se deja exactamente con las mismas columnas y los
# mismos tipos de la base 2024 ya limpia, y con las etiquetas armonizadas con
# los mapas aprendidos en 2024 (nada se aprende de 2025).
if(hay_2025){
  data_2025 <- data_2025_raw
  cols_faltan_2025 <- setdiff(names(data), names(data_2025))
  if(length(cols_faltan_2025) > 0){
    cat("\nOjo, columnas de 2024 que no vienen en 2025 (quedan en NA y se imputan):\n")
    print(cols_faltan_2025)
    for(v in cols_faltan_2025) data_2025[[v]] <- NA}
  
  data_2025 <- data_2025 %>%
    select(all_of(names(data))) %>%
    mutate(across(where(is.factor), as.character))
  for(v in names(data)){
    if(is.numeric(data[[v]])) data_2025[[v]] <- suppressWarnings(as.numeric(data_2025[[v]]))
    else data_2025[[v]] <- na_if(str_squish(as.character(data_2025[[v]])), "")}
  # mismas etiquetas que 2024 y mismo agrupamiento del departamento de residencia
  for (v in intersect(names(mapas_etiquetas), names(data_2025))) {
    data_2025[[v]] <- aplicar_mapa(data_2025[[v]], mapas_etiquetas[[v]])}
  if ("estu_depto_reside" %in% names(data_2025)) {
    data_2025 <- data_2025 %>%
      mutate(estu_depto_reside = if_else(!is.na(estu_depto_reside) & !(estu_depto_reside %in% niveles_depto_reside),
                                         "OTRO / EXTERIOR", estu_depto_reside))}
  
  archivo_salida_2025 <- file.path(ruta, "data_limpia_2025.csv")
  fwrite(data_2025, archivo_salida_2025, bom = TRUE)
  cat("Filas 2025 exportadas:", nrow(data_2025), "\n")
  cat("Archivo 2025 exportado en:\n", archivo_salida_2025, "\n")
} else {
  message("No está el archivo 2025, se omite. El pipeline igual corre sin él.")}

fin_total <- Sys.time()
cat("\nTiempo de limpieza:\n")
print(fin_total - inicio_total)
cat("\n===== SESSION INFO =====\n")
print(sessionInfo())
sink(); close(con_log)
#Q