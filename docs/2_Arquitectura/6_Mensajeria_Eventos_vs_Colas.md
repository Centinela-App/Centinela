# 6 — Mensajería: eventos vs. colas

## Propósito

Semana 2 introduce **dos mecanismos de mensajería distintos** en el pipeline de detección de
fraude. No son intercambiables: cada uno resuelve un problema diferente. Este documento fija la
distinción como entregable de la célula (ISS-S2-005) para que las piezas encajen y para justificar
por qué existen ambos.

```
                     transaction-event-v1                    flagged-case-v1
   ┌─────────┐   (notifica la ocurrencia)   ┌──────────┐  (garantiza el proceso)  ┌────────────┐
   │   API   │ ───────────────────────────▶ │  Event   │ ─────────┐               │            │
   │ ingesta │      publica y NO espera     │  Grid    │          ▼               │ consumidor │
   └─────────┘                              │  Topic   │     ┌──────────┐          │  de casos  │
        │  1. persiste                      └──────────┘     │ Function │          │(ISS-S2-011)│
        │  2. publica evento                     │ (sub.    │ scoring  │          └────────────┘
        │  3. responde 202                        ISS-S2-007)└──────────┘                ▲
        ▼                                         ▼                │ score >= umbral      │
   raw-transactions (Blob)               lee historial (Cosmos)    ▼                      │
                                                            ┌─────────────────┐           │
                                                            │  Storage Queue  │ ──────────┘
                                                            │  flagged-cases  │   procesa (pull)
                                                            └─────────────────┘
```

## 1. Event Grid Topic — *notificar la ocurrencia*

- **Qué hace:** distribuye el evento `transaction-event-v1` cuando la API termina de persistir una
  transacción. Es un mecanismo **push**, de notificación: "algo ocurrió".
- **Por qué:** desacopla la ingesta del análisis. La API **no** invoca al motor de scoring ni
  espera su resultado; publica el evento y responde `202`. El cliente no paga la latencia del
  análisis (RNF de no-bloqueo).
- **Semántica de entrega:** notificación de ocurrencia. Si no hay suscriptores, el evento no tiene
  a quién notificar; por eso el mecanismo que **garantiza que ningún caso se pierda** es la cola,
  no el tópico.
- **Suscripción:** la suscripción que enlaza la Function **no** se crea en ISS-S2-005; la crea
  quien conecta la Function (ISS-S2-007), para evitar una dependencia circular entre issues.
- **Recurso:** un *custom topic* de Event Grid, nombre determinista `<prefix>-egt-<hash>`.

## 2. Storage Queue de casos — *garantizar el procesamiento*

- **Qué hace:** almacena los mensajes `flagged-case-v1` que la Function encola cuando el score
  supera el umbral. Es un mecanismo **pull**, de trabajo pendiente: "esto debe procesarse".
- **Por qué:** un caso de fraude **no puede perderse**. Si el consumidor está caído o saturado, el
  mensaje permanece en la cola hasta que alguien lo procese. La cola es un **buffer duradero** que
  absorbe indisponibilidad y picos, y habilita reintentos e idempotencia por `transactionId`.
- **Semántica de entrega:** al menos una vez; el consumidor debe ser idempotente (ISS-S2-011).
- **Recursos:** colas dedicadas `flagged-cases-staging` y `flagged-cases-production` en la Storage
  Account de Semana 1.

## 3. La distinción en una frase

> **Event Grid notifica que un evento ocurrió (y la API sigue sin esperar); la cola garantiza que
> un caso marcado se procesará aunque el consumidor esté caído.** Notificación de ocurrencia
> (efímera, push) frente a trabajo pendiente garantizado (duradero, pull).

| Criterio | Event Grid Topic | Storage Queue de casos |
|---|---|---|
| Propósito | Notificar la ocurrencia | Garantizar el procesamiento |
| Patrón | Push (fan-out a suscriptores) | Pull (el consumidor toma el trabajo) |
| Si no hay quien atienda | No hay a quién notificar | El mensaje espera en la cola |
| Acopla | Ingesta → scoring (desacoplado) | Scoring → gestión de casos (desacoplado) |
| Mensaje | `transaction-event-v1` (sin score) | `flagged-case-v1` (con score y reglas) |
| Contrato | `docs/1_Requisitos_y_Contrato/schemas/transaction-event-v1.json` | `.../flagged-case-v1.json` |

## 4. Decisión: colas de casos dedicadas (no reutilizar la de ingesta)

La cola de Semana 1 (`transactions-ingestion-*`) transporta un contrato distinto y tiene otro
propósito (ingesta). Se crean **colas nuevas** `flagged-cases-*` en lugar de reutilizarla para:

- no mezclar dos contratos de mensaje en una misma cola,
- permitir RBAC y métricas independientes por propósito,
- mantener limpio el aislamiento staging/production ya establecido.

## 5. RBAC de mínimo privilegio (mensajería)

| Identidad | Rol | Alcance | Cuándo |
|---|---|---|---|
| Managed Identity de la Web App (prod + slot staging) | `EventGrid Data Sender` | El tópico | ISS-S2-005 (habilita publicar en ISS-S2-006) |
| Identidad de la Function | `Storage Queue Data Message Sender` | Colas `flagged-cases-*` | Al existir la identidad (ISS-S2-007/009) |
| Identidad del consumidor | `Storage Queue Data Message Processor` | Colas `flagged-cases-*` | Al existir la identidad (ISS-S2-011) |

Nunca se asignan `Owner`/`Contributor`/`User Access Administrator` (guard duro en el script). Los
roles de la Function y del consumidor se **difieren** hasta que esas identidades existan, sin
convertir issues futuras en dependencia para cerrar ISS-S2-005.

## 6. Trazabilidad

- **Issue:** ISS-S2-005 · **Historia:** HU-S2-003 · **Feature:** FEAT-S2-003
- **Requisitos:** RM-S2-001, RM-S2-002 · **Prueba:** TEST-S2-006
- **Contratos de mensaje:** [`../1_Requisitos_y_Contrato/4_Contrato_Evento_Transaccion.md`](../1_Requisitos_y_Contrato/4_Contrato_Evento_Transaccion.md)
- **Scripts:** `scripts/provision-eventgrid.sh`, `scripts/tests/validate-eventgrid.sh`
