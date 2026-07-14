# 05 — Modelo de datos de Semana 1

## Transacción

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---:|---|
| `transactionId` | string | Sí | Identificador único de la transacción. |
| `accountId` | string | Sí | Cuenta que origina la operación. |
| `amount` | decimal positivo | Sí | Monto de la operación. |
| `currency` | string de 3 caracteres | Sí | Moneda, por ejemplo `COP`. |
| `occurredAt` | fecha-hora RFC 3339 | Sí | Momento de la operación. |
| `location.countryCode` | string de 2 caracteres | Sí | País de la operación. |
| `location.city` | string | Sí | Ciudad de la operación. |
| `location.latitude` | decimal | No | Coordenada opcional. |
| `location.longitude` | decimal | No | Coordenada opcional. |
| `merchant.name` | string | Sí | Nombre del comercio. |
| `merchant.category` | string | Sí | Categoría del comercio. |

No contiene score, reglas disparadas, decisión ni caso.

> **Nota de decisión (endurecimiento deliberado del contrato).** El enunciado (`0_Vision/2_Alcance_Semana1.md`) exige como mínimo: identificador de transacción, identificador de cuenta, monto, marca de tiempo, ubicación y comercio **o** categoría. Este contrato añade sobre ese mínimo:
> - `currency` como campo **obligatorio** (el enunciado no lo pide) — necesario para interpretar `amount` sin ambigüedad y para la regla de monto atípico de Semana 2.
> - `merchant.name` **y** `merchant.category` ambos obligatorios (el enunciado admite "comercio o categoría") — habilita la regla de comercio/categoría de riesgo de Semana 2.
>
> Ambas son decisiones conscientes de la célula: forman un superconjunto del mínimo y son **compromisos estables**. Cambiarlas en Semana 2 obliga a tocar API, scoring y almacenes a la vez (ver advertencia del enunciado). Cualquier cambio debe actualizarse en paralelo en `openapi-centinela-semana1.yaml`, las pruebas y la matriz de trazabilidad.

## Blob de transacción

- Contenedores: `raw-transactions-staging` y `raw-transactions-production`.
- Ruta: `yyyy/MM/dd/{transactionId}.json`.
- Contenido: JSON original recibido, sin enriquecer con datos de Semana 2.

## Documento

- Contenedores: `verification-documents-staging` y `verification-documents-production`.
- Ruta: `yyyy/MM/dd/{documentId}/{originalFilename}`.
- Metadatos mínimos: `documentId`, nombre original, tipo de contenido, fecha de carga.

No se agrega `caseId` en Semana 1.

## Queue Storage

- Colas: `transactions-ingestion-staging` y `transactions-ingestion-production`.
- En Semana 1 solo se usa un mensaje temporal de conectividad.
- El contrato de negocio de la cola se define en Semana 2.
