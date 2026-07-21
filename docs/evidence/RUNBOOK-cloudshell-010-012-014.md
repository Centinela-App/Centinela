# Runbook — Cierre en Azure Cloud Shell (ISS-S1-010, 012, 014)

Ejecuta en vivo las 3 pruebas que faltan y recolecta su evidencia real. Continúa donde
termina `RUNBOOK-cloudshell.md` (003→006). Requiere la infraestructura desplegada.

> Entorno: **Azure Cloud Shell (Bash)**. Usa tus valores reales; no commitees `.env`.
> Los scripts fueron corregidos para que los nombres coincidan con lo provisionado
> (colas `transactions-ingestion-*`, Web App `<prefix>-app-<hash6>`, plan `<prefix>-asp-week1`).

---

## 0) Clonar y parámetros

```bash
cd ~ && rm -rf Centinela && git clone https://github.com/Centinela-App/Centinela.git && cd Centinela
git checkout develop
chmod +x scripts/*.sh scripts/tests/*.sh

export SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export LOCATION="eastus2"                  # tu región
export RESOURCE_GROUP="rg-centinela-week1"
export NAME_PREFIX="cent"                   # 3-11 minúsculas
export APP_SERVICE_SKU="S1"
az account set --subscription "$SUBSCRIPTION_ID"

# Nombres deterministas (idénticos a los que calculan los scripts):
HASH="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"
export STORAGE_ACCOUNT="${NAME_PREFIX}st${HASH}"
export WEBAPP_NAME="${NAME_PREFIX}-app-${HASH}"
export PLAN_NAME="${NAME_PREFIX}-asp-week1"
echo "Storage=$STORAGE_ACCOUNT  WebApp=$WEBAPP_NAME  Plan=$PLAN_NAME"
```

> Si aún no está desplegado el entorno: `bash scripts/deploy-week1.sh` (crea el RG y
> ejecuta storage, app service, red, private endpoints, entra y rbac).

---

## 1) ISS-S1-010 — Roundtrip de Queue (TEST-S1-020)

Requiere que tu identidad tenga rol de datos de cola sobre el Storage. Asignación temporal:

```bash
MY_OID="$(az ad signed-in-user show --query id -o tsv)"
SA_ID="$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RESOURCE_GROUP" --query id -o tsv)"
az role assignment create --assignee "$MY_OID" \
  --role "Storage Queue Data Contributor" --scope "$SA_ID"
```

Ejecuta el roundtrip en ambos ambientes (envía → recibe → valida testRunId → elimina → verifica sin residuos):

```bash
export STAGING_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export PRODUCTION_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"

bash scripts/validate-queue.sh staging     2>&1 | tee evidence-run/10-queue-staging.txt
bash scripts/validate-queue.sh production   2>&1 | tee evidence-run/10-queue-production.txt
```

Revoca la asignación temporal al terminar (mínimo privilegio):

```bash
az role assignment delete --assignee "$MY_OID" \
  --role "Storage Queue Data Contributor" --scope "$SA_ID"
```

La evidencia por corrida queda en `docs/evidence/queue/run-*.json`. Copia los `.txt`
sanitizados a `docs/evidence/iss-s1-010/`.

---

## 2) ISS-S1-012 — Alta disponibilidad (TEST-S1-024)

Necesita un token de servicio real (app role `SERVICE`) y la app desplegada. Obtén un
bearer token con client credentials del App Registration de la API:

```bash
# Datos del App Registration creado en ISS-S1-006:
APP_ID="$(az ad app list --display-name "${NAME_PREFIX}-api-week1" --query "[0].appId" -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
# Necesitas el secreto de un cliente de servicio autorizado con el app role SERVICE.
# (Créalo solo para la prueba; no lo commitees.)
export CENTINELA_SERVICE_TOKEN="$(curl -s -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -d "client_id=<client-de-servicio>" \
  -d "client_secret=<secreto-temporal>" \
  -d "scope=api://${APP_ID}/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)"

export CENTINELA_API_BASE_URL="https://${WEBAPP_NAME}.azurewebsites.net"
export CENTINELA_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export CENTINELA_RAW_TRANSACTIONS_CONTAINER="raw-transactions-production"

bash scripts/test-ha.sh 2>&1 | tee evidence-run/12-ha.txt
```

`test-ha.sh` escala el plan `$PLAN_NAME` a 2 workers, retira una instancia bajo carga,
reconcilia cada `202` con su Blob y **restaura a 1 instancia en el `trap` de salida**
(incluso si falla). Evidencia en `docs/evidence/ha/` (load, scale-events, reconciliation).
Copia el resumen a `docs/evidence/iss-s1-012/`.

---

## 3) ISS-S1-014 — Destrucción, reconstrucción y cierre (TEST-S1-026 / 027)

Ambos scripts generan su propio `run-*/` bajo `docs/evidence/final/` con metadata,
deployment.log, validation-summary.md, resource-inventory.json y cleanup.log:

```bash
bash scripts/tests/test-clean-deploy.sh            2>&1 | tee evidence-run/14-clean-deploy.txt   # TEST-S1-026
bash scripts/tests/test-destroy-rebuild-cleanup.sh 2>&1 | tee evidence-run/14-destroy-rebuild.txt # TEST-S1-027
```

> `test-clean-deploy.sh` corre `mvn clean verify` internamente; Cloud Shell trae Java y
> Maven. Si la versión de JDK no es 21 el paso Maven se marca “WITH WARNINGS” pero no
> aborta la prueba de infraestructura.

Al terminar, verifica que el RG quedó eliminado (control de costos):

```bash
az group exists --name "$RESOURCE_GROUP"   # debe devolver false
```

---

## 4) Versionar la evidencia real (sanitizada)

```bash
git checkout -b evidence/cierre-010-012-014
# copia los .txt sanitizados a docs/evidence/iss-s1-010, iss-s1-012 y confirma los run-*/ de final/
git add docs/evidence
git commit -m "docs(evidence): corridas reales ISS-S1-010, 012 y 014 en Cloud Shell"
git push -u origin evidence/cierre-010-012-014
```

> Verifica que NINGÚN log contenga tokens, `client_secret`, connection strings ni el
> `SUBSCRIPTION_ID` sin enmascarar antes de commitear. `bash scripts/tests/scan-repository.sh`.
