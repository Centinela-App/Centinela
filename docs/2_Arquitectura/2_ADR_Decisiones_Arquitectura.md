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
