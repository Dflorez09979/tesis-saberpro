# Determinantes socioeconómicos del rendimiento académico en Colombia mediante modelos de machine learning

Código del trabajo de grado (monografía) de **Diego Florez Castillo** para optar al título de Magíster en Ciencia de Datos, Universidad Ean (Bogotá, 2026).

Aquí están los dos scripts de R que se citan en los anexos del documento:

| Anexo | Script | Qué hace |
|---|---|---|
| A | `Limpieza_saberPro.R` | Toma los archivos en bruto de Saber Pro 2024 y 2025, corrige tipos de dato, calcula la edad, marca la comunicación escrita en cero, armoniza las etiquetas entre años y deja `data_limpia_tesis.csv` y `data_limpia_2025.csv`. |
| B | `pipeline_tesis_saberpro.R` | Filtro de calidad, partición entrenamiento/prueba, imputación, EDA e inferencia, PSM con análisis de sensibilidad de Rosenbaum, modelos (lineal, regularizados, Random Forest con `ranger`, XGBoost), SHAP, auditoría de equidad predictiva y validación con la cohorte 2025. |

## Datos

Los datos **no** están en este repositorio. Son las bases públicas y anonimizadas del ICFES (DataIcfes):
`02_Examen Saber Pro > 01_Módulos genéricos`

- `Examen_Saber_Pro_Genericas_2024.txt` (base principal)
- `Examen_Saber_Pro_Genericas_2025.txt` (solo para validar el modelo fuera del año de entrenamiento)

Portal: https://icfesgovco.sharepoint.com/sites/BasesDataIcfes

## Cómo correrlo

1. Descargue los dos `.txt` y póngalos en una carpeta.
2. Defina la variable de entorno `RUTA_SABERPRO` con esa carpeta (o abra R con esa carpeta como directorio de trabajo):
   ```r
   Sys.setenv(RUTA_SABERPRO = "ruta/a/la/carpeta")
   ```
3. Corra primero `Limpieza_saberPro.R` y después `pipeline_tesis_saberpro.R`.

Los scripts instalan los paquetes que falten. Las salidas (tablas, figuras y el log con `sessionInfo()`) quedan en `salidas_tesis/`. Pilas: el pipeline completo es pesado (más de 270.000 registros, tuning de Random Forest y XGBoost); en un portátil puede tardar varias horas.

## Licencia

MIT. Si usa el código, por favor cite la monografía.
