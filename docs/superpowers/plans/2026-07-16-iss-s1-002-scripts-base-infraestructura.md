# ISS-S1-002 · Scripts base de infraestructura — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir el armazón de scripts (orquestador + librería + validación + destrucción segura) para desplegar/destruir la infraestructura de Semana 1 sin crear todavía recursos concretos.

**Architecture:** Orquestador `deploy-week1.sh` con **registro de pasos** (Opción A) que llama scripts de provisión futuros si existen. Librería compartida `lib/common.sh` (logging, errores, reintentos, `mask`) y `lib/parameters.sh` (carga `.env` + validación fail-fast). Destrucción protegida por tecleo del nombre del RG. Validación en vivo contra Azure CLI. Pruebas en bash puro a través de los dos test scripts autorizados.

**Tech Stack:** Bash 5.2, Azure CLI 2.88, shellcheck 0.11.

## Global Constraints

- Solo se pueden crear/modificar estos archivos: `scripts/deploy-week1.sh`, `scripts/destroy-week1.sh`, `scripts/validate-week1.sh`, `scripts/lib/common.sh`, `scripts/lib/parameters.sh`, `.env.example`, `scripts/tests/test-deploy-parameters.sh`, `scripts/tests/test-destroy-safety.sh`, `README.md` (modificar), `.gitignore` (necesario en esta rama).
- Prohibidos: `.env` con valores reales, `scripts/github/**`, `.github/workflows/**`.
- Ningún script contiene región, suscripción o SKU rígidos: todo viene de `.env`/env vars.
- Los logs nunca imprimen valores sensibles crudos: usar `mask()`.
- Parámetros obligatorios: `SUBSCRIPTION_ID`, `LOCATION`, `RESOURCE_GROUP`, `NAME_PREFIX`, `APP_SERVICE_SKU`.
- `NAME_PREFIX`: 3–11 minúsculas/números. `SUBSCRIPTION_ID`: UUID. `RESOURCE_GROUP`: `[A-Za-z0-9._-]{1,90}`.
- Tags del Resource Group: `project=centinela week=1 team=celula-centinela`.
- shellcheck se invoca por ruta: `SC="/c/Users/carlo/AppData/Local/Microsoft/WinGet/Packages/koalaman.shellcheck_Microsoft.Winget.Source_8wekyb3d8bbwe/shellcheck.exe"`.

---

### Task 1: Scaffolding de configuración (`.gitignore` + `.env.example`)

**Files:**
- Create/commit: `.gitignore` (ya en disco protegiendo `.env`)
- Create: `.env.example`

**Interfaces:**
- Produces: `.env.example` (plantilla pública con placeholders), `.gitignore` (ignora `.env`, `*.env`, permite `.env.example`).

- [ ] **Step 1: Verificar que `.gitignore` protege `.env`**

Run: `git check-ignore -v .env && git check-ignore .env.example || echo "example NO ignorado (ok)"`
Expected: `.env` ignorado; `.env.example` NO ignorado.

- [ ] **Step 2: Crear `.env.example`**

```bash
# Copia este archivo a .env y rellena tus valores reales. NO commitees .env.
# El .env real esta protegido por .gitignore.
SUBSCRIPTION_ID="<tu-subscription-id-uuid>"
LOCATION="<region-ej-eastus2>"
RESOURCE_GROUP="<rg-nombre-ej-rg-centinela-week1>"
NAME_PREFIX="<prefijo-3-11-minusculas-ej-cent>"
APP_SERVICE_SKU="<sku-con-slots-ej-S1>"
```

- [ ] **Step 3: Verificar que `.env.example` no tiene valores reales**

Run: `grep -E "00000000|eastus2" .env.example && echo "FUGA" || echo "OK sin valores reales"`
Expected: `OK sin valores reales`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore .env.example
git commit -m "feat(ISS-S1-002): gitignore y plantilla .env.example"
```

---

### Task 2: Validación de parámetros y orquestador (TEST-S1-003)

**Files:**
- Create: `scripts/tests/test-deploy-parameters.sh` (test primero)
- Create: `scripts/lib/common.sh`, `scripts/lib/parameters.sh`, `scripts/deploy-week1.sh`

**Interfaces:**
- `common.sh` produce: `log_info/log_warn/log_error`, `die <msg>`, `mask <valor>`, `require_cmd <bin>`, `with_retry <n> <cmd...>`.
- `parameters.sh` produce: `load_parameters` (carga `.env` o `$ENV_FILE`), `validate_parameters` (fail-fast). Consume `common.sh`.
- `deploy-week1.sh` consume ambos; expone modo `--validate-only`.

- [ ] **Step 1: Escribir el test que falla — `scripts/tests/test-deploy-parameters.sh`**

```bash
#!/usr/bin/env bash
# test-deploy-parameters.sh — TEST-S1-003
# deploy-week1.sh --validate-only debe fallar ANTES de tocar Azure si falta un
# parametro; y validar los parametros offline antes de exigir 'az'.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy-week1.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Caso 1: falta RESOURCE_GROUP -> sale !=0, menciona el faltante, sin usar Azure.
out="$(env -i PATH="/usr/bin:/bin" ENV_FILE=/dev/null \
    SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" LOCATION="eastus2" \
    NAME_PREFIX="cent" APP_SERVICE_SKU="S1" \
    bash "$DEPLOY" --validate-only 2>&1)" && fail "no fallo con RESOURCE_GROUP faltante"
echo "$out" | grep -qi "RESOURCE_GROUP" || fail "el error no menciona el parametro faltante"
echo "PASS caso 1: falla antes de Azure con parametro faltante"

# Caso 2: todos presentes pero sin 'az' -> valida offline y LUEGO exige az.
out2="$(env -i PATH="/usr/bin:/bin" ENV_FILE=/dev/null \
    SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" LOCATION="eastus2" \
    RESOURCE_GROUP="rg-centinela-week1" NAME_PREFIX="cent" APP_SERVICE_SKU="S1" \
    bash "$DEPLOY" --validate-only 2>&1)" && fail "esperabamos fallo por falta de az"
echo "$out2" | grep -qi "validados" || fail "no valido parametros antes de az"
echo "$out2" | grep -qi "az" || fail "no fallo por ausencia de az"
echo "PASS caso 2: valida offline y luego exige az"

echo "TEST-S1-003 OK"
```

- [ ] **Step 2: Ejecutar el test para verlo fallar**

Run: `bash scripts/tests/test-deploy-parameters.sh`
Expected: FAIL (el archivo `deploy-week1.sh` no existe todavía).

- [ ] **Step 3: Implementar `scripts/lib/common.sh`**

```bash
#!/usr/bin/env bash
# common.sh — utilidades compartidas: logging, errores, reintentos, mask de secretos.
# Se hace "source" desde los demas scripts. No conoce Azure ni parametros de negocio.

if [ -t 2 ]; then
  _C_RED=$'\033[31m'; _C_YELLOW=$'\033[33m'; _C_GREEN=$'\033[32m'; _C_RESET=$'\033[0m'
else
  _C_RED=''; _C_YELLOW=''; _C_GREEN=''; _C_RESET=''
fi

log_info()  { printf '%s[INFO]%s  %s\n'  "$_C_GREEN"  "$_C_RESET" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s  %s\n'  "$_C_YELLOW" "$_C_RESET" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$_C_RED"    "$_C_RESET" "$*" >&2; }

die() { log_error "$*"; exit 1; }

# mask <valor> -> primeros/ultimos 4 chars; oculta el resto. Evita filtrar secretos.
mask() {
  local v="${1:-}"; local n=${#v}
  if [ "$n" -le 8 ]; then printf '****'; else printf '%s…%s' "${v:0:4}" "${v: -4}"; fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Falta la dependencia requerida: '$1'. Instalala y reintenta."
}

# with_retry <n> <cmd...> -> reintenta hasta n veces con backoff lineal.
with_retry() {
  local max="$1"; shift; local attempt=1
  until "$@"; do
    if [ "$attempt" -ge "$max" ]; then return 1; fi
    log_warn "Intento $attempt/$max fallo; reintentando en ${attempt}s..."
    sleep "$attempt"; attempt=$((attempt + 1))
  done
  return 0
}
```

- [ ] **Step 4: Implementar `scripts/lib/parameters.sh`**

```bash
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
```

- [ ] **Step 5: Implementar `scripts/deploy-week1.sh`**

```bash
#!/usr/bin/env bash
# deploy-week1.sh — orquestador de despliegue de Semana 1.
# Modos: --validate-only (no crea nada) | normal (ejecuta el registro de pasos).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: $0 [--validate-only]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

# Registro de pasos (Opcion A). Las issues 003-006 agregan sus scripts aqui.
PROVISION_STEPS=(
  "provision-storage.sh"            # ISS-S1-003
  "provision-app-service.sh"        # ISS-S1-004
  "provision-network.sh"            # ISS-S1-005
  "configure-private-endpoints.sh"  # ISS-S1-005
)

main() {
  load_parameters
  validate_parameters               # fail-fast offline: falla ANTES de tocar Azure

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  az account list-locations --query "[?name=='$LOCATION'] | [0].name" -o tsv | grep -q . \
    || die "Region '$LOCATION' no valida/disponible."
  az appservice list-locations --sku "$APP_SERVICE_SKU" --query "[?name=='$LOCATION'] | [0].name" -o tsv | grep -q . \
    || die "SKU '$APP_SERVICE_SKU' no disponible en '$LOCATION' o sin soporte de slots/escala."

  log_info "Plan de despliegue:"
  log_info "  Suscripcion   : $(mask "$SUBSCRIPTION_ID")"
  log_info "  Region        : $LOCATION"
  log_info "  Resource Group: $RESOURCE_GROUP"
  log_info "  Name prefix   : $NAME_PREFIX"
  log_info "  App SKU       : $APP_SERVICE_SKU"
  log_warn "AVISO DE COSTOS: consume el credito compartido de USD 200. Ejecuta destroy-week1.sh al terminar."

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "--validate-only: entorno valido. No se crea ningun recurso."
    return 0
  fi

  log_info "Creando/asegurando Resource Group '$RESOURCE_GROUP'..."
  with_retry 3 az group create --name "$RESOURCE_GROUP" --location "$LOCATION" \
    --tags project=centinela week=1 team=celula-centinela --output none

  for step in "${PROVISION_STEPS[@]}"; do
    if [ -f "$SCRIPT_DIR/$step" ]; then
      log_info "Ejecutando paso: $step"; bash "$SCRIPT_DIR/$step"
    else
      log_warn "Paso pendiente (issue futura): $step"
    fi
  done
  log_info "Despliegue base completado."
}

main
```

- [ ] **Step 6: Ejecutar el test para verlo pasar**

Run: `bash scripts/tests/test-deploy-parameters.sh`
Expected: `PASS caso 1` + `PASS caso 2` + `TEST-S1-003 OK`.

- [ ] **Step 7: Lint y sintaxis**

Run: `bash -n scripts/deploy-week1.sh scripts/lib/*.sh && "$SC" scripts/deploy-week1.sh scripts/lib/common.sh scripts/lib/parameters.sh`
Expected: sin salida de shellcheck (limpio), exit 0.

- [ ] **Step 8: Commit**

```bash
git add scripts/lib/common.sh scripts/lib/parameters.sh scripts/deploy-week1.sh scripts/tests/test-deploy-parameters.sh
git commit -m "feat(ISS-S1-002): orquestador, librería y validación de parámetros (TEST-S1-003)"
```

---

### Task 3: Destrucción protegida (TEST-S1-004)

**Files:**
- Create: `scripts/tests/test-destroy-safety.sh` (test primero)
- Create: `scripts/destroy-week1.sh`

**Interfaces:**
- `destroy-week1.sh` consume `common.sh` + `parameters.sh`; flag `--yes` para no interactivo.

- [ ] **Step 1: Escribir el test que falla — `scripts/tests/test-destroy-safety.sh`**

```bash
#!/usr/bin/env bash
# test-destroy-safety.sh — TEST-S1-004
# destroy-week1.sh debe RECHAZAR el borrado si la confirmacion tecleada no coincide
# con el nombre del RG, sin llamar a Azure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTROY="$SCRIPT_DIR/../destroy-week1.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(printf 'nombre-equivocado\n' | env -i PATH="/usr/bin:/bin" ENV_FILE=/dev/null \
    SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" LOCATION="eastus2" \
    RESOURCE_GROUP="rg-centinela-week1" NAME_PREFIX="cent" APP_SERVICE_SKU="S1" \
    bash "$DESTROY" 2>&1)" && fail "no aborto con confirmacion equivocada"
echo "$out" | grep -qi "no coincide" || fail "no explico la falta de coincidencia"
echo "PASS caso 1: rechaza confirmacion equivocada sin borrar"

echo "TEST-S1-004 OK"
```

- [ ] **Step 2: Ejecutar el test para verlo fallar**

Run: `bash scripts/tests/test-destroy-safety.sh`
Expected: FAIL (`destroy-week1.sh` no existe).

- [ ] **Step 3: Implementar `scripts/destroy-week1.sh`**

```bash
#!/usr/bin/env bash
# destroy-week1.sh — elimina el Resource Group de Semana 1 con confirmacion segura.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|--force) ASSUME_YES=1 ;;
    -h|--help) echo "Uso: $0 [--yes]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

main() {
  load_parameters
  validate_parameters

  log_warn "Vas a ELIMINAR el Resource Group '$RESOURCE_GROUP' y TODOS sus recursos."
  if [ "$ASSUME_YES" -eq 1 ]; then
    log_warn "--yes activo: confirmacion automatica (modo automatizacion)."
  else
    printf 'Para confirmar, teclea EXACTAMENTE el nombre del Resource Group: ' >&2
    read -r typed
    [ "$typed" = "$RESOURCE_GROUP" ] \
      || die "El nombre '$typed' no coincide con '$RESOURCE_GROUP'. Abortado sin borrar."
  fi

  require_cmd az
  if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "El Resource Group '$RESOURCE_GROUP' no existe. Nada que eliminar."; return 0
  fi
  log_info "Eliminando Resource Group '$RESOURCE_GROUP'..."
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  log_info "Eliminacion iniciada (--no-wait)."
}

main
```

- [ ] **Step 4: Ejecutar el test para verlo pasar**

Run: `bash scripts/tests/test-destroy-safety.sh`
Expected: `PASS caso 1` + `TEST-S1-004 OK`.

- [ ] **Step 5: Lint y sintaxis**

Run: `bash -n scripts/destroy-week1.sh && "$SC" scripts/destroy-week1.sh`
Expected: exit 0, sin hallazgos.

- [ ] **Step 6: Commit**

```bash
git add scripts/destroy-week1.sh scripts/tests/test-destroy-safety.sh
git commit -m "feat(ISS-S1-002): destrucción protegida del Resource Group (TEST-S1-004)"
```

---

### Task 4: Validación de entorno (`validate-week1.sh`)

**Files:**
- Create: `scripts/validate-week1.sh`

**Interfaces:**
- Consume `common.sh` + `parameters.sh`. Sin test dedicado (no autorizado); se verifica con `bash -n`, shellcheck y ejecución en vivo con `az`.

- [ ] **Step 1: Implementar `scripts/validate-week1.sh`**

```bash
#!/usr/bin/env bash
# validate-week1.sh — valida el entorno de despliegue sin crear recursos.
# Semana 1 (sin recursos aun): parametros + sesion az + region + SKU.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  log_info "Sesion de Azure activa."

  az account list-locations --query "[?name=='$LOCATION'] | [0].name" -o tsv | grep -q . \
    || die "Region '$LOCATION' no disponible."
  log_info "Region '$LOCATION' valida."

  az appservice list-locations --sku "$APP_SERVICE_SKU" --query "[?name=='$LOCATION'] | [0].name" -o tsv | grep -q . \
    || die "SKU '$APP_SERVICE_SKU' no disponible en '$LOCATION'."
  log_info "SKU '$APP_SERVICE_SKU' compatible con '$LOCATION'."

  log_info "Entorno validado. Listo para desplegar."
}

main
```

- [ ] **Step 2: Sintaxis y lint**

Run: `bash -n scripts/validate-week1.sh && "$SC" scripts/validate-week1.sh`
Expected: exit 0, sin hallazgos.

- [ ] **Step 3: Ejecución en vivo (usa el `.env` real y `az`)**

Run (con `az` en PATH): `bash scripts/validate-week1.sh`
Expected: `Sesion de Azure activa`, `Region 'eastus2' valida`, `SKU 'S1' compatible`, `Entorno validado`.

- [ ] **Step 4: Commit**

```bash
git add scripts/validate-week1.sh
git commit -m "feat(ISS-S1-002): validación de entorno con Azure CLI en vivo"
```

---

### Task 5: README, evidencia y barrido final

**Files:**
- Modify: `README.md`
- Create: `docs/evidence/iss-s1-002/` (salidas sanitizadas)

- [ ] **Step 1: Documentar parámetros y comandos en `README.md`**

Agregar sección con: los 5 parámetros, cómo copiar `.env.example` → `.env`, y los comandos `deploy-week1.sh --validate-only`, `validate-week1.sh`, `destroy-week1.sh`, y cómo correr los tests.

- [ ] **Step 2: Barrido completo de sintaxis y lint**

Run: `bash -n scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh && "$SC" scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh`
Expected: exit 0, sin hallazgos.

- [ ] **Step 3: Correr ambos tests obligatorios**

Run: `bash scripts/tests/test-deploy-parameters.sh && bash scripts/tests/test-destroy-safety.sh`
Expected: `TEST-S1-003 OK` y `TEST-S1-004 OK`.

- [ ] **Step 4: Generar evidencia sanitizada**

Capturar en `docs/evidence/iss-s1-002/`:
- `01-tests.txt` — salida de ambos test scripts.
- `02-shellcheck.txt` — salida de shellcheck (limpia).
- `03-validate-only.txt` — salida de `deploy-week1.sh --validate-only` con `.env` real (SUBSCRIPTION_ID enmascarado por `mask`).
- `README.md` — índice + tabla de criterios de aceptación.

- [ ] **Step 5: Verificar que no hay secretos en la evidencia**

Run: `grep -RIn "00000000-0000-0000-0000-000000000000" docs/evidence/iss-s1-002/ && echo "FUGA" || echo "OK sanitizado"`
Expected: `OK sanitizado`.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/evidence/iss-s1-002/
git commit -m "docs(ISS-S1-002): README de scripts y evidencia de cierre"
```

---

## Self-Review

**Spec coverage:**
- Orquestador no monolítico + registro de pasos → Task 2 (deploy-week1.sh). ✓
- 5 parámetros obligatorios por env/param → Task 2 (parameters.sh). ✓
- Validar sesión az, suscripción, región, SKU → Task 2 (deploy) + Task 4 (validate). ✓
- common.sh (logging/errores/reintentos/mask) → Task 2. ✓
- destroy con confirmación de RG + `--yes` → Task 3. ✓
- Tags + aviso de costos → Task 2 (deploy). ✓
- Sin hardcode región/sub/SKU → Global Constraints + `.env.example` Task 1. ✓
- Logs sin secretos (`mask`) → Task 2. ✓
- Soporta 003–006 sin duplicar → registro de pasos Task 2. ✓
- TEST-S1-003 → Task 2; TEST-S1-004 → Task 3. ✓
- Evidencia reproducible sanitizada → Task 5. ✓

**Placeholder scan:** `.env.example` usa placeholders intencionales (parte del entregable). Sin TODO/TBD en código. ✓

**Type consistency:** `load_parameters`/`validate_parameters`/`mask`/`die`/`require_cmd`/`with_retry` usados con los mismos nombres en todas las tareas. ✓
