# 06 — Contrato API de Semana 1

La fuente ejecutable es `openapi-centinela-semana1.yaml`.

## POST `/api/v1/transactions`

- Actor: Servicio.
- Valida el contrato.
- Guarda el JSON original.
- Devuelve `202` sin análisis.

Respuesta:

```json
{
  "transactionId": "tx-1001",
  "status": "RECEIVED"
}
```

## POST `/api/v1/verification-documents`

- Actor: Analista.
- Entrada: `multipart/form-data` con un campo `file`.
- Guarda el archivo en Blob Storage.
- Devuelve `201`.

Respuesta:

```json
{
  "documentId": "doc-1001",
  "status": "STORED"
}
```

## Decisiones aplazadas

No se publica en OpenAPI ningún endpoint de score, regla, caso, historial o IA. Tampoco se define un endpoint de consumo de cola.
