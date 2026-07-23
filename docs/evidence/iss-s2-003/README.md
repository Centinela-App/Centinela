# Evidencia — ISS-S2-003 · Key Vault + migración de secretos + auditoría de historial

**Issue S2-003 — alcance ESTRICTO:** crear **1 Azure Key Vault** (RBAC data plane, soft-delete +
purge protection), migrar a él el **único secreto real** de Semana 2 (connection string de Cosmos
for MongoDB), otorgar acceso por **Managed Identity** (`Key Vault Secrets User`) a la Web App y su
slot, y **auditar el historial de git** para confirmar ausencia de credenciales.

- **Entorno objetivo:** Azure Cloud Shell (Bash + Azure CLI preinstalados).
- **Ejecución:** control plane vía Azure CLI (`az keyvault ...`, `az role assignment ...`).

## Por qué existe Key Vault ahora (revisión de ADR-005)

Semana 1 difirió Key Vault (ADR-005): sin secretos inevitables, no se crea un vault vacío. En
Semana 2, **Cosmos for MongoDB** autentica su plano de datos con **connection string/key** (la API
Mongo no soporta Entra ID en el wire protocol) → aparece un **secreto real**. El principio se
mantiene: **PostgreSQL** usa Entra ID exclusiva (sin password) y **Event Grid** publica por
Managed Identity; solo Cosmos aporta un secreto, y por eso —y solo por eso— se crea el vault.

## Archivos del alcance estricto

| Ruta | Rol |
|---|---|
| `scripts/provision-keyvault.sh` | Crea el vault, migra el secreto de Cosmos, asigna RBAC, referencia el secreto en app settings. Idempotente. |
| `scripts/tests/validate-keyvault.sh` | TEST-S2-003: vault, RBAC, purge protection, secreto (por nombre), rol Secrets User a app+slot, tags. |
| `scripts/tests/audit-git-secrets.sh` | TEST-S2-026: audita el historial completo (gitleaks o fallback grep). |
| `scripts/assign-rbac.sh` | Actualizado: agrega `Key Vault Secrets User` a prod+slot si el vault existe. |
| `src/main/resources/application.yml` | Referencia `${CENTINELA_COSMOS_CONNECTION_STRING:}` (sin valor). |
| `docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` | ADR-005 revisada (parcialmente derogada). |

## Configuración aplicada

```text
Key Vault:     <prefix>-kv-<hash6>   (nombre determinista, global-único, 3..24)
Autorización:  RBAC data plane (enableRbacAuthorization=true)
Protección:    soft-delete 90d + purge protection
Secreto:       cosmos-mongo-connection-string   (valor NUNCA versionado ni impreso)
App setting:   CENTINELA_COSMOS_CONNECTION_STRING = @Microsoft.KeyVault(SecretUri=.../secrets/cosmos-mongo-connection-string/)
Roles:         Key Vault Secrets User -> MI de Web App (prod) y slot (staging)
               Key Vault Secrets Officer -> deployer (efímero, para poder cargar el secreto)
Tags:          project=centinela, week=2, team=celula-centinela, issue=ISS-S2-003
```

> La identidad de la **Function** de scoring aún no existe; su rol `Secrets User` se otorga en
> **ISS-S2-007** (donde se crea la Function).

## Auditoría del historial de git (TEST-S2-026)

Estado detectado en el historial actual:
- **Sin credenciales reales** (keys de Storage, connection strings con `AccountKey`, claves
  privadas, `client-secret`) en ningún commit.
- Existe un `.env` **commiteado y revertido** (`3ea6b91` → revert `740905f`) que contenía
  **solo identificadores** (SUBSCRIPTION_ID/LOCATION/RG/PREFIX), **no** credenciales. El script
  lo reporta como **advertencia** cuando hay documento de remediación registrado
  (`docs/SECURITY-remediacion-env-leak.md`); si no lo hay, falla y exige registrar la remediación.

`gitleaks` no está instalado localmente → el script usa el **fallback grep**. En CI (capa 4) se
recomienda `gitleaks` para la detección profunda.

## Verificaciones offline (sin Azure) — ya ejecutadas

- `bash -n` de los 3 scripts → sin errores de sintaxis.
- `audit-git-secrets.sh` → sin credenciales reales en el historial.
- `scan-repository.sh` → limpio (sin secretos ni connection strings versionadas).

## Cómo probarlo en Azure (Cloud Shell)

```bash
# 1) Parámetros (o usar .env) y autenticación
export SUBSCRIPTION_ID="<tu-subscription-id>"; export LOCATION="eastus2"
export RESOURCE_GROUP="rg-centinela-dev"; export NAME_PREFIX="cent"
export APP_SERVICE_SKU="S1"
az login && az account set --subscription "$SUBSCRIPTION_ID"

# 2) Provisión (requiere Cosmos de ISS-S2-001 ya desplegado)
bash scripts/provision-keyvault.sh

# 3) Validaciones
bash scripts/tests/validate-keyvault.sh
bash scripts/tests/audit-git-secrets.sh
bash scripts/tests/scan-repository.sh
```

## Pendiente fuera de este cambio

- Ejecución real en vivo con `az login` (Persona 1 en Cloud Shell) → salida sanitizada.
- Rol `Secrets User` a la Function → **ISS-S2-007** (Persona 3).
- Revisión cruzada de Persona 5.
