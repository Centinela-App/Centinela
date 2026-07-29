#!/usr/bin/env bash
#
# scripts/tests/check-appservice-quota.sh
# Diagnostico de cuota de App Service por region.
#
# Motivo: una suscripcion puede tener el SKU disponible en una region y aun asi
# rechazar el despliegue con 'SubscriptionIsOverQuotaForSku' (limite de VMs = 0).
# Las suscripciones Pay-As-You-Go creadas recientemente nacen con cuota cero y hay
# que solicitarla. La cuota es POR REGION, asi que casi siempre existe otra region
# donde el mismo SKU si se puede desplegar.
#
# Este script NO crea infraestructura del proyecto: usa un Resource Group efimero
# (gratis, se elimina al terminar) y una validacion ARM, que ejecuta exactamente el
# mismo preflight que fallaria en el despliegue real.
#
# Uso:
#   bash scripts/tests/check-appservice-quota.sh                     # regiones habituales
#   bash scripts/tests/check-appservice-quota.sh eastus2 westus2     # regiones concretas
#
# Variables: SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

DEFAULT_REGIONS=(eastus2 eastus centralus westus2 westus3 southcentralus canadacentral northeurope westeurope)

sku_tier() {
  case "${1^^}" in
    F1)                                          echo "Free" ;;
    D1)                                          echo "Shared" ;;
    B1|B2|B3)                                    echo "Basic" ;;
    S1|S2|S3)                                    echo "Standard" ;;
    P1V2|P2V2|P3V2)                              echo "PremiumV2" ;;
    P0V3|P1V3|P2V3|P3V3|P4V3|P5V3)               echo "PremiumV3" ;;
    P1MV3|P2MV3|P3MV3|P4MV3|P5MV3)               echo "PremiumV3" ;;
    I1|I2|I3)                                    echo "Isolated" ;;
    I1V2|I2V2|I3V2|I4V2|I5V2|I6V2)               echo "IsolatedV2" ;;
    *)                                           echo "" ;;
  esac
}

render_probe_template() {
  cat <<'JSON'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "type": "string" },
    "skuName":  { "type": "string" },
    "skuTier":  { "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.Web/serverfarms",
      "apiVersion": "2023-01-01",
      "name": "quota-probe-plan",
      "location": "[parameters('location')]",
      "kind": "linux",
      "sku": {
        "name": "[parameters('skuName')]",
        "tier": "[parameters('skuTier')]",
        "capacity": 1
      },
      "properties": { "reserved": true }
    }
  ]
}
JSON
}

main() {
  load_parameters
  validate_parameters
  require_cmd az

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  local tier; tier="$(sku_tier "$APP_SERVICE_SKU")"
  [ -n "$tier" ] || die "SKU '$APP_SERVICE_SKU' no reconocido."

  local regions=()
  if [ "$#" -gt 0 ]; then regions=("$@"); else regions=("${DEFAULT_REGIONS[@]}"); fi

  # Resource Group efimero: no toca el del proyecto ni fija su region.
  local probe_rg="${RESOURCE_GROUP}-quota-probe-$$"
  local tmp_dir template_file
  tmp_dir="$(mktemp -d)"
  template_file="$tmp_dir/probe.json"
  render_probe_template > "$template_file"
  # shellcheck disable=SC2064
  trap "az group delete --name '$probe_rg' --yes --no-wait >/dev/null 2>&1 || true; rm -rf '$tmp_dir'" EXIT

  log_info "Sondeando cuota de App Service SKU '$APP_SERVICE_SKU' (tier $tier)..."
  log_info "Resource Group efimero: $probe_rg (se elimina al terminar)"
  az group create --name "$probe_rg" --location "${regions[0]}" --output none

  local region available=() blocked=()
  for region in "${regions[@]}"; do
    printf '  %-18s ' "$region" >&2
    if az deployment group validate \
         --resource-group "$probe_rg" \
         --template-file "$template_file" \
         --parameters location="$region" skuName="$APP_SERVICE_SKU" skuTier="$tier" \
         --output none 2>/dev/null; then
      printf 'DISPONIBLE\n' >&2
      available+=("$region")
    else
      printf 'sin cuota\n' >&2
      blocked+=("$region")
    fi
  done

  log_info "──────────────────────────────────────────────────────────────"
  if [ "${#available[@]}" -eq 0 ]; then
    log_error "Ninguna region probada admite '$APP_SERVICE_SKU' en esta suscripcion."
    log_error "Solicita aumento de cuota: Portal > Suscripciones > Uso + cuotas > Solicitar aumento."
    return 1
  fi

  log_info "Regiones con cuota para '$APP_SERVICE_SKU': ${available[*]}"
  [ "${#blocked[@]}" -gt 0 ] && log_warn "Regiones SIN cuota: ${blocked[*]}"

  local in_list=0 r
  for r in "${available[@]}"; do [ "$r" = "$LOCATION" ] && in_list=1; done
  if [ "$in_list" -eq 1 ]; then
    log_info "Tu LOCATION actual ('$LOCATION') tiene cuota. No hay nada que cambiar."
  else
    log_warn "Tu LOCATION actual ('$LOCATION') NO tiene cuota."
    log_warn "Cambia LOCATION en .env a '${available[0]}' y despliega sobre un Resource Group nuevo o vacio."
  fi
}

main "$@"
