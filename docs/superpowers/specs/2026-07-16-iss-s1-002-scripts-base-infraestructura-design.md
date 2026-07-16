# Diseño — ISS-S1-002 · Scripts base de infraestructura y control de costos

- **Fecha:** 2026-07-16
- **Autor:** Célula Centinela (con asistencia de IA)
- **Estado:** Aprobado para implementación
- **Rama:** `iss-s1-002-scripts-base-infraestructura` (desde `develop`)
- **Responsable:** Persona 1 · **Revisor:** Persona 5
- **Alcance:** Semana 1 — `ISS-S1-002`. Solo el armazón; los recursos concretos entran en 003–006.

---

## 1. Objetivo

Crear el **armazón seguro y parametrizado** para desplegar, validar y destruir una única
infraestructura compartida por el equipo. Impide despliegues accidentales, valores rígidos
y recursos olvidados que gasten el crédito de USD 200 común a cinco personas.

**No** se crea Storage ni App Service aquí: eso lo agregan las issues 003–006 enchufándose
al orquestador que construimos ahora.

## 2. Decisiones de diseño

| Decisión | Valor | Razón |
|---|---|---|
| Extensión del orquestador | **Registro de pasos (Opción A)** | 003–006 solo registran su script; cero edición de lógica compartida. Cumple criterio 5. |
| Confirmación de destrucción | Tecleo del **nombre exacto del RG** + flag `--yes` para automatización | Directo de la spec; evita borrados accidentales. |
| Fuente de parámetros | `.env` local → override por variable de entorno; nunca hardcode | Cumple "sin región/suscripción/SKU rígidos". |
| Framework de pruebas | **Bash puro** (sin bats) | YAGNI; bats no está instalado. |
| Linter | **shellcheck** local + CI capa 3 | Instalado en esta sesión. |
| Validación en vivo | `az account show`, región y SKU vía Azure CLI | `az` 2.88 disponible; refuerza `--validate-only`. |

## 3. Arquitectura de archivos

```text
scripts/
├── lib/
│   ├── common.sh        # logging, errores, reintentos, mask() de secretos
│   └── parameters.sh    # carga .env, valida los 5 parametros (fail-fast)
├── deploy-week1.sh      # orquestador: --validate-only | normal; registro de pasos
├── validate-week1.sh    # valida entorno: params + sesion az + region + SKU
├── destroy-week1.sh     # confirmacion por tecleo del RG; --yes no interactivo
└── tests/
    ├── test-deploy-parameters.sh   # TEST-S1-003
    └── test-destroy-safety.sh      # TEST-S1-004
.env.example             # plantilla publica (solo placeholders)
```

### 3.1 `lib/common.sh`

Librería sourced por todos los scripts. Responsabilidades:

- `set -euo pipefail` como contrato de robustez.
- `log_info` / `log_warn` / `log_error` con prefijo y color (degrada a texto plano si no hay TTY).
- `die <msg>` → imprime error y sale con código ≠ 0.
- `mask <valor>` → devuelve el valor ofuscado (ej. `44dc…3999`) para no imprimir secretos.
- `with_retry <n> <cmd...>` → reintenta un comando hasta `n` veces con backoff limitado.
- `require_cmd <bin>` → verifica que una dependencia (ej. `az`) exista.

No conoce Azure ni parámetros de negocio: es utilitario puro.

### 3.2 `lib/parameters.sh`

- Carga `.env` **si existe** (sin fallar si no está: las env vars pueden venir del entorno/CI).
- Lista de parámetros requeridos: `SUBSCRIPTION_ID`, `LOCATION`, `RESOURCE_GROUP`,
  `NAME_PREFIX`, `APP_SERVICE_SKU`.
- `validate_parameters()` → falla (fail-fast) si **falta** alguno o si el **formato** es inválido:
  - `SUBSCRIPTION_ID`: patrón UUID.
  - `NAME_PREFIX`: 3–11 minúsculas/números (deja margen para el límite de 24 de Storage Account).
  - `RESOURCE_GROUP`: 1–90, `[A-Za-z0-9._-]`.
  - `LOCATION` y `APP_SERVICE_SKU`: no vacíos (validación viva opcional contra Azure).
- Nunca imprime los valores crudos sensibles; usa `mask()`.

### 3.3 `deploy-week1.sh` (orquestador)

Modos:

- `--validate-only`: carga y valida parámetros, valida sesión `az` + suscripción activa +
  región válida + SKU compatible, **imprime el plan de despliegue** y termina **sin crear nada**.
- Normal: lo anterior + itera el **registro de pasos**.

**Registro de pasos (Opción A):**

```bash
PROVISION_STEPS=(
  "provision-storage.sh"        # ISS-S1-003
  "provision-app-service.sh"    # ISS-S1-004
  "provision-network.sh"        # ISS-S1-005
  "configure-private-endpoints.sh"  # ISS-S1-005
  # ISS-S1-006 registrara los suyos aqui
)
```

El orquestador recorre el arreglo; para cada script: si **existe** en `scripts/`, lo ejecuta;
si **no existe todavía**, registra `log_warn "paso pendiente (issue futura): <script>"` y continúa.
Así las issues 003–006 solo crean su script y (si hace falta) agregan una línea al arreglo.

Aplica **tags** a nivel de creación del Resource Group: `project=centinela`, `week=1`,
`team=celula-centinela`, más una **advertencia de costos** en el log.

### 3.4 `validate-week1.sh`

Valida el estado sin desplegar. Hoy (sin recursos aún): parámetros + sesión `az` +
región + SKU. En 003–006 se ampliará para verificar los recursos creados.

### 3.5 `destroy-week1.sh`

- Muestra el **nombre exacto del Resource Group** y pide teclearlo para confirmar.
- Si lo tecleado **no coincide**, aborta sin borrar.
- Flag `--yes` (o `--force`) para automatización controlada (CI), documentado como riesgoso.
- Verifica que el RG exista antes de intentar borrarlo (idempotente: si no existe, informa y sale 0).

### 3.6 `.env.example`

Plantilla pública, **solo placeholders**, commiteable:

```bash
SUBSCRIPTION_ID="<tu-subscription-id>"
LOCATION="<region-ej-eastus2>"
RESOURCE_GROUP="<rg-nombre>"
NAME_PREFIX="<prefijo-minusculas>"
APP_SERVICE_SKU="<sku-ej-S1>"
```

## 4. Pruebas

| ID | Nivel | Archivo | Qué verifica |
|---|---|---|---|
| TEST-S1-003 | Estático | `tests/test-deploy-parameters.sh` | Con un param faltante, `deploy-week1.sh --validate-only` sale ≠0 **antes** de tocar Azure. |
| TEST-S1-004 | Integración | `tests/test-destroy-safety.sh` | Con un RG que no coincide, `destroy-week1.sh` rechaza el borrado. |
| TEST-S1-026/027 | E2E (posterior) | — | Deploy/destroy real. Trazadas; se ejecutan al cerrar Semana 1. |

Los test scripts **no llaman a Azure**: exportan parámetros de mentira y verifican la lógica de
guarda, de modo que corren en cualquier máquina/CI sin credenciales.

## 5. Comandos de validación (de la issue)

```bash
bash -n scripts/*.sh scripts/lib/*.sh
shellcheck scripts/*.sh scripts/lib/*.sh
./scripts/deploy-week1.sh --validate-only   # con .env presente
bash scripts/tests/test-deploy-parameters.sh
bash scripts/tests/test-destroy-safety.sh
```

## 6. Evidencia esperada

- Salida de validación de parámetros (caso OK y caso faltante).
- Resultado de ShellCheck.
- Captura sanitizada de la protección de destrucción (RG equivocado rechazado).
- (Bonus, gracias a `az`) salida de `--validate-only` con plan de despliegue sanitizado.

## 7. Fuera de alcance

Creación completa de recursos, CI/CD o GitHub Actions, cinco entornos independientes,
presupuesto automático. Prohibidos: `.env` con valores reales, `scripts/github/**`,
`.github/workflows/**`.

## 8. Riesgos

- **Sesión `az` expira** → `--validate-only` lo detecta y falla con mensaje claro.
- **Región/SKU no disponible en la suscripción** → validación viva lo reporta antes de desplegar.
- **Colarse hacia creación de recursos** (alcance 003+) → mitigado: el orquestador solo
  registra pasos; no implementa provisión aquí.
