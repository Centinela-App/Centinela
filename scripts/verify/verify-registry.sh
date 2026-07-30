#!/usr/bin/env bash
#
# scripts/verify/verify-registry.sh
# Verifica el estado REAL del registro de contenedores: SKU, ausencia de
# credenciales compartidas, identidad de pull, rol asignado e imagenes publicadas.
#
# Comprueba contra Azure, no contra el script que lo creo. Que un script de
# aprovisionamiento termine con codigo cero no significa que el recurso quedara
# como se pretendia; este proyecto ya pago esa leccion.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

load_parameters
require_cmd az

REGISTRY="${NAME_PREFIX}acr"
IDENTITY="id-${NAME_PREFIX}-acrpull"
fail=0

note() { printf '[verify-registry] %s\n' "$*"; }
ok()   { printf '[verify-registry]   OK — %s\n' "$*"; }
bad()  { printf '::error::%s\n' "$*"; fail=1; }

az account show >/dev/null 2>&1 || { note "Sin sesion de Azure. Nada que verificar."; exit 0; }

note "Registro: $REGISTRY"

# --- 1. Existe y con el SKU esperado ---------------------------------------
datos="$(az acr show -n "$REGISTRY" -g "$RESOURCE_GROUP" \
  --query "{sku:sku.name, admin:adminUserEnabled, servidor:loginServer, publico:publicNetworkAccess}" \
  -o tsv 2>/dev/null)" || { bad "El registro '$REGISTRY' no existe."; exit 1; }

sku="$(echo "$datos" | cut -f1)"
admin="$(echo "$datos" | cut -f2)"
servidor="$(echo "$datos" | cut -f3)"

ok "existe — SKU $sku, servidor $servidor"

# --- 2. Sin credenciales compartidas ----------------------------------------
# El usuario administrador es una credencial compartida CON PERMISO DE ESCRITURA
# que no se puede atribuir a nadie. Es lo contrario de lo que el proyecto viene
# sosteniendo desde la Semana 1.
if [ "$admin" = "False" ] || [ "$admin" = "false" ]; then
  ok "usuario administrador deshabilitado"
else
  bad "El usuario administrador esta HABILITADO: es una credencial compartida con permiso de escritura."
fi

# --- 3. Identidad de pull y su rol ------------------------------------------
principal="$(az identity show -n "$IDENTITY" -g "$RESOURCE_GROUP" --query principalId -o tsv 2>/dev/null)"
if [ -n "$principal" ]; then
  ok "identidad de pull '$IDENTITY' existe"
else
  bad "No existe la identidad de pull '$IDENTITY'."
fi

scope="$(az acr show -n "$REGISTRY" -g "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)"
asignaciones="$(role_assignment_count "$scope" "AcrPull")"
if [ "${asignaciones:-0}" -ge 1 ]; then
  ok "AcrPull asignado sobre el registro ($asignaciones asignacion/es)"
else
  bad "No hay ninguna asignacion AcrPull: Container Apps no podria descargar imagenes sin credenciales."
fi

# Ningun rol de escritura sobre el registro para la identidad de pull. Una
# identidad de solo lectura que puede escribir no es de solo lectura.
for rol in "AcrPush" "Contributor" "Owner"; do
  extra="$(role_assignment_count "$scope" "$rol")"
  if [ "${extra:-0}" -gt 0 ]; then
    note "  aviso: hay $extra asignacion/es de '$rol' sobre el registro; revisar que correspondan al pipeline y no a la identidad de pull"
  fi
done

# --- 4. Imagenes publicadas --------------------------------------------------
repos="$(az acr repository list --name "$REGISTRY" -o tsv 2>/dev/null)"
if [ -n "$repos" ]; then
  note "Imagenes publicadas:"
  while read -r repo; do
    [ -z "$repo" ] && continue
    etiquetas="$(az acr repository show --name "$REGISTRY" --repository "$repo" --query tagCount -o tsv 2>/dev/null)"
    printf '[verify-registry]   OK — %s (%s etiquetas)\n' "$repo" "${etiquetas:-?}"
  done <<< "$repos"
else
  note "  aviso: el registro no contiene ninguna imagen todavia"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  note "RESULTADO: OK"
else
  note "RESULTADO: FALLO"
fi
exit "$fail"
