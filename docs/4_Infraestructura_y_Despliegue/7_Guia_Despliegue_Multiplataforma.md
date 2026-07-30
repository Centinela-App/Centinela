# Guía de despliegue multiplataforma + gestión de roles

Guía paso a paso para desplegar Centinela **desde cualquier sistema operativo** y para
**asignar los roles del equipo** sobre el grupo de recursos, por comandos o desde el portal.

Cada paso indica qué hace, qué esperar y cómo saber si salió bien. Los tropiezos que
aparecieron en el despliegue real están marcados con **⚠ Ojo:** — no son teoría, ya ocurrieron.

> **Convenciones de este documento**
> - Grupo de recursos: `rg-centinela-week1` · Región: `eastus2` · Prefijo: `cent`
>   Si tu grupo es otro, cambia la primera variable de cada bloque; todo lo demás se deriva.
> - Todos los scripts son **Bash** e **idempotentes**: reejecutarlos converge sin duplicar.
>   Casi todos aceptan `--validate-only` (muestra el plan, no crea nada).

---

## Parte 0 — Preparar la máquina (según tu sistema operativo)

Necesitas cinco herramientas: **Git**, **Bash**, **Azure CLI**, **Docker**, y **Java 21 +
Maven** (solo si vas a compilar localmente). Y `psql` para el *bootstrap* de PostgreSQL.

### Windows

Los scripts son Bash, así que en Windows necesitas **Git Bash** (incluido con Git para
Windows) o **WSL2**. No funcionan en `cmd` ni en PowerShell.

```powershell
# En PowerShell como administrador, con winget:
winget install Git.Git                      # incluye Git Bash
winget install Microsoft.AzureCLI
winget install Docker.DockerDesktop         # requiere reiniciar
winget install EclipseAdoptium.Temurin.21.JDK
winget install Apache.Maven
winget install PostgreSQL.PostgreSQL.16      # aporta psql
```

Después, **abre "Git Bash"** (no PowerShell) para ejecutar todo lo que sigue. Si `az` no
aparece en Git Bash, añádelo al PATH de esa sesión:

```bash
export PATH="$PATH:/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"
```

> **⚠ Ojo (real):** en este proyecto `az` estaba instalado pero fuera del PATH de Git Bash.
> El `export` de arriba lo resuelve por sesión; para dejarlo fijo, añádelo a `~/.bashrc`.

### macOS

```bash
brew install git azure-cli docker openjdk@21 maven libpq
brew link --force libpq          # expone psql
# Docker Desktop tambien puede instalarse desde docker.com si prefieres la app
```

### Linux (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip postgresql-client openjdk-21-jdk maven
# Azure CLI (script oficial):
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
# Docker:
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # cierra sesion y vuelve a entrar
```

### Verificar (idéntico en los tres sistemas)

```bash
git --version
az version
docker info          # el daemon debe responder (Docker Desktop arrancado en Win/Mac)
java -version        # debe decir 21
mvn -v
psql --version
```

Si los seis responden, la máquina está lista.

---

## Parte 1 — Autenticación y contexto de Azure

```bash
az login             # abre el navegador; inicia sesion con tu cuenta de Azure
az account show      # confirma que la suscripcion activa es la correcta

# Fija la suscripcion explicitamente si tienes varias:
az account set --subscription "44dc85d0-5df9-46bb-a378-6f629c803999"
```

Clona el repositorio y prepara los parámetros:

```bash
git clone https://github.com/Centinela-App/Centinela.git
cd Centinela
cp .env.example .env
```

Edita `.env` con tus valores. Los cinco obligatorios:

```bash
SUBSCRIPTION_ID="44dc85d0-5df9-46bb-a378-6f629c803999"
LOCATION="eastus2"
RESOURCE_GROUP="rg-centinela-week1"
NAME_PREFIX="cent"          # 3-11 minusculas/numeros
APP_SERVICE_SKU="S1"        # no se usa en la topologia de contenedores, pero valida
```

> **⚠ Ojo (real):** `.env` **nunca** se sube al repositorio (lo bloquea `.gitignore` y un
> barrido de secretos en CI). Contiene identificadores, no secretos, pero la regla es estricta.

---

## Parte 2 — Registro de proveedores (una sola vez por suscripción)

Una suscripción nueva no tiene registrados los servicios que nunca ha usado. Regístralos
antes de crear nada, o los `create` fallan con `MissingSubscriptionRegistration` — un error
que **parece de permisos y no lo es**.

```bash
for p in Microsoft.ContainerRegistry Microsoft.App Microsoft.KeyVault \
         Microsoft.EventGrid Microsoft.DocumentDB Microsoft.DBforPostgreSQL \
         Microsoft.OperationalInsights Microsoft.Insights Microsoft.ManagedIdentity; do
  echo "registrando $p..."
  az provider register --namespace "$p" --wait
done
```

Cada `--wait` puede tardar un minuto. Es idempotente: si ya está registrado, no hace nada.

---

## Parte 3 — Despliegue paso a paso

Ejecuta desde la raíz del repositorio, en este orden. Cada script imprime `OK` al terminar y
la mayoría verifica su propio resultado contra Azure (no confía en el código de salida del
comando que crea).

> **Sugerencia:** ejecuta primero cada uno con `--validate-only` para ver el plan sin gastar.

### 3.1 — Red privada

```bash
bash scripts/provision-network-containerapps.sh
```
Crea la VNet, la subred de Private Endpoints, la subred `/23` delegada a Container Apps y las
zonas DNS privadas de Blob y Queue. **La subred de contenedores debe ser `/23`** — es el
mínimo que exige el perfil Consumption.

### 3.2 — Almacenes de datos

```bash
bash scripts/provision-cosmos.sh       # Cosmos for MongoDB + Private Endpoint + indices
bash scripts/provision-postgres.sh     # PostgreSQL Flexible Server privado + respaldo
```
> **⚠ Ojo (real):** la colección de Cosmos se crea con índices sobre `accountId`, `occurredAt`
> y `(accountId, occurredAt)`. Cosmos Mongo **exige** un índice para todo campo de `ORDER BY`;
> sin el de `occurredAt`, el motor moría en su primera consulta real. Ya está en el script.

### 3.3 — Key Vault e identidad de datos

```bash
bash scripts/provision-keyvault.sh                  # secretos + migracion de la cadena Cosmos
bash scripts/provision-containerapps-identity.sh    # id-cent-apps + roles de datos
```

### 3.4 — Mensajería

Necesita el object id de la identidad de datos como publicador y consumidor:

```bash
APPS_PID=$(az identity show -n "id-${NAME_PREFIX}-apps" -g "$RESOURCE_GROUP" --query principalId -o tsv)
bash scripts/provision-eventgrid.sh \
  --publisher-principal "$APPS_PID" \
  --consumer-principal "$APPS_PID" \
  --function-principal "$APPS_PID"
```

### 3.5 — Identidad de la API (Entra ID)

```bash
bash scripts/provision-entra-app.sh
```
Registra la aplicación OAuth2, sus cuatro *app roles* y —clave— fija **tokens v2**.
> **⚠ Ojo (real):** sin `requestedAccessTokenVersion=2`, Entra emite tokens v1 cuyo *issuer*
> es `sts.windows.net`, y la API los rechaza con `401` sin explicar por qué. Además, en v2 la
> audiencia es el appId **pelado** (`<appId>`), no `api://<appId>`. El script ya lo resuelve.

### 3.6 — Bootstrap de PostgreSQL (el paso delicado)

```bash
bash scripts/configure-postgres-managed-identity.sh
```
Crea el principal de base de datos para la identidad de datos. Como PostgreSQL no es alcanzable
desde internet, si ejecutas **fuera de la VNet** el script abre una **ventana temporal de
firewall acotada a tu IP pública** y la revierte con un `trap` al terminar.
> **⚠ Ojo (real):** ningún `trap` intercepta un `SIGKILL` ni un corte de luz. Si la corrida
> muere así, la ventana queda abierta; el propio script detecta y cierra ventanas huérfanas de
> corridas anteriores al arrancar. Requiere `psql` (Parte 0) y sesión interactiva de `az`.

### 3.7 — Registro, entorno y observabilidad

```bash
bash scripts/provision-container-registry.sh   # ACR Basic + AcrPull por Managed Identity
bash scripts/provision-container-apps.sh        # entorno integrado a la VNet
CENTINELA_ALERT_EMAIL="tu-correo@ejemplo.com" \
  bash scripts/provision-observability.sh       # App Insights + alerta con destinatario
```
> **⚠ Ojo (real):** el entorno de Container Apps **no admite integración de red a posteriori**;
> se fija al crearlo. El script lo comprueba y falla con instrucciones si encuentra uno mal
> creado. Y la alerta **exige un destinatario** (`CENTINELA_ALERT_EMAIL`): una alerta sin
> destinatario no avisa a nadie.

### 3.8 — Construir, publicar y desplegar las imágenes

```bash
TAG="$(git rev-parse --short HEAD)"
REG="${NAME_PREFIX}acr.azurecr.io"

docker build -t "$REG/centinela-api:$TAG" .
docker build -t "$REG/centinela-scoring:$TAG" ./scoring-function
az acr login --name "${NAME_PREFIX}acr"
docker push "$REG/centinela-api:$TAG"
docker push "$REG/centinela-scoring:$TAG"

bash scripts/deploy-containers.sh --tag "$TAG"
```
Crea las tres Container Apps: API, motor de scoring y explicador (la última es la imagen de la
API con otros interruptores). El script cablea además la suscripción de Event Grid al motor.
> **⚠ Ojo (real):** las imágenes fijan `file.encoding=UTF-8`. El JRE Alpine arranca en locale
> ASCII, y sin esto las explicaciones con acentos se guardan con *mojibake*. Ya está en el
> Dockerfile.

### 3.9 — Verificar que responde de verdad

```bash
bash scripts/verify/verify-deployment-health.sh
```
Sondea `/actuator/health/readiness` hasta obtener `200`. El arranque en frío ronda los
**220 segundos** (Spring Boot + Flyway + primera conexión por Private Endpoint). Un contenedor
que arranca y muere en bucle **no** se reporta como éxito: el criterio es que la app conteste.

---

## Parte 4 — Prueba de humo y evidencia end-to-end

```bash
# Recorrido completo: siembra historial, lanza una transaccion fraudulenta,
# espera veredicto y explicacion. Imprime el transactionId y el trace-id.
bash scripts/verify/run-e2e-fraud.sh

# Traza individual con tiempos por etapa (usa el transactionId anterior):
bash scripts/verify/verify-trace.sh <transactionId>

# Escalado bajo carga: en una terminal el observador, en otra el generador.
bash scripts/verify/verify-scaling.sh          # terminal 1
bash scripts/verify/generate-load.sh --rate 25 --duration 180   # terminal 2
```

---

## Parte 5 — Apagar al terminar (control de crédito)

```bash
bash scripts/shutdown-daily.sh          # apaga lo que factura por tiempo
bash scripts/shutdown-daily.sh --start  # lo reenciende
```
Apaga PostgreSQL y escala las Container Apps a cero. **Cosmos, Storage y el registro no se
tocan**: facturan por almacenamiento, y apagarlos equivaldría a destruirlos.

---

# Parte 6 — Gestión de roles del equipo (RBAC)

Aquí el detalle completo, por los **dos caminos**: comandos (§6.2) y portal con el recurso ya
corriendo (§6.3). Elige el que prefieras; hacen exactamente lo mismo.

## 6.1 — Conceptos que necesitas antes de tocar nada

**Qué es un rol.** En Azure, "quién puede hacer qué sobre qué" se define con *role
assignments*: la terna **(identidad, rol, alcance)**. Ejemplo: *(Carlos, Owner,
rg-centinela-week1)*.

**Los dos roles que vas a usar:**

| Rol | Puede gestionar recursos | Puede asignar roles a otros |
|---|---|---|
| **Owner** | Sí | **Sí** — es un privilegio fuerte |
| **Contributor** | Sí | No |

**Alcance = grupo de recursos, no suscripción.** Asignar sobre `rg-centinela-week1` acota el
poder de cada persona al perímetro del proyecto. Nunca asignes sobre la suscripción salvo que
haga falta de verdad.

**Los correos Gmail son usuarios invitados (B2B).** Son externos al tenant de la suscripción.
Tres consecuencias:
1. **No existen en el directorio hasta invitarlos.** Asignar un rol a un correo desconocido
   falla; primero se invita.
2. **Su identidad interna no es el correo.** Tras aceptar, su nombre pasa a ser algo como
   `carlosres1995_gmail.com#EXT#@<tenant>.onmicrosoft.com`.
3. **Solo un Owner puede conceder Owner** y traer invitados. Necesitas ese rol para ejecutar
   esta sección.

**El reparto de este proyecto:**

| Miembro | Correo | Rol |
|---|---|---|
| Carlos | `carlosres1995@gmail.com` | **Owner** |
| Stiven | `stivencolombia@gmail.com` | Contributor |
| L. Mejía | `lmejiacoronado@gmail.com` | Contributor |
| Esteban | `estebanbl090@gmail.com` | Contributor |

---

## 6.2 — Camino A: por comandos (Azure CLI)

### Paso 1 — Invitar a los cuatro (una sola vez)

`az` no tiene comando de invitación; se hace contra Microsoft Graph:

```bash
for EMAIL in carlosres1995@gmail.com stivencolombia@gmail.com \
             lmejiacoronado@gmail.com estebanbl090@gmail.com; do
  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/invitations" \
    --headers "Content-Type=application/json" \
    --body "{\"invitedUserEmailAddress\":\"$EMAIL\",\"inviteRedirectUrl\":\"https://portal.azure.com\",\"sendInvitationMessage\":true}"
done
```
Cada persona recibe un correo y **debe aceptarlo** antes del paso 2.

### Paso 2 — Asignar los roles (por object id, no por correo)

```bash
RG="rg-centinela-week1"
SCOPE="$(az group show --name "$RG" --query id -o tsv)"

# Owner — solo Carlos
OID=$(az ad user list --filter "mail eq 'carlosres1995@gmail.com'" --query "[0].id" -o tsv)
az role assignment create --assignee-object-id "$OID" --assignee-principal-type User \
  --role "Owner" --scope "$SCOPE"

# Contributor — los otros tres
for EMAIL in stivencolombia@gmail.com lmejiacoronado@gmail.com estebanbl090@gmail.com; do
  OID=$(az ad user list --filter "mail eq '$EMAIL'" --query "[0].id" -o tsv)
  az role assignment create --assignee-object-id "$OID" --assignee-principal-type User \
    --role "Contributor" --scope "$SCOPE"
done
```

> **⚠ Ojo (real y crítico):** dos cosas que ya nos pasaron en este proyecto:
> - **`--assignee-principal-type User` no es opcional.** Sin él, sobre un invitado, Azure
>   devuelve `UnmatchedPrincipalType`.
> - **`az role assignment` puede fallar con `MissingSubscription`** en algunas suscripciones
>   (cuenta personal sobre directorio predeterminado). Es un **defecto de la CLI**, no de
>   permisos: la misma operación por REST funciona. Si te ocurre, usa el paso 2-bis.

### Paso 2-bis — Alternativa por REST (si el paso 2 da `MissingSubscription`)

```bash
# IDs de rol (constantes de Azure):
#   Owner        8e3af657-a8ff-443c-a75c-2fe8c4bcb635
#   Contributor  b24988ac-6180-42a0-ab88-20f7382dd24c
SUB=$(az account show --query id -o tsv)

asignar_rol() {  # uso: asignar_rol <object-id> <role-id>
  local oid="$1" role="$2" guid
  guid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python -c "import uuid;print(uuid.uuid4())")
  az rest --method put \
    --uri "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignments/${guid}?api-version=2022-04-01" \
    --body "{\"properties\":{\"roleDefinitionId\":\"/subscriptions/${SUB}/providers/Microsoft.Authorization/roleDefinitions/${role}\",\"principalId\":\"${oid}\",\"principalType\":\"User\"}}"
}

OID=$(az ad user list --filter "mail eq 'carlosres1995@gmail.com'" --query "[0].id" -o tsv)
asignar_rol "$OID" "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"   # Owner

for EMAIL in stivencolombia@gmail.com lmejiacoronado@gmail.com estebanbl090@gmail.com; do
  OID=$(az ad user list --filter "mail eq '$EMAIL'" --query "[0].id" -o tsv)
  asignar_rol "$OID" "b24988ac-6180-42a0-ab88-20f7382dd24c"  # Contributor
done
```

### Paso 3 — Verificar

```bash
az role assignment list --scope "$SCOPE" \
  --query "[].{quien:principalName, rol:roleDefinitionName}" -o table
```
Debes ver un `Owner` y tres `Contributor` cuyos nombres contienen `#EXT#`.

---

## 6.3 — Camino B: desde el portal (con el recurso ya corriendo)

Si prefieres hacerlo con clics sobre el recurso desplegado, es igual de válido y más visual.

### Invitar a los miembros (si aún no están en el directorio)

1. Entra a **portal.azure.com** con la cuenta Owner.
2. Barra de búsqueda superior → **Microsoft Entra ID**.
3. Menú izquierdo → **Usuarios** → **+ Nuevo usuario** → **Invitar usuario externo**.
4. Escribe el correo (p. ej. `carlosres1995@gmail.com`), un nombre para mostrar, y **Revisar
   e invitar**. Repite para los cuatro. Cada uno recibe un correo que debe aceptar.

### Asignar el rol sobre el grupo de recursos

1. Barra de búsqueda → **Grupos de recursos** → abre **`rg-centinela-week1`**.
2. En el menú izquierdo del grupo, **Control de acceso (IAM)**.
3. Botón **+ Agregar** → **Agregar asignación de roles**. Se abre un asistente de tres pestañas:
   - **Rol:** busca y selecciona `Owner` (para Carlos) o `Contributor` (para los demás) →
     **Siguiente**.
   - **Miembros:** deja "Usuario, grupo o entidad de servicio" → **+ Seleccionar miembros** →
     escribe el correo del invitado, selecciónalo → **Seleccionar** → **Siguiente**.
   - **Revisar y asignar:** confirma la terna (rol, miembro, alcance = el grupo) → **Revisar y
     asignar**.
4. Repite para cada miembro con su rol.

### Verificar en el portal

En la misma pantalla **Control de acceso (IAM)** → pestaña **Asignaciones de roles**. Verás la
lista: debe aparecer un Owner y tres Contributor, todos con alcance "Este recurso"
(`rg-centinela-week1`).

> **Consejo:** el portal no sufre el defecto `MissingSubscription` de la CLI. Si los comandos
> te dan ese error y no quieres la vía REST, el portal es el camino más simple.

---

## Referencia rápida — orden de despliegue en un vistazo

```bash
az login && az account set --subscription "<SUBSCRIPTION_ID>"
cp .env.example .env            # y editar
# registrar proveedores (Parte 2)
bash scripts/provision-network-containerapps.sh
bash scripts/provision-cosmos.sh
bash scripts/provision-postgres.sh
bash scripts/provision-keyvault.sh
bash scripts/provision-containerapps-identity.sh
APPS_PID=$(az identity show -n "id-cent-apps" -g "$RESOURCE_GROUP" --query principalId -o tsv)
bash scripts/provision-eventgrid.sh --publisher-principal "$APPS_PID" --consumer-principal "$APPS_PID" --function-principal "$APPS_PID"
bash scripts/provision-entra-app.sh
bash scripts/configure-postgres-managed-identity.sh
bash scripts/provision-container-registry.sh
bash scripts/provision-container-apps.sh
CENTINELA_ALERT_EMAIL="..." bash scripts/provision-observability.sh
# construir/publicar/desplegar imagenes (3.8) + verificar (3.9)
# roles del equipo (Parte 6)
bash scripts/shutdown-daily.sh   # al terminar la jornada
```
