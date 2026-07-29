# ADR — Decisiones de arquitectura (documento vivo)

Este es el **documento de decisiones de arquitectura** que exige el enunciado (`0_Vision/2_Alcance_Semana1.md`, entregable 7). Se empieza en Semana 1 y se mantiene vivo durante las tres semanas. Cada decisión registra: contexto, decisión, alternativas y consecuencias.

Para Semana 1 el enunciado pide registrar explícitamente:
1. Clasificación de cada componente según su **modelo de servicio en la nube** y por qué.
2. Por qué se diseñó la red así.
3. Qué permisos recibió el rol **Servicio** y por qué cada uno es necesario.

Este documento responde a los tres puntos, más las decisiones transversales de la semana.

---

## ADR-001 — Clasificación de componentes por modelo de servicio en la nube

**Contexto.** El enunciado exige clasificar cada componente como IaaS, PaaS o SaaS y justificarlo, porque de esa clasificación depende cuánta administración asume la célula y cuánta la plataforma.

**Decisión.**

| Componente | Modelo | Qué administra la célula | Qué administra Azure | Por qué se eligió |
|---|---|---|---|---|
| **App Service (Web App + slot `staging`)** | **PaaS** | El artefacto Java y su configuración | SO, runtime, parches, balanceador, escalado | El cómputo como PaaS elimina administrar VMs y da HA/escala horizontal "de fábrica". Menor costo operativo y menor superficie de ataque. |
| **Blob Storage** | **PaaS (almacenamiento gestionado)** | Contenedores, rutas, datos | Discos, replicación, disponibilidad | Persistencia de objetos administrada; se consume por SDK + Managed Identity, sin operar infraestructura. |
| **Queue Storage** | **PaaS (mensajería gestionada)** | La cola y su mensaje de prueba | Infraestructura de cola | Buffer de ingesta preparado sin operar un broker propio. Sin consumidor en Semana 1. |
| **Microsoft Entra ID** | **SaaS (identidad gestionada)** | App roles y asignaciones | Todo el servicio de directorio y emisión de tokens | Identidad y autenticación como servicio; no se opera infraestructura de identidad. |
| **Managed Identity** | **PaaS (capacidad de identidad)** | La asignación de roles de datos | Ciclo de vida de la credencial | Permite acceso a datos **sin secretos** en código ni repositorio. |
| **VNet + Subredes + Private Endpoints + DNS privado** | **IaaS (capa de red)** | Rangos, subredes, endpoints, reglas NSG, zonas DNS | Hardware de red físico | Es la única porción que la célula administra directamente; necesaria para aislar el Storage de internet. |

**Consecuencia clave.** En Semana 1 **no existe IaaS de cómputo** (ni VMs ni Kubernetes). El único IaaS es la red. Es una decisión de costo (crédito compartido de USD 200) y de reducción de superficie administrable.

---

## ADR-002 — Diseño de la red privada

**Contexto.** Requisito no negociable del enunciado: **los almacenes de datos no deben ser alcanzables desde internet**; solo la subred de la aplicación puede llegar a ellos. Aunque en Semana 1 aún no hay bases de datos, la red debe quedar lista para recibirlas en Semana 2 bajo esa restricción.

**Decisión.**
- Una **VNet** con dos subredes: `snet-app-integration` (integración VNet del App Service) y `snet-private-endpoints` (Private Endpoints de Blob y Queue).
- **Acceso público del Storage deshabilitado** (`publicNetworkAccess = Disabled`).
- Acceso al Storage exclusivamente vía **Private Endpoint** + **zona DNS privada**, alcanzable solo desde la VNet.
- Reglas de tráfico (NSG) documentadas en `2_Arquitectura/3_Diagrama_Red.md`.

**Alternativas descartadas.**
- *Firewall de Storage por IP*: frágil y no cumple "no alcanzable desde internet" de forma robusta.
- *Service Endpoints en vez de Private Endpoints*: no dan IP privada real ni el mismo aislamiento que se necesitará en Semana 2.

**Consecuencia.** En Semana 2 se pueden añadir las bases de datos detrás de la misma subred de Private Endpoints sin rehacer la topología. Revertir esto más tarde (con el pipeline encima) sería la decisión más costosa del proyecto — por eso se cierra ahora.

---

## ADR-003 — Permisos del rol Servicio (mínimo privilegio)

**Contexto.** El rol **Servicio** es la identidad que corre desatendida; es el objetivo natural de un atacante. Cada permiso de más es superficie de ataque. El enunciado exige justificar cada permiso que se le da.

**Decisión.** El rol Servicio se materializa en dos planos, cada uno con lo mínimo:

**Plano de aplicación (app role `SERVICE` en Entra ID):**
| Permiso | ¿Por qué es necesario? |
|---|---|
| Invocar `POST /api/v1/transactions` | Es la única acción del sistema originador: entregar la transacción a la ingesta. |
| **Nada más** | No puede cargar documentos (eso es del Analista), ni leer, ni administrar. |

**Plano de datos (Managed Identity del App Service):**
| Permiso | ¿Por qué es necesario? |
|---|---|
| Rol de **datos de Blob** acotado a los contenedores que usa la API | Persistir el JSON crudo de la transacción y guardar documentos. Es acceso de datos, no de administración. |
| **Sin permiso de Queue Storage** | La cola no forma parte del flujo de negocio de Semana 1; darle acceso sería superficie ociosa. |
| **Sin Contributor ni Owner** sobre el Resource Group | La app nunca modifica infraestructura; solo lee/escribe datos. |

**Consecuencia.** Un Servicio comprometido solo puede escribir en dos contenedores de Blob acotados. No puede tocar red, identidades, ni otros recursos. La prueba de mínimo privilegio (Analista no puede modificar recursos) se verifica en `TEST-S1-009`.

---

## ADR-004 — Alta disponibilidad vs. control de costo (decisión con trade-off explícito)

**Contexto.** El enunciado exige que la API tolere la caída de una instancia sin perder transacciones y que se pueda tumbar una instancia en la demo y el sistema siga respondiendo. Al mismo tiempo, el equipo comparte un crédito de USD 200 y correr dos instancias permanentes lo consume más rápido.

**Decisión.**
- El App Service Plan usa un SKU que **soporta escala horizontal y deployment slots**.
- **Operación normal: una (1) instancia.**
- **Durante la prueba/demo de HA: se escala temporalmente a dos (2) instancias**, se retira una y se demuestra continuidad; luego se vuelve a una.

**Trade-off explícito (importante).** En operación normal, con una sola instancia, **no hay redundancia real**: si esa instancia cae, hay interrupción hasta que la plataforma la reponga. La tolerancia a caída de instancia se **demuestra** puntualmente escalando a dos, no se sostiene 24/7. Es una decisión consciente de costo, no un olvido.

**Cómo cerrar la brecha si se exige HA permanente.** Fijar el mínimo de instancias en 2 en el plan (aumenta costo del crédito). Queda documentado como palanca disponible.

**Verificación:** `ISS-S1-012` / `TEST-S1-024`.

---

## ADR-005 — Sin secretos: Managed Identity desde el día uno

**Contexto.** El enunciado prohíbe cualquier credencial, cadena de conexión o clave en código o repositorio.

**Decisión.** El acceso a Blob y Queue se hace con **Managed Identity** (`DefaultAzureCredential`), sin cadenas de conexión. **No se crea Key Vault** salvo que aparezca un secreto real e inevitable; no se crea un vault vacío "por si acaso".

**Consecuencia.** No hay secretos que rotar ni fugar. Si Semana 2 introduce un secreto externo real (p. ej. clave de un proveedor de IA), entonces —y solo entonces— se añade Key Vault.

> **Revisión — Semana 2 (ISS-S2-003).** La condición prevista **se cumplió**: **Cosmos DB
> for MongoDB** (ADR-007) autentica su plano de datos con una **connection string/key** —la
> API Mongo (RU) **no** soporta Microsoft Entra ID para el wire protocol—, por lo que aparece
> un **secreto real e inevitable**. En consecuencia se crea el **Key Vault** (RBAC data plane,
> soft-delete + purge protection) y se migra ese único secreto. **El principio se mantiene:**
> PostgreSQL (ADR/ISS-S2-002) usa **Entra ID exclusiva** (sin password de conexión) y Event
> Grid publica por **Managed Identity**; las apps se autentican **al vault** por Managed
> Identity (`Key Vault Secrets User`) — no existe "una credencial para obtener credenciales".
> ADR-005 queda **parcialmente derogada**: sí hay Key Vault, pero solo por un secreto real,
> nunca "por si acaso".

---

## ADR-006 — Stack y estructura interna

**Contexto.** El lenguaje es libre; lo que no es libre es el contrato entre piezas.

**Decisión.** **Java 21 + Spring Boot + Maven**, con **arquitectura hexagonal** (puertos y adaptadores) y una **aplicación modular** (no microservicios en Semana 1). Los adaptadores de Azure quedan aislados detrás de puertos para poder conectar el pipeline de Semana 2 sin tocar el dominio.

**Consecuencia.** El endpoint de ingesta y el JSON crudo almacenado quedan estables; Semana 2 se conecta por un punto de extensión en la capa de aplicación.

---

## Decisiones deliberadamente abiertas para Semana 2

No se deciden todavía (esperan `Azure-Semana2.md`): qué componente consume la cola, qué servicio serverless se usa, el formato final del evento de scoring, si la cola actual evoluciona a otro servicio de mensajería, qué almacén guarda el historial de transacciones, qué base de datos gestiona los casos, las reglas/puntuaciones/umbral, y la estructura del caso de fraude.

---

# Decisiones de Semana 2

## ADR-007 — Almacén de transacciones: Cosmos DB for MongoDB (partición, consistencia, TTL)

**Contexto.** El motor de scoring ejecuta, en cada transacción, una consulta dominante:
*"dame las transacciones recientes de esta cuenta"*. El perfil es escritura constante de alto
volumen y esa lectura por cuenta. El enunciado exige elegir clave de partición, nivel de
consistencia y política de expiración, y **justificar** cada una. La clave de partición **no
se puede cambiar tras la primera escritura** sin migrar todos los datos.

**Decisión.**

| Parámetro | Valor elegido | Justificación |
|---|---|---|
| **Servicio** | Cosmos DB for MongoDB (Free Tier) | API MongoDB (el equipo domina Mongo); Free Tier da 1000 RU/s + 25 GB sin costo. |
| **Clave de partición (shard key)** | `accountId` | La consulta dominante filtra por cuenta. Con `accountId` como partición, el historial de una cuenta vive en **una sola partición** → la lectura no recorre particiones ajenas y su costo (RU) es estable con el volumen. |
| **Consistencia** | `Session` | Compromiso equilibrado: dentro de la sesión que escribe y luego lee (la propia Function tras persistir), garantiza *read-your-writes* sin el costo de latencia de `Strong`. El scoring no requiere consistencia global fuerte: opera sobre el historial reciente de una cuenta, no sobre una vista transaccional global. |
| **Expiración (TTL)** | 90 días (`7 776 000 s`), configurable | Cubre con margen la ventana más larga que usan las reglas (velocidad = minutos; monto atípico = comportamiento histórico de semanas). Pasado ese periodo, el registro deja de aportar al scoring y se elimina solo, manteniendo el almacén dentro del Free Tier. |

**Qué se optimiza y qué se sacrifica.** Se optimiza la consulta *"historial de una cuenta"*
(la que corre en cada scoring). Se **sacrifica** la consulta *"todas las transacciones de un
comercio / de un rango de fechas global"*: esa sí recorrería varias particiones. Es un
sacrificio aceptable porque no está en el camino crítico del scoring.

**Alternativas descartadas.**
- *Particionar por `transactionId`*: distribuye perfecto la escritura, pero para leer el
  historial de una cuenta habría que consultar **todas** las particiones (fan-out) → costo de
  RU que crece con el volumen y falla en producción aunque funcione en pruebas.
- *Particionar por fecha (`yyyy/MM/dd`)*: bueno para consultas por rango temporal global, pero
  la consulta por cuenta seguiría siendo cross-partition. No sirve al camino crítico.
- *Azure Table Storage*: más barato, pero sin niveles de consistencia configurables ni TTL
  nativo por documento; cumpliría con dificultad los requisitos de consistencia y expiración.

**Consecuencia.** La forma del documento de transacción y la partición quedan **congeladas
antes de la primera escritura**. Cambiar la shard key en Semana 3 obligaría a una migración
completa. El adaptador Java de lectura (ISS-S2-007) debe consultar **siempre** filtrando por
`accountId` para respetar el diseño.

---

# Semana 3 — Decisiones de operación

Con el sistema ya funcional, las decisiones de esta semana no tratan sobre qué hace Centinela
sino sobre cómo se opera: cómo llega el código a producción, cómo responde a la carga, y cómo
se sabe qué le pasó a una transacción concreta.

---

## ADR-008 — Plataforma de despliegue continuo: GitHub Actions

**Contexto.** El enunciado exige elegir entre al menos dos plataformas viables y justificar el
criterio, indicando en qué contexto la decisión sería la contraria. Las dos candidatas reales
eran **GitHub Actions** y **Azure DevOps Pipelines**.

**Decisión.** GitHub Actions, con autenticación por **OpenID Connect**.

**Qué se obtiene.**

El repositorio ya vive en GitHub, así que el pipeline queda junto al código: un pull request
muestra su propio resultado sin cambiar de herramienta ni de identidad. Pero el argumento
decisivo no es la comodidad — es que **con OIDC no existe ninguna credencial que robar**.
GitHub emite un token de identidad de vida corta que Azure valida contra una credencial
federada acotada a este repositorio y esta rama. El requisito del enunciado dice que las
credenciales del pipeline "constituyen secretos y se gestionan como tales"; la lectura más
fuerte de ese requisito es no tener ninguna. Un JSON de service principal filtrado vale hasta
que alguien lo rote; un token OIDC filtrado caducó antes de terminar de leerse.

**Qué se sacrifica.**

Los *runners* alojados de GitHub viven fuera de la VNet. Esto tiene una consecuencia concreta y
no teórica: el paso de *bootstrap* de PostgreSQL necesita conectividad al plano de datos
privado, así que **no puede ejecutarse desde el pipeline**. Queda como operación manual
documentada en el runbook. Azure DevOps, con un *self-hosted agent* dentro de
`snet-app-integration`, sí podría automatizarlo.

También se pierde la integración nativa con Azure Boards y con los *service connections*, que
en organizaciones con gobierno centralizado de suscripciones simplifican la auditoría.

**En qué contexto la decisión sería la contraria.**

Elegiríamos Azure DevOps si se cumpliera cualquiera de estas tres condiciones:

1. **El despliegue exigiera acceso al plano de datos privado en cada corrida** — no solo en el
   aprovisionamiento inicial. Migraciones de esquema ejecutadas por el pipeline contra una base
   de datos sin acceso público caen justo aquí.
2. **La organización exigiera que los agentes de compilación corrieran en infraestructura
   propia**, por política de cumplimiento o porque el código no puede salir de su red.
3. **La gestión del trabajo ya viviera en Azure Boards.** La trazabilidad entre historia,
   commit y despliegue en una sola herramienta vale más que la comodidad del pull request.

Ninguna de las tres se cumple en este proyecto.

---

## ADR-009 — Contenedores en Azure Container Apps, no en App Service

**Contexto.** La Semana 1 desplegó la aplicación como artefacto Java en App Service. La Semana 3
exige empaquetarla como imagen de contenedor y desplegarla en "una plataforma de contenedores
gestionada", con reglas de escalado justificadas y evidencia de escalado bajo carga.

**Decisión.** Azure Container Apps (perfil Consumption). El App Service se **detiene**, no se
elimina, hasta el cierre del proyecto.

**Por qué.** Solo Container Apps ofrece las tres cosas a la vez: escalado por concurrencia HTTP
(no solo por CPU), *scale-to-zero*, y un nivel gratuito mensual generoso (180 000 vCPU-s,
360 000 GiB-s, 2 000 000 de peticiones). App Service for Containers habría sido un cambio menor
—mismo plan, misma VNet— pero escala por CPU y memoria, y no baja de una instancia.

Esa diferencia no es cosmética. La API de ingesta **espera E/S**: escribe un blob y publica un
evento. Bajo carga su CPU apenas se mueve mientras las peticiones se acumulan. Una regla por CPU
llegaría tarde, o no llegaría, justo cuando la latencia ya se degradó.

**Qué se sacrifica.** Se pierde el *slot* de `staging` con intercambio de despliegue que la
Semana 1 construyó. El enunciado deja explícitamente los entornos de staging con swap fuera del
alcance de esta semana, así que la pérdida es aceptable — pero es una pérdida real, y volver a
tenerla exigiría revisiones múltiples con división de tráfico, que es otro modelo mental.

**Consecuencia de costo.** El plan Standard del App Service era el mayor gasto recurrente del
proyecto. Detenerlo libera crédito justo en la semana de mayor consumo.

---

## ADR-010 — Métrica de escalado: una por componente, no una para todos

**Contexto.** El enunciado advierte que cada métrica produce una respuesta distinta y exige
documentar la elegida y su comportamiento esperado ante un pico.

**Decisión.** Tres métricas distintas, una por componente.

| Componente | Métrica | Por qué esa y no otra |
|---|---|---|
| **API de ingesta** | Concurrencia HTTP (10 peticiones simultáneas por réplica) | Su cuello de botella es la espera, no el cálculo. La concurrencia mide directamente lo que sufre el cliente: cuántas peticiones hay en vuelo. |
| **Motor de scoring** | Concurrencia de invocaciones (20) | Lo dispara Event Grid, que gestiona su propia entrega y reintento. Pasa la mayor parte del tiempo esperando a Cosmos, no calculando. |
| **Explicador** | Profundidad de trabajo pendiente; escala a **cero** | No recibe peticiones: consulta casos pendientes. Ni CPU ni concurrencia HTTP dicen nada sobre él. |

**Comportamiento esperado ante un pico.** Con 200 req/s y ~50 ms por petición hay unas 10
peticiones en vuelo, que caben en una réplica. A 600 req/s son unas 30, y KEDA levanta 3
réplicas en unos 30 segundos. Al cesar la carga, la ventana de enfriamiento de 300 s evita el
vaivén de crear y destruir réplicas por fluctuaciones cortas.

**Consecuencia aceptada.** Cuando el explicador está en cero réplicas, un caso nuevo espera al
siguiente ciclo de sondeo. Se acepta porque el requisito establece que la explicación es
posterior a la apertura del caso, y ese retraso molesta menos que pagar una réplica ociosa
durante todo el día.

---

## ADR-011 — Registro de contenedores: ACR Basic, pagando por no tener un secreto

**Contexto.** El enunciado pide usar los niveles gratuitos disponibles del registro de
contenedores. **Azure Container Registry no tiene nivel gratuito**: ninguno de sus SKU lo es.

**Decisión.** ACR Basic, con usuario administrador deshabilitado y *pull* mediante Managed
Identity. Coste: ~0,167 USD/día, unos 1,20 USD por la semana del proyecto.

**Por qué no la alternativa gratuita.** GitHub Container Registry admite imágenes privadas sin
costo. Se descartó porque Container Apps tendría que autenticarse con un *Personal Access
Token* almacenado como secreto de la aplicación — exactamente el tipo de credencial de larga
duración que el proyecto evita desde la Semana 1. Se pagan 1,20 USD por no tener ese secreto.

**Límites del SKU Basic**, para el reporte de costos: 10 GiB de almacenamiento incluido,
10 000 lecturas/día, 1 000 escrituras/día, 30 GiB/día de descarga. Con dos imágenes de ~250 MB
y una decena de construcciones diarias, el consumo se queda holgadamente dentro.

---

## ADR-012 — Trazabilidad: el contexto viaja dentro del mensaje

**Contexto.** El requisito es reconstruir el recorrido completo de **una** transacción, con
tiempos por etapa, atravesando la mensajería. El enunciado descarta explícitamente que un panel
de métricas agregadas lo satisfaga.

**Decisión.** El contexto de traza W3C (`traceparent`) se **serializa dentro de los contratos**
`transaction-event-v1` y `flagged-case-v1`.

**Por qué no bastaba con el agente de telemetría.** El agente correlaciona automáticamente las
llamadas HTTP salientes, pero el recorrido de Centinela cruza dos saltos asíncronos —Event Grid
y una Storage Queue— entre cuatro procesos distintos. En un salto asíncrono no hay llamada que
instrumentar: el productor termina y el consumidor empieza minutos después. Sin el contexto
dentro del mensaje, la traza se parte en cuatro trazas inconexas y ninguna responde la pregunta.

**Qué obligó a cambiar.** Ampliar dos contratos versionados y sus JSON Schema. Se hizo de forma
aditiva y con normalización tolerante: un `traceparent` ausente o corrupto abre una traza nueva
en lugar de rechazar el mensaje. **La telemetría nunca puede tumbar el negocio** — subordinar
la detección de fraude a la corrección de un dato de instrumentación sería invertir las
prioridades.

---

## ADR-013 — Qué componente se satura primero y qué se hizo al respecto

**Contexto.** El enunciado exige identificar el componente que se satura primero bajo carga y
las medidas de mitigación adoptadas.

**Respuesta: PostgreSQL**, y por un margen amplio.

El razonamiento: la API escala horizontalmente sin límite práctico y el motor de scoring
también. Cosmos está particionado por `accountId`, así que la carga se reparte. PostgreSQL, en
cambio, es **una sola instancia Flexible Server B1ms** — un núcleo, 2 GB de RAM — y cada réplica
nueva del consumidor de casos y del explicador abre su propio conjunto de conexiones. El límite
no es la CPU: es el número de conexiones simultáneas.

**Medidas adoptadas.**

1. **El explicador está acotado a 3 réplicas** y consulta en lotes de 25. Sin ese techo, un
   pico de casos multiplicaría las conexiones justo cuando la base ya está bajo presión.
2. **El consumidor de casos es idempotente** (Semana 2), así que agotar conexiones produce
   reintentos seguros en vez de casos duplicados.
3. **Las consultas del explicador usan un índice parcial** sobre `explanation_state = 'PENDING'`,
   de modo que el sondeo periódico no recorre la tabla completa de casos.
4. **La carga generada para demostrar el escalado no abre casos**: sus transacciones son
   inocuas. Es deliberado — miles de casos de prueba saturarían la base sin demostrar nada
   sobre el escalado de la API, que es lo que se quiere observar.

**Lo que no se hizo.** No se introdujo un *pool* de conexiones compartido ni PgBouncer. Con el
volumen del proyecto no hace falta, y añadir un componente intermedio habría creado un punto de
fallo nuevo que también habría que instrumentar y demostrar.

---

## ADR-014 — Qué cambiaría la célula si empezara de nuevo

El enunciado pide esta reflexión explícitamente. Cuatro cosas, ordenadas por lo que más costó.

**1. La instrumentación, desde la primera línea.** El enunciado advertía que la instrumentación
no admite implementación tardía, y tenía razón por un motivo más profundo del esperado: no fue
el trabajo de añadir logs, sino que **los contratos de mensaje no tenían dónde llevar el
contexto de traza**. Ampliar dos contratos versionados con sus esquemas y sus pruebas, ya
desplegados, costó más que haberlos diseñado con el campo desde el principio. El campo
`traceparent` habría cabido en la Semana 2 casi gratis.

**2. Diseñar las reglas pensando en cómo se explicarían.** El motor registraba lo justo para
*decidir*: distancia, tiempo, velocidad. Faltaba lo necesario para *explicar*: las ciudades, la
cadencia habitual de la cuenta, el multiplicador observado. La pregunta "¿qué frase escribirá el
analista con esto?" debería haberse hecho al escribir cada regla, no al escribir el explicador.
Detectarlo en la Semana 3 obligó a modificar reglas ya probadas.

**3. Una API de consulta desde la Semana 1.** Durante dos semanas el único modo de ver un
resultado fue entrar a la base de datos. Eso ralentizó cada verificación y volvió imposible que
nadie ajeno a la célula comprobara nada. Dos endpoints de lectura habrían pagado su costo la
primera semana.

**4. Contenedores desde el principio.** Desplegar como artefacto Java en App Service y migrar a
contenedores en la última semana significó configurar el mismo sistema dos veces. Empezar
contenedorizado habría dado además paridad entre el entorno local y el desplegado, que es donde
más tiempo se pierde depurando diferencias.

**Lo que no cambiaríamos.** La red privada con Private Endpoints desde el primer día, y Managed
Identity en lugar de secretos. Ambas decisiones fueron incómodas al principio —el *bootstrap* de
PostgreSQL sigue siendo el paso más engorroso del despliegue— y ambas evitaron la clase de
problema que no se puede arreglar después sin rehacerlo todo.

---

## Estado del documento

**Cerrado** al término de la Semana 3. Cubre las tres semanas: ADR-001 a ADR-007 (Semanas 1 y 2)
y ADR-008 a ADR-014 (Semana 3). Las decisiones que quedaron deliberadamente fuera del alcance
—multi-región, recuperación ante desastres, orquestación con clusters gestionados— están
registradas como tales en `docs/week2/OPEN_DECISIONS.md` y no se abordaron.
