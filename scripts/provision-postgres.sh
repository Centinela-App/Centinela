#!/usr/bin/env bash
#
# scripts/provision-postgres.sh
# ISS-S2-002 - Provisionar PostgreSQL Flexible Server privado (almacen de casos).
#
# Alcance ESTRICTO de la Issue S2-002:
#   - Crear/asegurar 1 servidor PostgreSQL Flexible Server (Burstable B1ms, Free tier).
#   - Red PRIVADA por Private Endpoint (coherente con el patron de Semana 1 para
#     Storage): el servidor se crea en modo "acceso publico sin reglas de firewall"
#     y luego se DESHABILITA el acceso publico de red; el unico camino de entrada es
#     un Private Endpoint en la subred 'snet-private-endpoints', resuelto por la zona
#     DNS privada 'privatelink.postgres.database.azure.com'.
#   - Autenticacion Microsoft Entra ID EXCLUSIVA (password auth deshabilitada): no
#     existe ninguna contrasena de conexion que guardar. La app/consumidor se conecta
#     por Managed Identity (token). Ver §13 del backlog y 3_Estrategia_Respaldo.md.
#   - Respaldo automatico gestionado por la plataforma (retencion configurable, PITR).
#   - Idempotente: reejecutar converge al mismo estado sin duplicar recursos.
#
# No crea tablas ni el esquema de casos (eso es ISS-S2-010). No abre acceso publico.
#
# Sobre la contrasena efimera de creacion:
#   Algunos comandos 'az postgres flexible-server create' exigen un admin nativo en la
#   llamada de creacion. Para NO introducir ningun secreto en el repo, se genera una
#   contrasena ALEATORIA en tiempo de ejecucion, se usa solo para crear el servidor y
#   acto seguido se DESHABILITA la autenticacion por password (--password-auth Disabled).
#   La contrasena nunca se imprime ni se persiste: queda inservible tras la creacion.
#
# Prerequisitos (validados al inicio):
#   - Azure CLI + sesion activa (Azure Cloud Shell).
#   - Suscripcion activa == SUBSCRIPTION_ID.
#   - Resource Group + VNet + subred 'snet-private-endpoints' (Semana 1).
#
# Variables (ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX
#
# Variables opcionales (con defaults):
#   POSTGRES_TIER              nivel de computo           (default: Burstable)
#   POSTGRES_SKU              SKU de computo             (default: Standard_B1ms)
#   POSTGRES_STORAGE_GB       tamano de storage en GiB   (default: 32)
#   POSTGRES_VERSION          version mayor de Postgres  (default: 16)
#   POSTGRES_BACKUP_RETENTION dias de retencion de backup(default: 7)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue S2-002 ---------------------------------------------

readonly SUBNET_PE="snet-private-endpoints"
readonly DNS_ZONE_PG="privatelink.postgres.database.azure.com"
readonly ADMIN_USER="pgadmin"   # solo usado de forma efimera durante la creacion.

# Defaults sobreescribibles por entorno.
readonly TIER="${POSTGRES_TIER:-Burstable}"
readonly SKU="${POSTGRES_SKU:-Standard_B1ms}"
readonly STORAGE_GB="${POSTGRES_STORAGE_GB:-32}"
readonly PG_VERSION="${POSTGRES_VERSION:-16}"
readonly BACKUP_RETENTION="${POSTGRES_BACKUP_RETENTION:-7}"

readonly TAGS=(
  "project=centinela"
  "week=2"
  "team=celula-centinela"
  "issue=ISS-S2-002"
)

# --- Helpers de nombrado (deterministas, mismo criterio que Storage/Cosmos) ----

# Cosmos/Storage usan sha1 de prefix|sub|rg. El servidor Postgres exige nombre
# global-unico, 3..63 chars, [a-z0-9-], sin guion inicial/final.
compute_postgres_server_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-pg-%s' "$prefix" "$hash"
}
compute_vnet_name() { printf '%s-vnet-week1' "$1"; }

assert_server_name_valid() {
  local name="$1"
  [ "${#name}" -ge 3 ] && [ "${#name}" -le 63 ] \
    || die "Nombre de servidor Postgres invalido (longitud fuera de 3..63): '$name'"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] \
    || die "Nombre de servidor Postgres invalido (solo [a-z0-9-], sin guion inicial/final): '$name'"
}

# Contrasena efimera valida para Postgres (>=8, con mayuscula, minuscula, digito y
# caracter especial). Nunca se imprime ni se persiste.
generate_ephemeral_password() {
  local base
  if command -v openssl >/dev/null 2>&1; then
    base="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
  else
    base="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
  fi
  # Garantiza complejidad aunque base quede corto.
  printf '%sAa9#%s' "${base:0:24}" "$(printf '%s' "$base" | tail -c 4)"
}

# --- Idempotencia: valida un servidor existente --------------------------------

# Devuelve 0 si el servidor existe (no reescribe computo); 1 si no existe.
server_exists() {
  local server="$1" rg="$2"
  az postgres flexible-server show --name "$server" --resource-group "$rg" \
    >/dev/null 2>&1
}

# --- Side effects (Azure) -------------------------------------------------------

create_server() {
  local server="$1" rg="$2"
  local pwd; pwd="$(generate_ephemeral_password)"

  log_info "Creando servidor Postgres '$server' ($TIER/$SKU, ${STORAGE_GB}GiB, v$PG_VERSION)..."
  # --public-access None: modo de red "publico sin reglas de firewall" (habilita
  #   Private Endpoint posterior); NO abre el servidor a internet.
  # --microsoft-entra-auth Enabled: habilita autenticacion Entra ID. Este flag se
  #   llamaba --active-directory-auth; az CLI lo renombro y ya NO acepta el viejo.
  # Sin --high-availability: ese flag tampoco existe ya en 'create', y el tier
  #   Burstable (B1ms) no soporta HA. El valor por defecto es Disabled.
  # La password efimera solo satisface la creacion; se anula en harden_server.
  with_retry 3 az postgres flexible-server create \
    --name "$server" \
    --resource-group "$rg" \
    --location "$LOCATION" \
    --tier "$TIER" \
    --sku-name "$SKU" \
    --storage-size "$STORAGE_GB" \
    --version "$PG_VERSION" \
    --public-access None \
    --backup-retention "$BACKUP_RETENTION" \
    --geo-redundant-backup Disabled \
    --microsoft-entra-auth Enabled \
    --admin-user "$ADMIN_USER" \
    --admin-password "$pwd" \
    --tags "${TAGS[@]}" \
    --yes \
    --output none
  unset pwd
  log_info "Servidor Postgres creado."
}

# Asegura el admin Entra ID = principal que ejecuta el script (nunca un secreto).
ensure_entra_admin() {
  local server="$1" rg="$2"
  local oid upn
  oid="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")"
  upn="$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "")"
  if [ -z "$oid" ]; then
    log_warn "No se pudo resolver el usuario Entra actual (¿service principal?). Configura el admin Entra manualmente."
    return 0
  fi

  if entra_admin_exists "$server" "$rg" "$oid"; then
    log_info "Admin Entra ID ya configurado ($(mask "$oid"))."
    return 0
  fi

  log_info "Asignando admin Entra ID ($(mask "$oid"))..."
  if with_retry 3 az postgres flexible-server microsoft-entra-admin create \
      --server-name "$server" --resource-group "$rg" \
      --display-name "${upn:-$ADMIN_USER}" --object-id "$oid" --type User \
      --output none; then
    return 0
  fi

  # La creacion puede FALLAR habiendo surtido efecto: Azure aplica el cambio y
  # despues devuelve InternalServerError. El reintento choca entonces contra
  # '42710: role already exists' y el paso muere pese a estar el admin creado.
  # Por eso no se confia en el codigo de salida, se consulta el estado real.
  if entra_admin_exists "$server" "$rg" "$oid"; then
    log_warn "La creacion reporto error, pero el admin Entra SI quedo configurado. Se continua."
    return 0
  fi
  die "No se pudo configurar el admin Entra ID en '$server'."
}

# 'ad-admin' fue renombrado a 'microsoft-entra-admin'; az CLI ya no reconoce el viejo.
entra_admin_exists() {
  local server="$1" rg="$2" oid="$3"
  az postgres flexible-server microsoft-entra-admin list \
    --server-name "$server" --resource-group "$rg" \
    --query "[?objectId=='$oid'] | [0].objectId" -o tsv 2>/dev/null | grep -q "$oid"
}

# Deshabilita password auth (anula la password efimera) y cierra el acceso publico.
harden_server() {
  local server="$1" rg="$2"
  log_info "Endureciendo servidor: password-auth Disabled + public-network-access Disabled..."
  # OJO: en 'update' el flag es --public-access (Enabled|Disabled). No existe
  # --public-network-access: ese es solo el nombre de la propiedad al leerla.
  with_retry 3 az postgres flexible-server update \
    --name "$server" --resource-group "$rg" \
    --password-auth Disabled \
    --public-access Disabled \
    --output none
}

ensure_private_dns_zone() {
  local rg="$1" vnet="$2"
  if az network private-dns zone show --name "$DNS_ZONE_PG" --resource-group "$rg" >/dev/null 2>&1; then
    log_info "Zona DNS privada '$DNS_ZONE_PG' ya existe."
  else
    log_info "Creando zona DNS privada '$DNS_ZONE_PG'..."
    with_retry 3 az network private-dns zone create \
      --name "$DNS_ZONE_PG" --resource-group "$rg" --output none
  fi

  local link="${vnet}-pg-link"
  if az network private-dns link vnet show \
        --zone-name "$DNS_ZONE_PG" --resource-group "$rg" --name "$link" >/dev/null 2>&1; then
    log_info "Vinculo VNet '$link' ya existe."
  else
    log_info "Vinculando zona DNS a la VNet '$vnet'..."
    with_retry 3 az network private-dns link vnet create \
      --zone-name "$DNS_ZONE_PG" --resource-group "$rg" --name "$link" \
      --virtual-network "$vnet" --registration-enabled false --output none
  fi
}

ensure_private_endpoint() {
  local server="$1" rg="$2" vnet="$3" pe="$4"
  local server_id
  server_id="$(az postgres flexible-server show --name "$server" --resource-group "$rg" \
    --query id -o tsv)"

  if az network private-endpoint show --name "$pe" --resource-group "$rg" >/dev/null 2>&1; then
    log_info "Private Endpoint '$pe' ya existe."
  else
    log_info "Creando Private Endpoint '$pe' en '$SUBNET_PE' (groupId=postgresqlServer)..."
    with_retry 3 az network private-endpoint create \
      --name "$pe" --resource-group "$rg" --location "$LOCATION" \
      --vnet-name "$vnet" --subnet "$SUBNET_PE" \
      --private-connection-resource-id "$server_id" \
      --group-id postgresqlServer \
      --connection-name "${pe}-plsc" \
      --output none
  fi

  if pe_dns_zone_group_exists "$pe" "$rg"; then
    log_info "DNS zone group del PE ya existe (registro A automatico)."
  else
    log_info "Registrando IP privada en la zona DNS (dns-zone-group)..."
    with_retry 3 az network private-endpoint dns-zone-group create \
      --resource-group "$rg" --endpoint-name "$pe" --name default \
      --private-dns-zone "$DNS_ZONE_PG" --zone-name postgres --output none
  fi
}

verify_all_resources() {
  local server="$1" rg="$2" pe="$3"

  log_info "Verificando servidor, red privada y respaldo..."
  az postgres flexible-server show --name "$server" --resource-group "$rg" >/dev/null 2>&1 \
    || die "No existe el servidor Postgres '$server'."

  local sku pub pwd_auth aad_auth retention
  sku="$(az postgres flexible-server show --name "$server" --resource-group "$rg" \
    --query 'sku.name' -o tsv 2>/dev/null || echo "?")"
  pub="$(az postgres flexible-server show --name "$server" --resource-group "$rg" \
    --query 'network.publicNetworkAccess' -o tsv 2>/dev/null || echo "?")"
  pwd_auth="$(az postgres flexible-server show --name "$server" --resource-group "$rg" \
    --query 'authConfig.passwordAuth' -o tsv 2>/dev/null || echo "?")"
  aad_auth="$(az postgres flexible-server show --name "$server" --resource-group "$rg" \
    --query 'authConfig.activeDirectoryAuth' -o tsv 2>/dev/null || echo "?")"
  retention="$(az postgres flexible-server show --name "$server" --resource-group "$rg" \
    --query 'backup.backupRetentionDays' -o tsv 2>/dev/null || echo "?")"

  az network private-endpoint show --name "$pe" --resource-group "$rg" >/dev/null 2>&1 \
    || die "No existe el Private Endpoint '$pe'."
  # Un PE sin registro A deja al servidor irresoluble por nombre dentro de la VNet.
  # Verificarlo es lo que distingue "creado" de "realmente alcanzable".
  retry_until 8 private_dns_has_a_records "$DNS_ZONE_PG" "$rg" \
    || die "El PE '$pe' existe pero '$DNS_ZONE_PG' no tiene registros A: PostgreSQL no seria resoluble desde la VNet."

  log_info "  OK servidor:        $server"
  log_info "  SKU:                $sku"
  log_info "  publicNetworkAccess:$pub"
  log_info "  passwordAuth:       $pwd_auth  ·  activeDirectoryAuth: $aad_auth"
  log_info "  backupRetention:    ${retention}d"
  log_info "  Private Endpoint:   $pe (groupId=postgresqlServer)"
}

# --- Main ----------------------------------------------------------------------

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 \
    || die "No hay sesion de Azure activa. Ejecuta 'az login' primero."

  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Ejecuta primero deploy-week1.sh."

  local server vnet pe
  server="$(compute_postgres_server_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  assert_server_name_valid "$server"
  vnet="$(compute_vnet_name "$NAME_PREFIX")"
  pe="${server}-pe"

  az network vnet subnet show --vnet-name "$vnet" --resource-group "$RESOURCE_GROUP" \
      --name "$SUBNET_PE" >/dev/null 2>&1 \
    || die "No existe la subred '$SUBNET_PE' en '$vnet'. Ejecuta primero scripts/provision-network.sh."

  log_info "Servidor Postgres objetivo: $server (longitud: ${#server})"
  log_info "VNet / subred PE:           $vnet / $SUBNET_PE"
  log_info "Autenticacion:              Entra ID exclusiva (password auth Disabled)"
  log_info "Respaldo:                   automatico, retencion ${BACKUP_RETENTION}d, geo-redundante Disabled"

  if server_exists "$server" "$RESOURCE_GROUP"; then
    log_info "Servidor '$server' ya existe. Sin recrear el computo (idempotente)."
  else
    create_server "$server" "$RESOURCE_GROUP"
  fi

  ensure_entra_admin      "$server" "$RESOURCE_GROUP"
  harden_server           "$server" "$RESOURCE_GROUP"
  ensure_private_dns_zone "$RESOURCE_GROUP" "$vnet"
  ensure_private_endpoint "$server" "$RESOURCE_GROUP" "$vnet" "$pe"
  verify_all_resources    "$server" "$RESOURCE_GROUP" "$pe"

  log_info "ISS-S2-002 OK: PostgreSQL '$server' privado (PE), sin acceso publico, respaldo activo."
}

main "$@"
