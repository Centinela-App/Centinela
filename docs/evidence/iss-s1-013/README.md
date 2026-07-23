# Evidencia ISS-S1-013 — README, matriz, diagrama, ADR y evidencias

**Pruebas obligatorias:** TEST-S1-002 (secretos), TEST-S1-025 (documentación), TEST-S1-028 (alcance).

## Entregables verificados

| Entregable | Ruta | Estado |
|---|---|---|
| Arquitectura | `docs/architecture/centinela-week1.md` | ✅ |
| ADR-001 Hexagonal | `docs/adr/ADR-001-hexagonal.md` | ✅ |
| ADR-002 Managed Identity | `docs/adr/ADR-002-managed-identity.md` | ✅ |
| ADR-003 Storage privado | `docs/adr/ADR-003-private-storage.md` | ✅ |
| ADR-004 Separación de ambientes | `docs/adr/ADR-004-environment-separation.md` | ✅ |
| Índice de evidencias | `docs/evidence/INDEX.md` | ✅ (corregido) |
| Decisiones abiertas Semana 2 | `docs/week2/OPEN_DECISIONS.md` | ✅ |
| Matriz de trazabilidad | `docs/5_Issues_y_Trazabilidad/2_Matriz_Trazabilidad.md` | ✅ |
| README principal | `Readme.md` | ✅ |

## Correcciones aplicadas en esta issue

Los scripts de validación fallaban por defectos propios (no por documentación faltante):

- `validate-documentation.sh`: `DOCS_DIR` apuntaba a `scripts/docs` (faltaba un nivel `..`)
  y buscaba la arquitectura en `2_Arquitectura/` en vez de `architecture/`. Corregido.
- `validate-week1-scope.sh`: el check de *Account Key* se auto-detectaba su propio patrón
  `grep`; el check de *deployment slots* marcaba como violación el slot `staging` que la
  ISS-S1-004 sí exige en Semana 1. Corregidos (auto-exclusión + solo blue-green avanzado).
- `scan-repository.sh`: no excluía a `validate-week1-scope.sh`, que contiene el patrón como
  cadena de búsqueda. Corregido.

## Resultados

- `01-validate-documentation.txt` — TEST-S1-025 PASADA (todos los entregables presentes).
- `02-validate-week1-scope.txt` — TEST-S1-028 PASADA (sin alcance de Semana 2).
- `03-scan-repository.txt` — TEST-S1-002 OK (sin secretos ni cadenas de conexión).
- `04-full-verify-suite.txt` — `mvn verify` completo (62 pruebas).

## Comandos reproducibles

```bash
bash scripts/tests/validate-documentation.sh
bash scripts/tests/validate-week1-scope.sh
bash scripts/tests/scan-repository.sh
mvn clean verify
```
