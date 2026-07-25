#!/usr/bin/env bash
# Integration fix ISS-S2-002/010/011.
# Creates database principals for the production Web App and staging slot, then
# configures JDBC passwordless settings. Must run from a host with private DNS and
# network reachability to the PostgreSQL Private Endpoint.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly SLOT_NAME="staging"
readonly DATABASE_NAME="centinela"

VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: $0 [--validate-only]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

resource_hash() {
  printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6
}
compute_postgres_server_name() { printf '%s-pg-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_web_app_name() { printf '%s-app-%s' "$NAME_PREFIX" "$(resource_hash)"; }

ensure_database() {
  local host="$1" admin="$2" token="$3" exists
  exists="$(PGPASSWORD="$token" psql "host=$host port=5432 dbname=postgres user=$admin sslmode=require" \
    -Atc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}'" 2>/dev/null || true)"
  if [ "$exists" = "1" ]; then
    log_info "Base '$DATABASE_NAME' ya existe."
  else
    log_info "Creando base '$DATABASE_NAME'..."
    PGPASSWORD="$token" psql "host=$host port=5432 dbname=postgres user=$admin sslmode=require" \
      -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${DATABASE_NAME}" >/dev/null
  fi
}

ensure_principal() {
  local host="$1" admin="$2" token="$3" role_name="$4" object_id="$5"
  log_info "Asegurando principal PostgreSQL '$role_name' para MI $(mask "$object_id")..."
  PGPASSWORD="$token" psql "host=$host port=5432 dbname=postgres user=$admin sslmode=require" \
    -v ON_ERROR_STOP=1 -v role_name="$role_name" -v object_id="$object_id" <<'SQL' >/dev/null
SELECT pg_catalog.pgaadauth_create_principal_with_oid(
    :'role_name', :'object_id', 'service', false, false)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role_name');
SQL

  PGPASSWORD="$token" psql "host=$host port=5432 dbname=${DATABASE_NAME} user=$admin sslmode=require" \
    -v ON_ERROR_STOP=1 -v role_name="$role_name" <<'SQL' >/dev/null
GRANT CONNECT ON DATABASE centinela TO :"role_name";
GRANT USAGE, CREATE ON SCHEMA public TO :"role_name";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"role_name";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO :"role_name";
SQL
}

configure_app_settings() {
  local app="$1" server="$2" prod_role="$3" staging_role="$4" jdbc_url
  jdbc_url="jdbc:postgresql://${server}.postgres.database.azure.com:5432/${DATABASE_NAME}?sslmode=require&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin"

  log_info "Configurando JDBC por Managed Identity en produccion y staging..."
  with_retry 3 az webapp config appsettings set --name "$app" --resource-group "$RESOURCE_GROUP" \
    --slot-settings \
      "CENTINELA_POSTGRES_JDBC_URL=$jdbc_url" \
      "CENTINELA_POSTGRES_USER=$prod_role" \
      "CENTINELA_FLAGGED_CASES_QUEUE=flagged-cases-production" \
      "CENTINELA_QUEUE_AUTO_START=true" \
    --output none
  with_retry 3 az webapp config appsettings set --name "$app" --resource-group "$RESOURCE_GROUP" \
    --slot "$SLOT_NAME" --slot-settings \
      "CENTINELA_POSTGRES_JDBC_URL=$jdbc_url" \
      "CENTINELA_POSTGRES_USER=$staging_role" \
      "CENTINELA_FLAGGED_CASES_QUEUE=flagged-cases-staging" \
      "CENTINELA_QUEUE_AUTO_START=true" \
    --output none
}

main() {
  load_parameters
  validate_parameters
  require_cmd az

  local server app host prod_oid staging_oid prod_role staging_role admin token
  server="$(compute_postgres_server_name)"
  app="$(compute_web_app_name)"
  host="${server}.postgres.database.azure.com"
  prod_role="${NAME_PREFIX}_case_prod"
  staging_role="${NAME_PREFIX}_case_staging"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "PostgreSQL MI bootstrap: $host -> roles '$prod_role' y '$staging_role'."
    log_info "--validate-only: no se conecta ni modifica Azure."
    return 0
  fi

  require_cmd psql
  az postgres flexible-server show --name "$server" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe PostgreSQL '$server'."
  az webapp show --name "$app" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Web App '$app'."

  prod_oid="$(az webapp identity show --name "$app" --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)"
  staging_oid="$(az webapp identity show --name "$app" --resource-group "$RESOURCE_GROUP" \
    --slot "$SLOT_NAME" --query principalId -o tsv)"
  [ -n "$prod_oid" ] && [ -n "$staging_oid" ] || die "Faltan Managed Identities de produccion/staging."

  admin="$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)"
  [ -n "$admin" ] || die "Este bootstrap requiere sesion interactiva del admin Entra de PostgreSQL."
  token="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
  [ -n "$token" ] || die "No se pudo obtener token Entra para PostgreSQL."

  # Falla de forma explicita si el runner no esta dentro/conectado a la VNet.
  PGPASSWORD="$token" psql "host=$host port=5432 dbname=postgres user=$admin sslmode=require connect_timeout=10" \
    -Atc 'SELECT 1' >/dev/null 2>&1 \
    || die "No hay conectividad privada a '$host'. Ejecuta este script desde un runner unido a la VNet."

  ensure_database "$host" "$admin" "$token"
  ensure_principal "$host" "$admin" "$token" "$prod_role" "$prod_oid"
  ensure_principal "$host" "$admin" "$token" "$staging_role" "$staging_oid"
  unset token PGPASSWORD
  configure_app_settings "$app" "$server" "$prod_role" "$staging_role"
  log_info "ISS-S2-002/010/011: base, principales Entra y JDBC passwordless configurados."
}

main "$@"
