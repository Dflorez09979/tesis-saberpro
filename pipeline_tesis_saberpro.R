# 0. PARÁMETROS DEL PROYECTO (lo único que hay que tocar para correr en otro equipo)
# Ojo: la ruta se toma de la variable de entorno RUTA_SABERPRO; si no existe,
# se usa la carpeta del proyecto donde quedan los CSV de Limpieza_saberPro.R.
# AJUSTE oct-2026: antes el respaldo era getwd(), y si RStudio arrancaba en
# Documentos el script no encontraba nada. Para correr en otro equipo basta
# con definir RUTA_SABERPRO, no hay que tocar esta línea.
ruta_por_defecto <- getwd()  # en mi equipo apuntaba a la carpeta Proyecto_Grado/App de OneDrive
ruta <- Sys.getenv("RUTA_SABERPRO", unset = ruta_por_defecto)
if (!file.exists(file.path(ruta, "data_limpia_tesis.csv"))) {
  stop("No encuentro data_limpia_tesis.csv en: ", ruta,
       "\nPilas: corre primero Limpieza_saberPro.R (deja los CSV en Proyecto_Grado/App) ",
       "o define la variable de entorno RUTA_SABERPRO.")}
dir.create(file.path(ruta, "salidas_tesis"), showWarnings = FALSE, recursive = TRUE)
con <- file(file.path(ruta, "salidas_tesis", "salida_pipeline_saberpro.txt"), open = "wt")

sink(con, split = TRUE)
sink(con, type = "message")
#### TESIS MAESTRÍA 
#### Determinantes socioeconómicos del rendimiento académico en Colombia mediante modelos de machine learning ###
#### Base: Saber Pro 2024 pública (DataIcfes, módulos genéricos). Antes de correr esto
#### hay que correr Limpieza_saberPro.R, que es el que deja listo data_limpia_tesis.csv
#### y data_limpia_2025.csv (esta última solo se usa en la sección 17.1).
####
#### REGISTRO DE AJUSTES (versión oct-2026, después de la revisión con la tutora)
#### Los cambios quedan marcados en el código con "AJUSTE oct-2026" para poder
#### rastrearlos en la sustentación. En resumen:
####  A1. Las variables de diseño (estrato, grupo PSM, tratamiento, banderas) ya
####      NO se imputan. Antes la imputación general convertía a los 8.735 sin
####      estrato en estrato 2 / grupo control (observación de la tutora).
####  A2. En la EDA los faltantes categóricos quedan como "No reporta" en vez de
####      la moda (antes internet/computador sin dato quedaban como "Sí").
####  A3. Los códigos administrativos no se winsorizan (se estaba recortando el
####      código de departamento que entra al PSM de variables previas).
####  A4. estu_tieneetnia se excluye de forma explícita y documentada.
####  A5. PSM: caliper sobre el logit del puntaje de propensión (Austin, 2011),
####      sin estudiantes sin estrato, y Rosenbaum también con psens (p-valores),
####      no solo con hlsens.
####  A6. R² tradicional (1 - SSE/SST) además del cuadrado de la correlación.
####  A7. ML: se quitan codificaciones duplicadas del estrato y del INSE, se agrega
####      bandera estrato_faltante y se excluye estu_privado_libertad (sensible).
####  A8. Mapa de familias SHAP corregido para que cuadre con la Tabla 1 (H2).
####  A9. Tuning: aviso y ampliación cuando el óptimo queda en el borde de la malla.
####  A10. Tablas nuevas que el documento citaba y el pipeline no generaba:
####       error por deciles, consistencia de importancias y composición por grupo.
####  A11. Registros con punt_global = 0 (exámenes sin puntaje válido) se excluyen.
####  A12. (2da revisión, 21-oct) Con el caliper en el logit estu_nse_ies quedó
####       con DME 0,13 tras emparejar. Se agrega chequeo de balance por
####       especificación y ATT con ajuste por regresión sobre la muestra emparejada.
####  A13. (2da revisión) El único estudiante con género "No reporta" sale del
####       modelo lineal inferencial (generaba un coeficiente sin sentido).
####  A14. (21-oct, con la limpieza nueva) diag_escrita_cero: solo diagnóstico,
####       nunca predictor; tabla descriptiva y tabla de error por esa condición.
####       Edad (nueva desde la limpieza) entra como variable individual.
####  A15. En el ML las categóricas faltantes van a "No reporta" (no a la moda).
####  A16. Sensibilidad sin comunicación escrita en 0 (6,7% en 2024 vs 1,7% en
####       2025, más frecuente en estratos bajos): se repiten la brecha y el PSM
####       completo sin ellos (12.3) y se mide si el corrimiento de 2025 se
####       explica por eso (17.2). El análisis principal sigue con el puntaje
####       oficial: excluirlos sería seleccionar por la variable dependiente.
####  A17. (Observación 5 de la tutora) La especificación "previas" incluye la
####       educación de los padres, que es componente del nivel socioeconómico:
####       se renombra como "origen familiar y territorial" y se agrega una
####       especificación mínima sin educación de los padres.
####  Nota (observación 6): inse_cuartil ya no entra al modelo desde A7, así que
####       la fuga leve de sus cortes quedó resuelta; solo se usa en descriptivos
####       y en la equidad.
####  A18. (22-oct) PSM completo con emparejamiento exacto en estu_nse_ies (la
####       DME de 0,13 movía el ATT); Bogotá como referencia de estu_depto_reside
####       en el modelo lineal inferencial.
####  A19. (24-oct, revisión final) nearZeroVar se estaba llevando las banderas
####       inse_imputado y estrato_faltante (3,8% y 3,2% de TRUE), o sea que el
####       modelo nunca las vio. Ahora se protegen del filtro.
####  A20. (24-oct) El PSM completo no contenía a la lectura de origen familiar
####       (le faltaban zona de residencia y tipo de bachillerato). Se agregan
####       para que las cuatro lecturas queden anidadas, de menos a más controles.
####  A21. (24-oct) SHAP por familias: antes se sumaba el |SHAP| de cada dummy y
####       eso inflaba las familias con muchas columnas (justo lo que mide H2).
####       Ahora se suman los SHAP del grupo por estudiante y luego se promedia
####       el valor absoluto. El top de variables individuales no cambia.
####  A22. (24-oct) Se imprime el lambda de Ridge y Lasso (el documento lo cita) y
####       se corrige la columna pct_escrita_cero de la sensibilidad 2025.
####  Ojo: este pipeline necesita los CSV de la Limpieza_saberPro.R del 21-oct.

inicio_total <- Sys.time()

# 1. LIBRERÍAS — CARGA ROBUSTA
paquetes_criticos <- c(
  "tidyverse", "data.table", "caret", "ggplot2",
  "xgboost", "glmnet", "ranger", "MatchIt", "cobalt",
  "broom", "janitor", "e1071", "ineq",
  "effectsize", "naniar", "forcats", "scales", "Matrix")
paquetes_opcionales <- c(
  "skimr", "DataExplorer", "corrplot", "GGally",
  "fastshap", "factoextra", "margins", "plotly",
  "DT", "patchwork", "pROC", "car", "ggrepel", "gridExtra",
  "knitr", "rmarkdown", "DescTools", "rbounds")
paquetes <- unique(c(paquetes_criticos, paquetes_opcionales))
instalar_si_falta <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message("Instalando paquete faltante: ", pkg)
    tryCatch(
      install.packages(pkg, dependencies = TRUE),
      error = function(e) {
        message("No se pudo instalar: ", pkg, " | Motivo: ", e$message)})}}
invisible(lapply(paquetes, instalar_si_falta))
cargar_critico <- function(pkg) {
  ok <- suppressPackageStartupMessages(require(pkg, character.only = TRUE))
  if (!ok) {
    stop(paste0("ERROR CRÍTICO: no se pudo cargar el paquete obligatorio: ", pkg))}}
cargar_opcional <- function(pkg) {
  ok <- suppressPackageStartupMessages(require(pkg, character.only = TRUE))
  if (!ok) {
    message("AVISO: paquete opcional omitido: ", pkg)}}
invisible(lapply(paquetes_criticos, cargar_critico))
invisible(lapply(paquetes_opcionales, cargar_opcional))
options(scipen = 999)
set.seed(123)

mostrar_en_pantalla <- interactive()

tema_base <- ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(size = 11),
    axis.title = ggplot2::element_text(face = "bold"),
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank())
colores_tesis <- c(
  azul = "#1D4E89",
  celeste = "#2E86AB",
  verde = "#2A9D8F",
  naranja = "#F4A261",
  rojo = "#E76F51",
  gris = "#6C757D",
  morado = "#6A4C93")
`%||%` <- function(a, b) {
  if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b}
calcular_theil <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x) & !is.na(x)]
  x <- x[x > 0]
  if (length(x) == 0) return(NA_real_)
  media_x <- mean(x)
  if (!is.finite(media_x) || media_x <= 0) return(NA_real_)
  ratio <- x / media_x
  mean(ratio * log(ratio))
}
calcular_gini <- function(x) {
  tryCatch(
    ineq::Gini(x, na.rm = TRUE),
    error = function(e) NA_real_)}

# 2. RUTAS Y CARGA DE DATOS (la ruta se define en la sección 0)
archivo <- file.path(ruta, "data_limpia_tesis.csv")
salidas <- file.path(ruta, "salidas_tesis")
dir.create(salidas, showWarnings = FALSE, recursive = TRUE)
dirs <- c(
  "01_diagnostico",
  "02_eda",
  "03_inferencia",
  "04_psm",
  "05_modelos",
  "06_shap",
  "07_equidad",
  "08_objetos",
  "09_tablas")
purrr::walk(file.path(salidas, dirs), ~ dir.create(.x, showWarnings = FALSE, recursive = TRUE))


# 2.1 FUNCIONES 
guardar_grafico <- function(plot, nombre, carpeta = "02_eda", width = 9, height = 6, dpi = 300) {
  if (mostrar_en_pantalla) {
    print(plot) }
  ggsave(
    filename = file.path(salidas, carpeta, nombre),
    plot = plot,
    width = width,
    height = height,
    dpi = dpi  )}
graficar_base <- function(expr, archivo, width = 1200, height = 800) {
  expr_sustituida <- substitute(expr)
  if (mostrar_en_pantalla) {
    eval(expr_sustituida, envir = parent.frame())
    grDevices::dev.copy(grDevices::png, filename = archivo, width = width, height = height)
    grDevices::dev.off()  } else {
      grDevices::png(archivo, width = width, height = height)
      eval(expr_sustituida, envir = parent.frame())
      grDevices::dev.off()}}
mostrar_tabla <- function(x, titulo) {
  if (mostrar_en_pantalla) {
    cat("\n----- ", titulo, " -----\n")
    print(x) }}

if (!file.exists(archivo)) {
  stop("ERROR: No se encontró data_limpia_tesis.csv en la ruta indicada: ", archivo)}
na_icfes <- c(
  "", "NA", "N/A", "NULL", "null",
  "Sin dato", "SIN DATO",
  "No informa", "NO INFORMA",
  "No aplica", "NO APLICA",
  "-")
# OJO: el script de limpieza ahora exporta con fwrite en UTF-8, por eso aquí
# se lee en UTF-8 y ya no hace falta el iconv que tenía antes
data_raw <- data.table::fread(
  archivo,
  encoding = "UTF-8",
  na.strings = na_icfes)
data_raw <- data_raw %>%
  as_tibble() %>%
  janitor::clean_names() %>%
  mutate(across(where(is.character), ~ stringr::str_squish(.)))
cat("\n===== DATA CARGADA =====\n")
cat("Filas:", nrow(data_raw), "| Columnas:", ncol(data_raw), "\n")


# 2.2 FILTRO DE REGISTROS INDIVIDUAL / NO PUBLICABLES
# En la base pública estu_estudiante sí trae ESTUDIANTE / INDIVIDUAL, y los
# INDIVIDUAL vienen sin código de institución, así que los dos criterios
# deberían coincidir. La columna de "publicar" no existe en la pública,
# ese criterio queda en cero y no pasa nada.
candidatos_col_individual <- c("estu_estudiante", "estu_tipoestudiante", "estu_tipo_estudiante")
candidatos_col_publicar <- c("publicar", "estu_estadoinvestigacion", "estado_publicacion", "estadoinvestigacion")
candidatos_col_institucion <- c("inst_cod_institucion", "estu_snies_prgmacademico")
col_individual <- intersect(candidatos_col_individual, names(data_raw))
col_publicar <- intersect(candidatos_col_publicar, names(data_raw))
col_institucion <- intersect(candidatos_col_institucion, names(data_raw))
col_individual <- if (length(col_individual) > 0) col_individual[1] else NA_character_
col_publicar <- if (length(col_publicar) > 0) col_publicar[1] else NA_character_
col_institucion <- if (length(col_institucion) > 0) col_institucion[1] else NA_character_

cat("\n===== FILTRO INDIVIDUAL / PUBLICAR =====\n")
cat("Columna usada para 'individual' (texto):", col_individual %||% "NO ENCONTRADA (revisar nombre real)", "\n")
if (!is.na(col_individual)) {
  cat("Valores observados en", col_individual, "(para confirmar si de verdad codifica INDIVIDUAL):\n")
  print(table(toupper(str_squish(as.character(data_raw[[col_individual]]))), useNA = "ifany"))}
cat("Columna usada para 'publicar':", col_publicar %||% "NO ENCONTRADA (revisar nombre real)", "\n")
cat("Columna institucional usada como respaldo de 'individual':", col_institucion %||% "NO ENCONTRADA (revisar nombre real)", "\n")

n_antes_filtro <- nrow(data_raw)
if (!is.na(col_individual) || !is.na(col_publicar) || !is.na(col_institucion)) {
  marca_individual_texto <- if (!is.na(col_individual)) {
    toupper(str_squish(as.character(data_raw[[col_individual]]))) == "INDIVIDUAL"} else {
      rep(FALSE, nrow(data_raw))}
  marca_individual_institucional <- if (!is.na(col_institucion)) {
    is.na(data_raw[[col_institucion]])} else {
      rep(FALSE, nrow(data_raw))}
  marca_no_publicar <- if (!is.na(col_publicar)) {
    toupper(str_squish(as.character(data_raw[[col_publicar]]))) %in% c("N", "NO", "NO PUBLICA", "NO PUBLICAR")
  } else {
    rep(FALSE, nrow(data_raw))  }
  marca_individual_texto[is.na(marca_individual_texto)] <- FALSE
  marca_individual_institucional[is.na(marca_individual_institucional)] <- FALSE
  marca_no_publicar[is.na(marca_no_publicar)] <- FALSE
  marca_individual <- marca_individual_texto | marca_individual_institucional
  marca_excluir <- marca_individual | marca_no_publicar
  
  reporte_filtro_individual <- tibble(
    criterio = c(
      "Registros originales",
      "Marcados como INDIVIDUAL (texto)",
      "Marcados como INDIVIDUAL (sin institución)",
      "Marcados como INDIVIDUAL (texto u sin institución)",
      "Marcados como no publicable",
      "Excluidos (INDIVIDUAL + no publicable)",
      "Registros restantes"),
    valor = c(
      n_antes_filtro,
      sum(marca_individual_texto, na.rm = TRUE),
      sum(marca_individual_institucional, na.rm = TRUE),
      sum(marca_individual, na.rm = TRUE),
      sum(marca_no_publicar, na.rm = TRUE),
      sum(marca_excluir, na.rm = TRUE),
      n_antes_filtro - sum(marca_excluir, na.rm = TRUE)  ) )
  write.csv(
    reporte_filtro_individual,
    file.path(salidas, "01_diagnostico", "filtro_individual_publicar.csv"),
    row.names = FALSE )
  mostrar_tabla(reporte_filtro_individual, "Filtro de registros INDIVIDUAL / no publicable")
  
  data_raw <- data_raw[!marca_excluir, ]
  cat("Filas tras filtro INDIVIDUAL/PUBLICAR:", nrow(data_raw), "\n")} else {
    message("AVISO: no se encontraron columnas de 'individual', 'institucion' ni 'publicar' con los nombres candidatos. ",
            "No se aplicó ningún filtro. Verifica los nombres reales de estas variables en tu base y ",
            "ajusta 'candidatos_col_individual' / 'candidatos_col_institucion' / 'candidatos_col_publicar' en la sección 2.2.")}

# 3. TARGET Y VALIDACIONES INICIALES
target <- "punt_global"
puntaje_maximo_teorico <- 300
if (!(target %in% names(data_raw))) {
  stop("ERROR: No existe punt_global en la base.")}
data_raw[[target]] <- suppressWarnings(as.numeric(data_raw[[target]]))
if (all(is.na(data_raw[[target]]))) {
  stop("ERROR CRÍTICO: punt_global no pudo convertirse a numérico.")}
validacion_inicial <- tibble(
  criterio = c(
    "Filas originales (tras filtro INDIVIDUAL/PUBLICAR)",
    "Columnas originales",
    "Registros con punt_global no faltante",
    "Porcentaje con punt_global no faltante",
    "Puntaje mínimo observado",
    "Puntaje máximo observado" ),
  valor = c(
    nrow(data_raw),
    ncol(data_raw),
    sum(!is.na(data_raw[[target]])),
    round(mean(!is.na(data_raw[[target]])) * 100, 2),
    min(data_raw[[target]], na.rm = TRUE),
    max(data_raw[[target]], na.rm = TRUE)))
write.csv(
  validacion_inicial,
  file.path(salidas, "01_diagnostico", "validacion_inicial.csv"),
  row.names = FALSE)
mostrar_tabla(validacion_inicial, "Validación inicial")

# 3.1 AJUSTE oct-2026 (A11): puntajes globales en cero
# Ojo: en 2024 salen 14 estudiantes con punt_global = 0. Un cero en el global
# implica cero en los cinco módulos, eso no es un desempeño sino un examen sin
# puntaje válido (anulado o no presentado). Se dejan por fuera y se reporta
# cuántos. Si el jurado pide lo contrario, basta con poner FALSE aquí.
excluir_puntaje_cero <- TRUE
n_puntaje_cero <- sum(data_raw[[target]] == 0, na.rm = TRUE)
cat("\n===== REGISTROS CON PUNTAJE GLOBAL = 0 =====\n")
cat("Registros con punt_global = 0:", n_puntaje_cero,
    if (excluir_puntaje_cero) "-> se excluyen\n" else "-> se conservan\n")
if (excluir_puntaje_cero && n_puntaje_cero > 0) {
  data_raw <- data_raw %>% filter(is.na(.data[[target]]) | .data[[target]] > 0)
  cat("Filas tras excluir puntajes en cero:", nrow(data_raw), "\n")}

# 4. DIAGNÓSTICO DE CALIDAD
diagnostico_columnas <- tibble(
  variable = names(data_raw),
  tipo = map_chr(data_raw, ~ class(.x)[1]),
  n = nrow(data_raw),
  n_missing = map_int(data_raw, ~ sum(is.na(.x))),
  pct_missing = n_missing / n,
  n_unicos = map_int(data_raw, ~ n_distinct(.x, na.rm = TRUE)),
  ejemplo_1 = map_chr(data_raw, ~ as.character(na.omit(.x)[1] %||% NA)),
  ejemplo_2 = map_chr(data_raw, ~ as.character(na.omit(.x)[2] %||% NA))) %>%
  arrange(desc(pct_missing), desc(n_unicos))
variables_vacias <- diagnostico_columnas %>%
  filter(n_unicos == 0 | pct_missing == 1) %>%
  pull(variable)
variables_constantes <- diagnostico_columnas %>%
  filter(n_unicos <= 1) %>%
  pull(variable)
write.csv(
  diagnostico_columnas,
  file.path(salidas, "01_diagnostico", "diagnostico_columnas.csv"),
  row.names = FALSE)
saveRDS(
  diagnostico_columnas,
  file.path(salidas, "08_objetos", "diagnostico_columnas.rds"))
tabla_faltantes_completa <- diagnostico_columnas %>%
  select(variable, tipo, n_missing, pct_missing, n_unicos)
write.csv(
  tabla_faltantes_completa,
  file.path(salidas, "01_diagnostico", "tabla_faltantes_completa.csv"),
  row.names = FALSE)
mostrar_tabla(head(diagnostico_columnas, 20), "Diagnóstico de columnas (primeras 20 filas)")

set.seed(123)
n_miss_plot <- min(10000, nrow(data_raw))
data_miss_plot <- data_raw %>%
  slice_sample(n = n_miss_plot)
graf_missing <- naniar::vis_miss(data_miss_plot, warn_large_data = FALSE) +
  labs(
    title = "Mapa de datos faltantes",
    subtitle = paste0("Muestra reproducible de ", nrow(data_miss_plot), " registros"))
guardar_grafico(
  graf_missing,
  "missing_data_muestra_10000.png",
  carpeta = "01_diagnostico",
  width = 16,
  height = 9,
  dpi = 100)
top_faltantes <- tabla_faltantes_completa %>%
  filter(n_missing > 0) %>%
  slice_max(pct_missing, n = 30)
if (nrow(top_faltantes) > 0) {
  graf_top_faltantes <- top_faltantes %>%
    mutate(variable = fct_reorder(variable, pct_missing)) %>%
    ggplot(aes(x = variable, y = pct_missing)) +
    geom_col(fill = colores_tesis["rojo"], alpha = 0.85) +
    coord_flip() +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    labs(
      title = "Top 30 variables con mayor proporción de datos faltantes",
      subtitle = "Cálculo sobre la base completa",
      x = "Variable",
      y = "Porcentaje de datos faltantes" ) +
    tema_base
  guardar_grafico(
    graf_top_faltantes,
    "top_30_variables_faltantes.png",
    carpeta = "01_diagnostico",
    width = 10,
    height = 7 )}
if ("skimr" %in% loadedNamespaces()) {
  set.seed(123)
  n_skim <- min(50000, nrow(data_raw))
  data_skim <- data_raw %>%
    slice_sample(n = n_skim)
  skim_base_muestra <- skimr::skim(data_skim)
  mostrar_tabla(skim_base_muestra, "Resumen skimr sobre muestra de 50.000 registros")
  saveRDS(
    skim_base_muestra,
    file.path(salidas, "08_objetos", "skim_base_muestra_50000.rds"))}

# 5. CURADURÍA DE VARIABLES
# Nota 21-oct: desde Limpieza_saberPro.R (L3) la etnia ya llega excluida, así
# que este bloque normalmente no hace nada; se deja como seguro por si se
# corre con un CSV viejo.
# AJUSTE oct-2026 (A4): estu_tieneetnia. Pilas con esta: solo trae "S" y el
# resto (85,3% en la base pública) es NA. Casi seguro el NA significa "no", pero no se puede
# distinguir de "no respondió". Si se imputara con la moda TODOS quedarían
# marcados como pertenecientes a una etnia. Antes se caía sola en el filtro de
# n_distinct de abajo; ahora se saca a propósito y queda en el log.
if ("estu_tieneetnia" %in% names(data_raw)) {
  cat("\n===== EXCLUSIÓN EXPLÍCITA: estu_tieneetnia =====\n")
  cat("Valores observados:", paste(unique(na.omit(data_raw$estu_tieneetnia)), collapse = ", "),
      "| % NA:", round(100 * mean(is.na(data_raw$estu_tieneetnia)), 1),
      "| se excluye: un solo valor observado y el NA no es interpretable\n")
  data_raw <- data_raw %>% select(-estu_tieneetnia)}
data <- data_raw %>%
  select(-any_of(variables_vacias)) %>%
  select(where(~ sum(!is.na(.)) > 0)) %>%
  select(where(~ n_distinct(.x, na.rm = TRUE) > 1)) %>%
  as_tibble()
vars_admin <- c(
  "inst_cod_institucion",
  "estu_snies_prgmacademico",
  "estu_prgm_codmunicipio",
  "estu_inst_codmunicipio",
  "estu_cod_mcpio_presentacion",
  "estu_cod_depto_presentacion",
  "estu_tipodocumento",
  "estu_estadoinvestigacion",
  "periodo",
  "estu_consecutivo",
  "estu_cod_reside_mcpio",
  "estu_cod_reside_depto",
  "estu_prgm_coddepartamento",
  "estu_inst_coddepartamento",
  # AJUSTE oct-2026 (A14): bandera que viene de Limpieza_saberPro.R (L2). Sale
  # del examen (comunicación escrita en 0), así que NUNCA puede ser predictor;
  # solo se usa para diagnosticar el error del modelo (sección 17).
  "diag_escrita_cero")
vars_discapacidad <- names(data)[str_detect(names(data), "disc")]
# AJUSTE oct-2026 (A7): estu_privado_libertad va por la misma razón ética que
# discapacidad: sirve para describir, no para predecir sobre personas.
vars_sensibles_modelo <- intersect(c(vars_discapacidad, "estu_privado_libertad"), names(data))
vars_sensibles_equidad <- intersect(c("estu_genero", vars_discapacidad), names(data))
vars_inse <- intersect(
  c("estu_inse_individual", "estu_nse_individual", "estu_nse_ies"),
  names(data))
cat("\n===== VARIABLES INSE DETECTADAS =====\n")
print(vars_inse)
write.csv(
  tibble(variable_inse_detectada = vars_inse),
  file.path(salidas, "01_diagnostico", "variables_inse_detectadas.csv"),
  row.names = FALSE)

# 6. VARIABLES DERIVADAS
# Todo esto se metió en una función para poder aplicarle exactamente lo mismo
# a la base 2025 en la validación fuera del tiempo (sección 17.1).
# OJO con qs_inse: los cortes de cuartil del INSE se aprenden con 2024 y a 2025
# se le pasan esos mismos cortes, si no los cuartiles no serían comparables.
# AJUSTE oct-2026: inse_cuartil ya NO entra al modelo (se calculaba con la base
# completa antes de partir y además repetía la información de
# estu_inse_individual). Queda solo para descriptivos y para la equidad.
normalizar_si_no <- function(x) {
  x <- toupper(str_squish(as.character(x)))
  case_when(
    x %in% c("SI", "SÍ", "1", "TRUE", "VERDADERO") ~ "Sí",
    x %in% c("NO", "0", "FALSE", "FALSO") ~ "No",
    TRUE ~ NA_character_  )}
vars_tecnologia_base <- c(
  "fami_tieneinternet",   "fami_tienecomputador",
  "fami_tieneserviciotv",  "fami_tienelavadora",
  "fami_tieneautomovil",  "fami_tienemotocicleta",
  "fami_tieneconsolavideojuegos",  "fami_tienehornomicroogas")

crear_derivadas <- function(df, qs_inse = NULL, verbose = TRUE) {
  if ("estu_genero" %in% names(df)) {
    df <- df %>%
      mutate(
        estu_genero = toupper(trimws(as.character(estu_genero))),
        estu_genero = case_when(
          estu_genero %in% c("M", "MASCULINO", "HOMBRE") ~ "M",
          estu_genero %in% c("F", "FEMENINO", "MUJER") ~ "F",
          TRUE ~ NA_character_))}
  if ("fami_estratovivienda" %in% names(df)) {
    df <- df %>%
      mutate(
        fami_estratovivienda_original = as.character(fami_estratovivienda),
        estrato_num = as.numeric(str_extract(as.character(fami_estratovivienda), "[0-9]+")),
        estrato_num = ifelse(estrato_num %in% 1:6, estrato_num, NA_real_),
        estrato_grupo_psm = case_when(
          !is.na(estrato_num) & estrato_num <= 2 ~ "Estratos 1 y 2",
          !is.na(estrato_num) & estrato_num > 2 ~ "Estratos superiores a 2",
          TRUE ~ NA_character_
        ),
        tratamiento = case_when(
          !is.na(estrato_num) & estrato_num <= 2 ~ 0,
          !is.na(estrato_num) & estrato_num > 2 ~ 1,
          TRUE ~ NA_real_),
        # AJUSTE oct-2026 (A7): bandera de estrato faltante, igual que se hizo
        # con el INSE. En el ML estrato_num se imputa con la mediana del train,
        # así el modelo puede distinguir "estrato 2 de verdad" de "sin dato".
        # Incluye blancos y "Sin Estrato".
        estrato_faltante = is.na(estrato_num))}
  if ("estu_inse_individual" %in% names(df)) {
    df <- df %>%
      mutate(estu_inse_individual = suppressWarnings(as.numeric(estu_inse_individual))) %>%
      mutate(inse_imputado = is.na(estu_inse_individual))
    if (verbose) {
      cat("\n===== DIAGNÓSTICO INSE =====\n")
      cat("Registros con INSE faltante (se imputarán con la mediana):",
          sum(df$inse_imputado), "de", nrow(df),
          sprintf("(%.1f%%)\n", 100 * mean(df$inse_imputado)))}
    if (is.null(qs_inse) && sum(!is.na(df$estu_inse_individual)) > 0) {
      qs_inse <- quantile(
        df$estu_inse_individual,
        probs = c(.25, .50, .75),
        na.rm = TRUE )}
    if (!is.null(qs_inse)) {
      df <- df %>%
        mutate(
          inse_cuartil = case_when(
            is.na(estu_inse_individual) ~ "Sin dato (INSE imputado)",
            estu_inse_individual <= qs_inse[1] ~ "Q1 INSE más bajo",
            estu_inse_individual <= qs_inse[2] ~ "Q2",
            estu_inse_individual <= qs_inse[3] ~ "Q3",
            estu_inse_individual > qs_inse[3] ~ "Q4 INSE más alto"  ),
          inse_cuartil = factor(
            inse_cuartil,
            levels = c("Q1 INSE más bajo", "Q2", "Q3", "Q4 INSE más alto", "Sin dato (INSE imputado)")   )   ) }}
  vars_tec <- intersect(vars_tecnologia_base, names(df))
  if (length(vars_tec) > 0) {
    df <- df %>% mutate(across(all_of(vars_tec), normalizar_si_no))}
  attr(df, "qs_inse") <- qs_inse
  df}

data <- crear_derivadas(data)
qs_inse <- attr(data, "qs_inse")
vars_tecnologia <- intersect(vars_tecnologia_base, names(data))

# 7. FUNCIONES AUXILIARES
aprender_imputacion <- function(df) {
  df <- as.data.frame(df)
  map(df, function(x) {
    if (is.numeric(x)) {
      med <- median(x, na.rm = TRUE)
      ifelse(is.finite(med), med, 0)
    } else {
      x_chr <- as.character(x)
      tab <- sort(table(x_chr), decreasing = TRUE)
      if (length(tab) == 0) return("Sin información")
      names(tab)[1] }  })}

# Pilas con esto: antes la winsorización del test se hacía con los percentiles
# del propio test. No es fuga del target, pero sí rompe la regla de que todo
# parámetro sale del train. Ahora los límites P1-P99 se aprenden en el train y
# se le pasan al test y a 2025 (argumento limites). Para la EDA no se pasa nada
# y funciona igual que antes.
aprender_limites <- function(df, excluir = character(0)) {
  df <- as.data.frame(df)
  vars_num <- setdiff(names(df)[sapply(df, is.numeric)], excluir)
  map(set_names(vars_num), ~ quantile(df[[.x]], probs = c(.01, .99), na.rm = TRUE))}

aplicar_imputacion <- function(df, reglas, winsorizar = TRUE, excluir = character(0), limites = NULL) {
  df <- as.data.frame(df)
  for (v in names(df)) {
    if (v %in% excluir) next
    if (is.numeric(df[[v]])) {
      if (winsorizar) {
        qnt <- if (!is.null(limites[[v]])) limites[[v]] else quantile(df[[v]], probs = c(.01, .99), na.rm = TRUE)
        if (all(is.finite(qnt))) {
          df[[v]][df[[v]] < qnt[1]] <- qnt[1]
          df[[v]][df[[v]] > qnt[2]] <- qnt[2]     }  }
      df[[v]][is.na(df[[v]])] <- reglas[[v]]
    } else {
      df[[v]] <- as.character(df[[v]])
      df[[v]][is.na(df[[v]]) | df[[v]] == ""] <- reglas[[v]]  }}
  as_tibble(df)}
resumen_categorica_vs_target <- function(df, var, target) {
  df <- as_tibble(df)
  df %>%
    filter(!is.na(.data[[var]]), !is.na(.data[[target]])) %>%
    group_by(.data[[var]]) %>%
    summarise(
      n = n(),
      pct = n / nrow(df),
      media = mean(.data[[target]], na.rm = TRUE),
      mediana = median(.data[[target]], na.rm = TRUE),
      sd = sd(.data[[target]], na.rm = TRUE),
      p25 = quantile(.data[[target]], 0.25, na.rm = TRUE),
      p75 = quantile(.data[[target]], 0.75, na.rm = TRUE),
      gini = calcular_gini(.data[[target]]),
      .groups = "drop"
    ) %>%
    arrange(desc(media))}

# 8. BASE PARA EDA
reglas_imputacion_general <- aprender_imputacion(data)

vars_colapsadas_sin_info <- names(reglas_imputacion_general)[
  map_lgl(reglas_imputacion_general, ~ isTRUE(identical(.x, "Sin información")))]
if (length(vars_colapsadas_sin_info) > 0) {
  cat("\n===== AVISO: variables cuya moda aprendida es 'Sin información' =====\n")
  cat("Esto implica que la columna llega 100% NA a este punto del pipeline.\n")
  print(vars_colapsadas_sin_info)
  for (vv in vars_colapsadas_sin_info) {
    cat("\n-- Tabla real de", vv, "en `data` (antes de imputar) --\n")
    print(table(data[[vv]], useNA = "always"))
  }
} else {
  cat("\n===== OK: ninguna variable categórica colapsó a 'Sin información' =====\n")}

if ("estu_genero" %in% names(data)) {
  cat("\n-- Chequeo puntual: tabla de estu_genero en `data` --\n")
  print(table(data$estu_genero, useNA = "always"))
}
for (vv_tec in vars_tecnologia) {
  cat("\n-- Chequeo puntual: tabla de", vv_tec, "en `data` --\n")
  print(table(data[[vv_tec]], useNA = "always"))}

qnt_target_check <- quantile(data[[target]], probs = c(.01, .99), na.rm = TRUE)
n_extremos_target <- sum(
  data[[target]] < qnt_target_check[1] | data[[target]] > qnt_target_check[2],
  na.rm = TRUE)
cat("\n===== DIAGNÓSTICO WINSORIZACIÓN DEL TARGET (NO SE APLICA) =====\n")
cat("Rango P1-P99 de", target, ":", round(qnt_target_check[1], 1), "-", round(qnt_target_check[2], 1), "\n")
cat("Registros fuera de ese rango que se preservan sin recortar:",
    n_extremos_target, sprintf("(%.2f%%)\n", 100 * n_extremos_target / nrow(data)))
data_eda <- data %>%
  as_tibble() %>%
  filter(!is.na(.data[[target]]))

# AJUSTE oct-2026 (A1, observación de la tutora): antes esta línea imputaba
# TODAS las columnas menos el target, y eso deshacía los NA que se ponen a
# propósito en crear_derivadas(): a estrato_num le ponía la mediana (2), a
# estrato_grupo_psm la moda ("Estratos 1 y 2") y a tratamiento el 0. Resultado:
# los estudiantes sin estrato terminaban como estrato 2 y como CONTROLES del PSM,
# inflando la brecha cruda y entrando al ANOVA, al eta² y a los emparejamientos.
# Con la base pública 2024 son 8.724 (7.517 en blanco + 1.207 "Sin Estrato",
# media 139,44); con la base anterior eran 8.735 y la brecha pasaba de 12,58 a 12,68.
# Regla que queda: toda variable que decide quién entra en qué grupo o
# tratamiento queda FUERA de cualquier imputación.
vars_diseno <- c(
  "estrato_num", "estrato_grupo_psm", "tratamiento", "estrato_faltante",
  "fami_estratovivienda", "fami_estratovivienda_original",
  "inse_imputado", "inse_cuartil")
vars_diseno <- intersect(vars_diseno, names(data_eda))

# AJUSTE oct-2026 (A2): en la EDA los faltantes de las categóricas quedan como
# "No reporta" en vez de la moda. Con la moda, los ~5.600 sin dato de internet
# o computador quedaban contados como "Sí" en los descriptivos. Para el PSM
# esto es el enfoque de indicador de faltante (categoría propia), que es más
# defendible que inventar el valor. Las numéricas siguen con la mediana.
reglas_imputacion_eda <- purrr::imap(reglas_imputacion_general, function(regla, v) {
  if (is.numeric(data_eda[[v]])) regla else "No reporta"})

# AJUSTE oct-2026 (A3): los códigos administrativos (departamento, municipio,
# institución...) son numéricos, así que la winsorización P1-P99 los estaba
# recortando: el código de San Andrés (88) o Vichada (99) quedaba convertido
# en el de otro departamento. Eso dañaba depto_reside_cod en el PSM de previas.
# Un código no se winsoriza, se deja tal cual.
vars_no_tocar_eda <- unique(c(target, vars_diseno, intersect(vars_admin, names(data_eda))))
data_eda <- aplicar_imputacion(data_eda, reglas_imputacion_eda, excluir = vars_no_tocar_eda) %>%
  as_tibble() %>%
  mutate(
    # para descriptivos: los sin estrato como categoría propia (es informativa)
    estrato_desc = if_else(is.na(estrato_num), "No reporta estrato", paste("Estrato", estrato_num)))

# Chequeo de que el arreglo sí quedó: estos NA tienen que seguir ahí
cat("\n===== DATA PARA EDA =====\n")
cat("Filas:", nrow(data_eda), "| Columnas:", ncol(data_eda), "\n")
cat("Estudiantes sin estrato reportado (siguen como NA, no se imputan):",
    sum(is.na(data_eda$estrato_num)), "\n")
cat("  - de ellos en blanco:", sum(is.na(data_eda$fami_estratovivienda)),
    "| marcados 'Sin Estrato':", sum(!is.na(data_eda$fami_estratovivienda) & is.na(data_eda$estrato_num)), "\n")
cat("  - media de punt_global en ese grupo:",
    round(mean(data_eda[[target]][is.na(data_eda$estrato_num)]), 2), "\n")
if (!all(is.na(data_eda$tratamiento) == is.na(data_eda$estrato_num))) {
  stop("ERROR: tratamiento y estrato_num no tienen los mismos NA, revisar sección 8.")}
saveRDS(data_eda, file.path(salidas, "08_objetos", "data_eda.rds"))

# 9. EDA PROFESIONAL
cat("\n===== EDA PROFESIONAL =====\n")
resumen_global <- data_eda %>%
  summarise(
    n = n(),
    columnas = ncol(data_eda),
    media = mean(.data[[target]], na.rm = TRUE),
    mediana = median(.data[[target]], na.rm = TRUE),
    desviacion = sd(.data[[target]], na.rm = TRUE),
    minimo = min(.data[[target]], na.rm = TRUE),
    p01 = quantile(.data[[target]], 0.01, na.rm = TRUE),
    p05 = quantile(.data[[target]], 0.05, na.rm = TRUE),
    p25 = quantile(.data[[target]], 0.25, na.rm = TRUE),
    p75 = quantile(.data[[target]], 0.75, na.rm = TRUE),
    p90 = quantile(.data[[target]], 0.90, na.rm = TRUE),
    p95 = quantile(.data[[target]], 0.95, na.rm = TRUE),
    p99 = quantile(.data[[target]], 0.99, na.rm = TRUE),
    maximo = max(.data[[target]], na.rm = TRUE),
    asimetria = e1071::skewness(.data[[target]], na.rm = TRUE),
    curtosis = e1071::kurtosis(.data[[target]], na.rm = TRUE),
    gini = calcular_gini(.data[[target]]),
    theil = calcular_theil(.data[[target]]),
    promedio_sobre_max_teorico = media / puntaje_maximo_teorico )
write.csv(resumen_global, file.path(salidas, "09_tablas", "resumen_global.csv"), row.names = FALSE)
saveRDS(resumen_global, file.path(salidas, "08_objetos", "resumen_global.rds"))
mostrar_tabla(resumen_global, "Resumen global del puntaje")
puntaje_minimo <- min(data_eda$punt_global, na.rm = TRUE)
puntaje_maximo <- max(data_eda$punt_global, na.rm = TRUE)
registro_minimo <- data_eda %>% filter(punt_global == puntaje_minimo) %>% slice(1)
registro_maximo <- data_eda %>% filter(punt_global == puntaje_maximo) %>% slice(1)
escala_puntaje <- tibble(
  minimo_observado = puntaje_minimo,
  genero_minimo = if ("estu_genero" %in% names(data_eda)) registro_minimo$estu_genero else NA_character_,
  estrato_minimo = if ("fami_estratovivienda" %in% names(data_eda)) registro_minimo$fami_estratovivienda else NA_character_,
  n_minimo_observado = data_eda %>% filter(punt_global == puntaje_minimo) %>% nrow(),
  p25 = as.numeric(quantile(data_eda$punt_global, 0.25, na.rm = TRUE)),
  mediana = median(data_eda$punt_global, na.rm = TRUE),
  p75 = as.numeric(quantile(data_eda$punt_global, 0.75, na.rm = TRUE)),
  p90 = as.numeric(quantile(data_eda$punt_global, 0.90, na.rm = TRUE)),
  p95 = as.numeric(quantile(data_eda$punt_global, 0.95, na.rm = TRUE)),
  maximo_observado = puntaje_maximo,
  genero_maximo = if ("estu_genero" %in% names(data_eda)) registro_maximo$estu_genero else NA_character_,
  estrato_maximo = if ("fami_estratovivienda" %in% names(data_eda)) registro_maximo$fami_estratovivienda else NA_character_,
  n_maximo_observado = data_eda %>% filter(punt_global == puntaje_maximo) %>% nrow(),
  maximo_teorico = puntaje_maximo_teorico,
  promedio = mean(data_eda$punt_global, na.rm = TRUE),
  promedio_sobre_max_observado = promedio / maximo_observado,
  promedio_sobre_max_teorico = promedio / maximo_teorico,
  minimo_sobre_max_teorico = minimo_observado / maximo_teorico,
  maximo_observado_sobre_max_teorico = maximo_observado / maximo_teorico)
write.csv(escala_puntaje, file.path(salidas, "09_tablas", "escala_puntaje.csv"), row.names = FALSE)
saveRDS(escala_puntaje, file.path(salidas, "08_objetos", "escala_puntaje.rds"))
mostrar_tabla(escala_puntaje, "Escala del puntaje global")
graf_dist_puntaje <- ggplot(data_eda, aes(x = .data[[target]])) +
  geom_histogram(aes(y = after_stat(density)), bins = 45, fill = colores_tesis["celeste"], color = "white", alpha = 0.85) +
  geom_density(color = colores_tesis["rojo"], linewidth = 1.1) +
  geom_vline(xintercept = resumen_global$media, color = colores_tesis["rojo"], linewidth = 1) +
  geom_vline(xintercept = resumen_global$mediana, color = colores_tesis["azul"], linewidth = 1, linetype = "dashed") +
  labs(
    title = "Distribución del puntaje global Saber Pro 2024",
    subtitle = "Histograma con densidad, media y mediana",
    x = "Puntaje global",
    y = "Densidad") +
  tema_base
guardar_grafico(graf_dist_puntaje, "01_distribucion_puntaje_global.png")
graf_box_puntaje <- ggplot(data_eda, aes(y = .data[[target]])) +
  geom_boxplot(fill = colores_tesis["naranja"], alpha = 0.75, outlier.alpha = 0.08) +
  labs(
    title = "Dispersión general del puntaje global",
    x = "",
    y = "Puntaje global" ) +
  tema_base
guardar_grafico(graf_box_puntaje, "02_boxplot_puntaje_global.png", width = 5, height = 6)
# Estrato
if ("estrato_num" %in% names(data_eda)) {
  tabla_estrato <- resumen_categorica_vs_target(data_eda, "estrato_num", target)
  write.csv(tabla_estrato, file.path(salidas, "09_tablas", "eda_puntaje_por_estrato.csv"), row.names = FALSE)
  mostrar_tabla(tabla_estrato, "Puntaje por estrato (solo estudiantes con estrato reportado)")
  # AJUSTE oct-2026: tabla para el documento, con los sin estrato como fila
  # propia. Ojo: el pct de esta tabla sí suma 100% sobre toda la base.
  tabla_estrato_desc <- resumen_categorica_vs_target(data_eda, "estrato_desc", target)
  write.csv(tabla_estrato_desc, file.path(salidas, "09_tablas", "eda_puntaje_por_estrato_con_no_reporta.csv"), row.names = FALSE)
  mostrar_tabla(tabla_estrato_desc, "Puntaje por estrato, incluyendo 'No reporta estrato'")
  graf_box_estrato <- data_eda %>%
    filter(!is.na(estrato_num)) %>%
    ggplot(aes(x = factor(estrato_num), y = .data[[target]])) +
    geom_boxplot(fill = colores_tesis["celeste"], alpha = 0.8, outlier.alpha = 0.06) +
    stat_summary(fun = mean, geom = "point", color = colores_tesis["rojo"], size = 2.4) +
    labs(
      title = "Distribución del puntaje global por estrato socioeconómico",
      subtitle = "El punto rojo representa la media",
      x = "Estrato socioeconómico",
      y = "Puntaje global" ) +
    tema_base
  guardar_grafico(graf_box_estrato, "03_boxplot_puntaje_por_estrato.png")
  graf_media_estrato <- tabla_estrato %>%
    mutate(estrato_num = factor(estrato_num)) %>%
    ggplot(aes(x = estrato_num, y = media, group = 1)) +
    geom_line(color = colores_tesis["azul"], linewidth = 1) +
    geom_point(color = colores_tesis["rojo"], size = 3) +
    geom_errorbar(aes(ymin = media - 1.96 * sd / sqrt(n), ymax = media + 1.96 * sd / sqrt(n)), width = .15) +
    labs(
      title = "Promedio del puntaje global por estrato",
      subtitle = "Media con intervalo aproximado del 95%",
      x = "Estrato",
      y = "Puntaje promedio" ) +
    tema_base
  guardar_grafico(graf_media_estrato, "04_media_puntaje_por_estrato.png")}
# Género
if ("estu_genero" %in% names(data_eda)) {
  tabla_genero <- resumen_categorica_vs_target(data_eda, "estu_genero", target)
  write.csv(tabla_genero, file.path(salidas, "09_tablas", "eda_puntaje_por_genero.csv"), row.names = FALSE)
  mostrar_tabla(tabla_genero, "Puntaje por género")
  graf_genero <- data_eda %>%
    filter(estu_genero %in% c("M", "F")) %>%
    ggplot(aes(x = estu_genero, y = .data[[target]], fill = estu_genero)) +
    geom_violin(alpha = 0.45, trim = TRUE) +
    geom_boxplot(width = 0.15, alpha = 0.85, outlier.alpha = 0.05) +
    scale_fill_manual(values = c("F" = unname(colores_tesis["morado"]), "M" = unname(colores_tesis["verde"]))) +
    labs(
      title = "Distribución del puntaje global por género",
      subtitle = "Violin plot y boxplot",
      x = "Género",
      y = "Puntaje global" ) +
    tema_base +
    guides(fill = "none")
  guardar_grafico(graf_genero, "05_violin_puntaje_por_genero.png")}
# INSE
if ("estu_inse_individual" %in% names(data_eda)) {
  set.seed(123)
  data_inse_plot <- data_eda %>%
    filter(!is.na(estu_inse_individual), !is.na(.data[[target]]))
  n_inse_plot <- min(30000, nrow(data_inse_plot))
  if (n_inse_plot > 10) {
    muestra_inse <- data_inse_plot %>%
      slice_sample(n = n_inse_plot)
    graf_inse_puntaje <- muestra_inse %>%
      ggplot(aes(x = estu_inse_individual, y = .data[[target]])) +
      geom_point(alpha = 0.18, color = colores_tesis["azul"]) +
      geom_smooth(method = "loess", color = colores_tesis["rojo"], linewidth = 1.1, se = TRUE) +
      labs(
        title = "Relación entre INSE oficial del ICFES y puntaje global",
        subtitle = "Muestra reproducible para visualización",
        x = "INSE individual oficial",
        y = "Puntaje global" ) +
      tema_base
    guardar_grafico(graf_inse_puntaje, "06_inse_vs_puntaje.png")}
  if ("inse_cuartil" %in% names(data_eda)) {
    tabla_inse_cuartil <- resumen_categorica_vs_target(data_eda, "inse_cuartil", target)
    write.csv(
      tabla_inse_cuartil,
      file.path(salidas, "09_tablas", "eda_puntaje_por_cuartil_inse.csv"),
      row.names = FALSE)
    mostrar_tabla(tabla_inse_cuartil, "Puntaje por cuartil de INSE")
    graf_inse_cuartil <- data_eda %>%
      filter(!is.na(inse_cuartil)) %>%
      ggplot(aes(x = inse_cuartil, y = .data[[target]], fill = inse_cuartil)) +
      geom_boxplot(alpha = .85, outlier.alpha = .05) +
      scale_fill_brewer(palette = "Blues") +
      labs(
        title = "Puntaje global por cuartiles del INSE oficial",
        x = "Cuartil de INSE",
        y = "Puntaje global" ) +
      tema_base +
      guides(fill = "none")
    guardar_grafico(graf_inse_cuartil, "07_puntaje_por_cuartil_inse.png") }
  if ("inse_imputado" %in% names(data_eda)) {
    tabla_inse_imputado <- resumen_categorica_vs_target(data_eda, "inse_imputado", target)
    write.csv(
      tabla_inse_imputado,
      file.path(salidas, "09_tablas", "eda_puntaje_por_inse_imputado.csv"),
      row.names = FALSE )
    mostrar_tabla(tabla_inse_imputado, "Puntaje según si el INSE fue imputado")  }}
# Tecnología
for (v in vars_tecnologia) {
  if (v %in% names(data_eda)) {
    # AJUSTE oct-2026 (A2): ahora sale también la fila "No reporta"; las
    # medias de "Sí" y "No" ya no incluyen imputados.
    tabla_v <- resumen_categorica_vs_target(data_eda, v, target)
    write.csv(tabla_v, file.path(salidas, "09_tablas", paste0("eda_", v, ".csv")), row.names = FALSE)
    if (v %in% c("fami_tieneinternet", "fami_tienecomputador")) {
      mostrar_tabla(tabla_v, paste("Puntaje según", v, "(sin imputar)"))}
    graf_v <- data_eda %>%
      filter(!is.na(.data[[v]])) %>%
      ggplot(aes(x = .data[[v]], y = .data[[target]], fill = .data[[v]])) +
      geom_boxplot(alpha = .8, outlier.alpha = .05) +
      scale_fill_manual(values = c("Sí" = unname(colores_tesis["verde"]), "No" = unname(colores_tesis["rojo"]),
                                   "No reporta" = unname(colores_tesis["gris"]))) +
      labs(
        title = paste("Puntaje global según", v),
        x = v,
        y = "Puntaje global" ) +
      tema_base +
      guides(fill = "none")
    guardar_grafico(graf_v, paste0("tecnologia_", v, ".png")) }}
# Rankings por variables clave
vars_clave <- c(
  "estu_genero",
  "fami_estratovivienda",
  "estrato_num",
  "estrato_grupo_psm",
  "estu_depto_reside",
  "estu_prgm_departamento",
  "estu_depto_presentacion",
  "inst_origen",
  "inst_caracter_academico",
  "estu_metodo_prgm",
  "estu_nucleo_pregrado",   # reemplaza a gruporeferencia, que la base pública no trae
  "fami_tieneinternet",
  "fami_tienecomputador",
  "estu_nse_individual",
  "estu_nse_ies",
  "inse_cuartil",
  "inse_imputado")
vars_clave <- intersect(vars_clave, names(data_eda))
resumen_grupos <- list()
for (v in vars_clave) {
  resumen_grupos[[v]] <- resumen_categorica_vs_target(data_eda, v, target)
  write.csv(
    resumen_grupos[[v]],
    file.path(salidas, "09_tablas", paste0("resumen_grupos_", v, ".csv")),
    row.names = FALSE)
  top_v <- resumen_grupos[[v]] %>%
    arrange(desc(n)) %>%
    slice_head(n = 15) %>%
    mutate(cat = fct_reorder(as.factor(.data[[v]]), media))
  if (nrow(top_v) > 0) {
    graf_top <- top_v %>%
      ggplot(aes(x = cat, y = media, fill = media)) +
      geom_col(alpha = .9) +
      coord_flip() +
      scale_fill_gradient(low = colores_tesis["celeste"], high = colores_tesis["rojo"]) +
      labs(
        title = paste("Puntaje promedio por", v),
        subtitle = "Top 15 categorías con mayor número de registros",
        x = v,
        y = "Puntaje promedio" ) +
      tema_base +
      guides(fill = "none")
    guardar_grafico(graf_top, paste0("ranking_media_", v, ".png"), width = 10, height = 6) }}
saveRDS(resumen_grupos, file.path(salidas, "08_objetos", "resumen_grupos.rds"))

# AJUSTE oct-2026 (A10): composición institucional por grupo de estrato.
# En el documento se afirmaba que los estratos 1 y 2 se concentran en
# instituciones oficiales y programas presenciales; lo de oficiales lo
# respalda el balance del PSM, lo de presenciales NO (sale al revés). Esta
# tabla deja el dato directo para no afirmar nada que no esté calculado.
if (all(c("estrato_desc", "inst_origen", "estu_metodo_prgm", "inst_caracter_academico") %in% names(data_eda))) {
  composicion_grupo <- data_eda %>%
    mutate(grupo = case_when(
      is.na(estrato_num) ~ "No reporta estrato",
      estrato_num <= 2 ~ "Estratos 1 y 2",
      TRUE ~ "Estratos superiores a 2")) %>%
    group_by(grupo) %>%
    summarise(
      n = n(),
      pct_oficial = mean(str_detect(inst_origen, "^OFICIAL")),
      pct_presencial = mean(estu_metodo_prgm == "PRESENCIAL"),
      pct_universidad = mean(inst_caracter_academico == "UNIVERSIDAD"),
      media_puntaje = mean(.data[[target]]),
      .groups = "drop")
  write.csv(composicion_grupo, file.path(salidas, "09_tablas", "composicion_institucional_por_grupo_estrato.csv"), row.names = FALSE)
  mostrar_tabla(composicion_grupo, "Composición institucional por grupo de estrato")}

# AJUSTE oct-2026 (A14): dos descriptivos que salen de la limpieza nueva.
# 1) Puntaje según comunicación escrita en 0 (para dimensionar el problema).
# 2) Puntaje por grupos de edad (la edad antes ni siquiera llegaba al pipeline).
if ("diag_escrita_cero" %in% names(data_eda)) {
  tabla_escrita_cero <- data_eda %>%
    mutate(escrita_cero = if_else(diag_escrita_cero %in% 1, "Comunicación escrita en 0", "Calificada")) %>%
    resumen_categorica_vs_target("escrita_cero", target)
  write.csv(tabla_escrita_cero, file.path(salidas, "09_tablas", "eda_puntaje_por_escrita_cero.csv"), row.names = FALSE)
  mostrar_tabla(tabla_escrita_cero, "Puntaje según si comunicación escrita quedó en 0")}
if ("edad" %in% names(data_eda)) {
  tabla_edad <- data_eda %>%
    mutate(grupo_edad = cut(edad, breaks = c(14, 22, 25, 30, 40, 80),
                            labels = c("15-22", "23-25", "26-30", "31-40", "41-80"))) %>%
    resumen_categorica_vs_target("grupo_edad", target)
  write.csv(tabla_edad, file.path(salidas, "09_tablas", "eda_puntaje_por_edad.csv"), row.names = FALSE)
  mostrar_tabla(tabla_edad, "Puntaje por grupo de edad (edad imputada con la mediana donde faltaba)")}

# Correlaciones seguras
# AJUSTE oct-2026: se sacan los códigos administrativos y el tratamiento. Antes
# salían inst_cod_institucion o estu_snies_prgmacademico en el top de
# correlaciones, y un código no tiene orden, esa correlación no significa nada.
vars_num <- data_eda %>%
  select(where(is.numeric)) %>%
  select(where(~ sd(.x, na.rm = TRUE) > 0)) %>%
  names()
vars_num_cor <- setdiff(vars_num, c(target, vars_admin, "tratamiento"))
cor_df <- tibble(variable = character(), cor = numeric(), abs_cor = numeric())
if (length(vars_num_cor) > 0) {
  cor_df <- map_dfr(vars_num_cor, function(v) {
    tibble(
      variable = v,
      cor = suppressWarnings(cor(data_eda[[v]], data_eda[[target]], use = "pairwise.complete.obs"))  ) }) %>%
    mutate(abs_cor = abs(cor)) %>%
    arrange(desc(abs_cor))
  write.csv(
    cor_df,
    file.path(salidas, "09_tablas", "correlacion_variables_numericas_con_punt_global.csv"),
    row.names = FALSE )
  mostrar_tabla(head(cor_df, 20), "Top 20 correlaciones con punt_global")
  if ("corrplot" %in% loadedNamespaces()) {
    vars_cor_plot <- cor_df %>%
      filter(!is.na(cor)) %>%
      slice_max(abs_cor, n = 20) %>%
      pull(variable)
    vars_cor_plot <- unique(c(target, vars_cor_plot))
    if (length(vars_cor_plot) >= 3) {
      cor_data <- data_eda %>% select(all_of(vars_cor_plot))
      cor_mat <- cor(cor_data, use = "pairwise.complete.obs")
      write.csv(
        cor_mat,
        file.path(salidas, "09_tablas", "matriz_correlacion_top_variables.csv")
      )
      graficar_base(
        corrplot::corrplot(cor_mat, method = "color", type = "upper", tl.cex = .75, tl.col = "black"),
        archivo = file.path(salidas, "02_eda", "correlacion_top_variables_numericas.png"),
        width = 1300,
        height = 1100   ) }  }}

# 10. INFERENCIA DESCRIPTIVA
cat("\n===== INFERENCIA DESCRIPTIVA =====\n")
test_genero <- NULL
cohen_genero <- NULL
anova_estrato <- NULL
eta_estrato <- NULL
test_psm_grupo_descriptivo <- NULL
cohen_psm_grupo <- NULL
if ("estu_genero" %in% names(data_eda)) {
  data_test_genero <- data_eda %>% filter(estu_genero %in% c("M", "F"))
  if (length(unique(data_test_genero$estu_genero)) == 2) {
    test_genero <- t.test(punt_global ~ estu_genero, data = data_test_genero)
    cohen_genero <- effectsize::cohens_d(punt_global ~ estu_genero, data = data_test_genero)
    mostrar_tabla(test_genero, "Prueba t por género")
    mostrar_tabla(cohen_genero, "Tamaño del efecto (Cohen's d) por género") }}
# AJUSTE oct-2026 (A1): como estrato_num y estrato_grupo_psm ya no vienen
# imputados, el ANOVA, el eta² y la prueba t solo usan estudiantes con estrato
# reportado. Se imprime el N para que en el documento quede claro.
cat("N usado en ANOVA / eta² / prueba t por estrato:", sum(!is.na(data_eda$estrato_num)),
    "(se excluyen", sum(is.na(data_eda$estrato_num)), "sin estrato reportado)\n")
if ("estrato_num" %in% names(data_eda)) {
  anova_estrato <- tryCatch(
    aov(punt_global ~ factor(estrato_num), data = data_eda),
    error = function(e) NULL )
  eta_estrato <- if (!is.null(anova_estrato)) {
    tryCatch(effectsize::eta_squared(anova_estrato), error = function(e) NULL)
  } else NULL
  if (!is.null(anova_estrato)) mostrar_tabla(summary(anova_estrato), "ANOVA por estrato")
  if (!is.null(eta_estrato)) mostrar_tabla(eta_estrato, "Eta cuadrado por estrato")}
if ("estrato_grupo_psm" %in% names(data_eda)) {
  data_test_psm <- data_eda %>% filter(!is.na(estrato_grupo_psm))
  if (length(unique(data_test_psm$estrato_grupo_psm)) == 2) {
    test_psm_grupo_descriptivo <- t.test(punt_global ~ estrato_grupo_psm, data = data_test_psm)
    cohen_psm_grupo <- effectsize::cohens_d(punt_global ~ estrato_grupo_psm, data = data_test_psm)
    mostrar_tabla(test_psm_grupo_descriptivo, "Prueba t por grupo de estrato (PSM)")  }}
saveRDS(test_genero, file.path(salidas, "08_objetos", "test_genero.rds"))
saveRDS(cohen_genero, file.path(salidas, "08_objetos", "cohen_genero.rds"))
saveRDS(anova_estrato, file.path(salidas, "08_objetos", "anova_estrato.rds"))
saveRDS(eta_estrato, file.path(salidas, "08_objetos", "eta_estrato.rds"))
saveRDS(test_psm_grupo_descriptivo, file.path(salidas, "08_objetos", "test_psm_grupo_descriptivo.rds"))
saveRDS(cohen_psm_grupo, file.path(salidas, "08_objetos", "cohen_psm_grupo.rds"))

# 11. MODELO INFERENCIAL
cat("\n===== MODELO INFERENCIAL =====\n")
vars_lm_base <- c(
  target,
  "estrato_num",
  "estu_genero",
  "estu_depto_reside",
  "inst_origen",
  "inst_caracter_academico",
  "estu_metodo_prgm",
  "estu_nucleo_pregrado",   # reemplaza a gruporeferencia, que la base pública no trae
  "fami_tieneinternet",
  "fami_tienecomputador",
  "estu_inse_individual",
  "inse_imputado",          # AJUSTE oct-2026: el INSE entra imputado, así que va con su bandera
  "estu_nse_individual",
  "estu_nse_ies")
vars_lm_base <- intersect(vars_lm_base, names(data_eda))
# Ojo: lm() descarta solo las filas con estrato_num NA (los sin estrato), así
# que este modelo queda con N menor que la EDA. Se imprime abajo.
modelo_lm <- NULL
summary_lm <- NULL
modelo_lm_tidy <- NULL
modelo_lm_glance <- NULL
margins_lm <- NULL
modelo_estrato <- NULL
if (length(vars_lm_base) >= 2) {
  modelo_lm <- tryCatch(
    # AJUSTE oct-2026 (A13): en la corrida anterior salió un coeficiente para
    # estu_genero "No reporta", que es UN solo estudiante. No dice nada y ensucia
    # la tabla, así que ese registro sale solo de este modelo.
    lm(as.formula(paste(target, "~ .")),
       data = data_eda %>% filter(estu_genero %in% c("M", "F")) %>% select(all_of(vars_lm_base)) %>%
         # AJUSTE oct-2026 (A18): con estu_depto_reside en el modelo la
         # categoría de referencia quedaba en un departamento pequeño (EE de
         # 2,17 en todos los coeficientes). Se deja Bogotá como referencia, que
         # es la más grande y la que se lee más natural.
         mutate(across(any_of("estu_depto_reside"),
                       ~ if ("BOGOTÁ" %in% .x) relevel(factor(.x), ref = "BOGOTÁ") else factor(.x)))),
    error = function(e) {
      message("Modelo lineal inferencial no pudo ejecutarse: ", e$message)
      NULL })
  if (!is.null(modelo_lm)) {
    summary_lm <- summary(modelo_lm)
    modelo_lm_tidy <- broom::tidy(modelo_lm)
    modelo_lm_glance <- broom::glance(modelo_lm)
    cat("N del modelo lineal inferencial:", stats::nobs(modelo_lm), "\n")
    write.csv(modelo_lm_tidy, file.path(salidas, "09_tablas", "modelo_lm_tidy.csv"), row.names = FALSE)
    write.csv(modelo_lm_glance, file.path(salidas, "09_tablas", "modelo_lm_glance.csv"), row.names = FALSE)
    mostrar_tabla(modelo_lm_tidy, "Coeficientes del modelo lineal inferencial")
    mostrar_tabla(modelo_lm_glance, "Bondad de ajuste del modelo lineal inferencial")
    margins_lm <- if ("margins" %in% loadedNamespaces()) {
      tryCatch(summary(margins::margins(modelo_lm)), error = function(e) NULL)
    } else NULL  }}
if ("estrato_num" %in% names(data_eda)) {
  modelo_estrato <- tryCatch(
    lm(punt_global ~ estrato_num, data = data_eda),
    error = function(e) NULL  )}
saveRDS(modelo_lm, file.path(salidas, "08_objetos", "modelo_lm.rds"))
saveRDS(modelo_estrato, file.path(salidas, "08_objetos", "modelo_estrato.rds"))
saveRDS(summary_lm, file.path(salidas, "08_objetos", "summary_lm.rds"))
saveRDS(margins_lm, file.path(salidas, "08_objetos", "margins_lm.rds"))

# 12. PSM CUASI-EXPERIMENTAL

cat("\n===== PSM CUASI-EXPERIMENTAL =====\n")
psm <- NULL
matched_data <- NULL
modelo_causal <- NULL
psm_test <- NULL
balance_psm <- NULL
ATT <- NULL
if ("tratamiento" %in% names(data_eda)) {
  # AJUSTE oct-2026 (A1): este filtro antes no sacaba a nadie porque tratamiento
  # venía imputado. Ahora sí excluye a los que no reportan estrato: "no reporta"
  # no es un valor del tratamiento, es ausencia de dato, y no pueden ser
  # controles emparejables.
  data_psm <- data_eda %>%
    as_tibble() %>%
    filter(!is.na(tratamiento)) %>%
    mutate(tratamiento = factor(tratamiento, levels = c(0, 1)))
  cat("Registros en el PSM:", nrow(data_psm), "| excluidos por no reportar estrato:",
      nrow(data_eda) - nrow(data_psm), "\n")
  vars_psm_candidatas <- c(
    "estu_genero",
    "estu_depto_reside",
    "estu_prgm_departamento",
    "estu_depto_presentacion",
    "inst_origen",
    "inst_caracter_academico",
    "estu_metodo_prgm",
    "estu_nucleo_pregrado",   # área de formación, en vez de gruporeferencia
    "fami_tieneinternet",
    "fami_tienecomputador",
    "fami_educacionpadre",
    "fami_educacionmadre",
    "estu_horassemanatrabaja",
    "estu_pagomatriculabeca",
    "estu_pagomatriculacredito",
    "estu_pagomatriculapadres",
    "estu_pagomatriculapropio",
    "estu_nse_ies",
    # AJUSTE oct-2026 (A20): estas dos estaban en la lectura de origen familiar
    # pero no en la completa, entonces las lecturas no quedaban anidadas y no se
    # podía decir "la completa = las anteriores + institución". Ojo con quitarlas.
    "estu_areareside",
    "estu_tituloobtenidobachiller")
  vars_psm <- intersect(vars_psm_candidatas, names(data_psm))
  if (length(vars_psm) > 0) {
    vars_psm <- vars_psm[
      sapply(data_psm[, vars_psm, drop = FALSE], function(x) n_distinct(x, na.rm = TRUE) > 1)  ] }
  if (length(vars_psm) >= 2) {
    formula_psm <- as.formula(
      paste("tratamiento ~", paste(vars_psm, collapse = " + "))  )
    psm <- tryCatch(
      MatchIt::matchit(
        formula_psm,
        data = as.data.frame(data_psm),
        method = "nearest",
        distance = "glm",
        # AJUSTE oct-2026 (A5): antes link = "logit", o sea el caliper de 0,2 DE
        # se medía sobre la probabilidad. La regla de 0,2 DE (Austin, 2011) es
        # sobre el LOGIT del puntaje de propensión, por eso "linear.logit".
        link = "linear.logit",
        ratio = 1,
        replace = FALSE,
        caliper = 0.2,
        std.caliper = TRUE,
        # AJUSTE oct-2026 (A18): en las dos corridas anteriores estu_nse_ies
        # quedó con DME de 0,13 tras emparejar, y el ATT ajustado por regresión
        # salió bien distinto (2,74 vs 4,37). O sea que ese desbalance sí movía
        # la brecha. Como estu_nse_ies solo tiene 4 niveles, lo más limpio es
        # emparejar EXACTO en ella: cada tratado se compara con un control de
        # una institución del mismo nivel socioeconómico.
        exact = ~ estu_nse_ies),
      error = function(e) {
        message("PSM no pudo ejecutarse: ", e$message)
        NULL   } )
    if (!is.null(psm)) {
      matched_data <- MatchIt::match.data(psm) %>% as_tibble()
      if (length(unique(matched_data$tratamiento)) == 2) {
        psm_test <- tryCatch(
          t.test(punt_global ~ tratamiento, data = matched_data),
          error = function(e) NULL )
        modelo_causal <- tryCatch(
          lm(punt_global ~ tratamiento, data = matched_data, weights = weights),
          error = function(e) NULL   )
        balance_psm <- tryCatch(cobalt::bal.tab(psm, un = TRUE), error = function(e) NULL)
        if (!is.null(balance_psm)) {
          write.csv(as.data.frame(balance_psm$Balance) %>% tibble::rownames_to_column("covariable"),
                    file.path(salidas, "04_psm", "balance_psm.csv"), row.names = FALSE)}
        ATT <- if (!is.null(modelo_causal) && "tratamiento1" %in% names(coef(modelo_causal))) {
          coef(modelo_causal)["tratamiento1"]
        } else {
          NA_real_   }
        mostrar_tabla(psm_test, "Prueba t sobre datos emparejados (PSM)")
        mostrar_tabla(balance_psm, "Balance de covariables tras el PSM")
        cat("\nATT estimado (diferencia promedio ajustada):", ATT, "\n")
        # Love plot propio: con las ~130 covariables dummies el de cobalt era
        # ilegible y salía en inglés. Aquí van solo las 20 con mayor desbalance
        # antes de emparejar, en español.
        if (!is.null(balance_psm)) {
          bal_df <- as.data.frame(balance_psm$Balance) %>%
            tibble::rownames_to_column("covariable") %>%
            filter(covariable != "distance") %>%
            mutate(sin_ajustar = abs(Diff.Un), emparejada = abs(Diff.Adj)) %>%
            slice_max(sin_ajustar, n = 20, with_ties = FALSE) %>%
            mutate(covariable = fct_reorder(covariable, sin_ajustar)) %>%
            select(covariable, sin_ajustar, emparejada) %>%
            pivot_longer(c(sin_ajustar, emparejada), names_to = "muestra", values_to = "dme") %>%
            mutate(muestra = dplyr::recode(muestra, sin_ajustar = "Sin ajustar", emparejada = "Emparejada"))
          graf_love <- ggplot(bal_df, aes(x = dme, y = covariable, color = muestra)) +
            geom_vline(xintercept = 0.1, linetype = "dashed", color = colores_tesis["gris"]) +
            geom_point(size = 2.6) +
            scale_color_manual(values = c("Sin ajustar" = unname(colores_tesis["rojo"]),
                                          "Emparejada" = unname(colores_tesis["azul"]))) +
            labs(
              title = "Balance de covariables del PSM",
              subtitle = "20 covariables con mayor desbalance antes del emparejamiento (línea: umbral de 0,1)",
              x = "Diferencia de medias estandarizada (valor absoluto)",
              y = NULL,
              color = NULL) +
            tema_base
          guardar_grafico(graf_love, "love_plot_psm.png", carpeta = "04_psm", width = 9, height = 6)}
        graficar_base(
          plot(psm, type = "hist"),
          archivo = file.path(salidas, "04_psm", "soporte_comun_psm.png"),
          width = 1200,
          height = 800 )
        write.csv(matched_data, file.path(salidas, "04_psm", "matched_data.csv"), row.names = FALSE) } }
  } else {
    message("PSM omitido: no hay suficientes covariables disponibles.") }}
saveRDS(psm, file.path(salidas, "08_objetos", "psm.rds"))
saveRDS(matched_data, file.path(salidas, "08_objetos", "matched_data.rds"))
saveRDS(modelo_causal, file.path(salidas, "08_objetos", "modelo_causal.rds"))
saveRDS(psm_test, file.path(salidas, "08_objetos", "psm_test.rds"))
saveRDS(balance_psm, file.path(salidas, "08_objetos", "balance_psm.rds"))
saveRDS(ATT, file.path(salidas, "08_objetos", "att_psm.rds"))

# 12.1 LÍMITES DE ROSENBAUM (SENSIBILIDAD DEL PSM A SESGO OCULTO)

cat("\n===== LÍMITES DE ROSENBAUM (SENSIBILIDAD PSM) =====\n")
rosenbaum_hl <- NULL
if (!is.null(matched_data) && "subclass" %in% names(matched_data) && "tratamiento" %in% names(matched_data)) {
  pares_rosenbaum <- matched_data %>%
    mutate(tratamiento = as.numeric(as.character(tratamiento))) %>%
    select(subclass, tratamiento, punt_global) %>%
    group_by(subclass) %>%
    filter(n() == 2, n_distinct(tratamiento) == 2) %>%
    ungroup()
  y_tratamiento <- pares_rosenbaum %>% filter(tratamiento == 1) %>% arrange(subclass) %>% pull(punt_global)
  y_control <- pares_rosenbaum %>% filter(tratamiento == 0) %>% arrange(subclass) %>% pull(punt_global)
  if (length(y_tratamiento) == length(y_control) && length(y_tratamiento) > 0 &&
      "rbounds" %in% loadedNamespaces()) {
    rosenbaum_hl <- tryCatch(
      rbounds::hlsens(y_tratamiento, y_control, Gamma = 3, GammaInc = 0.1),
      error = function(e) {
        message("Límites de Rosenbaum no pudieron calcularse: ", e$message)
        NULL} )
    if (!is.null(rosenbaum_hl)) {
      mostrar_tabla(rosenbaum_hl, "Límites de Rosenbaum (sensibilidad Hodges-Lehmann) sobre el PSM")
      tabla_rosenbaum <- tryCatch(as.data.frame(rosenbaum_hl$bounds), error = function(e) NULL)
      if (!is.null(tabla_rosenbaum)) {
        write.csv(
          tabla_rosenbaum,
          file.path(salidas, "04_psm", "rosenbaum_bounds.csv"),
          row.names = FALSE  )  } }
    # AJUSTE oct-2026 (A5): ojo con la lectura de hlsens. Lo que da son los
    # límites del ESTIMADOR PUNTUAL de Hodges-Lehmann bajo cada Gamma, no un
    # intervalo de confianza. Que el límite inferior toque cero quiere decir
    # que el estimador podría ser cero, no que "deje de ser significativo".
    # Para hablar de significancia se corre psens (prueba de rangos con signo
    # de Wilcoxon): da la cota superior del p-valor para cada Gamma. El Gamma
    # crítico de significancia es el primero donde esa cota pasa de 0,05.
    rosenbaum_p <- tryCatch(
      rbounds::psens(y_tratamiento, y_control, Gamma = 3, GammaInc = 0.05),
      error = function(e) {
        message("psens no pudo calcularse: ", e$message)
        NULL})
    if (!is.null(rosenbaum_p)) {
      tabla_rosenbaum_p <- as.data.frame(rosenbaum_p$bounds)
      names(tabla_rosenbaum_p) <- c("gamma", "p_inferior", "p_superior")
      gamma_critico_p <- tabla_rosenbaum_p %>% filter(p_superior > 0.05) %>% pull(gamma) %>% min(Inf)
      gamma_critico_hl <- Inf
      if (!is.null(rosenbaum_hl)) {
        tabla_hl_df <- as.data.frame(rosenbaum_hl$bounds)
        gamma_critico_hl <- tabla_hl_df[[1]][tabla_hl_df[[2]] <= 0] %>% min(Inf)}
      write.csv(tabla_rosenbaum_p, file.path(salidas, "04_psm", "rosenbaum_psens_pvalores.csv"), row.names = FALSE)
      mostrar_tabla(tabla_rosenbaum_p, "Rosenbaum con psens (cotas del p-valor de Wilcoxon por Gamma)")
      cat("Gamma crítico de SIGNIFICANCIA (psens, p superior > 0,05):",
          ifelse(is.finite(gamma_critico_p), gamma_critico_p, "no se alcanza en la malla"), "\n")
      cat("Gamma donde el límite inferior del ESTIMADOR HL llega a cero (hlsens):",
          ifelse(is.finite(gamma_critico_hl), gamma_critico_hl, "no se alcanza en la malla"), "\n")
      cat("Pilas: son dos preguntas distintas, en el documento se reportan las dos con su nombre.\n")
      saveRDS(rosenbaum_p, file.path(salidas, "08_objetos", "rosenbaum_psens.rds"))}
  } else {
    message("AVISO: no se pudo ejecutar el análisis de Rosenbaum (paquete 'rbounds' no disponible, ",
            "o los pares emparejados no son completos 1 a 1).") }
} else {
  message("AVISO: no hay matched_data con columna 'subclass'; se omite el análisis de Rosenbaum.")}
saveRDS(rosenbaum_hl, file.path(salidas, "08_objetos", "rosenbaum_hl.rds"))


# 12.2 TRES LECTURAS DE LA BRECHA POR ESTRATO: CRUDA, SOLO PREVIAS Y COMPLETA
# Ojo con esto (observación de la tutora): el PSM completo empareja también por
# institución, programa y forma de pago, que son POSTERIORES al estrato (el
# estrato influye en a qué universidad se entra y cómo se paga). Ajustar por
# eso puede "borrar" el canal institucional. Por eso se corren especificaciones
# con menos controles y se reportan todas. La distancia entre ellas es el peso
# de cada canal.
# AJUSTE oct-2026: en la lista de "posteriores" también van estu_nse_ies (es
# el nivel socioeconómico de la institución a la que se llegó), tener internet
# o computador y las horas de trabajo; en el documento hay que nombrarlas todas.
# Pilas: el emparejamiento EXACTO en estu_nse_ies solo va en la completa, porque
# es variable institucional; en las lecturas sin institución no tiene sentido.
cat("\n===== PSM: BRECHA CRUDA, MÍNIMA, ORIGEN FAMILIAR Y COMPLETA =====\n")
resumir_psm <- function(obj_psm, nombre) {
  if (is.null(obj_psm)) return(NULL)
  md <- MatchIt::match.data(obj_psm) %>% as_tibble()
  trat <- as.numeric(as.character(obj_psm$treat))
  n_trat <- sum(trat == 1)
  pares <- sum(as.character(md$tratamiento) == "1")
  tt <- t.test(punt_global ~ tratamiento, data = md)
  pares_df <- md %>%
    mutate(t = as.numeric(as.character(tratamiento))) %>%
    group_by(subclass) %>%
    filter(n() == 2, n_distinct(t) == 2) %>%
    ungroup()
  yt <- pares_df %>% filter(t == 1) %>% arrange(subclass) %>% pull(punt_global)
  yc <- pares_df %>% filter(t == 0) %>% arrange(subclass) %>% pull(punt_global)
  hl <- NA_real_
  gamma_crit <- NA_real_
  gamma_crit_p <- NA_real_
  # AJUSTE oct-2026 (A12): chequeo de balance y ajuste por regresión.
  # Pilas con esto: con el caliper sobre el logit, estu_nse_ies quedó con DME
  # de 0,13 después de emparejar (la única por encima de 0,1). La salida
  # estándar es ajustar por regresión SOBRE la muestra emparejada con las
  # mismas covariables del puntaje de propensión (Ho et al., 2007): si el ATT
  # casi no se mueve, el desbalance residual no está sesgando la brecha.
  dme_max <- NA_real_; cov_dme_max <- NA_character_; n_sobre_01 <- NA_integer_
  bal_i <- tryCatch(cobalt::bal.tab(obj_psm, un = FALSE), error = function(e) NULL)
  if (!is.null(bal_i)) {
    bal_i_df <- as.data.frame(bal_i$Balance) %>%
      tibble::rownames_to_column("covariable") %>%
      filter(covariable != "distance") %>%
      mutate(dme_abs = abs(Diff.Adj))
    dme_max <- max(bal_i_df$dme_abs, na.rm = TRUE)
    cov_dme_max <- bal_i_df$covariable[which.max(bal_i_df$dme_abs)]
    n_sobre_01 <- sum(bal_i_df$dme_abs > 0.1, na.rm = TRUE)
    if (n_sobre_01 > 0) {
      cat("Ojo [", nombre, "]: covariables con DME > 0,1 tras emparejar:",
          paste(bal_i_df$covariable[bal_i_df$dme_abs > 0.1], collapse = ", "), "\n")}}
  att_reg <- c(NA_real_, NA_real_, NA_real_)
  covs_ps <- setdiff(all.vars(obj_psm$formula), "tratamiento")
  covs_ps <- covs_ps[covs_ps %in% names(md)]
  if (length(covs_ps) > 0) {
    att_reg <- tryCatch({
      m_aj <- lm(as.formula(paste("punt_global ~ tratamiento +", paste(covs_ps, collapse = " + "))),
                 data = md, weights = weights)
      c(coef(m_aj)[["tratamiento1"]], confint(m_aj)["tratamiento1", ])},
      error = function(e) {
        message("Ajuste por regresión falló en ", nombre, ": ", e$message)
        c(NA_real_, NA_real_, NA_real_)})}
  # AJUSTE oct-2026 (A5): diferencia PAREADA con su IC. El t de Welch de abajo
  # trata las dos muestras como independientes y no aprovecha el emparejamiento.
  dif_pareada <- NA_real_; ic_par_inf <- NA_real_; ic_par_sup <- NA_real_
  if (length(yt) > 1 && length(yt) == length(yc)) {
    tt_par <- t.test(yt, yc, paired = TRUE)
    dif_pareada <- unname(tt_par$estimate)
    ic_par_inf <- tt_par$conf.int[1]
    ic_par_sup <- tt_par$conf.int[2]}
  if ("rbounds" %in% loadedNamespaces() && length(yt) > 0 && length(yt) == length(yc)) {
    rb <- tryCatch(rbounds::hlsens(yt, yc, Gamma = 2, GammaInc = 0.05), error = function(e) NULL)
    if (!is.null(rb)) {
      b <- as.data.frame(rb$bounds)
      hl <- b[1, 2]
      cruza <- b[[1]][b[[2]] <= 0]
      gamma_crit <- if (length(cruza) > 0) min(cruza) else NA_real_}
    rp <- tryCatch(rbounds::psens(yt, yc, Gamma = 2, GammaInc = 0.05), error = function(e) NULL)
    if (!is.null(rp)) {
      bp <- as.data.frame(rp$bounds)
      no_sig <- bp[[1]][bp[[3]] > 0.05]
      gamma_crit_p <- if (length(no_sig) > 0) min(no_sig) else NA_real_}}
  tibble(
    especificacion = nombre,
    n_tratados = n_trat,
    n_controles = sum(trat == 0),
    pares = pares,
    tratados_sin_pareja = n_trat - pares,
    pct_tratados_sin_pareja = (n_trat - pares) / n_trat,
    diferencia_medias = unname(tt$estimate[2] - tt$estimate[1]),
    ic95_inf = -tt$conf.int[2],
    ic95_sup = -tt$conf.int[1],
    diferencia_pareada = dif_pareada,
    ic95_pareada_inf = ic_par_inf,
    ic95_pareada_sup = ic_par_sup,
    hodges_lehmann = hl,
    gamma_hl_cero = gamma_crit,            # Gamma donde el estimador HL podría ser 0
    gamma_significancia = gamma_crit_p,    # Gamma donde p (Wilcoxon) pasa de 0,05
    dme_max_post = dme_max,                # peor balance tras emparejar
    covariable_dme_max = cov_dme_max,
    n_cov_dme_sobre_0_1 = n_sobre_01,
    att_ajustado_regresion = att_reg[1],   # ATT con ajuste por regresión (robustez)
    ic95_att_aj_inf = att_reg[2],
    ic95_att_aj_sup = att_reg[3])}

tabla_psm_especificaciones <- NULL
psm_previas <- NULL
if (exists("data_psm") && !is.null(psm)) {
  # brecha cruda, sin ajustar nada
  tt_cruda <- t.test(punt_global ~ tratamiento, data = data_psm)
  fila_cruda <- tibble(
    especificacion = "Cruda (sin ajuste)",
    n_tratados = sum(as.character(data_psm$tratamiento) == "1"),
    n_controles = sum(as.character(data_psm$tratamiento) == "0"),
    pares = NA_integer_,
    tratados_sin_pareja = NA_integer_,
    pct_tratados_sin_pareja = NA_real_,
    diferencia_medias = unname(tt_cruda$estimate[2] - tt_cruda$estimate[1]),
    ic95_inf = -tt_cruda$conf.int[2],
    ic95_sup = -tt_cruda$conf.int[1],
    diferencia_pareada = NA_real_,
    ic95_pareada_inf = NA_real_,
    ic95_pareada_sup = NA_real_,
    hodges_lehmann = NA_real_,
    gamma_hl_cero = NA_real_,
    gamma_significancia = NA_real_,
    dme_max_post = NA_real_,
    covariable_dme_max = NA_character_,
    n_cov_dme_sobre_0_1 = NA_integer_,
    att_ajustado_regresion = NA_real_,
    ic95_att_aj_inf = NA_real_,
    ic95_att_aj_sup = NA_real_)
  # solo covariables previas al estrato: género, educación de madre y padre,
  # departamento y zona de residencia, y tipo de bachillerato
  # AJUSTE oct-2026 (A3): el código ya no llega winsorizado; el único NA que
  # trae queda como categoría propia para que matchit no se caiga.
  data_psm_prev <- data_psm %>%
    mutate(depto_reside_cod = if_else(is.na(estu_cod_reside_depto), "No reporta",
                                      as.character(estu_cod_reside_depto)))
  vars_previas <- intersect(
    c("estu_genero", "fami_educacionmadre", "fami_educacionpadre",
      "depto_reside_cod", "estu_areareside", "estu_tituloobtenidobachiller"),
    names(data_psm_prev))
  vars_previas <- vars_previas[
    sapply(data_psm_prev[, vars_previas, drop = FALSE], function(x) n_distinct(x, na.rm = TRUE) > 1)]
  cat("Covariables previas usadas:", paste(vars_previas, collapse = ", "), "\n")
  psm_previas <- tryCatch(
    MatchIt::matchit(
      as.formula(paste("tratamiento ~", paste(vars_previas, collapse = " + "))),
      data = as.data.frame(data_psm_prev),
      method = "nearest", distance = "glm", link = "linear.logit",   # AJUSTE oct-2026 (A5)
      ratio = 1, replace = FALSE, caliper = 0.2, std.caliper = TRUE),
    error = function(e) {
      message("PSM con covariables previas no pudo ejecutarse: ", e$message)
      NULL})
  # AJUSTE oct-2026 (A17, observación 5 de la tutora): la educación de la madre
  # y del padre no es propiamente "anterior" al estrato, es un COMPONENTE del
  # nivel socioeconómico. Así que la especificación de previas mide la brecha
  # residual entre estudiantes con padres de la misma educación, del mismo
  # departamento, zona y tipo de bachillerato. Es un estimando legítimo pero hay
  # que llamarlo así (de ahí el nombre nuevo de la fila). Para que no digan en
  # la sustentación que se ajustó de más "por el otro lado", se agrega una
  # especificación mínima SIN la educación de los padres: solo género,
  # departamento y zona de residencia y tipo de bachillerato.
  vars_previas_minimas <- setdiff(vars_previas, c("fami_educacionmadre", "fami_educacionpadre"))
  cat("Covariables de la especificación mínima (sin educación de los padres):",
      paste(vars_previas_minimas, collapse = ", "), "\n")
  psm_minimas <- tryCatch(
    MatchIt::matchit(
      as.formula(paste("tratamiento ~", paste(vars_previas_minimas, collapse = " + "))),
      data = as.data.frame(data_psm_prev),
      method = "nearest", distance = "glm", link = "linear.logit",
      ratio = 1, replace = FALSE, caliper = 0.2, std.caliper = TRUE),
    error = function(e) {
      message("PSM con covariables mínimas no pudo ejecutarse: ", e$message)
      NULL})
  tabla_psm_especificaciones <- bind_rows(
    fila_cruda,
    resumir_psm(psm_minimas, "Demográficas y territoriales (género, depto y zona de residencia, bachillerato)"),
    resumir_psm(psm_previas, "Origen familiar y territorial (las anteriores + educación de madre y padre)"),
    resumir_psm(psm, "Todas las covariables (incluye institución, programa y pago)"))
  rm(psm_minimas)
  mostrar_tabla(tabla_psm_especificaciones, "Brecha por estrato: cruda, mínima, origen familiar y completa")
  # se imprime completa porque el tibble corta columnas y de aquí salen cifras del documento
  if (mostrar_en_pantalla) print(as.data.frame(tabla_psm_especificaciones))
  write.csv(tabla_psm_especificaciones, file.path(salidas, "04_psm", "psm_especificaciones.csv"), row.names = FALSE)
  if (!is.null(psm_previas)) {
    bal_prev <- tryCatch(cobalt::bal.tab(psm_previas, un = TRUE), error = function(e) NULL)
    if (!is.null(bal_prev)) {
      write.csv(as.data.frame(bal_prev$Balance) %>% tibble::rownames_to_column("covariable"),
                file.path(salidas, "04_psm", "balance_psm_previas.csv"), row.names = FALSE)}}}
saveRDS(tabla_psm_especificaciones, file.path(salidas, "08_objetos", "psm_especificaciones.rds"))
rm(psm_previas); invisible(gc())

# 12.3 AJUSTE oct-2026 (A16): SENSIBILIDAD SIN COMUNICACIÓN ESCRITA EN 0
# Esto salió revisando los CSV de la limpieza nueva: en 2024 el 6,7% de los
# estudiantes tiene comunicación escrita en 0 (media global 106 vs 149) y en
# 2025 solo el 1,7%. Además pega más abajo: 8,6% en estrato 1 vs 4,3% en
# estrato 6. Ojo: NO se sacan del análisis principal porque eso sería
# seleccionar por la variable dependiente (el 0 es parte del puntaje oficial).
# Lo que se hace es repetir la brecha y el PSM completo SIN ellos y reportar
# las dos lecturas: si la brecha casi no cambia, el hallazgo no depende de los
# escritos sin calificar.
tabla_psm_sensibilidad <- NULL
if (exists("data_psm") && "diag_escrita_cero" %in% names(data_psm) && exists("vars_psm") &&
    !is.null(tabla_psm_especificaciones)) {
  cat("\n===== SENSIBILIDAD: BRECHA Y PSM SIN COMUNICACIÓN ESCRITA EN 0 =====\n")
  data_psm_sens <- data_psm %>% filter(diag_escrita_cero %in% 0)
  cat("Registros del PSM sin escrita en 0:", nrow(data_psm_sens), "| excluidos:", nrow(data_psm) - nrow(data_psm_sens), "\n")
  cat("% con escrita en 0 por grupo de tratamiento (antes de excluir):\n")
  print(data_psm %>% group_by(tratamiento) %>% summarise(pct_escrita_cero = round(100 * mean(diag_escrita_cero %in% 1), 2), .groups = "drop"))
  tt_cruda_sens <- t.test(punt_global ~ tratamiento, data = data_psm_sens)
  psm_sens <- tryCatch(
    MatchIt::matchit(
      as.formula(paste("tratamiento ~", paste(vars_psm, collapse = " + "))),
      data = as.data.frame(data_psm_sens),
      method = "nearest", distance = "glm", link = "linear.logit",
      ratio = 1, replace = FALSE, caliper = 0.2, std.caliper = TRUE,
      exact = ~ estu_nse_ies),   # AJUSTE oct-2026 (A18): igual que la principal
    error = function(e) {
      message("PSM de sensibilidad no pudo ejecutarse: ", e$message)
      NULL})
  tabla_psm_sensibilidad <- bind_rows(
    tibble(
      especificacion = "Cruda sin escrita en 0",
      n_tratados = sum(as.character(data_psm_sens$tratamiento) == "1"),
      n_controles = sum(as.character(data_psm_sens$tratamiento) == "0"),
      diferencia_medias = unname(tt_cruda_sens$estimate[2] - tt_cruda_sens$estimate[1]),
      ic95_inf = -tt_cruda_sens$conf.int[2],
      ic95_sup = -tt_cruda_sens$conf.int[1]),
    resumir_psm(psm_sens, "Todas las covariables, sin escrita en 0"))
  # se pone al lado de la principal para comparar de un vistazo
  tabla_psm_sensibilidad <- bind_rows(
    tabla_psm_especificaciones %>% mutate(muestra = "Principal (puntaje oficial)"),
    tabla_psm_sensibilidad %>% mutate(muestra = "Sensibilidad (sin escrita en 0)")) %>%
    relocate(muestra)
  if (mostrar_en_pantalla) print(as.data.frame(tabla_psm_sensibilidad %>%
                                                 select(muestra, especificacion, pares, diferencia_medias, ic95_inf, ic95_sup,
                                                        att_ajustado_regresion, hodges_lehmann, gamma_significancia, dme_max_post)))
  write.csv(tabla_psm_sensibilidad, file.path(salidas, "04_psm", "psm_sensibilidad_escrita_cero.csv"), row.names = FALSE)
  saveRDS(tabla_psm_sensibilidad, file.path(salidas, "08_objetos", "psm_sensibilidad_escrita_cero.rds"))
  rm(psm_sens); invisible(gc())}

# 13. PREPROCESAMIENTO ML SIN DATA LEAKAGE
cat("\n===== PREPROCESAMIENTO ML =====\n")
# AJUSTE oct-2026 (A7): fuera del modelo también
#  - fami_estratovivienda: el estrato ya entra como estrato_num (+ bandera
#    estrato_faltante); con las dos versiones la importancia SHAP del estrato
#    quedaba partida entre varias columnas y se veía más baja de lo que es.
#  - inse_cuartil: es un corte de estu_inse_individual y sus cortes se sacaban
#    con la base completa, antes de partir. Repetido y con fuga de parámetros.
#  - estu_privado_libertad: variable sensible, mismo criterio que discapacidad.
excluir_modelo_principal <- unique(c(
  vars_admin,
  vars_sensibles_modelo,
  "tratamiento",
  "estrato_grupo_psm",
  "fami_estratovivienda_original",
  "fami_estratovivienda",
  "inse_cuartil"))
data_ml <- data %>%
  as_tibble() %>%
  select(-any_of(excluir_modelo_principal)) %>%
  select(all_of(target), everything()) %>%
  filter(!is.na(.data[[target]]))
if (nrow(data_ml) < 100) {
  stop("ERROR: data_ml tiene muy pocos registros para modelar.")}
# data_ml_meta guarda aparte estrato_grupo_psm y tratamiento. No entran al
# modelo, pero se necesitan para la equidad (sección 17). Antes se perdían y
# la equidad por grupo PSM nunca corría, ojo con no volver a borrarlas.
data_ml_meta <- data %>%
  as_tibble() %>%
  filter(!is.na(.data[[target]])) %>%
  select(any_of(c("estrato_grupo_psm", "tratamiento", "inse_imputado",
                  # AJUSTE oct-2026: estas ya no entran al modelo pero la
                  # equidad las necesita, así que viajan por aquí, sin imputar
                  "fami_estratovivienda", "estrato_num", "inse_cuartil", "estu_genero",
                  "diag_escrita_cero")))   # AJUSTE oct-2026 (A14): solo para diagnóstico

# Pilas: semilla fija JUSTO antes de partir. Antes solo estaba la semilla global
# del inicio y los muestreos de la EDA consumían números aleatorios, así que
# cualquier gráfico nuevo movía la partición 80/20 y todos los resultados.
set.seed(123)
train_index <- caret::createDataPartition(data_ml[[target]], p = 0.8, list = FALSE)
train_ml_raw <- data_ml[train_index, ] %>% as_tibble()
test_ml_raw <- data_ml[-train_index, ] %>% as_tibble()
train_meta_raw <- data_ml_meta[train_index, ] %>% as_tibble()
test_meta_raw <- data_ml_meta[-train_index, ] %>% as_tibble()

reglas_train <- aprender_imputacion(train_ml_raw)
# AJUSTE oct-2026 (A15): en el modelo también, las categóricas faltantes van a
# "No reporta" y no a la moda. Pilas con esto: con la moda, los que no
# respondieron (p. ej. el 4% sin dato de horno o motocicleta) quedaban como "No"
# sin que nadie lo hubiera dicho. (Consola y compartebaño ya salen desde la
# limpieza, L9, porque no se preguntaron en 20241 y 20242.) Con categoría propia el
# modelo aprende si "no responder" se asocia con el puntaje (que sí pasa: los
# "No reporta" puntúan más bajo en la EDA). Las numéricas siguen con la mediana.
reglas_train <- purrr::imap(reglas_train, function(regla, v) {
  if (is.numeric(train_ml_raw[[v]])) regla else "No reporta"})
limites_train <- aprender_limites(train_ml_raw, excluir = target)
# Igual que en data_eda: la variable dependiente se excluye de la
# winsorización/imputación al preparar train_ml y test_ml.
train_ml <- aplicar_imputacion(train_ml_raw, reglas_train, excluir = target, limites = limites_train)
test_ml <- aplicar_imputacion(test_ml_raw, reglas_train, excluir = target, limites = limites_train)
remove_single_level <- function(df) {
  df <- as_tibble(df)
  vars_validas <- names(df)[sapply(df, function(x) {
    if (is.character(x) || is.factor(x)) {
      return(n_distinct(x, na.rm = TRUE) > 1)
    } else {
      return(TRUE)}})]
  df %>% select(all_of(vars_validas))}
train_ml <- remove_single_level(train_ml)
test_ml <- test_ml %>% select(any_of(names(train_ml)))
train_ml <- train_ml %>% mutate(across(where(is.character), as.factor))
test_ml <- test_ml %>% mutate(across(where(is.character), as.factor))
for (col in names(train_ml)) {
  if (is.factor(train_ml[[col]]) && col %in% names(test_ml)) {
    niveles_train <- levels(train_ml[[col]])
    test_ml[[col]] <- as.character(test_ml[[col]])
    test_ml[[col]][!(test_ml[[col]] %in% niveles_train)] <- "Other"
    train_ml[[col]] <- as.character(train_ml[[col]])
    niveles_finales <- unique(c(niveles_train, "Other"))
    train_ml[[col]] <- factor(train_ml[[col]], levels = niveles_finales)
    test_ml[[col]] <- factor(test_ml[[col]], levels = niveles_finales)}}
dummies <- caret::dummyVars(
  as.formula(paste(target, "~ .")),
  data = train_ml,
  fullRank = TRUE)
train_x <- predict(dummies, newdata = train_ml) %>% as.data.frame()
test_x <- predict(dummies, newdata = test_ml) %>% as.data.frame()
train_y <- train_ml[[target]]
test_y <- test_ml[[target]]
train_x[is.na(train_x)] <- 0
test_x[is.na(test_x)] <- 0
train_x <- data.frame(lapply(train_x, as.numeric))
test_x <- data.frame(lapply(test_x, as.numeric))
train_x[!is.finite(as.matrix(train_x))] <- 0
test_x[!is.finite(as.matrix(test_x))] <- 0
nzv <- caret::nearZeroVar(train_x)
# AJUSTE oct-2026 (A19): ojo, nearZeroVar se llevaba las banderas de faltante
# (inse_imputado 3,8% y estrato_faltante 3,2% de TRUE) y el modelo nunca las
# veía; o sea que los sin estrato entraban como estrato 2 (la mediana) sin
# nada que los distinguiera. Se protegen a mano. Si este cat sale vacío es que
# dummyVars les cambió el nombre: revisar names(train_x).
proteger_nzv <- grep("^(inse_imputado|estrato_faltante)\\.?TRUE$", names(train_x))
nzv <- setdiff(nzv, proteger_nzv)
cat("Banderas protegidas del filtro nzv:", paste(names(train_x)[proteger_nzv], collapse = ", "), "\n")
if (length(nzv) > 0) {
  train_x <- train_x[, -nzv, drop = FALSE]
  test_x <- test_x[, -nzv, drop = FALSE]}
usar_reduccion_correlacion <- FALSE
if (ncol(train_x) > 500) {
  usar_reduccion_correlacion <- TRUE
  cor_target_ml <- sapply(train_x, function(x) {
    if (sd(x) == 0) return(0)
    val <- suppressWarnings(cor(x, train_y))
    if (is.na(val)) return(0)
    abs(val)})
  cor_target_ml <- sort(cor_target_ml, decreasing = TRUE)
  top_vars <- names(cor_target_ml)[1:min(300, length(cor_target_ml))]
  train_x <- train_x[, top_vars, drop = FALSE]
  test_x <- test_x[, top_vars, drop = FALSE]
} else {
  top_vars <- names(train_x)
}
cat("Variables finales para ML:", ncol(train_x), "\n")
saveRDS(dummies, file.path(salidas, "08_objetos", "dummies.rds"))
saveRDS(top_vars, file.path(salidas, "08_objetos", "top_vars.rds"))
saveRDS(train_x, file.path(salidas, "08_objetos", "train_x.rds"))
saveRDS(test_x, file.path(salidas, "08_objetos", "test_x.rds"))
saveRDS(train_y, file.path(salidas, "08_objetos", "train_y.rds"))
saveRDS(test_y, file.path(salidas, "08_objetos", "test_y.rds"))

# 14. MODELOS PREDICTIVOS
cat("\n===== MODELOS PREDICTIVOS =====\n")
# AJUSTE oct-2026 (A6): antes R2 era solo el cuadrado de la correlación. Ese
# R² ignora el sesgo de nivel: si el modelo se corre 3 puntos para abajo en
# todos (pasa en 2025), la correlación no se entera. Ahora R2 es el tradicional
# 1 - SSE/SST y se deja R2_cor2 al lado para comparar. En el test 2024 casi
# coinciden; donde se separan es en la cohorte 2025.
metricas <- function(real, pred, modelo) {
  ok <- !is.na(real) & !is.na(pred)
  tibble(
    modelo = modelo,
    RMSE = sqrt(mean((real[ok] - pred[ok])^2)),
    MAE = mean(abs(real[ok] - pred[ok])),
    R2 = 1 - sum((real[ok] - pred[ok])^2) / sum((real[ok] - mean(real[ok]))^2),
    R2_cor2 = suppressWarnings(cor(real[ok], pred[ok])^2),
    MAE_pct_max_teorico = MAE / puntaje_maximo_teorico,
    RMSE_pct_max_teorico = RMSE / puntaje_maximo_teorico)}
resultados_modelos <- tibble()
# Regresión lineal predictiva
df_train_lm <- train_x
df_train_lm$punt_global <- train_y
df_test_lm <- test_x
modelo_lm_pred <- tryCatch(
  lm(punt_global ~ ., data = df_train_lm),
  error = function(e) {
    message("Regresión lineal predictiva falló: ", e$message)
    NULL})
pred_lm <- rep(NA_real_, length(test_y))
if (!is.null(modelo_lm_pred)) {
  pred_lm <- predict(modelo_lm_pred, newdata = df_test_lm)
  resultados_modelos <- bind_rows(
    resultados_modelos,
    metricas(test_y, pred_lm, "Regresión lineal")
  )
}
# Ridge y Lasso
x_train_mat <- as.matrix(train_x)
x_test_mat <- as.matrix(test_x)
cv_ridge <- tryCatch(
  glmnet::cv.glmnet(x_train_mat, train_y, alpha = 0, nfolds = 5),
  error = function(e) {
    message("Ridge falló: ", e$message)
    NULL
  }
)
pred_ridge <- rep(NA_real_, length(test_y))
if (!is.null(cv_ridge)) {
  pred_ridge <- predict(cv_ridge, newx = x_test_mat, s = "lambda.min")[, 1]
  resultados_modelos <- bind_rows(resultados_modelos, metricas(test_y, pred_ridge, "Ridge"))
}
cv_lasso <- tryCatch(
  glmnet::cv.glmnet(x_train_mat, train_y, alpha = 1, nfolds = 5),
  error = function(e) {
    message("Lasso falló: ", e$message)
    NULL
  }
)
pred_lasso <- rep(NA_real_, length(test_y))
if (!is.null(cv_lasso)) {
  pred_lasso <- predict(cv_lasso, newx = x_test_mat, s = "lambda.min")[, 1]
  resultados_modelos <- bind_rows(resultados_modelos, metricas(test_y, pred_lasso, "Lasso"))
}
# AJUSTE oct-2026 (A22): el documento dice que Ridge y Lasso escogieron una
# penalización casi nula; esto deja el dato en el log para poder sostenerlo.
if (!is.null(cv_ridge) && !is.null(cv_lasso)) {
  cat("Ridge lambda.min:", signif(cv_ridge$lambda.min, 4),
      "| Lasso lambda.min:", signif(cv_lasso$lambda.min, 4), "\n")}
# Ranger RF
modelo_ranger <- NULL
pred_ranger <- NULL
num_threads <- max(1, parallel::detectCores() - 1)
df_train_ranger <- train_x
df_train_ranger$punt_global <- train_y
df_test_ranger <- test_x

# 14.0 TUNING DE HIPERPARÁMETROS RANDOM FOREST (grid ligero con validación cruzada de 5 partes)
# RF es poco sensible a sus hiperparámetros (Breiman, 2001; Probst et al., 2019),
# por eso la malla es más chica que la de XGBoost. Igual se usa CV de 5 partes
# para que la comparación entre modelos sea pareja. Esto se demora, paciencia.
cat("\n===== TUNING DE HIPERPARÁMETROS RANDOM FOREST =====\n")
set.seed(123)
p_predictores_rf <- ncol(train_x)
mtry_base_rf <- max(1, floor(sqrt(p_predictores_rf)))
grid_rf <- expand.grid(
  mtry = unique(pmax(1, round(mtry_base_rf * c(0.5, 1, 1.5)))),
  min.node.size = c(5, 10, 20))
set.seed(123)
folds_rf <- caret::createFolds(train_y, k = 5, list = TRUE)
evaluar_combo_rf <- function(mtry_i, min_node_i, num_trees_i = 300) {
  rmse_folds <- purrr::map_dbl(folds_rf, function(idx_val) {
    fit_i <- tryCatch(
      ranger::ranger(
        punt_global ~ .,
        data = df_train_ranger[-idx_val, ],
        num.trees = num_trees_i,
        mtry = mtry_i,
        min.node.size = min_node_i,
        num.threads = num_threads,
        seed = 123),
      error = function(e) NULL)
    if (is.null(fit_i)) return(NA_real_)
    pred_i <- predict(fit_i, data = df_train_ranger[idx_val, ])$predictions
    sqrt(mean((df_train_ranger$punt_global[idx_val] - pred_i)^2, na.rm = TRUE))})
  mean(rmse_folds, na.rm = TRUE)}
resultados_tuning_rf <- vector("list", nrow(grid_rf))
for (i in seq_len(nrow(grid_rf))) {
  cv_rmse_i <- evaluar_combo_rf(grid_rf$mtry[i], grid_rf$min.node.size[i])
  resultados_tuning_rf[[i]] <- tibble(
    combinacion = i,
    mtry = grid_rf$mtry[i],
    min_node_size = grid_rf$min.node.size[i],
    cv_rmse = cv_rmse_i)
  cat("Combinación RF", i, "de", nrow(grid_rf), "| CV-RMSE:", round(cv_rmse_i, 4), "\n")}
tabla_tuning_rf <- bind_rows(resultados_tuning_rf) %>% arrange(cv_rmse)

# AJUSTE oct-2026 (A9): en la corrida anterior el mejor quedó en mtry = 14 y
# min.node.size = 20, los DOS en el borde de la malla. Si el óptimo queda en el
# borde no se puede decir que se encontró, solo que la malla se acabó. Así que
# si pasa eso se amplía una vez hacia ese lado y se vuelve a escoger.
avisar_borde <- function(valor, malla, nombre) {
  if (valor == max(malla)) {
    cat("Ojo:", nombre, "=", valor, "quedó en el borde SUPERIOR de la malla\n"); return(TRUE)}
  if (valor == min(malla)) {
    cat("Ojo:", nombre, "=", valor, "quedó en el borde INFERIOR de la malla\n"); return(TRUE)}
  FALSE}
if (any(!is.na(tabla_tuning_rf$cv_rmse))) {
  mejor_rf_ini <- tabla_tuning_rf %>% filter(!is.na(cv_rmse)) %>% slice(1)
  borde_mtry <- mejor_rf_ini$mtry == max(grid_rf$mtry)
  borde_node <- mejor_rf_ini$min_node_size == max(grid_rf$min.node.size)
  if (borde_mtry || borde_node) {
    cat("\nEl mejor Random Forest quedó en el borde de la malla, se amplía una vez:\n")
    grid_rf_extra <- expand.grid(
      mtry = unique(c(mejor_rf_ini$mtry, if (borde_mtry) round(mejor_rf_ini$mtry * 1.5))),
      min.node.size = unique(c(mejor_rf_ini$min_node_size, if (borde_node) mejor_rf_ini$min_node_size * 2))) %>%
      anti_join(tabla_tuning_rf %>% select(mtry, min.node.size = min_node_size), by = c("mtry", "min.node.size"))
    for (j in seq_len(nrow(grid_rf_extra))) {
      cv_rmse_j <- evaluar_combo_rf(grid_rf_extra$mtry[j], grid_rf_extra$min.node.size[j])
      cat("Combinación RF extra", j, "| mtry =", grid_rf_extra$mtry[j], "| min.node.size =",
          grid_rf_extra$min.node.size[j], "| CV-RMSE:", round(cv_rmse_j, 4), "\n")
      tabla_tuning_rf <- bind_rows(tabla_tuning_rf, tibble(
        combinacion = max(tabla_tuning_rf$combinacion) + 1,
        mtry = grid_rf_extra$mtry[j],
        min_node_size = grid_rf_extra$min.node.size[j],
        cv_rmse = cv_rmse_j))}
    tabla_tuning_rf <- tabla_tuning_rf %>% arrange(cv_rmse)}
  mejor_rf_fin <- tabla_tuning_rf %>% filter(!is.na(cv_rmse)) %>% slice(1)
  invisible(avisar_borde(mejor_rf_fin$mtry, tabla_tuning_rf$mtry, "mtry"))
  invisible(avisar_borde(mejor_rf_fin$min_node_size, tabla_tuning_rf$min_node_size, "min.node.size"))}
write.csv(tabla_tuning_rf, file.path(salidas, "05_modelos", "tuning_random_forest.csv"), row.names = FALSE)
saveRDS(tabla_tuning_rf, file.path(salidas, "08_objetos", "tuning_random_forest.rds"))
mostrar_tabla(tabla_tuning_rf, "Resultados de la búsqueda de hiperparámetros Random Forest")

mtry_final_rf <- mtry_base_rf
min_node_final_rf <- 20
if (any(!is.na(tabla_tuning_rf$cv_rmse))) {
  mejor_combo_rf <- tabla_tuning_rf %>% filter(!is.na(cv_rmse)) %>% slice(1)
  mtry_final_rf <- mejor_combo_rf$mtry
  min_node_final_rf <- mejor_combo_rf$min_node_size
  cat("\nMejor combinación Random Forest (combinación", mejor_combo_rf$combinacion, "): mtry =",
      mtry_final_rf, "| min.node.size =", min_node_final_rf, "\n")
} else {
  message("AVISO: todas las combinaciones del tuning de Random Forest fallaron; se usan valores por defecto.")}
# Rango del CV-RMSE en la malla: si es pequeño, confirma lo que dijo la tutora,
# RF casi no se mueve con estos hiperparámetros.
rango_cv_rmse_rf <- diff(range(tabla_tuning_rf$cv_rmse, na.rm = TRUE))
cat("Rango del CV-RMSE entre combinaciones de Random Forest:", round(rango_cv_rmse_rf, 4), "\n")

# 14.0.1 Curvas de validación Random Forest: CV-RMSE vs. mtry y vs. min.node.size
graf_val_rf_mtry <- tabla_tuning_rf %>%
  filter(!is.na(cv_rmse)) %>%
  ggplot(aes(x = mtry, y = cv_rmse, color = factor(min_node_size))) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.4) +
  labs(
    title = "Curva de validación — Random Forest (mtry)",
    subtitle = "RMSE de validación cruzada de 5 partes por combinación de hiperparámetros",
    x = "mtry (variables candidatas por división)",
    y = "RMSE promedio de validación cruzada",
    color = "min.node.size") +
  tema_base
guardar_grafico(graf_val_rf_mtry, "curva_validacion_rf_mtry.png", carpeta = "05_modelos")
graf_val_rf_nodesize <- tabla_tuning_rf %>%
  filter(!is.na(cv_rmse)) %>%
  ggplot(aes(x = min_node_size, y = cv_rmse, color = factor(mtry))) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.4) +
  labs(
    title = "Curva de validación — Random Forest (min.node.size)",
    subtitle = "RMSE de validación cruzada de 5 partes por combinación de hiperparámetros",
    x = "min.node.size (tamaño mínimo del nodo terminal)",
    y = "RMSE promedio de validación cruzada",
    color = "mtry") +
  tema_base
guardar_grafico(graf_val_rf_nodesize, "curva_validacion_rf_min_node_size.png", carpeta = "05_modelos")

# 14.0.2 Curva de error Random Forest: error OOB vs. número de árboles.
# El OOB ya es como una validación cruzada "gratis" (cada árbol se evalúa con
# lo que no usó), así que aquí no hace falta repetir CV a mano.
secuencia_num_trees_rf <- c(50, 100, 150, 200, 300, 400, 500, 800)
curva_num_trees_rf <- purrr::map_dfr(secuencia_num_trees_rf, function(nt) {
  fit_nt <- tryCatch(
    ranger::ranger(
      punt_global ~ .,
      data = df_train_ranger,
      num.trees = nt,
      mtry = mtry_final_rf,
      min.node.size = min_node_final_rf,
      num.threads = num_threads,
      seed = 123),
    error = function(e) NULL)
  tibble(
    num_trees = nt,
    oob_rmse = if (!is.null(fit_nt)) sqrt(fit_nt$prediction.error) else NA_real_)})
write.csv(curva_num_trees_rf, file.path(salidas, "05_modelos", "curva_error_rf_num_trees.csv"), row.names = FALSE)
mostrar_tabla(curva_num_trees_rf, "Error OOB de Random Forest según número de árboles")
graf_curva_num_trees_rf <- curva_num_trees_rf %>%
  filter(!is.na(oob_rmse)) %>%
  ggplot(aes(x = num_trees, y = oob_rmse)) +
  geom_line(color = colores_tesis["morado"], linewidth = 1.1) +
  geom_point(color = colores_tesis["morado"], size = 2.6) +
  labs(
    title = "Curva de error — Random Forest",
    subtitle = "Error OOB (out-of-bag) según el número de árboles",
    x = "Número de árboles (num.trees)",
    y = "RMSE OOB") +
  tema_base
guardar_grafico(graf_curva_num_trees_rf, "curva_error_rf_num_trees.png", carpeta = "05_modelos")
num_trees_final_rf <- 300
if (nrow(filter(curva_num_trees_rf, !is.na(oob_rmse))) > 0) {
  # Me quedo con el menor num.trees que ya esté a menos de 1% del mínimo,
  # no tiene sentido inflar el bosque por centésimas.
  oob_min_rf <- min(curva_num_trees_rf$oob_rmse, na.rm = TRUE)
  candidatos_nt_rf <- curva_num_trees_rf %>%
    filter(!is.na(oob_rmse), oob_rmse <= oob_min_rf * 1.01) %>%
    arrange(num_trees)
  if (nrow(candidatos_nt_rf) > 0) num_trees_final_rf <- candidatos_nt_rf$num_trees[1]}
cat("num.trees final seleccionado para Random Forest:", num_trees_final_rf, "\n")

modelo_ranger <- tryCatch(
  ranger::ranger(
    punt_global ~ .,
    data = df_train_ranger,
    num.trees = num_trees_final_rf,
    mtry = mtry_final_rf,
    min.node.size = min_node_final_rf,
    importance = "permutation",
    num.threads = num_threads,
    seed = 123
  ),
  error = function(e) {
    message("Ranger no pudo entrenarse: ", e$message)
    NULL
  }
)
if (!is.null(modelo_ranger)) {
  pred_ranger <- predict(modelo_ranger, data = df_test_ranger)$predictions
  resultados_modelos <- bind_rows(resultados_modelos, metricas(test_y, pred_ranger, "Ranger RF"))
}

# XGBoost: matrices base para tuning y entrenamiento final
dtrain <- xgboost::xgb.DMatrix(as.matrix(train_x), label = train_y)
dtest <- xgboost::xgb.DMatrix(as.matrix(test_x), label = test_y)
obtener_best_nrounds <- function(cv_obj, default_nrounds = 200) {
  if (is.null(cv_obj)) return(default_nrounds)
  if (!is.null(cv_obj$best_iteration) && length(cv_obj$best_iteration) > 0) {
    if (!is.na(cv_obj$best_iteration) && cv_obj$best_iteration > 0) {
      return(as.integer(cv_obj$best_iteration))
    }
  }
  if (!is.null(cv_obj$evaluation_log)) {
    eval_log <- as.data.frame(cv_obj$evaluation_log)
    if ("test_rmse_mean" %in% names(eval_log)) {
      idx <- which.min(eval_log$test_rmse_mean)
      if (length(idx) > 0 && !is.na(idx)) return(as.integer(idx))   }}
  default_nrounds}

# 14.1 TUNING DE HIPERPARÁMETROS XGBOOST (random search acotado)

cat("\n===== TUNING DE HIPERPARÁMETROS XGBOOST =====\n")
set.seed(123)
# AJUSTE oct-2026 (A9): dos cosas que salieron en la revisión.
#  1. max_depth = 8 "ganó" porque era el máximo de la malla, y la curva de
#     validación mostraba que 9 y 10 seguían bajando el CV-RMSE. Se agrega 10.
#  2. El tope de 500 rondas era el que mandaba (early stopping nunca se
#     activó). Se sube a 1000 y se deja que el early stopping decida.
# Ojo: esto hace la sección más lenta, paciencia.
nrounds_max_tuning <- 1000
grid_xgb_completo <- expand.grid(
  eta = c(0.03, 0.05, 0.08),
  max_depth = c(4, 6, 8, 10),
  min_child_weight = c(3, 5, 8),
  subsample = c(0.7, 0.8),
  colsample_bytree = c(0.7, 0.8))
n_candidatos <- min(12, nrow(grid_xgb_completo))
grid_xgb <- grid_xgb_completo[sample(seq_len(nrow(grid_xgb_completo)), n_candidatos), ]
grid_xgb <- as_tibble(grid_xgb)

resultados_tuning <- vector("list", nrow(grid_xgb))
for (i in seq_len(nrow(grid_xgb))) {
  params_i <- list(
    objective = "reg:squarederror",
    eta = grid_xgb$eta[i],
    max_depth = grid_xgb$max_depth[i],
    min_child_weight = grid_xgb$min_child_weight[i],
    subsample = grid_xgb$subsample[i],
    colsample_bytree = grid_xgb$colsample_bytree[i],
    eval_metric = "rmse"  )
  set.seed(123)
  cv_i <- tryCatch(
    xgboost::xgb.cv(
      params = params_i,
      data = dtrain,
      nrounds = nrounds_max_tuning,
      nfold = 5,
      early_stopping_rounds = 25,
      verbose = 0 ),
    error = function(e) {
      message("Combinación ", i, " falló: ", e$message)
      NULL} )
  if (!is.null(cv_i)) {
    best_rmse_i <- min(cv_i$evaluation_log$test_rmse_mean)
    best_iter_i <- obtener_best_nrounds(cv_i, default_nrounds = 200)
  } else {
    best_rmse_i <- NA_real_
    best_iter_i <- NA_integer_ }
  resultados_tuning[[i]] <- tibble(
    combinacion = i,
    eta = grid_xgb$eta[i],
    max_depth = grid_xgb$max_depth[i],
    min_child_weight = grid_xgb$min_child_weight[i],
    subsample = grid_xgb$subsample[i],
    colsample_bytree = grid_xgb$colsample_bytree[i],
    mejor_nrounds = best_iter_i,
    cv_rmse = best_rmse_i )
  cat("Combinación", i, "de", nrow(grid_xgb), "| CV-RMSE:", round(best_rmse_i, 4), "\n")}
tabla_tuning_xgb <- bind_rows(resultados_tuning) %>% arrange(cv_rmse)
write.csv(tabla_tuning_xgb, file.path(salidas, "05_modelos", "tuning_xgboost.csv"), row.names = FALSE)
saveRDS(tabla_tuning_xgb, file.path(salidas, "08_objetos", "tuning_xgboost.rds"))
mostrar_tabla(tabla_tuning_xgb, "Resultados de la búsqueda de hiperparámetros XGBoost")

params_xgb <- list(
  objective = "reg:squarederror",
  eta = 0.05,
  max_depth = 6,
  min_child_weight = 5,
  subsample = 0.8,
  colsample_bytree = 0.8,
  eval_metric = "rmse")
best_nrounds <- 200
if (any(!is.na(tabla_tuning_xgb$cv_rmse))) {
  mejor_combo <- tabla_tuning_xgb %>% filter(!is.na(cv_rmse)) %>% slice(1)
  params_xgb <- list(
    objective = "reg:squarederror",
    eta = mejor_combo$eta,
    max_depth = mejor_combo$max_depth,
    min_child_weight = mejor_combo$min_child_weight,
    subsample = mejor_combo$subsample,
    colsample_bytree = mejor_combo$colsample_bytree,
    eval_metric = "rmse"  )
  best_nrounds <- mejor_combo$mejor_nrounds
  cat("\nMejor combinación seleccionada (combinación", mejor_combo$combinacion, "):\n")
  print(params_xgb)
  cat("nrounds:", best_nrounds, "\n")
  # AJUSTE oct-2026 (A9): avisos de borde, para no vender como "óptimo" lo que
  # en realidad es el límite de lo que se probó
  invisible(avisar_borde(params_xgb$max_depth, grid_xgb_completo$max_depth, "max_depth"))
  invisible(avisar_borde(params_xgb$eta, grid_xgb_completo$eta, "eta"))
  if (best_nrounds >= nrounds_max_tuning) {
    cat("Ojo: nrounds llegó al tope de", nrounds_max_tuning, "-> el early stopping no se activó\n")
  } else {
    cat("Early stopping activado: el CV-RMSE dejó de mejorar en la ronda", best_nrounds, "\n")}
} else {
  message("AVISO: todas las combinaciones del tuning fallaron; se usan los hiperparámetros por defecto.")}

modelo_xgb <- tryCatch(
  xgboost::xgb.train(
    params = params_xgb,
    data = dtrain,
    nrounds = best_nrounds,
    verbose = 0),
  error = function(e) {
    message("XGBoost falló: ", e$message)
    NULL})
pred_xgb <- rep(NA_real_, length(test_y))
if (!is.null(modelo_xgb)) {
  pred_xgb <- predict(modelo_xgb, dtest)
  resultados_modelos <- bind_rows(
    resultados_modelos,
    metricas(test_y, pred_xgb, "XGBoost"))}


# 14.2 DIAGNÓSTICO SESGO-VARIANZA: RMSE TRAIN VS. TEST XGBoost

comparacion_train_test_xgb <- NULL
if (!is.null(modelo_xgb)) {
  pred_xgb_train <- predict(modelo_xgb, dtrain)
  comparacion_train_test_xgb <- bind_rows(
    metricas(train_y, pred_xgb_train, "XGBoost (train)"),
    metricas(test_y, pred_xgb, "XGBoost (test)") )
  rmse_train_xgb <- comparacion_train_test_xgb$RMSE[comparacion_train_test_xgb$modelo == "XGBoost (train)"]
  rmse_test_xgb <- comparacion_train_test_xgb$RMSE[comparacion_train_test_xgb$modelo == "XGBoost (test)"]
  brecha_relativa <- (rmse_test_xgb - rmse_train_xgb) / rmse_train_xgb
  interpretacion_sesgo_varianza <- case_when(
    brecha_relativa < 0.05 ~ "Brecha muy pequeña entre train y test: señal de SUB-AJUSTE (el modelo tampoco ajusta bien lo que ya vio; considerar hiperparámetros menos conservadores: menor min_child_weight, mayor max_depth, más nrounds).",
    brecha_relativa > 0.20 ~ "Brecha grande entre train y test: señal de SOBRE-AJUSTE (el modelo memoriza el train pero no generaliza; considerar más regularización: mayor min_child_weight, menor max_depth, subsample/colsample más bajos).",
    TRUE ~ "Brecha moderada entre train y test: dentro de lo esperable para un modelo razonablemente ajustado; la compresión observada en el gráfico de predicción vs. observado responde principalmente al R² disponible, no a sub-ajuste ni sobre-ajuste."  )
  cat("\n===== DIAGNÓSTICO SESGO-VARIANZA XGBOOST (TRAIN VS. TEST) =====\n")
  mostrar_tabla(comparacion_train_test_xgb, "RMSE/MAE/R² de XGBoost: entrenamiento vs. prueba")
  cat("Brecha relativa (test-train)/train:", sprintf("%.1f%%\n", 100 * brecha_relativa))
  cat("Interpretación automática:", interpretacion_sesgo_varianza, "\n")
  write.csv(
    comparacion_train_test_xgb,
    file.path(salidas, "05_modelos", "diagnostico_sesgo_varianza_xgb.csv"),
    row.names = FALSE)
  saveRDS(comparacion_train_test_xgb, file.path(salidas, "08_objetos", "comparacion_train_test_xgb.rds"))}

# 14.3 CURVAS DE VALIDACIÓN Y DE ERROR XGBOOST

cat("\n===== CURVAS DE VALIDACIÓN Y DE ERROR XGBOOST =====\n")

# 14.3.1 Curva de error: RMSE train vs. CV por ronda de boosting.
# La 14.2 solo compara el valor final; esta muestra en qué ronda se empieza
# a abrir la brecha.
set.seed(123)
cv_final_xgb <- tryCatch(
  xgboost::xgb.cv(
    params = params_xgb,
    data = dtrain,
    nrounds = max(best_nrounds * 2, 300),
    nfold = 5,
    early_stopping_rounds = 25,
    verbose = 0),
  error = function(e) {
    message("No se pudo recalcular la curva de error de XGBoost: ", e$message)
    NULL})
curva_error_xgb <- tibble()
if (!is.null(cv_final_xgb)) {
  curva_error_xgb <- as_tibble(cv_final_xgb$evaluation_log) %>%
    select(iter, train_rmse_mean, test_rmse_mean) %>%
    rename(cv_rmse_mean = test_rmse_mean)
  write.csv(curva_error_xgb, file.path(salidas, "05_modelos", "curva_error_xgb.csv"), row.names = FALSE)
  graf_curva_error_xgb <- curva_error_xgb %>%
    pivot_longer(cols = c(train_rmse_mean, cv_rmse_mean), names_to = "conjunto", values_to = "rmse") %>%
    mutate(conjunto = dplyr::recode(conjunto,
                                    train_rmse_mean = "Entrenamiento",
                                    cv_rmse_mean = "Validación cruzada (5 partes)")) %>%
    ggplot(aes(x = iter, y = rmse, color = conjunto)) +
    geom_line(linewidth = 1) +
    geom_vline(xintercept = best_nrounds, linetype = "dashed", color = colores_tesis["gris"]) +
    labs(
      title = "Curva de error — XGBoost",
      subtitle = "RMSE de entrenamiento vs. validación cruzada por ronda de boosting",
      x = "Ronda de boosting (nrounds)",
      y = "RMSE",
      color = NULL) +
    tema_base
  guardar_grafico(graf_curva_error_xgb, "curva_error_xgb_nrounds.png", carpeta = "05_modelos")
  saveRDS(curva_error_xgb, file.path(salidas, "08_objetos", "curva_error_xgb.rds"))}

# 14.3.2 Curvas de validación: muevo uno a la vez max_depth y min_child_weight
# y dejo lo demás fijo en lo que ganó la búsqueda aleatoria.
# Ojo para la sustentación: como punt_global es continua, aquí NO hay entropía
# (eso es de clasificación). XGBoost parte cada nodo por la mayor ganancia
# ("gain") en el error cuadrático, y estos dos parámetros controlan qué tan
# lejos llega esa partición.
calcular_curva_validacion_xgb <- function(nombre_param, valores) {
  purrr::map_dfr(valores, function(v) {
    params_v <- params_xgb
    params_v[[nombre_param]] <- v
    set.seed(123)
    # AJUSTE oct-2026: antes estas curvas se corrían con 300 rondas fijas,
    # distinto del modelo final, y no eran comparables. Ahora usan el mismo
    # tope que el modelo final (con early stopping).
    cv_v <- tryCatch(
      xgboost::xgb.cv(
        params = params_v,
        data = dtrain,
        nrounds = max(best_nrounds, 300),
        nfold = 5,
        early_stopping_rounds = 25,
        verbose = 0),
      error = function(e) NULL)
    if (is.null(cv_v)) {
      return(tibble(valor = v, train_rmse = NA_real_, cv_rmse = NA_real_))}
    mejor_iter_v <- obtener_best_nrounds(cv_v, default_nrounds = 200)
    log_v <- as.data.frame(cv_v$evaluation_log)
    fila_v <- log_v[min(mejor_iter_v, nrow(log_v)), ]
    tibble(valor = v, train_rmse = fila_v$train_rmse_mean, cv_rmse = fila_v$test_rmse_mean)})}

graficar_curva_validacion_xgb <- function(datos, valor_final, nombre_x, nombre_archivo, titulo) {
  datos %>%
    filter(!is.na(cv_rmse)) %>%
    pivot_longer(cols = c(train_rmse, cv_rmse), names_to = "conjunto", values_to = "rmse") %>%
    mutate(conjunto = dplyr::recode(conjunto, train_rmse = "Entrenamiento", cv_rmse = "Validación cruzada (5 partes)")) %>%
    ggplot(aes(x = valor, y = rmse, color = conjunto)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2.4) +
    geom_vline(xintercept = valor_final, linetype = "dashed", color = colores_tesis["gris"]) +
    labs(
      title = titulo,
      subtitle = "RMSE de entrenamiento vs. RMSE de validación cruzada",
      x = nombre_x,
      y = "RMSE",
      color = NULL) +
    tema_base}

valores_max_depth <- c(2, 3, 4, 5, 6, 7, 8, 9, 10)
curva_val_max_depth <- calcular_curva_validacion_xgb("max_depth", valores_max_depth)
write.csv(curva_val_max_depth, file.path(salidas, "05_modelos", "curva_validacion_xgb_max_depth.csv"), row.names = FALSE)
graf_val_max_depth <- graficar_curva_validacion_xgb(
  curva_val_max_depth, params_xgb$max_depth, "max_depth",
  "curva_validacion_xgb_max_depth.png", "Curva de validación — XGBoost (max_depth)")
guardar_grafico(graf_val_max_depth, "curva_validacion_xgb_max_depth.png", carpeta = "05_modelos")

valores_min_child_weight <- c(1, 2, 3, 5, 8, 12, 20, 30)
curva_val_min_child <- calcular_curva_validacion_xgb("min_child_weight", valores_min_child_weight)
write.csv(curva_val_min_child, file.path(salidas, "05_modelos", "curva_validacion_xgb_min_child_weight.csv"), row.names = FALSE)
graf_val_min_child <- graficar_curva_validacion_xgb(
  curva_val_min_child, params_xgb$min_child_weight, "min_child_weight",
  "curva_validacion_xgb_min_child_weight.png", "Curva de validación — XGBoost (min_child_weight)")
guardar_grafico(graf_val_min_child, "curva_validacion_xgb_min_child_weight.png", carpeta = "05_modelos")

mostrar_tabla(curva_val_max_depth, "Curva de validación XGBoost — max_depth")
mostrar_tabla(curva_val_min_child, "Curva de validación XGBoost — min_child_weight")
saveRDS(
  list(curva_val_max_depth = curva_val_max_depth, curva_val_min_child = curva_val_min_child),
  file.path(salidas, "08_objetos", "curvas_validacion_xgb.rds"))

# 14.3.3 Resumen de validación cruzada por modelo (sale directo como Tabla 3)
tabla_resumen_cv <- tibble(
  modelo = c("Regresión lineal", "Ridge", "Lasso", "Random Forest (Ranger)", "XGBoost"),
  hiperparametros_ajustados = c(
    "Ninguno (no tiene hiperparámetros de regularización)",
    "lambda",
    "lambda",
    "mtry, min.node.size (num.trees por curva de error OOB)",
    "eta, max_depth, min_child_weight, subsample, colsample_bytree"),
  metodo_validacion = c(
    "No aplica",
    "Validación cruzada de 5 partes (cv.glmnet)",
    "Validación cruzada de 5 partes (cv.glmnet)",
    "Validación cruzada de 5 partes (malla de 9 combinaciones, ampliada una vez si el óptimo queda en el borde, sección 14.0) + error OOB para num.trees",
    paste0("Validación cruzada de 5 partes (xgb.cv): búsqueda aleatoria de 12 combinaciones sobre una malla de ",
           nrow(grid_xgb_completo), ", con early stopping (tope ", nrounds_max_tuning,
           " rondas) (14.1) + curvas de validación para max_depth y min_child_weight (14.3.2)")))
write.csv(tabla_resumen_cv, file.path(salidas, "09_tablas", "resumen_validacion_cruzada_por_modelo.csv"), row.names = FALSE)
mostrar_tabla(tabla_resumen_cv, "Resumen de validación cruzada por modelo")
saveRDS(tabla_resumen_cv, file.path(salidas, "08_objetos", "resumen_validacion_cruzada_por_modelo.rds"))

resultados_modelos <- resultados_modelos %>% arrange(RMSE)
mostrar_tabla(resultados_modelos, "Comparación de modelos predictivos")
write.csv(resultados_modelos, file.path(salidas, "05_modelos", "resultados_modelos.csv"), row.names = FALSE)
saveRDS(resultados_modelos, file.path(salidas, "08_objetos", "resultados_modelos.rds"))
if (nrow(resultados_modelos) > 0) {
  graf_modelos_rmse <- resultados_modelos %>%
    mutate(modelo = fct_reorder(modelo, RMSE)) %>%
    ggplot(aes(x = modelo, y = RMSE, fill = modelo)) +
    geom_col(alpha = .9) +
    coord_flip() +
    labs(
      title = "Comparación de modelos predictivos",
      subtitle = "Menor RMSE indica mejor desempeño",
      x = "Modelo",
      y = "RMSE" ) +
    tema_base +
    guides(fill = "none")
  guardar_grafico(graf_modelos_rmse, "comparacion_modelos_rmse.png", carpeta = "05_modelos")
}

# 15. PREDICCIONES Y DIAGNÓSTICO

predicciones_test <- tibble(
  real = test_y,
  pred_lm = pred_lm,
  pred_ridge = pred_ridge,
  pred_lasso = pred_lasso,
  pred_xgb = pred_xgb)
if (!is.null(pred_ranger)) {
  predicciones_test$pred_ranger <- pred_ranger}
write.csv(predicciones_test, file.path(salidas, "05_modelos", "predicciones_test.csv"), row.names = FALSE)
saveRDS(predicciones_test, file.path(salidas, "08_objetos", "predicciones_test.rds"))
if (!all(is.na(pred_xgb))) {
  graf_pred_real_xgb <- ggplot(predicciones_test, aes(x = real, y = pred_xgb)) +
    geom_point(alpha = .18, color = colores_tesis["azul"]) +
    geom_abline(slope = 1, intercept = 0, color = colores_tesis["rojo"], linewidth = 1) +
    labs(
      title = "Predicción vs. valor observado — XGBoost",
      x = "Puntaje observado",
      y = "Puntaje predicho" ) +
    tema_base
  guardar_grafico(graf_pred_real_xgb, "prediccion_vs_observado_xgb.png", carpeta = "05_modelos")
  residuales_xgb <- tibble(
    real = test_y,
    pred = pred_xgb,
    residual = test_y - pred_xgb )
  graf_residuales_xgb <- ggplot(residuales_xgb, aes(x = pred, y = residual)) +
    geom_point(alpha = .18, color = colores_tesis["gris"]) +
    geom_hline(yintercept = 0, color = colores_tesis["rojo"], linewidth = 1) +
    labs(
      title = "Residuales del modelo XGBoost",
      x = "Puntaje predicho",
      y = "Residual" ) +
    tema_base
  guardar_grafico(graf_residuales_xgb, "residuales_xgb.png", carpeta = "05_modelos")
  
  # AJUSTE oct-2026 (A10): error por deciles del puntaje observado. En el
  # documento se habla de que el modelo sobreestima el decil bajo (~32 puntos)
  # y subestima el alto (~25), pero ese número no salía de este pipeline. Ahora
  # sale aquí y queda trazable. Esto funciona para mostrar la "compresión hacia
  # la media" que es normal cuando el R² está lejos de 1.
  error_deciles_xgb <- residuales_xgb %>%
    mutate(decil_real = dplyr::ntile(real, 10)) %>%
    group_by(decil_real) %>%
    summarise(
      n = n(),
      real_min = min(real),
      real_max = max(real),
      real_promedio = mean(real),
      pred_promedio = mean(pred),
      error_medio = mean(pred - real),   # positivo = sobreestima
      rmse = sqrt(mean((pred - real)^2)),
      .groups = "drop")
  write.csv(error_deciles_xgb, file.path(salidas, "05_modelos", "error_por_decil_xgb.csv"), row.names = FALSE)
  mostrar_tabla(error_deciles_xgb, "Error de XGBoost por decil del puntaje observado (positivo = sobreestima)")}

# 16. SHAP SOBRE TEST
cat("\n===== SHAP SOBRE TEST =====\n")
imp_df <- tibble()
imp_familias <- tibble()
idx_shap <- integer(0)
importancia_xgb <- NULL
if (!is.null(modelo_xgb)) {
  set.seed(123)
  n_shap_max <- 20000
  n_shap <- min(n_shap_max, nrow(test_x))
  idx_shap <- sample(seq_len(nrow(test_x)), size = n_shap)
  test_x_shap <- test_x[idx_shap, , drop = FALSE]
  dtest_shap <- xgboost::xgb.DMatrix(as.matrix(test_x_shap))
  shap_values <- predict(modelo_xgb, dtest_shap, predcontrib = TRUE)
  shap_values <- shap_values[, -ncol(shap_values), drop = FALSE]
  imp <- colMeans(abs(shap_values))
  imp_df <- tibble(
    variable = colnames(test_x_shap),
    importance = as.numeric(imp)  ) %>%
    arrange(desc(importance))
  # AJUSTE oct-2026 (A8): el mapa anterior tenía tres fallas que movían H2:
  #  - "inst_|prgm" se tragaba estu_inst_departamento y estu_prgm_departamento,
  #    que son territoriales, e inflaba la familia institucional.
  #  - "nse" mandaba estu_nse_ies (índice de la INSTITUCIÓN) a hogar.
  #  - pago de matrícula y horas de trabajo quedaban como "individuales" cuando
  #    en la Tabla 1 son económicas y laborales; hacinamiento (compartebaño) y
  #    zona de residencia quedaban en "Otras".
  # Ojo con el ORDEN del case_when: lo territorial va primero a propósito para
  # que "departamento" gane antes que "inst_" o "prgm". Este mapa es el que
  # manda: la Tabla 1 del documento se arma con mapa_familias_shap.csv.
  clasificar_familia <- function(variable) {
    case_when(
      str_detect(variable, "departamento|depto|municipio|pais_reside|areareside|exterior") ~ "Territoriales",
      str_detect(variable, "nse_ies|^inst_|prgm|nucleo|gruporeferencia|metodo") ~ "Académicas e institucionales",
      str_detect(variable, "inse|nse_individual|estrato|fami_educacion|fami_ocupacion|fami_trabajo|cuantoscompartebano") ~ "Socioeconómicas y hogar",
      str_detect(variable, "internet|computador|lavadora|automovil|motocicleta|serviciotv|consola|horno") ~ "Bienes y tecnología",
      str_detect(variable, "pagomatricula|horassemanatrabaja") ~ "Económicas y laborales",
      # AJUSTE oct-2026: edad viene nueva de la limpieza (L1), es individual
      str_detect(variable, "^edad$|genero|nacionalidad|estadocivil|semestrecursa|repite|tituloobtenidobachiller") ~ "Individuales y trayectoria",
      TRUE ~ "Otras"  ) }
  imp_df <- imp_df %>%
    mutate(familia = clasificar_familia(variable))
  # AJUSTE oct-2026 (A21): pilas con esto, es lo que sostiene H2. Antes se
  # sumaba el |SHAP| promedio de cada dummy, y como |a + b| <= |a| + |b|, una
  # familia con 27 columnas salía más pesada que una con 9 solo por tener más
  # columnas. Lo correcto: sumar los SHAP del grupo POR ESTUDIANTE (SHAP es
  # aditivo, eso es el aporte del grupo completo) y después promediar el valor
  # absoluto. Se reportan columnas y variables originales por aparte.
  agregar_shap <- function(grupo_col) {
    idx <- split(seq_along(grupo_col), grupo_col)
    tibble(
      grupo = names(idx),
      importancia_total = map_dbl(idx, ~ mean(abs(rowSums(shap_values[, .x, drop = FALSE])))),
      n_columnas = map_int(idx, length),
      n_variables = map_int(idx, ~ n_distinct(str_remove(colnames(test_x_shap)[.x], "\\..*$")))) %>%
      mutate(participacion = importancia_total / sum(importancia_total)) %>%
      arrange(desc(importancia_total))}
  familia_col <- clasificar_familia(colnames(test_x_shap))
  imp_familias <- agregar_shap(familia_col) %>%
    rename(familia = grupo) %>%
    mutate(importancia_promedio = importancia_total / n_variables)   # por variable original, no por dummy
  write.csv(imp_df, file.path(salidas, "06_shap", "shap_variables.csv"), row.names = FALSE)
  write.csv(imp_familias, file.path(salidas, "06_shap", "shap_familias.csv"), row.names = FALSE)
  mostrar_tabla(head(imp_df, 25), "Top 25 variables SHAP")
  mostrar_tabla(imp_familias, "Importancia SHAP por familia de variables")
  
  # Mapa variable original -> familia, para armar la Tabla 1 con lo mismo que
  # usó el código (se corta el nombre en el punto que pone dummyVars)
  mapa_familias_shap <- imp_df %>%
    mutate(variable_original = str_remove(variable, "\\..*$")) %>%
    distinct(variable_original, familia) %>%
    arrange(familia, variable_original)
  write.csv(mapa_familias_shap, file.path(salidas, "06_shap", "mapa_familias_shap.csv"), row.names = FALSE)
  if (mostrar_en_pantalla) {
    cat("\n-----  Mapa variable -> familia usado en SHAP (para la Tabla 1)  -----\n")
    print(as.data.frame(mapa_familias_shap))}
  
  # Prueba directa de H2: entorno (hogar + bienes + territorio + económicas)
  # contra lo estrictamente individual. Lo institucional se reporta aparte
  # porque H2 no lo menciona, y mezclarlo con cualquiera de los dos lados
  # sería acomodar la hipótesis.
  # AJUSTE oct-2026 (A21): el bloque también se agrega por estudiante, no
  # sumando las participaciones de las familias (por la misma razón de arriba).
  bloque_col <- case_when(
    familia_col %in% c("Socioeconómicas y hogar", "Bienes y tecnología", "Territoriales", "Económicas y laborales") ~ "Entorno (H2)",
    familia_col == "Individuales y trayectoria" ~ "Individual (H2)",
    familia_col == "Académicas e institucionales" ~ "Institucional (aparte)",
    TRUE ~ "Otras")
  h2_resumen <- agregar_shap(bloque_col) %>%
    rename(bloque_h2 = grupo)
  write.csv(h2_resumen, file.path(salidas, "06_shap", "h2_entorno_vs_individual.csv"), row.names = FALSE)
  mostrar_tabla(h2_resumen, "H2: participación SHAP del entorno vs. lo individual")
  saveRDS(imp_df, file.path(salidas, "08_objetos", "imp_df.rds"))
  saveRDS(imp_familias, file.path(salidas, "08_objetos", "imp_familias.rds"))
  saveRDS(idx_shap, file.path(salidas, "08_objetos", "idx_muestra_shap.rds"))
  if (nrow(imp_df) > 0) {
    graf_shap_top <- imp_df %>%
      slice_max(importance, n = 25) %>%
      mutate(variable = fct_reorder(variable, importance)) %>%
      ggplot(aes(x = variable, y = importance, fill = familia)) +
      geom_col() +
      coord_flip() +
      labs(
        title = "Top 25 variables según importancia SHAP",
        subtitle = paste0("Muestra reproducible del test: n = ", length(idx_shap)),
        x = "Variable",
        y = "Importancia media absoluta SHAP"  ) +
      tema_base
    guardar_grafico(graf_shap_top, "shap_top_25_variables.png", carpeta = "06_shap", width = 10, height = 7) }
  if (nrow(imp_familias) > 0) {
    graf_shap_familias <- imp_familias %>%
      ggplot(aes(x = fct_reorder(familia, importancia_total), y = importancia_total, fill = familia)) +
      geom_col(alpha = .9) +
      coord_flip() +
      labs(
        title = "Importancia SHAP agregada por familias de variables",
        subtitle = "Operacionalización de la hipótesis secundaria",
        x = "Familia de variables",
        y = "Importancia SHAP agregada"    ) +
      tema_base +
      guides(fill = "none")
    guardar_grafico(graf_shap_familias, "shap_familias.png", carpeta = "06_shap", width = 10, height = 6) }
  importancia_xgb <- xgboost::xgb.importance(
    feature_names = colnames(train_x),
    model = modelo_xgb )
  write.csv(
    importancia_xgb,
    file.path(salidas, "06_shap", "importancia_xgb_gain_cover_frequency.csv"),
    row.names = FALSE)}
if (!is.null(modelo_ranger)) {
  importancia_ranger <- tibble(
    variable = names(modelo_ranger$variable.importance),
    importance = as.numeric(modelo_ranger$variable.importance) ) %>%
    arrange(desc(importance))
  write.csv(
    importancia_ranger,
    file.path(salidas, "05_modelos", "importancia_ranger_permutation.csv"),
    row.names = FALSE )
} else {
  importancia_ranger <- NULL}

# AJUSTE oct-2026 (A10): consistencia entre las tres medidas de importancia.
# El documento dice que cinco variables quedan en el top 7 de SHAP, gain y
# permutación; eso no salía en ninguna tabla. Ahora queda calculado.
if (nrow(imp_df) > 0 && !is.null(importancia_xgb) && !is.null(importancia_ranger)) {
  consistencia_importancia <- imp_df %>%
    transmute(variable, rank_shap = rank(-importance, ties.method = "min")) %>%
    full_join(
      as_tibble(importancia_xgb) %>% transmute(variable = Feature, rank_gain = rank(-Gain, ties.method = "min")),
      by = "variable") %>%
    full_join(
      importancia_ranger %>% transmute(variable, rank_permutacion = rank(-importance, ties.method = "min")),
      by = "variable") %>%
    mutate(
      en_top7_los_tres = rank_shap <= 7 & rank_gain <= 7 & rank_permutacion <= 7,
      rank_promedio = (rank_shap + rank_gain + rank_permutacion) / 3) %>%
    arrange(rank_promedio)
  write.csv(consistencia_importancia, file.path(salidas, "06_shap", "consistencia_shap_gain_permutacion.csv"), row.names = FALSE)
  mostrar_tabla(head(consistencia_importancia, 15), "Consistencia de importancia: SHAP vs. gain vs. permutación")
  cat("Variables en el top 7 de las tres medidas:",
      paste(consistencia_importancia$variable[consistencia_importancia$en_top7_los_tres %in% TRUE], collapse = ", "), "\n")}

# 17. EQUIDAD PREDICTIVA
cat("\n===== EQUIDAD PREDICTIVA =====\n")
df_eval <- tibble(
  real = test_y,
  pred = pred_xgb,
  error = pred - real,
  abs_error = abs(pred - real))
# AJUSTE oct-2026: los grupos se toman de test_meta_raw (sin imputar), porque
# fami_estratovivienda e inse_cuartil ya no están entre las columnas del modelo
if ("estu_genero" %in% names(test_meta_raw)) df_eval$genero <- test_meta_raw$estu_genero
if ("fami_estratovivienda" %in% names(test_meta_raw)) df_eval$estrato <- test_meta_raw$fami_estratovivienda
if ("estrato_num" %in% names(test_meta_raw)) df_eval$estrato_num <- test_meta_raw$estrato_num

if ("estrato_grupo_psm" %in% names(test_meta_raw)) df_eval$estrato_grupo_psm <- test_meta_raw$estrato_grupo_psm
if ("inse_cuartil" %in% names(test_meta_raw)) df_eval$inse_cuartil <- test_meta_raw$inse_cuartil
if ("inse_imputado" %in% names(test_meta_raw)) df_eval$inse_imputado <- test_meta_raw$inse_imputado
# AJUSTE oct-2026 (A14): error según si comunicación escrita quedó en 0. Esto
# funciona para mostrar que parte de la sobreestimación del decil bajo no es
# culpa del modelo: a esos estudiantes el ICFES les promedia un 0 en el global.
if ("diag_escrita_cero" %in% names(test_meta_raw)) {
  df_eval$escrita_cero <- if_else(test_meta_raw$diag_escrita_cero %in% 1,
                                  "Comunicación escrita en 0", "Comunicación escrita calificada")}
calcular_bias <- function(df, grupo) {
  df %>%
    filter(!is.na(.data[[grupo]]), !is.na(pred)) %>%
    group_by(.data[[grupo]]) %>%
    summarise(
      n = n(),
      real_promedio = mean(real, na.rm = TRUE),
      pred_promedio = mean(pred, na.rm = TRUE),
      rmse = sqrt(mean((real - pred)^2, na.rm = TRUE)),
      mae = mean(abs(real - pred), na.rm = TRUE),
      error_medio = mean(error, na.rm = TRUE),
      rmse_pct_max_teorico = rmse / puntaje_maximo_teorico,
      mae_pct_max_teorico = mae / puntaje_maximo_teorico,
      .groups = "drop" ) %>%
    arrange(desc(rmse))}
bias_genero <- if ("genero" %in% names(df_eval)) calcular_bias(df_eval, "genero") else NULL
bias_estrato <- if ("estrato" %in% names(df_eval)) calcular_bias(df_eval, "estrato") else NULL
bias_estrato_num <- if ("estrato_num" %in% names(df_eval)) calcular_bias(df_eval, "estrato_num") else NULL
bias_estrato_grupo <- if ("estrato_grupo_psm" %in% names(df_eval)) calcular_bias(df_eval, "estrato_grupo_psm") else NULL
bias_inse_cuartil <- if ("inse_cuartil" %in% names(df_eval)) calcular_bias(df_eval, "inse_cuartil") else NULL
bias_inse_imputado <- if ("inse_imputado" %in% names(df_eval)) calcular_bias(df_eval, "inse_imputado") else NULL
bias_escrita_cero <- if ("escrita_cero" %in% names(df_eval)) calcular_bias(df_eval, "escrita_cero") else NULL
objetos_bias <- list(
  escrita_cero = bias_escrita_cero,
  genero = bias_genero,
  estrato = bias_estrato,
  estrato_num = bias_estrato_num,
  estrato_grupo = bias_estrato_grupo,
  inse_cuartil = bias_inse_cuartil,
  inse_imputado = bias_inse_imputado)
saveRDS(objetos_bias, file.path(salidas, "08_objetos", "objetos_bias.rds"))
for (nm in names(objetos_bias)) {
  obj <- objetos_bias[[nm]]
  if (!is.null(obj) && nrow(obj) > 0) {
    write.csv(obj, file.path(salidas, "07_equidad", paste0("bias_", nm, ".csv")), row.names = FALSE)
    mostrar_tabla(obj, paste("Equidad predictiva:", nm))
    nombre_grupo <- names(obj)[1]
    graf_bias <- obj %>%
      mutate(grupo = fct_reorder(as.factor(.data[[nombre_grupo]]), rmse)) %>%
      ggplot(aes(x = grupo, y = rmse, fill = rmse)) +
      geom_col(alpha = .9) +
      coord_flip() +
      scale_fill_gradient(low = colores_tesis["celeste"], high = colores_tesis["rojo"]) +
      labs(
        title = paste("RMSE por grupo:", nm),
        x = "Grupo",
        y = "RMSE"  ) +
      tema_base +
      guides(fill = "none")
    guardar_grafico(graf_bias, paste0("bias_rmse_", nm, ".png"), carpeta = "07_equidad", width = 9, height = 6)}}

# 17.1 VALIDACIÓN FUERA DEL TIEMPO: MODELO 2024 PROBADO EN LA COHORTE 2025
# Esto funciona para responder la pregunta del jurado de "¿y esto sirve para
# otros años?". Los modelos se entrenaron solo con 2024 y aquí se les pasa
# 2025, que nunca vieron. Pilas: a 2025 se le aplica TODO con parámetros de
# 2024 (cortes del INSE, medianas/modas, límites de winsorización, niveles de
# los factores y dummies). Si algo se aprendiera con 2025 ya no sería una
# validación limpia.
cat("\n===== VALIDACIÓN FUERA DEL TIEMPO (COHORTE 2025) =====\n")
archivo_2025 <- file.path(ruta, "data_limpia_2025.csv")
resultados_2025 <- NULL
calibracion_2025 <- NULL
bias_2025 <- list()
if (file.exists(archivo_2025) && !is.null(modelo_xgb)) {
  d25 <- data.table::fread(archivo_2025, encoding = "UTF-8", na.strings = na_icfes) %>%
    as_tibble() %>%
    janitor::clean_names() %>%
    mutate(across(where(is.character), ~ stringr::str_squish(.)))
  n_25_inicial <- nrow(d25)
  
  # mismo filtro INDIVIDUAL de la sección 2.2
  marca_ind_25 <- rep(FALSE, nrow(d25))
  if (!is.na(col_individual) && col_individual %in% names(d25)) {
    marca_ind_25 <- marca_ind_25 |
      (toupper(str_squish(as.character(d25[[col_individual]]))) == "INDIVIDUAL") %in% TRUE}
  if (!is.na(col_institucion) && col_institucion %in% names(d25)) {
    marca_ind_25 <- marca_ind_25 | is.na(d25[[col_institucion]])}
  d25 <- d25[!marca_ind_25, ]
  d25[[target]] <- suppressWarnings(as.numeric(d25[[target]]))
  d25 <- d25 %>% filter(!is.na(.data[[target]]))
  # AJUSTE oct-2026 (A11): mismo criterio de 2024 para los puntajes en cero
  n_cero_25 <- sum(d25[[target]] == 0)
  if (excluir_puntaje_cero) d25 <- d25 %>% filter(.data[[target]] > 0)
  cat("Registros 2025 con punt_global = 0:", n_cero_25,
      if (excluir_puntaje_cero) "(excluidos)\n" else "(conservados)\n")
  cat("Registros 2025:", n_25_inicial, "| excluidos INDIVIDUAL:", sum(marca_ind_25),
      "| usados en la validación:", nrow(d25), "\n")
  
  # OJO: el archivo 2025 del ICFES NO trae estu_nse_ies, y esa es de las
  # variables más pesadas del modelo. Si se deja así, se imputa la misma
  # mediana a todo el mundo y la validación sale castigada por un problema de
  # datos, no del modelo. Como es un índice de la institución, se recupera con
  # el valor que cada institución tenía en 2024 (sigue siendo un parámetro
  # aprendido en 2024). Instituciones nuevas en 2025 quedan NA y se imputan.
  # AJUSTE oct-2026, ojo con cómo se escribe esto en el documento: lo que se
  # verifica aquí es que el índice es constante DENTRO de cada institución en
  # 2024. Que no cambie entre 2024 y 2025 es un SUPUESTO, no algo comprobado.
  if ("estu_nse_ies" %in% names(d25) && all(is.na(d25$estu_nse_ies)) &&
      all(c("inst_cod_institucion", "estu_nse_ies") %in% names(data))) {
    mapa_nse_ies <- data %>%
      filter(!is.na(inst_cod_institucion), !is.na(estu_nse_ies)) %>%
      count(inst_cod_institucion, estu_nse_ies) %>%
      group_by(inst_cod_institucion) %>%
      mutate(pct = n / sum(n)) %>%
      slice_max(n, n = 1, with_ties = FALSE) %>%
      ungroup()
    cat("Instituciones 2024 donde estu_nse_ies es (casi) único, >= 95% de sus estudiantes:",
        round(100 * mean(mapa_nse_ies$pct >= 0.95), 1), "%\n")
    d25 <- d25 %>%
      select(-estu_nse_ies) %>%
      left_join(mapa_nse_ies %>% select(inst_cod_institucion, estu_nse_ies), by = "inst_cod_institucion")
    cat("Registros 2025 con estu_nse_ies recuperado desde 2024:",
        round(100 * mean(!is.na(d25$estu_nse_ies)), 1), "%\n")
    write.csv(mapa_nse_ies, file.path(salidas, "05_modelos", "mapa_nse_ies_2024.csv"), row.names = FALSE)}
  
  # derivadas con los cortes de INSE de 2024
  d25 <- crear_derivadas(d25, qs_inse = qs_inse, verbose = FALSE)
  
  # mismas columnas y tipos que el train
  cols_modelo <- names(train_ml_raw)
  for (v in setdiff(cols_modelo, names(d25))) d25[[v]] <- NA
  d25_ml_raw <- d25 %>% select(all_of(cols_modelo))
  for (v in cols_modelo) {
    if (is.numeric(train_ml_raw[[v]])) {
      d25_ml_raw[[v]] <- suppressWarnings(as.numeric(d25_ml_raw[[v]]))
    } else {
      d25_ml_raw[[v]] <- as.character(d25_ml_raw[[v]])}}
  
  d25_ml <- aplicar_imputacion(d25_ml_raw, reglas_train, excluir = target, limites = limites_train)
  d25_ml <- d25_ml %>% select(any_of(names(train_ml)))
  # categorías que no existían en 2024 se van a "Other", igual que en el test
  for (col in names(train_ml)) {
    if (is.factor(train_ml[[col]]) && col %in% names(d25_ml)) {
      x_col <- as.character(d25_ml[[col]])
      x_col[!(x_col %in% levels(train_ml[[col]]))] <- "Other"
      d25_ml[[col]] <- factor(x_col, levels = levels(train_ml[[col]]))}}
  
  x25 <- predict(dummies, newdata = d25_ml) %>% as.data.frame()
  x25[is.na(x25)] <- 0
  x25 <- data.frame(lapply(x25, as.numeric))
  for (v in setdiff(names(train_x), names(x25))) x25[[v]] <- 0
  x25 <- x25[, names(train_x), drop = FALSE]
  x25[!is.finite(as.matrix(x25))] <- 0
  y25 <- d25_ml[[target]]
  
  pred_25_xgb <- predict(modelo_xgb, xgboost::xgb.DMatrix(as.matrix(x25)))
  resultados_2025 <- bind_rows(
    metricas(test_y, pred_xgb, "XGBoost | prueba 2024 (partición aleatoria)"),
    metricas(y25, pred_25_xgb, "XGBoost | cohorte 2025 (fuera del tiempo)"))
  # De una vez los otros dos para ver si H1 se sostiene también en 2025
  if (!is.null(modelo_ranger)) {
    pred_25_rf <- predict(modelo_ranger, data = x25)$predictions
    resultados_2025 <- bind_rows(resultados_2025, metricas(y25, pred_25_rf, "Ranger RF | cohorte 2025"))}
  if (!is.null(modelo_lm_pred)) {
    pred_25_lm <- suppressWarnings(predict(modelo_lm_pred, newdata = x25))
    resultados_2025 <- bind_rows(resultados_2025, metricas(y25, pred_25_lm, "Regresión lineal | cohorte 2025"))}
  resultados_2025 <- resultados_2025 %>% mutate(n = c(length(test_y), rep(length(y25), n() - 1)))
  mostrar_tabla(resultados_2025, "Validación fuera del tiempo: 2024 vs. 2025")
  write.csv(resultados_2025, file.path(salidas, "05_modelos", "validacion_fuera_tiempo_2025.csv"), row.names = FALSE)
  
  # Ojo con esto: si el puntaje promedio de 2025 cambió frente a 2024, el modelo
  # va a tener un error medio distinto de cero aunque ordene bien a los
  # estudiantes. Esta tabla separa ese corrimiento de nivel del error en sí.
  calibracion_2025 <- tibble(
    cohorte = c("Prueba 2024", "Cohorte 2025"),
    real_promedio = c(mean(test_y), mean(y25)),
    pred_promedio = c(mean(pred_xgb), mean(pred_25_xgb)),
    error_medio = pred_promedio - real_promedio,
    correlacion_real_pred = c(cor(test_y, pred_xgb), cor(y25, pred_25_xgb)))
  mostrar_tabla(calibracion_2025, "Corrimiento de nivel 2024 vs. 2025 (XGBoost)")
  # AJUSTE oct-2026 (A6): con el R² tradicional se ve el costo del corrimiento
  # de nivel. Diferencia R2_cor2 - R2 en 2025 = lo que se pierde por el sesgo.
  if (mostrar_en_pantalla) print(as.data.frame(resultados_2025 %>% select(modelo, RMSE, MAE, R2, R2_cor2, n)))
  write.csv(calibracion_2025, file.path(salidas, "05_modelos", "calibracion_2024_vs_2025.csv"), row.names = FALSE)
  
  # equidad en 2025 por género y grupo PSM, para ver si el patrón se repite
  df_eval_25 <- tibble(
    real = y25,
    pred = pred_25_xgb,
    error = pred - real,
    abs_error = abs(pred - real))
  if ("estu_genero" %in% names(d25)) df_eval_25$genero <- d25$estu_genero
  if ("estrato_grupo_psm" %in% names(d25)) df_eval_25$estrato_grupo_psm <- d25$estrato_grupo_psm
  for (g in intersect(c("genero", "estrato_grupo_psm"), names(df_eval_25))) {
    bias_2025[[g]] <- calcular_bias(df_eval_25, g)
    mostrar_tabla(bias_2025[[g]], paste("Equidad predictiva 2025:", g))
    write.csv(bias_2025[[g]], file.path(salidas, "07_equidad", paste0("bias_2025_", g, ".csv")), row.names = FALSE)}
  
  graf_pred_25 <- tibble(real = y25, pred = pred_25_xgb) %>%
    slice_sample(n = min(30000, length(y25))) %>%
    ggplot(aes(x = real, y = pred)) +
    geom_point(alpha = .15, color = colores_tesis["verde"]) +
    geom_abline(slope = 1, intercept = 0, color = colores_tesis["rojo"], linewidth = 1) +
    labs(
      title = "Predicción vs. valor observado — XGBoost en la cohorte 2025",
      subtitle = "Modelo entrenado solo con Saber Pro 2024",
      x = "Puntaje observado 2025",
      y = "Puntaje predicho" ) +
    tema_base
  guardar_grafico(graf_pred_25, "prediccion_vs_observado_xgb_2025.png", carpeta = "05_modelos")
  
  # 17.2 AJUSTE oct-2026 (A16): ¿el corrimiento de 2025 es de los estudiantes
  # o de la escrita en 0? Revisando los CSV: sin los escritos en 0 la media de
  # 2024 (149,0) y la de 2025 (148,9) son prácticamente iguales; lo que cambió
  # fue la proporción de escritos en 0 (6,7% -> 1,7%). Esta tabla lo deja
  # medido con el modelo: si sin ellos el error medio de 2025 se va a ~0, el
  # "modelo desactualizado" era en realidad un cambio en cómo quedó calificado
  # el escrito.
  if ("diag_escrita_cero" %in% names(d25) && "diag_escrita_cero" %in% names(test_meta_raw)) {
    sin_cero_24 <- test_meta_raw$diag_escrita_cero %in% 0
    sin_cero_25 <- d25$diag_escrita_cero %in% 0
    resumen_nivel <- function(real, pred, cohorte, muestra) {
      metricas(real, pred, paste(cohorte, "|", muestra)) %>%
        mutate(n = length(real), real_promedio = mean(real), pred_promedio = mean(pred),
               error_medio = mean(pred - real),
               pct_escrita_cero = NA_real_)}
    sensibilidad_2025 <- bind_rows(
      resumen_nivel(test_y, pred_xgb, "Prueba 2024", "todos"),
      resumen_nivel(test_y[sin_cero_24], pred_xgb[sin_cero_24], "Prueba 2024", "sin escrita en 0"),
      resumen_nivel(y25, pred_25_xgb, "Cohorte 2025", "todos"),
      resumen_nivel(y25[sin_cero_25], pred_25_xgb[sin_cero_25], "Cohorte 2025", "sin escrita en 0"))
    # AJUSTE oct-2026 (A22): en las filas "sin escrita en 0" el % es 0, antes
    # salía repetido el de la muestra completa y confundía
    sensibilidad_2025$pct_escrita_cero <- c(100 * mean(!sin_cero_24), 0, 100 * mean(!sin_cero_25), 0)
    cat("\n===== SENSIBILIDAD 2025: NIVEL Y ERROR CON Y SIN COMUNICACIÓN ESCRITA EN 0 =====\n")
    if (mostrar_en_pantalla) print(as.data.frame(sensibilidad_2025 %>%
                                                   select(modelo, n, pct_escrita_cero, real_promedio, pred_promedio, error_medio, RMSE, R2, R2_cor2)))
    write.csv(sensibilidad_2025, file.path(salidas, "05_modelos", "sensibilidad_2025_escrita_cero.csv"), row.names = FALSE)}
} else {
  message("No se hizo la validación 2025: falta data_limpia_2025.csv o el XGBoost no se entrenó.")}
saveRDS(list(resultados = resultados_2025, calibracion = calibracion_2025, bias = bias_2025),
        file.path(salidas, "08_objetos", "validacion_2025.rds"))

# 18. EXPORTACIÓN FINAL DE OBJETOS
# (El Shiny se sacó del alcance por indicación de la tutora, todo queda en 08_objetos)
cat("\n===== GUARDANDO OBJETOS FINALES =====\n")
saveRDS(data_raw, file.path(salidas, "08_objetos", "data_raw.rds"))
saveRDS(data, file.path(salidas, "08_objetos", "data_curada.rds"))
saveRDS(modelo_xgb, file.path(salidas, "08_objetos", "modelo_xgb.rds"))
saveRDS(modelo_ranger, file.path(salidas, "08_objetos", "modelo_ranger.rds"))
saveRDS(modelo_lm_pred, file.path(salidas, "08_objetos", "modelo_lm_pred.rds"))
saveRDS(cv_ridge, file.path(salidas, "08_objetos", "cv_ridge.rds"))
saveRDS(cv_lasso, file.path(salidas, "08_objetos", "cv_lasso.rds"))

bitacora <- tibble(
  componente = c(
    "Fuente",
    "Filtro INDIVIDUAL/PUBLICAR (texto + respaldo institucional)",
    "INSE",
    "INSE imputado",
    "Variable dependiente",
    "Tratamiento PSM",
    "PSM",
    "Rosenbaum bounds",
    "Modelos predictivos",
    "Tuning Random Forest",
    "Tuning XGBoost",
    "Diagnóstico sesgo-varianza XGBoost",
    "Curvas de validación y de error",
    "SHAP",
    "Equidad predictiva",
    "Variables sensibles",
    "Variables administrativas",
    "Faltantes",
    "Selección de variables ML",
    "Theil",
    "Muestreo de visualizaciones",
    "Conversión data.table",
    "Visualización en R",
    "Área de formación",
    "Winsorización",
    "Validación fuera del tiempo",
    "Especificaciones del PSM",
    "Reproducibilidad" ),
  decision = c(
    "Base pública Saber Pro 2024 (anonimizada), DataIcfes > 02_Examen Saber Pro > 01_Módulos genéricos > Examen_Saber_Pro_Genericas_2024.txt (https://icfesgovco.sharepoint.com/sites/BasesDataIcfes). Anotar fecha de descarga",
    paste0(
      "Se excluyen registros marcados como INDIVIDUAL (por texto en ",
      col_individual %||% "columna no encontrada", ", y como respaldo por ausencia de dato en ",
      col_institucion %||% "columna institucional no encontrada",
      ") y no publicables (variable ", col_publicar %||% "no encontrada",
      "). En la base pública la columna de texto sí trae ESTUDIANTE/INDIVIDUAL y coincide con ",
      "la ausencia de institución; el criterio de no publicable no aplica porque esa columna no viene en la base pública"),
    "Se usa estu_inse_individual como índice socioeconómico oficial; no se cruza archivo externo si ya está en la base",
    "Se documenta con la bandera inse_imputado (TRUE/FALSE) antes de imputar con la mediana, para poder usarla como covariable o diagnóstico",
    "punt_global como variable continua. CORREGIDO: ya no se winsoriza ni se imputa (antes se recortaba al percentil 1-99 y se rellenaban NAs con la mediana, generando pisos artificiales)",
    "tratamiento = 1 si estrato_num > 2; 0 si estrato_num <= 2",
    "PSM se reporta como diferencia promedio ajustada bajo comparabilidad observacional, no como causalidad definitiva",
    "Se evalúa la sensibilidad del ATT ante sesgo por variable no observada con el estimador Hodges-Lehmann (rbounds::hlsens) sobre los pares emparejados 1 a 1",
    "Regresión lineal, Ridge, Lasso, Ranger RF y XGBoost se comparan con la misma partición, variables y métricas",
    "Los hiperparámetros de Random Forest (mtry, min.node.size) se ajustan con una malla más pequeña que la de XGBoost, con validación cruzada de 5 folds; num.trees se fija con una curva de error OOB. La malla se mantuvo deliberadamente reducida porque Random Forest es comparativamente poco sensible a estos hiperparámetros (Breiman, 2001)",
    "Los hiperparámetros de XGBoost (eta, max_depth, min_child_weight, subsample, colsample_bytree) se seleccionan por random search con validación cruzada de 5 folds, en vez de un set fijo",
    "Se compara RMSE/MAE/R² de XGBoost entre train y test para distinguir sub-ajuste (brecha pequeña) de sobre-ajuste (brecha grande) y no confundir la compresión predicho-vs-observado (esperada cuando R²<1) con un problema de ajuste",
    "Se grafican, para XGBoost: el RMSE de train vs. validación cruzada por ronda de boosting (curva de error) y por max_depth/min_child_weight (curvas de validación); para Random Forest: el CV-RMSE por mtry/min.node.size y el error OOB por num.trees",
    "SHAP se calcula sobre muestra reproducible del conjunto de prueba, no sobre entrenamiento",
    "Se evalúan errores por género, estrato, grupo de estrato, cuartil de INSE y condición de INSE imputado cuando están disponibles",
    "Variables de discapacidad se excluyen del modelo principal y se reservan para análisis ético/descriptivo si se justifica",
    "Códigos, identificadores y estados administrativos se excluyen del modelo principal",
    "Diagnóstico tabular completo sobre toda la base y visualización sobre muestra reproducible",
    ifelse(
      usar_reduccion_correlacion,
      "Se aplicó reducción por correlación por control computacional al superar 500 columnas",
      "No se aplicó reducción por correlación; se conservó el conjunto de predictores depurado"),
    "Se calcula con función propia para evitar dependencia de DescTools::Theil",
    "Los gráficos de faltantes, INSE y SHAP usan muestras reproducibles con tamaño calculado previamente",
    "La base leída con fread se convierte a tibble para evitar errores de selección de columnas propios de data.table",
    "Cada gráfico se imprime en el panel Plots y cada tabla clave se imprime en consola en el momento en que se genera (mostrar_en_pantalla), además de guardarse en disco en 08_objetos/09_tablas",
    "gruporeferencia no viene en la base pública; se reemplaza por estu_nucleo_pregrado (núcleo básico del conocimiento) en el modelo lineal, el PSM y los rankings",
    "Los límites P1-P99 de las variables numéricas se aprenden en el train y se aplican igual al test y a 2025 (antes el test se recortaba con sus propios percentiles)",
    "Los modelos entrenados con 2024 se evalúan sobre la cohorte 2025 (Examen_Saber_Pro_Genericas_2025.txt) sin reentrenar, con todos los parámetros de preprocesamiento aprendidos en 2024. Como el archivo 2025 no trae estu_nse_ies, se asigna a cada institución el valor que tenía en 2024 (inst_cod_institucion)",
    "La brecha por estrato se reporta en tres versiones: cruda, ajustada solo por covariables previas al estrato (género, educación de los padres, departamento y zona de residencia, tipo de bachillerato) y ajustada por todas (incluye institución, programa y forma de pago); se reportan pares, tratados sin pareja, IC95 y Gamma crítico",
    "Ruta parametrizada (RUTA_SABERPRO o carpeta de trabajo), semilla fija justo antes de la partición 80/20 y sessionInfo() guardado en salidas_tesis/sessionInfo.txt"))
# AJUSTE oct-2026: se dejan en la bitácora los cambios de esta versión, con la
# razón de cada uno, para que el rastro quede también en las salidas
bitacora <- bitacora %>%
  mutate(decision = case_when(
    componente == "Rosenbaum bounds" ~ "Sensibilidad a sesgo oculto con dos lecturas: hlsens (rango del estimador Hodges-Lehmann por Gamma) y psens (cota del p-valor de Wilcoxon por Gamma). El Gamma de significancia sale de psens",
    componente == "Tuning XGBoost" ~ "Random search de 12 combinaciones con CV de 5 folds sobre una malla con max_depth hasta 10, tope de 1000 rondas con early stopping; aviso automático si el óptimo queda en el borde",
    componente == "Especificaciones del PSM" ~ "La brecha por estrato se reporta en cuatro versiones anidadas: cruda; mínima (género, departamento y zona de residencia, tipo de bachillerato); origen familiar y territorial (la mínima + educación de madre y padre, que es componente del nivel socioeconómico, por lo que esta cifra es la brecha residual entre estudiantes con padres de igual educación); y completa (la anterior + institución, programa, forma de pago, tecnología y horas de trabajo, posteriores al estrato, con emparejamiento exacto en estu_nse_ies). Se reportan pares, tratados sin pareja, IC95, diferencia pareada, Hodges-Lehmann, Gamma, balance y ATT ajustado por regresión",
    componente == "Equidad predictiva" ~ "Errores por género, estrato, grupo de estrato, cuartil de INSE, condición de INSE imputado y comunicación escrita en 0, tomando los grupos sin imputar (test_meta_raw)",
    componente == "Reproducibilidad" ~ "Ruta parametrizada (variable de entorno RUTA_SABERPRO o, por defecto, la carpeta Proyecto_Grado/App), semilla fija justo antes de la partición 80/20 y sessionInfo() guardado en salidas_tesis/sessionInfo.txt",
    TRUE ~ decision)) %>%
  bind_rows(tibble(
    componente = c(
      "AJUSTE: variables de diseño sin imputar",
      "AJUSTE: faltantes categóricos en la EDA",
      "AJUSTE: códigos administrativos",
      "AJUSTE: estu_tieneetnia",
      "AJUSTE: caliper del PSM",
      "AJUSTE: R² tradicional",
      "AJUSTE: predictores del ML",
      "AJUSTE: familias SHAP",
      "AJUSTE: bordes de la malla",
      "AJUSTE: tablas trazables",
      "AJUSTE: puntajes en cero",
      "AJUSTE: balance y ajuste por regresión en el PSM",
      "AJUSTE: género 'No reporta' en el modelo inferencial",
      "AJUSTE: limpieza del 21-oct",
      "AJUSTE: faltantes categóricos en el ML",
      "AJUSTE: sensibilidad comunicación escrita en 0",
      "AJUSTE: banderas de faltante en el ML",
      "AJUSTE: PSM anidado",
      "AJUSTE: SHAP agregado por grupo",
      "AJUSTE: lambda de Ridge/Lasso en el log"),
    decision = c(
      paste0("estrato_num, estrato_grupo_psm, tratamiento, estrato_faltante, fami_estratovivienda e inse_* quedan fuera de la imputación de la EDA. ",
             "Los estudiantes sin estrato (blanco o 'Sin Estrato') se reportan como categoría propia en los descriptivos y se excluyen del ANOVA, la regresión inferencial y el PSM (observación de la tutora)"),
      "En data_eda los NA de las categóricas quedan como 'No reporta' (no la moda); las numéricas se imputan con la mediana",
      "Los códigos de departamento, municipio, institución y programa no se winsorizan (antes se recortaban al P1-P99)",
      "Se excluye de forma explícita: un solo valor observado ('S') y 85,3% NA en la base pública; además de los 41.363 con 'S', 32.749 tienen etnia 'Ninguno'. Sale desde Limpieza_saberPro.R (L3) y el pipeline la vuelve a excluir por seguridad; imputar con la moda marcaría a todos como pertenecientes a una etnia",
      "Caliper de 0,2 DE sobre el logit del puntaje de propensión (link = 'linear.logit'), según Austin (2011); se reporta también la diferencia pareada con su IC",
      "R2 = 1 - SSE/SST; R2_cor2 (cuadrado de la correlación) se conserva al lado. La diferencia entre los dos refleja el sesgo de nivel (relevante en 2025)",
      "Se excluyen fami_estratovivienda e inse_cuartil (redundantes con estrato_num y estu_inse_individual; los cortes de inse_cuartil se calculaban con toda la base) y estu_privado_libertad (sensible). Se agrega la bandera estrato_faltante",
      "Mapa de familias corregido: departamento de programa/institución -> territorial, estu_nse_ies -> institucional, pago de matrícula y horas de trabajo -> económicas y laborales, hacinamiento -> hogar. Se exporta mapa_familias_shap.csv y la prueba directa de H2",
      "Si el mejor Random Forest queda en el borde de la malla se amplía una vez; en XGBoost se avisa si max_depth, eta o nrounds quedan en el límite",
      "Se generan las tablas de error por decil, consistencia SHAP/gain/permutación, composición institucional por grupo de estrato y estrato con 'No reporta'",
      "Los registros con punt_global = 0 (sin puntaje válido) se excluyen en 2024 y 2025 (parámetro excluir_puntaje_cero)",
      "Para cada especificación se reporta la peor DME tras emparejar y el ATT ajustado por regresión sobre la muestra emparejada con las covariables del puntaje de propensión (Ho et al., 2007), como chequeo de robustez. En versiones previas estu_nse_ies quedaba con DME 0,13; desde A18 se empareja exacto en esa variable",
      "El único registro con género 'No reporta' se excluye solo del modelo lineal inferencial",
      paste0("Desde Limpieza_saberPro.R: edad derivada de la fecha de nacimiento; diag_escrita_cero (comunicación escrita en 0, solo diagnóstico); ",
             "etnia y estu_repite excluidas; estu_depto_reside protegida del filtro de cardinalidad; variables con más de 90% de NA excluidas; ",
             "etiquetas armonizadas 2024-2025 y exclusión de variables cuyas categorías cambiaron en 2025"),
      "En el modelo predictivo los NA de las categóricas se codifican como 'No reporta' (indicador de faltante) en vez de la moda",
      "Análisis principal con el puntaje oficial; sensibilidad sin los estudiantes con comunicación escrita en 0 para la brecha cruda, el PSM completo y la comparación de nivel 2024-2025",
      "inse_imputado y estrato_faltante se protegen del filtro nearZeroVar (antes se eliminaban por su baja frecuencia y el modelo no distinguía imputados de reportados)",
      "El PSM completo incluye zona de residencia y tipo de bachillerato, de modo que contiene a la lectura de origen familiar y las cuatro lecturas quedan anidadas",
      "La importancia SHAP por familia y por bloque de H2 se calcula como el promedio del valor absoluto de la suma de los SHAP del grupo por estudiante (aporte conjunto del grupo), no como la suma de los |SHAP| de cada dummy, que inflaba las familias con más columnas",
      "Se imprime lambda.min de Ridge y Lasso para respaldar la lectura de penalización casi nula")))
write.csv(
  bitacora,
  file.path(salidas, "09_tablas", "bitacora_metodologica.csv"),
  row.names = FALSE)
saveRDS(bitacora, file.path(salidas, "08_objetos", "bitacora_metodologica.rds"))
mostrar_tabla(bitacora, "Bitácora metodológica")

fin_total <- Sys.time()
cat("\n===== TIEMPO TOTAL =====\n")
print(fin_total - inicio_total)
cat("\nPipeline finalizado correctamente.\n")
cat("\nSalidas guardadas en:", salidas, "\n")
if (mostrar_en_pantalla) {
  cat("Además, cada gráfico y cada tabla de resultados se mostraron en el panel Plots / consola de RStudio a medida que se generaban.\n")}

# Versiones de R y de paquetes: ranger, xgboost y MatchIt cambian resultados
# entre versiones, así que esto queda en el log y en un archivo aparte.
cat("\n===== SESSION INFO (reproducibilidad) =====\n")
print(sessionInfo())
writeLines(capture.output(sessionInfo()), file.path(salidas, "sessionInfo.txt"))
#Q

sink(type = "message")
sink()
close(con)