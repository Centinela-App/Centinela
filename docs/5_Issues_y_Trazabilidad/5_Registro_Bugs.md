# 12 — Registro de bugs e incidencias

| ID | Fecha | Descripción | Impacto | Issue relacionada | Estado | Evidencia de cierre |
|---|---|---|---|---|---|---|
| BUG-S1-001 | 2026-07-21 | El revert del PR #26 (revert del PR #25 de HA) eliminó de `develop` todo el código y evidencias de las issues 006–011 (controllers, DTOs, servicios, adaptadores Blob, seguridad JWT, scripts Entra/RBAC/Queue) además de la 012. | Crítico: `develop` no compilaba con los endpoints; 9 issues quedaron sin su implementación. Error de código/VCS. | ISS-S1-006..012 | Cerrado | Código reintegrado desde `17114d4` en rama `fix/restaurar-issues-006-014`; `mvn clean verify` = 62 pruebas OK. |
| BUG-S1-002 | 2026-07-21 | El OpenAPI en `docs/1_Requisitos_y_Contrato/` quedó (tras el revert) sin `additionalProperties: false` ni `operationId`, rompiendo los tests de contrato. | Alto: `OpenApiContractTest` y `VerificationDocumentOpenApiContractTest` fallaban. Error de configuración/contrato. | ISS-S1-007, ISS-S1-009 | Cerrado | OpenAPI restaurado; tests de contrato OK (6 pruebas). |
| BUG-S1-003 | 2026-07-21 | `validate-documentation.sh` usaba `DOCS_DIR=scripts/../docs` (nivel faltante) y buscaba arquitectura en `2_Arquitectura/` en vez de `architecture/`; reportaba 9 entregables como inexistentes aunque existían. | Alto: TEST-S1-025 fallaba con falsos negativos. Error de código (rutas). | ISS-S1-013 | Cerrado | `01-validate-documentation.txt`: VALIDACION PASADA. |
| BUG-S1-004 | 2026-07-21 | `scan-repository.sh` y `validate-week1-scope.sh` se auto-detectaban el patrón `AccountKey=` de su propio `grep`; además el check de scope marcaba el slot `staging` (requerido por ISS-S1-004) como violación de Semana 2. | Medio: TEST-S1-002 y TEST-S1-028 fallaban con falsos positivos. Error de código. | ISS-S1-013 | Cerrado | `02-validate-week1-scope.txt` y `03-scan-repository.txt`: OK. |
| BUG-S1-005 | 2026-07-21 | El proyecto no configuraba `maven-failsafe-plugin`, por lo que las pruebas de integración `*IT` (401/403/202/201 con MockMvc) nunca se ejecutaban en `mvn verify`. | Medio: pruebas posteriores locales no ejecutadas. Error de configuración. | ISS-S1-008, ISS-S1-009, ISS-S1-011 | Cerrado | Failsafe añadido; 23 IT ejecutadas (2 de Azure omitidas por guarda de entorno). |
| BUG-S1-006 | 2026-07-21 | Existía un archivo `env` (sin punto) versionable con un `SUBSCRIPTION_ID` real; no estaba cubierto por `.gitignore` y `*.log` impedía versionar los logs de evidencia de cierre requeridos por ISS-S1-014. | Medio: riesgo de fuga de secreto y de no poder versionar evidencia de cierre. | ISS-S1-001, ISS-S1-014 | Cerrado | `.gitignore`: añadido `/env` y excepción `!docs/evidence/**/*.log`. Secreto ya no versionado (scan OK). |

## Reglas

- No registrar como bug una funcionalidad de Semana 2 que aún no fue solicitada.
- Distinguir error de código, configuración de Azure, permiso, red y límite de crédito.
- Todo cierre debe incluir pasos de reproducción y prueba posterior.
