# Evidencia — ISS-S1-002 · Scripts base de infraestructura y control de costos

- **Fecha de ejecución:** 2026-07-16
- **Rama:** `iss-s1-002-scripts-base-infraestructura`
- **Entorno:** Bash 5.2 · Azure CLI 2.88 · ShellCheck 0.11 · Windows 11
- **Estado:** Pruebas obligatorias en verde. Evidencia sanitizada (SUBSCRIPTION_ID enmascarado).

## Archivos

| Archivo | Contenido |
|---|---|
| `01-tests.txt` | Salida de los dos test scripts obligatorios (TEST-S1-003, TEST-S1-004). |
| `02-shellcheck.txt` | ShellCheck sobre los 7 scripts (sin hallazgos). |
| `03-validate-only.txt` | `deploy-week1.sh --validate-only` en vivo; SUBSCRIPTION_ID enmascarado por `mask()`. |

## Criterios de aceptación (verificados)

| Criterio | Resultado | Evidencia |
|---|---|---|
| Falla antes de crear si falta un parámetro | ✅ | `01-tests.txt` (TEST-S1-003, caso 1) |
| Ningún script con región/suscripción/SKU rígidos | ✅ | Todo viene de `.env`; `.env.example` solo placeholders |
| `destroy` muestra el RG exacto antes de borrar | ✅ | `01-tests.txt` (TEST-S1-004) + confirmación por tecleo |
| Los logs no imprimen secretos | ✅ | `03-validate-only.txt` → `Suscripcion: 44dc…3999` (enmascarado) |
| Soporta incorporar 003–006 sin duplicar lógica | ✅ | Registro de pasos (`PROVISION_STEPS`) en `deploy-week1.sh` |

## Pruebas catalogadas

- **TEST-S1-003** (Estático · Scripts) — parámetros obligatorios → `test-deploy-parameters.sh`.
- **TEST-S1-004** (Integración · Control de costos) — protección de destrucción → `test-destroy-safety.sh`.
- **TEST-S1-026 / 027** (E2E, posteriores) — desplegar/destruir real. Trazadas; se ejecutan al cerrar la Semana 1 (requieren `az login` + recursos de issues 003–006).

## Validación en vivo (bonus, con Azure CLI disponible)

`validate-week1.sh` y `deploy-week1.sh --validate-only` se ejecutaron contra la suscripción
real: sesión activa, región `eastus2` válida y SKU `S1` compatible. Ningún recurso creado.

## Cómo reproducir

```bash
cp .env.example .env    # rellenar valores reales
az login
bash scripts/validate-week1.sh
bash scripts/deploy-week1.sh --validate-only
bash scripts/tests/test-deploy-parameters.sh
bash scripts/tests/test-destroy-safety.sh
SC=shellcheck; "$SC" -x --source-path=SCRIPTDIR scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh
```

## Desviaciones

- Se añadió `.gitattributes` (`*.sh text eol=lf`) — no listado en la issue, pero **necesario**:
  Git en Windows (`autocrlf=true`) convertiría los `.sh` a CRLF y rompería el shebang de bash.
  Es higiene de terminaciones de línea, no alcance funcional nuevo.
- Se corrigió en vivo un bug: `az appservice list-locations` usa el nombre display de la
  región ("East US 2"), no el corto ("eastus2"); los scripts ahora derivan el display.

## Pendiente para cerrar formalmente

- Revisión cruzada de Persona 5.
- ShellCheck en CI (capa 3) — ya diseñada; se activa en Semana 2.
