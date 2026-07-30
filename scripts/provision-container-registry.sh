#!/usr/bin/env bash
#
# scripts/provision-container-registry.sh
# ISS-S3-007 — Registro de contenedores privado con pull sin credenciales.
#
# Alcance ESTRICTO:
#   - Crear un Azure Container Registry SKU Basic, privado (admin user deshabilitado).
#   - Crear una Managed Identity asignada por el usuario para que las Container Apps
#     hagan pull sin usuario ni contrasena.
#   - Asignar a esa identidad el rol AcrPull, y solo ese.
#   - Idempotente: reejecutar converge al mismo estado.
#
# NO construye ni publica imagenes (eso lo hace el pipeline) ni crea Container Apps.
#
# ---------------------------------------------------------------------------
# Por que ACR Basic y no un nivel gratuito
# ---------------------------------------------------------------------------
# ACR NO tiene nivel gratuito. Ninguno de sus SKU lo es. Basic cuesta unos
# 0,167 USD/dia (~5 USD/mes, ~1,20 USD por la semana del proyecto) e incluye
# 10 GiB de almacenamiento y 2 webhooks.
#
# La alternativa realmente gratuita es GitHub Container Registry (ghcr.io), que
# admite imagenes privadas sin costo. Se descarto por una razon concreta: ACR se
# integra con Managed Identity, de modo que Container Apps hace pull SIN
# almacenar credencial alguna. Con ghcr.io habria que guardar un Personal Access
# Token como secreto de la Container App — exactamente el tipo de credencial de
# larga duracion que el proyecto viene evitando desde la Semana 1. Se paga
# ~1,20 USD por no tener ese secreto.
#
# Limites del SKU Basic, para el reporte de costos:
#   - Almacenamiento incluido : 10 GiB (el excedente se factura aparte)
#   - Operaciones de lectura  : 10 000/dia incluidas
#   - Operaciones de escritura: 1 000/dia incluidas
#   - Ancho de banda descarga : 30 GiB/dia
#   - Sin replicacion geografica, sin ambitos de token, sin red privada
#
# Con dos imagenes de ~250 MB y una decena de construcciones diarias, el consumo
# se mantiene holgadamente dentro de lo incluido.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly ACR_SKU="Basic"
readonly ACR_PULL_ROLE="AcrPull"

VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: $0 [--validate-only]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

main() {
  load_parameters
  validate_parameters
  require_cmd az

  # ACR exige nombre alfanumerico sin guiones, 5-50 caracteres.
  local registry_name="${NAME_PREFIX}acr"
  local identity_name="id-${NAME_PREFIX}-acrpull"

  [[ "$registry_name" =~ ^[a-z0-9]{5,50}$ ]] \
    || die "Nombre de registro invalido: '$registry_name'. Revisa NAME_PREFIX."

  log_info "Plan de ISS-S3-007:"
  log_info "  Registro          : $registry_name (SKU $ACR_SKU, admin deshabilitado)"
  log_info "  Identidad de pull : $identity_name"
  log_info "  Rol asignado      : $ACR_PULL_ROLE (unicamente)"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "Modo --validate-only: no se crea nada."
    exit 0
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Despliega primero las semanas 1 y 2."

  ensure_providers
  create_registry "$registry_name"
  local identity_principal identity_id
  identity_principal="$(create_pull_identity "$identity_name")"
  identity_id="$(az identity show --name "$identity_name" --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)"

  assign_pull_role "$registry_name" "$identity_principal"
  verify "$registry_name" "$identity_name"

  log_info "ISS-S3-007 OK"
  log_info "  ACR_LOGIN_SERVER=$(az acr show -n "$registry_name" -g "$RESOURCE_GROUP" --query loginServer -o tsv)"
  log_info "  ACR_PULL_IDENTITY_ID=$identity_id"
}

# Una suscripcion nueva no tiene registrados los proveedores de recursos que no
# ha usado nunca. El error que devuelve Azure —MissingSubscriptionRegistration—
# no menciona que se resuelve con un solo comando, asi que sin esto el script
# falla de una forma que parece un problema de permisos y no lo es.
# El registro es idempotente y a nivel de suscripcion: reejecutarlo no hace nada.
ensure_providers() {
  local provider="Microsoft.ContainerRegistry"
  local estado
  estado="$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")"

  if [ "$estado" = "Registered" ]; then
    log_info "Proveedor $provider ya registrado."
    return
  fi

  log_info "Registrando el proveedor $provider (puede tardar un minuto)..."
  az provider register --namespace "$provider" --wait --only-show-errors \
    || die "No se pudo registrar $provider. Requiere permisos de colaborador sobre la suscripcion."
  log_info "Proveedor $provider registrado."
}

create_registry() {
  local name="$1"
  if az acr show --name "$name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "El registro '$name' ya existe; se converge su configuracion."
  else
    log_info "Creando registro '$name'..."
    az acr create \
      --name "$name" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --sku "$ACR_SKU" \
      --admin-enabled false \
      --output none
  fi

  # El usuario administrador es una credencial compartida de larga duracion con
  # permiso de escritura. Se apaga explicitamente en cada corrida por si alguien
  # lo activo para "probar algo rapido".
  az acr update --name "$name" --resource-group "$RESOURCE_GROUP" \
    --admin-enabled false --output none
}

create_pull_identity() {
  local name="$1"
  if ! az identity show --name "$name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Creando identidad administrada '$name'..."
    az identity create --name "$name" --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" --output none
  fi
  az identity show --name "$name" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv
}

assign_pull_role() {
  local registry_name="$1" principal_id="$2"
  local scope
  scope="$(az acr show --name "$registry_name" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"

  # La propagacion de una identidad recien creada tarda unos segundos; sin
  # reintento la asignacion falla de forma intermitente y el script parece
  # inestable. 'assign_role' usa la API REST por el motivo documentado en
  # lib/common.sh.
  log_info "Asignando $ACR_PULL_ROLE sobre el registro..."
  with_retry 5 assign_role "$ACR_PULL_ROLE" "$principal_id" "$scope" \
    || die "Sin este rol, Container Apps no puede descargar imagenes del registro sin credenciales."
}

verify() {
  local registry_name="$1" identity_name="$2"
  local admin_enabled
  admin_enabled="$(az acr show --name "$registry_name" --resource-group "$RESOURCE_GROUP" \
    --query adminUserEnabled -o tsv)"
  [ "$admin_enabled" = "false" ] \
    || die "El usuario administrador del registro sigue habilitado: es una credencial compartida."

  local scope role_count
  scope="$(az acr show --name "$registry_name" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  role_count="$(role_assignment_count "$scope" "$ACR_PULL_ROLE")"
  [ "${role_count:-0}" -ge 1 ] || die "No hay ninguna asignacion $ACR_PULL_ROLE sobre el registro."

  az identity show --name "$identity_name" --resource-group "$RESOURCE_GROUP" >/dev/null \
    || die "La identidad de pull no existe."

  log_info "Verificacion: admin deshabilitado, identidad creada y $ACR_PULL_ROLE asignado."
}

main "$@"
