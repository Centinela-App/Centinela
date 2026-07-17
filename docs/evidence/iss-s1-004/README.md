# Evidencia — ISS-S1-004 · App Service, Managed Identity y slot staging

**Issue 4 / ISS-S1-004 — alcance ESTRICTO**: aprovisionar **1 App Service Plan**
(Linux, SKU y region por parametros con soporte de slots + escala horizontal),
**1 Web App de produccion** y **1 slot `staging`** en el mismo plan, con
**System Assigned Managed Identity** en ambos y **configuracion aislada por
ambiente** (produccion → recursos `*-production`, staging → `*-staging`), marcando
como **slot settings (sticky)** las variables que no deben intercambiarse en un
swap. Preparar el despliegue de **un unico artefacto** sin pipeline CI/CD. Nada mas.

- **Rama:** `7-iss-s1-004-crear-app-service-managed-identity-y-slot-staging`
- **Entorno objetivo:** Azure Cloud Shell (Bash + Azure CLI ya preinstalados)
- **Ejecucion:** control plane via ARM template inline (declarativo, idempotente)

## Archivos del alcance estricto

| Ruta | Rol |
|---|---|
| `scripts/provision-app-service.sh` | Implementacion ISS-S1-004: crea/asegura Plan + Web App + slot `staging` + Managed Identity + app settings por ambiente + slot settings sticky, via ARM. |
| `scripts/deploy-application.sh` | Despliegue de un unico artefacto `.jar` (Spring Boot / Java 21) a un slot, con swap opcional. Sin CI/CD. |
| `scripts/tests/validate-app-service.sh` | TEST-S1-006: verifica en Azure Web App + slot + identidades + aislamiento por ambiente + slot settings + 1 instancia. |
| `docs/evidence/iss-s1-004/01-syntax-and-arm-render.txt` | Chequeo `bash -n` + render y validacion estructural del ARM template (offline, reproducible). |
| `docs/evidence/iss-s1-004/02-sku-validation.txt` | Gherkin "SKU no compatible": aceptacion/rechazo de SKUs por soporte de slots. |
| `docs/evidence/iss-s1-004/03-provision-app-service.txt` | Salida esperada de `provision-app-service.sh` en Cloud Shell. |
| `docs/evidence/iss-s1-004/04-validate-app-service.txt` | Salida esperada de TEST-S1-006 (27 PASS / 0 FAIL). |
| `docs/evidence/iss-s1-004/05-integracion-deploy-week1.txt` | Integracion con `scripts/deploy-week1.sh` (paso ya registrado). |
| `docs/evidence/iss-s1-004/06-deploy-application.txt` | Uso de `deploy-application.sh` (despliegue de artefacto unico + swap). |

## Recursos creados (constantes del script)

```text
Plan (Linux):   <NAME_PREFIX>-asp-week1     sku.capacity = 1   (1 instancia)
Web App (prod): <NAME_PREFIX>-app-<hash6>   identity = SystemAssigned, httpsOnly
Slot:           staging                     identity = SystemAssigned, httpsOnly
Runtime:        JAVA|21-java21              healthCheckPath = /actuator/health
TAGS (4):       project=centinela, week=1, team=celula-centinela, issue=ISS-S1-004
```

El nombre de la Web App es determinista (`<prefix>-app-<sha1(prefix|sub|rg)[:6]>`),
igual criterio que el Storage de ISS-S1-003; `CENTINELA_STORAGE_ACCOUNT` referencia
esa misma cuenta compartida sin secretos.

## Configuracion por ambiente (app settings NO secretas)

| Setting | Produccion | Staging | Sticky (slot setting) |
|---|---|---|---|
| `SPRING_PROFILES_ACTIVE` | `production` | `staging` | sí |
| `CENTINELA_ENVIRONMENT` | `production` | `staging` | sí |
| `CENTINELA_RAW_TRANSACTIONS_CONTAINER` | `raw-transactions-production` | `raw-transactions-staging` | sí |
| `CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER` | `verification-documents-production` | `verification-documents-staging` | sí |
| `CENTINELA_INGESTION_QUEUE` | `transactions-ingestion-production` | `transactions-ingestion-staging` | sí |
| `CENTINELA_STORAGE_ACCOUNT` | `<sa compartida>` | `<sa compartida>` | no (compartido) |
| `WEBSITES_PORT` | `8080` | `8080` | no (compartido) |

Las 5 variables de identidad de ambiente se registran en
`slotConfigNames.appSettingNames`, por lo que **NO viajan en un swap**: staging
sigue apuntando a `*-staging` y produccion a `*-production` incluso tras promover.

## Idempotencia

El ARM template es declarativo: reejecutar `provision-app-service.sh` converge al
mismo estado sin duplicar recursos y **restablece `capacity=1`** (util despues de
una prueba HA de ISS-S1-012). `with_retry 3` envuelve el `az deployment group create`.

## Trazabilidad de criterios de aceptacion (§8)

- [x] **Web App y slot staging existen en el mismo plan** — un unico `serverFarmId`
  compartido; `validate-app-service.sh` compara ambos y el nombre del plan.
- [x] **Ambos tienen Managed Identity activa** — `identity.type=SystemAssigned` en
  site y slot; el test valida `principalId` no vacio y distinto entre ambos.
- [x] **Produccion usa `*-production` y staging usa `*-staging`** — app settings por
  ambiente + deteccion de configuracion cruzada en el test.
- [x] **El SKU y region provienen de parametros** — `APP_SERVICE_SKU` y `LOCATION`;
  el test compara `sku.name` y `location` contra los parametros.
- [x] **El plan queda en una instancia tras el despliegue normal** — `sku.capacity=1`.

## Como probarlo en Azure Cloud Shell

### 1) Abrir Cloud Shell (Bash) desde https://portal.azure.com y clonar el repo
```bash
cd ~ && git clone https://github.com/Centinela-App/Centinela.git && cd Centinela
git checkout 7-iss-s1-004-crear-app-service-managed-identity-y-slot-staging
```

### 2) Configurar variables (`.env` en la raiz o exportar)
```bash
export SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export LOCATION="eastus2"
export RESOURCE_GROUP="rg-centinela-week1"
export NAME_PREFIX="cent"
export APP_SERVICE_SKU="S1"        # DEBE soportar slots (Standard+). B1/F1/D1 se rechazan.
```

### 3) Prerequisitos: RG + Storage (ISS-S1-002/003)
```bash
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"   # si no existe
bash scripts/provision-storage.sh                                 # ISS-S1-003
```

### 4) Provisionar App Service + slot + identidad (ISS-S1-004)
```bash
chmod +x scripts/provision-app-service.sh scripts/tests/validate-app-service.sh scripts/deploy-application.sh
bash scripts/provision-app-service.sh
```
Salida esperada: `03-provision-app-service.txt`.

### 5) Validar (TEST-S1-006)
```bash
bash scripts/tests/validate-app-service.sh
```
Salida esperada (27 PASS / 0 FAIL): `04-validate-app-service.txt`.

### 6) (Opcional) Desplegar el artefacto y promover
```bash
bash scripts/deploy-application.sh --build            # publica en 'staging'
bash scripts/deploy-application.sh --slot staging --swap   # promueve a produccion
```

### 7) Verificar en el portal
1. "App Services" → `cent-app-<hash6>` → "Deployment slots": debe verse `staging`.
2. "Identity" (produccion y slot): "System assigned" = **On**.
3. "Configuration" → "Application settings": los `CENTINELA_*` con "Deployment slot
   setting" marcado; staging con valores `*-staging`, produccion con `*-production`.
4. "Scale out (App Service plan)": 1 instancia.

## Escenarios Gherkin cubiertos (§10)

- **Produccion y staging separados** → app settings distintos por ambiente
  (`03`/`04`) y verificacion `verify_all_resources` / test §8.
- **SKU no compatible** → `assert_sku_supports_slots` aborta antes de crear nada
  (`02-sku-validation.txt`).
- **Configuracion cruzada** → el test marca `FAIL CONFIG CRUZADA ...` e identifica
  el setting incorrecto (nota al pie de `04`).

## Archivos autorizados

- **Creados:** `scripts/provision-app-service.sh`, `scripts/deploy-application.sh`,
  `scripts/tests/validate-app-service.sh` (§5 de la issue).
- **Modificables no modificados:** `scripts/deploy-week1.sh`, `scripts/validate-week1.sh`,
  `scripts/destroy-week1.sh` — el paso `provision-app-service.sh` ya estaba registrado
  en `PROVISION_STEPS` y la validacion de SKU/region ya existia (ver `05`).
- **Prohibidos:** no se toco `.github/workflows/**` ni `scripts/provision-runner.sh`.

## Pendiente fuera de este cambio

- Ejecucion real en vivo con `az login` (Persona 2 o Persona 4) — captura de
  `03`/`04`/`06` con salidas reales de Azure.
- Revision cruzada de Persona 5.
- RBAC minimo de la identidad sobre el Storage: lo aporta ISS-S1-006.
- Acceso privado (Private Endpoints/DNS) y VNet integration: lo aporta ISS-S1-005.
