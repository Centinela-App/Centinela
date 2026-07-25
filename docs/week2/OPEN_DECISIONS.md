# Estado de decisiones técnicas de Semana 2

Este archivo reemplaza la lista heredada de Semana 1. Las decisiones ya tomadas no deben seguir figurando como abiertas.

| Decisión | Estado | Resolución actual |
|---|---|---|
| Persistencia transaccional | RESUELTA | Blob para crudo; Cosmos DB for MongoDB para historial y score; PostgreSQL para casos. |
| Procesamiento asíncrono | RESUELTA | Event Grid para notificar transacciones y Storage Queue para casos. |
| Motor de scoring | RESUELTA | Azure Function Java con cuatro reglas y umbral configurable. |
| Staging/producción | RESUELTA | Web App con slot `staging` y recursos lógicos separados por ambiente. |
| Contratos de eventos | RESUELTA | `transaction-event-v1` y `flagged-case-v1`, con JSON Schema versionado. |
| Consumidor de casos | RESUELTA | Worker de la Web App, idempotente por `transactionId`. |
| Backups y retención | RESUELTA PARCIAL | PostgreSQL administrado y TTL de Cosmos documentados; el cierre de costos corresponde a ISS-S2-014. |
| Multi-región/DR | ABIERTA, FUERA DE S2 | Semana 2 permanece en una región. |
| Observabilidad avanzada | ABIERTA, SEMANA 3 | Application Insights, alertas y dashboards instrumentados. |
| API de consulta | ABIERTA, FUERA DE S2 | Semana 2 no agrega endpoints de lectura. |

Las pruebas E2E y de desacoplamiento no son decisiones: corresponden a `ISS-S2-012` y `ISS-S2-013`.
