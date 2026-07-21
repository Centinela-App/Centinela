# 09 — Seguridad de Semana 1

## Roles de aplicación

| Rol | Permiso actual de Semana 1 |
|---|---|
| `SERVICE` | Enviar transacciones. |
| `ANALYST` | Cargar documentos de verificación. |
| `ADMINISTRATOR` | Administra usuarios y configuración cuando existan las funciones correspondientes; en Semana 1 no recibe permiso de escritura sobre los endpoints de negocio. |
| `AUDITOR` | Solo lectura; no tiene operaciones de escritura en los endpoints de Semana 1. |

## Azure RBAC

- La identidad de despliegue posee solo el alcance necesario sobre el Resource Group del proyecto.
- Analista y Auditor pueden recibir `Reader` para demostrar consulta sin modificación.
- La Managed Identity de App Service recibe acceso de datos a los contenedores que usa la API.
- La aplicación no necesita permiso de Queue Storage porque la cola no forma parte del flujo de negocio de Semana 1.
- La identidad que ejecuta la prueba temporal de cola recibe el permiso mínimo y se revoca al finalizar si fue asignado solo para la prueba.

## Identificadores técnicos (ISS-S1-006)

Concretados por los scripts `scripts/provision-entra-app.sh` y `scripts/assign-rbac.sh`:

| Elemento | Valor / identificador | Notas |
|---|---|---|
| App Registration (API) | `<NAME_PREFIX>-api-week1` (override: `ENTRA_APP_DISPLAY_NAME`) | `identifierUri = api://<appId>`; sin secreto de cliente. |
| App roles (`value`) | `SERVICE`, `ANALYST`, `ADMINISTRATOR`, `AUDITOR` | `SERVICE` → `allowedMemberTypes=[Application]`; resto → `[User]`. |
| Rol de datos de la Managed Identity | `Storage Blob Data Contributor` | Acotado por **contenedor** (prod → `*-production`, staging → `*-staging`). |
| Rol de la prueba de cola (temporal) | `Storage Queue Data Message Processor` | Solo para el roundtrip de ISS-S1-010; se revoca con `assign-rbac.sh --revoke-queue-test`. |
| Roles funcionales demo | `Reader` (Analista/Auditor) | Alcance Resource Group; solo si se pasan sus `principalId`. |

Regla dura aplicada por `assign-rbac.sh`: nunca asigna `Owner`, `Contributor` ni
`User Access Administrator` (guard explícito).

## Secretos

- Se usa Managed Identity siempre que sea posible.
- No se guardan claves ni cadenas de conexión en el repositorio.
- Si aparece un secreto real, se almacena en Azure Key Vault; no es obligatorio crear un vault vacío.

## Red

- Acceso público de Storage deshabilitado.
- App Service se integra con la VNet.
- Blob y Queue usan Private Endpoints y resolución DNS privada.
