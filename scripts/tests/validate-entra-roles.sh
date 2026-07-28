#!/usr/bin/env bash
# validate-entra-roles.sh — ISS-S1-006 (TEST-S1-008)
# Verifica que la App Registration expone exactamente los 4 app roles funcionales,
# habilitados y con el tipo de miembro correcto (SERVICE=Application, resto=User).
# Consulta exclusivamente Microsoft Graph via Azure CLI.
#
#   exit 0 -> todas las verificaciones pasaron ; exit 1 -> alguna fallo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

readonly EXPECTED_ROLES=("SERVICE" "ANALYST" "ADMINISTRATOR" "AUDITOR")

PASS=0; FAIL=0; RESULTS=()
ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }
print_report() {
  printf '\n============== ISS-S1-006 / TEST-S1-008 ==============\n'
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  printf '%s\n' '------------------------------------------------------'
  printf 'Resumen: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
  printf '======================================================\n'
}
cleanup() { local rc="${1:-$?}"; trap - EXIT; print_report; [ "$rc" -ne 0 ] && exit "$rc"; exit "$(( FAIL > 0 ? 1 : 0 ))"; }
trap 'cleanup $?' EXIT

require_cmd az
require_cmd jq
require_cmd sha1sum
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."
load_parameters
validate_parameters

DISPLAY_NAME="${ENTRA_APP_DISPLAY_NAME:-${NAME_PREFIX}-api-week1}"
log_info "Validando App Registration: $DISPLAY_NAME"

APP_ID="$(az ad app list --display-name "$DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)"
if [ -n "$APP_ID" ] && [ "$APP_ID" != "None" ]; then
  ok "App Registration '$DISPLAY_NAME' existe (appId $(mask "$APP_ID"))."
else
  fail "App Registration '$DISPLAY_NAME' NO existe. Ejecutar scripts/provision-entra-app.sh."
  cleanup
fi

# Un app role por cada rol esperado, habilitado.
for r in "${EXPECTED_ROLES[@]}"; do
  enabled="$(az ad app show --id "$APP_ID" \
    --query "appRoles[?value=='$r' && isEnabled].value | [0]" -o tsv 2>/dev/null || echo MISSING)"
  if [ "$enabled" = "$r" ]; then
    ok "App role '$r' existe y esta habilitado."
  else
    fail "App role '$r' ausente o deshabilitado."
  fi
done

# Exactamente 4 app roles (ni de mas ni de menos).
count="$(az ad app show --id "$APP_ID" --query "length(appRoles)" -o tsv 2>/dev/null || echo 0)"
if [ "$count" = "4" ]; then
  ok "La App expone exactamente 4 app roles."
else
  fail "La App expone $count app roles (esperado 4)."
fi

# Tipo de miembro: SERVICE=Application ; resto=User.
svc_type="$(az ad app show --id "$APP_ID" \
  --query "appRoles[?value=='SERVICE'].allowedMemberTypes[0] | [0]" -o tsv 2>/dev/null || echo MISSING)"
if [ "$svc_type" = "Application" ]; then
  ok "Rol SERVICE con allowedMemberTypes=Application (identidad de servicio)."
else
  fail "Rol SERVICE allowedMemberTypes='$svc_type' (esperado 'Application')."
fi
for r in ANALYST ADMINISTRATOR AUDITOR; do
  t="$(az ad app show --id "$APP_ID" \
    --query "appRoles[?value=='$r'].allowedMemberTypes[0] | [0]" -o tsv 2>/dev/null || echo MISSING)"
  if [ "$t" = "User" ]; then
    ok "Rol $r con allowedMemberTypes=User."
  else
    fail "Rol $r allowedMemberTypes='$t' (esperado 'User')."
  fi
done


# Resource Server: issuer, audience y JWK URI deben estar aplicados en ambos slots.
hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"
app_name="${NAME_PREFIX}-app-${hash}"
tenant_id="$(az account show --query tenantId -o tsv)"
expected_issuer="https://login.microsoftonline.com/${tenant_id}/v2.0"
expected_audience="api://${APP_ID}"
expected_jwk="https://login.microsoftonline.com/${tenant_id}/discovery/v2.0/keys"

for slot in production staging; do
  slot_args=()
  [ "$slot" = "staging" ] && slot_args=(--slot staging)
  settings="$(az webapp config appsettings list --name "$app_name" --resource-group "$RESOURCE_GROUP" "${slot_args[@]}" -o json 2>/dev/null || echo '[]')"
  issuer="$(printf '%s' "$settings" | jq -r '.[] | select(.name=="CENTINELA_ENTRA_ISSUER_URI") | .value' | head -n1)"
  audience="$(printf '%s' "$settings" | jq -r '.[] | select(.name=="CENTINELA_ENTRA_AUDIENCE") | .value' | head -n1)"
  jwk="$(printf '%s' "$settings" | jq -r '.[] | select(.name=="CENTINELA_ENTRA_JWK_SET_URI") | .value' | head -n1)"

  [ "$issuer" = "$expected_issuer" ] && ok "$slot tiene issuer OAuth2 correcto." || fail "$slot tiene issuer OAuth2 incorrecto o ausente."
  [ "$audience" = "$expected_audience" ] && ok "$slot tiene audience OAuth2 correcto." || fail "$slot tiene audience OAuth2 incorrecto o ausente."
  [ "$jwk" = "$expected_jwk" ] && ok "$slot tiene JWK URI correcto." || fail "$slot tiene JWK URI incorrecto o ausente."
done

cleanup
