# Runbook — Despliegue completo (Semana 1 + Semana 2)

Guía única y reproducible para levantar **toda** la infraestructura entregada hasta el
cierre de Semana 2 desde una máquina limpia. Cada comando es copiable tal cual.

El orquestador de un solo comando es `scripts/deploy-all.sh`. Los pasos individuales
siguen disponibles para recolectar evidencia por issue.

---

## 0. Dónde ejecutar

| Entorno | Sirve para | Limitación |
|---|---|---|
| **Azure Cloud Shell inyectado en la VNet** *(recomendado)* | Todo, incluida la Fase 2 | Requiere configurar Cloud Shell con red virtual |
| VM jumpbox en `snet-app-integration` | Todo | Costo adicional de la VM |
| Laptop / Cloud Shell público | Todo, vía ventana temporal (ver abajo) | Abre y cierra acceso público de PostgreSQL durante ~1 min |

**Por qué importa:** el diseño cierra el acceso público de los servicios de datos. El
paso `configure-postgres-managed-identity.sh` abre una conexión `psql` real contra el
servidor para crear los principales Entra de producción y staging.

### Ventana temporal de acceso público (máquinas fuera de la VNet)

El resto de la Fase 2 —Cosmos, Key Vault, Event Grid, Function host, despliegue de la
app— se resuelve por **plano de control** (ARM) y funciona desde cualquier máquina. El
único paso que necesita plano de datos privado es el *bootstrap* de PostgreSQL.

`configure-postgres-managed-identity.sh` lo resuelve así:

1. Intenta conectarse por el **Private Endpoint**. Si el runner vive en la VNet, termina
   ahí y nada más ocurre.
2. Si no hay camino privado, habilita el acceso público **acotado a una sola regla de
   firewall con la IP pública del operador**, ejecuta el bootstrap y la revierte mediante
   `trap EXIT INT TERM`, también si el script falla o se interrumpe con `Ctrl-C`.
3. Estado final idéntico al de diseño: `publicNetworkAccess=Disabled`, sin reglas.

**Límite de la reversión automática.** Ningún `trap` intercepta `SIGKILL` ni un corte de
energía: si la corrida muere así, la ventana **queda abierta**. Por eso el script
comprueba al arrancar si existe una ventana huérfana de una ejecución anterior y la
cierra antes de continuar (`close_leaked_window`). Verificación manual:

```bash
az postgres flexible-server show -n <servidor> -g "$RESOURCE_GROUP" \
  --query 'network.publicNetworkAccess' -o tsv    # esperado: Disabled
```

La ventana **no debilita la autenticación**: `password-auth` sigue `Disabled`, así que la
única credencial válida durante la ventana sigue siendo un token de Microsoft Entra ID.

Para prohibir esta ruta (por ejemplo en CI con runner dentro de la VNet):

```bash
export CENTINELA_ALLOW_PUBLIC_WINDOW=0   # el script falla en vez de abrir la ventana
```

Si el cierre automático llegara a fallar, el script imprime los dos comandos exactos de
reversión manual. Verificación:

```bash
az postgres flexible-server show -n <servidor> -g "$RESOURCE_GROUP" \
  --query 'network.publicNetworkAccess' -o tsv          # esperado: Disabled
az postgres flexible-server firewall-rule list -s <servidor> -g "$RESOURCE_GROUP" -o tsv
```

## 1. Requisitos de la máquina

```bash
az version                 # Azure CLI
java -version              # 21 o superior
mvn -version               # Maven 3.9+
psql --version             # cliente de PostgreSQL (solo Fase 2)
git --version
```

Instalación de `psql` si falta (Cloud Shell ya lo trae):

```bash
sudo apt-get update && sudo apt-get install -y postgresql-client   # Debian/Ubuntu
winget install -e --id PostgreSQL.PostgreSQL.17                    # Windows
```

En Windows el instalador **no** agrega su `bin` al `PATH`, así que `psql --version`
falla aunque esté instalado. Los scripts lo detectan solos: `ensure_psql_on_path`
(en `scripts/lib/common.sh`) busca en `C:\Program Files\PostgreSQL\<version>\bin` y lo
anexa al `PATH` de la corrida. No hace falta configurar nada a mano.

Permisos de directorio y suscripción necesarios:

- **Contributor** sobre la suscripción o el Resource Group (crear recursos).
- **User Access Administrator** u **Owner** sobre el RG (crear *role assignments*).
- **Application Administrator** en Entra ID (crear la App Registration y su SP).

## 2. Clonar y situarse en la entrega estable

```bash
git clone https://github.com/Centinela-App/Centinela.git
cd Centinela
git checkout develop
chmod +x scripts/*.sh scripts/tests/*.sh
```

## 3. Sesión de Azure

```bash
az login
az account set --subscription "<subscription-id>"
az account show --query "{sub:id, tenant:tenantId, user:user.name}" -o table
```

## 4. Parámetros locales

```bash
cp .env.example .env
nano .env        # o el editor que prefieras
```

Contenido esperado de `.env` (sin comillas sobrantes, sin espacios alrededor del `=`):

```env
SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
LOCATION="eastus2"
RESOURCE_GROUP="rg-centinela-week1"
NAME_PREFIX="cent"
APP_SERVICE_SKU="S1"
```

Reglas que valida el script antes de tocar Azure:

- `SUBSCRIPTION_ID` con formato UUID.
- `NAME_PREFIX` de 3 a 11 caracteres, solo minúsculas y dígitos.
- `APP_SERVICE_SKU` con soporte de slots y escala horizontal (`S1` o superior).

`.env` está en `.gitignore`: **nunca** se commitea.

## 5. Ensayo en seco (no crea nada)

```bash
bash scripts/deploy-all.sh --validate-only
```

Verifica herramientas, sesión, coincidencia de suscripción, región, disponibilidad del
SKU e imprime los **nombres deterministas** que va a crear. Todos los nombres derivan de
`sha1(NAME_PREFIX|SUBSCRIPTION_ID|RESOURCE_GROUP)[:6]`, de modo que la misma
configuración produce la misma infraestructura en cualquier máquina.

## 6. Despliegue completo

```bash
bash scripts/deploy-all.sh --with-tests
```

Sin interacción (CI, demo grabada):

```bash
bash scripts/deploy-all.sh --with-tests --yes
```

Qué hace, en orden:

| Fase | Paso | Recursos |
|---|---|---|
| 1 | `deploy-week1.sh` | Resource Group · Storage + 4 contenedores + 2 colas · App Service Plan + Web App + slot `staging` + Managed Identity · VNet + 2 subredes + DNS privado · Private Endpoints Blob/Queue · App Registration con 4 app roles · RBAC mínimo |
| 2 | `deploy-week2.sh` | Cosmos DB (API Mongo) privado · PostgreSQL Flexible Server privado con Entra ID exclusivo · Key Vault + secreto migrado · Event Grid Topic + colas de casos · Private Endpoint de Table para el host de Function · principales de BD para prod y staging |
| 2 | *(continúa)* | `mvn clean verify` · despliegue a producción (Flyway aplica el esquema) · re-grants para staging · despliegue a staging · build y despliegue de la Function de scoring · suscripción de Event Grid → `ScoreTransaction` |
| 3 | `--with-tests` | Validadores de solo lectura de Storage, App Service, red, Managed Identity, Entra, RBAC, Cosmos, PostgreSQL, Key Vault, Event Grid y desacoplamiento |

Cada paso deja su registro en `deploy-run/<timestamp>/NN-paso.log` y el script imprime
un resumen final con el resultado y la duración de cada uno.

**Duración esperada:** 35–50 minutos en la primera corrida (PostgreSQL y Cosmos son los
pasos lentos). Las reejecuciones son de pocos minutos porque todo es idempotente.

### Ejecución por fases

```bash
bash scripts/deploy-all.sh --skip-week2               # solo infraestructura base
bash scripts/deploy-all.sh --skip-week1               # solo datos, mensajería y scoring
bash scripts/deploy-all.sh --env-file ./.env.demo     # otro juego de parámetros
```

## 7. Comprobación manual posterior

```bash
# Nombres reales de la corrida
HASH=$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)
APP="${NAME_PREFIX}-app-${HASH}"

# Inventario del Resource Group
az resource list --resource-group "$RESOURCE_GROUP" -o table

# Salud de la aplicación en producción y en staging
curl -s "https://${APP}.azurewebsites.net/actuator/health"
curl -s "https://${APP}-staging.azurewebsites.net/actuator/health"

# La Function de scoring está suscrita al tópico
az eventgrid event-subscription list \
  --source-resource-id "$(az eventgrid topic show -g "$RESOURCE_GROUP" -n "${NAME_PREFIX}-egt-${HASH}" --query id -o tsv)" \
  -o table
```

## 8. Prueba de extremo a extremo (opcional, desde un host con acceso a la VNet)

```bash
bash scripts/tests/test-pipeline-e2e.sh staging       # API → Blob/Event Grid → Cosmos → Queue → caso en PostgreSQL
bash scripts/tests/test-decoupling.sh                 # la API responde 202 con el consumidor caído
bash scripts/tests/test-threshold-hot-reload.sh       # cambio de umbral sin redesplegar
```

## 9. Cierre y control de costos

```bash
# Reporte de costos y evidencia de cierre de Semana 2 (no borra nada)
bash scripts/tests/test-week2-closeout.sh --start-date 2026-07-01

# Destrucción completa: elimina el Resource Group y la App Registration
bash scripts/destroy-week1.sh --wait
bash scripts/destroy-week1.sh --yes --wait            # sin confirmación interactiva
bash scripts/destroy-week1.sh --wait --keep-entra     # conserva la identidad compartida
```

`destroy-week1.sh` pide teclear el nombre exacto del Resource Group antes de borrar.

## 10. Fallos frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `Faltan parametros obligatorios: ...` | No hay `.env` ni variables exportadas | `cp .env.example .env` y completarlo |
| `Suscripcion activa (...) != SUBSCRIPTION_ID` | Sesión apuntando a otra suscripción | `az account set --subscription "$SUBSCRIPTION_ID"` |
| `SKU 'F1' no disponible ... o sin soporte de slots` | SKU sin deployment slots | Usar `S1` o superior |
| `SubscriptionIsOverQuotaForSku` · `Current Limit (Total VMs): 0` | La suscripción no tiene cuota de App Service **en esa región** (las Pay-As-You-Go nuevas nacen con cuota 0) | `bash scripts/tests/check-appservice-quota.sh` para encontrar una región con cuota, cambiar `LOCATION` en `.env` y desplegar sobre un RG nuevo o vacío. Alternativa: Portal → Suscripciones → Uso + cuotas → Solicitar aumento |
| `Falta 'psql'` | Cliente de PostgreSQL ausente | Instalarlo, o `--skip-week2` |
| `No hay conectividad privada a <server>...` | El ejecutor no está en la VNet | Cloud Shell inyectado en la VNet, jumpbox o VPN |
| `Resource Group ... no existe` en Fase 2 | Se omitió la Fase 1 | Ejecutar sin `--skip-week1` |
| Error de directorio al crear la App Registration | Falta rol Application Administrator | Pedir el rol o ejecutar ese paso con una cuenta que lo tenga |

Todos los scripts son idempotentes: tras corregir la causa, vuelve a ejecutar
`bash scripts/deploy-all.sh` y la corrida retoma sin duplicar recursos.
