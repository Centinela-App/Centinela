# Informe de errores corregidos en los scripts de despliegue

Registro de los defectos encontrados al ejecutar el despliegue completo de extremo a
extremo sobre una suscripción real. **30 errores** corregidos, agrupados por causa raíz.

El despliegue original fallaba en el primer paso de RBAC con un error silencioso. Al
corregirlo, cada capa sucesiva reveló el siguiente defecto: la mayoría **no eran fallos
visibles**, sino comprobaciones que devolvían el resultado equivocado y daban por bueno
un despliegue roto.

---

## Resumen por categoría

| Categoría | Nº | Gravedad |
|---|---|---|
| Comprobaciones que mentían sobre el estado real | 6 | **Crítica** — reportaban OK sobre infraestructura rota |
| Comandos de `az` eliminados o renombrados | 5 | Alta — abortaban el despliegue |
| `set -e` matando el script en silencio | 3 | **Crítica** — fallo sin mensaje |
| Configuración de red/plataforma incompleta | 4 | **Crítica** — servicios inalcanzables |
| Operaciones no idempotentes | 3 | Media — fallaban al reintentar |
| Herramientas invisibles en Windows | 2 | Alta — falsos FAIL masivos |
| Reproducibilidad tras destruir | 1 | **Crítica** — impedía redesplegar |
| Errores de sintaxis y salida | 2 | Baja — ruido en los informes |

---

## 1. Comprobaciones que mentían sobre el estado real

La clase más peligrosa: el script preguntaba a Azure, interpretaba mal la respuesta y
**continuaba como si todo estuviera bien**.

### 1.1 · `dns-zone-group show` devuelve exit 0 con cuerpo vacío

**Archivos:** `configure-function-host-storage.sh`, `provision-cosmos.sh`, `provision-postgres.sh`

`az network private-endpoint dns-zone-group show` devuelve **código de salida 0 y `{}`**
cuando el grupo no existe. Las tres comprobaciones decidían por el código de salida, así
que siempre concluían "ya existe" y **nunca creaban el zone group**.

**Consecuencia:** los Private Endpoints de Cosmos, PostgreSQL y Table quedaban creados y
aprobados **pero sin registro DNS**. Los servicios eran irresolubles por nombre desde la
VNet. Peor aún, Cosmos y PostgreSQL reportaban `ISS-S2-00X OK` porque solo verificaban
que el PE existiera, no que el DNS resolviera. Medido: las tres zonas en `A=0`.

**Corrección:** helper `pe_dns_zone_group_exists()` en `lib/common.sh` que cuenta el
contenido real (`dns-zone-group list | length(@)`), más verificación de registros A con
espera (`private_dns_has_a_records` + `retry_until`), porque su publicación es asíncrona.

### 1.2 · Campo JMESPath inexistente en la integración de VNet

**Archivo:** `deploy-scoring-function.sh`

La consulta filtraba por `subnetResourceId`, pero `az functionapp vnet-integration list`
devuelve el campo como **`vnetResourceId`**. El filtro no casaba nunca: se re-integraba
en cada corrida y la verificación no comprobaba nada.

### 1.3 · `az webapp deploy` daba falsos negativos

**Archivo:** `deploy-application.sh`

Por defecto (`--track-status true`) el comando vigila el arranque del contenedor y se
rinde con *"site failed to start within 10 mins"*. La aplicación tarda **~220 s** en pasar
la sonda de calentamiento (Spring Boot + Flyway + primera conexión a PostgreSQL por
Private Endpoint). **Verificado:** mientras `az` reportaba fallo, la app respondía
`HTTP 200`. El script además **no verificaba nada** tras desplegar.

**Corrección:** `--track-status false` + `wait_until_healthy()` propia, que sondea
`/actuator/health` (30 × 20 s). El criterio de éxito pasa de *"az devolvió 0"* a
**"la aplicación responde"**.

### 1.4 · La creación del admin de Entra fallaba habiendo surtido efecto

**Archivo:** `provision-postgres.sh`

`microsoft-entra-admin create` aplicó el cambio y **después** devolvió
`InternalServerError`. `with_retry` reintentó a ciegas y chocó con
`42710: role already exists`, matando el paso pese a estar el admin correctamente creado.

**Corrección:** si la creación falla, se consulta el estado real antes de darse por
vencido (`entra_admin_exists`).

---

## 2. Comandos de `az` eliminados o renombrados

El CLI 2.88 ya no acepta cinco invocaciones del repositorio. Se auditaron **983 pares
(comando, flag)** de todos los scripts contra el CLI instalado.

| Archivo | Antes | Ahora |
|---|---|---|
| `provision-postgres.sh` | `--active-directory-auth` | `--microsoft-entra-auth` |
| `provision-postgres.sh` | `--high-availability` | *(eliminado; Burstable no soporta HA)* |
| `provision-postgres.sh` | `ad-admin` | `microsoft-entra-admin` |
| `provision-postgres.sh` | `--public-network-access` | `--public-access` |
| `provision-cosmos.sh` | `--ttl` | índice TTL sobre `_ts` vía `--idx` |
| `deploy-scoring-function.sh` | `--runtime-version 21` | `--runtime-version 21.0` |
| `configure-postgres-managed-identity.sh` | `firewall-rule --rule-name` | `--server-name` / `--name` |

En Cosmos DB for MongoDB el TTL **no es un flag**: se declara como índice sobre `_ts` con
`expireAfterSeconds`.

---

## 3. `set -e` matando el script en silencio

**El fallo original que bloqueó el despliegue.**

```bash
assert_not_forbidden_role() {
  for f in "${FORBIDDEN_ROLES[@]}"; do
    [ "$role" = "$f" ] && die "..."   # ← última sentencia de la función
  done
}
```

Cuando el rol **no** está prohibido (el caso normal), la última evaluación es falsa, la
función devuelve 1 y `set -e` **mata el script sin imprimir nada**. El log cortaba justo
tras `Asignando 'Storage Blob Data Contributor'...` sin ningún mensaje de error.

**Afectaba a:** `assign-rbac.sh`, `provision-eventgrid.sh` (guard idéntico) y
`provision-app-service.sh` (`[ capacity = 1 ] && log_info` al final de función).

**Corrección:** `if/then/fi` con `return 0` explícito. Se barrió todo el repositorio en
busca del patrón `[ ... ] && cmd` en posición final de función; no quedan casos.

**Regresión propia:** al limpiar una salida `000000` en `wait_until_healthy` se eliminó un
`|| true` que además protegía de `set -e`; cuando `curl` agotaba el tiempo (código 28) la
sustitución de comandos abortaba el despliegue. Corregido conservando ambos efectos.

---

## 4. Configuración de red y plataforma incompleta

### 4.1 · Faltaba el Private Endpoint de `file` — el bloqueo final

**Archivo:** `configure-function-host-storage.sh`

El host de Azure Functions **monta un recurso compartido de Azure Files** como su sistema
de archivos. Existían Private Endpoints de blob, queue y table, pero **no de `file`**. Con
el Storage en `publicNetworkAccess=Disabled`, el montaje fallaba con
`Container failed to remount volume. Terminate.` y la Function App devolvía **503
indefinidamente** mientras ARM la reportaba `Running`.

**Corrección:** se generalizaron las tres funciones para cubrir `table` y `file` con el
mismo código, en lugar de duplicarlas.

### 4.2 · El almacén de claves del host no se inicializaba

**Archivo:** `deploy-scoring-function.sh`

Por defecto el host guarda sus claves en el contenedor `azure-webjobs-secrets` del
Storage. Con acceso público deshabilitado y conexión por identidad, ese almacén **no
llegaba a inicializarse**: `az functionapp keys list` devolvía `Bad Request` y Event Grid
fallaba al validar el endpoint con `Webhook endpoint validation failed ... NotFound`,
porque no podía obtener la clave de sistema `eventgrid_extension`.

**Corrección:** `AzureWebJobsSecretStorageType=files`. Las claves se guardan en el sistema
de archivos del host (ya montado por Azure Files con su Private Endpoint). El almacén se
inicializa en segundos y la suscripción se crea sin error.

### 4.3 · La Function App se creaba sin red

`az functionapp create` **rechaza** la creación cuando el Storage tiene el acceso público
deshabilitado y no se declara red: el runtime no podría alcanzar su propia cuenta de
Storage para arrancar. El script integraba la VNet *después* de crear, demasiado tarde.
Ahora se pasan `--vnet`/`--subnet` en la propia creación.

### 4.4 · Límite de arranque del contenedor demasiado justo

**Archivo:** `provision-app-service.sh`

La app tarda ~205 s en arrancar contra un límite por defecto de **230 s**. Con 25 s de
margen, el despliegue fallaba de forma intermitente con `ContainerStartupFailure` aunque
la app estuviera sana. Añadido `WEBSITES_CONTAINER_START_TIME_LIMIT=600`.

**Medición útil:** producción tarda ~220 s y staging ~365 s. Ambos slots comparten el plan
S1, así que el segundo en arrancar compite por CPU.

---

## 5. Operaciones no idempotentes

### 5.1 · Propagación no atómica del firewall de PostgreSQL

**Archivo:** `configure-postgres-managed-identity.sh`

La regla de firewall **no propaga de forma atómica** a todos los nodos del gateway: la
sonda conectaba, pero conexiones posteriores daban `Connection timed out`. Se añadieron
reintentos sobre `ensure_database` y `ensure_principal` (idempotentes:
`CREATE ... WHERE NOT EXISTS`, `GRANT`).

### 5.2 · `ensure_database` no toleraba que la base ya existiera

El reintento reveló que la comprobación de existencia silencia sus errores, así que un
timeout de red se parecía a "no existe" y el `CREATE` fallaba con *"database already
exists"*. Ahora el `CREATE` tolera ese caso concreto: es correcto por construcción, no por
que un reintento lo tape.

### 5.3 · Registro de la función tras el zip deploy

Event Grid valida el endpoint al crear la suscripción; tras un zip deploy el host tarda en
registrar sus funciones. Se añadió `wait_for_function_registered()`.

---

## 6. Herramientas invisibles en Windows

### 6.1 · `jq` y `psql` instalados pero fuera del `PATH`

Los instaladores de PostgreSQL y winget no modifican el `PATH` de la sesión. `jq` faltaba
y lo usan 12 scripts: `validate-entra-roles` moría al arrancar y `validate-rbac` fallaba.

**Corrección:** el descubrimiento se movió **dentro de `require_cmd`** en `lib/common.sh`,
que busca en rutas de PostgreSQL, WinGet (Links y Packages), Chocolatey y Scoop antes de
fallar. Se usa un **array**, no una lista sin comillas, porque `Program Files` contiene un
espacio que rompía el *word splitting*. Además `jq` se descubre al cargar `common.sh`,
porque 4 scripts lo usan sin declararlo y su ausencia produce FAIL silenciosos.

### 6.2 · El stub de `python3` de Microsoft Store

**Archivo:** `tests/validate-app-service.sh`

El lector de App Settings usaba `jq` y, si faltaba, caía a `python3`. En Windows
`command -v python3` **sí** encuentra el stub de Microsoft Store, que no ejecuta nada y
devuelve vacío. Resultado: **10 FAIL falsos** sobre settings que en Azure estaban
correctos.

Enmascarado por un segundo defecto: `jq -r '(.[] | select(...)) // "MISSING"'` **no**
produce `"MISSING"` cuando no hay coincidencia — deja el flujo vacío. Ahora se materializa
la lista antes de decidir y el fallback a `python3` se comprueba de verdad.

---

## 7. Reproducibilidad tras destruir

**Archivo:** `provision-keyvault.sh`

El Key Vault se crea con *purge protection*, así que borrar el Resource Group lo deja en
estado **soft-deleted y no purgable**: su nombre queda reservado durante todo el periodo
de retención. Sin corrección, **el segundo despliegue con el mismo `NAME_PREFIX` fallaría
para siempre** con *"vault name is already in use"* — justo el flujo *destruir y volver a
desplegar* que exige un entorno de prácticas.

**Corrección:** se detecta el vault borrado y se **recupera** (`az keyvault recover`) en
lugar de intentar crear uno nuevo.

---

## 8. Sintaxis y salida

- `printf '-----\n'` en 6 validadores: `bash` interpreta la cadena inicial como opción y
  emite `printf: --: invalid option`. Corregido a `printf '%s\n' '-----'`.
- Diagnóstico de los orquestadores: `deploy-week1.sh` y `deploy-week2.sh` no decían qué
  sub-paso moría ni con qué código. Ahora capturan el código explícitamente. Un fallo
  silencioso como el original no puede repetirse.

---

## 9. Garantía de seguridad que no se cumplía

**Archivo:** `configure-postgres-managed-identity.sh`

La ventana temporal de PostgreSQL se documentó afirmando que **"revierte siempre"**
mediante `trap`. **Es falso:** `trap` intercepta `EXIT`, `INT` y `TERM`, pero **ningún
trap puede interceptar `SIGKILL`** ni un corte de energía.

Ocurrió en la práctica: una corrida fue terminada abruptamente y **la ventana quedó
abierta** con `publicNetworkAccess=Enabled` y la regla de firewall activa, hasta que se
cerró a mano. La exposición estaba acotada a una sola IP y `password-auth` seguía
`Disabled` (solo servía un token de Entra), pero la garantía prometida no existía.

**Corrección:** `close_leaked_window()` se ejecuta **al arrancar el script**, antes de
cualquier otra operación: detecta una ventana huérfana de una corrida anterior muerta y la
cierra. Es la única defensa posible cuando ningún `trap` llega a ejecutarse. La
documentación (`DESPLIEGUE.md`, runbook y el propio mensaje del script) declara ahora el
límite de forma explícita.

## 10. Tiempos de propagación medidos al filo

- **Firewall de PostgreSQL** (`configure-postgres-managed-identity.sh`): la propagación
  varía entre corridas — medida desde ~20 s hasta más de un minuto. Con 6 × 10 s el paso
  fallaba de forma intermitente sobre una ventana correctamente abierta. Ampliado a
  12 × 20 s.
- **Arranque de las Web Apps** (`deploy-application.sh`): producción ~220 s, staging
  ~365 s. Presupuesto de espera de salud subido a 30 × 20 s (10 min).

## 11. Mensajes de log que afirmaban lo contrario del estado real

`provision-keyvault.sh` y `provision-eventgrid.sh` emitían un `log_warn` **fijo**
declarando que la identidad de la Function "aún no existe", incluso en redespliegues donde
la Function ya estaba desplegada. No era un fallo funcional —los roles se asignan después
en `deploy-scoring-function.sh`— pero engañaba a quien leyera el registro. Ambos scripts
resuelven ahora la identidad y, si existe, **aplican el rol en ese momento**.

---

## Limitación conocida del entorno (no es un defecto de los scripts)

El plan **S1 (1 core, 1.75 GB)** aloja tres JVMs: Web App de producción, slot staging y el
host de Azure Functions. **No caben las tres arrancadas a la vez**: se observó que al
levantarse staging (HTTP 200), producción caía (HTTP 000). De ahí los arranques de
220-365 s.

No bloquea el despliegue —cada paso verifica la salud del slot que acaba de publicar— pero
para una demostración con los tres servicios activos simultáneamente conviene separar el
host de Functions a su propio plan (B1, ~USD 13/mes) o escalar a S2.

---

## Herramienta añadida

`scripts/watch-deploy.sh` — barra de avance en vivo (17 pasos) con cronómetro del paso
actual. Un despliegue tarda 40-60 min y hay pasos que pasan minutos sin escribir nada; sin
señal de avance es imposible distinguir *trabajando* de *colgado*.

---

## Lección transversal

**Seis de los defectos críticos comparten la misma causa: confiar en el código de salida
de `az` en vez de verificar el estado real en Azure.** El CLI devuelve 0 con cuerpo vacío,
falla después de aplicar el cambio, o se rinde antes de que el recurso esté listo.

El criterio que se aplicó de forma sistemática en las correcciones es **verificar el
resultado observable** — que el DNS resuelva, que la app responda 200, que el rol aparezca
listado — en lugar del código de retorno del comando que debía producirlo.
