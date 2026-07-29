# =============================================================================
# Centinela — API de ingesta, consulta, explicador y extractor documental.
#
# Una sola imagen para los tres papeles. Cual asume lo deciden las variables
# CENTINELA_*_ENABLED en tiempo de despliegue, no en tiempo de construccion.
# La alternativa —tres imagenes desde el mismo codigo— triplicaria el tiempo de
# construccion y el almacenamiento del registro para entregar exactamente los
# mismos bytes de aplicacion.
#
# Construccion multietapa: lo que compila NO viaja a produccion. La etapa de
# build arrastra el JDK completo, Maven y ~200 MB de dependencias descargadas;
# a la imagen final solo cruza el JAR. Esto importa mas alla del tamano: las
# capas de una imagen conservan todo lo que existio en ellas, asi que borrar el
# repositorio de Maven en una capa posterior NO lo elimina de la imagen. Solo
# no copiarlo lo elimina.
# =============================================================================

# -----------------------------------------------------------------------------
# Etapa 1 — Construccion
# -----------------------------------------------------------------------------
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /build

# El POM se copia solo para resolver dependencias. Al ir en su propia capa,
# cambiar codigo fuente no invalida la descarga de dependencias: la construccion
# incremental pasa de minutos a segundos.
COPY pom.xml ./
RUN mvn -B -ntp dependency:go-offline

COPY src ./src

# Las pruebas NO se ejecutan aqui. Ya corrieron como etapa previa del pipeline,
# donde un fallo lo detiene antes de construir la imagen. Repetirlas duplicaria
# varios minutos por construccion sin anadir una sola garantia.
RUN mvn -B -ntp clean package -DskipTests \
    && mv target/*.jar /build/application.jar

# -----------------------------------------------------------------------------
# Etapa 2 — Agente de telemetria
# -----------------------------------------------------------------------------
# En su propia etapa para que la descarga se cachee por separado del codigo y no
# se repita en cada construccion.
FROM eclipse-temurin:21-jre-alpine AS telemetry

ARG APPLICATIONINSIGHTS_VERSION=3.6.2
ADD https://github.com/microsoft/ApplicationInsights-Java/releases/download/${APPLICATIONINSIGHTS_VERSION}/applicationinsights-agent-${APPLICATIONINSIGHTS_VERSION}.jar /agent/applicationinsights-agent.jar

# -----------------------------------------------------------------------------
# Etapa 3 — Ejecucion
# -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine AS runtime

# Usuario sin privilegios. Un proceso comprometido no debe poder escribir en el
# sistema de archivos de la imagen ni escalar dentro del contenedor.
RUN addgroup -S centinela && adduser -S centinela -G centinela

WORKDIR /app

COPY --from=telemetry --chown=centinela:centinela /agent/applicationinsights-agent.jar ./applicationinsights-agent.jar
COPY --from=build --chown=centinela:centinela /build/application.jar ./application.jar
COPY --chown=centinela:centinela applicationinsights.json ./applicationinsights.json

USER centinela

EXPOSE 8080

# NINGUNA credencial entra aqui. La cadena de conexion de telemetria, la de
# Cosmos y la de PostgreSQL llegan como variables de entorno inyectadas por la
# plataforma desde Key Vault en el arranque. Un ARG o un ENV con un secreto
# quedaria grabado en la capa y seria recuperable con `docker history`.
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/applicationinsights-agent.jar" \
    JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseSerialGC"

# Container Apps enruta el trafico segun este puerto.
ENV SERVER_PORT=8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD wget -q -O- http://localhost:8080/actuator/health/readiness || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/application.jar"]
