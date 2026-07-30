# Centinela — Documento de Especificaciones del Proyecto

| | |
|---|---|
| **Proyecto** | Centinela — motor de detección de fraude transaccional |
| **Plataforma** | Microsoft Azure |
| **Suscripción** | Azure subscription 1 (Pay-As-You-Go) |
| **Grupo de recursos** | `rg-centinela-week1` (región `eastus2`) |
| **Estado** | Semana 3 cerrada · 24/25 issues verificadas · pipeline en `main` |
| **Repositorios** | `Centinela` (sistema) · `centinela-lab` (banco de pruebas, cliente externo) |

---

## 1. Resumen ejecutivo y objetivos

Centinela evalúa cada transacción financiera contra el historial de su cuenta y abre un
**caso de fraude** cuando el riesgo supera un umbral configurable, sin que el cliente espere
por el análisis. El sistema pasó, a lo largo de tres semanas, de una API de ingesta a un
sistema **operable**: desplegado por integración continua, con escalado automático,
explicaciones legibles de cada decisión y trazabilidad de extremo a extremo.

### Objetivos

1. **No bloquear al originador.** La ingesta responde `202 Accepted` antes de que exista
   veredicto; la detección ocurre de forma asíncrona y desacoplada.
2. **Detección con contexto.** Cuatro reglas —velocidad, monto atípico, geografía imposible,
   comercio de riesgo— evaluadas contra el historial reciente de la cuenta.
3. **Decisiones defendibles.** Cada caso marcado recibe una explicación determinista por
   plantilla, en correspondencia estricta con las reglas y los valores que la activaron. Sin
   modelos de lenguaje generativo.
4. **Trazabilidad individual.** Dado un identificador de transacción, se reconstruye su
   recorrido completo con los tiempos de cada etapa, atravesando la mensajería asíncrona.
5. **Cero credenciales.** Managed Identity para el acceso a datos; OIDC federado para el
   pipeline; Key Vault para lo inevitablemente secreto. Ninguna credencial en código,
   repositorio, configuración del pipeline ni imágenes de contenedor.
6. **Control de costo.** El proyecto opera bajo un tope de crédito; los recursos que facturan
   por tiempo se apagan al cierre de cada jornada.

---

## 2. Arquitectura y stack tecnológico

### Recorrido de una transacción

```
cliente ──► API de ingesta ──► Blob crudo ──► Event Grid ──► Motor de scoring
                 │ 202 inmediato                                  │ reglas + historial (Cosmos)
                 │                                                 ▼
       API de consulta ◄── PostgreSQL (casos) ◄── consumidor ◄── Storage Queue
                                  ▲
                        explicador (asíncrono)
```

El contexto de traza W3C (`traceparent`) viaja **dentro de los contratos de mensaje**
(`transaction-event-v1`, `flagged-case-v1`), no en memoria: es lo que permite que la traza
sobreviva los dos saltos asíncronos —Event Grid y la Storage Queue— y no se fragmente.

### Stack

| Capa | Tecnología | Justificación |
|---|---|---|
| Lenguaje / framework | Java 21 · Spring Boot 3.4 | Arquitectura hexagonal, verificada con ArchUnit |
| Motor de scoring | Azure Functions (Java), en contenedor, disparado por Event Grid | Conserva reintento y concurrencia ya validados en Semana 2 |
| Cómputo | **Azure Container Apps** (perfil Consumption) | Escalado por concurrencia HTTP y por evento, *scale-to-zero*, nivel gratuito generoso |
| Almacén transaccional | **Cosmos DB for MongoDB** (Free Tier) | Partición por `accountId`; consulta dominante en una sola partición; TTL 90 días |
| Almacén de casos | **PostgreSQL Flexible Server** (privado) | Modelo relacional con auditoría *append-only* |
| Objetos | **Blob Storage** (privado) | Transacción cruda y documentos de verificación |
| Mensajería | **Event Grid** (evento) + **Storage Queue** (cola de casos) | Desacoplamiento ingesta/análisis |
| Secretos | **Key Vault** (RBAC, purge protection) | Cadenas de conexión resueltas en arranque por Managed Identity |
| Registro | **Azure Container Registry** (Basic) | *Pull* por Managed Identity, sin credenciales de registro |
| Observabilidad | **Application Insights** + **Log Analytics** | Traza individual y las cinco consultas de operación (KQL) |
| Red | **VNet** + **Private Endpoints** + DNS privado | Los almacenes no son alcanzables desde internet |
| CI/CD | **GitHub Actions** + **OIDC federado** | Sin credenciales almacenadas |

### Componentes del código (repositorio `Centinela`)

- `transactioningestion` — ingesta y publicación del evento.
- `casemanagement` — apertura de casos, auditoría inmutable, consumidor de la cola.
- `caseexplanation` — explicador determinista por plantilla.
- `caseinquiry` — API de consulta (análisis y caso).
- `documentstorage` / `documentverification` — carga y extracción documental con manejo de fallos.
- `scoringrecord` — lectura del registro del motor (Cosmos).
- `shared` — contratos, contexto de traza W3C, telemetría por etapas.

---

## 3. Gestión de accesos y roles del equipo

### Esquema de roles (RBAC sobre `rg-centinela-week1`)

El acceso se concede **a nivel de grupo de recursos**, nunca de suscripción: acota el alcance
de cualquier error o compromiso al perímetro del proyecto.

| Miembro | Correo | Rol Azure | Alcance | Qué puede hacer |
|---|---|---|---|---|
| Carlos Restrepo | `carlosres1995@gmail.com` | **Owner** | `rg-centinela-week1` | Gestionar recursos **y** administrar accesos (asignar roles) |
| Stiven | `stivencolombia@gmail.com` | **Contributor** | `rg-centinela-week1` | Crear/modificar/eliminar recursos; **no** puede asignar roles |
| L. Mejía | `lmejiacoronado@gmail.com` | **Contributor** | `rg-centinela-week1` | Ídem |
| Esteban BL | `estebanbl090@gmail.com` | **Contributor** | `rg-centinela-week1` | Ídem |

### Naturaleza B2B de los miembros

Los cuatro correos son de Gmail, es decir, **externos al tenant** de la suscripción
(`stiven007carhotmail078.onmicrosoft.com`). Azure los incorpora como **usuarios invitados
(B2B Guest Users)** de Microsoft Entra ID:

- **No existen en el directorio hasta ser invitados.** Un `az role assignment create` sobre un
  correo desconocido falla; primero hay que enviar la invitación B2B (§4 del runbook de RBAC).
- **Su identidad interna cambia de forma.** Tras aceptar, su `userPrincipalName` toma la forma
  `carlosres1995_gmail.com#EXT#@stiven007carhotmail078.onmicrosoft.com`. Por eso las
  asignaciones se hacen por **object id**, no por correo, que es ambiguo para invitados.
- **Owner sobre un invitado es un privilegio fuerte.** Un `Owner` puede conceder acceso a
  terceros. Se limita a un único miembro y solo sobre el grupo de recursos, nunca sobre la
  suscripción.

### Identidades no humanas (principio de mínimo privilegio)

El sistema **no usa las cuentas del equipo** para operar. Cada componente tiene su propia
identidad, con roles de **datos** y ninguno de administración:

| Identidad | Tipo | Roles | Para qué |
|---|---|---|---|
| `id-cent-apps` | Managed Identity | Storage Blob/Queue Data Contributor, Key Vault Secrets User, EventGrid Data Sender | Las Container Apps acceden a datos sin secretos |
| `id-cent-acrpull` | Managed Identity | AcrPull | *Pull* de imágenes desde el registro |
| `app-cent-github-deploy` | App registration (OIDC) | AcrPush + Contributor (RG) | El pipeline despliega sin contraseña |

---

## 4. Requisitos de infraestructura y despliegue

### Principios no negociables

1. **Datos no alcanzables desde internet.** Cosmos, PostgreSQL, Blob y Key Vault tienen el
   acceso público deshabilitado y se consumen por Private Endpoint desde la VNet.
2. **Cero credenciales.** Managed Identity para datos; OIDC para el pipeline; Key Vault para
   cadenas de conexión. Un barrido de secretos (árbol de trabajo **e** historial de Git) corre
   como compuerta de CI.
3. **Reproducibilidad.** Toda la infraestructura se reconstruye desde cero con los scripts de
   `scripts/`, idempotentes y con modo `--validate-only`.

### Pipeline CI/CD y el Service Principal federado

El despliegue **no usa un secreto de Service Principal**, que es el enfoque clásico y su
punto débil (una credencial de larga duración que hay que rotar). En su lugar:

- **OIDC federado.** GitHub emite un token de identidad de vida corta que Azure valida contra
  una credencial federada **acotada a este repositorio y esta rama**. No hay secreto que robar.
- **Roles del pipeline:** `AcrPush` (publicar imágenes) y `Contributor` sobre el grupo de
  recursos. Documentado como deuda consciente: lo ideal sería un rol personalizado con solo las
  acciones de `Microsoft.App`.
- **Interruptor de despliegue.** Las etapas que tocan Azure se activan con la variable de
  repositorio `AZURE_DEPLOY_ENABLED=true`, para que un *merge* sin OIDC configurado ejecute CI
  y se detenga limpio en lugar de fallar.

Aprovisionamiento de esta identidad: `bash scripts/provision-github-oidc.sh`.

### Etapas del despliegue continuo (ante integración a `main`)

1. Construcción de la aplicación.
2. Ejecución de las pruebas — un fallo detiene el pipeline antes de construir imagen.
3. Construcción de las imágenes de contenedor (multietapa, sin secretos en ninguna capa).
4. Publicación en el registro privado.
5. Despliegue en Container Apps y verificación de salud (la app debe **responder**, no solo
   que `az` devuelva cero).

### Control de costo

Recurso con costo recurrente principal: PostgreSQL Flexible Server y ACR Basic (~0,167 USD/día;
ACR no tiene nivel gratuito). El resto opera dentro de niveles gratuitos o escala a cero.

```bash
bash scripts/shutdown-daily.sh          # apaga lo que factura por tiempo
bash scripts/shutdown-daily.sh --start  # lo reenciende
```

---

## 5. Siguientes pasos

1. **Invitar y asignar roles al equipo** (B2B) — comandos en el runbook de RBAC que acompaña
   a este documento.
2. **Registrar los secrets de OIDC** en GitHub y poner `AZURE_DEPLOY_ENABLED=true` para
   activar el despliegue automático en cada integración a `main`.
3. **ISS-S3-025 — sustentación:** verificación del README por un tercero ajeno a la célula, y
   ensayo cronometrado de los ocho escenarios, incluidos los dos de fallo (documento ilegible y
   explicador detenido), ya implementados y probados en local.
4. **Mejora de mínimo privilegio (deuda registrada):** sustituir el rol `Contributor` del
   pipeline por un rol personalizado con solo las acciones de `Microsoft.App` y `AcrPush`.
5. **Endurecer la extracción documental** si la suscripción habilita Azure AI Document
   Intelligence, publicando otro adaptador de `IdentityDataExtractorPort` sin cambiar la
   política de fallos.

---

*Documento vivo. Refleja el estado del proyecto al cierre de la Semana 3. Las decisiones de
arquitectura, con sus contrapartidas, están en `docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md`.*
