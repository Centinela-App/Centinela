#!/usr/bin/env bash
# Integration fix ISS-S2-002/010/011.
# Creates database principals for the production Web App and staging slot, then
# configures JDBC passwordless settings.
#
# CAMINO DE CONEXION
#   Ruta preferida: Private Endpoint. Si el runner esta unido a la VNet (Cloud Shell
#   inyectado, jumpbox o VPN), se conecta por la IP privada y nada mas ocurre.
#
#   Ruta de respaldo (maquina de escritorio fuera de la VNet): se abre una VENTANA
#   TEMPORAL de acceso publico acotada a la IP publica del operador, se ejecuta el
#   bootstrap y se REVIERTE SIEMPRE mediante 'trap EXIT' -- incluso si el script
#   falla o se interrumpe con Ctrl-C. El estado final es identico al de diseno:
#   publicNetworkAccess=Disabled y sin reglas de firewall.
#
#   La ventana NO debilita la autenticacion: password auth sigue Disabled, asi que
#   la unica credencial valida sigue siendo un token de Microsoft Entra ID.
#
#   Para prohibir la ruta de respaldo (p. ej. en CI con runner en la VNet), exporta
#   CENTINELA_ALLOW_PUBLIC_WINDOW=0: el script fallara en vez de abrir la ventana.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly SLOT_NAME="staging"
readonly DATABASE_NAME="centinela"
readonly TEMP_FIREWALL_RULE="centinela-deployer-temp"

# Permite prohibir la ventana temporal (runners que ya viven en la VNet).
ALLOW_PUBLIC_WINDOW="${CENTINELA_ALLOW_PUBLIC_WINDOW:-1}"
# Estado de la ventana, para que el trap sepa que revertir.
WINDOW_SERVER=""
WINDOW_OPEN=0

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

# --- Ventana temporal de acceso publico (ruta de respaldo) ----------------------

# Intenta 'SELECT 1' contra el servidor. 0 = hay camino de red utilizable.
probe_connectivity() {
  local host="$1" admin="$2" token="$3" timeout="${4:-10}"
  PGPASSWORD="$token" psql \
    "host=$host port=5432 dbname=postgres user=$admin sslmode=require connect_timeout=$timeout" \
    -Atc 'SELECT 1' >/dev/null 2>&1
}

# IP publica del operador. Se consultan varios proveedores: si uno esta caido, el
# despliegue no debe detenerse por eso.
detect_deployer_ip() {
  local url ip
  for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
    ip="$(curl -fsS --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]')" || continue
    if printf '%s' "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

# Revierte SIEMPRE: registrado con 'trap EXIT' antes de abrir nada.
close_deployer_window() {
  local exit_code=$?
  if [ "$WINDOW_OPEN" -eq 1 ] && [ -n "$WINDOW_SERVER" ]; then
    log_warn "Cerrando la ventana temporal de acceso publico de '$WINDOW_SERVER'..."
    az postgres flexible-server firewall-rule delete \
      --server-name "$WINDOW_SERVER" --resource-group "$RESOURCE_GROUP" \
      --name "$TEMP_FIREWALL_RULE" --yes --output none 2>/dev/null || true
    if az postgres flexible-server update \
        --name "$WINDOW_SERVER" --resource-group "$RESOURCE_GROUP" \
        --public-access Disabled --output none 2>/dev/null; then
      log_info "Acceso publico de PostgreSQL restaurado a Disabled."
    else
      log_error "NO se pudo cerrar la ventana. Cierrala a mano de inmediato:"
      log_error "  az postgres flexible-server firewall-rule delete --server-name $WINDOW_SERVER --resource-group $RESOURCE_GROUP --name $TEMP_FIREWALL_RULE --yes"
      log_error "  az postgres flexible-server update --name $WINDOW_SERVER --resource-group $RESOURCE_GROUP --public-access Disabled"
    fi
    WINDOW_OPEN=0
  fi
  return "$exit_code"
}

# close_leaked_window <servidor> — cierra una ventana que quedo abierta porque una
# corrida anterior murio sin poder ejecutar su trap (SIGKILL, corte de energia).
close_leaked_window() {
  local server="$1" pub rules
  pub="$(az postgres flexible-server show --name "$server" --resource-group "$RESOURCE_GROUP" \
    --query 'network.publicNetworkAccess' -o tsv 2>/dev/null || echo '')"
  [ "$pub" = "Enabled" ] || return 0

  log_warn "DETECTADA una ventana de acceso publico ABIERTA en '$server' de una corrida previa."
  rules="$(az postgres flexible-server firewall-rule list --server-name "$server" \
    --resource-group "$RESOURCE_GROUP" --query "[?name=='$TEMP_FIREWALL_RULE'] | length(@)" \
    -o tsv 2>/dev/null || echo 0)"
  if [ "${rules:-0}" -ge 1 ] 2>/dev/null; then
    log_warn "Eliminando la regla temporal '$TEMP_FIREWALL_RULE' huerfana..."
    az postgres flexible-server firewall-rule delete --server-name "$server" \
      --resource-group "$RESOURCE_GROUP" --name "$TEMP_FIREWALL_RULE" \
      --yes --output none 2>/dev/null || true
  fi
  log_warn "Restaurando publicNetworkAccess=Disabled antes de continuar..."
  with_retry 3 az postgres flexible-server update --name "$server" \
    --resource-group "$RESOURCE_GROUP" --public-access Disabled --output none \
    || die "No se pudo cerrar la ventana huerfana de '$server'. Cierrala a mano antes de reintentar."
  log_info "Ventana huerfana cerrada."
}

# Abre la ventana acotada a una sola IP. El trap ya debe estar armado.
open_deployer_window() {
  local server="$1" ip
  [ "$ALLOW_PUBLIC_WINDOW" = "1" ] || return 1

  ip="$(detect_deployer_ip)" \
    || { log_error "No se pudo determinar la IP publica del operador."; return 1; }

  log_warn "Sin camino privado a PostgreSQL. Abriendo ventana TEMPORAL para la IP $ip..."
  log_warn "Se cerrara al terminar via trap (password auth sigue Disabled). Un SIGKILL la dejaria abierta; la proxima corrida la detecta y la cierra."

  # El orden importa: primero se habilita el plano publico, luego la unica regla.
  WINDOW_SERVER="$server"
  WINDOW_OPEN=1
  with_retry 3 az postgres flexible-server update \
    --name "$server" --resource-group "$RESOURCE_GROUP" \
    --public-access Enabled --output none \
    || { log_error "No se pudo habilitar el acceso publico temporal."; return 1; }
  with_retry 3 az postgres flexible-server firewall-rule create \
    --server-name "$server" --resource-group "$RESOURCE_GROUP" \
    --name "$TEMP_FIREWALL_RULE" \
    --start-ip-address "$ip" --end-ip-address "$ip" --output none \
    || { log_error "No se pudo crear la regla de firewall temporal."; return 1; }

  log_info "Ventana abierta para $ip. Esperando propagacion de la regla..."
  return 0
}

ensure_database() {
  local host="$1" admin="$2" token="$3" exists
  exists="$(PGPASSWORD="$token" psql "host=$host port=5432 dbname=postgres user=$admin sslmode=require" \
    -Atc "SELECT 1 FROM pg_database WHERE datname='${DATABASE_NAME}'" 2>/dev/null || true)"
  if [ "$exists" = "1" ]; then
    log_info "Base '$DATABASE_NAME' ya existe."
    return 0
  fi

  # OJO: la consulta de arriba silencia sus errores, asi que un timeout de red se
  # parece a "no existe". Por eso el CREATE debe tolerar que ya este creada: de lo
  # contrario una conexion intermitente convierte un estado correcto en un fallo.
  log_info "Creando base '$DATABASE_NAME'..."
  local out
  out="$(PGPASSWORD="$token" psql "host=$host port=5432 dbname=postgres user=$admin sslmode=require" \
        -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${DATABASE_NAME}" 2>&1)" && return 0

  if printf '%s' "$out" | grep -qi 'already exists'; then
    log_info "Base '$DATABASE_NAME' ya existia (la comprobacion previa no pudo confirmarlo)."
    return 0
  fi
  log_error "$out"
  return 1
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

  ensure_psql_on_path
  require_cmd psql

  # RED DE SEGURIDAD. El 'trap' de mas abajo cubre EXIT, INT y TERM, pero NINGUN
  # trap puede interceptar SIGKILL ni un corte de energia: si una corrida anterior
  # murio de ese modo, la ventana temporal sigue ABIERTA. Se detecta y se cierra
  # aqui, antes de hacer nada mas, para que el estado inseguro no sobreviva a la
  # siguiente ejecucion.
  close_leaked_window "$server"

  az postgres flexible-server show --name "$server" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe PostgreSQL '$server'."

  # Dos topologias posibles. Con Web App (Semanas 1-2): un principal por ambiente,
  # prod y staging. Sin Web App (Semana 3, ADR-009): las Container Apps comparten
  # la identidad id-<prefijo>-apps y basta UN principal. La deteccion es por
  # existencia del recurso y no por bandera, para que el mismo comando funcione
  # en ambas sin que el operador tenga que saber en cual esta.
  local apps_mode=0 apps_oid="" apps_role="${NAME_PREFIX}_apps"
  if az webapp show --name "$app" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    prod_oid="$(az webapp identity show --name "$app" --resource-group "$RESOURCE_GROUP" \
      --query principalId -o tsv)"
    staging_oid="$(az webapp identity show --name "$app" --resource-group "$RESOURCE_GROUP" \
      --slot "$SLOT_NAME" --query principalId -o tsv)"
    [ -n "$prod_oid" ] && [ -n "$staging_oid" ] || die "Faltan Managed Identities de produccion/staging."
  else
    apps_oid="$(az identity show -n "id-${NAME_PREFIX}-apps" -g "$RESOURCE_GROUP" \
      --query principalId -o tsv 2>/dev/null || true)"
    [ -n "$apps_oid" ] \
      || die "No existe la Web App '$app' NI la identidad 'id-${NAME_PREFIX}-apps'.
     En la topologia de contenedores, ejecuta antes provision-containerapps-identity.sh."
    apps_mode=1
    log_info "Topologia de contenedores: principal unico '$apps_role' para la identidad compartida."
  fi

  admin="$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)"
  [ -n "$admin" ] || die "Este bootstrap requiere sesion interactiva del admin Entra de PostgreSQL."
  token="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
  [ -n "$token" ] || die "No se pudo obtener token Entra para PostgreSQL."

  # Ruta preferida: Private Endpoint. Si el runner vive en la VNet, termina aqui.
  if probe_connectivity "$host" "$admin" "$token"; then
    log_info "Conectividad privada a '$host' confirmada (Private Endpoint)."
  else
    # Ruta de respaldo: ventana temporal por IP. El trap se arma ANTES de abrir
    # nada, para que un fallo o un Ctrl-C posterior nunca deje el puerto abierto.
    trap close_deployer_window EXIT INT TERM
    open_deployer_window "$server" \
      || die "Sin camino a '$host'. Ejecuta desde un runner unido a la VNet, o permite la ventana temporal (CENTINELA_ALLOW_PUBLIC_WINDOW=1)."

    # La regla de firewall tarda en propagar por el plano de datos, y el tiempo
    # varia entre corridas: se ha medido desde ~20s hasta mas de un minuto. Con
    # 6x10s el paso fallaba de forma intermitente sobre una ventana correctamente
    # abierta. 12x20s (~4 min, mas el timeout de cada sonda) cubre el caso lento
    # sin alargar el caso normal, que sale en el primer intento.
    local attempt=1
    until probe_connectivity "$host" "$admin" "$token" 15; do
      [ "$attempt" -lt 12 ] \
        || die "La ventana temporal quedo abierta pero '$host' sigue inaccesible tras $attempt intentos."
      log_warn "Aun sin respuesta (intento $attempt/12); reintentando en 20s..."
      sleep 20
      attempt=$((attempt + 1))
    done
    log_info "Conectividad establecida por la ventana temporal."
  fi

  # Que la sonda conecte UNA vez no garantiza que las siguientes conexiones entren:
  # la regla de firewall de PostgreSQL no propaga de forma atomica a todos los nodos
  # del gateway, asi que durante el primer minuto unas conexiones pasan y otras dan
  # 'Connection timed out'. Cada paso es idempotente (CREATE ... WHERE NOT EXISTS,
  # GRANT), asi que reintentarlo es seguro y absorbe esa intermitencia.
  with_retry 4 ensure_database "$host" "$admin" "$token" \
    || die "No se pudo asegurar la base '$DATABASE_NAME' tras varios reintentos."

  if [ "$apps_mode" -eq 1 ]; then
    with_retry 4 ensure_principal "$host" "$admin" "$token" "$apps_role" "$apps_oid" \
      || die "No se pudo asegurar el principal '$apps_role' tras varios reintentos."
    unset token PGPASSWORD
    # Sin Web App no hay app settings que escribir. La URL se inyecta como
    # variable de entorno al desplegar las Container Apps; se imprime aqui para
    # que el operador no tenga que reconstruir su forma exacta (el plugin de
    # autenticacion es la parte que nadie recuerda de memoria).
    log_info "Principal '$apps_role' listo. JDBC para las Container Apps:"
    log_info "  CENTINELA_POSTGRES_USER=$apps_role"
    log_info "  CENTINELA_POSTGRES_JDBC_URL=jdbc:postgresql://${host}:5432/${DATABASE_NAME}?sslmode=require&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin"
    log_info "ISS-S2-002/010/011 (topologia contenedores): base y principal Entra configurados."
    return 0
  fi

  with_retry 4 ensure_principal "$host" "$admin" "$token" "$prod_role" "$prod_oid" \
    || die "No se pudo asegurar el principal '$prod_role' tras varios reintentos."
  with_retry 4 ensure_principal "$host" "$admin" "$token" "$staging_role" "$staging_oid" \
    || die "No se pudo asegurar el principal '$staging_role' tras varios reintentos."
  unset token PGPASSWORD
  configure_app_settings "$app" "$server" "$prod_role" "$staging_role"
  log_info "ISS-S2-002/010/011: base, principales Entra y JDBC passwordless configurados."
}

main "$@"
