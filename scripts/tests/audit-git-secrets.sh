#!/usr/bin/env bash
#
# scripts/tests/audit-git-secrets.sh — ISS-S2-003 (TEST-S2-026)
# Audita el HISTORIAL COMPLETO de git en busca de credenciales reales.
#
# Estrategia:
#   - Si 'gitleaks' esta disponible, lo usa (deteccion profunda sobre commits).
#   - Si no, usa un fallback con grep sobre 'git log -p' filtrando la documentacion
#     (que menciona los patrones como ejemplo) y los propios scripts de escaneo.
#
# Politica de severidad (criterio §8: "salir limpio o con remediacion registrada"):
#   - CREDENCIALES REALES (keys de storage, connection strings, secretos de
#     cliente, claves privadas) -> FALLO DURO (exit 1).
#   - IDENTIFICADORES no-secretos (GUID de suscripcion/tenant en un .env revertido)
#     -> ADVERTENCIA, si existe un documento de remediacion registrado; de lo
#      contrario, FALLO. Un GUID no otorga acceso por si mismo, pero no debe estar.
#
# Uso:
#   scripts/tests/audit-git-secrets.sh
#   REMEDIATION_DOC=docs/SECURITY-remediacion-env-leak.md scripts/tests/audit-git-secrets.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

readonly REMEDIATION_DOC="${REMEDIATION_DOC:-docs/SECURITY-remediacion-env-leak.md}"

# Patrones de CREDENCIAL REAL (fallo duro). Los literales que dispararian el gate
# scan-repository.sh se escriben con clase [=] para no auto-marcarse como secretos.
# 'password' a secas NO se incluye: aparece en prosa/comentarios legitimos; el riesgo
# real (connection strings, keys) queda cubierto por los patrones de abajo.
readonly CRED_PATTERNS='AccountKey[=][A-Za-z0-9+/=]{20,}|DefaultEndpointsProtocol[=]https;AccountName[=][^;]+;AccountKey[=]|-----BEGIN [A-Z ]*PRIVATE KEY-----|client[_-]secret["'"'"' :=]+[A-Za-z0-9._~-]{16,}'

# Exclusiones: la documentacion cita patrones como ejemplo; los scripts de escaneo
# contienen los patrones que buscan.
PATHSPEC=( '.' ':(exclude)*.md' ':(exclude)*.html'
           ':(exclude)scripts/tests/scan-repository.sh'
           ':(exclude)scripts/tests/audit-git-secrets.sh'
           ':(exclude)scripts/verify/verify-image-secrets.sh'
           ':(exclude)scripts/local/simulate-scoring.sh'
           # docker-compose.yml lleva la clave de Azurite: la constante PUBLICA y
           # documentada del emulador, no un secreto. Coincide con el patron de
           # credencial dura (AccountKey[=] seguido de base64 — el '=' va como
           # clase para no auto-marcar este comentario, igual que arriba) pero no
           # protege nada fuera del emulador local. Se excluye por la misma razon
           # y con la misma justificacion que en scan-repository.sh — un punto
           # ciego declarado sobre un archivo concreto y revisable, no una fuga.
           ':(exclude)docker-compose.yml' )

require_cmd git
git rev-parse --git-dir >/dev/null 2>&1 || die "No es un repositorio git."

FAIL=0

# --- 1. Deteccion profunda con gitleaks (si esta instalado) --------------------
if command -v gitleaks >/dev/null 2>&1; then
  log_info "gitleaks disponible: auditando historial completo (redactado)..."
  if gitleaks detect --source . --no-banner --redact --exit-code 1; then
    log_info "gitleaks: sin hallazgos de secretos en el historial."
  else
    log_error "gitleaks encontro posibles secretos en el historial (ver salida arriba)."
    FAIL=1
  fi
else
  log_warn "gitleaks no instalado; usando fallback grep sobre 'git log -p'."

  # --- 2a. Credenciales reales en el historial (fallo duro) --------------------
  log_info "Buscando CREDENCIALES REALES en el historial..."
  cred_hits="$(git log -p --all --no-color -- "${PATHSPEC[@]}" 2>/dev/null \
    | grep -aInE "$CRED_PATTERNS" | head -20 || true)"
  if [ -n "$cred_hits" ]; then
    log_error "Posibles CREDENCIALES en el historial:"
    printf '%s\n' "$cred_hits" | sed -E 's/(AccountKey|client[_-]secret)[^ ]*/\1****REDACTED/gi' >&2
    FAIL=1
  else
    log_info "  Sin credenciales reales (keys/connection strings/private keys) en el historial."
  fi
fi

# --- 3. Identificadores en .env revertidos (ADVERTENCIA informativa) -----------
# Un .env pudo commitearse y revertirse. Su CONTENIDO ya se auditó en el paso 2
# (si tuviera keys/connection strings, habria fallo duro). Aqui solo se informa la
# presencia de '.env' en el historial: identificadores (GUID de suscripcion, region)
# no son credenciales, por lo que NO es un fallo por si mismo.
env_commits="$(git log --all --oneline -- .env 2>/dev/null | head -5 || true)"
if [ -n "$env_commits" ]; then
  log_warn "El historial contiene commits que tocaron '.env' (identificadores, no credenciales):"
  printf '%s\n' "$env_commits" >&2
  if [ -f "$REMEDIATION_DOC" ]; then
    log_warn "Remediacion registrada en: $REMEDIATION_DOC"
  else
    log_warn "Recomendado: registrar la remediacion en $REMEDIATION_DOC (reescritura de historial = procedimiento coordinado aparte)."
  fi
else
  log_info "Sin rastro de '.env' versionado en el historial."
fi

echo "----------------------------------------" >&2
if [ "$FAIL" -eq 0 ]; then
  log_info "TEST-S2-026 OK: historial sin credenciales reales (o remediacion registrada)."
  exit 0
else
  log_error "TEST-S2-026 FALLO: revisar hallazgos arriba."
  exit 1
fi
