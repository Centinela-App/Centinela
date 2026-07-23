# Índice de Evidencias — Semana 1

Este índice mapea cada issue con su evidencia real versionada en el repositorio. Los
títulos coinciden con `docs/5_Issues_y_Trazabilidad/1_Historias_Issues.md`.

## Notas importantes

⚠️ **SANITIZACIÓN**: Los IDs sensibles se reemplazan con marcadores (`<subscription-id>`,
`<resource-id>`, `<tenant-id>`). No se versionan credenciales reales.

⚠️ **ALCANCE DE EVIDENCIA**: Las pruebas obligatorias locales (unitarias, contrato,
arquitectura, integración MockMvc, sintaxis de scripts y validaciones de documentación)
están ejecutadas y versionadas. Las pruebas E2E contra Azure real (colas, HA, despliegue
y destrucción) requieren una suscripción activa; su código está completo y su ejecución
queda documentada como pendiente. No se fabrica evidencia de Azure (regla del DoD).

---

## Evidencia por issue

| Issue | Título | Estado | Evidencia |
|---|---|---|---|
| ISS-S1-001 | Preparar repositorio Java y estructura hexagonal | ✅ local | `iss-s1-001/` |
| ISS-S1-002 | Scripts base de infraestructura y control de costos | ✅ local + Azure | `iss-s1-002/` |
| ISS-S1-003 | Storage, contenedores y colas por ambiente | ✅ local + Azure | `iss-s1-003/` |
| ISS-S1-004 | App Service, Managed Identity y slot staging | ✅ local + Azure | `iss-s1-004/` |
| ISS-S1-005 | VNet, subredes, DNS y Private Endpoints | ✅ local + Azure | `iss-s1-005/` |
| ISS-S1-006 | Entra ID, roles y RBAC mínimo | ✅ local + Azure | `iss-s1-006/` |
| ISS-S1-007 | Contrato de transacción (OpenAPI, DTO, mapper) | ✅ local | `iss-s1-007/` |
| ISS-S1-008 | Persistir transacción cruda en Blob | ✅ local (IT MockMvc) | `iss-s1-008/` |
| ISS-S1-009 | Carga técnica de documentos | ✅ local (IT MockMvc) | `iss-s1-009/` |
| ISS-S1-010 | Roundtrip de Queue Storage | ⏳ scripts OK · run Azure pendiente | `iss-s1-010/` |
| ISS-S1-011 | Proteger endpoints y mínimo privilegio | ✅ local (401/403 MockMvc) | `iss-s1-011/` |
| ISS-S1-012 | Probar alta disponibilidad de la API | ⏳ scripts OK · run Azure pendiente | `iss-s1-012/` |
| ISS-S1-013 | README, matriz, diagrama, ADR y evidencias | ✅ local | `iss-s1-013/` |
| ISS-S1-014 | Destrucción, reconstrucción y cierre final | ⏳ scripts OK · run Azure pendiente | `final/` |

---

## Detalle por issue

### ISS-S1-001 — Repositorio Java hexagonal
- `iss-s1-001/01-mvn-clean-verify.txt` — `mvn clean verify`.
- `iss-s1-001/02-package-tree.txt` — árbol de paquetes hexagonales.
- `iss-s1-001/03-scan-repository.txt` — escaneo de secretos (TEST-S1-002).

### ISS-S1-002 — Scripts base de infraestructura
- `iss-s1-002/01-tests.txt`, `02-shellcheck.txt`, `03-validate-only.txt` — parámetros
  obligatorios, ShellCheck y `--validate-only`. Ver `iss-s1-002/README.md`.

### ISS-S1-003 — Storage, contenedores y colas
- `iss-s1-003/01..03` — validación local (validate-only, tests, ShellCheck).
- `iss-s1-003/05-azure-provision.txt`, `06-azure-validation.txt`, `07-azure-idempotency.txt`,
  `08-azure-resources-final.txt` — provisionamiento, validación e idempotencia en Azure real.

### ISS-S1-004 — App Service, Managed Identity y slot staging
- `iss-s1-004/01-syntax-and-arm-render.txt`, `02-sku-validation.txt` — validación previa.
- `iss-s1-004/03-provision-app-service.txt`, `04-validate-app-service.txt`,
  `06-deploy-application.txt` — provisionamiento y despliegue.

### ISS-S1-005 — Red privada y DNS
- `iss-s1-005/02-provision-network.txt`, `03-configure-private-endpoints.txt`,
  `04-validate-network.txt` — VNet, Private Endpoints y resolución privada.

### ISS-S1-006 — Entra ID y RBAC
- `iss-s1-006/01-syntax-and-approles.txt`, `02-provision-entra-app.txt`,
  `03-assign-rbac.txt`, `04-validate-rbac.txt` — app roles, RBAC mínimo y validación.

### ISS-S1-007 — Contrato de transacción
- `iss-s1-007/01-required-tests.txt`, `02-full-test-suite.txt`, `03-openapi-lint.txt` —
  pruebas obligatorias, suite completa y lint OpenAPI.
- `iss-s1-007/examples/` — `valid-request.json`, `202-response.json`, `400-response.json`.

### ISS-S1-008 — Persistencia en Blob
- `iss-s1-008/runs/20260718T210504Z/` — unit test del caso de uso, IT de API, IT de Blob
  (Azure), suite completa y escaneo de alcance.
- IT MockMvc (`202`/`503`) ejecutadas localmente en la suite `mvn verify`.

### ISS-S1-009 — Carga de documentos
- `iss-s1-009/runs/20260718T214017Z/` — service test, IT de API/contrato, IT de Blob
  documental (Azure), suite completa.
- `iss-s1-009/examples/` — `201-response.json`, `400-response.json`, documento de ejemplo.

### ISS-S1-010 — Roundtrip de Queue *(scripts OK · run Azure pendiente)*
- `iss-s1-010/01-syntax-check.txt`, `iss-s1-010/README.md`.

### ISS-S1-011 — Seguridad de endpoints
- `iss-s1-011/01-endpoint-authorization-test.txt` — mapeo de roles (7/7).
- `iss-s1-011/02-full-verify-suite.txt` — IT MockMvc `401`/`403`/`202`/`201`. Ver README.

### ISS-S1-012 — Alta disponibilidad *(scripts OK · run Azure pendiente)*
- `iss-s1-012/01-syntax-check.txt`, `iss-s1-012/README.md`.

### ISS-S1-013 — Documentación y trazabilidad
- `iss-s1-013/01-validate-documentation.txt`, `02-validate-week1-scope.txt`,
  `03-scan-repository.txt`, `04-full-verify-suite.txt`. Ver README.

### ISS-S1-014 — Cierre final *(scripts OK · run Azure pendiente)*
- `final/01-syntax-check.txt`, `final/README.md`.

---

## Referencias

- [Matriz de Trazabilidad](../5_Issues_y_Trazabilidad/2_Matriz_Trazabilidad.md)
- [README Principal](../../Readme.md)
- [Arquitectura](../architecture/centinela-week1.md)
