# Evidencia — ISS-S1-003 · Provisionar Storage Account, contenedores y colas por ambiente

**Issue 3 / ISS-S1-003 — alcance ESTRICTO**: crear/asegurar **1 Storage Account**
+ **4 contenedores** (staging/production × raw-transactions/verification-documents)
+ **2 colas** (transactions-ingestion staging/production), con propiedades de
seguridad obligatorias y tags de trazabilidad. Nada más.

- **Rama:** `iss-s1-003-crear-storage-contenedores-y-colas-por-ambiente`
- **Entorno objetivo:** Azure Cloud Shell (Bash + Azure CLI ya preinstalados)
- **Ejecución:** control plane via ARM template inline (sin tocar data plane)

## Archivos del alcance estricto

| Ruta | Rol |
|---|---|
| `scripts/provision-storage.sh` | Implementación ISS-S1-003 (crea/asegura Storage + containers + queues vía ARM). |
| `scripts/tests/validate-storage.sh` | TEST-S1-005: verifica en Azure que el SA + contenedores + colas cumplen las propiedades obligatorias. |
| `docs/evidence/iss-s1-003/02-tests-validate-storage.txt` | Salida esperada de TEST-S1-005 en Cloud Shell. |
| `docs/evidence/iss-s1-003/03-shellcheck.txt` | Resultado esperado de `shellcheck` sobre los dos scripts. |
| `docs/evidence/iss-s1-003/04-integracion-deploy-week1.txt` | Confirmación de auto-discovery por `deploy-week1.sh`. |

## Recursos creados (constantes del script)

```text
CONTAINERS (4):  raw-transactions-{staging,production}
                 verification-documents-{staging,production}
QUEUES (2):      transactions-ingestion-{staging,production}
TAGS (4):        project=centinela, week=1, team=celula-centinela, issue=ISS-S1-003
```

## Propiedades de seguridad aplicadas (ARM template inline)

- `kind = StorageV2`, `sku.name = Standard_LRS`
- `minimumTlsVersion = TLS1_2`
- `supportsHttpsTrafficOnly = true`
- `allowBlobPublicAccess = false`
- `publicNetworkAccess = Disabled`
- `networkAcls.defaultAction = Deny`, `networkAcls.bypass = AzureServices`
- `encryption.keySource = Microsoft.Storage`, cifrado habilitado en blob/queue/file/table
- `publicAccess = None` por contenedor

## Idempotencia

`assert_storage_account_compliant_if_exists` consulta el SA existente y, si existe,
**falla con error claro** si alguna propiedad obligatoria no se cumple (no sobreescribe).
Si no existe o si las propiedades son correctas, salta el deploy. Re-ejecutable sin
efectos colaterales. `with_retry 3` envuelve el `az deployment group create`.

## Cómo probarlo en el portal de Azure (Azure Cloud Shell)

### 1) Abrir Cloud Shell desde el portal

1. Ve a https://portal.azure.com
2. Inicia sesión con la cuenta que tiene acceso a la suscripción del proyecto.
3. Arriba a la derecha, click en el icono de Cloud Shell (`> _`) — abre un terminal
   Bash en el navegador. Si te pide elegir, elige **Bash** (no PowerShell).

### 2) Subir los scripts al Cloud Shell

En la barra superior del Cloud Shell, click en **"Upload/Download files" → "Upload"**
y sube toda la carpeta `scripts/` (o al menos `scripts/provision-storage.sh`,
`scripts/tests/validate-storage.sh`, `scripts/lib/common.sh`, `scripts/lib/parameters.sh`).
También necesitas el `.env` (o exportar las variables manualmente — ver paso 3).

Alternativa rápida: clonar el repo.
```bash
cd ~
git clone https://github.com/Centinela-App/Centinela.git
cd Centinela
```

### 3) Configurar variables (sin `.env` también funciona)

Si subiste los archivos y NO tienes `.env`, exporta manualmente:
```bash
export SUBSCRIPTION_ID="<tu-subscription-id>"
export LOCATION="eastus2"
export RESOURCE_GROUP="rg-centinela-week1"
export NAME_PREFIX="cent"
# APP_SERVICE_SKU no es necesario para ISS-S1-003
```

Para obtener tu `SUBSCRIPTION_ID` actual en Cloud Shell:
```bash
az account show --query id -o tsv
```

Si subiste `.env` en la raíz, `scripts/lib/parameters.sh` lo lee automáticamente.

### 4) Autenticarse y seleccionar suscripción

```bash
az login                # si no estas logueado, abrira un codigo de device login
az account set --subscription "$SUBSCRIPTION_ID"
```

### 5) Asegurar el Resource Group (ISS-S1-001/002 debe estar hecho)

Si aún no existe el RG:
```bash
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
```

### 6) Ejecutar la provisión (ISS-S1-003)

```bash
cd ~/Centinela          # o la ruta donde quedaron los scripts
chmod +x scripts/provision-storage.sh scripts/tests/validate-storage.sh
bash scripts/provision-storage.sh
```

Salida esperada (resumen):
```
[INFO] Storage Account objetivo: centst<hash6> (longitud: <n>)
[INFO] Storage Account 'centst<hash6>' no existe. Desplegando...
[INFO] Desplegando Storage Account 'centst<hash6>' via ARM (control plane)...
[INFO] Deployment ARM completado.
[INFO] Verificando contenedores...
[INFO]   OK contenedor: raw-transactions-staging
[INFO]   OK contenedor: raw-transactions-production
[INFO]   OK contenedor: verification-documents-staging
[INFO]   OK contenedor: verification-documents-production
[INFO] Verificando colas...
[INFO]   OK cola: transactions-ingestion-staging
[INFO]   OK cola: transactions-ingestion-production
[INFO] ISS-S1-003 OK: Storage + 4 contenedores + 2 colas listos.
```

Re-ejecutar el mismo comando es idempotente:
```
[INFO] Storage Account 'centst<hash6>' ya existe. Validando configuracion...
[INFO] Storage Account 'centst<hash6>' ya existe y cumple las propiedades obligatorias. Sin cambios.
[INFO] ISS-S1-003 OK: Storage + 4 contenedores + 2 colas listos.
```

### 7) Validar el resultado (TEST-S1-005)

```bash
bash scripts/tests/validate-storage.sh
```

Verifica existencia + 7 propiedades de seguridad + 4 tags + 4 contenedores + 2 colas
+ intento HTTP anónimo al endpoint público (debe ser rechazado). Salida esperada
completa en `02-tests-validate-storage.txt`.

### 8) Verificar visualmente en el portal

1. Ve a https://portal.azure.com → "Storage accounts" → busca `centst<hash6>`.
2. Click en el SA → "Containers": debes ver los 4 contenedores listados.
3. Click en el SA → "Queues" → "Storage browser (preview)" o "Queues":
   debes ver las 2 colas.
4. Click en el SA → "Networking": debe decir "Public network access: Disabled".
5. Click en el SA → "Encryption": cifrado Microsoft-managed keys habilitado.

### 9) (Opcional) Probar el orquestador completo de Semana 1

```bash
bash scripts/deploy-week1.sh     # ejecuta todos los provision-* en orden
```

`deploy-week1.sh` descubre automáticamente `scripts/provision-*.sh` por glob, así
que **no fue necesario modificarlo**. Ver `04-integracion-deploy-week1.txt`.

## Pendiente fuera de este cambio

- Ejecución real en vivo con `az login` (Persona 2 o Persona 4) — fuera de este cambio.
- Revisión cruzada de Persona 5.
- Activación real del cifrado CMK cuando ISS-S1-005 (Key Vault) esté en main.