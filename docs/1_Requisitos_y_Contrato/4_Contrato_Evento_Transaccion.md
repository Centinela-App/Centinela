# 08 — Contratos de mensaje de Semana 2 (evento y caso)

## Propósito

Este documento fija los **dos contratos de mensaje** que cruzan el pipeline orientado a eventos
de Semana 2 y que deben ser estables antes de que las piezas se implementen:

1. **`transaction-event-v1`** — evento de transacción: **API → Event Grid → Function**.
2. **`flagged-case-v1`** — mensaje de caso marcado: **Function → Storage Queue → consumidor**.

Ambos existen en dos representaciones que **deben coincidir**:

- **JSON Schema versionado** (autoritativo): `schemas/transaction-event-v1.json` y
  `schemas/flagged-case-v1.json` (Draft 2020-12).
- **Records Java compartidos**: `com.centinela.shared.event.TransactionEvent` y
  `com.centinela.shared.event.FlaggedCaseMessage`, que tanto la app como la Function consumen.

La coherencia esquema ↔ record se verifica de forma automática en
`EventContractTest` (TEST-S2-005). Cualquier divergencia de campos rompe la compilación de la
prueba de contrato.

> **Fuera de alcance (Semana 3).** Ninguno de los dos contratos incluye explicación en lenguaje
> natural ni campos de verificación de identidad. `transaction-event-v1` **no** incluye `score`
> ni `decision`: el motor de scoring los calcula más tarde a partir del historial.

---

## 1. `transaction-event-v1` — evento de transacción

**Rol.** *Notifica la ocurrencia* de una transacción ya persistida para que el motor de scoring
reaccione de forma desacoplada. La API publica este evento tras persistir y **no** espera al
scoring (ver ISS-S2-006).

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---:|---|
| `eventId` | string (uuid) | Sí | Identificador único del evento. Metadato mínimo para trazabilidad/correlación. |
| `transactionId` | string | Sí | Transacción que originó el evento. |
| `accountId` | string | Sí | Cuenta dueña de la transacción. Es la **clave de partición** que la Function usa para leer el historial de una sola partición. |
| `occurredAt` | string (date-time RFC 3339) | Sí | Momento en que ocurrió la transacción. |
| `blobPath` | string | Sí | Ubicación del **JSON crudo** en Blob Storage (`{contenedor}/yyyy/MM/dd/{transactionId}.json`). |
| `schemaVersion` | string const `transaction-event-v1` | Sí | Discriminador de versión del contrato. |

**No contiene** `score`, `decision`, `triggeredRules` ni `caseId`. Esos datos aún no existen en
el momento de publicar el evento.

---

## 2. `flagged-case-v1` — mensaje de caso marcado

**Rol.** *Garantiza el procesamiento* de un caso: es el disparador de apertura que la Function
encola **solo si `score >= umbral`**. Viaja por una **cola** (no por una llamada directa) para
que ningún caso se pierda si el consumidor está caído (ver ISS-S2-005, ISS-S2-011).

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---:|---|
| `transactionId` | string | Sí | Transacción que disparó el caso. **Clave de idempotencia**: reprocesar el mismo mensaje no abre un caso duplicado. |
| `accountId` | string | Sí | Cuenta asociada al caso. |
| `score` | integer (≥ 0) | Sí | Puntaje total (suma de puntos de las reglas activadas) que superó el umbral. |
| `triggeredRules` | array de objetos | Sí | **Resumen** de las reglas activadas: `[{ ruleId, points }]`. |
| `occurredAt` | string (date-time RFC 3339) | Sí | Momento en que ocurrió la transacción. |
| `scoredAt` | string (date-time RFC 3339) | Sí | Momento en que la Function calculó el score. |

Cada elemento de `triggeredRules`:

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---:|---|
| `ruleId` | string | Sí | Identificador de la regla activada (p. ej. `VELOCITY`, `ATYPICAL_AMOUNT`, `GEO_IMPOSSIBLE`, `RISKY_MERCHANT`). |
| `points` | integer (≥ 0) | Sí | Puntos que la regla aportó al score total. |

> **Resumen, no detalle.** El mensaje transporta únicamente `ruleId` + `points`. El **detalle de
> activación** con los valores observados (monto vs. promedio, distancia y tiempo, etc.) se
> persiste en **Cosmos** junto a la transacción (ISS-S2-009), donde lo consumirá el explicador de
> Semana 3. Mantener el mensaje pequeño evita acoplar la cola al formato del detalle.

El `caseId` **no** viaja en el mensaje: lo genera el consumidor al insertar el caso en PostgreSQL
(ISS-S2-011).

---

## 3. Política de versionado

Los contratos de mensaje son acoplamientos entre módulos desplegados por separado (app y
Function). Se versionan de forma explícita para evolucionar sin romper a los consumidores.

- **Versión en el nombre.** La versión vive en el nombre del esquema y del tipo de mensaje
  (`transaction-event-v1`, `flagged-case-v1`) y, en `transaction-event-v1`, también en el campo
  `schemaVersion`. Un consumidor puede enrutar por versión.
- **Cambios compatibles (no rompen; NO suben la versión mayor):** agregar un campo **opcional**
  (aditivo). Los consumidores existentes deben ignorar campos desconocidos; por eso los esquemas
  declaran `additionalProperties: false` para *validación estricta del productor* mientras el
  consumidor tolera lo aditivo. Un campo nuevo se agrega primero como opcional.
- **Cambios incompatibles (rompen; exigen `-v2`):** renombrar o eliminar un campo, cambiar su
  tipo, o volver obligatorio un campo que antes no existía. Se publica un esquema y record nuevos
  (`...-v2`) y ambas versiones coexisten hasta que todos los consumidores migran.
- **Compatibilidad hacia atrás.** Mientras haya un consumidor en `v1`, el productor no puede dejar
  de emitir `v1`. La retirada de una versión es una decisión explícita, no un efecto colateral.
- **Fuente de verdad.** El **JSON Schema** es autoritativo; el record Java debe seguirlo.
  `EventContractTest` falla si divergen, forzando actualizar ambos lados y la matriz de
  trazabilidad en el mismo cambio.

---

## 4. Validación

```bash
# Prueba de contrato esquema <-> record Java (TEST-S2-005).
mvn -Dtest=EventContractTest test

# Lint opcional de los esquemas JSON.
npx @redocly/cli lint docs/1_Requisitos_y_Contrato/schemas/*.json || true
```

## 5. Trazabilidad

- **Issue:** ISS-S2-004 · **Historia:** HU-S2-003 · **Feature:** FEAT-S2-003
- **Requisitos:** RM-S2-001 (contrato de evento), RM-S2-002 (contrato de caso)
- **Prueba:** TEST-S2-005 (contrato mensajería)
- **Contrato base de transacción:** [`2_Contrato_Transaccion.md`](2_Contrato_Transaccion.md)
