#!/usr/bin/env bash
#
# scripts/tests/capture-week3-evidence.sh
# Captura la evidencia de las issues de Semana 3 que se verifican sin Azure.
#
# Existe como script y no como una lista de comandos en un documento por una razon
# concreta: la evidencia tiene que poder regenerarse. Una captura pegada a mano en
# un README no se sabe con que version del codigo se obtuvo, y en cuanto el codigo
# cambia deja de ser evidencia para convertirse en decoracion.
#
# Cada corrida crea docs/evidence/iss-s3-XXX/run-<sello>/ con la salida real de los
# comandos que el criterio de aceptacion de esa issue exige.
#
# Las issues que requieren Docker o una suscripcion de Azure se saltan y se
# reportan como tales: declararlo es mas util que una carpeta vacia.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

SELLO="$(date -u +%Y%m%dT%H%M%SZ)"
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'sin-commit')"
RAMA="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'sin-rama')"

capturadas=0
saltadas=0

note() { printf '\n[evidencia] %s\n' "$*"; }

# carpeta_de <issue> -> crea y devuelve la ruta de la corrida
carpeta_de() {
  local issue="$1"
  local destino="docs/evidence/$issue/run-$SELLO"
  mkdir -p "$destino"
  {
    echo "issue      : $issue"
    echo "commit     : $COMMIT"
    echo "rama       : $RAMA"
    echo "instante   : $SELLO (UTC)"
    echo "java       : $(java -version 2>&1 | head -1)"
    echo "maven      : $(mvn -v 2>/dev/null | head -1)"
  } > "$destino/00-metadata.txt"
  printf '%s' "$destino"
}

# capturar <issue> <nombre-archivo> <descripcion> -- <comando...>
capturar() {
  local issue="$1" archivo="$2" descripcion="$3"; shift 3
  [ "$1" = "--" ] && shift

  local destino; destino="$(carpeta_de "$issue")"
  local salida="$destino/$archivo"

  {
    echo "# $descripcion"
    echo "# comando: $*"
    echo "# ------------------------------------------------------------------"
  } > "$salida"

  if "$@" >> "$salida" 2>&1; then
    echo "" >> "$salida"
    echo "# RESULTADO: OK" >> "$salida"
    printf '  OK    %s/%s\n' "$issue" "$archivo"
    capturadas=$((capturadas + 1))
  else
    local codigo=$?
    echo "" >> "$salida"
    echo "# RESULTADO: FALLO (codigo $codigo)" >> "$salida"
    printf '  FALLO %s/%s (codigo %s)\n' "$issue" "$archivo" "$codigo"
  fi
}

# saltar <issue> <motivo>
saltar() {
  local issue="$1" motivo="$2"
  local destino; destino="$(carpeta_de "$issue")"
  {
    echo "# Evidencia NO capturada en esta corrida"
    echo "#"
    echo "# Motivo: $motivo"
    echo "#"
    echo "# Esta issue esta implementada, pero su criterio de aceptacion exige"
    echo "# ejecutar contra un recurso que no esta disponible en este entorno."
    echo "# Declararlo es mas util que dejar una carpeta vacia que parezca"
    echo "# evidencia."
  } > "$destino/01-no-verificable.txt"
  printf '  SALTO %s — %s\n' "$issue" "$motivo"
  saltadas=$((saltadas + 1))
}

hay_docker() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }
hay_azure()  { command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; }

# ============================================================================
note "Persona 1 — trazabilidad, motor, esquema y lectura"

capturar iss-s3-001 "01-trace-context.txt" \
  "Contexto de traza: parseo, derivacion de span y degradacion sin excepcion" \
  -- mvn -B -ntp -f scoring-function/pom.xml test -Dtest=TraceContextTest \
       -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-001 "02-contrato-esquemas.txt" \
  "Los JSON Schema y los records Java describen la misma forma" \
  -- mvn -B -ntp test -Dtest=EventContractTest -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-001 "03-traceparent-en-esquemas.txt" \
  "traceparent declarado y obligatorio en los dos contratos" \
  -- grep -n "traceparent" docs/1_Requisitos_y_Contrato/schemas/transaction-event-v1.json \
       docs/1_Requisitos_y_Contrato/schemas/flagged-case-v1.json

capturar iss-s3-002 "01-detalle-de-activacion.txt" \
  "Cada afirmacion de la explicacion objetivo tiene su valor registrado" \
  -- mvn -B -ntp -f scoring-function/pom.xml test -Dtest=RuleActivationDetailTest -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-002 "02-suite-motor.txt" \
  "La deteccion no cambio: suite completa del motor" \
  -- mvn -B -ntp -f scoring-function/pom.xml test

capturar iss-s3-003 "01-migracion-v4.txt" \
  "Contenido de la migracion V4" \
  -- cat src/main/resources/db/migration/V4__case_explanation_and_verification.sql

capturar iss-s3-003 "02-apertura-de-caso.txt" \
  "El caso nace PENDING con cuenta y traza" \
  -- mvn -B -ntp test -Dtest=OpenCaseServiceTest -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-004 "01-api-de-consulta.txt" \
  "Analisis y caso: una transaccion limpia tiene analisis pero no caso" \
  -- mvn -B -ntp test -Dtest=CaseInquiryControllerTest -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-004 "02-autorizacion.txt" \
  "Los endpoints de consulta exigen rol ANALYST o SERVICE" \
  -- mvn -B -ntp test -Dtest=EndpointAuthorizationTest -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-005 "01-etapas-instrumentadas.txt" \
  "Ninguna etapa declarada queda sin emisor" \
  -- bash scripts/verify/verify-practices.sh

# ============================================================================
note "Persona 2 — contenedores, registro y escalado"

if hay_docker; then
  capturar iss-s3-006 "01-construccion-imagen-api.txt" \
    "Construccion de la imagen de la API" \
    -- docker build -t centinela-api:evidencia .
  capturar iss-s3-006 "02-sin-secretos-en-capas.txt" \
    "Ninguna capa contiene credenciales" \
    -- bash scripts/verify/verify-image-secrets.sh centinela-api:evidencia
  capturar iss-s3-007 "01-construccion-imagen-motor.txt" \
    "Construccion de la imagen del motor" \
    -- docker build -t centinela-scoring:evidencia ./scoring-function
  capturar iss-s3-015 "01-tamano-de-imagenes.txt" \
    "Tamano y capas mas pesadas de las imagenes locales" \
    -- bash scripts/verify/report-image-size.sh "" "evidencia"
else
  saltar iss-s3-006 "Docker no disponible en este entorno"
  saltar iss-s3-007 "Docker no disponible en este entorno"
  saltar iss-s3-015 "Docker no disponible en este entorno"
fi

capturar iss-s3-008 "01-plan-registro.txt" \
  "Plan de aprovisionamiento del registro, sin crear nada" \
  -- bash scripts/provision-container-registry.sh --validate-only

capturar iss-s3-009 "01-plan-container-apps.txt" \
  "Plan del entorno y de las reglas de escalado, sin crear nada" \
  -- bash scripts/provision-container-apps.sh --validate-only

if hay_azure; then
  capturar iss-s3-010 "01-observacion-escalado.txt" \
    "Replicas antes, durante y despues de la carga" \
    -- bash scripts/verify/verify-scaling.sh
else
  saltar iss-s3-010 "Requiere el sistema desplegado y carga generada en vivo"
fi

# ============================================================================
note "Persona 3 — integracion y despliegue continuo"

capturar iss-s3-011 "01-plan-oidc.txt" \
  "Plan de la credencial federada, sin crear nada" \
  -- env CENTINELA_GITHUB_REPO="Centinela-App/Centinela" bash scripts/provision-github-oidc.sh --validate-only

capturar iss-s3-012 "01-suite-completa.txt" \
  "Lo que el pipeline de CI ejecuta: suite del modulo principal" \
  -- mvn -B -ntp test

capturar iss-s3-012 "02-barrido-de-secretos.txt" \
  "Barrido de credenciales en el arbol de trabajo" \
  -- bash scripts/tests/scan-repository.sh

capturar iss-s3-013 "01-encadenamiento-etapas.txt" \
  "Las cinco etapas estan encadenadas con needs" \
  -- grep -n "needs:\|name:\|uses:" .github/workflows/cd.yml

capturar iss-s3-014 "01-justificacion-plataforma.txt" \
  "ADR-008 con criterio, contrapartida y contexto inverso" \
  -- sed -n '/## ADR-008/,/## ADR-009/p' docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md

# ============================================================================
note "Persona 4 — observabilidad, verificacion y costos"

capturar iss-s3-016 "01-consultas-de-operacion.txt" \
  "Las cinco consultas de operacion documentadas" \
  -- cat docs/observabilidad/consultas-kql.md

if hay_azure; then
  capturar iss-s3-016 "02-plan-observabilidad.txt" \
    "Plan de Application Insights y alerta" \
    -- bash scripts/provision-observability.sh --validate-only
else
  saltar iss-s3-017 "Requiere Application Insights con datos ingeridos"
  saltar iss-s3-018 "Requiere provocar la condicion sobre el sistema desplegado"
  saltar iss-s3-020 "Requiere consultar Cost Management"
fi

capturar iss-s3-019 "01-agentes-definidos.txt" \
  "Siete agentes de verificacion con su descripcion" \
  -- grep -h "^name:\|^description:" .claude/agents/verify-infra.md .claude/agents/verify-secrets.md \
       .claude/agents/verify-containers.md .claude/agents/verify-cicd.md \
       .claude/agents/verify-observability.md .claude/agents/verify-explainer.md \
       .claude/agents/verify-practices.md

capturar iss-s3-019 "02-verificacion-de-practicas.txt" \
  "Estructura, migraciones, instrumentacion y secretos" \
  -- bash scripts/verify/verify-practices.sh

# ============================================================================
note "Persona 5 — explicabilidad, documental, banco de pruebas y cierre"

capturar iss-s3-021 "01-correspondencia-estricta.txt" \
  "Las dos formas de romper la correspondencia estan cubiertas" \
  -- mvn -B -ntp test -Dtest=ExplanationTemplateTest -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-022 "01-resiliencia-del-explicador.txt" \
  "Aislamiento de fallos y recuperacion de backlog" \
  -- mvn -B -ntp test -Dtest=GenerateCaseExplanationServiceTest -Dsurefire.failIfNoSpecifiedTests=false

capturar iss-s3-023 "01-manejo-de-fallos-documentales.txt" \
  "Nueve formas de documento roto, ninguna lanza" \
  -- mvn -B -ntp test -Dtest=TextualIdentityDataExtractorTest -Dsurefire.failIfNoSpecifiedTests=false

if [ -d "../centinela-lab" ]; then
  capturar iss-s3-024 "01-escenarios-del-banco-de-pruebas.txt" \
    "Cada escenario genera de verdad la forma de trafico que promete" \
    -- mvn -B -ntp -f ../centinela-lab/pom.xml test
else
  saltar iss-s3-024 "El repositorio centinela-lab no esta junto a este"
fi

capturar iss-s3-025 "01-adr-cerrado.txt" \
  "ADR con las decisiones de las tres semanas" \
  -- grep -n "^## ADR" docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md

# ============================================================================
note "Resumen"
printf '  Capturadas : %s\n' "$capturadas"
printf '  Saltadas   : %s\n' "$saltadas"
printf '  Sello      : %s\n' "$SELLO"
printf '  Commit     : %s\n' "$COMMIT"
echo ""
echo "  Las evidencias estan en docs/evidence/iss-s3-*/run-$SELLO/"
