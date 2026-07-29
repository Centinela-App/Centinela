# =============================================================================
# Centinela — Motor de scoring.
#
# Sigue siendo una Azure Function disparada por Event Grid, pero empaquetada
# como imagen de contenedor. Se eligio la imagen base oficial del runtime de
# Functions en vez de reescribir el motor como servicio HTTP: el disparador de
# Event Grid, el reintento y la concurrencia ya funcionaban y validarlos de
# nuevo habria consumido la semana sin cambiar el comportamiento observable.
#
# Azure Container Apps ejecuta esta imagen directamente; el runtime de Functions
# vive dentro del contenedor.
# =============================================================================

# -----------------------------------------------------------------------------
# Etapa 1 — Construccion
# -----------------------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /build

COPY pom.xml ./
RUN mvn -B -ntp dependency:go-offline

COPY src ./src
COPY host.json ./

# Las pruebas corrieron ya en el pipeline. El plugin de Functions arma el
# directorio de staging con el JAR, host.json y function.json.
RUN mvn -B -ntp clean package -DskipTests

# -----------------------------------------------------------------------------
# Etapa 2 — Ejecucion
# -----------------------------------------------------------------------------
FROM mcr.microsoft.com/azure-functions/java:4-java21 AS runtime

# El runtime de Functions espera el paquete en esta ruta y la descubre solo.
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    FUNCTIONS_WORKER_RUNTIME=java

# Se copia UNICAMENTE el directorio de staging: ni el codigo fuente, ni el
# repositorio de Maven, ni el JDK de compilacion llegan a la imagen final.
COPY --from=build /build/target/azure-functions/cent-scoring-fn/ /home/site/wwwroot/

# Sin secretos en ninguna capa. Las cadenas de conexion de Cosmos y de Storage
# se resuelven en arranque contra Key Vault mediante Managed Identity.
