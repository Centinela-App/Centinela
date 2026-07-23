# Evidencia — ISS-S2-002 · Almacén de casos (PostgreSQL Flexible Server privado)

**Issue S2-002 — alcance ESTRICTO:** crear/asegurar **1 servidor PostgreSQL Flexible Server**
(Burstable **B1ms**, Free tier), **accesible solo desde la VNet** por Private Endpoint (acceso
público deshabilitado), con **autenticación Entra ID exclusiva** y **estrategia de respaldo
documentada**. Sin tablas ni esquema de casos (eso es ISS-S2-010).

- **Entorno objetivo:** Azure Cloud Shell (Bash + Azure CLI preinstalados).
- **Ejecución:** control plane vía Azure CLI (`az postgres flexible-server ...`, `az network ...`).

## Archivos del alcance estricto

| Ruta | Rol |
|---|---|
| `scripts/provision-postgres.sh` | Implementación ISS-S2-002 (servidor + PE + DNS privada + hardening, idempotente). |
| `scripts/tests/validate-postgres.sh` | TEST-S2-002: verifica SKU, acceso público, auth, respaldo, PE y DNS. |
| `scripts/deploy-week2.sh` | Orquestador de Semana 2 (ya registra `provision-postgres.sh` como paso 2). |
| `docs/4_Infraestructura_y_Despliegue/3_Estrategia_Respaldo.md` | Estrategia de respaldo (periodicidad, retención, RPO). |

## Configuración aplicada

```text
Servidor:      <prefix>-pg-<hash6>   (nombre determinista, global-único)
Tier / SKU:    Burstable / Standard_B1ms   (Free tier)
Storage:       32 GiB                       (configurable con POSTGRES_STORAGE_GB)
Versión:       PostgreSQL 16               (configurable con POSTGRES_VERSION)
Red:           publicNetworkAccess=Disabled + Private Endpoint en snet-private-endpoints
Zona DNS:      privatelink.postgres.database.azure.com  (vinculada a la VNet)
Auth:          Entra ID exclusiva (passwordAuth=Disabled) → conexión por Managed Identity
Respaldo:      automático, retención 7 días, geo-redundante Disabled, RPO ≈ 5 min (PITR)
Tags:          project=centinela, week=2, team=celula-centinela, issue=ISS-S2-002
```

## Decisión de red: Private Endpoint (coherente con Semana 1)

PostgreSQL Flexible Server fija su modelo de red en la creación. Se eligió **Private Endpoint**
(servidor creado con `--public-access None` + `publicNetworkAccess=Disabled` + PE) en lugar de
**VNet injection** (subred delegada) para **reutilizar exactamente el patrón que Semana 1 ya
montó para Storage** (subred `snet-private-endpoints`, zonas `privatelink.*`,
`configure-private-endpoints.sh`) y **no** modificar `provision-network.sh` ni crear una subred
delegada nueva.

## Verificaciones offline (sin Azure) — ya ejecutadas

- `bash -n` de los 2 scripts → sin errores de sintaxis.
- Fail-fast: `provision-postgres.sh` exige `RESOURCE_GROUP` y la subred PE **antes** de crear.
- Nombre determinista: mismas entradas → mismo nombre válido (`[a-z0-9-]`, 3..63).
- Gate de secretos (`scan-repository.sh`) → limpio (sin secretos ni GUIDs reales).

## Cómo probarlo en Azure (Cloud Shell)

```bash
# 1) Parámetros (o usar .env de Semana 1)
export SUBSCRIPTION_ID="<tu-subscription-id>"
export LOCATION="eastus2"
export RESOURCE_GROUP="rg-centinela-dev"
export NAME_PREFIX="cent"
export APP_SERVICE_SKU="S1"   # exigido por parameters.sh aunque S2-002 no lo use

# 2) Autenticación
az login
az account set --subscription "$SUBSCRIPTION_ID"

# 3) Provisión (idempotente)
bash scripts/provision-postgres.sh

# 4) Validación (TEST-S2-002)
bash scripts/tests/validate-postgres.sh
```

## Pendiente fuera de este cambio

- Ejecución real en vivo con `az login` (Persona 1 en Cloud Shell) → adjuntar salida sanitizada.
- Esquema relacional de casos + auditoría → **ISS-S2-010** (Persona 4).
- Guardar cualquier secreto de infraestructura en Key Vault → **ISS-S2-003** (aquí no aplica:
  el servidor no tiene password de conexión).
- Revisión cruzada de Persona 4.
