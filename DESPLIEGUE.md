# Despliegue de Centinela — guía de un solo comando

Levanta **toda** la infraestructura de Semana 1 + Semana 2 en Azure desde una máquina
limpia. Todos los comandos son copiables tal cual.

> **Aviso de costos.** El entorno consume ≈ **USD 4,5 por día encendido**. Al terminar
> cada sesión, ejecuta la [destrucción](#5-destruir-todo-al-terminar). Recrearlo cuesta
> ~40 min de espera y centavos.

---

## 1. Requisitos de la máquina

| Herramienta | Versión | Comprobar con |
|---|---|---|
| Azure CLI | 2.88+ | `az version` |
| Java (JDK) | **21+** | `java -version` |
| Maven | 3.9+ | `mvn -version` |
| Git | cualquiera | `git --version` |
| `psql` | 14+ | `psql --version` |
| `jq` | 1.6+ | `jq --version` |
| Bash | Git Bash en Windows | `bash --version` |

### Instalación de lo que falte

```bash
# Windows (PowerShell)
winget install -e --id Microsoft.AzureCLI
winget install -e --id EclipseAdoptium.Temurin.21.JDK
winget install -e --id Apache.Maven
winget install -e --id PostgreSQL.PostgreSQL.17
winget install -e --id jqlang.jq

# Debian / Ubuntu / Azure Cloud Shell
sudo apt-get update && sudo apt-get install -y postgresql-client jq maven
```

**En Windows no hace falta tocar el `PATH`.** Los instaladores de PostgreSQL y winget no
añaden sus binarios al `PATH`, así que `psql --version` y `jq --version` fallan aunque
estén instalados. Los scripts lo resuelven solos: `require_cmd` busca en las rutas
estándar (PostgreSQL, WinGet Links/Packages, Chocolatey, Scoop) antes de darse por
vencido.

`JAVA_HOME` **sí** debe apuntar a un JDK 21: Maven usa `JAVA_HOME`, no el `java` del
`PATH`, y el preflight valida ese mismo JDK.

```bash
echo "$JAVA_HOME"          # debe existir y ser un JDK 21
"$JAVA_HOME/bin/java" -version
```

### Permisos necesarios en Azure

- **Contributor** sobre la suscripción o el Resource Group.
- **User Access Administrator** u **Owner** sobre el RG (para crear *role assignments*).
- **Application Administrator** en Entra ID (para la App Registration).

---

## 2. Preparar el repositorio y los parámetros

```bash
git clone https://github.com/Centinela-App/Centinela.git
cd Centinela
cp .env.example .env
```

Edita `.env` con tus valores:

```bash
SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
LOCATION="centralus"
RESOURCE_GROUP="rg-centinela-week1"
NAME_PREFIX="cent"           # 3-11 minúsculas/números
APP_SERVICE_SKU="S1"
```

Los nombres de recurso son **deterministas**: se derivan de un hash de
`NAME_PREFIX|SUBSCRIPTION_ID|RESOURCE_GROUP`. Con los mismos parámetros obtienes
siempre los mismos nombres, en cualquier máquina.

---

## 3. Sesión de Azure

```bash
az login
az account set --subscription "$(grep -E '^SUBSCRIPTION_ID=' .env | cut -d= -f2 | tr -d '\"')"
az account show --query "{sub:name, id:id, user:user.name}" -o table
```

---

## 4. Desplegar

### Ensayo en seco (no crea nada, no cuesta nada)

Valida herramientas, sesión, parámetros, región y disponibilidad del SKU:

```bash
bash scripts/deploy-all.sh --validate-only
```

### Despliegue completo — **el comando único**

```bash
bash scripts/deploy-all.sh --yes
```

Tarda **40-60 minutos**. Levanta, en orden de dependencias:

| Fase | Contenido |
|---|---|
| 0 · Preflight | herramientas, sesión, parámetros, región, SKU |
| 1 · Semana 1 | Storage + contenedores/colas, App Service + slot staging, VNet + subredes + DNS privado, Private Endpoints, App Registration (4 app roles), RBAC de mínimo privilegio |
| 2 · Semana 2 | Cosmos (Mongo), PostgreSQL privado, Key Vault, Event Grid + colas, Storage del host de Functions, principales de BD, build Maven, despliegue en producción y staging, Function de scoring, suscripción de Event Grid |

Con validadores incluidos (recomendado la primera vez):

```bash
bash scripts/deploy-all.sh --yes --with-tests
```

### Ver el avance en vivo

En **otra** terminal, dentro del proyecto:

```bash
bash scripts/watch-deploy.sh
```

```
[###################.......................]  47%   8/17  S2 PostgreSQL privado  (3s)
```

Muestra el paso actual y **cuánto lleva** — ese cronómetro distingue "trabajando" de
"colgado" cuando Cosmos o Maven pasan minutos en silencio. Es de solo lectura: cortarlo
con `Ctrl-C` no afecta al despliegue.

### Opciones

| Opción | Efecto |
|---|---|
| `--validate-only` | Solo preflight y planes en seco. No crea nada. |
| `--skip-week1` | Omite la Fase 1 (la base ya existe). |
| `--skip-week2` | Omite la Fase 2. |
| `--with-tests` | Ejecuta los validadores de solo lectura. |
| `--yes` | No pide confirmación antes de crear recursos con costo. |
| `--env-file <ruta>` | Archivo de parámetros alternativo. |

### Si algo falla

El script es **idempotente**: corrige la causa y vuelve a ejecutar el mismo comando. Los
pasos ya completados convergen sin duplicar recursos. Cada paso deja su registro en
`deploy-run/<timestamp>/`, y el error indica exactamente qué paso falló y con qué código.

---

## 5. Verificar

```bash
# Semana 1
bash scripts/tests/validate-storage.sh
bash scripts/tests/validate-app-service.sh
bash scripts/tests/validate-network.sh
bash scripts/tests/validate-managed-identity.sh
bash scripts/tests/validate-entra-roles.sh
bash scripts/tests/validate-rbac.sh

# Semana 2
bash scripts/tests/validate-cosmos.sh
bash scripts/tests/validate-postgres.sh
bash scripts/tests/validate-keyvault.sh
bash scripts/tests/validate-eventgrid.sh
```

Comprobación rápida a mano:

```bash
HASH=$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)

# Salud de la aplicación
curl -s -o /dev/null -w '%{http_code}\n' "https://${NAME_PREFIX}-app-${HASH}.azurewebsites.net/actuator/health"
curl -s -o /dev/null -w '%{http_code}\n' "https://${NAME_PREFIX}-app-${HASH}-staging.azurewebsites.net/actuator/health"

# La Function está suscrita al tópico
az eventgrid event-subscription list \
  --source-resource-id "$(az eventgrid topic show -n "${NAME_PREFIX}-egt-${HASH}" -g "$RESOURCE_GROUP" --query id -o tsv)" \
  -o table

# PostgreSQL sigue cerrado al exterior
az postgres flexible-server show -n "${NAME_PREFIX}-pg-${HASH}" -g "$RESOURCE_GROUP" \
  --query 'network.publicNetworkAccess' -o tsv    # esperado: Disabled
```

---

## 6. Destruir todo al terminar

**Hazlo siempre al cerrar la sesión de prácticas.**

```bash
bash scripts/destroy-week1.sh --wait
```

Elimina el Resource Group completo y la App Registration de Entra, y **verifica** que
hayan desaparecido. Con `--yes` no pide confirmación; sin él, exige teclear el nombre
exacto del Resource Group.

```bash
bash scripts/destroy-week1.sh --yes --wait      # sin confirmación interactiva
bash scripts/destroy-week1.sh --keep-entra      # conserva la App Registration
```

Comprobar que no queda nada consumiendo:

```bash
az group exists --name "$RESOURCE_GROUP"        # esperado: false
az ad app list --display-name "${NAME_PREFIX}-api-week1" --query "length(@)" -o tsv   # esperado: 0
```

> **Sobre el Key Vault y el redespliegue.** El vault se crea con *purge protection*, así
> que al borrar el Resource Group queda en estado "borrado" y **su nombre sigue
> reservado**. `provision-keyvault.sh` lo detecta y lo **recupera** automáticamente en el
> siguiente despliegue, así que destruir y volver a desplegar funciona sin intervención.

---

## 7. Nota sobre la conexión a PostgreSQL

El servidor tiene el acceso público deshabilitado y solo entra por Private Endpoint. El
paso que crea los principales de base de datos necesita una conexión `psql` real.

- **Desde un runner en la VNet** (Cloud Shell inyectado, jumpbox o VPN): se conecta por
  la ruta privada y no ocurre nada más.
- **Desde tu portátil**: el script abre una **ventana temporal** de acceso público
  acotada a **tu IP**, ejecuta el bootstrap y la revierte mediante `trap EXIT INT TERM`,
  también si el paso falla o lo interrumpes con `Ctrl-C`. El estado final es idéntico al
  de diseño: `publicNetworkAccess=Disabled`, sin reglas de firewall.

> **Límite real de la reversión automática.** Ningún `trap` puede interceptar `SIGKILL`
> ni un corte de energía. Si la corrida muere de ese modo, **la ventana queda abierta**.
> Por eso el script comprueba al arrancar si hay una ventana huérfana de una corrida
> anterior y la cierra antes de seguir. Si prefieres verificarlo a mano:
>
> ```bash
> az postgres flexible-server show -n "${NAME_PREFIX}-pg-${HASH}" -g "$RESOURCE_GROUP" \
>   --query 'network.publicNetworkAccess' -o tsv    # esperado: Disabled
> ```

La ventana **no debilita la autenticación**: `password-auth` sigue `Disabled`, así que la
única credencial válida durante la ventana es un token de Microsoft Entra ID.

Para prohibir esa ruta (CI con runner dentro de la VNet):

```bash
export CENTINELA_ALLOW_PUBLIC_WINDOW=0    # el script falla en vez de abrir la ventana
```

---

## 8. Referencia de recursos creados

Con `NAME_PREFIX=cent` y el hash `a84cc6`:

| Recurso | Nombre |
|---|---|
| Storage | `centsta84cc6` |
| Web App | `cent-app-a84cc6` (+ slot `staging`) |
| App Service Plan | `cent-asp-week1` |
| VNet | `cent-vnet-week1` |
| Cosmos DB | `cent-cosmos-a84cc6` |
| PostgreSQL | `cent-pg-a84cc6` |
| Key Vault | `cent-kv-a84cc6` |
| Event Grid | `cent-egt-a84cc6` |
| Function | `cent-scoring-fn-a84cc6` |
| App Registration | `cent-api-week1` |
| Private Endpoints | blob, queue, table, file, mongo, postgres |
