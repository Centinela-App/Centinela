# Evidencia — ISS-S1-006 · Entra ID, roles y RBAC mínimo

**Issue 6 / ISS-S1-006 — alcance ESTRICTO**: crear la App Registration de la API
con los **4 app roles** (`SERVICE`, `ANALYST`, `ADMINISTRATOR`, `AUDITOR`) y aplicar
**Azure RBAC de mínimo privilegio**: la **Managed Identity** de producción y staging
recibe acceso de **datos Blob** acotado por contenedor (sin claves), la aplicación
**no recibe rol de Queue**, Analista/Auditor demo reciben `Reader`, y la prueba de
cola usa una asignación **temporal** identificada para revocación. **Ninguna**
identidad recibe `Contributor`/`Owner`. La autorización HTTP (Spring Security) es
ISS-S1-011, fuera de alcance.

- **Rama:** `12-iss-s1-006-configurar-entra-id-roles-y-rbac-minimo`
- **Entorno objetivo:** Azure Cloud Shell (Bash + Azure CLI)
- **Planos:** aplicación (app roles de Entra) y Azure RBAC (control/datos) — no se confunden.

## Archivos del alcance estricto

| Ruta | Rol |
|---|---|
| `scripts/provision-entra-app.sh` | App Registration + 4 app roles + Service Principal (idempotente). |
| `scripts/assign-rbac.sh` | RBAC mínimo: Blob Data a la MI por contenedor; Reader demo; prueba de cola temporal + revocación; guard anti Owner/Contributor. |
| `scripts/tests/validate-rbac.sh` | Comando §12: agrega TEST-S1-008/009/010 + escaneo global de admins en el RG. |
| `scripts/tests/validate-entra-roles.sh` | TEST-S1-008: existencia/tipo de los 4 app roles. |
| `scripts/tests/test-analyst-rbac.sh` | TEST-S1-009: Analista/Auditor no pueden modificar (solo Reader). |
| `scripts/tests/validate-managed-identity.sh` | TEST-S1-010: MI con Blob Data en sus contenedores y **sin** rol de Queue. |
| `docs/evidence/identity/.gitkeep` | Carpeta para registros sanitizados en tiempo de ejecución. |
| `docs/evidence/iss-s1-006/01..05` | Evidencia offline + esperada. |

## Modelo de permisos aplicado

### Plano de aplicación (app roles de Entra)
```text
SERVICE        allowedMemberTypes=[Application]   (identidad de servicio, desatendida)
ANALYST        allowedMemberTypes=[User]
ADMINISTRATOR  allowedMemberTypes=[User]
AUDITOR        allowedMemberTypes=[User]
```
identifierUri = `api://<appId>`; **sin secreto de cliente** (Managed Identity/JWT en ISS-S1-011).

### Plano de Azure (RBAC)
| Identidad | Rol | Alcance | Notas |
|---|---|---|---|
| MI producción | `Storage Blob Data Contributor` | contenedores `*-production` | escritura de datos, sin claves |
| MI staging | `Storage Blob Data Contributor` | contenedores `*-staging` | escritura de datos, sin claves |
| MI (ambas) | — (ningún rol de Queue) | — | la cola no participa del negocio S1 |
| Analista/Auditor demo | `Reader` | Resource Group | solo si se pasan sus `principalId` |
| Prueba de cola | `Storage Queue Data Message Processor` | Storage Account | **temporal**, se revoca con `--revoke-queue-test` |

**Regla dura:** `assign-rbac.sh` rechaza `Owner`, `Contributor` y `User Access Administrator`.

## Trazabilidad de criterios de aceptación (§8)

- [x] **Los cuatro roles de aplicación existen** — `validate-entra-roles.sh` (TEST-S1-008).
- [x] **Analista y Auditor no pueden modificar/eliminar** — solo `Reader`, sin roles de
  escritura; `test-analyst-rbac.sh` (TEST-S1-009), con intento real opcional `--live-attempt`.
- [x] **La MI puede escribir en los contenedores necesarios sin claves** — `Storage Blob
  Data Contributor` por contenedor; `validate-managed-identity.sh` (TEST-S1-010).
- [x] **La aplicación no recibe permisos de Queue** — verificado por ausencia de cualquier
  rol con "Queue" en la MI.
- [x] **La asignación temporal de la prueba de cola queda identificada para revocación** —
  registro `docs/evidence/identity/temp-queue-assignment.record.txt` + `--revoke-queue-test`.

## Escenarios Gherkin (§10)
- **Managed Identity con mínimo privilegio** → Blob Data Contributor por contenedor, sin cadena de conexión.
- **Analista sin modificación** → solo Reader; intento de `az tag update` denegado (`--live-attempt`).
- **Permiso excesivo detectado** → si aparece Contributor/Owner para Analista/Auditor, TEST-S1-009 falla e identifica la asignación.

## Cómo probarlo en Azure Cloud Shell

```bash
cd ~ && git clone https://github.com/Centinela-App/Centinela.git && cd Centinela
git checkout 12-iss-s1-006-configurar-entra-id-roles-y-rbac-minimo

export SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export LOCATION="eastus2"; export RESOURCE_GROUP="rg-centinela-week1"
export NAME_PREFIX="cent"; export APP_SERVICE_SKU="S1"

# Prerequisitos: 003 (Storage) y 004 (App Service + MI)
bash scripts/provision-storage.sh
bash scripts/provision-app-service.sh

# ISS-S1-006:
chmod +x scripts/provision-entra-app.sh scripts/assign-rbac.sh scripts/tests/*.sh
bash scripts/provision-entra-app.sh          # requiere rol de directorio (App Administrator)
bash scripts/assign-rbac.sh                  # RBAC mínimo (MI Blob Data por contenedor)
ANALYST_PRINCIPAL_ID=<objectId> bash scripts/tests/validate-rbac.sh   # TEST-S1-008/009/010
```

### Prerequisito de permisos
`provision-entra-app.sh` crea objetos de directorio: el ejecutor necesita **Application
Administrator** (o Cloud Application Administrator). `assign-rbac.sh` necesita poder crear
role assignments en el RG/Storage (p. ej. **User Access Administrator** acotado, u Owner
del RG solo para el despliegue — nunca se concede a identidades funcionales).

## Archivos autorizados

- **Creados (§5):** `provision-entra-app.sh`, `assign-rbac.sh`, `tests/validate-rbac.sh`,
  `tests/validate-entra-roles.sh`, `tests/test-analyst-rbac.sh`,
  `tests/validate-managed-identity.sh`, `docs/evidence/identity/.gitkeep`.
- **Modificados (§6):** `scripts/deploy-week1.sh` (2 pasos añadidos a `PROVISION_STEPS`),
  `scripts/destroy-week1.sh` (limpieza tenant-level de la App Registration),
  `docs/3_Seguridad/1_Seguridad_Backend.md` (subsección de identificadores técnicos).
- **Prohibidos:** no se creó `scripts/grant-owner.sh`, no se tocó `.env` real ni
  `src/main/resources/*secret*`.

## Desviaciones y pendientes

- **Analista/Auditor demo y prueba de cola** requieren `principalId` reales del tenant;
  los scripts los aceptan por flag/env y, si faltan, lo documentan (no inventan usuarios).
  TEST-S1-009 queda `PEND` hasta ejecutarse con el principal del Analista.
- **Ejecución real en vivo** (Entra + RBAC) la corre quien tenga rol de directorio; aquí
  se entrega validado offline (`bash -n` + JSON de app roles) y con salidas esperadas.
- La conversión de claims a authorities Spring y la autorización 401/403 por endpoint
  (TEST-S1-021/022) son **ISS-S1-011**, fuera de esta issue.
