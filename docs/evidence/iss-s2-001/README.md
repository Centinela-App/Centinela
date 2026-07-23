# Evidencia — ISS-S2-001 · Almacén de transacciones (Cosmos DB for MongoDB)

**Issue S2-001 — alcance ESTRICTO:** crear/asegurar **1 cuenta Cosmos DB (API MongoDB)** con
Free Tier, la base `centinela`, la colección `transactions`, la **shard key `accountId`**, el
nivel de **consistencia `Session`** y una **política de expiración (TTL) de 90 días**. Nada más.

- **Entorno objetivo:** Azure Cloud Shell (Bash + Azure CLI preinstalados).
- **Ejecución:** control plane vía Azure CLI (`az cosmosdb ...`), sin tocar el data plane.

## Archivos del alcance estricto

| Ruta | Rol |
|---|---|
| `scripts/provision-cosmos.sh` | Implementación ISS-S2-001 (crea/asegura cuenta + base + colección, idempotente). |
| `scripts/tests/validate-cosmos.sh` | TEST-S2-001: verifica en Azure cuenta, Free Tier, consistencia, shard key, TTL y tags. |
| `scripts/deploy-week2.sh` | Orquestador de Semana 2 (registra `provision-cosmos.sh` como paso 1). |
| `docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md` | ADR-007: justificación de partición, consistencia y TTL. |

## Configuración aplicada

```text
Cuenta:        <prefix>-cosmos-<hash6>   (nombre determinista, global-unico)
Base:          centinela
Colección:     transactions
Shard key:     accountId          (INMUTABLE tras la primera escritura)
Consistencia:  Session            (configurable con COSMOS_CONSISTENCY)
TTL:           7 776 000 s (90 d) (configurable con COSMOS_TTL_SECONDS)
API/Version:   MongoDB 4.2        (configurable con COSMOS_MONGO_VERSION)
Free Tier:     habilitado         (1000 RU/s + 25 GB)
Tags:          project=centinela, week=2, team=celula-centinela, issue=ISS-S2-001
```

## Verificaciones offline (sin Azure) — ya ejecutadas

- `bash -n` de los 3 scripts → sin errores de sintaxis.
- Fail-fast: `provision-cosmos.sh` exige `RESOURCE_GROUP` **antes** de tocar Azure.
- Nombre determinista: mismas entradas → mismo nombre válido para Cosmos (`[a-z0-9-]`, 3..44).
- Gate de secretos (`scan-repository.sh`) → limpio (sin secretos ni GUIDs reales).

## Cómo probarlo en Azure (Cloud Shell)

```bash
# 1) Parámetros (o usar .env de Semana 1)
export SUBSCRIPTION_ID="<tu-subscription-id>"
export LOCATION="eastus2"
export RESOURCE_GROUP="rg-centinela-dev"
export NAME_PREFIX="cent"
export APP_SERVICE_SKU="S1"   # exigido por parameters.sh aunque S2-001 no lo use

# 2) Autenticación
az login
az account set --subscription "$SUBSCRIPTION_ID"

# 3) Provisión (idempotente)
bash scripts/provision-cosmos.sh

# 4) Validación (TEST-S2-001)
bash scripts/tests/validate-cosmos.sh
```

### Salida esperada (resumen)

```
[INFO] Cuenta Cosmos objetivo: cent-cosmos-<hash6>
[INFO] Creando cuenta Cosmos '...' (API MongoDB 4.2, Free Tier, consistencia Session)...
[INFO] Creando base 'centinela'...
[INFO] Creando coleccion 'transactions' (shard key=accountId, TTL=7776000s)...
[INFO]   OK coleccion: transactions (shard=accountId, ttl=7776000s)
[INFO] ISS-S2-001 OK: Cosmos (Mongo) + base 'centinela' + coleccion 'transactions' listos.
```

Re-ejecutar `provision-cosmos.sh` es **idempotente**: si la cuenta ya existe y cumple, no la
recrea; la colección con shard key no se recrea (la shard key es inmutable).

## Pendiente fuera de este cambio

- Ejecución real en vivo con `az login` (Persona 1 en Cloud Shell) → adjuntar salida sanitizada.
- Adaptador Java de lectura/escritura → **ISS-S2-007** (Persona 3).
- Guardar la connection string de Cosmos en Key Vault → **ISS-S2-003**.
- Revisión cruzada de Persona 3.
