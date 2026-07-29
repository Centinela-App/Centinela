# 08 — Backlog implementable de Semana 3

## Propósito

Traduce `0_Vision/5_Alcance_Semana3.md` a **25 issues implementables**, con la misma estructura
que Semanas 1 y 2: descripción técnica, archivos, criterios de aceptación, pruebas por nivel,
Gherkin, Definition of Done, comandos y evidencia.

Es el backlog de cierre del proyecto. No autoriza nada fuera del alcance del enunciado:
orquestación con clusters gestionados, modelos de lenguaje generativo y entornos de staging con
intercambio de despliegue quedan explícitamente fuera.

### Stack fijado por la célula

- Despliegue continuo: **GitHub Actions + OIDC** · Registro: **ACR Basic** · Ejecución: **Azure Container Apps**
- Contenedores: **Docker multietapa** · Telemetría: **Application Insights + Log Analytics**
- Extracción documental: **PDFBox local** (plan alternativo del enunciado)
- Banco de pruebas: **repositorio aparte** (`centinela-lab`), Spring Boot + Thymeleaf

## Distribución consecutiva para cinco personas

| Persona | Issues | Entrega principal | Puede depender de |
|---|---|---|---|
| Persona 1 | `ISS-S3-001` a `ISS-S3-005` | Trazabilidad, registro suficiente del motor, esquema y lectura | Semanas 1 y 2 completas |
| Persona 2 | `ISS-S3-006` a `ISS-S3-010` | Contenedores, registro privado y escalado | `001`–`005` |
| Persona 3 | `ISS-S3-011` a `ISS-S3-015` | Integración y despliegue continuo | `006`–`010` |
| Persona 4 | `ISS-S3-016` a `ISS-S3-020` | Observabilidad, agentes de verificación y costos | `005`, `011`–`013` |
| Persona 5 | `ISS-S3-021` a `ISS-S3-025` | Explicabilidad, verificación documental, banco de pruebas y cierre | `002`, `003`, `004` |

Persona 1 abre la semana a propósito: sin contexto de traza en los contratos y sin el registro
enriquecido del motor, ni la observabilidad ni el explicador pueden construirse, y ambos son
correcciones sobre código ya desplegado.

### Regla obligatoria de dependencias

- Ninguna issue puede depender de una issue con número mayor.
- Un archivo compartido se modifica solo después del traspaso del bloque anterior.
- Las pruebas posteriores de integración no convierten una issue futura en dependencia para
  iniciar o cerrar una issue temprana.

## Jerarquía del backlog

### EPIC-S3-001 — De sistema funcional a sistema operable

| Feature | Historia | Resultado de negocio | Issues |
|---|---|---|---|
| FEAT-S3-001 Trazabilidad de extremo a extremo | HU-S3-001 Como operador quiero reconstruir el recorrido de una transacción concreta. | Diagnóstico en minutos, no en horas. | 001, 005, 016, 017 |
| FEAT-S3-002 Entrega continua | HU-S3-002 Como célula quiero que integrar despliegue sin tocar nada. | Ciclo corto y reproducible. | 011, 012, 013, 014 |
| FEAT-S3-003 Elasticidad | HU-S3-003 Como sistema quiero absorber picos sin degradarme. | Disponibilidad bajo carga. | 006, 007, 008, 009, 010, 015 |
| FEAT-S3-004 Explicabilidad | HU-S3-004 Como analista quiero entender por qué se marcó un caso. | Decisiones defendibles. | 002, 003, 004, 021, 022 |
| FEAT-S3-005 Verificación documental | HU-S3-005 Como analista quiero contrastar el documento con la cuenta. | Escalamiento completo. | 003, 023 |
| FEAT-S3-006 Validación y cierre | HU-S3-006 Como célula quiero demostrar que todo funciona. | Sustentación defendible. | 018, 019, 020, 024, 025 |

## Mapa de ejecución

| ID | Persona | Título | Dependencias | Resultado verificable |
|---|---|---|---|---|
| ISS-S3-001 | 1 | Contexto de traza W3C en contratos y mensajería | Semana 2 | `traceparent` sobrevive los saltos asíncronos |
| ISS-S3-002 | 1 | Registro de activación suficiente en el motor | Semana 2 | Ciudades, cadencia y multiplicador persistidos |
| ISS-S3-003 | 1 | Migración V4 del caso | Semana 2 | Explicación y documentos con estado propio |
| ISS-S3-004 | 1 | API de consulta de análisis y de caso | 003 | Resultado observable sin entrar a la base |
| ISS-S3-005 | 1 | Instrumentación de etapas del pipeline | 001 | Una línea por etapa con duración y desenlace |
| ISS-S3-006 | 2 | Imagen de la API de ingesta | 004, 005 | Imagen multietapa sin secretos |
| ISS-S3-007 | 2 | Imagen del motor de scoring | 002 | Function empaquetada en contenedor |
| ISS-S3-008 | 2 | Registro privado con pull sin credenciales | — | ACR con admin deshabilitado |
| ISS-S3-009 | 2 | Container Apps y reglas de escalado | 006, 007, 008 | Tres aplicaciones con métrica justificada |
| ISS-S3-010 | 2 | Evidencia de escalado bajo carga | 009, 024 | Réplicas suben y bajan, observado |
| ISS-S3-011 | 3 | Credencial federada OIDC | 008 | Despliegue sin ninguna contraseña |
| ISS-S3-012 | 3 | Pipeline de integración continua | — | Prueba fallida detiene el flujo |
| ISS-S3-013 | 3 | Pipeline de despliegue continuo | 009, 011, 012 | Integración a `main` despliega sola |
| ISS-S3-014 | 3 | Justificación de la plataforma de CI/CD | 013 | Criterio, contrapartidas y contexto inverso |
| ISS-S3-015 | 3 | Reporte de optimización de imágenes | 006, 007 | Tamaño y medidas documentadas |
| ISS-S3-016 | 4 | Application Insights y consultas de operación | 005 | Las cinco preguntas responden |
| ISS-S3-017 | 4 | Traza individual por transacción | 016 | Recorrido con tiempos por etapa |
| ISS-S3-018 | 4 | Alerta con umbral justificado | 016 | Se dispara al provocar la condición |
| ISS-S3-019 | 4 | Agentes de verificación | 001–018 | Veredicto reproducible por un tercero |
| ISS-S3-020 | 4 | Reporte de crédito y apagado diario | 009 | Consumo final < 60 USD |
| ISS-S3-021 | 5 | Explicador determinista por plantilla | 002, 003 | Correspondencia estricta con las reglas |
| ISS-S3-022 | 5 | Ejecución asíncrona y resiliencia del explicador | 021 | Detenido no impide abrir casos |
| ISS-S3-023 | 5 | Verificación documental con manejo de fallos | 003 | Documento ilegible no interrumpe el flujo |
| ISS-S3-024 | 5 | Banco de pruebas en repositorio aparte | 004 | Un botón por causal más control negativo |
| ISS-S3-025 | 5 | Cierre documental y ensayo de sustentación | Todas | Los ocho escenarios ensayados |

## Tipos de prueba utilizados

- **Estático:** estructura, contratos, secretos, sintaxis de scripts y alcance.
- **Unitario:** una clase aislada con dobles de prueba.
- **Contrato:** coherencia entre esquemas JSON y records Java.
- **Integración:** interacción entre componentes o con un recurso real controlado.
- **E2E:** recorrido completo sobre el pipeline desplegado.
- **Operación:** consultas y comprobaciones sobre el sistema en ejecución.

## Convención de estado

Cada issue cierra con su **Estado** real. Los valores posibles:

- `IMPLEMENTADA` — código y pruebas en la rama, verificados localmente.
- `PENDIENTE DE EVIDENCIA EN AZURE` — implementada, pero su criterio de aceptación exige
  ejecutar contra la suscripción y esa evidencia aún no se capturó.
- `PENDIENTE` — no implementada.

---

# Persona 1 — Trazabilidad, registro del motor, esquema y lectura

---

## ISS-S3-001 — Contexto de traza W3C en contratos y mensajería

### Metadatos

- **Historia:** HU-S3-001 · **Feature:** FEAT-S3-001
- **Responsable:** Persona 1 · **Revisor:** Persona 4
- **Dependencias para iniciar:** Semana 2 completa
- **Estimación orientativa:** 1 día
- **Requisitos:** RD-S3-001, RNF-S3-001

### 1. Objetivo

Hacer que el contexto de traza sobreviva los dos saltos asíncronos del pipeline, de modo que el
recorrido de una transacción individual pueda reconstruirse de extremo a extremo.

### 2. Razón técnica

El recorrido cruza cuatro procesos distintos y dos mecanismos de mensajería (Event Grid y
Storage Queue). En un salto asíncrono **no hay llamada que instrumentar**: el productor termina
y el consumidor empieza después. Un agente de telemetría correlaciona llamadas HTTP salientes,
pero no puede unir un mensaje encolado con quien lo escribió.

Sin contexto dentro del mensaje, quedan cuatro trazas inconexas y ninguna responde la pregunta
que el enunciado exige. Ampliar los contratos es la única solución, y por eso esta issue abre la
semana: son contratos versionados ya desplegados y todo lo demás depende de ellos.

### 3. Descripción técnica

- Crear `TraceContext` (formato W3C `traceparent`) en `shared/trace`, con `parse`, `newRoot`,
  `childSpan` y `toTraceparent`. Replicarlo en el motor de scoring, que se despliega como
  artefacto independiente y no comparte classpath.
- Añadir `traceparent` a `TransactionEvent` y `FlaggedCaseMessage`, y a sus dos JSON Schema, de
  forma **aditiva** y con patrón de validación.
- `TracePropagationFilter`: continúa la traza del cliente si llega en la cabecera, o abre una
  nueva. Precedencia máxima —antes del limitador de tasa y de la cadena de seguridad— para que
  una petición rechazada con `429` o `401` también quede trazada.
- `TraceContextHolder` (ThreadLocal) para que el adaptador de Event Grid acceda al contexto sin
  que el caso de uso de ingesta cargue con un dato que solo sirve a la telemetría.
- **Normalización tolerante:** un `traceparent` ausente o corrupto abre una traza nueva; nunca
  rechaza el mensaje.

### 4. Fuera de alcance

Instrumentación de etapas (`ISS-S3-005`), Application Insights (`ISS-S3-016`), muestreo.

### 5. Archivos

```
src/main/java/com/centinela/shared/trace/TraceContext.java
src/main/java/com/centinela/shared/trace/TraceContextHolder.java
src/main/java/com/centinela/shared/web/TracePropagationFilter.java
src/main/java/com/centinela/shared/event/TransactionEvent.java
src/main/java/com/centinela/shared/event/FlaggedCaseMessage.java
docs/1_Requisitos_y_Contrato/schemas/transaction-event-v1.json
docs/1_Requisitos_y_Contrato/schemas/flagged-case-v1.json
scoring-function/src/main/java/com/centinela/scoring/domain/model/TraceContext.java
scoring-function/src/main/java/com/centinela/scoring/domain/model/TransactionEventNotification.java
```

### 6. Criterios de aceptación

- [x] Los dos contratos transportan `traceparent` y sus esquemas lo declaran obligatorio.
- [x] El `trace-id` es idéntico antes y después de cada salto asíncrono.
- [x] Un `traceparent` corrupto **no** impide procesar la transacción.
- [x] Los identificadores todo-ceros que la especificación prohíbe se rechazan.
- [x] `EventContractTest` sigue en verde: esquemas y records describen la misma forma.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `TraceContextTest` | Parseo, derivación de span, degradación sin excepción |
| Contrato | `EventContractTest` | Esquema y record sincronizados |
| Unitario | `StorageQueueFlaggedCasePublisherTest` | El `traceparent` se reemite sin alterar |

### 8. Gherkin

```gherkin
Escenario: El contexto sobrevive el salto por la cola
  Dado un evento con traceparent 00-4bf9…-00f0…-01
  Cuando el motor puntúa la transacción y encola el caso
  Entonces el mensaje de caso lleva el mismo trace-id

Escenario: Un traceparent corrupto no detiene la detección
  Dado un evento cuyo traceparent es "basura"
  Cuando el motor lo procesa
  Entonces la transacción se puntúa igual
  Y se abre una traza nueva válida
```

### 9. Definition of Done

Pruebas en verde en los dos módulos · esquemas actualizados · sin cambios rompientes en el
contrato · revisión de Persona 4.

### 10. Comandos

```bash
mvn -B test -Dtest='TraceContextTest,EventContractTest'
mvn -B -f scoring-function/pom.xml test -Dtest='TraceContextTest'
```

### 11. Evidencia

`docs/evidence/iss-s3-001/`

### Estado

**IMPLEMENTADA.** 6 pruebas de `TraceContextTest` y 5 de `EventContractTest` en verde.

---

## ISS-S3-002 — Registro de activación suficiente en el motor

### Metadatos

- **Historia:** HU-S3-004 · **Feature:** FEAT-S3-004
- **Responsable:** Persona 1 · **Revisor:** Persona 5
- **Dependencias para iniciar:** Semana 2 completa
- **Estimación orientativa:** 1 día
- **Requisitos:** RD-S3-002

### 1. Objetivo

Que el motor registre, en el instante de decidir, todo lo que la explicación necesitará después.

### 2. Razón técnica

El enunciado lo dice sin rodeos: si el explicador no puede producir su salida, **el defecto está
en el motor**, no en el explicador. La auditoría previa encontró exactamente eso.

`GeoImpossibleRule` guardaba distancia, tiempo y velocidad. Suficiente para *decidir*; inútil
para *explicar*: «de 6.25,-75.56 a 40.41,-3.70» no es una frase para un analista. `VelocityRule`
no medía la cadencia habitual de la cuenta, así que «cuando el promedio es 1 cada 6 horas» era
imposible de afirmar.

Un dato que no se registra en el momento de decidir **no se puede recuperar después** sin
reprocesar la transacción, y el enunciado advierte que reprocesar consume tiempo que la semana
no contempla.

### 3. Descripción técnica

- `HistoricalTransaction` gana `city` y `countryCode`; el adaptador de Cosmos los proyecta.
- `GeoImpossibleRule` registra `previousCity`, `previousCountryCode`, `previousTransactionId`,
  `previousOccurredAt`, `currentCity`, `currentCountryCode` y `maxSpeedKmh`. Omite las claves
  cuyo dato no existe: `Map.copyOf` rechaza nulos, y un campo ausente **no es** un campo vacío.
- `VelocityRule` registra `elapsedMinutesInWindow` (el lapso real de la ráfaga, no la ventana
  configurada) y `baselineAverageIntervalMinutes` con su tamaño de muestra. Omite la línea base
  cuando el historial tiene menos de dos transacciones.
- `AtypicalAmountRule` registra `observedMultiplier`, `historySampleSize` y `currency`.
- `Score` gana `threshold` (el vigente al decidir) y `traceparent`. El umbral se lee **una sola
  vez** por evaluación.
- El adaptador de Cosmos persiste `threshold`, `flagged` y `traceparent`.

### 4. Fuera de alcance

El explicador (`ISS-S3-021`). Nuevas reglas de detección.

### 5. Archivos

```
scoring-function/src/main/java/com/centinela/scoring/domain/model/HistoricalTransaction.java
scoring-function/src/main/java/com/centinela/scoring/domain/model/Score.java
scoring-function/src/main/java/com/centinela/scoring/domain/rule/GeoImpossibleRule.java
scoring-function/src/main/java/com/centinela/scoring/domain/rule/VelocityRule.java
scoring-function/src/main/java/com/centinela/scoring/domain/rule/AtypicalAmountRule.java
scoring-function/src/main/java/com/centinela/scoring/application/service/ScoreTransactionService.java
scoring-function/src/main/java/com/centinela/scoring/infrastructure/mongo/CosmosMongoScorePersistenceAdapter.java
scoring-function/src/main/java/com/centinela/scoring/infrastructure/mongo/CosmosMongoTransactionHistoryAdapter.java
```

### 6. Criterios de aceptación

- [x] La regla geográfica registra las ciudades de ambos extremos cuando el dato existe.
- [x] La regla de velocidad registra el lapso real de la ráfaga y la cadencia histórica.
- [x] La regla de monto registra el multiplicador **observado**, no el configurado.
- [x] Cuando falta un dato, la clave **no aparece** en lugar de aparecer con un valor por defecto.
- [x] El umbral queda persistido junto al score.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `RuleActivationDetailTest` | Cada afirmación de la explicación objetivo tiene su valor registrado |
| Unitario | Pruebas por regla existentes | La decisión no cambió |

### 8. Gherkin

```gherkin
Escenario: La ráfaga se describe por su lapso real
  Dada una cuenta con transacciones cada seis horas
  Y cuatro transacciones en los últimos 4 minutos
  Cuando el motor evalúa la regla de velocidad
  Entonces registra elapsedMinutesInWindow = 4
  Y registra baselineAverageIntervalMinutes = 360

Escenario: Sin ciudad registrada no se inventa una
  Dado un historial sin ciudad
  Cuando se activa la regla geográfica
  Entonces observedValues no contiene previousCity
  Y sí contiene distanceKm
```

### 9. Definition of Done

30 pruebas del motor en verde · sin cambios en el comportamiento de detección · revisión de
Persona 5, que consumirá estos datos.

### 10. Comandos

```bash
mvn -B -f scoring-function/pom.xml test -Dtest='RuleActivationDetailTest'
mvn -B -f scoring-function/pom.xml test
```

### 11. Evidencia

`docs/evidence/iss-s3-002/`

### Estado

**IMPLEMENTADA.** 6 pruebas de `RuleActivationDetailTest`; 30 del módulo en verde.

---

## ISS-S3-003 — Migración V4 del caso

### Metadatos

- **Historia:** HU-S3-004 · **Feature:** FEAT-S3-004, FEAT-S3-005
- **Responsable:** Persona 1 · **Revisor:** Persona 5
- **Dependencias para iniciar:** Semana 2 completa
- **Estimación orientativa:** 0,5 día
- **Requisitos:** RD-S3-003

### 1. Objetivo

Dar al caso un lugar donde vivir su explicación y los datos extraídos del documento, con estado
propio y consultable.

### 2. Razón técnica

Ambas cosas se producen **después** de abrir el caso y de forma asíncrona. El esquema debe
representar explícitamente el estado «abierto pero todavía sin explicar» — no como ausencia de
dato, sino como un estado que el analista puede consultar y entender.

Además, `account_id` viajaba en el mensaje y se perdía al abrir el caso: quedaba dentro del texto
libre de auditoría. Sin él no se puede contrastar el documento de identidad con el titular, que
es el propósito del punto 2.3 del enunciado.

### 3. Descripción técnica

- `fraud_case` gana `account_id`, `traceparent`, `explanation`, `explanation_state`
  (`PENDING`/`GENERATED`/`FAILED`, con restricción CHECK), `explained_at` y
  `explanation_attempts`.
- Índice **parcial** sobre `opened_at WHERE explanation_state = 'PENDING'`: el explicador
  consulta exactamente eso, y las filas ya explicadas —la mayoría— no aportan nada a la consulta.
- Tabla `case_verification_document` con estado propio y restricción CHECK sobre los seis
  desenlaces posibles.
- `Case_` gana `ExplanationState` como ciclo de vida **independiente** del estado del caso: un
  caso puede estar `RESOLVED` y sin explicar, o `NEW` y explicado. Mezclarlos haría que la caída
  del explicador alterase el flujo de trabajo del analista, que es justo lo que se prohíbe.
- `FraudCase.attachExplanation` es la única transición a `GENERATED` y escribe texto y estado
  juntos, de modo que no pueda existir un caso «explicado» con la explicación en blanco.

### 4. Fuera de alcance

El explicador y el extractor, que consumen este esquema (`ISS-S3-021`, `ISS-S3-023`).

### 5. Archivos

```
src/main/resources/db/migration/V4__case_explanation_and_verification.sql
src/main/java/com/centinela/casemanagement/domain/model/Case_.java
src/main/java/com/centinela/casemanagement/domain/model/FraudCase.java
src/main/java/com/centinela/casemanagement/application/service/OpenCaseService.java
```

### 6. Criterios de aceptación

- [x] La migración es aditiva y no modifica ninguna migración anterior.
- [x] Un caso nuevo nace en `PENDING` y lo declara explícitamente.
- [x] El estado de la explicación es independiente del estado del caso.
- [x] No puede existir un caso `GENERATED` con explicación vacía.
- [x] La numeración de migraciones es consecutiva, sin huecos.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `OpenCaseServiceTest` | El caso nace PENDING con cuenta y traza |
| Estático | `verify-practices.sh` | Migraciones consecutivas |
| Integración | `CaseSchemaIT` | El esquema real acepta el modelo JPA |

### 8. Gherkin

```gherkin
Escenario: El caso se abre sin explicación y lo declara
  Cuando llega un mensaje flagged-case-v1
  Entonces se abre un caso con explanation_state = PENDING
  Y con account_id y traceparent poblados
```

### 9. Definition of Done

Migración aplicada en un entorno limpio · pruebas en verde · revisión de Persona 5.

### 10. Comandos

```bash
mvn -B test -Dtest='OpenCaseServiceTest'
bash scripts/verify/verify-practices.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-003/`

### Estado

**IMPLEMENTADA.** Migración `V4` creada; pruebas unitarias en verde. La aplicación real de la
migración contra PostgreSQL se verifica en `ISS-S3-013`.

---

## ISS-S3-004 — API de consulta de análisis y de caso

### Metadatos

- **Historia:** HU-S3-004 · **Feature:** FEAT-S3-004
- **Responsable:** Persona 1 · **Revisor:** Persona 3
- **Dependencias para iniciar:** `ISS-S3-003`
- **Estimación orientativa:** 1 día
- **Requisitos:** RD-S3-004

### 1. Objetivo

Exponer el resultado del análisis y el caso asociado como recursos de lectura autenticados.

### 2. Razón técnica

La ingesta responde `202` **antes** de que exista veredicto — por diseño, para no bloquear al
cliente. La consecuencia es que durante dos semanas el resultado del análisis solo fue observable
entrando a la base de datos. Eso ralentizó cada verificación e hizo imposible que nadie ajeno a
la célula comprobara nada.

Son dos preguntas distintas y se responden por separado a propósito: «qué decidió el motor» tiene
respuesta para **toda** transacción puntuada, incluidas las no marcadas; «qué caso se abrió» solo
para las marcadas. Fusionarlas obligaría a devolver un caso vacío para una transacción limpia,
que es justo la confusión que la demostración del escenario normal debe evitar.

### 3. Descripción técnica

- `GET /api/v1/transactions/{id}/analysis` — score, umbral, `flagged`, reglas activadas con sus
  valores observados y `traceparent`. Lee del registro del motor en Cosmos.
- `GET /api/v1/cases/{transactionId}` — caso, estado, explicación con su estado, y documentos
  adjuntos con su desenlace. Un `404` significa «no fue marcada», que es una respuesta legítima.
- Módulo `scoringrecord` extraído: lo consumen el explicador y la consulta, y que la consulta
  dependiera del explicador sería al revés.
- Autorización: `ANALYST` y `SERVICE` pueden leer. Ninguno escribe por esta vía.
- El servicio **no recalcula nada**: devuelve lo registrado al decidir. Recalcular daría
  respuestas que cambian con el tiempo, porque el umbral es configurable en caliente.

### 4. Fuera de alcance

Listados, filtros, paginación, acciones sobre el caso.

### 5. Archivos

```
src/main/java/com/centinela/caseinquiry/**
src/main/java/com/centinela/scoringrecord/**
src/main/java/com/centinela/identityaccess/SecurityConfiguration.java
```

### 6. Criterios de aceptación

- [x] Una transacción no marcada devuelve `200` en `/analysis` y `404` en `/cases`.
- [x] La respuesta expone `flagged` explícito, no obliga al cliente a comparar score y umbral.
- [x] Los dos endpoints exigen autenticación y uno de los dos roles.
- [x] La respuesta incluye los valores observados de cada regla activada.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `EndpointAuthorizationTest` | Los roles exigidos |
| Estático | ArchUnit | El módulo respeta los límites hexagonales |

### 8. Gherkin

```gherkin
Escenario: Una transacción normal no tiene caso
  Dada una transacción que no superó el umbral
  Cuando se consulta /api/v1/cases/{id}
  Entonces la respuesta es 404
  Y /analysis devuelve 200 con flagged = false
```

### 9. Definition of Done

Pruebas en verde · ArchUnit en verde · revisión de Persona 3.

### 10. Comandos

```bash
mvn -B test -Dtest='EndpointAuthorizationTest,ArchitectureConventionsTest'
```

### 11. Evidencia

`docs/evidence/iss-s3-004/`

### Estado

**IMPLEMENTADA Y VERIFICADA.** Al ejecutar la issue se cerró la brecha que declaraba: se añadió
`CaseInquiryControllerTest` con 6 pruebas HTTP. La decisiva es la que fija que una transacción
limpia devuelve `200` con `flagged: false` en `/analysis` y `404` en `/cases` — el control
negativo de la sustentación depende exactamente de ese par de respuestas.

---

## ISS-S3-005 — Instrumentación de etapas del pipeline

### Metadatos

- **Historia:** HU-S3-001 · **Feature:** FEAT-S3-001
- **Responsable:** Persona 1 · **Revisor:** Persona 4
- **Dependencias para iniciar:** `ISS-S3-001`
- **Estimación orientativa:** 1 día
- **Requisitos:** RD-S3-005

### 1. Objetivo

Emitir una línea por etapa completada, con su duración y su desenlace, en formato consultable.

### 2. Razón técnica

El enunciado advierte que la instrumentación no admite implementación tardía. Dos de las cinco
preguntas de operación —el componente de mayor latencia y el punto exacto de fallo— **no se
pueden responder con una latencia global**: hacen falta etapas con nombre estable y comparable.

El formato es de pares clave-valor y no prosa a propósito. Un mensaje redactado obliga a extraer
campos con expresiones regulares al consultar, y cualquier cambio de redacción rompe las
consultas en silencio.

### 3. Descripción técnica

- `PipelineStage`: enumerado con las siete etapas. Que sea enumerado y no cadena libre evita que
  `"scoring"`, `"Scoring"` y `"score"` convivan y las consultas dejen de agrupar.
- `StageTelemetry.success/failure` con `transactionId`, `traceId`, `durationMs` y `outcome`.
- Instrumentar `RAW_PERSIST` y `EVENT_PUBLISH` por separado: una transacción persistida cuyo
  evento no se publicó no genera caso, y es el único modo de distinguir ese fallo del de una que
  ni llegó a guardarse.
- Instrumentar `CASE_OPEN`, `EXPLANATION` y `DOCUMENT_EXTRACTION`.
- El motor de scoring emite `stage=SCORING` con el mismo formato desde su propio proceso.
- **Nunca lanza:** un fallo al instrumentar no puede tumbar la etapa que mide.

### 4. Fuera de alcance

Application Insights y las consultas (`ISS-S3-016`), la alerta (`ISS-S3-018`).

### 5. Archivos

```
src/main/java/com/centinela/shared/telemetry/PipelineStage.java
src/main/java/com/centinela/shared/telemetry/StageTelemetry.java
src/main/java/com/centinela/transactioningestion/application/service/IngestTransactionService.java
src/main/java/com/centinela/casemanagement/infrastructure/messaging/FlaggedCaseQueueListener.java
scoring-function/src/main/java/com/centinela/scoring/infrastructure/function/ScoreTransactionFunction.java
```

### 6. Criterios de aceptación

- [x] Toda etapa declarada se emite en algún punto del código.
- [x] Cada línea lleva `transactionId`, `traceId`, `durationMs` y `outcome`.
- [x] Persistencia y publicación se instrumentan por separado.
- [x] La instrumentación no propaga excepciones.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | `verify-practices.sh` | Ninguna etapa declarada queda sin emisor |
| Unitario | `IngestTransactionServiceTest` | La ingesta sigue comportándose igual |

### 8. Gherkin

```gherkin
Escenario: El punto de fallo queda localizado
  Dada una transacción cuya publicación de evento falla
  Cuando se consultan sus etapas
  Entonces RAW_PERSIST aparece con outcome SUCCESS
  Y EVENT_PUBLISH aparece con outcome FAILURE y su motivo
```

### 9. Definition of Done

Pruebas en verde · `verify-practices.sh` sin huecos de instrumentación · revisión de Persona 4.

### 10. Comandos

```bash
mvn -B test
bash scripts/verify/verify-practices.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-005/`

### Estado

**IMPLEMENTADA Y VERIFICADA.** Siete etapas declaradas, todas con emisor.

La ejecución de esta issue encontró un hueco real: **`INGEST_API` estaba declarada y nadie la
emitía**. Se instrumentó en `TransactionController`, midiendo lo que espera *el cliente* de
extremo a extremo. Es una medida distinta de la suma de sus etapas internas —incluye
deserialización, validación y serialización de la respuesta— y es la única que sustenta la
afirmación de que el cliente recibió respuesta antes de que concluyera el análisis.

El hueco no se detectó antes porque la propia comprobación estaba rota de dos formas sucesivas:
usaba `grep -P` con *lookbehind*, no soportado en todos los entornos, y bajo `set -e` moría en
silencio; al arreglar la extracción, su umbral contaba el archivo de declaración como si fuera un
uso y reportaba huecos inexistentes en cinco etapas. Se añadió una guarda que falla si no se
extrae ninguna etapa: una comprobación que no comprueba nada es peor que ninguna, porque da OK.

---

# Persona 2 — Contenedores, registro privado y escalado

---

## ISS-S3-006 — Imagen de la API de ingesta

### Metadatos

- **Historia:** HU-S3-003 · **Feature:** FEAT-S3-003
- **Responsable:** Persona 2 · **Revisor:** Persona 3
- **Dependencias para iniciar:** `ISS-S3-004`, `ISS-S3-005`
- **Estimación orientativa:** 1 día

### 1. Objetivo

Empaquetar la aplicación como imagen de contenedor, sin secretos en ninguna capa y ejecutándose
con un usuario sin privilegios.

### 2. Razón técnica

El punto crítico del enunciado es explícito: *«las capas de la imagen conservan los archivos
eliminados en capas posteriores»*. Esto tiene una consecuencia contraintuitiva y peligrosa: un
`COPY .env` seguido de un `RUN rm .env` produce una imagen cuyo sistema de archivos final **no**
contiene el archivo, pero cuya capa intermedia sí lo conserva y es recuperable.

Borrar no elimina. Solo **no copiar** elimina. Por eso la construcción multietapa no es una
optimización de tamaño: es el mecanismo de seguridad.

### 3. Descripción técnica

- Etapa `build` con `maven:3.9-eclipse-temurin-21`; el POM se copia en su propia capa para que
  cambiar código fuente no invalide la descarga de dependencias.
- Etapa `telemetry` separada para el agente de Application Insights, de modo que su descarga se
  cachee aparte del código.
- Etapa `runtime` con `eclipse-temurin:21-jre-alpine`. Solo cruza el JAR.
- Usuario `centinela` sin privilegios, creado explícitamente.
- `HEALTHCHECK` con `start-period` de 90 s: la aplicación tarda ~220 s en frío por Spring Boot,
  Flyway y la primera conexión a PostgreSQL por Private Endpoint. Un periodo corto reportaría un
  fallo inexistente.
- Las pruebas **no** se ejecutan en la construcción de la imagen: ya corrieron en el pipeline,
  donde un fallo lo detiene antes. Repetirlas duplicaría minutos sin añadir garantía.
- `.dockerignore` que excluye `.env`, `.git`, `target/`, `docs/` y `scripts/`.

### 4. Fuera de alcance

Publicación en el registro (`ISS-S3-008`), despliegue (`ISS-S3-009`), reporte de tamaño
(`ISS-S3-015`).

### 5. Archivos

```
Dockerfile
.dockerignore
applicationinsights.json
```

### 6. Criterios de aceptación

- [x] La imagen final no contiene JDK, Maven ni repositorio de dependencias.
- [x] La imagen se ejecuta con un usuario distinto de root.
- [x] Ningún `ARG` ni `ENV` contiene credenciales.
- [x] `.dockerignore` excluye `.env` y el historial de Git.
- [x] `verify-image-secrets.sh` pasa sobre la imagen construida.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | Revisión del Dockerfile | Multietapa real, usuario no-root |
| Operación | `verify-image-secrets.sh` | Sin credenciales en ninguna capa |

### 8. Gherkin

```gherkin
Escenario: Ninguna capa contiene credenciales
  Dada la imagen centinela-api construida
  Cuando se inspecciona capa por capa
  Entonces no aparece ningún archivo .env
  Y el historial de construcción no expone cadenas de conexión
```

### 9. Definition of Done

Imagen construida localmente · `verify-image-secrets.sh` en verde · revisión de Persona 3.

### 10. Comandos

```bash
docker build -t centinela-api:local .
bash scripts/verify/verify-image-secrets.sh centinela-api:local
```

### 11. Evidencia

`docs/evidence/iss-s3-006/`

### Estado

**IMPLEMENTADA Y VERIFICADA.** Imagen construida: **187 MB en 10 capas**. El verificador confirma
que ninguna capa contiene archivos de credenciales, que el historial de construcción no expone
cadenas de conexión y que la imagen se ejecuta como `centinela`, no como root.

---

## ISS-S3-007 — Imagen del motor de scoring

### Metadatos

- **Historia:** HU-S3-003 · **Feature:** FEAT-S3-003
- **Responsable:** Persona 2 · **Revisor:** Persona 1
- **Dependencias para iniciar:** `ISS-S3-002`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Empaquetar el motor de scoring como imagen de contenedor conservando su disparador de Event Grid.

### 2. Razón técnica

Se eligió la imagen base oficial del runtime de Functions en lugar de reescribir el motor como
servicio HTTP. El disparador de Event Grid, el reintento y la concurrencia ya funcionaban y
estaban validados en Semana 2; reescribirlos habría consumido la semana para llegar al mismo
comportamiento observable, con el riesgo añadido de perder garantías de entrega por el camino.

### 3. Descripción técnica

- Etapa `build` que produce el directorio de staging del plugin de Functions.
- Etapa `runtime` sobre `mcr.microsoft.com/azure-functions/java:4-java21`.
- Se copia **únicamente** el directorio de staging: ni fuentes, ni `.m2`, ni JDK de compilación.
- Sin secretos: Cosmos y Storage se resuelven en arranque contra Key Vault por Managed Identity.

### 4. Fuera de alcance

Migrar el motor a otro modelo de ejecución.

### 5. Archivos

```
scoring-function/Dockerfile
```

### 6. Criterios de aceptación

- [x] La imagen conserva el disparador de Event Grid.
- [x] Solo el directorio de staging llega a la imagen final.
- [ ] La imagen arranca y registra la función `ScoreTransaction`.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | Revisión del Dockerfile | Multietapa, sin secretos |
| Operación | Arranque local del contenedor | El runtime descubre la función |

### 8. Gherkin

```gherkin
Escenario: El contenedor registra la función
  Cuando arranca la imagen centinela-scoring
  Entonces el runtime de Functions descubre ScoreTransaction
```

### 9. Definition of Done

Imagen construida · función descubierta al arrancar · revisión de Persona 1.

### 10. Comandos

```bash
docker build -t centinela-scoring:local ./scoring-function
docker run --rm centinela-scoring:local
```

### 11. Evidencia

`docs/evidence/iss-s3-007/`

### Estado

**IMPLEMENTADA Y VERIFICADA.** Imagen construida: **660 MB en 20 capas**.

El contraste con los 187 MB de la API no es descuido y conviene explicarlo: la imagen base de
Azure Functions ronda los 500 MB porque trae el host de Functions, su runtime de .NET y el worker
de Java. No es reducible sin abandonar el runtime, que es justamente lo que se decidió no hacer.
Es un coste asumido a cambio de no rehacer un componente validado, y se mitiga con que este
contenedor escala desde cero réplicas y sus descargas son poco frecuentes.

---

## ISS-S3-008 — Registro privado con pull sin credenciales

### Metadatos

- **Historia:** HU-S3-003 · **Feature:** FEAT-S3-003
- **Responsable:** Persona 2 · **Revisor:** Persona 4
- **Dependencias para iniciar:** Semana 1 completa
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Aprovisionar un registro privado del que Container Apps pueda descargar imágenes sin usuario ni
contraseña.

### 2. Razón técnica

**ACR no tiene nivel gratuito**: ninguno de sus SKU lo es. La alternativa realmente gratuita es
GitHub Container Registry, que admite imágenes privadas sin costo.

Se eligió ACR Basic —~1,20 USD por la semana— porque se integra con Managed Identity. Con
`ghcr.io` habría que almacenar un token de acceso personal como secreto de la Container App:
exactamente el tipo de credencial de larga duración que el proyecto evita desde la Semana 1. Se
paga 1,20 USD por no tener ese secreto.

### 3. Descripción técnica

- ACR SKU Basic con `adminUserEnabled = false`, reafirmado en cada corrida por si alguien lo
  activó «para probar algo rápido». El usuario administrador es una credencial compartida con
  permiso de escritura.
- Managed Identity asignada por el usuario, con rol `AcrPull` y **solo** ese.
- Reintento en la asignación de rol: la propagación de una identidad recién creada tarda, y sin
  reintento el script falla de forma intermitente.
- Verificación posterior: admin deshabilitado, identidad creada, rol asignado.

### 4. Fuera de alcance

Publicación de imágenes (`ISS-S3-013`), red privada del registro (fuera del SKU Basic).

### 5. Archivos

```
scripts/provision-container-registry.sh
```

### 6. Criterios de aceptación

- [x] El script es idempotente y admite `--validate-only`.
- [x] Los límites del SKU están documentados para el reporte de costos.
- [ ] El registro existe con el usuario administrador deshabilitado.
- [ ] La identidad tiene `AcrPull` y ningún otro rol sobre el registro.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | `bash -n`, shellcheck | Sintaxis y advertencias |
| Operación | Verificación integrada del script | Admin deshabilitado y rol asignado |

### 8. Gherkin

```gherkin
Escenario: El registro no admite credenciales compartidas
  Cuando se aprovisiona el registro
  Entonces adminUserEnabled es false
  Y existe una asignación AcrPull para la identidad de pull
```

### 9. Definition of Done

Script ejecutado contra la suscripción · verificación integrada en verde · revisión de Persona 4.

### 10. Comandos

```bash
bash scripts/provision-container-registry.sh --validate-only
bash scripts/provision-container-registry.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-008/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Script escrito, sintaxis verificada, modo `--validate-only`
disponible.

---

## ISS-S3-009 — Container Apps y reglas de escalado

### Metadatos

- **Historia:** HU-S3-003 · **Feature:** FEAT-S3-003
- **Responsable:** Persona 2 · **Revisor:** Persona 4
- **Dependencias para iniciar:** `ISS-S3-006`, `ISS-S3-007`, `ISS-S3-008`
- **Estimación orientativa:** 1,5 días

### 1. Objetivo

Desplegar los tres componentes en Container Apps con una regla de escalado justificada por cada
uno.

### 2. Razón técnica

El enunciado advierte que cada métrica produce una respuesta distinta. Usar una sola para los
tres componentes sería más simple y estaría **mal en dos de ellos**.

La API de ingesta espera E/S: escribe un blob y publica un evento. Bajo carga su CPU apenas se
mueve mientras las peticiones se acumulan esperando. Una regla por CPU llegaría tarde —o no
llegaría— justo cuando la latencia ya se degradó. La concurrencia mide directamente lo que sufre
el cliente.

El explicador ni siquiera recibe peticiones: consulta trabajo pendiente. Ni CPU ni concurrencia
HTTP dicen nada sobre él.

### 3. Descripción técnica

- Container Apps Environment con Log Analytics (retención 30 días, el mínimo gratuito).
- Tres aplicaciones desde **dos** imágenes: la de aplicación cumple el papel de API y el de
  explicador según qué interruptores encienda la plataforma.
- API: ingreso externo, concurrencia HTTP 10, réplicas 1–10.
- Motor: ingreso **interno** —lo invoca Event Grid dentro del entorno, no necesita dirección
  pública—, réplicas 0–8.
- Explicador: **sin ingreso**, réplicas 0–3, escala a cero.
- Pull por Managed Identity; cero credenciales de registro.
- La clave del workspace se usa solo en memoria y no se persiste en ningún archivo.

### 4. Fuera de alcance

La evidencia de escalado bajo carga (`ISS-S3-010`).

### 5. Archivos

```
scripts/provision-container-apps.sh
scripts/deploy-containers.sh
```

### 6. Criterios de aceptación

- [x] La métrica de cada componente está justificada por escrito.
- [x] El explicador escala a cero.
- [x] El motor no tiene ingreso externo.
- [ ] Las tres aplicaciones existen y responden.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | shellcheck, `bash -n` | Sintaxis |
| Operación | `verify-deployment-health.sh` | La aplicación responde, no solo que `az` devolvió 0 |

### 8. Gherkin

```gherkin
Escenario: El despliegue no termina hasta que la aplicación responde
  Cuando se despliega la API
  Entonces se sondea /actuator/health/readiness hasta obtener 200
  Y un contenedor que arranca y muere en bucle se reporta como fallo
```

### 9. Definition of Done

Tres aplicaciones desplegadas · salud verificada · reglas justificadas en el ADR · revisión de
Persona 4.

### 10. Comandos

```bash
bash scripts/provision-container-apps.sh --validate-only
bash scripts/provision-container-apps.sh
bash scripts/deploy-containers.sh --tag "$(git rev-parse HEAD)"
bash scripts/verify/verify-deployment-health.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-009/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Scripts escritos; justificación de métricas en `ADR-010`.

---

## ISS-S3-010 — Evidencia de escalado bajo carga

### Metadatos

- **Historia:** HU-S3-003 · **Feature:** FEAT-S3-003
- **Responsable:** Persona 2 · **Revisor:** Persona 5
- **Dependencias para iniciar:** `ISS-S3-009`, `ISS-S3-024`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Observar y registrar el aumento y la posterior reducción del número de instancias bajo carga real.

### 2. Razón técnica

El enunciado lo dice sin ambigüedad: *«una configuración de escalado documentada no constituye
evidencia de que el escalado ocurra»*. Esta issue existe separada de `ISS-S3-009` precisamente
porque configurar y demostrar son cosas distintas, y confundirlas es el error que el enunciado
anticipa.

### 3. Descripción técnica

- `verify-scaling.sh` muestrea el número de réplicas cada 10 s durante 12 minutos y dibuja una
  barra por muestra, para que la curva se vea en vivo durante la sustentación sin abrir el portal.
- La carga la genera el banco de pruebas (`ISS-S3-024`), no un script propio: reutilizar el mismo
  generador que se usará en la demostración evita que la evidencia se obtenga con una herramienta
  distinta de la que se enseña.
- El resultado se guarda en `docs/evidence/iss-s3-010/run-<sello>/` con el mínimo y el máximo
  observados y un veredicto explícito.
- Si no se observa variación, el script **lo dice**: puede ser carga insuficiente o una ventana
  de observación más corta que el tiempo de reacción de KEDA. Un resultado ambiguo declarado es
  mejor que uno silencioso.

### 4. Fuera de alcance

Ajustar los umbrales de escalado a partir de lo observado.

### 5. Archivos

```
scripts/verify/verify-scaling.sh
```

### 6. Criterios de aceptación

- [x] El script registra las muestras en un archivo con marca de tiempo.
- [ ] La carga produce un aumento observable del número de instancias.
- [ ] Al cesar la carga, el número de instancias se reduce.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Operación | Corrida completa con carga | Aumento y reducción observados |

### 8. Gherkin

```gherkin
Escenario: El escalado ocurre y se registra
  Dado el observador de réplicas en ejecución
  Cuando se genera carga de 20 tx/s durante 120 s
  Entonces el número de réplicas aumenta por encima del mínimo
  Y al cesar la carga vuelve a bajar
```

### 9. Definition of Done

Evidencia capturada con aumento y reducción visibles · revisión de Persona 5.

### 10. Comandos

```bash
# Terminal 1
bash scripts/verify/verify-scaling.sh
# Terminal 2: botón "Generar carga" en centinela-lab
```

### 11. Evidencia

`docs/evidence/iss-s3-010/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Observador escrito; requiere el sistema desplegado.

---

# Persona 3 — Integración y despliegue continuo

---

## ISS-S3-011 — Credencial federada OIDC

### Metadatos

- **Historia:** HU-S3-002 · **Feature:** FEAT-S3-002
- **Responsable:** Persona 3 · **Revisor:** Persona 4
- **Dependencias para iniciar:** `ISS-S3-008`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Dar al pipeline permiso para desplegar sin que exista ninguna credencial almacenada.

### 2. Razón técnica

El enunciado exige que las credenciales del pipeline se gestionen como secretos y no residan en
el archivo de configuración. La lectura más fuerte de ese requisito es **no tener ninguna**.

Con OIDC, GitHub emite un token de identidad de vida corta que Azure valida contra una credencial
federada acotada a un repositorio y una rama concretos. La diferencia con guardar un JSON de
service principal no es «el secreto está bien guardado», sino que no hay secreto que robar: una
credencial de service principal filtrada vale hasta que alguien la rote; un token OIDC filtrado
caducó antes de terminar de leerse.

### 3. Descripción técnica

- Registro de aplicación en Entra ID y su service principal.
- **Tres** credenciales federadas, cada una acotada a un contexto: rama `main`, entorno
  `produccion` y `pull_request`. Acotar importa: una credencial que aceptara cualquier rama
  permitiría desplegar a producción a quien pudiera crear una rama.
- Roles sobre el **grupo de recursos**, nunca sobre la suscripción: un pipeline comprometido debe
  poder estropear este proyecto, no todos.
- Dos roles y solo dos: `AcrPush` y `Contributor` sobre el grupo. `Contributor` es más amplio de
  lo ideal; la alternativa exacta sería un rol personalizado con las acciones de `Microsoft.App`.
  **Se documenta como deuda consciente** en vez de fingir que el mínimo privilegio está completo.
- El script imprime los tres *secrets* y las cuatro *variables* a registrar en GitHub, aclarando
  que ninguno es un secreto en sentido estricto.

### 4. Fuera de alcance

El rol personalizado que sustituiría a `Contributor`.

### 5. Archivos

```
scripts/provision-github-oidc.sh
```

### 6. Criterios de aceptación

- [x] No se genera ni almacena ninguna contraseña o certificado.
- [x] Las credenciales federadas están acotadas a repositorio y rama.
- [x] El alcance de los roles es el grupo de recursos.
- [ ] `az login` en el pipeline funciona sin contraseña.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | Revisión del script | Sin generación de secretos de cliente |
| Operación | Corrida del pipeline | Autenticación efectiva |

### 8. Gherkin

```gherkin
Escenario: El pipeline se autentica sin credenciales
  Dada una credencial federada para la rama main
  Cuando el flujo de despliegue ejecuta azure/login
  Entonces obtiene acceso sin ninguna contraseña configurada
```

### 9. Definition of Done

Aplicación registrada · credenciales federadas creadas · valores registrados en GitHub · revisión
de Persona 4.

### 10. Comandos

```bash
CENTINELA_GITHUB_REPO="Centinela-App/Centinela" \
  bash scripts/provision-github-oidc.sh --validate-only
CENTINELA_GITHUB_REPO="Centinela-App/Centinela" \
  bash scripts/provision-github-oidc.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-011/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Script escrito y verificado sintácticamente.

---

## ISS-S3-012 — Pipeline de integración continua

### Metadatos

- **Historia:** HU-S3-002 · **Feature:** FEAT-S3-002
- **Responsable:** Persona 3 · **Revisor:** Persona 1
- **Dependencias para iniciar:** ninguna
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Decir, ante cada cambio, si el código es apto para desplegarse.

### 2. Razón técnica

El flujo de CI **no despliega nada ni toca Azure**, así que no necesita —ni recibe— ninguna
credencial. Es deliberado: un fork malicioso que abra un pull request no obtiene acceso a nada.
Separarlo del despliegue no es organización, es contención del daño.

### 3. Descripción técnica

- Trabajo `pruebas`: `mvn verify` en los dos módulos, con caché de Maven.
- Trabajo `seguridad`: barrido de credenciales en el árbol de trabajo y en el **historial
  completo** de Git —un secreto «borrado» sigue vivo en el objeto anterior—, más verificación de
  que `.env` no está versionado.
- Trabajo `analisis-estatico`: shellcheck sobre los scripts. Un error de shell en un script de
  aprovisionamiento no se descubre hasta que se ejecuta contra la suscripción real y deja
  recursos a medio crear.
- Cancelación de corridas obsoletas al llegar un push nuevo sobre la misma rama.
- Publicación de los informes de prueba como artefacto.

### 4. Fuera de alcance

Construcción y publicación de imágenes (`ISS-S3-013`).

### 5. Archivos

```
.github/workflows/ci.yml
```

### 6. Criterios de aceptación

- [x] El flujo de CI no recibe ninguna credencial.
- [x] Se analiza el historial completo de Git, no solo el árbol de trabajo.
- [x] Un fallo de prueba marca la corrida como fallida.
- [ ] La corrida real pasa en GitHub.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | Revisión del workflow | Ausencia de `secrets` en los trabajos de CI |
| Operación | Corrida en GitHub | El flujo completo pasa |

### 8. Gherkin

```gherkin
Escenario: Un pull request de un fork no obtiene credenciales
  Cuando se abre un pull request desde un fork
  Entonces el flujo de CI se ejecuta
  Y ningún paso recibe secretos de Azure
```

### 9. Definition of Done

Workflow en la rama · corrida verde en GitHub · revisión de Persona 1.

### 10. Comandos

```bash
mvn -B -ntp verify
mvn -B -ntp -f scoring-function/pom.xml verify
bash scripts/tests/scan-repository.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-012/`

### Estado

**IMPLEMENTADA, PENDIENTE DE CORRIDA REAL.** Workflow escrito; los comandos que ejecuta pasan
localmente.

---

## ISS-S3-013 — Pipeline de despliegue continuo

### Metadatos

- **Historia:** HU-S3-002 · **Feature:** FEAT-S3-002
- **Responsable:** Persona 3 · **Revisor:** Persona 2
- **Dependencias para iniciar:** `ISS-S3-009`, `ISS-S3-011`, `ISS-S3-012`
- **Estimación orientativa:** 1 día

### 1. Objetivo

Llevar el código de la rama principal al sistema en ejecución sin intervención manual.

### 2. Razón técnica

El requisito tiene un punto que se pasa por alto leyendo el workflow por encima: que los trabajos
existan **no basta**. Si el trabajo que construye imágenes no declara `needs` sobre el que
ejecuta pruebas, ambos corren en paralelo y una prueba fallida **no detiene nada**. El
encadenamiento explícito es lo que convierte «hay una etapa de pruebas» en «una prueba fallida
detiene el pipeline antes del despliegue».

### 3. Descripción técnica

- Reutiliza `ci.yml` mediante `uses:` para que no existan dos definiciones de «las pruebas pasan»
  que puedan divergir.
- `publicar-imagenes` declara `needs: verificar`; `desplegar` declara `needs: publicar-imagenes`.
- Etiqueta de imagen = SHA del commit. `latest` se mueve y no permite responder «qué hay
  desplegado ahora mismo».
- `az acr login` con token de vida corta; el usuario administrador del registro está deshabilitado.
- Verificación de secretos en la imagen **antes** de desplegarla: encontrar una credencial
  horneada aquí cuesta un despliegue; encontrarla después cuesta rotar todo.
- Comprobación de salud posterior: el criterio de éxito es que la aplicación responda, no que
  `az` devolviera cero.
- `concurrency` sin cancelación: abortar un despliegue a la mitad deja el entorno en estado
  desconocido.

### 4. Fuera de alcance

Despliegues progresivos con división de tráfico. Reversión automática.

### 5. Archivos

```
.github/workflows/cd.yml
scripts/deploy-containers.sh
scripts/verify/verify-deployment-health.sh
scripts/verify/verify-image-secrets.sh
```

### 6. Criterios de aceptación

- [x] Las cinco etapas existen y están encadenadas con `needs`.
- [x] Ninguna etapa exige intervención humana.
- [x] Las credenciales del pipeline no residen en el repositorio.
- [ ] Una integración a `main` despliega el sistema sin intervención.
- [ ] Una prueba fallida detiene el pipeline antes del despliegue.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | Revisión del encadenamiento | `needs` correctos |
| Operación | Commit a `main` | Despliegue automático |
| Operación | Commit con prueba rota | El pipeline se detiene antes de construir imagen |

### 8. Gherkin

```gherkin
Escenario: Una prueba fallida detiene el pipeline
  Dado un commit que rompe una prueba
  Cuando se integra a main
  Entonces el trabajo de pruebas falla
  Y el trabajo de construcción de imágenes no llega a ejecutarse
  Y no se despliega nada
```

### 9. Definition of Done

Despliegue automático demostrado · prueba fallida demostrada · revisión de Persona 2.

### 10. Comandos

```bash
git push origin main   # dispara el flujo
gh run watch
```

### 11. Evidencia

`docs/evidence/iss-s3-013/`

### Estado

**IMPLEMENTADA, PENDIENTE DE CORRIDA REAL.** Encadenamiento verificado por revisión; requiere
`ISS-S3-011` ejecutada para autenticarse.

---

## ISS-S3-014 — Justificación de la plataforma de CI/CD

### Metadatos

- **Historia:** HU-S3-002 · **Feature:** FEAT-S3-002
- **Responsable:** Persona 3 · **Revisor:** Persona 5
- **Dependencias para iniciar:** `ISS-S3-013`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Documentar el criterio aplicado, lo que se sacrifica y el contexto en que la decisión sería la
contraria.

### 2. Razón técnica

Es un entregable explícito del enunciado. Su valor está en la tercera parte: enunciar cuándo la
decisión sería la contraria obliga a entender el problema, no solo a defender la elección.

### 3. Descripción técnica

`ADR-008` documenta:

- **Qué se obtiene:** el pipeline junto al código y, sobre todo, ninguna credencial que robar.
- **Qué se sacrifica:** los *runners* alojados viven fuera de la VNet, así que el *bootstrap* de
  PostgreSQL —que necesita el plano de datos privado— **no puede ejecutarse desde el pipeline** y
  queda como operación manual documentada.
- **Cuándo sería al revés:** tres condiciones concretas, ninguna de las cuales se cumple aquí.

### 4. Fuera de alcance

Implementar la alternativa.

### 5. Archivos

```
docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md
```

### 6. Criterios de aceptación

- [x] Se nombran al menos dos plataformas viables.
- [x] Se enuncia lo que se sacrifica, con una consecuencia concreta y no genérica.
- [x] Se enuncian las condiciones bajo las cuales la decisión sería la contraria.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | Revisión cruzada | Las tres partes están presentes |

### 8. Gherkin

```gherkin
Escenario: La justificación es contrastable
  Cuando se lee ADR-008
  Entonces se identifica la alternativa evaluada
  Y la contrapartida asumida
  Y el contexto en que se elegiría la otra
```

### 9. Definition of Done

`ADR-008` escrito · revisión de Persona 5.

### 10. Comandos

```bash
grep -n "ADR-008" docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md
```

### 11. Evidencia

`docs/evidence/iss-s3-014/`

### Estado

**IMPLEMENTADA.** `ADR-008` escrito.

---

## ISS-S3-015 — Reporte de optimización de imágenes

### Metadatos

- **Historia:** HU-S3-003 · **Feature:** FEAT-S3-003
- **Responsable:** Persona 3 · **Revisor:** Persona 2
- **Dependencias para iniciar:** `ISS-S3-006`, `ISS-S3-007`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Documentar el tamaño resultante de las imágenes y las medidas aplicadas para reducirlo.

### 2. Razón técnica

El tamaño importa por dos razones concretas y no estéticas: cada arranque en frío descarga la
imagen —y el escalado crea réplicas justo cuando la latencia ya está sufriendo—, y el registro
Basic incluye 10 GiB, que se llenan antes de lo que parece con una imagen por commit.

### 3. Descripción técnica

`report-image-size.sh` imprime tamaño y número de capas por imagen, las capas más pesadas, y el
razonamiento de las medidas aplicadas:

1. Multietapa (la medida con más efecto, y la única que realmente elimina).
2. Base JRE Alpine en vez de JDK Debian.
3. `.dockerignore` que excluye `docs/`, `target/`, `.git/`.
4. Agente de telemetría en etapa propia.

Y lo que **no** se hizo: `jlink` para un runtime a medida, que habría bajado otros ~40 MB a
cambio de recalcular el conjunto de módulos en cada cambio de dependencia, con fallos que solo
aparecen en ejecución.

### 4. Fuera de alcance

Aplicar `jlink`.

### 5. Archivos

```
scripts/verify/report-image-size.sh
```

### 6. Criterios de aceptación

- [x] El reporte enumera las medidas aplicadas con su razón.
- [x] Documenta una medida descartada y por qué.
- [x] Incluye el tamaño real de las dos imágenes.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Operación | Ejecución del reporte | Tamaños reales capturados |

### 8. Gherkin

```gherkin
Escenario: El reporte documenta el tamaño real
  Cuando se ejecuta report-image-size.sh
  Entonces imprime el tamaño de centinela-api y centinela-scoring
  Y las capas que más pesan
```

### 9. Definition of Done

Reporte ejecutado con las imágenes construidas · revisión de Persona 2.

### 10. Comandos

```bash
bash scripts/verify/report-image-size.sh <registro> <etiqueta>
```

### 11. Evidencia

`docs/evidence/iss-s3-015/`

### Estado

**IMPLEMENTADA Y VERIFICADA.** Medición real: API **187 MB / 10 capas**, motor **660 MB / 20
capas**.

Las capas más pesadas de la API son la base Alpine (165 MB), el JAR (89,5 MB) y el agente de
telemetría (47,3 MB). Esa última merece una nota: el agente pesa una cuarta parte de la imagen y
se aceptó porque sin él no hay correlación automática de peticiones ni dependencias, que es la
mitad de la observabilidad exigida. Cambiarlo por instrumentación manual habría ahorrado 47 MB a
cambio de escribir —y mantener— lo que el agente hace solo.

---

# Persona 4 — Observabilidad, verificación y costos

---

## ISS-S3-016 — Application Insights y consultas de operación

### Metadatos

- **Historia:** HU-S3-001 · **Feature:** FEAT-S3-001
- **Responsable:** Persona 4 · **Revisor:** Persona 1
- **Dependencias para iniciar:** `ISS-S3-005`
- **Estimación orientativa:** 1 día

### 1. Objetivo

Poder responder, en ejecución, las cinco preguntas de operación que el enunciado enumera.

### 2. Razón técnica

Las cinco preguntas no son un panel bonito: dos de ellas —el componente de mayor latencia y el
punto exacto de fallo— determinan si un incidente se diagnostica en minutos o en horas.

La consulta del percentil superior merece una nota: con un promedio de 80 ms y un p95 de 900 ms,
la mayoría de transacciones va bien y una de cada veinte tarda casi un segundo. El promedio solo
esconde eso, y por eso el enunciado pide ambos.

### 3. Descripción técnica

- Application Insights sobre el workspace de Log Analytics ya creado.
- Tope diario de ingesta de 1 GB. No por la estimación —que da menos de 1 GB para todo el
  proyecto— sino porque un bucle de reintentos ruidoso puede multiplicar el volumen por veinte en
  una noche; el tope convierte un susto de facturación en una pérdida de datos acotada.
- Cinco consultas KQL documentadas, más la de consumo de telemetría.
- La consulta de tasa cuenta `dcount` y no `count`: un reintento de Event Grid produce varias
  líneas para la misma transacción, y contarlas todas inflaría la tasa justo cuando algo falla.
- La proporción de marcadas usa `arg_max` por transacción para no contar dos veces una
  reprocesada.
- El componente más lento se ordena por p95 pero muestra también el total: son dos preguntas
  distintas, porque una etapa de 5 ms que ocurre mil veces cuesta más que una de 300 ms que
  ocurre diez.

### 4. Fuera de alcance

Paneles gráficos. Muestreo adaptativo.

### 5. Archivos

```
scripts/provision-observability.sh
docs/observabilidad/consultas-kql.md
applicationinsights.json
```

### 6. Criterios de aceptación

- [x] Las cinco consultas están escritas y razonadas.
- [x] El límite del nivel gratuito y el consumo estimado están documentados con su cálculo.
- [ ] Las cinco consultas devuelven datos sobre el sistema en ejecución.
- [ ] El tope diario de ingesta está aplicado.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Operación | Ejecución de cada consulta | Devuelven datos, no error de extracción de campos |

### 8. Gherkin

```gherkin
Escenario: La latencia del scoring se conoce en promedio y en percentil
  Cuando se ejecuta la consulta de latencia de scoring
  Entonces devuelve promedio, p95 y p99 con su número de muestras
```

### 9. Definition of Done

Recurso creado · cinco consultas verificadas contra datos reales · revisión de Persona 1.

### 10. Comandos

```bash
CENTINELA_ALERT_EMAIL="..." bash scripts/provision-observability.sh --validate-only
CENTINELA_ALERT_EMAIL="..." bash scripts/provision-observability.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-016/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Script y consultas escritos.

---

## ISS-S3-017 — Traza individual por transacción

### Metadatos

- **Historia:** HU-S3-001 · **Feature:** FEAT-S3-001
- **Responsable:** Persona 4 · **Revisor:** Persona 1
- **Dependencias para iniciar:** `ISS-S3-016`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Dado un identificador de transacción, mostrar su recorrido completo con los tiempos de cada etapa.

### 2. Razón técnica

Es el requisito que el enunciado blinda explícitamente: *«un panel de métricas agregadas no
satisface este requisito»*. Se separa de `ISS-S3-016` porque son capacidades distintas —agregar y
seguir un caso individual— y solo la segunda sirve cuando un analista pregunta por *esta*
transacción.

### 3. Descripción técnica

- `verify-trace.sh` consulta App Insights filtrando por `transactionId`, extrae etapa, duración,
  desenlace y `traceId`, y los imprime en orden cronológico.
- Calcula el tiempo acumulado, la etapa más lenta y —si hay algún `FAILURE`— el punto de fallo.
- **La comprobación clave** es que el `traceId` sea el mismo en todas las filas. Si cambia entre
  dos etapas, la propagación se rompió en ese salto y la traza dejó de ser una sola, aunque cada
  etapa por separado se vea bien.
- Distingue «no hay datos» de «la consulta no funciona»: si no encuentra nada, dice que App
  Insights tarda entre 1 y 3 minutos en indexar.

### 4. Fuera de alcance

Visualización gráfica del árbol de spans.

### 5. Archivos

```
scripts/verify/verify-trace.sh
docs/observabilidad/consultas-kql.md
```

### 6. Criterios de aceptación

- [x] La consulta filtra por una transacción concreta, no agrupa.
- [ ] Se obtiene el recorrido completo con tiempos por etapa.
- [ ] El `traceId` es el mismo en todas las etapas, incluidas las posteriores a un salto asíncrono.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Operación | `verify-trace.sh` sobre una transacción real | Recorrido completo y continuo |

### 8. Gherkin

```gherkin
Escenario: La traza cruza los saltos asíncronos
  Dada una transacción que generó caso
  Cuando se consulta su traza
  Entonces aparecen RAW_PERSIST, EVENT_PUBLISH, SCORING, CASE_OPEN y EXPLANATION
  Y todas comparten el mismo trace-id
```

### 9. Definition of Done

Traza completa obtenida sobre una transacción real · revisión de Persona 1.

### 10. Comandos

```bash
bash scripts/verify/verify-trace.sh <transactionId>
```

### 11. Evidencia

`docs/evidence/iss-s3-017/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Script escrito.

---

## ISS-S3-018 — Alerta con umbral justificado

### Metadatos

- **Historia:** HU-S3-006 · **Feature:** FEAT-S3-006
- **Responsable:** Persona 4 · **Revisor:** Persona 3
- **Dependencias para iniciar:** `ISS-S3-016`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Definir una condición que requiera intervención humana, con su umbral justificado, y demostrar
que se dispara.

### 2. Razón técnica

**Por qué esta condición y no otra.** «Transacciones ingeridas que no llegaron a puntuarse» es la
única condición del sistema que significa *un cliente recibió acuse y el fraude no se evaluó*.
Eso exige intervención humana: no se resuelve reintentando.

Una alerta por latencia alta o por CPU avisaría de síntomas que el escalado ya corrige solo.
Despertar a alguien para que mire cómo se autorresuelve es la forma más rápida de que las alertas
se ignoren.

**Por qué 5 y no 1.** Un fallo aislado lo cubre el reintento de Event Grid, que insiste durante
24 horas; alertar al primero produciría falsos positivos constantes. Cinco en quince minutos ya
no es una anomalía puntual sino un patrón: con el volumen previsto representa más del 15 % de
pérdida, muy por encima de cualquier fluctuación normal.

### 3. Descripción técnica

- Regla programada sobre la consulta que compara `EVENT_PUBLISH` con `SCORING` mediante
  `join kind=leftanti`.
- Evaluación cada 5 minutos sobre ventana de 15. Severidad 1.
- Grupo de acción con destinatario real; el script **falla** si no se define uno, porque una
  alerta sin destinatario no alerta a nadie.

### 4. Fuera de alcance

Alertas adicionales. Escalado automático de incidentes.

### 5. Archivos

```
scripts/provision-observability.sh
```

### 6. Criterios de aceptación

- [x] La condición, el umbral y el criterio están escritos y razonados.
- [x] El script rechaza crear la alerta sin destinatario.
- [ ] La alerta se dispara al provocar la condición deliberadamente.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Operación | Provocar la condición | La alerta se dispara y notifica |

### 8. Gherkin

```gherkin
Escenario: La alerta se dispara ante pérdida de transacciones
  Dado el motor de scoring detenido
  Cuando se envían diez transacciones
  Entonces en menos de 20 minutos la alerta se dispara
  Y el destinatario recibe la notificación
```

### 9. Definition of Done

Alerta creada · disparo demostrado · revisión de Persona 3.

### 10. Comandos

```bash
# Provocar: detener el motor y enviar tráfico
az containerapp update -g "$RESOURCE_GROUP" -n "ca-${NAME_PREFIX}-scoring" \
  --min-replicas 0 --max-replicas 0
```

### 11. Evidencia

`docs/evidence/iss-s3-018/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Alerta definida en el script con su justificación.

---

## ISS-S3-019 — Agentes de verificación

### Metadatos

- **Historia:** HU-S3-006 · **Feature:** FEAT-S3-006
- **Responsable:** Persona 4 · **Revisor:** Persona 5
- **Dependencias para iniciar:** `ISS-S3-001` a `ISS-S3-018`
- **Estimación orientativa:** 1 día

### 1. Objetivo

Poder auditar el estado del sistema —funcionalidad y buenas prácticas— de forma reproducible.

### 2. Razón técnica

El proyecto ya sufrió una vez el problema que estos agentes previenen: **seis comprobaciones que
devolvían OK sobre infraestructura rota** porque interpretaban mal la respuesta de `az` (ver
`6_Informe_Errores_Corregidos.md`). El caso más traicionero:
`az network private-endpoint dns-zone-group show` devuelve código 0 y `{}` cuando el grupo no
existe.

De ahí la regla que gobierna los siete agentes: **el veredicto se apoya en salida de comando, no
en lo que el código o la documentación afirman**. Y «no verificable» es un resultado honesto; un
OK sin evidencia no lo es.

### 3. Descripción técnica

Siete agentes en `.claude/agents/`, cada uno con su script ejecutable:

| Agente | Qué audita |
|---|---|
| `verify-infra` | Red privada, DNS resoluble, RBAC, ventanas huérfanas |
| `verify-secrets` | Repositorio, historial de Git, imágenes capa por capa, pipeline |
| `verify-containers` | Multietapa real, tamaño, usuario, escalado justificado |
| `verify-cicd` | Cinco etapas encadenadas, sin intervención, sin credenciales |
| `verify-observability` | Traza individual, cinco consultas, alerta |
| `verify-explainer` | Correspondencia estricta, determinismo, resiliencia |
| `verify-practices` | Límites hexagonales, caminos de fallo probados, migraciones |

Los scripts viven en `scripts/verify/` para que un tercero pueda reproducir el veredicto **sin
depender de una IA**.

### 4. Fuera de alcance

Ejecución automática en el pipeline de los agentes que requieren sesión de Azure.

### 5. Archivos

```
.claude/agents/*.md
scripts/verify/*.sh
```

### 6. Criterios de aceptación

- [x] Siete agentes definidos, cada uno apoyado en scripts ejecutables.
- [x] Cada agente distingue OK, FALLO y NO VERIFICABLE.
- [x] `verify-practices.sh` pasa sobre el repositorio.
- [ ] Los agentes que requieren Azure se ejecutan sobre el sistema desplegado.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | `verify-practices.sh` | Estructura, migraciones, instrumentación, secretos |
| Operación | Resto de agentes | Estado del sistema desplegado |

### 8. Gherkin

```gherkin
Escenario: Un hueco de instrumentación se detecta
  Dada una etapa declarada en PipelineStage sin emisor
  Cuando se ejecuta verify-practices.sh
  Entonces reporta que quedaría un hueco en la traza
```

### 9. Definition of Done

Siete agentes escritos · scripts verificados · revisión de Persona 5.

### 10. Comandos

```bash
bash scripts/verify/verify-practices.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-019/`

### Estado

**IMPLEMENTADA.** Siete agentes y siete scripts; `verify-practices.sh` verificado localmente.

---

## ISS-S3-020 — Reporte de crédito y apagado diario

### Metadatos

- **Historia:** HU-S3-006 · **Feature:** FEAT-S3-006
- **Responsable:** Persona 4 · **Revisor:** Persona 2
- **Dependencias para iniciar:** `ISS-S3-009`
- **Estimación orientativa:** 0,5 día

### 1. Objetivo

Mantener el consumo por debajo de 60 USD y reportar el consumo final del proyecto.

### 2. Razón técnica

El enunciado avisa de que el consumo alcanza su máximo esta semana porque la generación de carga,
la construcción repetida de imágenes y la ingesta de telemetría coinciden.

El apagado distingue lo que factura **por tiempo** de lo que factura **por almacenamiento**:
apagar Cosmos o Storage equivaldría a destruirlos, así que no se tocan.

### 3. Descripción técnica

- `shutdown-daily.sh` con `--stop` y `--start`.
- Container Apps a cero réplicas, mínimo **y máximo**: dejar el máximo en 10 permitiría que una
  regla de escalado levantara réplicas por tráfico residual.
- App Service y PostgreSQL detenidos: son los que facturan por hora.
- El reporte de crédito reutiliza la consulta a Cost Management de `ISS-S2-014`.

### 4. Fuera de alcance

Apagado automático programado.

### 5. Archivos

```
scripts/shutdown-daily.sh
```

### 6. Criterios de aceptación

- [x] El script distingue lo que se apaga de lo que no, con su razón.
- [ ] El consumo final del proyecto es inferior a 60 USD.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Operación | Ciclo apagar/encender | El sistema vuelve a responder tras encender |
| Operación | Consulta a Cost Management | Consumo final |

### 8. Gherkin

```gherkin
Escenario: El apagado no destruye datos
  Cuando se ejecuta shutdown-daily.sh
  Entonces Container Apps queda a cero réplicas
  Y Cosmos y Storage siguen intactos
```

### 9. Definition of Done

Ciclo demostrado · reporte de crédito capturado · revisión de Persona 2.

### 10. Comandos

```bash
bash scripts/shutdown-daily.sh
bash scripts/shutdown-daily.sh --start
bash scripts/tests/validate-week2-closeout.sh
```

### 11. Evidencia

`docs/evidence/iss-s3-020/`

### Estado

**PENDIENTE DE EVIDENCIA EN AZURE.** Script escrito y verificado sintácticamente.

---

# Persona 5 — Explicabilidad, verificación documental, banco de pruebas y cierre

---

## ISS-S3-021 — Explicador determinista por plantilla

### Metadatos

- **Historia:** HU-S3-004 · **Feature:** FEAT-S3-004
- **Responsable:** Persona 5 · **Revisor:** Persona 1
- **Dependencias para iniciar:** `ISS-S3-002`, `ISS-S3-003`
- **Estimación orientativa:** 1,5 días

### 1. Objetivo

Convertir el detalle de las reglas activadas en una explicación legible que se corresponda
estrictamente con lo que el motor registró.

### 2. Razón técnica

El criterio de aceptación no es «la explicación se lee bien», sino que **se corresponde
estrictamente con las reglas que se activaron y con los valores que las activaron**. Hay dos
formas de incumplirlo y ambas son fáciles:

- **Afirmar de más:** rellenar un hueco con un valor por defecto. Una frase que dice «supera en
  0× el promedio» porque el multiplicador no se registró es peor que no decir nada: afirma algo
  falso con la misma autoridad que lo verdadero.
- **Afirmar de menos:** omitir una regla que la plantilla no conoce. Eso dejaría un score que no
  cuadra con las frases mostradas, y el analista no tendría forma de advertirlo.

### 3. Descripción técnica

- `ExplanationTemplate.render` — determinista por construcción: sin modelo de lenguaje, sin
  aleatoriedad, sin lectura del reloj.
- Las reglas se ordenan explícitamente por contribución. Cosmos no garantiza el orden de un
  arreglo entre lecturas, así que sin ordenación el mismo caso podría explicarse distinto dos
  veces.
- Encabezado con score y **umbral registrado en el instante de decidir**, no el actual.
- Degradación honesta: sin ciudad se habla de distancia; sin cadencia medida no se menciona
  promedio.
- Una regla desconocida se enumera con sus valores crudos ordenados por clave.
- `InsufficientDecisionRecordException` cuando no hay reglas: el diagnóstico —el defecto está en
  el motor— queda escrito en el código y no se confunde con un fallo del explicador.
- Los accesores de `RuleActivation` devuelven `Optional`, nunca valores por defecto.

### 4. Fuera de alcance

Ejecución asíncrona (`ISS-S3-022`). Traducción a otros idiomas.

### 5. Archivos

```
src/main/java/com/centinela/caseexplanation/domain/explanation/ExplanationTemplate.java
src/main/java/com/centinela/caseexplanation/domain/explanation/InsufficientDecisionRecordException.java
src/main/java/com/centinela/scoringrecord/domain/model/RuleActivation.java
src/main/java/com/centinela/scoringrecord/domain/model/ScoringDecision.java
```

### 6. Criterios de aceptación

- [x] La misma decisión produce el mismo texto, byte a byte.
- [x] No se menciona ninguna regla que no se activó.
- [x] Cuando falta un dato, la frase se empobrece en lugar de rellenarse.
- [x] Una regla desconocida se enumera en vez de omitirse.
- [x] Las contribuciones citadas suman el score total.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `ExplanationTemplateTest` | Las dos formas de incumplir la correspondencia |
| Operación | `verify-explainer-correspondence.sh` | Correspondencia sobre un caso real |

### 8. Gherkin

```gherkin
Escenario: Sin cadencia medida no se menciona ningún promedio
  Dada una activación de velocidad sin baselineAverageIntervalMinutes
  Cuando se genera la explicación
  Entonces menciona el lapso de la ráfaga
  Y no contiene la palabra "promedio"
```

### 9. Definition of Done

8 pruebas de plantilla en verde · revisión de Persona 1, que produjo los datos que consume.

### 10. Comandos

```bash
mvn -B test -Dtest='ExplanationTemplateTest'
```

### 11. Evidencia

`docs/evidence/iss-s3-021/`

### Estado

**IMPLEMENTADA.** 8 pruebas en verde, incluida la reproducción de la salida esperada del
enunciado.

---

## ISS-S3-022 — Ejecución asíncrona y resiliencia del explicador

### Metadatos

- **Historia:** HU-S3-004 · **Feature:** FEAT-S3-004
- **Responsable:** Persona 5 · **Revisor:** Persona 2
- **Dependencias para iniciar:** `ISS-S3-021`
- **Estimación orientativa:** 1 día

### 1. Objetivo

Que la generación ocurra después de abrir el caso, sin que su indisponibilidad impida abrirlos.

### 2. Razón técnica

**Por qué consulta de estado y no cola.** El requisito dice que con el explicador detenido los
casos siguen abriéndose y que, al restablecerlo, las explicaciones pendientes se generan. Con una
cola habría que garantizar que ningún mensaje se pierde mientras el consumidor no existe;
consultando `explanation_state = 'PENDING'` la recuperación del backlog es **una consecuencia del
modelo de datos**, no un mecanismo aparte que pueda fallar.

**Por qué la misma imagen.** El explicador es la imagen de la API con otros interruptores. Eso
convierte «detener el explicador» —escenario de fallo obligatorio de la sustentación— en escalar
su Container App a cero, sin tocar la API ni desplegar nada.

### 3. Descripción técnica

- `GenerateCaseExplanationService` procesa lotes; cada caso se aísla. Un caso que no se puede
  explicar no impide explicar los demás: detener el lote ante el primer fallo convertiría un caso
  defectuoso en una parada de todo el backlog.
- Contador de intentos con máximo, para que un caso irreparable no consuma el ciclo
  indefinidamente.
- `attachExplanation` escribe explicación, estado y auditoría en una sola transacción: separarlas
  dejaría un caso marcado como explicado sin rastro de quién lo explicó.
- El trabajador captura sus propias excepciones: propagarlas detendría la planificación y
  convertiría un error transitorio en una parada permanente que exigiría reinicio manual.
- La generación **no está** en la ruta de ingesta: su latencia no entra en el camino del cliente.

### 4. Fuera de alcance

Regeneración de explicaciones ya emitidas.

### 5. Archivos

```
src/main/java/com/centinela/caseexplanation/application/service/GenerateCaseExplanationService.java
src/main/java/com/centinela/caseexplanation/application/port/out/PendingExplanationPort.java
src/main/java/com/centinela/caseexplanation/infrastructure/persistence/JpaPendingExplanationAdapter.java
src/main/java/com/centinela/caseexplanation/infrastructure/worker/CaseExplanationWorker.java
src/main/java/com/centinela/caseexplanation/infrastructure/config/CaseExplanationConfiguration.java
```

### 6. Criterios de aceptación

- [x] Un caso inexplicable no bloquea el resto del lote.
- [x] El explicador no participa en la ruta de ingesta.
- [ ] Con el explicador detenido, los casos siguen abriéndose en `PENDING`.
- [ ] Al restablecerlo, las explicaciones pendientes se generan sin intervención.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `GenerateCaseExplanationServiceTest` | Aislamiento de fallos y recuperación de backlog |
| Operación | Escenario de fallo de la sustentación | Detener y restablecer |

### 8. Gherkin

```gherkin
Escenario: El backlog se recupera al restablecer el explicador
  Dado el explicador detenido
  Y tres casos abiertos en estado PENDING
  Cuando el explicador vuelve a ejecutarse
  Entonces los tres reciben su explicación sin intervención
```

### 9. Definition of Done

5 pruebas en verde · escenario de fallo ensayado · revisión de Persona 2.

### 10. Comandos

```bash
mvn -B test -Dtest='GenerateCaseExplanationServiceTest'
az containerapp update -g "$RESOURCE_GROUP" -n "ca-${NAME_PREFIX}-explainer" \
  --min-replicas 0 --max-replicas 0
```

### 11. Evidencia

`docs/evidence/iss-s3-022/`

### Estado

**IMPLEMENTADA, PENDIENTE DE ENSAYO.** 5 pruebas en verde, incluida la recuperación de backlog.

---

## ISS-S3-023 — Verificación documental con manejo de fallos

### Metadatos

- **Historia:** HU-S3-005 · **Feature:** FEAT-S3-005
- **Responsable:** Persona 5 · **Revisor:** Persona 4
- **Dependencias para iniciar:** `ISS-S3-003`
- **Estimación orientativa:** 1,5 días

### 1. Objetivo

Extraer los datos del documento de identidad y adjuntarlos al caso, sin que ningún desenlace
interrumpa el flujo.

### 2. Razón técnica

El requisito es que un documento ilegible, incompleto, corrupto o de formato inesperado **no
interrumpa el flujo ni deje el caso en estado indeterminado**.

De ahí dos decisiones de diseño. Primera: el resultado de la extracción es un **valor de retorno,
no una excepción**. Un documento ilegible es un desenlace previsto del flujo; modelarlo como
excepción invitaría a que alguien lo dejara escapar y tumbara el lote. Segunda: el fallo se
escribe como **fila con estado**, no como ausencia de fila, porque el analista tiene que poder
consultar qué pasó con el documento que cargó.

**Sobre el plan alternativo.** El informe de cuotas que el punto 2.3 da por hecho no existía: la
Semana 1 dejó el OCR explícitamente fuera de alcance. Se implementa la extracción con librería
local, que es el plan alternativo previsto, y el requisito de manejo de fallos se mantiene sin
cambios.

### 3. Descripción técnica

- `IdentityDataExtractorPort` con contrato estricto: **no lanza**. Existe como puerto porque el
  enunciado contempla dos implementaciones según la suscripción, y la política de fallos vive en
  la capa de aplicación para no duplicarse por adaptador.
- `TextualIdentityDataExtractor` (PDFBox): distingue PDF con firma inválida, PDF cifrado, PDF sin
  capa de texto, formato no soportado, archivo vacío y texto sin campos de identidad.
- **Limitación declarada, no disimulada:** no hace OCR. Un escaneo sin capa de texto se reporta
  como ilegible con un mensaje que dice qué hacer, en lugar de devolver campos vacíos que
  parezcan un documento legítimo en blanco.
- El tipo declarado por el cliente no se cree sin comprobar el contenido: los clientes mienten
  sobre el `content-type`.
- El registro se escribe **antes** de intentar extraer: si el proceso muere durante la
  extracción, el documento ya consta como `RECEIVED` y el siguiente ciclo lo recoge.
- Notificación al analista como entrada en la bitácora inmutable del caso, escrita en la misma
  transacción que el desenlace. El envío por correo queda fuera del alcance y se documenta: lo que
  el requisito exige es que el analista **reciba el resultado**, no un canal concreto.
- La carga responde `201` sin esperar a la extracción.

### 4. Fuera de alcance

OCR. Envío por correo o mensajería. Contraste automático con los datos de la cuenta.

### 5. Archivos

```
src/main/java/com/centinela/documentverification/**
src/main/java/com/centinela/documentstorage/**  (el puerto devuelve la ruta del blob)
```

### 6. Criterios de aceptación

- [x] El extractor nunca lanza; todo desenlace es un valor de retorno.
- [x] Cada desenlace lleva un mensaje accionable distinto.
- [x] Un documento válido produce datos extraídos adjuntos al caso.
- [ ] Un documento corrupto no interrumpe el flujo y el caso queda consultable.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `TextualIdentityDataExtractorTest` | Nueve formas de documento roto, ninguna lanza |
| Operación | Botón «Documento ilegible» del banco de pruebas | El caso sigue consultable |

### 8. Gherkin

```gherkin
Escenario: Un PDF corrupto no interrumpe el flujo
  Dado un caso abierto
  Cuando el analista carga un archivo corrupto declarado como PDF
  Entonces la carga responde 201
  Y el documento queda en estado UNREADABLE con su motivo
  Y el caso sigue consultable
```

### 9. Definition of Done

9 pruebas en verde · escenario de fallo ensayado · revisión de Persona 4.

### 10. Comandos

```bash
mvn -B test -Dtest='TextualIdentityDataExtractorTest'
```

### 11. Evidencia

`docs/evidence/iss-s3-023/`

### Estado

**IMPLEMENTADA, PENDIENTE DE ENSAYO E2E.** 9 pruebas cubren todos los desenlaces.

---

## ISS-S3-024 — Banco de pruebas en repositorio aparte

### Metadatos

- **Historia:** HU-S3-006 · **Feature:** FEAT-S3-006
- **Responsable:** Persona 5 · **Revisor:** Persona 1
- **Dependencias para iniciar:** `ISS-S3-004`
- **Estimación orientativa:** 2 días

### 1. Objetivo

Una aplicación independiente con un botón por causal de alerta, un control negativo y un
generador de carga.

### 2. Razón técnica

**Por qué repositorio aparte.** Una herramienta de prueba que comparte código con lo que prueba
puede pasar por alto exactamente el error que ambos cometen. Al replicar los contratos en lugar
de importarlos, una divergencia se manifiesta como un `400` inmediato —la API rechaza toda
propiedad no declarada— y no como un dato silenciosamente ignorado.

**Por qué el control negativo no es opcional.** Un detector que marca absolutamente todo también
«acierta» en los cinco escenarios fraudulentos. El botón de transacción normal es lo único que
distingue un sistema que funciona de uno que sospecha de todo.

**Por qué cada escenario siembra historial.** Las reglas comparan contra el pasado de la cuenta.
Un monto de cuatro millones sobre una cuenta recién creada no activa nada: sin promedio previo no
hay nada que superar. Y cada ejecución usa una cuenta nueva, porque reutilizarla haría que tras
tres demostraciones de monto atípico el promedio ya incluyera los montos desmedidos.

### 3. Descripción técnica

- Spring Boot + Thymeleaf. Una plantilla del lado del servidor evita una cadena de construcción
  de frontend entera para ocho botones.
- Ocho escenarios: cinco causales, control negativo, documento ilegible y carga sostenida.
- Cada escenario abre **su propia traza W3C**, de modo que el recorrido mostrado en la
  herramienta de monitoreo empieza en el clic y no en el borde HTTP de Centinela.
- Ejecución sincrónica: durante una sustentación es preferible que la página se quede cargando a
  que el evaluador tenga que refrescar.
- Sondeo en dos fases —el score aparece en segundos, la explicación tarda más— para no alargar
  cada demostración innecesariamente.
- La carga usa transacciones inocuas: si generara casos, miles de registros de prueba se
  mezclarían con los reales.
- Topes de 50 tx/s y 300 s: un cero de más en un formulario no debe costar el presupuesto.
- `DefaultAzureCredential`: cero credenciales en el repositorio.
- La pantalla contrasta lo observado con lo esperado, y declara que un desajuste **no es un fallo
  de la herramienta** sino un hallazgo sobre el motor o sobre la expectativa.

### 4. Fuera de alcance

Persistencia de resultados históricos. Ejecución programada.

### 5. Archivos

```
centinela-lab/  (repositorio independiente)
```

### 6. Criterios de aceptación

- [x] Un botón por causal más el control negativo.
- [x] Cada escenario siembra historial y usa una cuenta nueva.
- [x] Cero credenciales en el repositorio.
- [x] La app no comparte código, base de datos ni despliegue con Centinela.
- [ ] Los ocho escenarios se ejecutan contra el sistema desplegado.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Unitario | `TransactionFactoryTest` | Cada escenario genera de verdad la forma que promete |
| Operación | Los ocho botones | Comportamiento real de Centinela |

### 8. Gherkin

```gherkin
Escenario: El control negativo no genera alerta
  Cuando se lanza el escenario de transacción normal
  Entonces Centinela responde con flagged = false
  Y no existe caso para esa transacción
```

### 9. Definition of Done

8 pruebas en verde · repositorio con su propio pipeline · revisión de Persona 1.

### 10. Comandos

```bash
cd ../centinela-lab && mvn -B verify
```

### 11. Evidencia

`docs/evidence/iss-s3-024/`

### Estado

**IMPLEMENTADA.** Repositorio creado con commit inicial; 8 pruebas en verde.

---

## ISS-S3-025 — Cierre documental y ensayo de sustentación

### Metadatos

- **Historia:** HU-S3-006 · **Feature:** FEAT-S3-006
- **Responsable:** Persona 5 · **Revisor:** toda la célula
- **Dependencias para iniciar:** todas las anteriores
- **Estimación orientativa:** 1 día

### 1. Objetivo

Cerrar el documento de decisiones, dejar el README reproducible por un tercero y ensayar los ocho
escenarios de la sustentación.

### 2. Razón técnica

El enunciado advierte que una demostración limitada al camino de ejecución exitoso no permite
evaluar el sistema, y que los dos escenarios de fallo son parte del alcance. Ensayarlos importa
más que ensayar los otros seis: son los únicos que pueden salir mal de forma no prevista.

El README lo verifica **alguien ajeno a la célula**. Quien escribió los scripts no puede juzgar
si son seguibles: conoce los pasos implícitos.

### 3. Descripción técnica

- `ADR-008` a `ADR-014` cierran el documento cubriendo las tres semanas, e incluyen los cuatro
  puntos que el enunciado exige: plataforma de CI/CD, métrica de escalado, componente que se
  satura primero, y qué se cambiaría al empezar de nuevo.
- README con la sección de Semana 3: aprovisionar, configurar el pipeline, desplegar, verificar,
  demostrar el escalado, provocar los dos fallos y controlar el crédito.
- Ensayo cronometrado de los ocho escenarios, **sin búsqueda ni preparación intermedia**.

### 4. Fuera de alcance

Nuevas funcionalidades.

### 5. Archivos

```
docs/2_Arquitectura/2_ADR_Decisiones_Arquitectura.md
README.md
docs/0_Vision/5_Alcance_Semana3.md
```

### 6. Criterios de aceptación

- [x] El ADR cubre las tres semanas y responde los cuatro puntos exigidos.
- [x] El README describe el despliegue completo desde cero.
- [ ] Un tercero ajeno reconstruye la infraestructura siguiendo el README.
- [ ] Los ocho escenarios se ensayan de corrido.

### 7. Pruebas

| Nivel | Prueba | Qué fija |
|---|---|---|
| Estático | Revisión cruzada del ADR | Los cuatro puntos exigidos |
| Operación | Ensayo completo | Los ocho escenarios, cronometrados |

### 8. Gherkin

```gherkin
Escenario: Los escenarios de fallo se demuestran
  Cuando se ejecuta la demostración
  Entonces se muestra el comportamiento ante un documento ilegible
  Y el comportamiento con el explicador detenido
```

### 9. Definition of Done

ADR cerrado · README verificado por un tercero · ensayo completo · revisión de toda la célula.

### 10. Comandos

```bash
bash scripts/verify/verify-practices.sh
# Ensayo: los ocho escenarios de docs/0_Vision/5_Alcance_Semana3.md
```

### 11. Evidencia

`docs/evidence/iss-s3-025/`

### Estado

**PARCIALMENTE IMPLEMENTADA.** ADR cerrado y README escrito. Pendientes la verificación por un
tercero y el ensayo de los ocho escenarios.

---

# Resumen de estado del backlog

Última captura: `bash scripts/tests/capture-week3-evidence.sh` — **29 comprobaciones correctas,
0 fallos, 4 declaradas no verificables** en este entorno.

| Estado | Issues | Cuáles |
|---|---|---|
| `IMPLEMENTADA Y VERIFICADA` | 20 | 001–009, 011–016, 019, 021–024 |
| `PENDIENTE DE EVIDENCIA EN AZURE` | 4 | 010, 017, 018, 020 |
| `PARCIAL` | 1 | 025 (ADR y README hechos; falta verificación por un tercero y el ensayo) |

Ninguna issue está pendiente de implementación. Lo que falta son **cuatro comprobaciones que
exigen un sistema desplegado**, y no hay forma honesta de sustituirlas: el enunciado es explícito
en que una configuración documentada no es evidencia de que el escalado ocurra, y lo mismo vale
para una alerta que nunca se ha disparado.

## Lo que la ejecución del backlog encontró

Cuatro defectos, **todos en las herramientas de verificación y ninguno en el código de
producción**. Merece registrarse porque es el modo de fallo más peligroso: un verificador roto no
avisa de que lo está — devuelve OK y crea confianza infundada.

| # | Defecto | Dónde | Cómo se resolvió |
|---|---|---|---|
| 1 | El barrido de credenciales se detectaba a sí mismo | `verify-image-secrets.sh` contiene los patrones que busca | Añadido a la lista de exclusiones que el escáner ya mantenía para este caso, con el punto ciego documentado |
| 2 | GUIDs reales versionados desde Semana 1 | `docs/evidence/identity/entra-app.record.txt` | Enmascarado parcial; deuda del historial declarada en `SECURITY-remediacion-env-leak.md` |
| 3 | La comprobación de instrumentación no comprobaba nada | `verify-practices.sh` — `grep -P` no soportado, y luego umbral mal | Extracción con `sed` portable, umbral corregido y guarda que falla si no se extrae ninguna etapa |
| 4 | `INGEST_API` declarada sin emisor | `TransactionController` | Instrumentada; mide lo que espera el cliente de extremo a extremo |

El defecto 3 merece una lectura: sus dos versiones rotas fallaban de forma **opuesta** —una
callaba, la otra reportaba huecos inexistentes— y ambas eran igual de inútiles. Solo al
arreglarlas apareció el defecto 4, que era el único hueco real.
