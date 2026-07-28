# Guía técnica de los scripts de despliegue

Guía de aprendizaje para entender **qué hace cada script, cómo funciona por dentro y cómo
harías lo mismo a mano** en el Portal de Azure o con `az` suelto.

Está pensada para leerse en orden: los conceptos de las primeras secciones se usan en
todas las siguientes.

---

## Índice

1. [Conceptos de Azure que hay que tener claros](#1-conceptos-de-azure-que-hay-que-tener-claros)
2. [Anatomía común de todos los scripts](#2-anatomía-común-de-todos-los-scripts)
3. [`lib/common.sh` — el cimiento](#3-libcommonsh--el-cimiento)
4. [`lib/parameters.sh` — parámetros y validación](#4-libparameterssh--parámetros-y-validación)
5. [`deploy-all.sh` — el orquestador](#5-deploy-allsh--el-orquestador)
6. [Semana 1 — infraestructura base](#6-semana-1--infraestructura-base)
7. [Semana 2 — datos, mensajería y scoring](#7-semana-2--datos-mensajería-y-scoring)
8. [`destroy-week1.sh` — destrucción segura](#8-destroy-week1sh--destrucción-segura)
9. [Patrones de diseño que se repiten](#9-patrones-de-diseño-que-se-repiten)

---

## 1. Conceptos de Azure que hay que tener claros

### 1.1 · Control plane vs data plane

Es **la** distinción que explica media arquitectura de estos scripts.

| | Control plane | Data plane |
|---|---|---|
| Qué hace | Crear, configurar, borrar recursos | Leer/escribir **datos dentro** del recurso |
| Endpoint | `management.azure.com` (ARM) | `<cuenta>.blob.core.windows.net`, `<server>.postgres...` |
| Ejemplo | `az storage account create` | `az storage blob upload` |
| Autenticación | Azure RBAC (roles de gestión) | Azure RBAC de datos, claves, o token Entra |

**Por qué importa aquí:** el proyecto deshabilita el acceso **público al data plane** de
Storage, Cosmos y PostgreSQL. Puedes seguir creando y configurando esos recursos desde
cualquier máquina (control plane, siempre público), pero **no puedes leer sus datos** sin
estar dentro de la red privada.

De ahí que casi todo el despliegue funcione desde tu portátil, y solo el paso que ejecuta
`psql` contra PostgreSQL necesite un camino privado.

### 1.2 · ARM y las plantillas

**ARM** (Azure Resource Manager) es la API de control. Puedes hablarle de dos formas:

- **Imperativa:** `az storage account create --name X ...` → "haz esto ahora".
- **Declarativa:** una plantilla JSON que describe el **estado deseado**, y ARM calcula
  qué hace falta. Es idempotente por naturaleza.

Estos scripts usan **plantillas ARM** para los recursos con muchas propiedades acopladas
(Storage, App Service, red) y `az` imperativo para el resto. La plantilla se genera al
vuelo con un *heredoc* de bash en un directorio temporal.

### 1.3 · Managed Identity

Una identidad en Entra ID que **Azure gestiona por ti** y asocia a un recurso (una Web
App, una Function). El recurso obtiene tokens sin que exista ninguna contraseña.

- **System-assigned:** nace y muere con el recurso. Es la que usa este proyecto.
- **User-assigned:** independiente, reutilizable entre recursos.

**Por qué es el corazón del diseño:** no hay una sola cadena de conexión con contraseña en
todo el despliegue. La Web App accede a Storage, Key Vault y PostgreSQL presentando un
token de su Managed Identity.

### 1.4 · RBAC y el ámbito (scope)

Una asignación de rol son tres cosas: **quién** (principal) + **qué puede hacer** (rol) +
**dónde** (ámbito).

El ámbito es jerárquico y se hereda hacia abajo:

```
/subscriptions/<id>                                      ← suscripción
  /resourceGroups/rg-centinela-week1                     ← grupo de recursos
    /providers/Microsoft.Storage/storageAccounts/centst… ← cuenta
      /blobServices/default/containers/raw-transactions-production   ← contenedor
```

Este proyecto asigna al **nivel más bajo posible**. La Web App de producción no tiene
permiso sobre "el Storage", sino sobre *dos contenedores concretos*. Si alguien compromete
la app, no puede tocar los contenedores de staging.

### 1.5 · Private Endpoint y DNS privado

Un **Private Endpoint** es una tarjeta de red dentro de tu VNet con una IP privada que
representa a un servicio PaaS. Tiene dos mitades que se suelen confundir:

1. **La conexión de red** — el PE en sí, con su IP privada (ej. `10.10.2.4`).
2. **La resolución de nombres** — para que `centst….blob.core.windows.net` devuelva esa IP
   privada en vez de la pública, hace falta una **zona DNS privada**
   (`privatelink.blob.core.windows.net`) **vinculada a la VNet**, y un **DNS zone group**
   que publique el registro A.

**Si creas el PE pero olvidas el zone group, el recurso parece configurado y es
inalcanzable por nombre.** Eso fue exactamente uno de los bugs corregidos: la
comprobación fallaba y los zone groups nunca se creaban.

### 1.6 · VNet Integration (salida de App Service)

Es lo simétrico del Private Endpoint:

- **Private Endpoint** = tráfico **entrante** hacia un servicio PaaS por IP privada.
- **VNet Integration** = tráfico **saliente** de tu App Service inyectado en una subred.

La subred de integración debe estar **delegada** a `Microsoft.Web/serverFarms`, lo que la
reserva en exclusiva para App Service.

Con `vnetRouteAllEnabled=true`, **todo** el tráfico saliente de la app va por la VNet, de
modo que resuelve las zonas DNS privadas y alcanza los Private Endpoints.

---

## 2. Anatomía común de todos los scripts

Todos siguen la misma estructura. Reconocerla te permite leer cualquiera de ellos rápido:

```bash
#!/usr/bin/env bash
# Cabecera: objetivo, alcance ESTRICTO, prerequisitos, variables.

set -euo pipefail          # 1. Modo estricto

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"       # 2. Utilidades
source "$SCRIPT_DIR/lib/parameters.sh"   # 3. Parámetros

readonly ALGO="valor"      # 4. Constantes del alcance

while [ "$#" -gt 0 ]; do   # 5. Parseo de argumentos
  case "$1" in ... esac
done

compute_x_name() { ... }   # 6. Nombres deterministas
render_arm_template() {…}  # 7. Plantilla (si aplica)
ensure_x() { ... }         # 8. Creación idempotente
verify_all_resources() {…} # 9. Verificación contra Azure

main() {                   # 10. Orquestación
  load_parameters
  validate_parameters
  # ...comprobaciones previas...
  # ...creación...
  # ...verificación...
}
main "$@"
```

### `set -euo pipefail`, línea por línea

| Flag | Qué hace | Por qué |
|---|---|---|
| `-e` | Aborta si un comando devuelve ≠ 0 | Que un fallo no pase desapercibido |
| `-u` | Aborta al usar una variable no definida | Caza erratas en nombres de variable |
| `-o pipefail` | Una tubería falla si **cualquier** etapa falla | Sin esto, `az … \| grep` oculta el error de `az` |

> **Trampa real de `set -e`.** Si la **última** sentencia de una función es
> `[ cond ] && comando` y `cond` es falsa, la función devuelve 1 y `set -e` **mata el
> script sin imprimir nada**. Fue el bug original que bloqueó el despliegue. Escribe
> siempre `if cond; then comando; fi`.

---

## 3. `lib/common.sh` — el cimiento

Utilidades compartidas. No sabe nada de Azure ni del negocio.

### 3.1 · Compatibilidad con Git Bash en Windows

```bash
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    export MSYS2_ARG_CONV_EXCL='/subscriptions/;/providers/'
    az() { command az "$@" | tr -d '\r'; }
    ;;
esac
```

Dos problemas de Windows resueltos:

1. **`az` imprime CRLF.** Cualquier `$(az … -o tsv)` arrastra un `\r` final, y comparar
   `"abc\r" = "abc"` **siempre falla**. La función `az()` envuelve al comando real
   (`command az` evita recursión infinita) y filtra el `\r`.
2. **MSYS reescribe rutas.** Cualquier argumento que empiece por `/` lo convierte a ruta
   de Windows, corrompiendo los `--scope` de RBAC (`/subscriptions/...`).
   `MSYS2_ARG_CONV_EXCL` excluye solo esos prefijos — desactivarlo del todo rompería los
   `--template-file`, que **sí** necesitan ruta Windows.

> Si copias estos scripts a Linux o Cloud Shell, este bloque no se activa y todo funciona
> igual.

### 3.2 · Logging y `die`

```bash
log_info()  { printf '%s[INFO]%s  %s\n'  "$_C_GREEN"  "$_C_RESET" "$*" >&2; }
die() { log_error "$*"; exit 1; }
```

Todo va a **stderr** (`>&2`). Así, si una función devuelve un valor con `printf` a stdout,
los logs no lo contaminan:

```bash
nombre="$(compute_storage_account_name …)"   # stdout limpio
```

### 3.3 · `mask` — no filtrar identificadores

```bash
mask() {
  local v="${1:-}"; local n=${#v}
  if [ "$n" -le 8 ]; then printf '****'; else printf '%s…%s' "${v:0:4}" "${v: -4}"; fi
}
```

Convierte `ae1e7c2d-...-4f3b6eb6` en `ae1e…6eb6`: suficiente para correlacionar en el log,
insuficiente para reutilizar.

### 3.4 · `with_retry` y `retry_until`

```bash
with_retry() {          # reintenta y AVISA
  local max="$1"; shift; local attempt=1
  until "$@"; do
    if [ "$attempt" -ge "$max" ]; then return 1; fi
    log_warn "Intento $attempt/$max fallo; reintentando en ${attempt}s..."
    sleep "$attempt"; attempt=$((attempt + 1))
  done
}

retry_until() {         # reintenta en SILENCIO (para verificar)
  local max="$1"; shift; local attempt=1
  while true; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    [ "$attempt" -ge "$max" ] && return 1
    sleep "$attempt"; attempt=$((attempt + 1))
  done
}
```

Ambos usan **backoff lineal** (1 s, 2 s, 3 s…).

- `with_retry` → **crear** cosas: el fallo es excepcional, hay que avisarlo.
- `retry_until` → **verificar** cosas: el fallo inicial es esperado (Azure es asíncrono).

**Por qué hace falta:** un deployment ARM puede reportar éxito antes de que sus recursos
hijo sean consultables, y el registro DNS de un Private Endpoint es asíncrono por diseño.
Sin reintento, la verificación falla por carrera aunque todo esté bien.

### 3.5 · `discover_tool` y `require_cmd`

```bash
require_cmd() {
  command -v "$1" >/dev/null 2>&1 && return 0
  discover_tool "$1" && return 0
  die "Falta la dependencia requerida: '$1'. Instalala y reintenta."
}
```

En Windows, los instaladores de PostgreSQL y winget **no** tocan el `PATH` de la sesión:
`psql` y `jq` existen pero son invisibles. `discover_tool` los busca en las rutas estándar
(PostgreSQL, WinGet Links/Packages, Chocolatey, Scoop) y las añade al `PATH` de la corrida.

> Usa un **array** de rutas candidatas, no una lista sin comillas: `Program Files` lleva un
> espacio que rompería el *word splitting*.

### 3.6 · Helpers de Private Endpoint

```bash
pe_dns_zone_group_exists() {
  local pe="$1" rg="$2" n
  n="$(az network private-endpoint dns-zone-group list \
        --endpoint-name "$pe" --resource-group "$rg" \
        --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  [ "${n:-0}" -ge 1 ] 2>/dev/null
}
```

**Existe por un bug muy instructivo:** `az network private-endpoint dns-zone-group show`
devuelve **código de salida 0 con cuerpo `{}`** cuando el grupo no existe. Comprobarlo con
`if az … show; then` da *siempre* verdadero, el grupo nunca se crea, y el Private Endpoint
queda sin registro DNS.

**Lección:** con `az`, verifica el **contenido**, no el código de salida.

---

## 4. `lib/parameters.sh` — parámetros y validación

```bash
load_parameters() {
  local env_file="${ENV_FILE:-$params_dir/../../.env}"
  if [ -f "$env_file" ]; then
    set -a          # exporta automáticamente todo lo que se defina
    source "$env_file"
    set +a
  fi
}
```

`set -a` hace que cada asignación del `.env` quede **exportada**, visible para los
subprocesos (`az`, sub-scripts). Sin él, las variables serían locales al script.

> Las variables **ya presentes en el entorno ganan** sobre el `.env` si las exportas antes.
> Útil en CI.

`validate_parameters` valida **formato** antes de tocar Azure — falla en 50 ms en vez de a
los 10 minutos:

```bash
[[ "$SUBSCRIPTION_ID" =~ ^[0-9a-fA-F]{8}-…$ ]] || die "…UUID valido."
[[ "$NAME_PREFIX" =~ ^[a-z0-9]{3,11}$ ]]       || die "…3-11 minusculas/numeros."
```

`NAME_PREFIX` se limita a 3-11 porque el nombre de Storage (`<prefix>st<hash6>`) no puede
pasar de 24 caracteres ni usar mayúsculas.

---

## 5. `deploy-all.sh` — el orquestador

Punto de entrada único. No crea nada por sí mismo: encadena los demás scripts.

### Fase 0 · Preflight

```bash
preflight() {
  load_parameters
  validate_parameters               # falla offline antes de tocar Azure
  require_cmd az; require_cmd git; require_cmd sha1sum
  assert_java_21

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] || die "Suscripcion activa != SUBSCRIPTION_ID."

  loc_display="$(az account list-locations --query "[?name=='$LOCATION'] | [0].displayName" -o tsv)"
  [ -n "$loc_display" ] || die "Region '$LOCATION' no valida."
  az appservice list-locations --sku "$APP_SERVICE_SKU" \
      --query "[?name=='$loc_display'] | [0].name" -o tsv | grep -q . \
    || die "SKU '$APP_SERVICE_SKU' no disponible en '$LOCATION'."
}
```

Valida **suscripción activa == la esperada**. Sin esa comprobación, un `az account set`
olvidado despliega en la suscripción equivocada — un error caro y difícil de deshacer.

`assert_java_21` valida el JDK de **`JAVA_HOME`**, no el del `PATH`, porque **Maven usa
`JAVA_HOME`**. Validar otro sería validar algo que no se usa.

### Nombres deterministas

```bash
hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"
```

Los nombres salen de un hash de `prefijo|suscripción|grupo`:

| Recurso | Patrón | Ejemplo |
|---|---|---|
| Storage | `<prefix>st<hash>` | `centsta84cc6` |
| Web App | `<prefix>-app-<hash>` | `cent-app-a84cc6` |
| PostgreSQL | `<prefix>-pg-<hash>` | `cent-pg-a84cc6` |

**Por qué:** Storage, Key Vault y Web App necesitan nombres **globalmente únicos en todo
Azure**. Con el hash, cada suscripción obtiene nombres distintos sin colisionar, y los
mismos parámetros producen siempre el mismo nombre — así el script puede *recalcular* el
nombre en vez de guardarlo.

### `run_step` — ejecución con registro

```bash
run_step() {
  local label="$1"; shift
  log_file="$RUN_DIR/${slug}.log"
  started="$(date +%s)"
  set +e
  "$@" 2>&1 | tee "$log_file"
  status="${PIPESTATUS[0]}"      # ← el código del COMANDO, no el de tee
  set -e
  ...
}
```

`${PIPESTATUS[0]}` es la clave: en `comando | tee`, `$?` sería el de `tee` (siempre 0).
`PIPESTATUS` es un array con el estado de **cada** etapa de la tubería.

`set +e` / `set -e` alrededor permite capturar el fallo y reportarlo con contexto en vez de
morir en seco.

### Equivalente manual

`deploy-all.sh` no tiene equivalente en el Portal: **es** el valor añadido. A mano
ejecutarías los scripts de Semana 1 y Semana 2 en orden, comprobando cada uno.

---

## 6. Semana 1 — infraestructura base

### 6.1 · `provision-storage.sh`

**Objetivo:** una cuenta de Storage endurecida con 4 contenedores y 2 colas.

**Propiedades de seguridad de la plantilla ARM:**

```json
"minimumTlsVersion":       "TLS1_2",
"supportsHttpsTrafficOnly": true,
"allowBlobPublicAccess":    false,
"publicNetworkAccess":      "Disabled",
"networkAcls": { "defaultAction": "Deny", "bypass": "AzureServices" }
```

| Propiedad | Qué evita |
|---|---|
| `minimumTlsVersion: TLS1_2` | Clientes con TLS antiguo y vulnerable |
| `supportsHttpsTrafficOnly` | HTTP en claro |
| `allowBlobPublicAccess: false` | Contenedores anónimos — la fuga clásica de datos |
| `publicNetworkAccess: Disabled` | Todo el data plane desde internet |
| `networkAcls.defaultAction: Deny` | Denegar por defecto; permitir es la excepción |

El bucle `copy` de ARM crea los contenedores sin repetir el bloque:

```json
"name": "[concat(parameters('storageAccountName'), '/default/', variables('containers')[copyIndex('containersCopy')])]",
"copy": { "name": "containersCopy", "count": "[length(variables('containers'))]" }
```

**Idempotencia con validación.** Si la cuenta ya existe, no la recrea: **comprueba que
cumple**. Si alguien relajó una propiedad a mano, el script lo detecta:

```bash
[ "$pub_net" = "Disabled" ] || { log_error "publicNetworkAccess debe ser Disabled (actual: $pub_net)"; return 1; }
```

**Cómo lo harías a mano:**

```bash
az group create --name rg-centinela-week1 --location centralus

az storage account create \
  --name centsta84cc6 --resource-group rg-centinela-week1 \
  --location centralus --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --https-only true \
  --allow-blob-public-access false --public-network-access Disabled \
  --default-action Deny --bypass AzureServices

# Contenedores y colas: con acceso público deshabilitado, el data plane no
# es alcanzable desde fuera, así que se crean por CONTROL PLANE:
for c in raw-transactions-production raw-transactions-staging \
         verification-documents-production verification-documents-staging; do
  az storage account blob-service-properties update … # (o vía ARM/Portal)
done
```

> **Detalle importante:** `az storage container create` es **data plane**. Con
> `publicNetworkAccess=Disabled` falla desde fuera de la VNet. Por eso el script los crea
> dentro de la plantilla ARM (control plane), que siempre funciona.

**En el Portal:** *Storage accounts → Create* → pestaña **Advanced** (TLS, HTTPS, blob
público) → pestaña **Networking** → *Disable public access*.

---

### 6.2 · `provision-app-service.sh`

**Objetivo:** plan + Web App + slot `staging`, ambos con Managed Identity y configuración
aislada por ambiente.

**El concepto clave — slot settings (sticky):**

```json
"appSettings": [ common_settings, prod_env_settings ]
```

Un *deployment slot* es una copia de la app con su propia URL. Al hacer **swap**, los
contenidos se intercambian. Los ajustes marcados como **sticky** (`slotSetting: true`)
**no viajan en el swap**: se quedan pegados al slot.

Por eso `CENTINELA_ENVIRONMENT` es sticky. Si no lo fuera, tras un swap producción se
creería staging y escribiría en los contenedores equivocados.

**Ajuste crítico añadido:**

```bash
"WEBSITES_CONTAINER_START_TIME_LIMIT=600"
```

Esta app tarda ~205 s en arrancar (Spring Boot + Flyway + primera conexión a PostgreSQL).
El límite por defecto de Azure son **230 s**: con 25 s de margen, el despliegue fallaba de
forma intermitente con `ContainerStartupFailure` aunque la app estuviera sana.

**Cómo lo harías a mano:**

```bash
az appservice plan create --name cent-asp-week1 --resource-group rg-centinela-week1 \
  --sku S1 --is-linux --number-of-workers 1

az webapp create --name cent-app-a84cc6 --resource-group rg-centinela-week1 \
  --plan cent-asp-week1 --runtime "JAVA:21-java21"

az webapp deployment slot create --name cent-app-a84cc6 \
  --resource-group rg-centinela-week1 --slot staging

# Managed Identity (system-assigned) en ambos
az webapp identity assign --name cent-app-a84cc6 --resource-group rg-centinela-week1
az webapp identity assign --name cent-app-a84cc6 --resource-group rg-centinela-week1 --slot staging

# Ajustes sticky
az webapp config appsettings set --name cent-app-a84cc6 --resource-group rg-centinela-week1 \
  --slot-settings CENTINELA_ENVIRONMENT=production SPRING_PROFILES_ACTIVE=production
```

> `--slot-settings` marca sticky; `--settings` no. Es la diferencia entre un swap correcto
> y uno que rompe producción.

---

### 6.3 · `provision-network.sh`

**Objetivo:** VNet con dos subredes de propósito distinto, zonas DNS privadas y VNet
Integration.

```json
{ "name": "snet-app-integration",
  "properties": {
    "addressPrefix": "10.10.1.0/24",
    "delegations": [ { "properties": { "serviceName": "Microsoft.Web/serverFarms" } } ],
    "privateEndpointNetworkPolicies": "Enabled"
  } },
{ "name": "snet-private-endpoints",
  "properties": {
    "addressPrefix": "10.10.2.0/24",
    "privateEndpointNetworkPolicies": "Disabled"
  } }
```

Las dos subredes existen porque tienen requisitos **incompatibles**:

| | `snet-app-integration` | `snet-private-endpoints` |
|---|---|---|
| Para | Salida de App Service | Private Endpoints |
| Delegación | `Microsoft.Web/serverFarms` | ninguna |
| `privateEndpointNetworkPolicies` | `Enabled` | **`Disabled`** |

**`privateEndpointNetworkPolicies: Disabled`** es obligatorio en la subred de PEs: si está
habilitado, Azure aplica NSG/UDR a la NIC del Private Endpoint y **la creación falla**. Una
subred delegada a App Service, además, no admite Private Endpoints.

**A mano:**

```bash
az network vnet create --name cent-vnet-week1 --resource-group rg-centinela-week1 \
  --address-prefix 10.10.0.0/16 \
  --subnet-name snet-app-integration --subnet-prefix 10.10.1.0/24

az network vnet subnet update --vnet-name cent-vnet-week1 \
  --resource-group rg-centinela-week1 --name snet-app-integration \
  --delegations Microsoft.Web/serverFarms

az network vnet subnet create --vnet-name cent-vnet-week1 \
  --resource-group rg-centinela-week1 --name snet-private-endpoints \
  --address-prefix 10.10.2.0/24 --disable-private-endpoint-network-policies true

# Zona DNS privada + vínculo a la VNet
az network private-dns zone create --name privatelink.blob.core.windows.net \
  --resource-group rg-centinela-week1
az network private-dns link vnet create --zone-name privatelink.blob.core.windows.net \
  --resource-group rg-centinela-week1 --name cent-vnet-week1-blob-link \
  --virtual-network cent-vnet-week1 --registration-enabled false

# VNet Integration de la Web App (salida)
az webapp vnet-integration add --name cent-app-a84cc6 \
  --resource-group rg-centinela-week1 --vnet cent-vnet-week1 --subnet snet-app-integration
```

> `--registration-enabled false`: la zona **resuelve** nombres pero no registra
> automáticamente las VMs de la VNet. Para privatelink es siempre `false`.

---

### 6.4 · `configure-private-endpoints.sh`

**Objetivo:** Private Endpoints de Blob y Queue, con su registro DNS.

Un PE se crea en **tres pasos**, y saltarse el tercero es el error clásico:

```bash
# 1. El Private Endpoint (la NIC con IP privada)
az network private-endpoint create \
  --name centsta84cc6-blob-pe --resource-group rg-centinela-week1 \
  --vnet-name cent-vnet-week1 --subnet snet-private-endpoints \
  --private-connection-resource-id "$STORAGE_ID" \
  --group-id blob --connection-name centsta84cc6-blob-pe-plsc

# 2. La zona DNS privada, vinculada a la VNet   (ver 6.3)

# 3. El DNS zone group: publica el registro A ← SIN ESTO NO RESUELVE
az network private-endpoint dns-zone-group create \
  --resource-group rg-centinela-week1 --endpoint-name centsta84cc6-blob-pe \
  --name default --private-dns-zone privatelink.blob.core.windows.net --zone-name blob
```

**`--group-id` es el subrecurso**, y **cada uno necesita su propio PE y su propia zona**:

| `--group-id` | Zona DNS | Para qué |
|---|---|---|
| `blob` | `privatelink.blob.core.windows.net` | Contenedores |
| `queue` | `privatelink.queue.core.windows.net` | Colas |
| `table` | `privatelink.table.core.windows.net` | Estado del host de Functions |
| `file` | `privatelink.file.core.windows.net` | **Recurso compartido que monta el host de Functions** |

> Olvidar el de `file` fue el bug que dejó la Function App en 503 permanente: el host monta
> Azure Files como su sistema de archivos y sin ese camino el contenedor se termina con
> `Container failed to remount volume`.

**Cómo verificar que funciona** (desde dentro de la VNet):

```bash
nslookup centsta84cc6.blob.core.windows.net
# Debe devolver 10.10.2.x (privada), no una IP pública.
```

---

### 6.5 · `provision-entra-app.sh`

**Objetivo:** App Registration con 4 app roles y su Service Principal.

**App Registration vs Service Principal** — la confusión más común de Entra ID:

- **App Registration** = la *definición* global de la aplicación (su identidad, sus roles).
- **Service Principal** = la *instancia* de esa app **en un tenant concreto**, sobre la que
  se hacen las asignaciones.

Una App Registration puede tener un SP en varios tenants. Sin SP, no puedes asignar
usuarios a los roles.

**GUIDs deterministas para los roles:**

```bash
approle_guid() {
  local name="$1" h
  h="$(printf 'centinela-approle-%s' "$name" | sha1sum | tr -d ' -' | cut -c1-32)"
  printf '%s-%s-5%s-%s%s-%s' "${h:0:8}" "${h:8:4}" "${h:13:3}" "9" "${h:18:3}" "${h:20:12}"
}
```

Cada app role necesita un GUID. Si se generara al azar, cada ejecución crearía roles
nuevos y duplicados. Derivándolo del nombre por hash, `ANALYST` obtiene **siempre** el
mismo GUID y la operación es idempotente. El `5` y el `9` incrustados fijan la versión y
la variante para que sea un UUID sintácticamente válido.

**Los 4 roles y `allowedMemberTypes`:**

| Rol | Tipo | Por qué |
|---|---|---|
| `SERVICE` | `Application` | Corre desatendido, sin usuario detrás |
| `ANALYST` | `User` | Persona que carga documentos |
| `ADMINISTRATOR` | `User` | Persona |
| `AUDITOR` | `User` | Persona, solo lectura |

**A mano:**

```bash
az ad app create --display-name cent-api-week1 \
  --sign-in-audience AzureADMyOrg --app-roles @roles.json

APP_ID=$(az ad app list --display-name cent-api-week1 --query "[0].appId" -o tsv)
az ad app update --id "$APP_ID" --identifier-uris "api://$APP_ID"
az ad sp create --id "$APP_ID"
```

`identifierUri` (`api://<appId>`) es el **audience** que la API valida en el token JWT. Un
token emitido para otra audiencia debe rechazarse.

**En el Portal:** *Microsoft Entra ID → App registrations → New registration*, luego *App
roles* y *Expose an API*.

---

### 6.6 · `assign-rbac.sh`

**Objetivo:** mínimo privilegio real, acotado a contenedores concretos.

```bash
PROD_CONTAINERS=("raw-transactions-production" "verification-documents-production")

for c in "${PROD_CONTAINERS[@]}"; do
  scope="${sa_id}/blobServices/default/containers/${c}"
  assign_role_scope "$prod_pid" "ServicePrincipal" "Storage Blob Data Contributor" "$scope"
done
```

El ámbito **no** es la cuenta de Storage: es **cada contenedor**. Producción no puede leer
los contenedores de staging aunque quisiera.

**El guard de regla dura:**

```bash
FORBIDDEN_ROLES=("Owner" "Contributor" "User Access Administrator")

assert_not_forbidden_role() {
  local role="$1" f
  for f in "${FORBIDDEN_ROLES[@]}"; do
    if [ "$role" = "$f" ]; then
      die "REGLA DURA violada: intento de asignar rol prohibido '$role'."
    fi
  done
  return 0     # ← imprescindible con set -e
}
```

Convierte una política de seguridad en **código que la impide**. Si alguien edita el script
para asignar `Contributor`, el guard aborta.

> Ese `return 0` explícito es el bug original: sin él, la última comparación falsa devolvía
> 1 y `set -e` mataba el script en silencio.

**Idempotencia:** consulta si el rol ya está antes de asignarlo, para no acumular
asignaciones duplicadas.

**A mano:**

```bash
PROD_PID=$(az webapp identity show --name cent-app-a84cc6 \
  --resource-group rg-centinela-week1 --query principalId -o tsv)

SA_ID=$(az storage account show --name centsta84cc6 \
  --resource-group rg-centinela-week1 --query id -o tsv)

az role assignment create \
  --assignee-object-id "$PROD_PID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$SA_ID/blobServices/default/containers/raw-transactions-production"
```

> Usa `--assignee-object-id` + `--assignee-principal-type`, no `--assignee`. Con
> `--assignee`, `az` intenta resolver el principal en Entra y falla si la Managed Identity
> aún no se ha propagado.

---

## 7. Semana 2 — datos, mensajería y scoring

### 7.1 · `provision-cosmos.sh`

**Objetivo:** cuenta Cosmos (API MongoDB) privada, con base y colección.

```bash
az cosmosdb create --name cent-cosmos-a84cc6 --resource-group rg-centinela-week1 \
  --kind MongoDB --server-version 4.2 \
  --default-consistency-level Session \
  --enable-free-tier true \
  --public-network-access Disabled
```

- **`Session`**: consistencia por defecto. Garantiza *read-your-writes* dentro de una
  sesión, con mucha menos latencia y coste que `Strong`.
- **`--enable-free-tier true`**: 1000 RU/s y 25 GB gratis. **Solo una cuenta free por
  suscripción**; si ya existe otra, la creación falla.

**TTL en la API Mongo:**

```bash
idx="$(printf '[{"key":{"keys":["_id"]}},{"key":{"keys":["_ts"]},"options":{"expireAfterSeconds":%s}}]' "$TTL_SECONDS")"
az cosmosdb mongodb collection create … --shard accountId --idx "$idx"
```

En Cosmos DB for MongoDB **el TTL no es un flag**: se declara como **índice sobre `_ts`**
(la marca de tiempo interna) con `expireAfterSeconds`. Hay que incluir también el índice
obligatorio de `_id`.

**`--shard accountId`** define la clave de partición, y es **inmutable tras la primera
escritura**. Elegirla mal obliga a recrear la colección.

---

### 7.2 · `provision-postgres.sh`

**Objetivo:** PostgreSQL Flexible Server privado, con autenticación Entra exclusiva.

**El truco de la contraseña efímera:**

```bash
pwd="$(generate_ephemeral_password)"      # aleatoria, en memoria
az postgres flexible-server create … --admin-password "$pwd" …
unset pwd
# ...después:
az postgres flexible-server update … --password-auth Disabled --public-access Disabled
```

`create` **exige** un admin nativo con contraseña. Para no meter ningún secreto en el
repositorio, se genera una aleatoria, se usa solo para crear, y acto seguido se
**deshabilita la autenticación por contraseña**: queda inservible. Nunca se imprime ni se
persiste.

**Endurecimiento en dos tiempos:**

```
create --public-access None   →  modo de red "público sin reglas de firewall"
                                  (habilita añadir Private Endpoint después)
update --public-access Disabled → cierra el plano público
+ Private Endpoint             → único camino de entrada
```

> Ojo con los flags: en `create` es `--public-access None`; en `update` es
> `--public-access Disabled`. **No existe `--public-network-access`** — ese es solo el
> nombre de la propiedad al leerla con `--query 'network.publicNetworkAccess'`.

**A mano:**

```bash
az postgres flexible-server create --name cent-pg-a84cc6 -g rg-centinela-week1 \
  --tier Burstable --sku-name Standard_B1ms --storage-size 32 --version 16 \
  --public-access None --microsoft-entra-auth Enabled \
  --admin-user centinelaadmin --admin-password "$(openssl rand -base64 32)" --yes

OID=$(az ad signed-in-user show --query id -o tsv)
az postgres flexible-server microsoft-entra-admin create \
  --server-name cent-pg-a84cc6 -g rg-centinela-week1 \
  --display-name "$(az ad signed-in-user show --query userPrincipalName -o tsv)" \
  --object-id "$OID" --type User

az postgres flexible-server update --name cent-pg-a84cc6 -g rg-centinela-week1 \
  --password-auth Disabled --public-access Disabled
```

> `ad-admin` fue **renombrado** a `microsoft-entra-admin`, y `--active-directory-auth` a
> `--microsoft-entra-auth`. Los nombres viejos ya no existen en el CLI 2.88.

---

### 7.3 · `provision-keyvault.sh`

**Objetivo:** Key Vault con RBAC, que guarda la cadena de conexión de Cosmos.

**Modelo RBAC en vez de access policies:**

```bash
az keyvault create … --enable-rbac-authorization true --enable-purge-protection true
```

Key Vault tiene dos modelos de autorización. `--enable-rbac-authorization true` usa **Azure
RBAC** (roles como `Key Vault Secrets User`), coherente con el resto del proyecto, en vez
del sistema antiguo de *access policies*, propio de Key Vault.

**El permiso temporal del deployer:**

```bash
grant_deployer_officer "$vault_id"          # se concede Secrets Officer
trap revoke_temporary_deployer_officer EXIT  # se revoca SIEMPRE al salir
store_cosmos_secret …
```

Escribir un secreto requiere `Key Vault Secrets Officer`. En vez de dejarlo puesto, el
script se lo concede, escribe, y lo **revoca con un `trap EXIT`** que se ejecuta también si
falla. Privilegio elevado solo durante los segundos que dura la operación.

**Recuperación tras destruir** — sutil y crítico:

```bash
if az keyvault show-deleted --name "$vault" --location "$LOCATION" >/dev/null 2>&1; then
  az keyvault recover --name "$vault" --location "$LOCATION" --resource-group "$rg"
fi
```

Con *purge protection*, borrar el Resource Group deja el vault **soft-deleted y no
purgable**: su nombre queda reservado durante todo el periodo de retención. Sin este
bloque, **el segundo despliegue con el mismo `NAME_PREFIX` fallaría para siempre** con
*"vault name is already in use"*. Recuperarlo es la única salida.

**Referencias a Key Vault en app settings:**

```
@Microsoft.KeyVault(SecretUri=https://cent-kv-a84cc6.vault.azure.net/secrets/cosmos-mongo-connection-string/)
```

La app **no recibe el valor**: recibe una referencia. App Service la resuelve en el
arranque usando la Managed Identity. El secreto nunca aparece en la configuración.

---

### 7.4 · `provision-eventgrid.sh`

**Objetivo:** el tópico de eventos y las colas de casos, con su RBAC.

```
Web App  --(publica evento)-->  Event Grid Topic
                                       |
                                       v  (suscripción)
                              Function ScoreTransaction
                                       |
                                       v  (encola caso)
                              Storage Queue flagged-cases-*
```

**Por qué la suscripción NO se crea aquí:**

```bash
log_info "NOTA: la SUSCRIPCION del topico NO se crea aqui; la conecta la Function en ISS-S2-007."
```

Sería una **dependencia circular**: la suscripción necesita que la Function exista, y la
Function necesita el tópico para configurarse. Se rompe creando el tópico primero y la
suscripción al final, desde el script de la Function.

**Roles de mensajería:**

| Principal | Rol | Para |
|---|---|---|
| Web App | `EventGrid Data Sender` | Publicar eventos en el tópico |
| Function | `Storage Queue Data Message Sender` | Encolar casos marcados |
| Web App | `Storage Queue Data Message Processor` | Consumir y borrar mensajes |

---

### 7.5 · `configure-function-host-storage.sh`

**Objetivo:** completar la ruta privada que el host de Functions necesita.

```bash
readonly HOST_SUBRESOURCES=(table file)
```

Además de blob y queue (Semana 1), el host de Azure Functions necesita:

- **`table`** — donde guarda su estado interno con acceso por identidad.
- **`file`** — **monta un recurso compartido de Azure Files como su sistema de archivos**.

Sin el de `file`, con el Storage en `publicNetworkAccess=Disabled`, el montaje falla y el
contenedor se termina con `Container failed to remount volume. Terminate.` La Function App
devuelve **503 indefinidamente** mientras ARM la reporta `Running` — un fallo
desconcertante si no conoces esta dependencia.

---

### 7.6 · `configure-postgres-managed-identity.sh`

**Objetivo:** crear en PostgreSQL los *principals* que corresponden a las Managed
Identities, para que la app se conecte **sin contraseña**.

Es el único paso que necesita **data plane** privado: hay que ejecutar SQL.

**Autenticación con token en vez de contraseña:**

```bash
token="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
PGPASSWORD="$token" psql "host=$host … user=$admin sslmode=require" -c "…"
```

Se pide a Entra un token para el *resource type* `oss-rdbms` y **se pasa como si fuera la
contraseña**. PostgreSQL lo valida contra Entra. Es la conexión *passwordless*.

**Crear el principal de la Managed Identity:**

```sql
SELECT pg_catalog.pgaadauth_create_principal_with_oid(
    :'role_name', :'object_id', 'service', false, false)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role_name');
```

`pgaadauth_create_principal_with_oid` es una función que **añade la extensión Entra de
Azure**: vincula un rol de PostgreSQL con el `objectId` de la Managed Identity. El
`WHERE NOT EXISTS` lo hace idempotente.

**La ventana temporal** — cómo funciona el mecanismo completo:

```bash
if probe_connectivity "$host" "$admin" "$token"; then
  # Ruta privada disponible: nada más que hacer.
else
  trap close_deployer_window EXIT INT TERM   # ← armado ANTES de abrir
  open_deployer_window "$server"             # público + regla para 1 IP
  # ...bootstrap...
fi                                            # el trap cierra al salir
```

El `trap` se arma **antes** de abrir nada, de modo que un fallo o un `Ctrl-C` posterior
cierre igualmente la ventana.

> **Límite real:** ningún `trap` intercepta `SIGKILL` ni un corte de energía. Si la corrida
> muere así, la ventana **queda abierta**. Por eso el script llama a
> `close_leaked_window()` al arrancar: detecta una ventana huérfana de una ejecución
> anterior y la cierra antes de seguir.

**Cadena JDBC passwordless:**

```
jdbc:postgresql://cent-pg-a84cc6.postgres.database.azure.com:5432/centinela
  ?sslmode=require
  &authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin
```

Ese `authenticationPluginClassName` hace que el driver JDBC pida el token a la Managed
Identity en cada conexión. **No hay contraseña en ninguna parte.**

---

### 7.7 · `deploy-application.sh`

**Objetivo:** publicar el artefacto y **verificar que la app responde**.

```bash
az webapp deploy … --type jar --src-path "$artifact" --async false --track-status false
wait_until_healthy "$app_name" "$TARGET_SLOT"
```

**`--track-status false` es deliberado.** Por defecto, `az webapp deploy` vigila el arranque
del contenedor y se rinde con *"site failed to start within 10 mins"*. Esta app tarda
~220 s en pasar la sonda, así que ese rastreo producía **falsos negativos**: reportaba
fallo sobre despliegues que sí habían funcionado.

Se publica el artefacto y la salud se verifica con criterio propio:

```bash
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 \
          "https://${host}/actuator/health" 2>/dev/null || true)"
```

> El `|| true` es **obligatorio**: mientras la app arranca, `curl` termina con código 28
> (timeout) o 7 (sin conexión) y, bajo `set -e`, esa sustitución de comandos abortaría el
> despliegue justo cuando hay que seguir esperando.

**Lección general:** el criterio de éxito de un despliegue no es *"`az` devolvió 0"*, es
**"la aplicación responde"**.

---

### 7.8 · `deploy-scoring-function.sh`

**Objetivo:** Function App integrada en la VNet, con RBAC, código y suscripción a Event
Grid.

**Red en la creación, no después:**

```bash
az functionapp create … --vnet "$vnet" --subnet "$SUBNET_APP" …
```

Con el Storage en `publicNetworkAccess=Disabled`, `az` **rechaza** crear la Function App
sin declarar red: el runtime no podría alcanzar su propia cuenta de Storage para arrancar.
Integrarla después es demasiado tarde.

**Ajuste que desbloquea Event Grid:**

```bash
"AzureWebJobsSecretStorageType=files"
```

Por defecto el host guarda sus claves en el contenedor `azure-webjobs-secrets` del Storage.
Con acceso público deshabilitado y conexión por identidad, ese almacén **no llega a
inicializarse**: `az functionapp keys list` devuelve `Bad Request` y Event Grid falla al
validar el endpoint con `Webhook endpoint validation failed … NotFound`, porque no puede
obtener la clave de sistema `eventgrid_extension`. Guardarlas en el sistema de archivos del
host (montado por Azure Files) elimina la dependencia.

**Despliegue por zip, no con el plugin de Maven:**

```bash
"$jar_bin" cfM "$zip_path" -C "$staging" .
az functionapp deployment source config-zip --name "$app" … --src "$zip_path"
```

`mvn azure-functions:deploy` hace *"create or update"* del recurso con **su propia**
configuración (plan de consumo por defecto), choca con la Function App ya creada sobre el
plan S1 con VNet, y Azure responde `400` con cuerpo vacío. Separando responsabilidades —`az`
provisiona, el zip publica el código— desaparece el conflicto.

> Se usa `jar cfM` del JDK (ya requerido) porque `zip` no existe en Git Bash sobre Windows.
> La `M` evita generar `MANIFEST.MF`: Azure espera un zip plano.

**La suscripción de Event Grid:**

```bash
az eventgrid event-subscription create \
  --name score-transaction-v1 --source-resource-id "$topic_id" \
  --endpoint-type azurefunction --endpoint "$function_id"
```

`--endpoint-type azurefunction` evita el *handshake* de validación de webhook genérico:
Event Grid resuelve la función por su ID de recurso
(`<functionapp-id>/functions/ScoreTransaction`) y obtiene su clave de sistema.

---

## 8. `destroy-week1.sh` — destrucción segura

```bash
printf 'Para confirmar, teclea EXACTAMENTE el nombre del Resource Group: ' >&2
read -r typed
[ "$typed" = "$RESOURCE_GROUP" ] || die "El nombre no coincide. Abortado sin borrar."
```

Confirmación por **escritura del nombre exacto**, no un `y/n`. Un `y` se teclea por inercia;
el nombre del grupo obliga a mirar qué vas a borrar.

Borra **dos cosas**, porque viven en sitios distintos:

1. **El Resource Group** — se lleva todos los recursos de Azure.
2. **La App Registration** — vive en **Entra ID**, *fuera* del Resource Group, y
   sobreviviría al borrado.

`--wait` **verifica** que ambos desaparecen, en vez de confiar en que la orden se aceptó.

**A mano:**

```bash
az group delete --name rg-centinela-week1 --yes
APP_ID=$(az ad app list --display-name cent-api-week1 --query "[0].appId" -o tsv)
az ad app delete --id "$APP_ID"

# Verificar
az group exists --name rg-centinela-week1          # false
az ad app list --display-name cent-api-week1 --query "length(@)" -o tsv   # 0
```

---

## 9. Patrones de diseño que se repiten

Reconocerlos te permite leer cualquiera de estos scripts sin releer esta guía.

### 9.1 · Nombres deterministas en vez de estado

```bash
compute_storage_account_name() {
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%sst%s' "$prefix" "$hash"
}
```

Cada script **recalcula** los nombres en vez de leerlos de un archivo de estado. No hay
`terraform.tfstate` que perder ni desincronizar: los mismos parámetros producen siempre los
mismos nombres.

### 9.2 · Idempotencia: comprobar, actuar, verificar

```bash
if <ya existe y cumple>; then
  log_info "Ya existe."
else
  <crear>
fi
<verificar contra Azure>
```

Reejecutar converge al mismo estado. Es lo que permite decir *"corrige la causa y vuelve a
lanzar el mismo comando"*.

### 9.3 · Verificar el resultado, no el código de salida

**El patrón más importante de todos.** Seis de los defectos críticos corregidos venían de
confiar en el código de salida de `az`:

- `dns-zone-group show` devuelve 0 con `{}` cuando **no** existe.
- `microsoft-entra-admin create` aplica el cambio y **después** devuelve `InternalServerError`.
- `az webapp deploy` se rinde antes de que la app arranque.

La forma correcta:

```bash
# ❌ Confía en el código de salida
if az network private-endpoint dns-zone-group show …; then …

# ✅ Verifica el contenido
n="$(az network private-endpoint dns-zone-group list … --query 'length(@)' -o tsv)"
[ "${n:-0}" -ge 1 ]

# ✅ Si crear falla, comprueba si surtió efecto igualmente
if with_retry 3 az … create …; then return 0; fi
if entra_admin_exists …; then
  log_warn "La creacion reporto error, pero el admin SI quedo configurado."
  return 0
fi
```

### 9.4 · `trap` para revertir cambios temporales

```bash
trap close_deployer_window EXIT INT TERM
open_deployer_window "$server"
```

Cualquier elevación temporal de privilegio o apertura de red **se arma con un `trap` antes
de aplicarse**, para que se revierta también si el script falla.

Se usa en dos sitios: la ventana de PostgreSQL y el `Secrets Officer` temporal del Key
Vault.

### 9.5 · Esperar lo asíncrono

Azure devuelve éxito antes de que el efecto sea observable. Los registros DNS de un PE, los
recursos hijo de un deployment ARM y las reglas de firewall tardan segundos o minutos.

```bash
retry_until 8 private_dns_has_a_records "$zone" "$rg" \
  || die "La zona '$zone' no tiene registros A tras esperar su publicacion."
```

Tiempos medidos en este proyecto:

| Operación | Tiempo real |
|---|---|
| Arranque de la Web App (producción) | ~220 s |
| Arranque de la Web App (staging) | ~365 s |
| Propagación del firewall de PostgreSQL | 20 s – 1 min |
| Registro A de un Private Endpoint | segundos |

---

## Para seguir aprendiendo

Lee los scripts **en el orden de dependencias**, que es el orden de esta guía. Cada uno
declara su alcance estricto en la cabecera y solo hace eso.

Un ejercicio útil: coge `provision-storage.sh`, ejecútalo con `--validate-only`, y luego
reproduce lo mismo a mano con los comandos `az` de la sección 6.1. Comparar el resultado
con `az storage account show` te fija los conceptos mucho mejor que leer.

- **Guía de despliegue:** [DESPLIEGUE.md](DESPLIEGUE.md)
- **Errores corregidos y sus causas raíz:** [docs/4_Infraestructura_y_Despliegue/6_Informe_Errores_Corregidos.md](docs/4_Infraestructura_y_Despliegue/6_Informe_Errores_Corregidos.md)
