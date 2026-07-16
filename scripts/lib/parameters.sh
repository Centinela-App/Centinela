#!/usr/bin/env bash
# parameters.sh — carga y validacion de parametros. Requiere common.sh ya cargado.

REQUIRED_PARAMS=(SUBSCRIPTION_ID LOCATION RESOURCE_GROUP NAME_PREFIX APP_SERVICE_SKU)

# load_parameters — carga .env del raiz del repo (o $ENV_FILE). Env vars ya presentes ganan.
load_parameters() {
  local params_dir; params_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local env_file="${ENV_FILE:-$params_dir/../../.env}"
  if [ -f "$env_file" ]; then
    log_info "Cargando parametros desde $env_file"
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  else
    log_info "Sin archivo .env; usando variables de entorno del proceso."
  fi
}

# validate_parameters — fail-fast si falta un parametro o el formato es invalido.
validate_parameters() {
  local missing=() p
  for p in "${REQUIRED_PARAMS[@]}"; do
    [ -z "${!p:-}" ] && missing+=("$p")
  done
  [ "${#missing[@]}" -gt 0 ] && die "Faltan parametros obligatorios: ${missing[*]}. Ver .env.example."

  [[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
    || die "SUBSCRIPTION_ID no tiene formato UUID valido."
  [[ "$NAME_PREFIX" =~ ^[a-z0-9]{3,11}$ ]] \
    || die "NAME_PREFIX debe ser 3-11 minusculas/numeros (actual: '$NAME_PREFIX')."
  [[ "$RESOURCE_GROUP" =~ ^[A-Za-z0-9._-]{1,90}$ ]] \
    || die "RESOURCE_GROUP tiene caracteres invalidos."
  [ -n "$LOCATION" ] || die "LOCATION vacio."
  [ -n "$APP_SERVICE_SKU" ] || die "APP_SERVICE_SKU vacio."

  log_info "Parametros validados correctamente."
}
