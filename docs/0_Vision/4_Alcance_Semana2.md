# Centinela — Semana 2

**Motor de scoring y arquitectura orientada a eventos**

Proyecto integrador · 3 semanas · Trabajo por células

---

## Contexto

En Semana 1 se construyeron los cimientos: infraestructura, identidad, red privada y la API
que recibe y almacena transacciones. Esta semana se construye el **núcleo funcional**: los
almacenes de datos, el motor de scoring serverless con las cuatro reglas de detección, y la
capa de mensajería que **desacopla la ingesta del análisis**.

Al cierre de la semana, una transacción recibida por la API debe **puntuarse automáticamente**
contra su historial y, si supera el umbral, **generar un caso de fraude** — sin intervención
manual y sin que el cliente espere por ese proceso.

> **Restricción arquitectónica central:** la API responde al cliente **antes** de que el
> análisis concluya. Una implementación en la que la API invoque directamente al motor de
> scoring y espere su resultado **no cumple**, aunque produzca la salida esperada.

**Fuera del alcance de esta semana:** contenedores, despliegue automatizado (CI/CD), servicios
de IA, explicador de casos, observabilidad instrumentada.

---

## Stack elegido por la célula (decisiones de Semana 2)

| Componente | Servicio elegido | Nota |
|---|---|---|
| Almacén no relacional (transacciones + scores) | **Azure Cosmos DB for MongoDB** (nivel gratuito) | Partition key, niveles de consistencia y TTL. |
| Almacén relacional (casos) | **Azure Database for PostgreSQL Flexible Server** (free B1ms) | Detrás de Private Endpoint, aislado de internet. |
| Distribución del evento de transacción | **Azure Event Grid** | Notifica la ocurrencia; la API no espera. |
| Cola de casos marcados | **Azure Storage Queue** (reutiliza la de Semana 1) | Garantiza el procesamiento aunque el consumidor esté caído. |
| Motor de scoring | **Azure Functions (Java)** | Serverless, activado por Event Grid. |
| Gestión de secretos | **Azure Key Vault** | Acceso por Managed Identity (sin credencial para obtener credenciales). |
| Limitación de tasa | **En la aplicación** (App Service) | Sin capa de API Management dedicada. |

---

## Catálogo de requisitos de Semana 2

Códigos usados por el backlog y la matriz de trazabilidad.

| Código | Requisito | Origen |
|---|---|---|
| `RD-S2-001` | Almacén no relacional con clave de partición que recupera el historial de UNA cuenta sin recorrer particiones ajenas. | 2.1 |
| `RD-S2-002` | Nivel de consistencia seleccionado y justificado (garantía vs. latencia). | 2.1 |
| `RD-S2-003` | Política de expiración (TTL) alineada a las ventanas temporales de las reglas. | 2.1 |
| `RD-S2-004` | Almacén relacional con modelo Caso/Estado/Asignación/Resolución/Auditoría inmutable. | 2.2 |
| `RD-S2-005` | Almacén relacional NO alcanzable desde internet (Private Endpoint). | 2.2 |
| `RD-S2-006` | Estrategia de respaldo documentada (periodicidad, retención, RPO). | 2.2 |
| `RF-S2-001` | Motor de scoring serverless activado por evento, con las cuatro reglas. | 2.3 |
| `RF-S2-002` | Umbral configurable sin redespliegue. | 2.3 |
| `RF-S2-003` | Registro del detalle de activación (valores observados, no solo el id de la regla). | 2.3 |
| `RF-S2-004` | La API publica el evento tras persistir y responde sin esperar el scoring. | 2.5 |
| `RM-S2-001` | Distribución de evento (notificar la ocurrencia). | 2.4 |
| `RM-S2-002` | Cola de casos con garantía de procesamiento (sin pérdida ante consumidor caído). | 2.4 |
| `RS-S2-001` | Cero secretos en código, repositorio, historial de git ni variables manuales. | 2.6 |
| `RS-S2-002` | Autenticación al gestor de secretos por identidad gestionada. | 2.6 |
| `RS-S2-003` | Limitación de tasa por origen con código de estado correcto (`429`). | 2.7 |
| `RNF-S2-001` | Desacoplamiento: la API responde antes de que termine el scoring (demostrable por timestamps). | 1, 2.4 |
| `RNF-S2-002` | Ambos almacenes dentro de los límites del nivel gratuito. | 2.1, 2.2 |
| `RNF-S2-003` | Crédito acumulado al cierre de Semana 2 inferior a 40 USD. | 4 |

---

## Flujos de Semana 2

### FM-S2-001 — Puntuar una transacción (pipeline desacoplado)

1. La API recibe y valida la transacción (Semana 1).
2. La API persiste la transacción cruda en Blob (Semana 1).
3. La API **publica un evento** de transacción en Event Grid y responde `202` (no espera).
4. El **motor de scoring** (Function) reacciona al evento.
5. Consulta el **historial reciente** de esa cuenta en Cosmos (una sola partición).
6. Evalúa las **cuatro reglas** y suma los puntos.
7. Persiste el **score + detalle de activación** junto a la transacción en Cosmos.
8. Si el score supera el **umbral**, encola un mensaje de **apertura de caso** en la Storage Queue.

### FM-S2-002 — Abrir y auditar un caso

1. El **consumidor de casos** lee un mensaje de la cola a su propio ritmo.
2. Inserta el caso en PostgreSQL (Caso + estado inicial + auditoría), de forma **idempotente**.
3. Elimina el mensaje solo tras confirmar la escritura.
4. Si el consumidor está caído, los mensajes **se acumulan** y se procesan al reanudarse (sin pérdida).

### FM-S2-003 — Verificación de desacoplamiento

1. Detener el consumidor de casos.
2. Enviar transacciones: la API sigue respondiendo con normalidad.
3. Verificar que los casos quedan encolados (no perdidos).
4. Reanudar el consumidor y confirmar que se procesan todos.

---

## Entregables

| # | Entregable | Issue(s) |
|---|---|---|
| 1 | Almacén de transacciones desplegado (partition key, consistencia, TTL). | ISS-S2-001 |
| 2 | Justificación del diseño de particionamiento. | ISS-S2-001, 014 |
| 3 | Almacén de casos desplegado (modelo + auditoría, aislado). | ISS-S2-002, 010 |
| 4 | Estrategia de respaldo. | ISS-S2-002 |
| 5 | Motor de scoring operativo (4 reglas, por evento). | ISS-S2-007, 008 |
| 6 | Umbral configurable sin redespliegue. | ISS-S2-008 |
| 7 | Registro de detalle de activación. | ISS-S2-008, 009 |
| 8 | Capa de mensajería (evento + cola de casos, distinción documentada). | ISS-S2-004, 005 |
| 9 | Pipeline de extremo a extremo. | ISS-S2-012 |
| 10 | Prueba de desacoplamiento. | ISS-S2-013 |
| 11 | Secretos migrados (código, repo e historial). | ISS-S2-003 |
| 12 | Limitación de tasa. | ISS-S2-006 |
| 13 | Reporte de crédito consumido. | ISS-S2-014 |
| 14 | Documento de decisiones actualizado. | ISS-S2-014 |

---

## Criterios de aceptación (globales)

**Desacoplamiento**
- [ ] La API responde antes de que el motor de scoring termine (demostrable por timestamps).
- [ ] Con el consumidor de casos detenido, la API sigue recibiendo y respondiendo.
- [ ] Al restablecerse el consumidor, los casos marcados durante la caída se procesan sin pérdidas.

**Datos y escalabilidad**
- [ ] El motor consulta el historial de una única cuenta (demostrable por la métrica de consumo).
- [ ] La política de expiración elimina registros fuera de la ventana.
- [ ] El almacén de casos no es alcanzable desde internet (verificado).
- [ ] Ambos almacenes operan dentro del nivel gratuito.

**Motor de scoring**
- [ ] Geo-imposible, velocidad, monto atípico y comercio de riesgo se activan en sus escenarios.
- [ ] El umbral se modifica sin redespliegue y el comportamiento cambia en consecuencia.
- [ ] Cada regla activada persiste los valores concretos que la activaron.

**Seguridad y costo**
- [ ] Ninguna credencial en código, repo ni historial de git.
- [ ] Los componentes acceden al gestor de secretos por identidad gestionada.
- [ ] Al superar el límite de tasa, la API responde con el código correcto (`429`).
- [ ] El crédito acumulado al cierre de Semana 2 es inferior a 40 USD.

---

> El backlog implementable de esta semana está en
> [`docs/5_Issues_y_Trazabilidad/3_Historias_Issues_Semana2.md`](../5_Issues_y_Trazabilidad/3_Historias_Issues_Semana2.md).
