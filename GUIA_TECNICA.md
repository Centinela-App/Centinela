# Centinela — Guía técnica

Guía única del sistema. Cubre la arquitectura, el funcionamiento de los dos
proyectos (Centinela y Centinela Lab), su despliegue en Azure desde una cuenta
limpia, el CI/CD y la operación diaria. Un desarrollador debe poder comprender
y reproducir todo el sistema leyendo solo este documento y los README de cada
repositorio.

- Repositorio del servicio: `https://github.com/Centinela-App/Centinela`
- Repositorio del simulador: `https://github.com/Centinela-App/centinela-lab`

---

## Índice

1. [Qué es el sistema](#1-qué-es-el-sistema)
2. [Arquitectura general](#2-arquitectura-general)
3. [Flujo completo de una transacción](#3-flujo-completo-de-una-transacción)
4. [Componentes de Centinela](#4-componentes-de-centinela)
5. [Centinela Lab: el banco de pruebas](#5-centinela-lab-el-banco-de-pruebas)
6. [Relación entre Centinela y Centinela Lab](#6-relación-entre-centinela-y-centinela-lab)
7. [Funcionamiento interno](#7-funcionamiento-interno)
8. [Persistencia](#8-persistencia)
9. [Seguridad e identidad](#9-seguridad-e-identidad)
10. [Configuración del entorno local](#10-configuración-del-entorno-local)
11. [Arquitectura de Azure](#11-arquitectura-de-azure)
12. [Despliegue desde cero](#12-despliegue-desde-cero)
13. [CI/CD](#13-cicd)
14. [Ejecución de pruebas](#14-ejecución-de-pruebas)
15. [Observabilidad](#15-observabilidad)
16. [Operación y costos](#16-operación-y-costos)
17. [Decisiones de arquitectura (ADR)](#17-decisiones-de-arquitectura-adr)
18. [Registro de seguridad](#18-registro-de-seguridad)

---

## 1. Qué es el sistema

**Centinela** es un servicio de detección de fraude transaccional: recibe
transacciones por una API REST, las puntúa contra un conjunto de reglas
(velocidad, monto atípico, geografía imposible, comercio riesgoso), abre un
caso cuando el puntaje supera el umbral, genera una explicación determinista
del caso y permite adjuntar documentos de verificación de identidad que se
procesan por extracción de texto.

**Centinela Lab** es un simulador de transacciones: una aplicación web
independiente que ejerce la API pública de Centinela con ocho escenarios
reproducibles (normales y fraudulentos) y verifica que el sistema responde lo
que promete. Es la herramienta de demostración y prueba de aceptación del
sistema completo.

Ambos son proyectos Java 21 / Maven. Centinela usa Spring Boot 3.4 (API) y
Azure Functions (motor de scoring); el Lab usa Spring Boot 3.4 con Thymeleaf.

## 2. Arquitectura general

```
                     ┌─────────────────────  Azure Container Apps (cae-cent)  ─────────────────────┐
                     │                                                                              │
┌──────────────┐     │  ┌─────────────┐    Blob     ┌──────────────┐    Storage    ┌─────────────┐  │
│ centinela-lab│ HTTPS│  │ ca-cent-api │──crudo──►  │ Event Grid   │    Queue      │ca-cent-     │  │
│ (ca-cent-lab)│──┬──►│  │ (ingesta +  │            │ topic        │  flagged-     │explainer    │  │
│  Thymeleaf   │  │  │  │  consulta)  │──evento──► │ cent-egt-*   │  cases        │(explicador +│  │
└──────────────┘  │  │  └─────────────┘            └──────┬───────┘     ▲         │ extractor   │  │
      token       │  │        │  ▲                        │ webhook     │         │ documental) │  │
      Entra ID    │  │        ▼  │ lee                    ▼             │         └──────┬──────┘  │
                  │  │  PostgreSQL│                ┌──────────────┐     │                │         │
                  │  │  (casos)   │                │ca-cent-scoring│────┘                │         │
                  │  │        ▲   └── Cosmos ◄─────│ (motor de    │  escribe            │         │
                  │  │        │       (registro    │  reglas,     │  score              ▼         │
                  │  │        └───────de scoring)  │  Functions)  │              PostgreSQL       │
                  │  │                             └──────────────┘              (explicación,    │
                  │  │                                                            documentos)     │
                  └──►  autenticación: Microsoft Entra ID (app roles SERVICE / ANALYST)            │
                     └──────────────────────────────────────────────────────────────────────────────┘
```

Tres aplicaciones de Centinela comparten **una misma imagen** de contenedor
(`centinela-api`) con papeles distintos según interruptores de entorno, más una
cuarta imagen para el motor:

| Container App | Imagen | Papel |
|---|---|---|
| `ca-cent-api` | `centinela-api` | API de ingesta (`POST /transactions`), API de consulta, consumidor de la cola de casos |
| `ca-cent-scoring` | `centinela-scoring` | Motor de reglas (runtime de Azure Functions en contenedor, trigger Event Grid) |
| `ca-cent-explainer` | `centinela-api` | Explicador de casos + extractor de documentos (workers `@Scheduled`, sin ingreso) |
| `ca-cent-lab` | `centinela-lab` | Banco de pruebas (repositorio propio) |

Los interruptores que definen el papel (todos nacen apagados):
`CENTINELA_INQUIRY_ENABLED`, `CENTINELA_EXPLAINER_ENABLED`,
`CENTINELA_DOCUMENT_VERIFICATION_ENABLED`, `CENTINELA_SCORING_RECORD_ENABLED`,
`CENTINELA_QUEUE_AUTO_START`.

## 3. Flujo completo de una transacción

1. Un cliente autenticado (el Lab, o cualquier servicio con el app role
   `SERVICE`) envía `POST /api/v1/transactions`. La API valida el contrato,
   persiste el JSON crudo en Blob Storage (`raw-transactions-production`) y
   publica un evento `transaction-event-v1` en Event Grid. Responde `202`
   **antes** de cualquier análisis: la ingesta nunca espera al scoring.
2. Event Grid entrega el evento por webhook al motor (`ScoreTransaction`). El
   motor lee el blob crudo, consulta el historial de la cuenta en Cosmos DB
   (API MongoDB), ejecuta las cuatro reglas y persiste la decisión (puntaje,
   umbral vigente, reglas activadas) en Cosmos de forma idempotente.
3. Si el puntaje alcanza el umbral (`SCORING_THRESHOLD`, por defecto 25), el
   motor encola un mensaje `flagged-case-v1` en la Storage Queue
   `flagged-cases-production`.
4. El consumidor de la cola (dentro de `ca-cent-api`) abre el caso en
   PostgreSQL de forma idempotente (la transacción es la clave única) y solo
   borra el mensaje tras el commit.
5. El explicador (`ca-cent-explainer`) recoge los casos con explicación
   pendiente y genera una explicación determinista a partir del registro de
   scoring (plantillas por regla, sin LLM). Si el registro no alcanza para
   explicar, lo dice explícitamente en lugar de inventar.
6. Un analista (o el Lab con el rol `ANALYST`) puede adjuntar un documento de
   identidad con `POST /api/v1/verification-documents?transactionId=...`. El
   extractor lo procesa con PDFBox: si el PDF no tiene capa de texto, queda
   `ILLEGIBLE` con su motivo — no hay OCR, y eso es una decisión declarada.
7. Todo se consulta por `GET /api/v1/transactions/{id}/analysis` (registro del
   motor) y `GET /api/v1/cases/{id}` (caso, explicación y documentos).

La traza W3C (`traceparent`) viaja desde el originador por HTTP, dentro del
evento y dentro del mensaje de cola, de modo que Application Insights muestra
el recorrido completo con el mismo `trace-id`.

El contrato completo de la API está en `docs/contracts/openapi-centinela.yaml`;
los contratos de mensajería en `docs/contracts/schemas/`. Los tres archivos
son **ejecutables**: los tests de contrato verifican que el código coincide
exactamente con ellos.

## 4. Componentes de Centinela

Arquitectura hexagonal por *bounded context*: cada contexto tiene `domain/`
(modelo puro), `application/` (casos de uso y puertos) e `infrastructure/`
(adaptadores web, Azure, persistencia). Un test de ArchUnit
(`ArchitectureConventionsTest`) impide que domain/application dependan de
Spring Web o del SDK de Azure.

| Paquete (`com.centinela.`) | Responsabilidad |
|---|---|
| `transactioningestion` | `POST /api/v1/transactions` → Blob crudo + evento Event Grid. Responde 202. |
| `casemanagement` | Consumidor de la cola `flagged-cases`, apertura idempotente de casos, auditoría append-only. |
| `caseexplanation` | Worker `@Scheduled` que redacta la explicación determinista de cada caso. |
| `caseinquiry` | `GET .../analysis` y `GET /cases/{id}`, detrás de `centinela.inquiry.enabled`. |
| `documentstorage` | `POST /api/v1/verification-documents` (multipart) → Blob. |
| `documentverification` | Worker que extrae identidad del PDF (PDFBox, sin OCR). |
| `scoringrecord` | Lectura del registro que el motor dejó en Cosmos. |
| `identityaccess` | Resource server OAuth2 (validación JWT de Entra, issuer + audiencia + roles). |
| `shared` | Contratos de evento/mensaje, traza W3C, rate limiting, telemetría de etapas, manejo de errores. |

El **motor** vive en el módulo Maven independiente `scoring-function/`
(`com.centinela.scoring`): función `ScoreTransaction` con trigger Event Grid,
cuatro reglas (`VelocityRule`, `AtypicalAmountRule`, `GeoImpossibleRule`,
`RiskyMerchantRule`), umbral y listas de riesgo recargables en caliente
(`ScoringThresholdProvider`), persistencia idempotente en Cosmos y publicación
en Storage Queue. No comparte ni una línea de código con el módulo principal:
el acoplamiento es **solo por los contratos de mensaje** versionados en
`docs/contracts/schemas/`.

Endpoints y roles:

| Método y ruta | Rol requerido | Respuesta |
|---|---|---|
| `POST /api/v1/transactions` | `SERVICE` | 202 / 400 / 429 |
| `POST /api/v1/verification-documents` | `ANALYST` | 201 |
| `GET /api/v1/transactions/{id}/analysis` | `ANALYST` o `SERVICE` | 200 / 404 |
| `GET /api/v1/cases/{id}` | `ANALYST` o `SERVICE` | 200 / 404 |
| `GET /actuator/health/**` | público | 200 |

## 5. Centinela Lab: el banco de pruebas

Aplicación Spring Boot (puerto 8081) con una pantalla Thymeleaf: un botón por
escenario y un panel con lo que Centinela decidió. La ejecución es sincrónica a
propósito (10–40 s por escenario): durante una demostración es preferible que
la página cargue a tener que refrescar.

| Escenario | Qué envía | Qué se espera |
|---|---|---|
| `NORMAL` | Historial + 1 compra dentro del patrón | **No** marcada (control negativo) |
| `VELOCITY` | 4 transacciones en 4 minutos | Caso por regla de velocidad |
| `ATYPICAL_AMOUNT` | Monto ≈84× el promedio | Caso por monto atípico |
| `GEO_IMPOSSIBLE` | Medellín → Madrid en 11 minutos | Caso por geografía imposible |
| `RISKY_MERCHANT` | "Casino Royale" / `gambling` | Caso por comercio riesgoso |
| `COMBINED` | Geografía + monto a la vez | Caso con varias reglas |
| `UNREADABLE_DOCUMENT` | Fraude + PDF corrupto adjunto | Documento `ILLEGIBLE` con motivo |
| `SUSTAINED_LOAD` | Carga configurable (tope 50 tx/s, 180 s) | Escalado + `429` del rate limiter |

Detalles de diseño que importan:

- **Cada ejecución usa una cuenta nueva** (`acc-lab-<8 hex>`) y **siembra
  historial primero**: las reglas comparan contra el comportamiento previo de
  la cuenta, y sin historial el escenario probaría otra cosa.
- La carga sostenida usa transacciones inocuas con cuentas distintas para no
  ensuciar la base de casos, y cuenta los `429` aparte: son el rate limiter
  funcionando, no un error.
- El cliente HTTP trata `404` como "aún no puntuada / no marcada" (resultado
  legítimo) pero **propaga `401/403` como error**: un token sin roles no debe
  presentarse como "no marcada".
- `traceparent` W3C se genera en el Lab y se envía en cada petición: el
  recorrido en telemetría empieza en el originador.

## 6. Relación entre Centinela y Centinela Lab

- **Repositorios, imágenes, identidades y permisos separados.** El Lab es un
  cliente externo puro: habla con Centinela únicamente por la API pública con
  un token de Entra ID, igual que lo haría un banco originador real.
- **Contrato duplicado a propósito.** `TransactionPayload` en el Lab replica el
  contrato de `POST /api/v1/transactions` sin compartir código: si Centinela
  rompe el contrato, el Lab falla — que es exactamente su trabajo.
- **Infraestructura de soporte compartida** (mismo resource group, ACR, entorno
  de Container Apps y workspace de observabilidad): ver la decisión en
  [§11](#11-arquitectura-de-azure).
- La identidad del Lab (`id-cent-lab`) sostiene **dos app roles**: `SERVICE`
  (enviar transacciones, como un originador) y `ANALYST` (adjuntar el documento
  del escenario de ilegible). No se ampliaron los permisos de `SERVICE` para
  cubrir documentos: eso habría borrado la frontera de la matriz de roles.

## 7. Funcionamiento interno

**Reglas de scoring.** Cada regla devuelve puntos y los valores observados que
la activaron. La decisión persiste el umbral **vigente en ese momento**: la
respuesta de análisis expone `flagged` ya calculado en lugar de dejar que el
cliente compare, porque el umbral puede cambiar después.

**Umbral en caliente.** `SCORING_THRESHOLD`, `RISKY_MERCHANTS` y
`RISKY_CATEGORIES` se releen del entorno sin redesplegar. El valor por defecto
es **25** en el código, el emulador y el script de despliegue: el puntaje de la
regla más débil (atypical-amount = 25; velocity = 30; risky-merchant = 35;
geo-impossible = 40), porque la promesa verificada por el banco de pruebas es
que cada causal por sí sola abre un caso. Se descubrió en despliegue real: con
el antiguo umbral de 50, los cuatro escenarios de una sola regla terminaban en
"NO MARCADA".

**Idempotencia.** El motor persiste la decisión con la transacción como clave;
reintentos de Event Grid no duplican. La apertura de casos usa
`transaction_id UNIQUE` en PostgreSQL; el mensaje de cola solo se borra tras el
commit. Un mensaje indeserializable se registra y se reintenta (limitación
declarada: no hay dead-letter todavía).

**Rate limiting.** Token bucket por IP solo en `POST /api/v1/transactions`
(`CENTINELA_RATELIMIT_CAPACITY` / `_REFILL_MS`), responde `429`.

**Explicación determinista.** Plantillas por regla a partir del registro de
scoring. Si el registro no alcanza (`InsufficientDecisionRecordException`), el
caso lo dice en vez de inventar.

**Trazas.** `TracePropagationFilter` (orden máximo) captura o genera el
`traceparent` y lo propaga a blob, evento, mensaje y logs
(`stage=INGEST_API|RAW_PERSIST|EVENT_PUBLISH|...` con `traceId`).

## 8. Persistencia

| Almacén | Contenido | Acceso |
|---|---|---|
| PostgreSQL Flexible Server (privado) | Casos, auditoría append-only, documentos de verificación | JDBC **sin contraseña**: plugin `azure-identity-extensions` + Managed Identity; usuario `cent_apps` |
| Cosmos DB for MongoDB | Transacciones + registro de scoring | Connection string en Key Vault (`cosmos-mongo-connection-string`), referenciada como `keyvaultref`/`secretref` |
| Blob Storage | JSON crudo (`raw-transactions-*`), documentos (`verification-documents-*`) | Managed Identity |
| Storage Queue | `flagged-cases-*` (buffer motor → casos) | Managed Identity |

Migraciones con Flyway (`src/main/resources/db/migration/V1..V4`): esquema de
casos, auditoría inmutable (trigger que rechaza UPDATE/DELETE), alineación del
modelo y tablas de explicación/documentos. `ddl-auto: validate` — Hibernate
nunca toca el esquema.

## 9. Seguridad e identidad

- **Cero secretos en el repositorio y en las imágenes.** `.env` está fuera de
  git; el escaneo (`scan-repository.sh` + `audit-git-secrets.sh`) corre como
  gate del CI; `verify-image-secrets.sh` audita las capas de la imagen. La
  única credencial que existe (Cosmos) vive en Key Vault.
- **Managed Identity para todo el plano de datos**: Blob, Queue, Event Grid,
  PostgreSQL y el host de Functions autentican con la identidad
  `id-cent-apps`; el registro de contenedores con `id-cent-acrpull` (Centinela)
  e `id-cent-lab` (el Lab). `AZURE_CLIENT_ID` selecciona la identidad cuando el
  contenedor tiene varias.
- **API protegida por Entra ID**: resource server JWT, validación de issuer,
  audiencia (el appId pelado — los tokens v2 no llevan el prefijo `api://`) y
  app roles (`SERVICE`, `ANALYST`). El perfil `local` desactiva la seguridad
  con un aviso a gritos, solo para docker-compose.
- **Matriz de roles**: `SERVICE` ingesta y consulta; `ANALYST` documentos y
  consulta. Conceder un app role exige rol de directorio (Application
  Administrator o propietario de la app) y es un paso de aprovisionamiento
  humano, nunca del pipeline.

## 10. Configuración del entorno local

Requisitos: Docker Desktop (o Docker + Compose v2). Nada más — la imagen se
construye dentro de compose.

```bash
cd Centinela
./start.sh            # levanta Azurite, PostgreSQL, Mongo, API y explicador
# API en http://localhost:8080 (perfil local: seguridad desactivada)
./stop.sh             # apaga y BORRA volúmenes (--keep para conservarlos)
```

En local no existe Event Grid ni el motor: `scripts/local/simulate-scoring.sh`
simula ese tramo (escribe el registro en Mongo y encola el mensaje de caso).

El Lab en local:

```bash
cd centinela-lab
cp .env.example .env   # apuntar CENTINELA_BASE_URL y CENTINELA_SCOPE al destino
mvn spring-boot:run    # http://localhost:8081
```

Perfiles de Spring: `default` (Azure), `local` (docker-compose), `test` (H2 en
memoria, sin Azure).

## 11. Arquitectura de Azure

**Decisión: un único grupo de recursos (`rg-centinela`) compartido por
Centinela y el Lab**, con separación lógica por nombres. Motivos:

1. El Lab existe para probar **esta** plataforma; su ciclo de vida es el mismo
   y destruir el grupo debe llevárselo también.
2. Duplicar ACR, entorno de Container Apps y Log Analytics costaría dinero y
   **rompería la traza de extremo a extremo** (dos workspaces no correlacionan
   solos), sin aportar aislamiento real: el aislamiento que importa — código,
   identidad, permisos, pipeline — ya está garantizado por repositorios,
   identidades y roles separados.
3. Una sola superficie de operación (apagado, monitoreo, costos).

Topología: **Azure Container Apps** (plan Consumption). La alternativa App
Service quedó descartada (ADR-009) y además bloqueada por cuota
(`SubscriptionIsOverQuotaForSku`, límite de VMs = 0 en suscripciones nuevas).

Los nombres se **derivan**, no se escriben: sufijo
`hash = sha1(NAME_PREFIX|SUBSCRIPTION_ID|RESOURCE_GROUP)[0:6]`. Con
`cent` / `rg-centinela` en la suscripción del proyecto: `79d78c`.

| Recurso | Nombre | Notas |
|---|---|---|
| Resource group | `rg-centinela` | todo el sistema |
| VNet | `cent-vnet-week1` | subred de infraestructura ACA + subred de private endpoints |
| Storage | `centst79d78c` | blobs crudos, documentos, colas, host de Functions |
| Cosmos DB (Mongo) | `cent-cosmos-79d78c` | Free Tier, consistencia Session, TTL 90 días |
| PostgreSQL Flexible | `cent-pg-79d78c` | privado, solo autenticación Entra |
| Key Vault | `cent-kv-79d78c` | secreto de Cosmos + system keys del host Functions |
| Event Grid topic | `cent-egt-79d78c` | eventos de transacción |
| Container Registry | `centacr79d78c` | Basic; pull por Managed Identity, admin deshabilitado. Lleva el hash porque el nombre es DNS global (`centacr` a secas ya estaba tomado por un tercero) |
| Entorno ACA | `cae-cent` | + Log Analytics `cent-logs` y App Insights `appi-cent` |
| Identidades | `id-cent-apps`, `id-cent-acrpull`, `id-cent-lab` | datos / pull / lab |
| App Entra (API) | `cent-api-week1` | app roles `SERVICE`, `ANALYST`, `ADMIN`, `AUDITOR` |
| App Entra (OIDC) | para GitHub Actions | federada con ambos repositorios |
| Container Apps | `ca-cent-api`, `ca-cent-scoring`, `ca-cent-explainer`, `ca-cent-lab` | |

Escalado (ADR-010): la API por concurrencia HTTP, el motor por concurrencia de
eventos, el explicador por réplicas fijas mínimas, el Lab de 0 a 2 réplicas
(escala a cero: es una herramienta de demostración).

## 12. Despliegue desde cero

Reproduce el sistema completo en una suscripción de Azure limpia, desde
cualquier equipo (Windows con Git Bash, macOS o Linux). No requiere Docker
local: las imágenes se construyen dentro de Azure con `az acr build`.

### 12.1 Requisitos

| Herramienta | Verificación | Instalación (Windows con winget) |
|---|---|---|
| Azure CLI ≥ 2.60 | `az version` | `winget install Microsoft.AzureCLI` |
| Git (incluye Git Bash) | `git --version` | `winget install Git.Git` |
| Cliente PostgreSQL (`psql`) | `psql --version` | `winget install PostgreSQL.PostgreSQL.17` |
| curl | `curl --version` | incluido en Windows/Git Bash |

En Windows, todos los comandos de esta sección se ejecutan en **Git Bash**.
`psql` no se agrega solo al `PATH`; los scripts lo detectan en
`C:\Program Files\PostgreSQL\<ver>\bin` automáticamente.

Permisos necesarios de la cuenta que despliega:

- **Owner** (o Contributor + User Access Administrator) sobre la suscripción.
- **Application Administrator** en el directorio de Entra (crear apps y
  conceder app roles).

### 12.2 Clonar y configurar

```bash
git clone https://github.com/Centinela-App/Centinela.git
git clone https://github.com/Centinela-App/centinela-lab.git   # al lado
cd Centinela
cp .env.example .env
```

Editar `.env`:

```env
SUBSCRIPTION_ID="<uuid de la suscripción>"
LOCATION="eastus2"
RESOURCE_GROUP="rg-centinela"
NAME_PREFIX="cent"        # 3-11 minúsculas/números; prefijo de TODOS los nombres
```

```bash
az login
az account set --subscription "<uuid de la suscripción>"
```

### 12.3 Desplegar la plataforma completa (un comando)

```bash
CENTINELA_ALERT_EMAIL="tu@correo" bash scripts/deploy-platform.sh --yes --with-lab
```

El orquestador es **idempotente** (si falla un paso, se corrige la causa y se
vuelve a ejecutar; converge sin duplicar) y deja el registro de cada paso en
`deploy-run/<timestamp>/`. Secuencia que ejecuta:

1. Registro de resource providers que falten (suscripciones nuevas no los tienen).
2. Grupo de recursos y red privada (subred ACA /23 + subred de private endpoints).
3. Storage (contenedores y colas de producción y staging).
4. Cosmos DB Mongo (privado, free tier) y PostgreSQL Flexible (privado, solo Entra).
5. Key Vault (RBAC) y secreto de Cosmos.
6. Identidad de datos `id-cent-apps` (primera pasada: Storage y Key Vault).
7. Event Grid topic + colas; **segunda pasada** de la identidad (ahora existe
   el tópico y recibe `EventGrid Data Sender` — sin esta repetición la ingesta
   fallaría con 403 silencioso).
8. Storage privado del host de Functions; registro Entra `cent-api-week1` con
   sus app roles; bootstrap de PostgreSQL (crea el rol `cent_apps` para
   Managed Identity; si la máquina no está en la VNet, abre una ventana de
   firewall acotada a tu IP y la cierra con `trap`, con `password-auth`
   siempre deshabilitado).
9. ACR + identidad de pull; entorno de Container Apps con Log Analytics.
10. Observabilidad (App Insights, alerta al correo indicado).
11. `az acr build` de las dos imágenes (API y motor) dentro de Azure.
12. `deploy-containers.sh`: crea/actualiza las tres Container Apps, espera el
    arranque del host de Functions, recupera su system key del Key Vault
    (lectura temporal conceder-usar-revocar) y **cablea la suscripción de
    Event Grid** hacia el webhook del motor.
13. Verificación de salud (`/actuator/health/readiness`).
14. Con `--with-lab`: ejecuta `scripts/deploy-lab.sh` del repositorio vecino —
    identidad `id-cent-lab`, app roles `SERVICE`+`ANALYST`, AcrPull, imagen y
    Container App del banco de pruebas.

> El primer despliegue DEBE ser interactivo (una persona con `az login`): el
> cableado de Event Grid necesita leer temporalmente la system key del vault y
> la concesión de app roles exige permisos de directorio. El pipeline queda
> para los despliegues siguientes, con `--skip-role --skip-acrpull`.

### 12.4 Verificar el sistema

```bash
# Salud de la API
API_FQDN=$(az containerapp show -g rg-centinela -n ca-cent-api \
  --query properties.configuration.ingress.fqdn -o tsv)
curl -s "https://$API_FQDN/actuator/health/readiness"   # {"status":"UP"}

# Banco de pruebas
LAB_FQDN=$(az containerapp show -g rg-centinela -n ca-cent-lab \
  --query properties.configuration.ingress.fqdn -o tsv)
echo "https://$LAB_FQDN"    # abrir en el navegador y ejecutar escenarios
```

Prueba completa desde la línea de comandos (sin navegador):

```bash
curl -s -X POST "https://$LAB_FQDN/escenarios/VELOCITY" | grep -o 'CASO ABIERTO\|NO MARCADA'
bash scripts/verify/run-e2e-fraud.sh    # E2E transacción→caso desde Centinela
```

### 12.5 Configurar el CI/CD (una vez)

Ver [§13](#13-cicd). Resumen de la parte de aprovisionamiento:

```bash
# App OIDC federada con AMBOS repositorios + roles AcrPush/Contributor
CENTINELA_GITHUB_REPO="Centinela-App/Centinela,Centinela-App/centinela-lab" \
  bash scripts/provision-github-oidc.sh
```

El script imprime `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` y
`AZURE_SUBSCRIPTION_ID` para copiarlos como **secrets** en ambos repositorios
(Settings → Secrets and variables → Actions), y las **variables** necesarias:

| Variable | Centinela | centinela-lab |
|---|---|---|
| `AZURE_RESOURCE_GROUP` | `rg-centinela` | `rg-centinela` |
| `AZURE_LOCATION` | `eastus2` | `eastus2` |
| `NAME_PREFIX` | `cent` | `cent` |
| `APP_SERVICE_SKU` | `S1` (legado, requerido por el validador de parámetros) | — |
| `AZURE_DEPLOY_ENABLED` | `true` para habilitar el CD | — |
| `DESPLIEGUE_HABILITADO` | — | `true` para habilitar el CD |
| `CENTINELA_ENTRA_APP_ID` | — | appId de `cent-api-week1` |

### 12.6 Destruir todo

```bash
bash scripts/destroy-week1.sh --wait   # pide confirmación tecleada
# El Key Vault queda en soft-delete 90 días; para reutilizar el nombre:
az keyvault purge --name cent-kv-<hash> --location eastus2
```

## 13. CI/CD

Ambos repositorios usan **GitHub Actions con OIDC federado**: el pipeline no
guarda ninguna credencial de Azure — `azure/login@v2` intercambia el token del
workflow por una sesión del service principal cuya credencial federada declara
`repo:<org/repo>:ref:refs/heads/main`. Los "secrets" (`AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) son identificadores, no claves.

### Centinela (`.github/workflows/ci.yml` y `cd.yml`)

- **CI** (PRs y ramas): `mvn verify` de ambos módulos, barrido de secretos
  (`scan-repository.sh` + `audit-git-secrets.sh` sobre el historial),
  shellcheck bloqueante a nivel error.
- **CD** (push a `main` o manual): reusa el CI, publica `centinela-api` y
  `centinela-scoring` en ACR (buildx, cache de GitHub, sin build-args de
  secretos), audita las capas (`verify-image-secrets.sh`), despliega con
  `deploy-containers.sh --tag <sha>` en el environment `produccion` y verifica
  salud. Interruptor: variable `AZURE_DEPLOY_ENABLED`.

### centinela-lab (`.github/workflows/ci-cd.yml`)

- Job `pruebas`: `mvn verify`, chequeo de credenciales versionadas, shellcheck.
- Job `desplegar` (push a `main` con `DESPLIEGUE_HABILITADO=true`, o manual
  desde `main`): login OIDC, instala la extensión `containerapp` y ejecuta
  `deploy-lab.sh --yes --skip-role --skip-acrpull --tag <sha>`.

Por qué los dos `--skip`:

- `--skip-role`: conceder app roles exige escritura en el directorio
  (`AppRoleAssignment.ReadWrite.All`). Dárselo al SP del pipeline significaría
  que quien edite el workflow puede autoconcederse roles.
- `--skip-acrpull`: escribir una asignación RBAC exige
  `Microsoft.Authorization/roleAssignments/write`; el SP solo tiene
  `AcrPush` + `Contributor` (Contributor **no** incluye ese permiso).

Ambas concesiones las hace una persona una única vez, ejecutando
`deploy-lab.sh` sin los skips (o vía `deploy-platform.sh --with-lab`).

El job de despliegue del Lab tiene concurrencia propia **sin** cancelación
(abortar un update de Container Apps a medias deja el entorno en estado
desconocido) y `id-token: write` solo en ese job.

## 14. Ejecución de pruebas

```bash
# Centinela — módulo principal (unitarias + integración con H2 + ArchUnit + contrato)
mvn -B -ntp verify
# Motor
mvn -B -ntp -f scoring-function/pom.xml verify
# Integración contra Azure real (opcional, requiere sesión y recursos)
CENTINELA_RUN_AZURE_IT=1 mvn verify

# Lab
cd ../centinela-lab && mvn -B -ntp verify

# Gates de repositorio
bash scripts/tests/scan-repository.sh       # secretos en el árbol
bash scripts/tests/audit-git-secrets.sh     # secretos en el historial
bash scripts/verify/verify-practices.sh     # convenciones estructurales

# Contra el entorno desplegado
bash scripts/verify/verify-deployment-health.sh
bash scripts/verify/run-e2e-fraud.sh        # transacción → caso, extremo a extremo
bash scripts/verify/verify-trace.sh <txId>  # traza completa en App Insights
bash scripts/tests/test-threshold-hot-reload.sh
bash scripts/tests/test-analyst-rbac.sh
```

Cobertura: 26 clases / ~104 tests en el módulo principal (incluye 5 reglas de
ArchUnit y 3 tests de contrato contra `docs/contracts/`), 11 clases / 31 tests
en el motor, y los tests de `TransactionFactory` en el Lab (verifican que cada
escenario genera de verdad la forma de tráfico que promete).

## 15. Observabilidad

- Agente Java de Application Insights horneado en la imagen
  (`applicationinsights.json`; la connection string llega por variable de
  entorno, nunca en la imagen). `cloud_RoleName` por `CENTINELA_ROLE_NAME`:
  `centinela-api`, `centinela-scoring`, `centinela-explainer`.
- Telemetría de etapas del pipeline en logs estructurados:
  `stage=<ETAPA> transactionId=… traceId=… durationMs=… outcome=…`.
- Consultas KQL de operación (guardadas del trabajo previo — ejecutar en el
  App Insights del grupo):

```kusto
// ¿Dónde se corta el pipeline para una transacción?
union traces, requests, dependencies
| where operation_Id == '<traceId>'
| order by timestamp asc

// Latencia por etapa (P50/P95) en la última hora
traces
| where message startswith 'stage='
| parse message with 'stage=' stage ' transactionId=' txId ' traceId=' tid ' durationMs=' dur:long ' outcome=' outcome
| summarize p50=percentile(dur,50), p95=percentile(dur,95), total=count() by stage

// Tasa de 429 (rate limiter) por 5 minutos
requests | where resultCode == 429 | summarize count() by bin(timestamp, 5m)
```

- Alerta de disponibilidad al correo de `CENTINELA_ALERT_EMAIL`
  (`provision-observability.sh`).

## 16. Operación y costos

La plataforma cuesta ≈4–5 USD/día encendida (Container Apps mínimos, PostgreSQL
B1ms, Log Analytics; Cosmos free tier y ACR Basic son fijos menores).

```bash
bash scripts/shutdown-daily.sh          # réplicas a 0 y PostgreSQL detenido
bash scripts/shutdown-daily.sh --start  # revierte
bash scripts/destroy-week1.sh --wait    # elimina TODO el grupo
```

El Lab escala a cero solo. **Atención**: su UI es pública y sin autenticación
(decisión de demostración); el generador de carga está acotado (50 tx/s,
180 s) precisamente para que nadie pueda quemar el crédito desde el navegador.

## 17. Decisiones de arquitectura (ADR)

Resumen de las decisiones vigentes (las catorce originales se consolidaron
aquí; el historial completo vive en el historial de git):

| ADR | Decisión |
|---|---|
| 001 | Arquitectura hexagonal por bounded context; entidades JPA en infraestructura |
| 002 | Red privada: subred ACA + subred de private endpoints; datos sin acceso público |
| 003 | Mínimo privilegio por app role (`SERVICE` no carga documentos) |
| 004 | Disponibilidad vs costo: réplicas mínimas bajas, escalado por demanda |
| 005 | Managed Identity desde el día uno; el único secreto (Cosmos) vive en Key Vault |
| 006 | Java 21 + Spring Boot; motor como módulo Maven independiente |
| 007 | Cosmos DB for MongoDB para transacciones/scoring (partición por cuenta, TTL) |
| 008 | GitHub Actions con OIDC federado; sin credenciales en el pipeline |
| 009 | **Azure Container Apps**, no App Service (cuota 0 de VMs; contenedores ya existentes) |
| 010 | Métrica de escalado propia por componente (HTTP para API, eventos para el motor) |
| 011 | ACR Basic con pull por Managed Identity (pagar por no tener un secreto) |
| 012 | El contexto de traza viaja DENTRO del mensaje (evento y cola), no en cabeceras |
| 013 | El primer cuello es el consumidor de la cola; visibilidad y poll ajustados |
| 014 | Registro de lecciones: ver historial de git |

## 18. Registro de seguridad

- **Incidente histórico**: un commit temprano (`3ea6b91`) versionó `.env` con
  el identificador de una suscripción anterior. Remediación aplicada: rotación
  (la suscripción actual es otra), `.gitignore` + doble gate de escaneo en CI
  (árbol e historial con gitleaks si está instalado), y política de GUIDs
  enmascarados en cualquier registro versionado. La reescritura del historial
  se evaluó y se descartó por costo operativo: el dato expuesto es un
  identificador, no una credencial.
- Gates activos: `scan-repository.sh` (árbol), `audit-git-secrets.sh`
  (historial), `verify-image-secrets.sh` (capas de imagen), chequeo de `.env`
  versionado en ambos pipelines.
- Ventana de PostgreSQL: el bootstrap puede abrir acceso público **acotado a la
  IP del operador** y lo revierte con `trap`; `password-auth` permanece
  deshabilitado siempre. `CENTINELA_ALLOW_PUBLIC_WINDOW=0` la prohíbe.
