# Centinela — Resumen de la Semana 1

> Documento pedagógico y resumido de **qué se ha construido hasta la fecha**, con foco
> en los **servicios de Azure**, los **scripts** que los crean/validan, y **dónde vive
> cada acción en el código** (para que puedas ir directo al archivo que la implementa).

---

## 1. En una frase

Centinela es un motor de detección de fraude transaccional sobre Azure. En la **Semana 1**
todavía **no detecta fraude**: se construyeron los *cimientos* — la infraestructura en la
nube, la identidad, la red privada y la puerta de entrada (API) que **recibe y almacena**
transacciones y documentos. El análisis (scoring, casos, IA) llega en las semanas 2 y 3.

> Analogía: esta semana se construyó **la bóveda antes de meter el dinero**. La API recibe
> una transacción, responde de inmediato con un acuse, y la guarda intacta — sin leerla ni
> juzgarla todavía.

---

## 2. Los servicios de Azure implementados

Toda la infraestructura se crea **por script** (nunca a mano en el portal) y se consume
**sin secretos** (vía Managed Identity). Cada servicio se clasifica por su modelo de nube:

| Servicio de Azure | Modelo | Para qué sirve en Centinela | Issue |
|---|---|---|---|
| **App Service** (Web App + slot `staging`) | PaaS | Corre la aplicación Java/Spring Boot. Es donde vive la API. | ISS-004 |
| **Blob Storage** | PaaS | Guarda el JSON crudo de transacciones y los documentos de verificación. | ISS-003 |
| **Queue Storage** | PaaS | Cola *buffer* para absorber picos de transacciones (aún sin consumidor). | ISS-003/010 |
| **Microsoft Entra ID** | SaaS | Emite y valida los tokens de identidad (roles Servicio/Analista/Admin/Auditor). | ISS-006 |
| **Managed Identity** | PaaS | La “credencial sin contraseña” con la que la app habla con Blob/Queue. | ISS-004/006 |
| **VNet + subredes + Private Endpoints + DNS privado** | IaaS (red) | La red privada que **aísla el almacenamiento de internet**. | ISS-005 |

> **Regla de oro del diseño:** el único componente que la célula administra a mano es la
> **red**. Todo lo demás (cómputo, almacenamiento, identidad) es servicio gestionado.
> No hay VMs ni Kubernetes en Semana 1 — decisión deliberada de costo y seguridad.

### 2.1 Cómo se explican uno por uno

**App Service — la casa de la API.**
Azure gestiona el sistema operativo, el runtime de Java y los parches; la célula solo sube
el `.jar`. Tiene un *slot* `staging` separado de producción, con su propia configuración,
para probar sin tocar el ambiente real. Soporta escalar a más instancias (se usa en la
prueba de alta disponibilidad).
*Se crea en:* `scripts/provision-app-service.sh`. *Se despliega el `.jar` con:* `scripts/deploy-application.sh`.

**Blob Storage — el archivador.**
Dos tipos de contenido en 4 contenedores separados por ambiente:
- `raw-transactions-{staging,production}` → el JSON original de cada transacción.
- `verification-documents-{staging,production}` → los archivos (cédulas, extractos) que
  suben los analistas.
El acceso público está **deshabilitado**: no existe una URL desde internet que alguien
pueda golpear.
*Se crea en:* `scripts/provision-storage.sh`. *Se escribe desde el código en:*
`transactioningestion/infrastructure/azure/blob/AzureRawTransactionBlobAdapter.java` y
`documentstorage/infrastructure/azure/blob/AzureVerificationDocumentBlobAdapter.java`.

**Queue Storage — la sala de espera.**
Dos colas (`transactions-ingestion-{staging,production}`). Su propósito futuro es amortiguar
ráfagas de transacciones. En Semana 1 **solo se valida técnicamente** (se escribe, lee y
borra un mensaje de prueba); ningún componente de negocio la consume todavía.
*Se crea en:* `scripts/provision-storage.sh`. *Se valida en:* `scripts/validate-queue.sh`.

**Entra ID — el portero de identidades.**
Define 4 *app roles* (Servicio, Analista, Administrador, Auditor) con **mínimo privilegio**:
cada uno puede exactamente lo que necesita y nada más. Ejemplo: el rol **Servicio** solo
puede invocar `POST /api/v1/transactions`; no puede leer ni administrar.
*Se crea en:* `scripts/provision-entra-app.sh`. *Se valida el token en el código en:*
`identityaccess/SecurityConfiguration.java` + `identityaccess/EntraRolesJwtAuthenticationConverter.java`.

**Managed Identity — la llave sin contraseña.**
En vez de guardar una connection string en el código, el App Service recibe una identidad
propia de Azure. El código usa `DefaultAzureCredential` y obtiene un token automáticamente.
Resultado: **cero secretos en el repositorio** para acceder a los datos.
*Se activa en:* `scripts/provision-app-service.sh`. *Se le asignan permisos en:* `scripts/assign-rbac.sh`.
*Se usa desde el código en:* los adaptadores `azure/blob/*Adapter.java` y su cableado `infrastructure/config/*Configuration.java`.

**Red privada — el túnel blindado.**
```
Internet ──HTTPS 443──▶ App Service ──VNet──▶ snet-app-integration
                                                     │ (tráfico privado)
                                                     ▼
                                          snet-private-endpoints
                                                     │ Private Endpoint + DNS privado
                                                     ▼
                                          Storage Account (público: Disabled)
```
La app alcanza el Storage **solo** por una IP privada dentro de la VNet. Los NSG deniegan
todo lo no permitido explícitamente. Esta red ya queda lista para recibir las bases de datos
de Semana 2 bajo la misma restricción.
*Se crea en:* `scripts/provision-network.sh` + `scripts/configure-private-endpoints.sh`.

---

## 3. El código de la aplicación — dónde vive cada acción

La app es **Java 21 + Spring Boot** con **arquitectura hexagonal**. La regla clave para
encontrar las cosas: la dependencia va **`domain` ← `application` ← `infrastructure`**, y
**solo `infrastructure` puede tocar Azure o Spring Web**. Entonces:

- ¿Buscas una **regla de negocio pura**? → `domain/`
- ¿Buscas **qué hace el sistema** (orquestación, contratos/puertos)? → `application/`
- ¿Buscas el **cómo técnico** (HTTP, Azure, JSON)? → `infrastructure/`

### 3.1 Mapa de carpetas

```
src/main/java/com/centinela/
├── CentinelaApplication.java          # arranque de Spring Boot (main)
├── transactioningestion/              # MÓDULO: ingesta de transacciones (Flujo A)
│   ├── domain/model/                  #   Transaction, Location, Merchant (reglas puras)
│   ├── application/                    #   casos de uso + puertos (in/out) + comandos
│   └── infrastructure/                #   web (controller/DTO/mapper) + azure/blob + config
├── documentstorage/                   # MÓDULO: carga de documentos (Flujo B)
│   ├── domain/model/                  #   VerificationDocument
│   ├── application/                    #   caso de uso + puertos + validación/normalización
│   └── infrastructure/                #   web (controller/DTO) + azure/blob + config
├── identityaccess/                    # MÓDULO: seguridad HTTP (Flujo C — JWT + roles)
└── shared/web/                        # transversal: manejo de errores (400/503)
src/main/resources/
├── application.yml                    # config base + actuator + parámetros de seguridad Entra
└── application-test.yml               # perfil de prueba (arranca SIN Azure)
src/test/java/com/centinela/architecture/
└── ArchitectureConventionsTest.java   # test que IMPIDE romper los límites de capas
```

### 3.2 Flujo A — Ingestar una transacción (`POST /api/v1/transactions`)

Ruta base: `src/main/java/com/centinela/transactioningestion/`

| Paso / acción | Archivo | Capa |
|---|---|---|
| Recibe el `POST`, valida el JSON y responde `202` tras persistir | `infrastructure/web/TransactionController.java` | infra · web |
| Forma del payload y validaciones de campos (obligatorios, rangos) | `infrastructure/web/dto/TransactionRequest.java`, `LocationRequest.java`, `MerchantRequest.java` | infra · web |
| Convierte el DTO de entrada → comando de aplicación | `infrastructure/web/mapper/TransactionWebMapper.java` | infra · web |
| Contrato del caso de uso (puerto de entrada) | `application/port/in/IngestTransactionUseCase.java` | application |
| Comando de entrada al caso de uso | `application/command/IngestTransactionCommand.java` | application |
| **Orquesta: persiste ANTES de devolver el acuse** | `application/service/IngestTransactionService.java` | application |
| Contrato de almacenamiento (puerto de salida) | `application/port/out/RawTransactionStoragePort.java` | application |
| **Escribe el JSON en Azure Blob** (usa Managed Identity) | `infrastructure/azure/blob/AzureRawTransactionBlobAdapter.java` | infra · azure |
| Construye la ruta UTC `yyyy/MM/dd/{transactionId}.json` | `infrastructure/azure/blob/BlobPathFactory.java` | infra · azure |
| Cableado: cliente Blob + contenedor del ambiente | `infrastructure/config/TransactionIngestionConfiguration.java`, `azure/blob/RawTransactionBlobProperties.java` | infra · config |
| Modelo de dominio puro | `domain/model/Transaction.java`, `Location.java`, `Merchant.java` | domain |
| Acuse de respuesta (`transactionId` + `RECEIVED`) | `infrastructure/web/dto/TransactionReceiptResponse.java` | infra · web |
| Error si Blob no está disponible → mapea a `503` | `application/exception/StorageUnavailableException.java` | application |

### 3.3 Flujo B — Cargar un documento (`POST /api/v1/verification-documents`)

Ruta base: `src/main/java/com/centinela/documentstorage/`

| Paso / acción | Archivo |
|---|---|
| Recibe el multipart (campo `file`) y responde `201` | `infrastructure/web/VerificationDocumentController.java` |
| **Valida no-vacío, normaliza el nombre (anti `../` / path traversal) y genera `documentId`** | `application/service/StoreVerificationDocumentService.java` |
| Puerto de entrada / puerto de salida | `application/port/in/StoreVerificationDocumentUseCase.java`, `application/port/out/VerificationDocumentStoragePort.java` |
| Comando de entrada | `application/command/StoreVerificationDocumentCommand.java` |
| **Escribe el archivo en el Blob de documentos** | `infrastructure/azure/blob/AzureVerificationDocumentBlobAdapter.java` |
| Cableado del adaptador | `infrastructure/config/DocumentStorageConfiguration.java` |
| Modelo de dominio | `domain/model/VerificationDocument.java` |
| Acuse `201` (`documentId` + `STORED`) | `infrastructure/web/dto/DocumentReceiptResponse.java` |
| Errores `400` (archivo inválido) / `503` (Blob caído) | `application/exception/InvalidVerificationDocumentException.java`, `DocumentStorageUnavailableException.java` |

### 3.4 Flujo C — Seguridad: quién puede llamar a qué

Ruta base: `src/main/java/com/centinela/identityaccess/`

| Acción | Archivo |
|---|---|
| **Reglas de acceso**: `/transactions`→`ROLE_SERVICE`, `/verification-documents`→`ROLE_ANALYST`, `health/info` público; valida el JWT (firma, issuer y audience) | `SecurityConfiguration.java` |
| **Traduce el claim `roles` de Entra → `ROLE_*`** (solo reconoce los 4 roles previstos; ignora cualquier otro) | `EntraRolesJwtAuthenticationConverter.java` |
| Respuesta `401` (sin token) sin filtrar detalles del token | `RestAuthenticationEntryPoint.java` |
| Respuesta `403` (token válido, rol incorrecto) sin filtrar detalles | `RestAccessDeniedHandler.java` |
| Valores de issuer/audience/JWK se inyectan por variables de entorno (no secretos versionados) | `src/main/resources/application.yml` |

### 3.5 Transversal y arranque

| Acción | Archivo |
|---|---|
| Convierte errores de entrada en respuestas seguras (`400`/`503`) sin stack trace | `shared/web/ApiExceptionHandler.java` |
| Forma del cuerpo de error (`code` + `message`) | `shared/web/ErrorResponse.java` |
| `main()` que arranca Spring Boot | `CentinelaApplication.java` |
| Config base, endpoints de salud y parámetros de seguridad | `src/main/resources/application.yml` |
| Perfil de prueba que arranca **sin** conectarse a Azure | `src/main/resources/application-test.yml` |
| Test que **impide** que `domain`/`application` toquen Spring Web o el SDK de Azure | `src/test/java/com/centinela/architecture/ArchitectureConventionsTest.java` |

---

## 4. Los scripts

Todos en Bash + Azure CLI. Diseño en capas: una **librería compartida**, unos **orquestadores**,
los **scripts de provisión** por servicio, y una batería de **pruebas/validaciones**.

### 4.1 Librería compartida (`scripts/lib/`)

| Script | Qué hace |
|---|---|
| `common.sh` | Utilidades base: logging con colores (`log_info/warn/error`), `die` (salir con error), `mask` (oculta secretos mostrando solo primeros/últimos 4 caracteres), `require_cmd` (verifica dependencias), `with_retry` (reintentos con backoff). |
| `parameters.sh` | Carga el `.env` y **valida** los 5 parámetros obligatorios (`SUBSCRIPTION_ID`, `LOCATION`, `RESOURCE_GROUP`, `NAME_PREFIX`, `APP_SERVICE_SKU`) con sus formatos, antes de tocar Azure. |

### 4.2 Orquestadores (`scripts/`)

| Script | Qué hace |
|---|---|
| `deploy-week1.sh` | Orquestador de despliegue. Valida parámetros *offline*, verifica sesión y suscripción de Azure, crea el Resource Group y ejecuta en orden los `provision-*`. |
| `destroy-week1.sh` | Elimina el Resource Group completo, exigiendo teclear su nombre exacto como confirmación (o `--yes` en automatización). |
| `validate-week1.sh` | Valida el entorno (parámetros, sesión, región, SKU) sin crear ni destruir nada. |

### 4.3 Provisión por servicio (`scripts/`)

| Script | Servicio que crea | Issue |
|---|---|---|
| `provision-storage.sh` | Storage Account + 4 contenedores + 2 colas (idempotente, vía plantilla ARM, acceso público off). | ISS-003 |
| `provision-app-service.sh` | App Service Plan + Web App + slot `staging` + Managed Identity. | ISS-004 |
| `deploy-application.sh` | Despliega el artefacto Java en el App Service. | ISS-004 |
| `provision-network.sh` | VNet + `snet-app-integration` + `snet-private-endpoints`. | ISS-005 |
| `configure-private-endpoints.sh` | Private Endpoints (Blob y Queue) + zonas DNS privadas. | ISS-005 |
| `provision-entra-app.sh` | App Registration en Entra ID + los 4 app roles. | ISS-006 |
| `assign-rbac.sh` | Asignaciones RBAC mínimas (rol de datos de Blob a la Managed Identity). | ISS-006 |
| `validate-queue.sh` | Roundtrip técnico de la cola: escribe, lee y borra un mensaje de prueba. | ISS-010 |
| `test-ha.sh` | Prueba de alta disponibilidad: escala a 2 instancias, retira una, verifica continuidad y vuelve a 1. | ISS-012 |

### 4.4 Pruebas y validaciones (`scripts/tests/`)

| Script | Verifica | Prueba |
|---|---|---|
| `scan-repository.sh` | Que no haya secretos, cadenas de conexión **ni GUIDs reales** versionados. | TEST-S1-002 |
| `test-deploy-parameters.sh` | Que el despliegue falle *antes de Azure* si falta un parámetro. | TEST-S1-003 |
| `test-destroy-safety.sh` | Que la destrucción rechace una confirmación equivocada. | TEST-S1-004 |
| `validate-storage.sh` | Storage + contenedores + colas + propiedades de seguridad. | TEST-S1-005 |
| `validate-app-service.sh` | Web App, slot y Managed Identity activos. | TEST-S1-006 |
| `validate-network.sh` | Red privada y resolución DNS. | TEST-S1-007 |
| `validate-entra-roles.sh`, `validate-rbac.sh`, `test-analyst-rbac.sh`, `validate-managed-identity.sh` | Los 4 roles, mínimo privilegio y que el Analista no pueda modificar recursos. | TEST-S1-008/009/010 |
| `test-queue-roundtrip.sh` | Roundtrip de la cola. | TEST-S1-020 |
| `send-transaction-load.sh`, `reconcile-accepted-transactions.sh` | Carga continua y reconciliación de cada `202` con su Blob (HA). | TEST-S1-024 |
| `test-transaction-e2e.sh`, `test-environment-isolation.sh` | Ingesta E2E y aislamiento staging/production. | ISS-008 |
| `test-document-upload-e2e.sh` | Carga de documento desde la API. | ISS-009 |
| `validate-documentation.sh`, `validate-week1-scope.sh` | Entregables documentales y que no se coló alcance de Semana 2. | ISS-013 |
| `test-clean-deploy.sh`, `test-destroy-rebuild-cleanup.sh` | Reconstrucción desde cero y ciclo destruir/reconstruir/limpiar. | TEST-S1-026/027 |

---

## 5. Cómo encaja todo

### 5.1 Flujo de despliegue (infraestructura)

```
1. deploy-week1.sh valida parámetros (offline) y sesión de Azure
2. Crea el Resource Group
3. provision-storage.sh          → Storage + contenedores + colas
4. provision-app-service.sh      → App Service + slot + Managed Identity
5. provision-network.sh          → VNet + subredes
6. configure-private-endpoints.sh→ Private Endpoints + DNS privado
7. provision-entra-app.sh        → App Registration + app roles
8. assign-rbac.sh                → RBAC mínimo a la Managed Identity
9. deploy-application.sh         → sube el .jar de Spring Boot
10. validate-week1.sh + tests    → verifican que todo quedó bien
```

### 5.2 Recorrido de una transacción (con el archivo de cada paso)

```
Sistema originador (token rol SERVICE)
   │
   └─ POST /api/v1/transactions
        │  ── seguridad ──────────────────────────────────────────────
        │  SecurityConfiguration.java        (¿ROLE_SERVICE? si no → 401/403)
        │  EntraRolesJwtAuthenticationConverter.java (claim roles → ROLE_*)
        │
        └─ TransactionController.java         (valida JSON; si inválido → 400)
             └─ TransactionWebMapper.java     (DTO → comando)
                  └─ IngestTransactionService.java   (orquesta: persistir primero)
                       └─ RawTransactionStoragePort  (puerto de salida)
                            └─ AzureRawTransactionBlobAdapter.java  (escribe en Blob)
                                 └─ BlobPathFactory.java  (ruta yyyy/MM/dd/{id}.json)
                                      └─ raw-transactions-<ambiente>  (Azure Blob)
             └─ 202 Accepted (TransactionReceiptResponse.java)  ── inmediato, sin analizar
```

Si el Blob falla, `StorageUnavailableException` → `ApiExceptionHandler.java` → `503`.

---

## 6. Qué **no** se hizo (a propósito)

Para evitar confusiones, esto es alcance de Semana 2/3 y **no** existe todavía:

- ❌ Scoring, reglas de fraude, umbral, apertura de casos.
- ❌ Consumidor de la cola / pipeline serverless.
- ❌ Bases de datos (historial de transacciones, casos).
- ❌ Servicios de IA (explicabilidad, verificación de identidad).
- ❌ Key Vault (no se crea hasta que exista un secreto real e inevitable — ADR-005).

Hay **pruebas automáticas** (en `src/test/java/.../contract/OpenApiContractTest.java` y
`.../web/TransactionWebMapperTest.java`) que verifican que campos como `score`, `decision`,
`rules` y `caseId` **no** existen, para garantizar que el alcance no se adelantó.

---

## 7. Estado a la fecha

- **Build Java:** verde — 62 pruebas (39 unitarias + 23 integración), 0 fallos (2 tests de
  adaptador Azure se omiten sin conexión, por diseño).
- **Infraestructura:** las 14 issues tienen scripts/código entregados; las de infraestructura
  se validan con evidencia de corridas reales en Azure.
- **Seguridad:** el árbol actual no contiene secretos; el gate de secretos se reforzó para
  detectar también GUIDs reales. Ver [`SECURITY-remediacion-env-leak.md`](SECURITY-remediacion-env-leak.md)
  para la limpieza pendiente de un `.env` que quedó en la historia de git.
