# Evidencia ISS-S1-011 — Proteger endpoints y verificar mínimo privilegio

**Commit de restauración:** rama `fix/restaurar-issues-006-014` (código reintegrado tras
el revert accidental del PR #26).
**Pruebas obligatorias:** TEST-S1-021, TEST-S1-022 (Seguridad HTTP).
**Pruebas posteriores ejecutadas localmente:** TEST-S1-016, TEST-S1-019 a nivel HTTP con MockMvc.

## Implementación verificada

`SecurityConfiguration` (OAuth2 Resource Server JWT) aplica las reglas:

| Método + endpoint | Authority requerida | Sin token | Rol incorrecto |
|---|---|---|---|
| `POST /api/v1/transactions` | `ROLE_SERVICE` | `401` | `403` |
| `POST /api/v1/verification-documents` | `ROLE_ANALYST` | `401` | `403` |
| `/actuator/health/**`, `/actuator/info` | público | — | — |
| cualquier otro | autenticado | `401` | — |

`EntraRolesJwtAuthenticationConverter` traduce los app roles de Entra
(`SERVICE`, `ANALYST`, `ADMINISTRATOR`, `AUDITOR`) a authorities `ROLE_*`, ignora
valores desconocidos y no otorga authorities cuando falta el claim `roles`.

## Resultados

- `01-endpoint-authorization-test.txt` — `EndpointAuthorizationTest` (7/7 OK): mapeo
  de cada rol, múltiples roles, rol desconocido ignorado y claim ausente sin authorities.
- `02-full-verify-suite.txt` — suite completa `mvn verify` (62 pruebas, 2 IT de Azure
  omitidas por guarda de entorno). Incluye:
  - `TransactionEndpointAuthorizationIT` (5/5): `401` sin token y `403` con `ROLE_ANALYST`
    sobre `/transactions`, `202` con `ROLE_SERVICE`.
  - `DocumentEndpointAuthorizationIT` (5/5): `401`/`403` sobre `/verification-documents`,
    `201` con `ROLE_ANALYST`.

## Comandos reproducibles

```bash
mvn -Dtest=EndpointAuthorizationTest test
mvn verify   # ejecuta también los IT de autorización 401/403 (MockMvc)
```

## Pendiente de suscripción Azure

La matriz E2E contra el App Service desplegado con tokens reales de Entra ID
(TEST-S1-016, TEST-S1-019 desplegados) requiere una suscripción activa. La lógica de
autorización queda demostrada de forma equivalente con las IT MockMvc anteriores.
No se registran tokens ni encabezados `Authorization` (verificado en la configuración).
