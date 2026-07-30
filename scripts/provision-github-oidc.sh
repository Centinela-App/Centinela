#!/usr/bin/env bash
#
# scripts/provision-github-oidc.sh
# ISS-S3-010 — Identidad federada para el pipeline, sin ninguna credencial.
#
# Crea un registro de aplicacion en Entra ID y le asocia credenciales federadas
# acotadas a un repositorio y una rama concretos. GitHub emite un token de
# identidad de vida corta; Azure lo valida contra esas credenciales. En ningun
# momento existe una contrasena, un certificado ni un JSON de service principal.
#
# La diferencia con el enfoque clasico no es "el secreto esta bien guardado",
# sino que NO HAY SECRETO QUE ROBAR. Una credencial de service principal
# filtrada vale hasta que alguien la rote; un token OIDC filtrado caduco antes
# de terminar de leerse.
#
# Uso:
#   CENTINELA_GITHUB_REPO="Centinela-App/Centinela" bash scripts/provision-github-oidc.sh
#
#   # Los dos repositorios del sistema, en una sola corrida:
#   CENTINELA_GITHUB_REPO="Centinela-App/Centinela,Centinela-App/centinela-lab" \
#     bash scripts/provision-github-oidc.sh
#
# VARIOS REPOSITORIOS, UNA SOLA IDENTIDAD
# ---------------------------------------
# El banco de pruebas vive en su propio repositorio y tiene su propio pipeline, y
# ese pipeline tambien necesita autenticarse. Una credencial federada esta acotada
# a UN repositorio, asi que sin una credencial propia el workflow del banco de
# pruebas falla en 'azure/login' con un error que habla de token invalido y no
# menciona que el problema es el repositorio de origen.
#
# Se usa la MISMA aplicacion con una credencial por repositorio en lugar de dos
# aplicaciones. El motivo es que ambos pipelines necesitan exactamente los mismos
# dos permisos sobre el mismo grupo de recursos —publicar en el registro y
# actualizar Container Apps—, asi que dos aplicaciones significarian mantener dos
# juegos identicos de asignaciones de rol y descubrir por un despliegue roto
# cuando uno de los dos se queda atras. El acotamiento real lo da la credencial
# federada: cada repositorio solo puede pedir el token desde su propia rama.
#
# Al terminar imprime los valores que hay que configurar en GitHub. Ninguno es un
# secreto — son identificadores — pero se registran como secretos del repositorio
# por costumbre y para no exponer la topologia de la suscripcion en los registros
# publicos de las corridas.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

GITHUB_REPO="${CENTINELA_GITHUB_REPO:-}"
GITHUB_BRANCH="${CENTINELA_GITHUB_BRANCH:-main}"
VALIDATE_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: CENTINELA_GITHUB_REPO=<org/repo> $0 [--validate-only]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

main() {
  load_parameters
  validate_parameters
  require_cmd az

  [ -n "$GITHUB_REPO" ] || die "Define CENTINELA_GITHUB_REPO con la forma 'organizacion/repositorio'."

  # Se admite una lista separada por comas para cubrir los dos repositorios del
  # sistema en una sola corrida. Cada entrada se valida por separado: un error
  # tipografico en el segundo repositorio no debe descubrirse cuando su pipeline
  # falle semanas despues.
  local -a repos=()
  local entrada
  local IFS_ORIGINAL="$IFS"
  IFS=','
  for entrada in $GITHUB_REPO; do
    entrada="$(printf '%s' "$entrada" | tr -d '[:space:]')"
    [ -n "$entrada" ] || continue
    [[ "$entrada" == */* ]] \
      || die "'$entrada' no tiene la forma 'organizacion/repositorio'."
    repos+=("$entrada")
  done
  IFS="$IFS_ORIGINAL"
  [ "${#repos[@]}" -gt 0 ] || die "CENTINELA_GITHUB_REPO no contiene ningun repositorio valido."

  local app_name="app-${NAME_PREFIX}-github-deploy"

  log_info "Plan de ISS-S3-010:"
  log_info "  Aplicacion       : $app_name"
  log_info "  Repositorios     : ${repos[*]}"
  log_info "  Rama autorizada  : $GITHUB_BRANCH"
  log_info "  Alcance del rol  : el grupo de recursos, NO la suscripcion"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "Modo --validate-only: no se crea nada."
    exit 0
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."

  local app_id
  app_id="$(ensure_application "$app_name")"
  ensure_service_principal "$app_id"
  local repo
  for repo in "${repos[@]}"; do
    log_info "Credenciales federadas para '$repo':"
    ensure_federated_credentials "$app_id" "$repo"
  done
  assign_deployment_roles "$app_id"
  print_github_configuration "$app_id" "${repos[@]}"
}

ensure_application() {
  local name="$1" existing
  existing="$(az ad app list --display-name "$name" --query '[0].appId' -o tsv 2>/dev/null || true)"
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    log_info "El registro de aplicacion '$name' ya existe."
    printf '%s' "$existing"
    return
  fi
  log_info "Creando registro de aplicacion '$name'..." >&2
  az ad app create --display-name "$name" --query appId -o tsv
}

ensure_service_principal() {
  local app_id="$1"
  if az ad sp show --id "$app_id" >/dev/null 2>&1; then
    log_info "El service principal ya existe."
    return
  fi
  log_info "Creando service principal..."
  az ad sp create --id "$app_id" --output none
}

ensure_federated_credentials() {
  local app_id="$1" repo="$2"

  # El nombre de cada credencial incluye el repositorio: son unicos dentro de la
  # aplicacion, y con dos repositorios los nombres genericos colisionarian —la
  # segunda credencial se veria como "ya existe" y el segundo pipeline fallaria
  # con un token que Azure rechaza sin decir que el problema es el origen.
  local slug
  slug="$(printf '%s' "$repo" | tr '/' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"

  # Tres credenciales por repositorio, cada una acotada a un contexto distinto.
  # Acotar importa: una credencial que aceptara cualquier rama permitiria a quien
  # pudiera crear una rama en el repositorio desplegar a produccion.
  federated "$app_id" "gh-${slug}-branch-${GITHUB_BRANCH}" \
    "repo:${repo}:ref:refs/heads/${GITHUB_BRANCH}" \
    "Integraciones a la rama ${GITHUB_BRANCH} de ${repo}"

  federated "$app_id" "gh-${slug}-environment-produccion" \
    "repo:${repo}:environment:produccion" \
    "Despliegues al entorno de produccion de ${repo}"

  federated "$app_id" "gh-${slug}-pull-request" \
    "repo:${repo}:pull_request" \
    "Validaciones de pull request de ${repo} (solo lectura en la practica)"
}

federated() {
  local app_id="$1" name="$2" subject="$3" description="$4"

  if az ad app federated-credential list --id "$app_id" \
       --query "[?name=='$name'] | length(@)" -o tsv 2>/dev/null | grep -q '^[1-9]'; then
    log_info "  Credencial federada '$name' ya existe."
    return
  fi

  log_info "  Creando credencial federada '$name'..."
  az ad app federated-credential create --id "$app_id" --parameters "$(cat <<JSON
{
  "name": "$name",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$subject",
  "description": "$description",
  "audiences": ["api://AzureADTokenExchange"]
}
JSON
)" --output none
}

assign_deployment_roles() {
  local app_id="$1"
  local principal_id scope
  principal_id="$(az ad sp show --id "$app_id" --query id -o tsv)"
  scope="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv)"

  # El alcance es el grupo de recursos, nunca la suscripcion. Un pipeline
  # comprometido debe poder estropear este proyecto, no todos.
  #
  # Dos roles y solo dos:
  #   AcrPush             -> publicar imagenes en el registro
  #   Contributor (RG)    -> actualizar las Container Apps
  #
  # Contributor sobre el grupo es mas amplio de lo ideal. La alternativa exacta
  # seria un rol personalizado con las acciones de Microsoft.App; se documenta
  # como deuda consciente en vez de fingir que el minimo privilegio esta
  # completo aqui.
  local fallos=0
  for role in "AcrPush" "Contributor"; do
    log_info "Asignando '$role' sobre el grupo de recursos..."
    # La identidad puede tardar unos segundos en propagarse tras crearse.
    with_retry 5 assign_role "$role" "$principal_id" "$scope" || fallos=$((fallos + 1))
  done

  if [ "$fallos" -gt 0 ]; then
    log_warn "La identidad quedo creada pero SIN permisos de despliegue."
    log_warn "El pipeline podra autenticarse y fallara al crear o actualizar recursos."
    log_warn "Asignar manualmente desde el portal: Grupo de recursos -> Control de acceso (IAM)."
    return 1
  fi
}

print_github_configuration() {
  local app_id="$1"; shift
  local -a repos=("$@")
  local tenant_id entra_app_id api_fqdn
  tenant_id="$(az account show --query tenantId -o tsv)"

  # Se resuelven aqui para que el operador no tenga que buscarlos: son las dos
  # variables que el pipeline del banco de pruebas necesita para no depender de
  # permisos de lectura sobre Microsoft Graph. Si todavia no existen, se imprime el
  # comando que las obtiene mas adelante en vez de un hueco sin explicacion.
  entra_app_id="$(az ad app list --display-name "${NAME_PREFIX}-api-week1" \
    --query '[0].appId' -o tsv 2>/dev/null | grep -v '^None$' || true)"
  api_fqdn="$(az containerapp show -g "$RESOURCE_GROUP" -n "ca-${NAME_PREFIX}-api" \
    --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"

  cat <<EOF

================================================================================
CONFIGURACION A REGISTRAR EN GITHUB
================================================================================

Repositorios habilitados por credencial federada:
$(printf '  - %s\n' "${repos[@]}")

--- En AMBOS repositorios ------------------------------------------------------

Secrets (Settings -> Secrets and variables -> Actions -> Secrets):

  AZURE_CLIENT_ID        $app_id
  AZURE_TENANT_ID        $tenant_id
  AZURE_SUBSCRIPTION_ID  $SUBSCRIPTION_ID

Variables (misma pantalla, pestana Variables):

  AZURE_RESOURCE_GROUP   $RESOURCE_GROUP
  AZURE_LOCATION         $LOCATION
  NAME_PREFIX            $NAME_PREFIX

--- Solo en el repositorio de Centinela ---------------------------------------

  APP_SERVICE_SKU        $APP_SERVICE_SKU
  AZURE_DEPLOY_ENABLED   true        <- activa el despliegue automatico

--- Solo en el repositorio del banco de pruebas -------------------------------

  DESPLIEGUE_HABILITADO  true        <- activa el despliegue automatico
  CENTINELA_ENTRA_APP_ID ${entra_app_id:-<ejecuta provision-entra-app.sh y vuelve a correr este script>}
  CENTINELA_API_FQDN     ${api_fqdn:-<se resuelve solo tras desplegar la API; opcional>}

Estas dos ultimas evitan que el pipeline del banco de pruebas necesite permiso de
lectura sobre Microsoft Graph. Son identificadores publicos, no secretos.

--- Nota sobre lo que NO se configura aqui ------------------------------------

El app role SERVICE de la identidad del banco de pruebas NO se concede desde el
pipeline: exige escritura en el directorio, y darsela al service principal de un
workflow significaria que quien pueda editar ese workflow puede concederse roles
de aplicacion. Lo hace una persona, una vez:

  bash scripts/deploy-lab.sh --skip-image --yes      (en el repo centinela-lab)

================================================================================
Ninguno de estos valores es un secreto en sentido estricto: son identificadores
y no sirven de nada sin un token firmado por GitHub para ESE repositorio y ESA
rama. Se registran como secrets por costumbre y para no publicar la topologia de
la suscripcion en los registros de cada corrida.

Con esto, 'az login' en los dos pipelines funciona sin contrasena alguna.
================================================================================
EOF
}

main "$@"
