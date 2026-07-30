# [FIX-S2-001] Integrar y cerrar ISS-S2-001 a ISS-S2-011

## Problema

Las issues `ISS-S2-001` a `ISS-S2-011` dejaron componentes aislados funcionales, pero con contratos, tecnologías y modelos incompatibles al conectarlos:

- Cosmos fue aprovisionado con API MongoDB, mientras la Function usaba Cosmos NoSQL.
- La API publicaba `transaction-event-v1`, pero la Function esperaba la transacción completa.
- El scoring calculaba, pero el runtime no persistía ni publicaba el caso.
- Productor, esquema y consumidor de `flagged-case-v1` no coincidían.
- PostgreSQL, entidades JPA y migraciones usaban modelos diferentes.
- El consumidor descartaba el `popReceipt`, por lo que no eliminaba el mensaje real.
- Faltaban permisos, configuración y conexiones de Managed Identity.

## Objetivo

Dejar las issues `ISS-S2-001` a `ISS-S2-011` integrables y alineadas con `docs`, sin implementar todavía la prueba E2E de `ISS-S2-012`.

## Alcance

- Mantener **Cosmos DB for MongoDB**, shard key `accountId`, TTL y acceso privado.
- Consumir el contrato oficial `transaction-event-v1` y leer la transacción mediante `blobPath`.
- Conectar Function → reglas → persistencia de score → publicación en Queue.
- Enrutar `staging` y `production` según el contenedor presente en `blobPath`.
- Usar un solo contrato `flagged-case-v1` entre productor y consumidor.
- Alinear Flyway, JPA, repositorios y auditoría append-only.
- Crear el caso de manera idempotente por `transactionId`.
- Eliminar Queue con `messageId + popReceipt` únicamente después del commit.
- Configurar Function App, Event Grid, Key Vault, RBAC, VNet y app settings.
- Completar la ruta privada del Storage usado por la Function: Blob/Queue existentes y Table para el host.
- Configurar PostgreSQL y JDBC con Managed Identity, sin password versionada.
- Revocar permisos temporales usados para cargar secretos.

## Criterios de aceptación

- [ ] No existe uso de Cosmos NoSQL en `scoring-function`; se usa MongoDB Java Driver.
- [ ] La Function recibe exactamente `transaction-event-v1` y descarga el Blob indicado.
- [ ] La consulta histórica incluye `accountId` y tiempo anterior a `occurredAt`.
- [ ] El score se guarda idempotentemente y solo se publica caso al superar el umbral.
- [ ] Un evento de staging usa Blob/Queue de staging y uno de producción usa los recursos de producción.
- [ ] El mensaje publicado y consumido cumple `flagged-case-v1` sin campos adicionales.
- [ ] Migraciones, entidades JPA y repositorios usan `fraud_case` y `case_audit`.
- [ ] Caso y auditoría se guardan en una misma transacción.
- [ ] Reprocesar `transactionId` no crea un caso duplicado.
- [ ] Queue se elimina con `messageId + popReceipt` después del commit.
- [ ] Cosmos, PostgreSQL y Storage permanecen privados; Key Vault conserva RBAC, soft-delete y purge protection.
- [ ] Function y Web App usan Managed Identity y RBAC de mínimo privilegio.
- [ ] La Function usa identidad administrada, permisos acotados y DNS/Private Endpoints para Blob, Queue y Table.
- [ ] El rol temporal `Key Vault Secrets Officer` se revoca al finalizar.
- [ ] `mvn clean verify` pasa en raíz y `scoring-function`.
- [ ] `bash scripts/tests/validate-week2-integration-fix.sh` pasa.
- [ ] `bash scripts/tests/scan-repository.sh` pasa.
- [ ] Se guardan evidencias reales en `docs/evidence/iss-s2-integration-fix/run-*`.

## Fuera de alcance

- `ISS-S2-012`: script y evidencia del pipeline E2E completo.
- Pruebas de desacoplamiento/umbral de `ISS-S2-013`.
- Reporte de costos y cierre de `ISS-S2-014`.

## Dependencias

Semana 1 desplegada y cuota S1 disponible. Para crear los principales de PostgreSQL, ejecutar el bootstrap desde un runner con conectividad a la VNet.
