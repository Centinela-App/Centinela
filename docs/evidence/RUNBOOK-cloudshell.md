# Runbook — Corrida en Azure Cloud Shell (ISS-S1-003 → 006)

Guía única para ejecutar en vivo la infraestructura de Semana 1 y recolectar la
evidencia real. Orden: **003 (Storage) → 004 (App Service) → 005 (Red/PE) → 006
(Entra/RBAC)**, con sus validaciones obligatorias.

> Entorno: **Azure Cloud Shell (Bash)**. Usa **tus valores reales**; no commitees `.env`.

## Prerrequisitos de permisos

- Provisionar recursos: contribuir sobre el Resource Group del proyecto.
- `provision-entra-app.sh`: rol de directorio **Application Administrator** (o Cloud
  Application Administrator) para crear la App Registration + Service Principal.
- `assign-rbac.sh`: poder crear *role assignments* en el RG/Storage (p. ej. Owner del
  RG **solo** para el despliegue; nunca se concede a Analista/Auditor).

---

## 0) Abrir Cloud Shell y clonar

```bash
cd ~ && git clone https://github.com/Centinela-App/Centinela.git && cd Centinela
git checkout develop            # develop ya tiene 003, 004, 005 y 006
```

## 1) Parámetros (exporta o usa tu `.env` en la raíz)

```bash
export SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export LOCATION="eastus2"                 # tu región
export RESOURCE_GROUP="rg-centinela-week1"
export NAME_PREFIX="cent"                 # 3-11 minúsculas
export APP_SERVICE_SKU="S1"               # debe soportar slots (S1+)
```

## 2) Login, suscripción y Resource Group

```bash
az login                                  # si no estás logueado
az account set --subscription "$SUBSCRIPTION_ID"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
chmod +x scripts/*.sh scripts/tests/*.sh
mkdir -p evidence-run                      # carpeta local para guardar salidas
```

## 3) Provisión en orden (cada paso guarda su salida)

```bash
bash scripts/provision-storage.sh            2>&1 | tee evidence-run/03-storage.txt      # ISS-003
bash scripts/provision-app-service.sh        2>&1 | tee evidence-run/04-appservice.txt   # ISS-004
bash scripts/provision-network.sh            2>&1 | tee evidence-run/05-network.txt      # ISS-005
bash scripts/configure-private-endpoints.sh  2>&1 | tee evidence-run/05-endpoints.txt    # ISS-005
bash scripts/provision-entra-app.sh          2>&1 | tee evidence-run/06-entra.txt        # ISS-006 (Application Administrator)
bash scripts/assign-rbac.sh                  2>&1 | tee evidence-run/06-rbac.txt          # ISS-006
```

> Alternativa en un solo comando: `bash scripts/deploy-week1.sh` (crea el RG y ejecuta
> todos los pasos de `PROVISION_STEPS` en orden). Para recolectar evidencia limpia se
> prefieren los pasos individuales.

## 4) Validaciones obligatorias (TEST-S1-005/006/007/008/009/010)

```bash
bash scripts/tests/validate-storage.sh       2>&1 | tee evidence-run/val-05-storage.txt      # TEST-S1-005
bash scripts/tests/validate-app-service.sh   2>&1 | tee evidence-run/val-06-appservice.txt   # TEST-S1-006
bash scripts/tests/validate-network.sh       2>&1 | tee evidence-run/val-07-network.txt      # TEST-S1-007

# ISS-006 — pasa el objectId real del Analista para cerrar TEST-S1-009:
export ANALYST_PRINCIPAL_ID="<objectId-del-analista>"   # az ad user show --id <upn> --query id -o tsv
export AUDITOR_PRINCIPAL_ID="<objectId-del-auditor>"    # opcional
bash scripts/tests/validate-rbac.sh          2>&1 | tee evidence-run/val-06-rbac.txt         # agrega 008/009/010
```

## 5) (Opcional) Reader demo + prueba de cola temporal y su revocación

```bash
# Reader a Analista/Auditor y rol de cola TEMPORAL para la prueba de ISS-010:
bash scripts/assign-rbac.sh \
  --analyst-principal "$ANALYST_PRINCIPAL_ID" \
  --auditor-principal "$AUDITOR_PRINCIPAL_ID" \
  --queue-test-principal "<objectId-sp-de-prueba>"      2>&1 | tee evidence-run/06-rbac-demo.txt

# Intento real de modificación como Analista (debe ser DENEGADO) — en sesión del Analista:
bash scripts/tests/test-analyst-rbac.sh --analyst "$ANALYST_PRINCIPAL_ID" --live-attempt

# Revocar la asignación temporal de cola al terminar la prueba:
bash scripts/assign-rbac.sh --revoke-queue-test "<objectId-sp-de-prueba>"  2>&1 | tee evidence-run/06-rbac-revoke.txt
```

## 6) Empaquetar la evidencia real para el repo

Los `.txt` en `docs/evidence/**` son la **salida esperada**; sustitúyelos por la real
(vienen sanitizados con `…` en los ids — verifica que no quede ningún secreto).

```bash
ls -la evidence-run/
cp evidence-run/val-06-appservice.txt docs/evidence/iss-s1-004/04-validate-app-service.txt
cp evidence-run/val-07-network.txt    docs/evidence/iss-s1-005/04-validate-network.txt
cp evidence-run/val-06-rbac.txt       docs/evidence/iss-s1-006/04-validate-rbac.txt
# ...revisar, luego commit/push de la evidencia real.
```

## 7) Al terminar — destruir y controlar costos

```bash
bash scripts/destroy-week1.sh            # pide teclear el nombre del RG; borra RG + limpia el App de Entra
# bash scripts/destroy-week1.sh --yes           # sin confirmación
# bash scripts/destroy-week1.sh --keep-entra    # conserva la App Registration
```

---

## Notas

- **Idempotencia**: puedes reejecutar cualquier `provision-*` / `assign-rbac`; convergen
  sin duplicar recursos.
- **`ANALYST_PRINCIPAL_ID`**: sin él, TEST-S1-009 sale como `PEND` (no falla, pero no
  cierra el criterio de aceptación).
- **Costos**: una sola instancia en operación normal; la segunda solo durante la prueba
  HA (ISS-S1-012). Ejecuta `destroy-week1.sh` al terminar la demostración.
- **Nombres deterministas**: Storage `<prefix>st<hash6>`, Web App `<prefix>-app-<hash6>`,
  VNet `<prefix>-vnet-week1`, App Entra `<prefix>-api-week1` (hash = `sha1(prefix|sub|rg)[:6]`).
