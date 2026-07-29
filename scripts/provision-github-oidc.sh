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
# Al terminar imprime los tres valores que hay que configurar en GitHub. Ninguno
# de los tres es un secreto — son identificadores — pero se registran como
# secretos del repositorio por costumbre y para no exponer la topologia de la
# suscripcion en los registros publicos de las corridas.

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
  [[ "$GITHUB_REPO" == */* ]] || die "CENTINELA_GITHUB_REPO debe tener la forma 'organizacion/repositorio'."

  local app_name="app-${NAME_PREFIX}-github-deploy"

  log_info "Plan de ISS-S3-010:"
  log_info "  Aplicacion       : $app_name"
  log_info "  Repositorio      : $GITHUB_REPO"
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
  ensure_federated_credentials "$app_id"
  assign_deployment_roles "$app_id"
  print_github_configuration "$app_id"
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
  local app_id="$1"

  # Tres credenciales, cada una acotada a un contexto distinto. Acotar importa:
  # una credencial que aceptara cualquier rama permitiria a quien pudiera crear
  # una rama en el repositorio desplegar a produccion.
  federated "$app_id" "github-branch-${GITHUB_BRANCH}" \
    "repo:${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}" \
    "Integraciones a la rama ${GITHUB_BRANCH}"

  federated "$app_id" "github-environment-produccion" \
    "repo:${GITHUB_REPO}:environment:produccion" \
    "Despliegues al entorno de produccion"

  federated "$app_id" "github-pull-request" \
    "repo:${GITHUB_REPO}:pull_request" \
    "Validaciones de pull request (solo lectura en la practica)"
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
  for role in "AcrPush" "Contributor"; do
    log_info "Asignando '$role' sobre el grupo de recursos..."
    retry_until 8 5 az role assignment create \
      --assignee-object-id "$principal_id" \
      --assignee-principal-type ServicePrincipal \
      --role "$role" \
      --scope "$scope" \
      --output none 2>/dev/null || log_info "  La asignacion ya existia."
  done
}

print_github_configuration() {
  local app_id="$1"
  local tenant_id
  tenant_id="$(az account show --query tenantId -o tsv)"

  cat <<EOF

================================================================================
CONFIGURACION A REGISTRAR EN GITHUB
================================================================================

Secrets (Settings -> Secrets and variables -> Actions -> Secrets):

  AZURE_CLIENT_ID        $app_id
  AZURE_TENANT_ID        $tenant_id
  AZURE_SUBSCRIPTION_ID  $SUBSCRIPTION_ID

Variables (misma pantalla, pestana Variables):

  AZURE_RESOURCE_GROUP   $RESOURCE_GROUP
  AZURE_LOCATION         $LOCATION
  NAME_PREFIX            $NAME_PREFIX
  APP_SERVICE_SKU        $APP_SERVICE_SKU

Ninguno de estos valores es un secreto en sentido estricto: son identificadores
y no sirven de nada sin un token firmado por GitHub para este repositorio y esta
rama. Se registran como secrets por costumbre y para no publicar la topologia de
la suscripcion en los registros de cada corrida.

Con esto, 'az login' en el pipeline funciona sin contrasena alguna.
================================================================================
EOF
}

main "$@"
